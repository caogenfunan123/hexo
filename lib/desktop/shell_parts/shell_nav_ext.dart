// 导航 / 文件打开 / 布局开关扩展（desktop_shell.dart 的 part，与主类同 library，可访问私有成员）。
// 由 desktop_shell.dart 拆分而来（修复1），方法体保持零变更；
// setState 经宿主 _applyState 包装调用。
part of '../desktop_shell.dart';

extension DesktopShellNavExt on DesktopShellState {
  void _setAsRepoDefault(String templateId) {
    if (_editorRepo == null) return;
    final updated = _editorRepo!.copyWith(defaultPostTemplateId: templateId);
    final idx = repos.indexWhere((r) => r.id == _editorRepo!.id);
    if (idx >= 0) {
      repos[idx] = updated;
      storage.saveRepos(repos);
      _editorRepo = updated;

      _showToast('已设为仓库默认模板');
    }
  }

  void _openHome() {
    _openTab(
      'home',
      '首页',
      Icons.home_outlined,
      HomeScreen(
        articles: drafts,
        onOpenArticle: (a) => _openExistingArticle(a),
        onNewArticle: _newArticle,
        onNewArticleInVolume: _newArticle,
        onRenameArticle: _renameArticle,
        onMoveArticleVolume: _moveArticleVolume,
        onExportArticle: _exportArticle,
        onDeleteArticle: _deleteDraft,
      ),
    );
  }

  void _openDrafts() {
    _openTab(
      'drafts',
      '草稿箱',
      Icons.drafts_outlined,
      DraftsScreen(
        drafts: drafts,
        repos: repos,
        blogSiteConfigs: settings.blogSiteConfigs,
        onOpen: (a) => _openExistingArticle(a),
        onDelete: _deleteDraft,
      ),
    );
  }

  void _openDashboard() {
    _openTab(
      'dashboard',
      '仪表盘',
      Icons.dashboard_outlined,
      DashboardScreen(
        drafts: drafts,
        remotePosts: remotePosts,
        commits: commits,
        settings: settings,
        activeRepo: activeRepo,
        onNewPost: _newArticle,
        onNavigateToRemote: _openRemote,
        onNavigateToHistory: _openHistory,
        onNavigateToSettings: _openSettings,
        onNavigateToPreview: _openPreview,
        onNavigateToDrafts: _openDrafts,
      ),
    );
  }

  void _openHistory() {
    _openTab(
      'history',
      '提交历史',
      Icons.history_outlined,
      HistoryScreen(
        commits: commits,
        github: github,
        effectiveRepo: effectiveRepo,
        onRefresh: _refreshCommits,
        onCommitTap: (commit) {},
      ),
    );
  }

  void _openRss() {
    _openTab(
      'rss',
      'RSS 订阅',
      Icons.rss_feed_outlined,
      RssScreen(
        items: rssItems,
        activeRepo: activeRepo,
        onRefresh: _refreshRss,
      ),
    );
  }

  void _openBatchUpload() {
    _openTab(
      'batch_upload',
      '批量上传',
      Icons.drive_folder_upload,
      FolderUploadScreen(
        repos: repos,
        github: github,
        activeRepo: effectiveRepo,
      ),
    );
  }

  void _openPreview() {
    // flutter_inappwebview 不支持 Linux，回退到系统浏览器
    if (Platform.isLinux) {
      _openPreviewExternal();
      return;
    }
    _openTab(
      'preview',
      '网站预览',
      Icons.language,
      PreviewScreen(
        activeRepo: activeRepo,
        sitePreviewUrl: settings.sitePreviewUrl,
      ),
    );
  }

