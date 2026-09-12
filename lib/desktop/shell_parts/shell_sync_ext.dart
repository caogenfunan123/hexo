// 云同步 / WebDAV / 冲突解决扩展（desktop_shell.dart 的 part，与主类同 library，可访问私有成员）。
// 由 desktop_shell.dart 拆分而来（修复1），方法体保持零变更；
// setState 经宿主 _applyState 包装调用。
part of '../desktop_shell.dart';

extension DesktopShellSyncExt on DesktopShellState {
  void _startAutoSync() {
    _stopAutoSync();
    if (!settings.draftSyncEnabled) return;
    _autoSyncTimer = Timer.periodic(
      Duration(seconds: settings.webdavAutoSyncIntervalSeconds),
      (_) => _autoSyncToCloud(),
    );
  }

  void _stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  Future<void> _autoSyncToCloud() async {
    if (busy || _autoSyncing) return;
    final backend = cloudSyncService.configuredBackends.firstOrNull;
    if (backend == null) return;
    _autoSyncing = true;
    try {
      await cloudSyncService.pushDrafts(backend, drafts);
      await cloudSyncService.pushSyncMappings(backend, syncService);
    } catch (e) {
      debugPrint('Cloud push drafts error: $e');
    } finally {
      _autoSyncing = false;
    }
  }

  Future<void> _autoPullFromCloud() async {
    if (busy || _autoSyncing) return;
    final backend = cloudSyncService.configuredBackends.firstOrNull;
    if (backend == null) return;
    _autoSyncing = true;
    try {
      final pulled = await cloudSyncService.pullDrafts(
        backend,
        existingDrafts: drafts,
      );
      if (pulled.isNotEmpty && mounted) {
        _applyState(() {
          drafts = pulled..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        });
        storage.saveDrafts(drafts);
      }
      await cloudSyncService.pullSyncMappings(backend, syncService);
    } catch (e) {
      debugPrint('Cloud pull drafts error: $e');
    } finally {
      _autoSyncing = false;
    }
  }

  Future<void> _pushAllToCloud() async {
    final backend = cloudSyncService.configuredBackends.firstOrNull;
    if (backend == null) {
      _showToast('请先配置同步后端');
      return;
    }
    _applyState(() => busy = true);
    try {
      final result = await cloudSyncService.pushAll(
        backend,
        drafts: drafts,
        settings: settings,
        syncService: syncService,
        templates: templates,
        snippets: snippets,
      );
      if (mounted) {
        _applyState(() => busy = false);
        if (result.isSuccess) {
          _showToast('推送完成: ${result.pushed} 项');
        } else {
          _showToast('推送完成: ${result.pushed} 成功, ${result.errors.length} 失败');
        }
      }
    } catch (e) {
      if (mounted) {
        _applyState(() => busy = false);
        _showToast('推送失败: $e');
      }
    }
  }

  Future<void> _pullAllFromCloud() async {
    final backend = cloudSyncService.configuredBackends.firstOrNull;
    if (backend == null) {
      _showToast('请先配置同步后端');
      return;
    }
    _applyState(() => busy = true);
    try {
      await cloudSyncService.pullAll(
        backend,
        existingDrafts: drafts,
        syncService: syncService,
        onSettingsLoaded: (s) {
          _applyState(() => settings = s);
          _updateSiteManager();
          _startAutoSync();
          storage.saveSettings(s);
        },
        onDraftsLoaded: (d) {
          _applyState(() {
            drafts = d..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          });
          storage.saveDrafts(drafts);
        },
        onTemplatesLoaded: (tList) {
          final merged = <TemplateItem>[];
          final seen = <String>{};
          for (final remote in tList) {
            final t = TemplateItem.fromJson(remote);
            merged.add(t);
            seen.add(t.id);
          }
          for (final t in templates) {
            if (!seen.contains(t.id)) merged.add(t);
          }
          _applyState(() => templates = merged);
          storage.saveTemplates(merged);
        },
        onSnippetsLoaded: (sList) {
          final merged = <SnippetItem>[];
          final seen = <String>{};
          for (final s in sList) {
            final item = SnippetItem.fromJson(s);
            merged.add(item);
            seen.add(item.id);
          }
          for (final s in snippets) {
            if (!seen.contains(s.id)) merged.add(s);
          }
          _applyState(() => snippets = merged);
          storage.saveSnippets(merged);
        },
      );
      if (mounted) {
        _applyState(() => busy = false);
        _showToast('拉取完成');
      }
    } catch (e) {
      if (mounted) {
        _applyState(() => busy = false);
        _showToast('拉取失败: $e');
      }
    }
  }

