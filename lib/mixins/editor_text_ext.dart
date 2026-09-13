// 编辑器文本操作扩展（由 main.dart part 引入，与原类同 library，可访问私有成员）
part of '../main.dart';

extension EditorTextExt on _RootShellState {
  /// 新建空白文章：先将当前文章存到草稿箱，再清空编辑器
  Future<void> _newBlankArticle() async {
    // 当前有内容时先保存到草稿箱
    final hasContent =
        _doc.titleCtrl.text.isNotEmpty || _doc.contentCtrl.text.isNotEmpty;
    if (hasContent) {
      await _saveLocal();
    }
    _stopAutoSave();
    await _clearSession();
    _resetEditor();
    _startAutoSave();
    if (mounted) {
      _showToast(hasContent ? '已保存到草稿箱，开始新文章' : '开始写新文章');
    }
  }

  /// 根据当前文章类型和仓库配置自动选择模板
  void _autoSelectTemplate() {
    final repo = _editorRepo;
    if (repo == null) return;
    _doc.setSelectedTemplateId(
      _doc.articleType == ArticleType.post
          ? TemplateResolver.resolvePostTemplateId(repo, templates)
          : TemplateResolver.resolvePageTemplateId(repo, templates),
    );
  }

  void _startAutoSave() {
    _stopAutoSave();
    // 种子化当前文章的"上次保存标题"，供标题-only 改动正确判定未保存
    _lastSavedTitleMap[_doc.currentArticle.id] = _doc.titleCtrl.text;
    if (!settings.autoSaveEnabled) return;
    _autoSaveTimer = Timer.periodic(
      Duration(seconds: settings.autoSaveIntervalSeconds),
      (_) {
        // 定时自动保存：仅保存当前文章，防止串草稿
        final current = _doc.contentCtrl.text;
        _autoSaveSnapshot(
          articleId: _doc.currentArticle.id,
          content: current,
          title: _doc.titleCtrl.text,
        );
      },
    );
  }

