// 设置 / 站点 / 管理弹窗扩展（desktop_shell.dart 的 part，与主类同 library，可访问私有成员）。
// 由 desktop_shell.dart 拆分而来（修复1），方法体保持零变更；
// setState 经宿主 _applyState 包装调用。
part of '../desktop_shell.dart';

extension DesktopShellDialogsExt on DesktopShellState {
  Future<void> _showModeGuideDialog(AppSettings s) async {
    final choice = await showDialog<AppMode>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('选择使用模式'),
        content: const Text(
          '「简易普通用户模式」面向写作用户，隐藏专业开发与运维入口，保留写作、同步与 AI 配置；'
          '「标准专业模式」展示全部功能入口。可在设置中随时切换。',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, AppMode.standard),
            child: const Text('标准专业模式'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, AppMode.simple),
            child: const Text('简易普通用户模式'),
          ),
        ],
      ),
    );
    if (choice != null) {
      await _updateSettings(s.copyWith(ui: s.ui.copyWith(appMode: choice)));
      _showToast(choice == AppMode.simple ? '已切换到简易普通用户模式' : '已切换到标准专业模式');
    }
  }

  Future<void> _updateSettings(AppSettings s) async {
    final oldDc = settings.ui.designConfig;
    final oldLang = settings.language;
    final oldEt = settings.ui.editorTheme;
    _applyState(() => settings = s);
    storage.setCustomRoot(s.storageRootDir);
    storage.setExternalSafUri(s.externalSafUri);
    _updateSiteManager();
    _startAutoSync();
    await storage.saveSettings(s);
    // 编辑器主题变化：异步刷新壁纸亮度以适配字色
    if (oldEt.bgMode != s.ui.editorTheme.bgMode ||
        oldEt.wallpaperPath != s.ui.editorTheme.wallpaperPath ||
        oldEt.forceTextMode != s.ui.editorTheme.forceTextMode) {
      await _refreshWallpaperBrightness();
      if (mounted) _applyState(() {});
    }
    // 如果 DesignConfig 发生变化，通知 DesktopApp 重建主题
    if (widget.onDesignConfigChanged != null && oldDc != s.ui.designConfig) {
      widget.onDesignConfigChanged!(s.ui.designConfig);
    }
    // 如果语言发生变化，通知 DesktopApp 重建 MaterialApp locale
    if (widget.onLanguageChanged != null && oldLang != s.language) {
      widget.onLanguageChanged!(s.language);
    }
  }

  Future<void> _updateRepos(List<RepoConfig> r) async {
    _applyState(() => repos = r);
    _updateSiteManager();
    await storage.saveRepos(r);
  }

  Future<void> _loadEditorSettings() async {
    try {
      final rootDir = await storage.root;
      final file = File('${rootDir.path}/editor_settings.json');
      if (await file.exists()) {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        if (mounted) {
          _applyState(() {
            _editor.setEditorFontSize(
              (data['fontSize'] as num?)?.toDouble() ?? 16.0,
            );
            _editor.setEditorLineHeight(
              (data['lineHeight'] as num?)?.toDouble() ?? 1.6,
            );
            _editor.setEditorFontFamily(
              data['fontFamily'] as String? ?? 'System',
            );
            _editor.setEditorTheme(data['editorTheme'] as String? ?? 'default');
            _editor.setCustomCss(data['customCss'] as String? ?? '');
            _editor.setCustomShortcuts(
              (data['customShortcuts'] as Map<String, dynamic>?)?.map(
                    (k, v) => MapEntry(k, v.toString()),
                  ) ??
                  {},
            );
          });
          // 快捷键可能在桌面壳就绪后才加载完成，通知上层重建全局绑定
          widget.onShortcutsChanged?.call();
        }
      }
    } catch (e) {
      debugPrint('Load editor settings error: $e');
    }
  }

  Future<void> _saveEditorSettings() async {
    try {
      final rootDir = await storage.root;
      final file = File('${rootDir.path}/editor_settings.json');
      await file.writeAsString(
        jsonEncode({
          'fontSize': _editor.editorFontSize,
          'lineHeight': _editor.editorLineHeight,
          'fontFamily': _editor.editorFontFamily,
          'editorTheme': _editor.editorTheme,
          'customCss': _editor.customCss,
          'customShortcuts': _editor.customShortcuts,
        }),
      );
    } catch (e) {
      debugPrint('Save editor settings error: $e');
    }
  }

  void _showPwaGuide() {
    final site = activeRepo?.siteUrl.isNotEmpty == true
        ? activeRepo!.siteUrl
        : (settings.sitePreviewUrl.isNotEmpty ? settings.sitePreviewUrl : '');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PWA / 主屏幕快捷方式'),
        content: Text(
          '本应用负责写作与 Git 发布。\n\n'
          '站点 $site 由 Cloudflare Pages 部署，可在 Chrome/Edge/Safari：\n'
          '1. 打开站点\n'
          '2. 菜单 → 添加到主屏幕 / 安装应用\n'
          '3. 获得 PWA 阅读入口\n\n'
          '写作请继续使用本应用（支持离线草稿与 Token 发布）。',
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: site));
              Navigator.pop(ctx);
              _showToast('站点地址已复制');
            },
            child: const Text('复制站点'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _showTemplateManager() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TemplateManagerScreen(
          storage: storage,
          aiService: aiService,
          settings: settings,
          repos: repos,
          githubService: github,
        ),
      ),
    );
    final t = await storage.loadAllTemplates();
    if (mounted) {
      var reposChanged = false;
      for (int i = 0; i < repos.length; i++) {
        final updated = TemplateResolver.ensureTemplateFallback(repos[i], t);
        if (updated != repos[i]) {
          repos[i] = updated;
          reposChanged = true;
        }
      }
      if (reposChanged) await _persistRepos();
      _applyState(() => templates = t);
    }
  }

  Future<void> _showSnippetManager() async {
    final nameCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    String category = '自定义';
    try {
      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('片段素材库'),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (snippets.isNotEmpty) ...[
                    SizedBox(
                      height: 160,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: snippets.length,
                        itemBuilder: (_, i) {
                          final sn = snippets[i];
                          return ListTile(
                            dense: true,
                            title: Text(
                              sn.name,
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              sn.category,
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.content_copy,
                                    size: 16,
                                  ),
                                  onPressed: () {
                                    _insertText(sn.content);
                                    Navigator.pop(ctx);
                                  },
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 16,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () async {
                                    snippets.removeAt(i);
                                    await storage.saveSnippets(snippets);
                                    setDialogState(() {});
                                    if (mounted)
                                      _applyState(
                                        () =>
                                            this.snippets = List.from(snippets),
                                      );
                                  },
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
                                ),
                              ],
                            ),
                            onTap: () {
                              _insertText(sn.content);
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
                    ),
                    const Divider(),
                  ],
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '片段名称',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: const InputDecoration(
                      labelText: '分类',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: '友链模板', child: Text('友链模板')),
                      DropdownMenuItem(value: '公告片段', child: Text('公告片段')),
                      DropdownMenuItem(value: '版权声明', child: Text('版权声明')),
                      DropdownMenuItem(value: '代码块', child: Text('代码块')),
                      DropdownMenuItem(value: '自定义提示块', child: Text('自定义提示块')),
                      DropdownMenuItem(value: '自定义', child: Text('自定义')),
                    ],
                    onChanged: (v) {
                      if (v != null) category = v;
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: contentCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '片段内容',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
              FilledButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  final now = DateTime.now();
                  snippets.add(
                    SnippetItem(
                      id: now.millisecondsSinceEpoch.toString(),
                      name: nameCtrl.text.trim(),
                      content: contentCtrl.text,
                      category: category,
                      createdAt: now,
                    ),
                  );
                  await storage.saveSnippets(snippets);
                  if (mounted)
                    _applyState(() => this.snippets = List.from(snippets));
                  Navigator.pop(ctx);
                },
                child: const Text('保存片段'),
              ),
            ],
          ),
        ),
      );
    } finally {
      nameCtrl.dispose();
      contentCtrl.dispose();
    }
  }

  Future<void> _showConfigEditor() async {
    final repo = effectiveRepo;
    if (repo == null) {
      _showToast('请先配置仓库');
      return;
    }
    try {
      final configPath = repo.frameworkId == 'hugo'
          ? 'config.toml'
          : '_config.yml';
      final result = await github.getRawFile(repo, configPath);
      String content = result?['content'] ?? '';
      String sha = result?['sha'] ?? '';
      if (!mounted) return;
      final ctrl = TextEditingController(text: content);
      try {
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('${repo.frameworkId} 配置编辑'),
            content: SizedBox(
              width: 600,
              height: 400,
              child: TextField(
                controller: ctrl,
                maxLines: null,
                expands: true,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '# 站点配置文件',
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  try {
                    await github.putRawFile(
                      repo,
                      configPath,
                      ctrl.text,
                      sha: sha,
                      commitMessage: 'chore: update $configPath',
                    );
                    _showToast('配置已保存');
                    Navigator.pop(ctx, true);
                  } catch (e) {
                    _showToast('保存失败: $e');
                  }
                },
                child: const Text('保存到 GitHub'),
              ),
            ],
          ),
        );
      } finally {
        ctrl.dispose();
      }
    } catch (e) {
      _showToast('操作失败: $e');
    }
  }

  Future<void> _showSiteEditor() async {
    final repo = effectiveRepo;
    if (repo == null) {
      _showToast('请先配置仓库');
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SiteEditorScreen(
          repo: repo,
          github: github,
          onSaved: () => _showToast('站点内容已同步到 GitHub'),
        ),
      ),
    );
    if (mounted) _applyState(() {});
  }

  Future<void> _showBlogSiteManager() async {
    await Navigator.of(context).push<BlogSiteConfig?>(
      MaterialPageRoute(
        builder: (_) => BlogSiteEditorScreen(
          appSettings: settings,
          onSaved: _handleBlogSiteSaved,
        ),
      ),
    );
  }

  Future<void> _handleBlogSiteSaved(BlogSiteConfig config) async {
    final existing = List<BlogSiteConfig>.from(settings.blogSiteConfigs);
    final idx = existing.indexWhere((s) => s.id == config.id);
    if (idx >= 0) {
      existing[idx] = config;
    } else {
      existing.add(config);
    }
    await _updateSettings(settings.copyWith(blogSiteConfigs: existing));
  }

  Future<void> _showGithubTokenManager() async {
    final tokens = List<GithubTokenProfile>.from(settings.githubTokens);
    final nameCtrl = TextEditingController();
    final tokenCtrl = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Row(
              children: [
                const Expanded(
                  child: Text('GitHub 登录令牌', style: TextStyle(fontSize: 17)),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final token = tokenCtrl.text.trim();
                    if (name.isEmpty || token.isEmpty) {
                      _showToast('名称和令牌不能为空');
                      return;
                    }
                    final profile = GithubTokenProfile(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: name,
                      token: token,
                    );
                    tokens.add(profile);
                    await _updateSettings(
                      settings.copyWith(
                        github: settings.github.copyWith(
                          githubTokens: tokens,
                          activeGithubTokenId: profile.id,
                        ),
                      ),
                    );
                    nameCtrl.clear();
                    tokenCtrl.clear();
                    setDialogState(() {});
                    _showToast('已添加令牌: $name');
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加'),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tokens.isNotEmpty) ...[
                    SizedBox(
                      height: 160,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: tokens.length,
                        itemBuilder: (_, i) {
                          final t = tokens[i];
                          final isActive = settings.activeGithubTokenId == t.id;
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              isActive ? Icons.check_circle : Icons.key,
                              size: 18,
                              color: isActive
                                  ? Theme.of(ctx).colorScheme.primary
                                  : null,
                            ),
                            title: Text(
                              t.name,
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              t.token.length > 8
                                  ? '${t.token.substring(0, 8)}...'
                                  : t.token,
                              style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isActive)
                                  TextButton(
                                    onPressed: () async {
                                      await _updateSettings(
                                        settings.copyWith(
                                          github: settings.github.copyWith(
                                            activeGithubTokenId: t.id,
                                          ),
                                        ),
                                      );
                                      setDialogState(() {});
                                    },
                                    child: const Text(
                                      '启用',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 16,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () async {
                                    tokens.removeAt(i);
                                    await _updateSettings(
                                      settings.copyWith(
                                        github: settings.github.copyWith(
                                          githubTokens: tokens,
                                        ),
                                      ),
                                    );
                                    setDialogState(() {});
                                  },
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(),
                  ],
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '令牌名称',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: tokenCtrl,
                    decoration: const InputDecoration(
                      labelText: 'GitHub Token',
                      isDense: true,
                    ),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      );
    } finally {
      nameCtrl.dispose();
      tokenCtrl.dispose();
    }
  }

  Future<void> _showRepoManager() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SiteManagementScreen(
          siteManager: siteManager,
          repos: repos,
          onChanged: () async {
            await _updateSettings(settings);
          },
        ),
      ),
    );
  }

  void _showSiteOperations() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SiteOperationsScreen(repos: repos, onToast: _showToast),
      ),
    );
  }
}