  void _openSyncStatus() {
    final adapter = siteManager.currentAdapter;
    final config = adapter?.config;
    if (adapter != null && config != null) {
      _openTab(
        'sync',
        '同步状态',
        Icons.sync,
        SyncScreen(
          adapter: adapter,
          siteConfig: config,
          syncService: syncService,
          logService: logService,
          localArticles: drafts,
          onOpenArticle: _openExistingArticle,
          onOpenRemotePost: (post) {
            _openExistingArticle(
              Article(
                // 用远程 id 生成稳定 tab id，避免同一远程文章重复打开
                id: 'sync_${post.id ?? post.title.hashCode}',
                title: post.title,
                content: post.contentMd,
                tags: post.tags,
                categories: post.categories,
                createdAt: post.date,
                updatedAt: post.modifiedDate,
                isDraft: false,
                published: true,
                articleType: ArticleType.post,
                remotePath: post.link,
                remoteSha: post.id?.toString(),
              ),
            );
          },
        ),
      );
    } else {
      _showToast('请先在"动态博客登录"中配置 CMS 站点');
    }
  }

  void _showConflictResolution(List<SyncEntry> conflicts) {
    showDialog(
      context: context,
      builder: (ctx) => _ConflictResolutionDialog(
        conflicts: conflicts,
        drafts: drafts,
        syncService: syncService,
        siteManager: siteManager,
        onResolved: (resolutions) {
          Navigator.pop(ctx);
          _applyConflictResolutions(resolutions);
        },
      ),
    );
  }

  void _applyConflictResolutions(Map<String, String> resolutions) {
    // resolutions: key=articleId, value="local"/"remote"/"merge"
    for (final entry in resolutions.entries) {
      final articleId = entry.key;
      final strategy = entry.value;
      if (strategy == 'local') {
        // 保留本地版本，标记为需要推送
        _showToast(
          '已保留本地版本: ${drafts.firstWhere((a) => a.id == articleId, orElse: () => _doc.currentArticle).title}',
        );
      } else if (strategy == 'remote') {
        // 使用远程版本覆盖本地
        _showToast('已使用远程版本覆盖本地');
      }
    }
    storage.saveDrafts(drafts);
    _showToast('冲突已解决，可重新同步');
  }

  Future<bool> _checkAndResolveConflicts() async {
    if (!siteManager.isDynamicSite) return true;
    final adapter = siteManager.currentAdapter;
    if (adapter == null) return true;

    try {
      final siteConfig = siteManager.currentAdapter?.config;
      if (siteConfig == null) return true;
      final entries = await syncService.compareSync(
        siteConfig,
        adapter,
        drafts,
      );
      final conflicts = entries.where((e) => e.hasConflict).toList();
      if (conflicts.isNotEmpty) {
        _showConflictResolution(conflicts);
        return false;
      }
    } catch (e) {
      debugPrint('Shell: AI diff failed: $e');
    }
    return true;
  }

