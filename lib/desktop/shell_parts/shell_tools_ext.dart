// 运维工具 / 批量操作扩展（desktop_shell.dart 的 part，与主类同 library，可访问私有成员）。
// 由 desktop_shell.dart 拆分而来（修复1），方法体保持零变更；
// setState 经宿主 _applyState 包装调用。
part of '../desktop_shell.dart';

extension DesktopShellToolsExt on DesktopShellState {
  void _showBatchOperations() {
    if (drafts.isEmpty) {
      if (mounted) _showToast('没有可用的草稿');
      return;
    }

    final selected = <String, bool>{};
    for (final d in drafts) {
      selected[d.id] = false;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final selectedIds = selected.entries
              .where((e) => e.value)
              .map((e) => e.key)
              .toList();
          return AlertDialog(
            title: const Text('批量操作'),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          final allSelected = selected.values.every((v) => v);
                          for (final k in selected.keys) {
                            selected[k] = !allSelected;
                          }
                          setDialogState(() {});
                        },
                        child: Text(
                          selected.values.every((v) => v) ? '取消全选' : '全选',
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '已选: ${selectedIds.length} / ${drafts.length}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 300,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: drafts.length,
                      itemBuilder: (_, i) {
                        final d = drafts[i];
                        return CheckboxListTile(
                          dense: true,
                          value: selected[d.id] ?? false,
                          onChanged: (v) {
                            selected[d.id] = v ?? false;
                            setDialogState(() {});
                          },
                          title: Text(
                            d.title.isNotEmpty ? d.title : '未命名',
                            style: const TextStyle(fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            d.updatedAt.toString().substring(0, 16),
                            style: const TextStyle(fontSize: 11),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: selectedIds.isEmpty
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        await _batchExportMd(selectedIds);
                      },
                child: const Text('批量导出 MD'),
              ),
              TextButton(
                onPressed: selectedIds.isEmpty
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        await _batchFormat(selectedIds);
                      },
                child: const Text('批量格式化'),
              ),
              FilledButton(
                onPressed: selectedIds.isEmpty
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        await _batchPublish(selectedIds);
                      },
                child: const Text('批量发布'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _batchExportMd(List<String> articleIds) async {
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择导出目录',
      );
      if (result == null) return;

      int exported = 0;
      for (final id in articleIds) {
        final article = drafts.firstWhere(
          (a) => a.id == id,
          orElse: () => Article(
            id: '',
            title: '',
            content: '',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            isDraft: true,
          ),
        );
        if (article.id.isEmpty) continue;

        final safeTitle =
            (article.title.isNotEmpty ? article.title : 'untitled').replaceAll(
              RegExp(r'[\\/:*?"<>|]'),
              '_',
            );
        final fileName = '$safeTitle.md';
        final file = File('$result/$fileName');
        await file.writeAsString(article.toMarkdownWithFrontMatter());
        exported++;
      }
      if (mounted) _showToast('已导出 $exported 篇草稿');
    } catch (e) {
      if (mounted) _showToast('导出失败: $e');
    }
  }

  Future<void> _batchFormat(List<String> articleIds) async {
    try {
      int formatted = 0;
      for (final id in articleIds) {
        final article = drafts.firstWhere(
          (a) => a.id == id,
          orElse: () => Article(
            id: '',
            title: '',
            content: '',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            isDraft: true,
          ),
        );
        if (article.id.isEmpty) continue;

        // 格式化文章内容
        final lines = article.content.split('\n');
        final result = <String>[];
        int emptyLineCount = 0;
        for (final line in lines) {
          final trimmed = line.trimRight();
          if (trimmed.isEmpty) {
            emptyLineCount++;
            if (emptyLineCount <= 2) result.add(trimmed);
            continue;
          }
          emptyLineCount = 0;

          final headingMatch = RegExp(r'^(#{1,6})\s').firstMatch(trimmed);
          if (headingMatch != null) {
            if (result.isNotEmpty && result.last.trim().isNotEmpty)
              result.add('');
            result.add(trimmed);
          } else {
            result.add(trimmed);
          }
        }
        while (result.isNotEmpty && result.last.trim().isEmpty) {
          result.removeLast();
        }

        final formattedContent = '${result.join('\n')}\n';
        final updated = article.copyWith(
          content: formattedContent,
          updatedAt: DateTime.now(),
        );
        final idx = drafts.indexWhere((a) => a.id == id);
        if (idx >= 0) drafts[idx] = updated;
        formatted++;
      }
      await storage.saveDrafts(drafts);
      if (mounted) {
        _showToast('已格式化 $formatted 篇草稿');
      }
    } catch (e) {
      if (mounted) _showToast('批量格式化失败: $e');
    }
  }

  void _openThemeMigration() {
    _openTab(
      'theme_migration',
      'AI 主题迁移',
      Icons.auto_fix_high,
      ThemeMigrationScreen(
        settings: settings,
        activeRepo: effectiveRepo,
        repos: repos,
        aiService: aiService,
        githubService: github,
        modelManager: aiModelManager,
        dispatcher: aiDispatcher,
        migrationService: themeMigrationService,
        selfChecker: aiSelfChecker,
        onSettingsChanged: _updateSettings,
        storageService: storage,
      ),
    );
  }

  void _openRecycleBin() {
    _openTab(
      'recycle_bin',
      '回收站',
      Icons.delete_outline,
      RecycleBinScreen(
        recycleBinService: recycleBinService,
        onRestored: (entry, path) {
          _showToast('已恢复: $path');
          // 把恢复的文章重新加入草稿列表并持久化
          final article = entry?.article;
          if (article != null) {
            final i = drafts.indexWhere((d) => d.id == article.id);
            if (i >= 0) {
              drafts[i] = article;
            } else {
              drafts.insert(0, article);
            }
            drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
            storage.saveDrafts(drafts);
          }
          // 恢复后刷新草稿列表
          _refreshDraftsFromStorage();
        },
      ),
    );
  }

  void _openP2PSync() {
    _openTab(
      'p2p_sync',
      'P2P 同步',
      Icons.wifi,
      P2PSyncScreen(
        p2pService: p2pSyncService,
        localArticles: drafts,
        onFilesReceived: (files) {
          for (final file in files) {
            // 接收到的文件添加到草稿
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
    );
  }

  void _openImageBedManager() {
    _openTab(
      'image_bed',
      '图床管理',
      Icons.photo_library_outlined,
      ImageBedScreen(
        settings: settings,
        githubService: github,
        imageService: imageService,
        allArticles: drafts,
        onUrlReplaced: (oldUrl, newUrl) {
          // 批量替换所有文章中的图片URL
          for (int i = 0; i < drafts.length; i++) {
            final a = drafts[i];
            if (a.content.contains(oldUrl)) {
              drafts[i] = a.copyWith(
                content: a.content.replaceAll(oldUrl, newUrl),
              );
            }
          }
          storage.saveDrafts(drafts);
          // 如果当前文章也受影响，更新编辑器
          if (_doc.currentArticle.content.contains(oldUrl)) {
            _doc.contentCtrl.text = _doc.currentArticle.content.replaceAll(
              oldUrl,
              newUrl,
            );
            _onContentChanged();
          }
          _showToast('图片URL批量替换完成');
        },
      ),
    );
  }

  void _openVersionHistory() {
    final articleId = _doc.currentArticle.id;
    final articleTitle = _doc.currentArticle.title;
    showDialog(
      context: context,
      builder: (ctx) => _VersionHistoryDialog(
        articleId: articleId,
        articleTitle: articleTitle,
        versionSnapshotService: versionSnapshotService,
        onRestore: (content) {
          _doc.contentCtrl.text = content;
          _onContentChanged();
          _doc.markUnsaved();
          _editor.setEditorStatus('已恢复历史版本');
          _showToast('已恢复历史版本，请保存');
        },
      ),
    );
  }

  Future<void> _openProxySettings() async {
    final hostCtrl = TextEditingController(text: settings.proxyHost);
    final portCtrl = TextEditingController(text: settings.proxyPort.toString());
    final userCtrl = TextEditingController(text: settings.proxyUsername);
    final passCtrl = TextEditingController(text: settings.proxyPassword);
    bool enabled = settings.proxyEnabled;
    bool applyToAi = settings.proxyApplyToAi;

    try {
      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.vpn_lock_outlined, size: 22),
                SizedBox(width: 8),
                Text('网络代理设置', style: TextStyle(fontSize: 17)),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('启用代理', style: TextStyle(fontSize: 14)),
                    value: enabled,
                    onChanged: (v) => setDialogState(() => enabled = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  TextField(
                    controller: hostCtrl,
                    decoration: const InputDecoration(
                      labelText: '代理主机',
                      hintText: '127.0.0.1',
                      isDense: true,
                    ),
                    enabled: enabled,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: portCtrl,
                    decoration: const InputDecoration(
                      labelText: '端口',
                      hintText: '1080',
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    enabled: enabled,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: userCtrl,
                    decoration: const InputDecoration(
                      labelText: '用户名 (可选)',
                      isDense: true,
                    ),
                    enabled: enabled,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: passCtrl,
                    decoration: const InputDecoration(
                      labelText: '密码 (可选)',
                      isDense: true,
                    ),
                    obscureText: true,
                    enabled: enabled,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text(
                      '对 AI 接口也启用代理',
                      style: TextStyle(fontSize: 13),
                    ),
                    subtitle: const Text(
                      '国内网络访问 OpenAI 等 API 需要代理',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: applyToAi,
                    onChanged: enabled
                        ? (v) => setDialogState(() => applyToAi = v)
                        : null,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  final newSettings = settings.copyWith(
                    proxyEnabled: enabled,
                    proxyHost: hostCtrl.text.trim(),
                    proxyPort: int.tryParse(portCtrl.text.trim()) ?? 1080,
                    proxyUsername: userCtrl.text.trim(),
                    proxyPassword: passCtrl.text.trim(),
                    proxyApplyToAi: applyToAi,
                  );
                  await _updateSettings(newSettings);
                  if (mounted) {
                    Navigator.pop(ctx);
                    _showToast('代理设置已保存');
                  }
                },
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      );
    } finally {
      hostCtrl.dispose();
      portCtrl.dispose();
      userCtrl.dispose();
      passCtrl.dispose();
    }
  }

  void _openCacheCleanup() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cleaning_services_outlined, size: 22),
            SizedBox(width: 8),
            Text('缓存清理', style: TextStyle(fontSize: 17)),
          ],
        ),
        content: const SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '此操作将清理以下缓存:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text('  • 图片缓存 (image_cache)', style: TextStyle(fontSize: 13)),
              Text('  • 预览缓存 (webview_cache)', style: TextStyle(fontSize: 13)),
              Text('  • 临时文件', style: TextStyle(fontSize: 13)),
              SizedBox(height: 12),
              Text(
                '清理后不会影响草稿和设置。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final rootDir = await storage.root;
                // 清理图片缓存
                final imgCache = Directory('${rootDir.path}/image_cache');
                if (await imgCache.exists())
                  await imgCache.delete(recursive: true);
                // 清理 WebView 缓存
                final webCache = Directory('${rootDir.path}/webview_cache');
                if (await webCache.exists())
                  await webCache.delete(recursive: true);
                // 清理临时文件
                final tmpDir = Directory('${rootDir.path}/tmp');
                if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  _showToast('缓存已清理');
                }
              } catch (e) {
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  _showToast('清理失败: $e');
                }
              }
            },
            child: const Text('立即清理'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportLogs() async {
    try {
      final logs = logService.logs;
      if (logs.isEmpty) {
        _showToast('暂无日志');
        return;
      }
      final logText = logs
          .map(
            (l) =>
                '[${l.timestamp}] ${l.success ? "✓" : "✗"} ${l.action}: ${l.detail}',
          )
          .join('\n');
      final rootDir = await storage.root;
      final logFile = File(
        '${rootDir.path}/export_logs_${DateTime.now().millisecondsSinceEpoch}.txt',
      );
      await logFile.writeAsString(logText);
      _showToast('日志已导出到: ${logFile.path}');
    } catch (e) {
      _showToast('日志导出失败: $e');
    }
  }

  Future<void> _fixEncoding() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'txt', 'markdown'],
      );
      if (result == null || result.files.isEmpty) return;
      final filePath = result.files.first.path;
      if (filePath == null) return;
      final file = File(filePath);
      final rawBytes = await file.readAsBytes();

