// 编辑器设置/管理弹窗扩展（由 main.dart part 引入，与原类同 library，可访问私有成员）
part of '../main.dart';

extension SettingsDialogsExt on _RootShellState {
  Future<bool> _showExitDialog() async {
    final hasChanges = _doc.hasUnsavedChanges;
    if (!hasChanges) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认退出'),
          content: const Text('确认退出当前文章？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认退出'),
            ),
          ],
        ),
      );
      return ok == true;
    }

    // 有未保存改动
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('是否退出当前文章？'),
        content: const Text('检测到未保存的改动，请选择处理方式：'),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, 'publish'),
                icon: const Icon(Icons.cloud_upload, size: 18),
                label: const Text('保存并发布'),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'save'),
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('仅本地保存，暂不发布'),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'discard'),
                child: const Text(
                  '放弃修改，直接退出',
                  style: TextStyle(color: Colors.red),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('取消'),
              ),
            ],
          ),
        ],
      ),
    );
    if (result == null || result == 'cancel') return false;

    switch (result) {
      case 'publish':
        await _publish();
        break;
      case 'save':
        await _saveLocal();
        break;
      case 'discard':
        break;
    }
    return true;
  }

  Future<void> _updateSettings(AppSettings s) async {
    _applyState(() => settings = s);
    _updateSystemBarStyle();
    _updateSiteManager();
    _startAutoSync(); // 重启自动同步（间隔/开关可能变化）
    // 壁纸变化时刷新自动字色
    _refreshWallpaperBrightness();
    // 同步全局统一存储目录 / SAF 导出文件夹
    storage.setCustomRoot(s.storageRootDir);
    storage.setExternalSafUri(s.externalSafUri);
    await storage.saveSettings(s);
    widget.onThemeChanged(Color(s.themeColor));
    // 通知父 widget 重建 MaterialApp（DesignConfig 变化时主题实时更新）
    widget.onSettingsChanged?.call(s);
  }

  Future<void> _showWebDavDialog() async {
    final c = TextEditingController(text: settings.webdavUrl);
    final u = TextEditingController(text: settings.webdavUsername);
    final pw = TextEditingController(text: settings.webdavPassword);
    final f = TextEditingController(text: settings.webdavFolder);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
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
        );
      },
    );
    c.dispose();
    u.dispose();
    pw.dispose();
    f.dispose();
    if (mounted) _applyState(() {});
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
          onSaved: () => _showToast('站点内容已同步到 GitHub，稍后自动部署'),
        ),
      ),
    );
    if (mounted) _applyState(() {});
  }

  /// 打开动态 CMS 站点管理页面
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

  Future<void> _showAiManager() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final profiles = List<AiProfile>.from(settings.aiProfiles);
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.75,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'AI 中转站配置',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final created = await _editAiProfile(null);
                            if (created != null) {
                              final list = List<AiProfile>.from(
                                settings.aiProfiles,
                              )..add(created);
                              settings = settings.copyWith(
                                aiProfiles: list,
                                activeAiProfileId: created.id,
                                aiBaseUrl: created.baseUrl,
                                aiApiKey: created.apiKey,
                                aiModel: created.model,
                                aiProvider: created.name,
                              );
                              await _persistSettings();
                              setModal(() {});
                              if (mounted) _applyState(() {});
                              _showToast('已保存配置');
                            }
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('新增'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '填写 Base URL + API Key，点「获取模型」选择模型后保存。可保存多套并任意切换。',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: profiles.isEmpty
                          ? const Center(child: Text('暂无配置，点右上角新增'))
                          : ListView.separated(
                              itemCount: profiles.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final p = profiles[i];
                                final active =
                                    settings.activeAiProfileId == p.id;
                                return Card(
                                  child: ListTile(
                                    leading: Icon(
                                      active
                                          ? Icons.check_circle
                                          : Icons.smart_toy_outlined,
                                      color: active
                                          ? Theme.of(ctx).colorScheme.primary
                                          : null,
                                    ),
                                    title: Text(p.displayLabel),
                                    subtitle: Text(
                                      '${p.baseUrl}\n模型: ${p.model.isEmpty ? "未选" : p.model}',
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    isThreeLine: true,
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (v) async {
                                        if (v == 'use') {
                                          settings = settings.copyWith(
                                            activeAiProfileId: p.id,
                                            aiBaseUrl: p.baseUrl,
                                            aiApiKey: p.apiKey,
                                            aiModel: p.model,
                                            aiProvider: p.name,
                                          );
                                          await _persistSettings();
                                          setModal(() {});
                                          if (mounted) _applyState(() {});
                                          _showToast('已切换到 ${p.displayLabel}');
                                        } else if (v == 'edit') {
                                          final edited = await _editAiProfile(
                                            p,
                                          );
                                          if (edited != null) {
                                            final list = List<AiProfile>.from(
                                              settings.aiProfiles,
                                            );
                                            final ix = list.indexWhere(
                                              (e) => e.id == p.id,
                                            );
                                            if (ix >= 0) list[ix] = edited;
                                            final activeId =
                                                settings.activeAiProfileId ==
                                                    p.id
                                                ? edited.id
                                                : settings.activeAiProfileId;
                                            settings = settings.copyWith(
                                              aiProfiles: list,
                                              activeAiProfileId: activeId,
                                              aiBaseUrl: activeId == edited.id
                                                  ? edited.baseUrl
                                                  : settings.aiBaseUrl,
                                              aiApiKey: activeId == edited.id
                                                  ? edited.apiKey
                                                  : settings.aiApiKey,
                                              aiModel: activeId == edited.id
                                                  ? edited.model
                                                  : settings.aiModel,
                                              aiProvider: activeId == edited.id
                                                  ? edited.name
                                                  : settings.aiProvider,
                                            );
                                            await _persistSettings();
                                            setModal(() {});
                                            if (mounted) _applyState(() {});
                                          }
                                        } else if (v == 'delete') {
                                          final ok = await _confirm(
                                            '删除配置「${p.name}」？',
                                          );
                                          if (!ok) return;
                                          final list = List<AiProfile>.from(
                                            settings.aiProfiles,
                                          )..removeWhere((e) => e.id == p.id);
                                          var activeId =
                                              settings.activeAiProfileId;
                                          if (activeId == p.id) {
                                            activeId = list.isNotEmpty
                                                ? list.first.id
                                                : '';
                                          }
                                          AiProfile? activeP;
                                          for (final e in list) {
                                            if (e.id == activeId) {
                                              activeP = e;
                                              break;
                                            }
                                          }
                                          if (activeP == null &&
                                              list.isNotEmpty) {
                                            activeP = list.first;
                                            activeId = activeP.id;
                                          }
                                          settings = settings.copyWith(
                                            aiProfiles: list,
                                            activeAiProfileId: activeId,
                                            aiBaseUrl:
                                                activeP?.baseUrl ??
                                                settings.aiBaseUrl,
                                            aiApiKey: activeP?.apiKey ?? '',
                                            aiModel:
                                                activeP?.model ??
                                                settings.aiModel,
                                            aiProvider:
                                                activeP?.name ??
                                                settings.aiProvider,
                                          );
                                          await _persistSettings();
                                          setModal(() {});
                                          if (mounted) _applyState(() {});
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'use',
                                          child: Text('设为当前'),
                                        ),
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('编辑'),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('删除'),
                                        ),
                                      ],
                                    ),
                                    onTap: () async {
                                      settings = settings.copyWith(
                                        activeAiProfileId: p.id,
                                        aiBaseUrl: p.baseUrl,
                                        aiApiKey: p.apiKey,
                                        aiModel: p.model,
                                        aiProvider: p.name,
                                      );
                                      await _persistSettings();
                                      setModal(() {});
                                      if (mounted) _applyState(() {});
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showGithubTokenManager() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final tokens = List<GithubTokenProfile>.from(settings.githubTokens);
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.75,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'GitHub 登录令牌',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final created = await _editGithubToken(null);
                            if (created != null) {
                              await _upsertGithubToken(
                                created,
                                makeActive: true,
                              );
                              setModal(() {});
                              if (mounted) _applyState(() {});
                              _showToast('已保存 ${created.displayLabel}');
                            }
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('登录'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Token 仅保存在本机。登录后可在多仓库间复用，也可随时切换当前令牌。',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: tokens.isEmpty
                          ? const Center(child: Text('暂无已登录令牌，点右上角登录'))
                          : ListView.separated(
                              itemCount: tokens.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final t = tokens[i];
                                final active =
                                    settings.activeGithubTokenId == t.id;
                                return Card(
                                  child: ListTile(
                                    leading: Icon(
                                      active
                                          ? Icons.check_circle
                                          : Icons.key_outlined,
                                      color: active
                                          ? Theme.of(ctx).colorScheme.primary
                                          : null,
                                    ),
                                    title: Text(t.displayLabel),
                                    subtitle: Text(
                                      [
                                        t.provider.label,
                                        if (t.login.isNotEmpty) '@${t.login}',
                                        t.maskedToken,
                                        if (t.lastVerifiedAt != null)
                                          '验证于 ${t.lastVerifiedAt!.toLocal().toString().substring(0, 16)}',
                                      ].join(' · '),
                                    ),
                                    isThreeLine: t.lastVerifiedAt != null,
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (v) async {
                                        if (v == 'use') {
                                          await _activateGithubToken(t.id);
                                          setModal(() {});
                                        } else if (v == 'edit') {
                                          final edited = await _editGithubToken(
                                            t,
                                          );
                                          if (edited != null) {
                                            await _upsertGithubToken(
                                              edited,
                                              makeActive:
                                                  settings
                                                      .activeGithubTokenId ==
                                                  t.id,
                                            );
                                            setModal(() {});
                                          }
                                        } else if (v == 'verify') {
                                          try {
                                            final user = await github.getUser(
                                              t.token,
                                              provider: t.provider,
                                            );
                                            final login =
                                                user['login']?.toString() ?? '';
                                            await _upsertGithubToken(
                                              t.copyWith(
                                                login: login,
                                                avatarUrl:
                                                    user['avatar_url']
                                                        ?.toString() ??
                                                    '',
                                                htmlUrl:
                                                    user['html_url']
                                                        ?.toString() ??
                                                    '',
                                                lastVerifiedAt: DateTime.now(),
                                                name:
                                                    t.name.isEmpty ||
                                                        t.name == '默认 Token' ||
                                                        t.name == 'GitHub Token'
                                                    ? (login.isNotEmpty
                                                          ? login
                                                          : t.name)
                                                    : t.name,
                                              ),
                                              makeActive: active,
                                            );
                                            setModal(() {});
                                            _showToast(
                                              login.isEmpty
                                                  ? 'Token 有效'
                                                  : '有效 · @$login',
                                            );
                                          } catch (e) {
                                            _showToast('校验失败: $e');
                                          }
                                        } else if (v == 'delete') {
                                          final ok = await _confirm(
                                            '删除已保存令牌「${t.displayLabel}」？',
                                          );
                                          if (!ok) return;
                                          final list =
                                              List<GithubTokenProfile>.from(
                                                settings.githubTokens,
                                              )..removeWhere(
                                                (e) => e.id == t.id,
                                              );
                                          var activeId =
                                              settings.activeGithubTokenId;
                                          if (activeId == t.id) {
                                            activeId = list.isNotEmpty
                                                ? list.first.id
                                                : '';
                                          }
                                          final activeToken = list.isEmpty
                                              ? ''
                                              : list
                                                    .firstWhere(
                                                      (e) => e.id == activeId,
                                                      orElse: () => list.first,
                                                    )
                                                    .token;
                                          settings = settings.copyWith(
                                            githubTokens: list,
                                            activeGithubTokenId: activeId,
                                            defaultToken: activeToken,
                                          );
                                          await _persistSettings();
                                          setModal(() {});
                                          if (mounted) _applyState(() {});
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'use',
                                          child: Text('设为当前'),
                                        ),
                                        PopupMenuItem(
                                          value: 'verify',
                                          child: Text('验证'),
                                        ),
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('编辑'),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('删除'),
                                        ),
                                      ],
                                    ),
                                    onTap: () async {
                                      await _activateGithubToken(t.id);
                                      setModal(() {});
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showRepoManager() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                top: 8,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.75,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '多仓库管理',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () async {
                            await _editRepo();
                            setModal(() {});
                            _applyState(() {});
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('添加'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: repos.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final r = repos[i];
                          final active = activeRepo?.id == r.id;
                          return Card(
                            child: ListTile(
                              leading: Icon(
                                active
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: active
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              title: Text(r.name),
                              subtitle: Text(
                                '${r.fullName} @ ${r.branch}\n'
                                '${BlogFramework.byId(r.frameworkId)?.name ?? r.frameworkId} | '
                                '文章: ${r.postsPath} | 页面: ${r.pagesPath}\n'
                                '${TemplateResolver.describeRepoDefaults(r, templates)}',
                              ),
                              isThreeLine: false,
                              dense: false,
                              onTap: () async {
                                settings = settings.copyWith(
                                  activeRepoId: r.id,
                                );
                                await _persistSettings();
                                remotePosts = [];
                                commits = [];
                                _applyState(() {});
                                setModal(() {});
                                if (ctx.mounted) Navigator.pop(ctx);
                              },
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'edit') {
                                    await _editRepo(existing: r);
                                  } else if (v == 'delete') {
                                    final ok = await _confirm(
                                      '删除仓库配置「${r.name}」？',
                                    );
                                    if (ok) {
                                      repos.removeWhere((e) => e.id == r.id);
                                      await _persistRepos();
                                      if (settings.activeRepoId == r.id) {
                                        settings = settings.copyWith(
                                          activeRepoId: repos.isEmpty
                                              ? ''
                                              : repos.first.id,
                                        );
                                        await _persistSettings();
                                      }
                                    }
                                  }
                                  setModal(() {});
                                  _applyState(() {});
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('编辑'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (mounted) _applyState(() {});
  }

  void _showTemplateManager() async {
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
    // 刷新模板列表
    final t = await storage.loadAllTemplates();
    if (mounted) {
      // 模板变更后检查降级
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

  void _showSnippetManager() async {
    // 片段管理器 - 跳转到片段管理对话框
    _showSnippetDialog();
  }

  void _showSnippetDialog() {
    final nameCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    String category = '自定义';
    try {
      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('片段素材库'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 已有片段列表
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
                                      if (mounted) {
                                        _applyState(
                                          () => this.snippets = List.from(
                                            snippets,
                                          ),
                                        );
                                      }
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
                    // 新增片段
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
                        DropdownMenuItem(
                          value: '自定义提示块',
                          child: Text('自定义提示块'),
                        ),
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
            );
          },
        ),
      );
    } finally {
      nameCtrl.dispose();
      contentCtrl.dispose();
    }
  }

  void _showConfigEditor() async {
    final repo = effectiveRepo;
    if (repo == null) {
      _showToast('请先配置仓库');
      return;
    }
    try {
      // 尝试读取 _config.yml
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
              width: double.maxFinite,
              height: 400,
              child: TextField(
                controller: ctrl,
                maxLines: null,
                expands: true,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
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
                child: const Text('保存到GitHub'),
              ),
            ],
          ),
        );
      } finally {
        ctrl.dispose();
      }
    } catch (e) {
      _showToast('读取配置失败: $e');
    }
  }

  void _showAiModelManager() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiModelManagerScreen(
          modelManager: aiModelManager,
          aiService: aiService,
          settings: settings,
          onSettingsChanged: _updateSettings,
        ),
      ),
    );
  }

  void _showSiteConfigEditor() {
    _showConfigEditor();
  }
}