  List<_DiffLine> _computeDiff(String oldText, String newText) {
    final result = <_DiffLine>[];
    final oldLines = oldText.split('\n');
    final newLines = newText.split('\n');

    // 逐行 LCS diff
    final lcs = _lcsMatrix(oldLines, newLines);
    int i = oldLines.length, j = newLines.length;
    final reversed = <_DiffLine>[];

    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && oldLines[i - 1] == newLines[j - 1]) {
        reversed.add(
          _DiffLine(type: _DiffType.equal, text: oldLines[i - 1], lineNum: i),
        );
        i--;
        j--;
      } else if (j > 0 && (i == 0 || lcs[i][j - 1] >= lcs[i - 1][j])) {
        reversed.add(
          _DiffLine(type: _DiffType.added, text: newLines[j - 1], lineNum: j),
        );
        j--;
      } else if (i > 0) {
        reversed.add(
          _DiffLine(type: _DiffType.removed, text: oldLines[i - 1], lineNum: i),
        );
        i--;
      }
    }
    result.addAll(reversed.reversed);
    return result;
  }

  List<List<int>> _lcsMatrix(List<String> a, List<String> b) {
    final m = a.length, n = b.length;
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (a[i - 1] == b[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
        }
      }
    }
    return dp;
  }

  Future<void> _showWebDavDialog() async {
    final c = TextEditingController(text: settings.webdavUrl);
    final u = TextEditingController(text: settings.webdavUsername);
    final pw = TextEditingController(text: settings.webdavPassword);
    final f = TextEditingController(text: settings.webdavFolder);
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('WebDAV 备份'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: c,
                  decoration: const InputDecoration(
                    labelText: 'WebDAV 网址',
                    hintText: 'https://dav.jianguoyun.com/dav',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: u,
                  decoration: const InputDecoration(labelText: '账号'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pw,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: f,
                  decoration: const InputDecoration(labelText: '文件夹'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                settings = settings.copyWith(
                  webdavUrl: c.text.trim(),
                  webdavUsername: u.text.trim(),
                  webdavPassword: pw.text,
                  webdavFolder: f.text.trim().isEmpty
                      ? 'hexo-backup'
                      : f.text.trim(),
                );
                _persistSettings();
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (mounted) _applyState(() {});
    } finally {
      c.dispose();
      u.dispose();
      pw.dispose();
      f.dispose();
    }
  }

  Future<void> _syncWebDavToLocal() async {
    if (settings.webdavUrl.isEmpty) {
      await _showWebDavDialog();
      if (mounted && settings.webdavUrl.isEmpty) return;
    }
    try {
      loading = true;
      if (mounted) _applyState(() {});
      final svc = WebDavService();
      final drafts = await storage.loadDrafts();
      final folder = settings.webdavFolder.endsWith('/')
          ? settings.webdavFolder
          : '${settings.webdavFolder}/';
      final remote = await svc.list(
        settings.webdavUrl,
        settings.webdavUsername,
        settings.webdavPassword,
        folder,
      );
      final localIds = drafts.map((a) => '${a.id}.md').toSet();
      int count = 0;
      for (final item in remote) {
        if (!item.isDir &&
            item.name.endsWith('.md') &&
            !localIds.contains(item.name)) {
          final bytes = await svc.downloadFile(
            settings.webdavUrl,
            settings.webdavUsername,
            settings.webdavPassword,
            folder,
            item.name,
          );
          final md = utf8.decode(bytes);
          final article = Article.fromMarkdown(
            md,
            id: item.name.replaceAll(RegExp(r'\.md$'), ''),
          );
          drafts.add(article);
          count++;
        }
      }
      await storage.saveDrafts(drafts);
      if (mounted) {
        _applyState(() {
          loading = false;
          this.drafts = drafts
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        });
        _showToast('已从云端同步 $count 篇草稿到本地');
      }
    } catch (e) {
      if (mounted) {
        _applyState(() => loading = false);
        _showToast('WebDAV 同步失败: $e');
      }
    }
  }

  Future<void> _syncDraftsToWebDav() async {
    if (settings.webdavUrl.isEmpty) {
      await _showWebDavDialog();
      if (mounted && settings.webdavUrl.isEmpty) return;
    }
    try {
      loading = true;
      if (mounted) _applyState(() {});
      final svc = WebDavService();
      final drafts = await storage.loadDrafts();
      final folder = settings.webdavFolder.endsWith('/')
          ? settings.webdavFolder
          : '${settings.webdavFolder}/';
      await svc.createFolder(
        settings.webdavUrl,
        settings.webdavUsername,
        settings.webdavPassword,
        folder,
      );
      final remote = await svc.list(
        settings.webdavUrl,
        settings.webdavUsername,
        settings.webdavPassword,
        folder,
      );
      final names = remote
          .where((e) => e.name.endsWith('.md'))
          .map((e) => e.name)
          .toSet();
      int count = 0;
      for (final a in drafts) {
        if (!names.contains('${a.id}.md')) {
          await svc.putFile(
            settings.webdavUrl,
            settings.webdavUsername,
            settings.webdavPassword,
            '$folder${a.id}.md',
            a.toMarkdownWithFrontMatter(),
          );
          count++;
        }
      }
      if (mounted) {
        _applyState(() => loading = false);
        _showToast('已上传 $count 篇草稿');
      }
    } catch (e) {
      if (mounted) {
        _applyState(() => loading = false);
        _showToast('WebDAV 失败: $e');
      }
    }
  }

  Future<void> _handleSync() async {
    _sync.addLog('开始同步...', status: SyncStatus.syncing);
    // 1. 同步远程文章列表
    await _refreshRemote();
    _sync.addLog('远程文章已刷新', status: SyncStatus.success);
    // 2. 云同步草稿
    await _autoSyncToCloud();
    _sync.addLog('云同步完成', status: SyncStatus.success);
    _showToast('同步完成');
  }
}