  void _stopAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    _flushAllPendingSaves();
  }

  void _onContentChanged() {
    final current = _doc.contentCtrl.text;
    final title = _doc.titleCtrl.text;
    _editor.updateStats(current);
    // 正文或标题任一变化都视为未保存，避免标题-only 改动被忽略
    final articleId = _doc.currentArticle.id;
    if (current == _doc.lastSavedContent &&
        title == _lastSavedTitleMap[articleId]) {
      _doc.markSaved();
      return;
    }
    _doc.markUnsaved();
    // 每草稿独立防抖，杜绝多草稿相互阻塞。
    // 元数据在触发时捕获（对齐桌面端）：切文章后定时器到点不会把
    // 新文章的 tags/categories/cover 写进旧文章快照
    _debounceTimers[articleId]?.cancel();
    _debounceTimers[articleId] = _DebounceEntry(
      content: current,
      title: title,
      tags: _doc.tagsCtrl.text,
      categories: _doc.categoriesCtrl.text,
      cover: _doc.coverCtrl.text,
      timer: Timer(const Duration(seconds: 2), () {
        final entry = _debounceTimers.remove(articleId);
        if (entry == null) return;
        // 已切走文章也必须保存：用调度时捕获的内容与元数据落快照，
        // 串草稿/防降级由 _autoSaveSnapshot 的 isCurrent 守卫保证，
        // 直接 return 会把该窗口编辑静默丢弃（flush 也救不回）
        _autoSaveSnapshot(
          articleId: articleId,
          content: entry.content,
          title: entry.title,
          tags: entry.tags,
          categories: entry.categories,
          cover: entry.cover,
        );
      }),
    );
  }

  Future<void> _autoSaveSnapshot({
    required String articleId,
    required String content,
    String title = '',
    String? tags,
    String? categories,
    String? cover,
  }) async {
    // 正文与标题都未变化（或均为空）时无需保存，标题-only 改动必须落盘
    if ((content.isEmpty && title.isEmpty) ||
        (content == _lastSavedContentMap[articleId] &&
            title == _lastSavedTitleMap[articleId])) {
      return;
    }
    // 保存时应以文档当前最新状态为准，但防止串草稿：
    // 仅当用户当前仍在此文章时才标记 saved
    final isCurrent = _doc.currentArticle.id == articleId;
    try {
      await sessionService.saveAutoSnapshot(
        articleId: articleId,
        content: content,
        title: title.isEmpty ? '未命名' : title,
        // 传入捕获的元数据；为空时回退当前控制器（仅当前文章场景）
        tags: tags ?? _doc.tagsCtrl.text,
        categories: categories ?? _doc.categoriesCtrl.text,
        cover: cover ?? _doc.coverCtrl.text,
      );
      _lastSavedContentMap[articleId] = content;
      _lastSavedTitleMap[articleId] = title;
      // await 窗口内可能已切走文章，markSaved 只对仍停留的文章生效
      if (_doc.currentArticle.id == articleId) _doc.markSaved();
      await sessionService.cleanupSnapshots(articleId);
      // 草稿落盘仅限当前文章（非当前文章绝不 _collect，防串草稿/防降级）
      if (isCurrent && _doc.contentCtrl.text == content) {
        final currentArticle = _doc.currentArticle;
        await _saveDraft(
          _collect(draft: true).copyWith(
            isDraft: currentArticle.isDraft,
            published: currentArticle.published,
          ),
        );
      }
      // 静默保存：保存状态由 AppBar/状态栏指示反馈，成功不再弹 toast
    } catch (e) {
      debugPrint('Auto save snapshot error: $e');
      // 失败必须用户可见（此前仅 debugPrint，静默丢保存）
      if (mounted) {
        _showToast('自动保存失败: $e');
      }
    }
  }

  Future<void> _openReader(Article article) async {
    // 切文章前先拉回 WebView 内未回写的输入，落进当前文章的防抖表
    await _flushWebViewMarkdown();
    _doc.setCurrentArticle(article);
    _saveSession(SessionPageType.reader);
    _applyState(() => _currentPage = 9); // 阅读页
    _updateSystemBarStyle();
  }

  void _enterEditorFromReader(Article article) {
    _doc.setCurrentArticle(article);
    _editorRepo =
        repos.where((r) => r.id == article.repoId).firstOrNull ?? activeRepo;
    _doc.setEditorRepoId(_editorRepo?.id);
    _startAutoSave();
    _saveSession(SessionPageType.editor);
    _applyState(() => _currentPage = 0); // 回到编辑器
    _updateSystemBarStyle();
  }

  void _insertText(String t) {
    final sel = _doc.contentCtrl.selection;
    final txt = _doc.contentCtrl.text;
    final s = sel.isValid ? sel.start : txt.length;
    final e = sel.isValid ? sel.end : txt.length;
    _doc.contentCtrl.value = TextEditingValue(
      text: txt.replaceRange(s, e, t),
      selection: TextSelection.collapsed(offset: s + t.length),
    );
    _doc.contentFocus.requestFocus();
    _onContentChanged();
  }

  void _wrap(String l, String r, {String p = ''}) {
    final sel = _doc.contentCtrl.selection;
    final txt = _doc.contentCtrl.text;
    if (!sel.isValid || sel.start == sel.end) {
      final body = p.isEmpty ? '' : p;
      final ins = '$l$body$r';
      final s = sel.isValid ? sel.start : txt.length;
      _doc.contentCtrl.value = TextEditingValue(
        text: txt.replaceRange(s, s, ins),
        selection: TextSelection.collapsed(offset: s + l.length + body.length),
      );
      _doc.contentFocus.requestFocus();
      _onContentChanged();
      return;
    }
    final sel2 = txt.substring(sel.start, sel.end);
    _doc.contentCtrl.value = TextEditingValue(
      text: txt.replaceRange(sel.start, sel.end, '$l$sel2$r'),
      selection: TextSelection.collapsed(
        offset: sel.start + l.length + sel2.length,
      ),
    );
    _doc.contentFocus.requestFocus();
    _onContentChanged();
  }

  void _insertHeading(int level) {
    final prefix = '${'#' * level} ';
    final txt = _doc.contentCtrl.text;
    final s = _doc.contentCtrl.selection.isValid
        ? _doc.contentCtrl.selection.start
        : txt.length;
    final lineStart = txt.lastIndexOf('\n', s - 1) + 1;
    _doc.contentCtrl.value = TextEditingValue(
      text: txt.replaceRange(lineStart, lineStart, prefix),
      selection: TextSelection.collapsed(offset: s + prefix.length),
    );
    _doc.contentFocus.requestFocus();
    _onContentChanged();
  }

  void _insertList(String marker) {
    final sel = _doc.contentCtrl.selection;
    if (sel.isValid && sel.start != sel.end) {
      final selected = _doc.contentCtrl.text.substring(sel.start, sel.end);
      final lines = selected
          .split('\n')
          .map((l) => l.isEmpty ? l : '$marker$l')
          .join('\n');
      final txt = _doc.contentCtrl.text;
      _doc.contentCtrl.value = TextEditingValue(
        text: txt.replaceRange(sel.start, sel.end, lines),
        selection: TextSelection.collapsed(offset: sel.start + lines.length),
      );
      _doc.contentFocus.requestFocus();
      _onContentChanged();
      return;
    }
    _insertText('\n$marker');
  }

  void _insertCodeBlock() {
    final sel = _doc.contentCtrl.selection;
    final txt = _doc.contentCtrl.text;
    final selected = (sel.isValid && sel.start != sel.end)
        ? txt.substring(sel.start, sel.end)
        : '';
    final fence = '```\n$selected\n```\n';
    final s = sel.isValid ? sel.start : txt.length;
    final e = sel.isValid ? sel.end : txt.length;
    _doc.contentCtrl.value = TextEditingValue(
      text: txt.replaceRange(s, e, fence),
      selection: TextSelection.collapsed(offset: s + 4),
    );
    _doc.contentFocus.requestFocus();
    _onContentChanged();
  }

}
