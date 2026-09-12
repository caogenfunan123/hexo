// 文章 / 草稿 / 标签页 / 会话扩展（desktop_shell.dart 的 part，与主类同 library，可访问私有成员）。
// 由 desktop_shell.dart 拆分而来（修复1），方法体保持零变更；
// setState 经宿主 _applyState 包装调用。
part of '../desktop_shell.dart';

extension DesktopShellDraftsExt on DesktopShellState {
  Future<void> _restoreSession() async {
    if (_sessionRestored) return;
    _sessionRestored = true;
    try {
      final session = await sessionService.loadSession();
      if (!session.hasArticle || session.isHome) return;
      final article = Article(
        id: session.articleId,
        title: session.articleTitle,
        content: session.articleContent,
        tags: session.articleTags
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        categories: session.articleCategories
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        cover: session.articleCover.isEmpty ? null : session.articleCover,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isDraft: true,
        repoId: session.articleRepoId,
        remotePath: session.articleRemotePath,
        remoteSha: session.articleRemoteSha,
      );
      if (session.pageType == SessionPageType.editor) {
        _openExistingArticle(article);
      }
    } catch (e) {
      debugPrint('Restore session error: $e');
    }
  }

  void _openExistingArticle(Article a) {
    final tabId = 'editor_${a.id}';
    final now = DateTime.now();
    // 300ms 内同一文章重复打开 → 直接忽略（点击防抖）
    if (tabId == _lastOpenGuardKey &&
        now.difference(_lastOpenGuardTime) < const Duration(milliseconds: 300)) {
      return;
    }
    _lastOpenGuardKey = tabId;
    _lastOpenGuardTime = now;

    // 标签已打开：仅切换过去，保留该标签未保存的内容
    final existingIndex = _editor.openTabs.indexWhere((t) => t.id == tabId);
    if (existingIndex >= 0) {
      _switchEditorTab(existingIndex);
      return;
    }

    // 首次打开：建立会话并载入
    // 先保存当前激活标签的未保存会话，避免切走后编辑丢失
    if (_editor.openTabs.isNotEmpty) {
      final currentId = _editor.openTabs[_editor.activeTabIndex].id;
      if (currentId != tabId && _tabSessions.containsKey(currentId)) {
        _saveSessionFromDoc(currentId);
      }
    }
    _tabSessions[tabId] = _EditorTabSession(
      article: a,
      content: a.content,
      title: a.title,
      tags: a.tags.join(', '),
      categories: a.categories.join(', '),
      cover: a.cover ?? '',
      repo: repos.where((r) => r.id == a.repoId).firstOrNull ?? activeRepo,
      lastSavedContent: a.content,
      lastSavedTitle: a.title,
      articleType: a.articleType,
      templateId: a.templateId,
      splitMode: _splitEditorMode,
      splitRatio: _splitEditorRatio,
    );
    _loadSessionIntoDoc(tabId);
    _startAutoSave();
    _addEditorTab(a);

    // 自动聚焦到正文编辑区
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _doc.contentFocus.requestFocus();
    });
  }

  void _saveSessionFromDoc(String tabId) {
    final s = _tabSessions[tabId];
    if (s == null) return;
    s.article = _doc.currentArticle;
    s.title = _doc.titleCtrl.text;
    s.content = _doc.contentCtrl.text;
    s.tags = _doc.tagsCtrl.text;
    s.categories = _doc.categoriesCtrl.text;
    s.cover = _doc.coverCtrl.text;
    s.repo = _editorRepo;
    s.lastSavedContent = _lastSavedContent;
    s.lastSavedTitle = _lastSavedTitle;
    s.showEditorMeta = _showEditorMeta;
    s.articleType = _doc.articleType;
    s.templateId = _doc.selectedTemplateId;
    s.splitMode = _splitEditorMode;
    s.splitRatio = _splitEditorRatio;
  }

  void _loadSessionIntoDoc(String tabId) {
    final s = _tabSessions[tabId];
    if (s == null) return;
    // 载入会话期间抑制标签标题回写，避免误改其它标签
    _loadingSession = true;
    try {
      _doc.setCurrentArticle(s.article);
      _doc.titleCtrl.text = s.title;
      _doc.contentCtrl.text = s.content;
      _doc.tagsCtrl.text = s.tags;
      _doc.categoriesCtrl.text = s.categories;
      _doc.coverCtrl.text = s.cover;
      _editorRepo = s.repo ?? activeRepo;
      // setCurrentArticle 会用 article 内的旧值覆盖类型/模板，需用会话中保存的值还原
      _doc.setArticleType(s.articleType);
      _doc.setSelectedTemplateId(s.templateId);
      _doc.setEditorRepoId(_editorRepo?.id);
      _splitEditorMode = s.splitMode;
      _splitEditorRatio = s.splitRatio;
      _lastSavedContent = s.lastSavedContent;
      _lastSavedTitle = s.lastSavedTitle;
      _showEditorMeta = s.showEditorMeta;
      _lastSavedContentMap[s.article.id] = s.lastSavedContent;
      _lastSavedTitleMap[s.article.id] = s.lastSavedTitle;
      _lastCursorLine = 0;
      _focusCursorLine.value = 1;
      if (s.content == s.lastSavedContent && s.title == s.lastSavedTitle) {
        _doc.markSaved();
      } else {
        _doc.markUnsaved();
      }
    } finally {
      _loadingSession = false;
    }
    _onContentChanged();
  }

  void _switchEditorTab(int index) {
    final tabs = _editor.openTabs;
    if (index < 0 || index >= tabs.length) return;
    if (tabs.isEmpty || _editor.activeTabIndex >= tabs.length) return;
    final currentId = tabs[_editor.activeTabIndex].id;
    final nextId = tabs[index].id;
    if (currentId == nextId) return;
    _saveSessionFromDoc(currentId);
    _editor.switchTab(index);
    _loadSessionIntoDoc(nextId);
    // 元数据折叠状态由本 State 持有且位于 _editor 监听范围之外，
    // 需显式重建，保证切换标签后抽屉展开状态与目标标签一致
    if (mounted) _applyState(() {});
  }

  Future<void> _deleteDraft(Article a) async {
    // 先移入回收站
    try {
      final dir = await storage.mdArticlesDir();
      final filePath = '${dir.path}/${a.id}_${a.fileName()}';
      await recycleBinService.moveToTrash(filePath, a);
    } catch (e) {
      debugPrint('Shell: moveToTrash failed: $e');
    }
    drafts.removeWhere((e) => e.id == a.id);
    await storage.saveDrafts(drafts);
    logService.add('删除草稿', '标题: ${a.title.isNotEmpty ? a.title : "(无标题)"}');
    if (mounted) _applyState(() {});
  }

  Future<void> _renameArticle(Article a) async {
    final ctrl = TextEditingController(text: a.title);
    try {
      final newTitle = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('重命名文章'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '新标题',
              hintText: '输入新的文章标题',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      if (newTitle == null || newTitle.isEmpty || newTitle == a.title) return;
      final idx = drafts.indexWhere((e) => e.id == a.id);
      if (idx < 0) return;
      final updated = drafts[idx].copyWith(
        title: newTitle,
        updatedAt: DateTime.now(),
      );
      _applyState(() => drafts[idx] = updated);
      await storage.saveDrafts(drafts);
      await storage.exportDraftMarkdown(updated);
      logService.add('重命名文章', '「${a.title}」→「$newTitle」');
      if (mounted) _showToast('已重命名为「$newTitle」');
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _moveArticleVolume(Article a) async {
    final volumes = <String>{};
    for (final d in drafts) {
      final v = d.volume?.trim();
      if (v != null && v.isNotEmpty) volumes.add(v);
    }
    final volList = volumes.toList()..sort();

    String? current = a.volume?.trim();
    String? selected = current;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final isNew = selected != null && !volList.contains(selected);
          final ctrl = TextEditingController(text: isNew ? selected! : '');
          return AlertDialog(
            title: const Text('移动到卷宗'),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '选择目标卷宗：',
                    style: TextStyle(
                        fontSize: 13, color: AppColor.textMuted(context)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('未分类'),
                        selected: selected == null || selected!.isEmpty,
                        onSelected: (_) => setDlgState(() => selected = null),
                      ),
                      ...volList.map(
                        (v) => ChoiceChip(
                          label: Text(v),
                          selected: selected == v,
                          onSelected: (_) => setDlgState(() => selected = v),
                        ),
                      ),
                      ChoiceChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: const Text('新建卷宗'),
                        selected: isNew,
                        onSelected: (_) => setDlgState(() => selected = ''),
                      ),
                    ],
                  ),
                  if (isNew) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: '卷宗名称',
                        hintText: '输入新卷宗名称',
                      ),
                      onChanged: (v) => setDlgState(() => selected = v.trim()),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final v = (selected == null || selected!.isEmpty)
                      ? null
                      : selected;
                  Navigator.pop(ctx, v);
                },
                child: const Text('确定'),
              ),
            ],
          );
        },
      ),
    );

    if (result == null) return;
    final idx = drafts.indexWhere((e) => e.id == a.id);
    if (idx < 0) return;
    final updated = drafts[idx].copyWith(
      volume: result.isEmpty ? null : result,
      updatedAt: DateTime.now(),
    );
    _applyState(() => drafts[idx] = updated);
    await storage.saveDrafts(drafts);
    await storage.exportDraftMarkdown(updated);
    logService.add('移动卷宗', '「${a.title}」→ ${result.isEmpty ? '未分类' : result}');
    if (mounted) _showToast('已移动到 ${result.isEmpty ? '未分类' : result}');
  }

  Future<void> _exportArticle(Article a) async {
    try {
      await storage.exportDraftMarkdown(a);
      final dir = await storage.draftsDir();
      logService.add('导出文章', '标题: ${a.title.isNotEmpty ? a.title : "(无标题)"}');
      if (mounted) _showToast('已导出到 ${dir.path}');
    } catch (e) {
      if (mounted) _showToast('导出失败: $e');
    }
  }

  Future<void> _refreshDraftsFromStorage() async {
    final d = await storage.loadDrafts();
    d.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (mounted) {
      _applyState(() => drafts = d);
    }
  }

  void _newArticle([String? volume]) {
    final repo = activeRepo;
    _editorRepo = repo;
    _doc.setArticleType(ArticleType.post);
    String? autoTemplateId;
    if (repo != null)
      autoTemplateId = TemplateResolver.resolvePostTemplateId(repo, templates);
    // 覆盖 _doc 前先保存当前激活标签的未保存会话，避免切换标签时内容丢失
    if (_editor.openTabs.isNotEmpty &&
        _editor.activeTabIndex < _editor.openTabs.length) {
      _saveSessionFromDoc(_editor.openTabs[_editor.activeTabIndex].id);
    }
    _doc.setCurrentArticle(
      Article(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: '',
        content: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isDraft: true,
        repoId: repo?.id,
        articleType: _doc.articleType,
        templateId: autoTemplateId,
        volume: (volume == null || volume.isEmpty) ? null : volume,
      ),
    );
    _doc.titleCtrl.text = '';
    _doc.contentCtrl.text = '';
    _doc.tagsCtrl.text = '';
    _doc.categoriesCtrl.text = '';
    _doc.coverCtrl.text = '';
    _lastSavedContent = '';
    _lastSavedTitle = '';
    _lastSavedContentMap[_doc.currentArticle.id] = '';
    _lastSavedTitleMap[_doc.currentArticle.id] = '';
    _lastCursorLine = 0;
    _focusCursorLine.value = 1;
    _doc.markSaved();
    _doc.setSelectedTemplateId(autoTemplateId);
    _startAutoSave();
    _tabSessions['editor_${_doc.currentArticle.id}'] = _EditorTabSession(
      article: _doc.currentArticle,
      content: '',
      title: '',
      tags: '',
      categories: '',
      cover: '',
      repo: repo,
      lastSavedContent: '',
      lastSavedTitle: '',
    );
    _addEditorTab(_doc.currentArticle);

    // 新文章默认进入极简写作模式（对齐手机端清爽体验）
    _switchWorkMode(WorkMode.focus);

    // 自动聚焦到正文编辑区（光标定位到开头）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _doc.contentFocus.requestFocus();
    });
  }

  void _addEditorTab(Article article) {
    final tabId = 'editor_${article.id}';
    _editor.addTab(
      EditorTab(
        id: tabId,
        title: article.title.isNotEmpty ? article.title : '未命名',
        icon: Icons.edit_note,
        contentBuilder: (_) => _buildEmbeddedEditor(),
        canClose: true,
      ),
    );
  }

  void _openTab(String id, String title, IconData icon, Widget content) {
    _editor.addTab(
      EditorTab(
        id: id,
        title: title,
        icon: icon,
        contentBuilder: (_) => content,
        canClose: true,
      ),
    );
  }

  void _closeTab(int index) {
    final tabs = _editor.openTabs;
    if (tabs.length <= 1) {
      // 关闭最后一个标签：清理会话与文档状态，进入空态
      _tabSessions.clear();
      _debounceTimers.forEach((_, t) => t.cancel());
      _debounceTimers.clear();
      _pendingSaveMap.clear();
      _lastSavedContentMap.clear();
      _lastSavedTitleMap.clear();
      _editor.closeAllTabs();
      _doc.titleCtrl.text = '';
      _doc.contentCtrl.text = '';
      _doc.tagsCtrl.text = '';
      _doc.categoriesCtrl.text = '';
      _doc.coverCtrl.text = '';
      _lastSavedContent = '';
      _lastSavedTitle = '';
      _doc.markSaved();
      return;
    }
    if (index < 0 || index >= tabs.length) return;
    final closingId = tabs[index].id;
    final isClosingActive = _editor.activeTabIndex == index;
    // 关闭的是当前激活标签：先把未保存内容收回会话，避免丢失
    if (isClosingActive) {
      _saveSessionFromDoc(closingId);
    }
    _tabSessions.remove(closingId);
    _editor.closeTab(index);
    // 仅关闭激活标签时才需载入新的激活标签会话；
    // 关闭非激活标签会保留当前激活标签的实时未保存编辑，不得覆盖
    if (isClosingActive) {
      final remaining = _editor.openTabs;
      if (remaining.isNotEmpty && _editor.activeTabIndex < remaining.length) {
        _loadSessionIntoDoc(remaining[_editor.activeTabIndex].id);
      }
    }
  }
}