      // 尝试检测编码并转为 UTF-8
      String decoded;
      try {
        // 尝试 UTF-8
        decoded = utf8.decode(rawBytes);
      } catch (e) {
        debugPrint('Shell: encoding UTF-8 decode failed: $e');
        try {
          // 尝试 GBK
          decoded = gbk.decode(rawBytes);
        } catch (e) {
          debugPrint('Shell: encoding GBK decode failed: $e');
          // 尝试 Latin-1
          decoded = latin1.decode(rawBytes);
        }
      }

      // 写回 UTF-8
      final backupPath = '$filePath.bak';
      await file.copy(backupPath);
      await file.writeAsString(decoded, encoding: utf8);
      _showToast('编码修复完成，已保存 UTF-8 版本\n备份文件: $backupPath');
    } catch (e) {
      _showToast('编码修复失败: $e');
    }
  }

  Future<void> _toggleOfflineMode() async {
    final newSettings = settings.copyWith(offlineMode: !settings.offlineMode);
    await _updateSettings(newSettings);
    _showToast(settings.offlineMode ? '已退出离线模式' : '已进入离线模式\n同步和 AI 功能已暂停');
  }

  Future<void> _toggleNightEyeProtection() async {
    final newSettings = settings.copyWith(
      nightEyeProtection: !settings.nightEyeProtection,
    );
    await _updateSettings(newSettings);
    _showToast(settings.nightEyeProtection ? '已关闭护眼滤镜' : '已开启护眼滤镜');
  }

  void _openLinkChecker() {
    _openTab(
      'link_checker',
      '链接检测',
      Icons.link_off,
      LinkCheckerScreen(articles: drafts, onOpenArticle: _openExistingArticle),
    );
  }

  void _openBatchTools() {
    _openTab(
      'batch_tools',
      '批量工具箱',
      Icons.build_circle,
      BatchToolsScreen(
        articles: drafts,
        github: github,
        repos: repos,
        onArticlesUpdated: (updated) {
          _applyState(() {
            drafts = updated;
            // 更新当前文章如果被修改
            for (final a in updated) {
              if (a.id == _doc.currentArticle.id) {
                _doc.setCurrentArticle(a);
                _doc.contentCtrl.text = a.content;
                _doc.titleCtrl.text = a.title;
                _doc.tagsCtrl.text = a.tags.join(', ');
                _doc.categoriesCtrl.text = a.categories.join(', ');
                break;
              }
            }
          });
          _onContentChanged();
          storage.saveDrafts(drafts);
          _showToast('批量操作已完成，草稿已保存');
        },
      ),
    );
  }

  void _openContentStats() {
    _openTab(
      'content_stats',
      '内容统计',
      Icons.insights_outlined,
      ContentStatsScreen(drafts: drafts, repos: repos),
    );
  }

  void _openBackupRestore() {
    _openTab(
      'backup_restore',
      '备份与恢复',
      Icons.settings_backup_restore,
      BackupRestoreScreen(
        rootProvider: () => storage.root,
        onToast: _showToast,
      ),
    );
  }

  void _showSpellCheck() {
    final results = spellCheckService.check(_doc.contentCtrl.text);
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.spellcheck, size: 20),
              const SizedBox(width: 8),
              const Text('拼写检查', style: TextStyle(fontSize: 16)),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  spellCheckService.toggle();
                  Navigator.pop(ctx);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: spellCheckService.enabled
                        ? Colors.green.withOpacity(0.15)
                        : Colors.grey.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    spellCheckService.enabled ? '已启用' : '已禁用',
                    style: TextStyle(
                      fontSize: 11,
                      color: spellCheckService.enabled
                          ? Colors.green
                          : Colors.grey,
                    ),
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 400,
            child: SpellCheckPanel(
              results: results,
              isDark: isDark,
              onJumpToOffset: (offset) {
                Navigator.pop(ctx);
                _doc.contentCtrl.selection = TextSelection.collapsed(
                  offset: offset,
                );
                _doc.contentFocus.requestFocus();
              },
              onReplace: (result) {
                // 替换单词
                if (result.suggestions.isNotEmpty) {
                  final text = _doc.contentCtrl.text;
                  final newText =
                      text.substring(0, result.offset) +
                      result.suggestions.first +
                      text.substring(result.offset + result.length);
                  _doc.contentCtrl.text = newText;
                  _doc.contentCtrl.selection = TextSelection.collapsed(
                    offset: result.offset + result.suggestions.first.length,
                  );
                  _onContentChanged();
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showSpellCheck();
              },
              child: const Text('重新检查'),
            ),
          ],
        );
      },
    );
  }
}
