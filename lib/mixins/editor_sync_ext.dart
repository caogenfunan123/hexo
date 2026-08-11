// 编辑器同步/云端扩展（由 main.dart part 引入，与原类同 library，可访问私有成员）
part of '../main.dart';

extension EditorSyncExt on _RootShellState {

  /// 初始化云同步后端
  Future<void> _initCloudSync() async {
    // 初始化设备密钥
    final deviceKey = await storage.loadDeviceKey();
    cloudSyncService.initDeviceKey(deviceKey);

    // 注册 GitHub 后端 — 使用独立同步仓库，不与网站仓库混用
    final githubBackend = GitHubSyncBackend(github);
    cloudSyncService.registerBackend(githubBackend);
    githubBackend.configureFromSyncSettings(settings.sync);

    // 注册 WebDAV 后端
    final webdavBackend = WebDavSyncBackend();
    webdavBackend.configureFromSettings(settings);
    cloudSyncService.registerBackend(webdavBackend);

    // 启动自动同步（仅当 draftSyncEnabled 开启时生效）
    _startAutoSync();

    // 如果后端已配置且草稿同步开启，启动后自动拉取一次
    if (cloudSyncService.hasConfiguredBackend && settings.draftSyncEnabled) {
      _autoPullFromCloud();
    }
  }


  /// 启动云端自动同步定时器
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


  /// 打开 P2P 同步界面
  void _openP2PSync() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => P2PSyncScreen(
          p2pService: _p2pSyncService,
          localArticles: drafts,
          onFilesReceived: (files) {
            for (final file in files) {
              final existingIndex = drafts.indexWhere(
                (d) => d.fileName() == file.path,
              );
              final article = Article(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                title: file.path.replaceAll('.md', ''),
                content: file.content,
                createdAt: file.modifiedAt,
                updatedAt: DateTime.now(),
                isDraft: true,
              );
              if (existingIndex >= 0) {
                drafts[existingIndex] = article;
              } else {
                drafts.add(article);
              }
            }
            storage.saveDrafts(drafts);
            if (mounted) _applyState(() {});
            _showToast('已接收 ${files.length} 个文件');
          },
        ),
      ),
    );
  }


  /// 自动同步到云端（推送）
  Future<void> _autoSyncToCloud() async {
    if (busy) return;
    final backend = cloudSyncService.configuredBackends.firstOrNull;
    if (backend == null) return;

    try {
      await cloudSyncService.pushDrafts(backend, drafts);
      await cloudSyncService.pushSyncMappings(backend, syncService);
    } catch (e) {
      debugPrint('Auto sync error: $e');
    }
  }


  /// 自动从云端拉取（后台静默，不弹 toast）
  Future<void> _autoPullFromCloud() async {
    if (busy) return;
    final backend = cloudSyncService.configuredBackends.firstOrNull;
    if (backend == null) return;

    try {
      final pulled = await cloudSyncService.pullDrafts(
        backend,
        existingDrafts: drafts,
      );
      if (pulled.isNotEmpty) {
        if (mounted)
          _applyState(() {
            drafts = pulled..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          });
        storage.saveDrafts(drafts);
      }
      await cloudSyncService.pullSyncMappings(backend, syncService);
    } catch (e) {
      debugPrint('Auto sync error: $e');
    }
  }


  /// 冲刷所有等待中的保存任务（三重落盘：文本变更 / 页面切换 / APP 转入后台）
  void _flushAllPendingSaves() {
    for (final entry in _debounceTimers.entries) {
      entry.value.cancel();
      final articleId = entry.key;
      final content = entry.value.content;
      if (content.isNotEmpty && content != _lastSavedContentMap[articleId]) {
        _autoSaveSnapshot(
          articleId: articleId,
          content: content,
          title: entry.value.title,
        );
      }
    }
    _debounceTimers.clear();
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
        if (!item.isDir && item.name.endsWith('.md')) {
          final id = item.name.replaceAll(RegExp(r'\.md$'), '');
          if (!localIds.contains(item.name)) {
            final bytes = await svc.downloadFile(
              settings.webdavUrl,
              settings.webdavUsername,
              settings.webdavPassword,
              folder,
              item.name,
            );
            final md = utf8.decode(bytes);
            final article = Article.fromMarkdown(md, id: id);
            drafts.add(article);
            count++;
          }
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
    } on Exception catch (e) {
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
            a.toMarkdownWithFrontMatter(templates: templates),
          );
          count++;
        }
      }
      if (mounted) {
        _applyState(() => loading = false);
        _showToast('已上传 $count 篇草稿');
      }
    } on Exception catch (e) {
      if (mounted) {
        _applyState(() => loading = false);
        _showToast('WebDAV 失败: $e');
      }
    }
  }


  // ============ 云同步 ============

  /// 全量推送到云端
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


  /// 全量从云端拉取
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
          // 合并远程模板到本地：按 ID 覆盖，保留本地独有
          final remoteMap = <String, Map<String, dynamic>>{};
          for (final t in tList) {
            remoteMap[t['id']?.toString() ?? ''] = t;
          }
          final merged = <TemplateItem>[];
          final seen = <String>{};
          for (final t in templates) {
            if (remoteMap.containsKey(t.id)) {
              // 远程有同 ID → 使用远程版本（更新）
              final remote = remoteMap[t.id]!;
              merged.add(TemplateItem.fromJson(remote));
              seen.add(t.id);
            } else {
              // 本地独有 → 保留
              merged.add(t);
              seen.add(t.id);
            }
          }
          // 远程独有 → 添加
          for (final entry in remoteMap.entries) {
            if (!seen.contains(entry.key)) {
              merged.add(TemplateItem.fromJson(entry.value));
            }
          }
          _applyState(() => templates = merged);
          storage.saveTemplates(merged);
        },
        onSnippetsLoaded: (sList) {
          // 合并远程片段到本地：按 ID 覆盖
          final remoteMap = <String, Map<String, dynamic>>{};
          for (final s in sList) {
            remoteMap[s['id']?.toString() ?? ''] = s;
          }
          final merged = <SnippetItem>[];
          final seen = <String>{};
          for (final s in snippets) {
            if (remoteMap.containsKey(s.id)) {
              merged.add(SnippetItem.fromJson(remoteMap[s.id]!));
              seen.add(s.id);
            } else {
              merged.add(s);
              seen.add(s.id);
            }
          }
          for (final entry in remoteMap.entries) {
            if (!seen.contains(entry.key)) {
              merged.add(SnippetItem.fromJson(entry.value));
            }
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

}