  void _openPreviewExternal() {
    final url = settings.sitePreviewUrl.isNotEmpty
        ? settings.sitePreviewUrl
        : (activeRepo?.siteUrl.isNotEmpty == true ? activeRepo!.siteUrl : '');
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      _showToast('无法打开浏览器：无效的网址');
      return;
    }
    try {
      launchUrl(uri, mode: LaunchMode.externalApplication);
      _showToast('已在浏览器中打开: $url');
    } catch (e) {
      _showToast('无法打开浏览器: $e');
    }
  }

  void _openSettings() {
    _openTab(
      'settings',
      '设置',
      Icons.settings_outlined,
      SettingsScreen(
        settings: settings,
        repos: repos,
        github: github,
        storage: storage,
        webdavService: webdavService,
        onSettingsChanged: _updateSettings,
        onReposChanged: _updateRepos,
        onShowWebDavDialog: _showWebDavDialog,
        onSyncWebDavToLocal: _syncWebDavToLocal,
        onSyncDraftsToWebDav: _syncDraftsToWebDav,
        onShowAiManager: _showAiManager,
        onShowGithubTokenManager: _showGithubTokenManager,
        onShowRepoManager: _showRepoManager,
        onShowSiteEditor: _showSiteEditor,
        onShowThemeColorPicker: _showThemeColorPicker,
        onShowPwaGuide: _showPwaGuide,
        onPersistSettings: _persistSettings,
        onShowToast: _showToast,
        onShowBlogSiteManager: _showBlogSiteManager,
        onShowCreateSite: () => _startAiSiteWizard(),
      ),
    );
  }

  void _openSyncSettings() {
    _openTab(
      'sync_settings',
      '云同步',
      Icons.cloud_sync,
      SyncSettingsScreen(
        cloudSyncService: cloudSyncService,
        logService: logService,
        settings: settings,
        repos: repos,
        onSettingsChanged: _updateSettings,
        onPushAll: _pushAllToCloud,
        onPullAll: _pullAllFromCloud,
      ),
    );
  }

  void _openLogs() {
    _openTab('logs', '操作日志', Icons.history, LogScreen(logService: logService));
  }

  void _addRecentFile(String path, String name) {
    _recentFiles.removeWhere((f) => f.path == path);
    _recentFiles.insert(
      0,
      RecentFile(path: path, name: name, openedAt: DateTime.now()),
    );
    if (_recentFiles.length > DesktopShellState._maxRecentFiles) {
      _recentFiles.removeRange(DesktopShellState._maxRecentFiles, _recentFiles.length);
    }
    _persistRecentFiles();
  }

  Future<void> _persistRecentFiles() async {
    try {
      final rootDir = await storage.root;
      final file = File('${rootDir.path}/recent_files.json');
      await file.writeAsString(
        jsonEncode(
          _recentFiles
              .map(
                (f) => {
                  'path': f.path,
                  'name': f.name,
                  'openedAt': f.openedAt.toIso8601String(),
                },
              )
              .toList(),
        ),
      );
    } catch (e) {
      debugPrint('Shell: git status failed: $e');
    }
  }

  Future<void> _loadRecentFiles() async {
    try {
      final rootDir = await storage.root;
      final file = File('${rootDir.path}/recent_files.json');
      if (await file.exists()) {
        final list = jsonDecode(await file.readAsString()) as List;
        _recentFiles.clear();
        for (final item in list) {
          _recentFiles.add(
            RecentFile(
              path: item['path'] as String,
              name: item['name'] as String,
              openedAt:
                  DateTime.tryParse(item['openedAt']?.toString() ?? '') ??
                  DateTime.now(),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Shell: git log failed: $e');
    }
  }

  Future<void> _openFileDialog() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'markdown', 'txt'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;
      final file = File(path);
      final content = await file.readAsString();
      final fileName = path
          .split('/')
          .last
          .replaceAll(RegExp(r'\.(md|markdown|txt)$'), '');
      openExternalFile(fileName, content, path);
    } catch (e) {
      _showToast('打开文件失败: $e');
    }
  }

  void _openLocalFileZone() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LocalFileZoneScreen(
          storage: storage,
          github: github,
          activeRepo: _editorRepo,
          onOpenFile: (fileName, content, filePath) {
            openExternalFile(fileName, content, filePath);
          },
        ),
      ),
    );
  }

  void _openAllFeatures() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AllFeaturesScreen(
          mode: settings.ui.appMode,
          simpleModeExtras: settings.ui.simpleModeExtras,
          navCustom: settings.ui.navCustom,
          bus: _bus,
          onNavCustomChanged: (cfg) {
            _updateSettings(
              settings.copyWith(ui: settings.ui.copyWith(navCustom: cfg)),
            );
          },
        ),
      ),
    );
  }

  void _openSidebarCustomize() {
    showSidebarCustomizeDialog(
      context: context,
      mode: settings.ui.appMode,
      simpleModeExtras: settings.ui.simpleModeExtras,
      navCustom: settings.ui.navCustom,
      onNavCustomChanged: (cfg) {
        _updateSettings(
          settings.copyWith(ui: settings.ui.copyWith(navCustom: cfg)),
        );
      },
    );
  }

  void _switchSite(RepoConfig repo) async {
    await _updateSettings(settings.copyWith(activeRepoId: repo.id));
    _editorRepo = repo;
    if (mounted) {
      _showToast('已切换到: ${repo.name}');
    }
  }

  void _toggleLeftPanel() {
    _layout.toggleLeftPanel();
    if (_layout.leftPanelExpanded && _layout.workMode == WorkMode.focus) {
      _layout.switchWorkMode(WorkMode.workspace);
    }
    // 持久化左面板展开状态（重启恢复；默认隐藏，用户展开才记住"开"）
    final expanded = _layout.leftPanelExpanded;
    if (settings.ui.leftPanelExpanded != expanded) {
      _updateSettings(
        settings.copyWith(
          ui: settings.ui.copyWith(leftPanelExpanded: expanded),
        ),
      );
    }
  }

  void _toggleRightDrawer() => _layout.toggleRightDrawer();

  /// Escape 键处理：关闭抽屉 → 关闭极简预览 → 退出专注模式 → 退出源码模式
  void _handleEscape() {
    if (_layout.rightDrawerOpen) {
      _layout.closeRightDrawer();
    } else if (_focusPreviewOpen) {
      _applyState(() => _focusPreviewOpen = false);
    } else if (_layout.workMode == WorkMode.focus ||
        _layout.workMode == WorkMode.source) {
      _switchWorkMode(WorkMode.workspace);
    }
  }

  void _openRightDrawer(RightDrawerTab tab) {
    _layout.openRightDrawer(tab);
  }

  void _toggleTheme() {
    widget.onToggleAppTheme?.call();
  }

  void _switchWorkMode(WorkMode mode) {
    _layout.switchWorkMode(mode);
    switch (mode) {
      case WorkMode.workspace:
        // 保留当前左面板折叠状态（尊重持久化偏好，不再强制展开）
        _layout.closeRightDrawer();
        break;
      case WorkMode.focus:
        _layout.collapseLeftPanel();
        _layout.closeRightDrawer();
        if (_focusShowToolbar || _focusPreviewOpen) {
          _applyState(() {
            _focusShowToolbar = false;
            _focusPreviewOpen = false;
          });
        }
        break;
      case WorkMode.source:
        // 保留当前左面板折叠状态
        _layout.closeRightDrawer();
        break;
    }
  }
}
