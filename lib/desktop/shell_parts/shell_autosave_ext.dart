// 自动保存 / 内容变更跟踪扩展（desktop_shell.dart 的 part，与主类同 library，可访问私有成员）。
// 由 desktop_shell.dart 拆分而来（修复1），方法体保持零变更；
// setState 经宿主 _applyState 包装调用。
part of '../desktop_shell.dart';

extension DesktopShellAutosaveExt on DesktopShellState {
  void _startAutoSave() {
    _stopAutoSave();
    if (!settings.autoSaveEnabled) return;
    _autoSaveTimer = Timer.periodic(
      Duration(seconds: settings.autoSaveIntervalSeconds),
      (_) => _autoSaveSnapshot(),
    );
  }

  void _stopAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    _flushAllPendingSaves();
    for (final t in _debounceTimers.values) {
      t.cancel();
    }
    _debounceTimers.clear();
  }

  List<Future<void>> _flushAllPendingSaves() {
    final futures = <Future<void>>[];
    final saved = <String>{};
    // 1) 仍在排队中的防抖任务：立即取消并按调度时捕获的数据保存
    //    （数据在 _pendingSaveMap，裸 Timer 闭包里的内容 flush 拿不到）
    for (final entry in _debounceTimers.entries) {
      entry.value.cancel();
      final pending = _pendingSaveMap[entry.key];
      if (pending != null && pending.content.isNotEmpty) {
        saved.add(entry.key);
        futures.add(_autoSaveSnapshot(
          articleId: pending.articleId,
          content: pending.content,
          title: pending.title,
          tags: pending.tags,
          categories: pending.categories,
          cover: pending.cover,
          force: true,
        ));
      }
    }
    _debounceTimers.clear();
    // 2) 已切走文章挂起在 pending 中的内容：真正落盘（去重防二次保存）
    for (final pending in _pendingSaveMap.values) {
      if (saved.contains(pending.articleId)) continue;
      if (pending.content.isNotEmpty) {
        futures.add(_autoSaveSnapshot(
          articleId: pending.articleId,
          content: pending.content,
          title: pending.title,
          tags: pending.tags,
          categories: pending.categories,
          cover: pending.cover,
          force: true,
        ));
      }
    }
    _pendingSaveMap.clear();
    return futures;
  }

  void _onTitleChanged() {
    if (_loadingSession) return;
    if (_editor.openTabs.isEmpty) return;
    if (_editor.activeTabIndex >= _editor.openTabs.length) return;
    final tabId = _editor.openTabs[_editor.activeTabIndex].id;
    final title = _doc.titleCtrl.text.trim();
    _editor.updateTabTitle(tabId, title.isEmpty ? '未命名' : title);
  }

  void _onContentChanged() {
    final current = _doc.contentCtrl.text;
    final title = _doc.titleCtrl.text;
    final articleId = _doc.currentArticle.id;
    // 元数据（标签/分类/封面）变化同样视为未保存，不能仅比较正文+标题
    final metaChanged =
        _doc.tagsCtrl.text != _doc.currentArticle.tags.join(', ') ||
            _doc.categoriesCtrl.text !=
                _doc.currentArticle.categories.join(', ') ||
            _doc.coverCtrl.text != (_doc.currentArticle.cover ?? '');
    if (current == _lastSavedContentMap[articleId] &&
        title == _lastSavedTitleMap[articleId] &&
        !metaChanged) {
      _doc.markSaved();
      return;
    }
    _doc.markUnsaved();
    _trackStats();
    // 更新打字机光标位置
    final cursorPos = _doc.contentCtrl.selection.baseOffset;
    final textBefore = current.substring(0, cursorPos.clamp(0, current.length));
    final currentLine = '\n'.allMatches(textBefore).length;
    final totalLines = '\n'.allMatches(current).length + 1;
    _typewriterCtrl.updateCursorPosition(currentLine, totalLines);
    // 每草稿独立防抖，杜绝多草稿相互阻塞
    _debounceTimers[articleId]?.cancel();
    // 内容与元数据在调度时一并捕获进 _pendingSaveMap（对齐手机端）：
    // 触发时无论是否已切走文章，用的都是当时的值，不会把新文章的
    // tags/categories/cover 写进旧文章，也不会丢捕获窗口内的编辑
    _pendingSaveMap[articleId] = _PendingSave(
      articleId: articleId,
      content: current,
      title: title,
      tags: _doc.tagsCtrl.text,
      categories: _doc.categoriesCtrl.text,
      cover: _doc.coverCtrl.text,
    );
    _debounceTimers[articleId] = Timer(const Duration(seconds: 2), () {
      _debounceTimers.remove(articleId);
      final pending = _pendingSaveMap.remove(articleId);
      if (pending == null) return;
      if (_doc.currentArticle.id != articleId) {
        // 已切走：留在 pendingMap，由 _flushAllPendingSaves 兜底落盘
        _pendingSaveMap[articleId] = pending;
        return;
      }
      _autoSaveSnapshot(
        articleId: articleId,
        content: pending.content,
        title: pending.title,
        tags: pending.tags,
        categories: pending.categories,
        cover: pending.cover,
      );
      // 元数据（标签/分类/封面）变化也要落盘：content/title 未变时 force 保存
      final metaChangedNow =
          _doc.tagsCtrl.text != _doc.currentArticle.tags.join(', ') ||
              _doc.categoriesCtrl.text !=
                  _doc.currentArticle.categories.join(', ') ||
              _doc.coverCtrl.text != (_doc.currentArticle.cover ?? '');
      if (metaChangedNow) {
        _autoSaveSnapshot(
          articleId: articleId,
          content: current,
          title: title,
          force: true,
        );
      }
      // 仍是当前文章的后台快照保存，主动刷新保存状态栏
      if (current == _doc.contentCtrl.text && title == _doc.titleCtrl.text) {
        _doc.markSaved();
      }
    });
  }

  void _trackStats() {
    final text = _doc.contentCtrl.text;
    _editor.updateStats(text);
    final sel = _doc.contentCtrl.selection;
    final totalLines = '\n'.allMatches(text).length + 1;
    if (sel.isValid) {
      final before = text.substring(0, sel.start);
      final line = '\n'.allMatches(before).length + 1;
      final lastNewline = before.lastIndexOf('\n');
      final col = lastNewline < 0 ? sel.start + 1 : sel.start - lastNewline;
      _editor.updateCursorPosition(line, col, totalLines: totalLines);

      // 打字机滚动：专注模式下光标始终在屏幕中间
      if (_layout.workMode == WorkMode.focus && line != _lastCursorLine) {
        _lastCursorLine = line;
        _focusCursorLine.value = line;
        _centerCursorInFocusMode(line);
      }
    }
    // 状态栏通过 ListenableBuilder 监听 _editor/_doc 自刷新，无需整壳 setState
  }

  void _onCursorSelectionChanged() {
    if (_layout.workMode != WorkMode.focus) return;
    final text = _doc.contentCtrl.text;
    final sel = _doc.contentCtrl.selection;
    if (!sel.isValid) return;
    final before = text.substring(0, sel.start.clamp(0, text.length));
    final line = '\n'.allMatches(before).length + 1;
    if (line != _lastCursorLine) {
      _lastCursorLine = line;
      _focusCursorLine.value = line;
      _centerCursorInFocusMode(line);
    }
  }

  void _centerCursorInFocusMode(int line) {
    if (!_focusScrollCtrl.hasClients) return;
    final lineHeight = _editor.editorFontSize * _editor.editorLineHeight;
    final viewportHeight = _focusScrollCtrl.position.viewportDimension;
    final targetY =
        DesktopShellState._focusHeaderOffset + (line - 1) * lineHeight - viewportHeight / 2 + lineHeight;
    if (targetY < 0) return;
    _focusScrollCtrl.animateTo(
      targetY.clamp(0, _focusScrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  Future<void> _autoSaveSnapshot({
    String? articleId,
    String? content,
    String? title,
    String? tags,
    String? categories,
    String? cover,
    bool force = false,
  }) async {
    final aid = articleId ?? _doc.currentArticle.id;
    final c = content ?? _doc.contentCtrl.text;
    final t = title ?? _doc.titleCtrl.text;
    final prevC = _lastSavedContentMap[aid];
    final prevT = _lastSavedTitleMap[aid];
    if (!force &&
        ((c.isEmpty && t.isEmpty) || (c == prevC && t == prevT))) {
      return;
    }
    try {
      await sessionService.saveAutoSnapshot(
        articleId: aid,
        content: c,
        title: t.isEmpty ? '未命名' : t,
        // 传入捕获的元数据；为空时回退到当前控制器，避免把别的文章元数据写到目标文章
        tags: tags ?? _doc.tagsCtrl.text,
        categories: categories ?? _doc.categoriesCtrl.text,
        cover: cover ?? _doc.coverCtrl.text,
      );
      _lastSavedContentMap[aid] = c;
      _lastSavedTitleMap[aid] = t;
      // 全局镜像只反映当前激活文章，后台保存其他文章时不得覆盖
      if (aid == _doc.currentArticle.id) {
        _lastSavedContent = c;
        _lastSavedTitle = t;
      }
      // await 窗口内可能已切走文章，markSaved 只对仍停留的文章生效
      if (_doc.currentArticle.id == aid) {
        _doc.markSaved();
      }
      await sessionService.cleanupSnapshots(aid);
      // 仅当保存的是当前激活文章且内容一致时才落草稿，避免后台保存污染其他文章
      if (aid == _doc.currentArticle.id && _doc.contentCtrl.text == c) {
        final currentArticle = _doc.currentArticle;
        await _saveDraft(
          _collect(draft: true).copyWith(
            isDraft: currentArticle.isDraft,
            published: currentArticle.published,
          ),
        );
      }
      // 静默保存：状态栏「已保存」指示灯即反馈，成功不再弹 toast
    } catch (e) {
      debugPrint('AutoSave snapshot error: $e');
      // 失败必须用户可见：写入编辑器状态（状态栏/工作台状态行常驻显示）并弹提示，
      // 未保存指示灯（状态栏黄点）会继续保持，直到下次保存成功
      _editor.setEditorStatus('自动保存失败：$e（内容仍在，稍后自动重试或 Ctrl+S 手动保存）');
      if (mounted) _showToast('自动保存失败，请检查磁盘后手动存草稿');
    }
  }
}
