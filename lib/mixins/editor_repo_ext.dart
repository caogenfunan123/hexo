// 仓库/Token 管理扩展（由 main.dart part 引入，与原类同 library，可访问私有成员）
part of '../main.dart';

extension EditorRepoExt on _RootShellState {
  /// 处理动态 CMS 站点保存
  Future<void> _handleBlogSiteSaved(BlogSiteConfig config) async {
    final existing = List<BlogSiteConfig>.from(settings.blogSiteConfigs);
    final idx = existing.indexWhere((s) => s.id == config.id);
    if (idx >= 0) {
      existing[idx] = config;
    } else {
      existing.add(config);
    }
    final updated = settings.copyWith(blogSiteConfigs: existing);
    await _updateSettings(updated);
  }

  Future<void> _activateGithubToken(String id) async {
    GithubTokenProfile? profile;
    for (final t in settings.githubTokens) {
      if (t.id == id) {
        profile = t;
        break;
      }
    }
    if (profile == null) return;
    settings = settings.copyWith(
      activeGithubTokenId: profile.id,
      defaultToken: profile.token,
    );
    await _persistSettings();
    final repo = activeRepo;
    if (repo != null && repo.token.isEmpty) {
      final i = repos.indexWhere((e) => e.id == repo.id);
      if (i >= 0) {
        repos[i] = repo.copyWith(token: profile.token);
        await _persistRepos();
      }
    }
    if (mounted) _applyState(() {});
    _showToast('已切换到 ${profile.displayLabel}');
  }

  Future<void> _upsertGithubToken(
    GithubTokenProfile profile, {
    bool makeActive = false,
  }) async {
    final list = List<GithubTokenProfile>.from(settings.githubTokens);
    final byToken = list.indexWhere((e) => e.token == profile.token);
    final byId = list.indexWhere((e) => e.id == profile.id);
    if (byId >= 0) {
      list[byId] = profile;
    } else if (byToken >= 0) {
      list[byToken] = profile.copyWith(id: list[byToken].id);
    } else {
      list.add(profile);
    }
    final activeId = makeActive || settings.activeGithubTokenId.isEmpty
        ? (byId >= 0
              ? profile.id
              : byToken >= 0
              ? list[byToken].id
              : profile.id)
        : settings.activeGithubTokenId;
    GithubTokenProfile? active;
    for (final t in list) {
      if (t.id == activeId) {
        active = t;
        break;
      }
    }
    active ??= list.isNotEmpty ? list.first : null;
    settings = settings.copyWith(
      githubTokens: list,
      activeGithubTokenId: active?.id ?? '',
      defaultToken: active?.token ?? settings.defaultToken,
    );
    await _persistSettings();
    if (mounted) _applyState(() {});
  }

  Future<GithubTokenProfile?> _editGithubToken(
    GithubTokenProfile? existing,
  ) async {
    final nameCtrl = TextEditingController(
      text: existing?.name.isNotEmpty == true
          ? existing!.name
          : (existing?.login.isNotEmpty == true
                ? existing!.login
                : 'GitHub Token'),
    );
    final tokenCtrl = TextEditingController(text: existing?.token ?? '');
    var verifying = false;
    String? err;
    String login = existing?.login ?? '';
    String avatarUrl = existing?.avatarUrl ?? '';
    String htmlUrl = existing?.htmlUrl ?? '';

    return showDialog<GithubTokenProfile>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            Future<void> verifyAndFill() async {
              final token = tokenCtrl.text.trim();
              if (token.isEmpty) {
                setDlg(() => err = '请先填写 Token');
                return;
              }
              setDlg(() {
                verifying = true;
                err = null;
              });
              try {
                final user = await github.getUser(token);
                login = user['login']?.toString() ?? '';
                avatarUrl = user['avatar_url']?.toString() ?? '';
                htmlUrl = user['html_url']?.toString() ?? '';
                if (nameCtrl.text.trim().isEmpty ||
                    nameCtrl.text.trim() == 'GitHub Token' ||
                    nameCtrl.text.trim() == '默认 Token') {
                  if (login.isNotEmpty) nameCtrl.text = login;
                }
                setDlg(() => verifying = false);
                _showToast(login.isEmpty ? 'Token 有效' : '验证成功 · @$login');
              } catch (e) {
                setDlg(() {
                  verifying = false;
                  err = e.toString();
                });
              }
            }

            return AlertDialog(
              title: Text(existing == null ? '登录 GitHub Token' : '编辑 Token'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: '备注名称',
                          hintText: '如 主账号 / 图床专用',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: tokenCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'GitHub Token',
                          hintText: 'ghp_... 或 fine-grained token',
                          helperText: '需要 contents:read/write 权限',
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (login.isNotEmpty)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.account_circle_outlined),
                          title: Text('@$login'),
                          subtitle: Text(htmlUrl.isEmpty ? '已验证' : htmlUrl),
                        ),
                      if (err != null)
                        Text(
                          err!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonalIcon(
                          onPressed: verifying ? null : verifyAndFill,
                          icon: verifying
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.verified_user_outlined),
                          label: Text(verifying ? '验证中…' : '验证并识别账号'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: verifying
                      ? null
                      : () async {
                          final token = tokenCtrl.text.trim();
                          if (token.isEmpty) {
                            _showToast('请填写 Token');
                            return;
                          }
                          if (login.isEmpty) {
                            try {
                              final user = await github.getUser(token);
                              login = user['login']?.toString() ?? '';
                              avatarUrl = user['avatar_url']?.toString() ?? '';
                              htmlUrl = user['html_url']?.toString() ?? '';
                            } catch (e) {
                              final force = await _confirm(
                                'Token 校验失败：\n$e\n\n仍要保存吗？',
                              );
                              if (!force) return;
                            }
                          }
                          final name = nameCtrl.text.trim().isEmpty
                              ? (login.isNotEmpty ? login : 'GitHub Token')
                              : nameCtrl.text.trim();
                          Navigator.pop(
                            ctx,
                            GithubTokenProfile(
                              id:
                                  existing?.id ??
                                  'gh_${DateTime.now().millisecondsSinceEpoch}',
                              name: name,
                              token: token,
                              login: login,
                              avatarUrl: avatarUrl,
                              htmlUrl: htmlUrl,
                              lastVerifiedAt: login.isNotEmpty
                                  ? DateTime.now()
                                  : existing?.lastVerifiedAt,
                            ),
                          );
                        },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editRepo({RepoConfig? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final owner = TextEditingController(
      text: existing?.owner ?? 'caogenfunan123',
    );
    final repo = TextEditingController(text: existing?.repo ?? 'xiamend');
    final branch = TextEditingController(text: existing?.branch ?? 'main');
    final posts = TextEditingController(
      text: existing?.postsPath ?? 'source/_posts',
    );
    final pages = TextEditingController(text: existing?.pagesPath ?? 'source');
    final site = TextEditingController(
      text: existing?.siteUrl.isNotEmpty == true ? existing!.siteUrl : '',
    );
    final token = TextEditingController(
      text: existing?.token.isNotEmpty == true
          ? existing!.token
          : settings.effectiveGithubToken,
    );
    String frameworkId = existing?.frameworkId ?? 'hexo';
    final String originalFrameworkId = existing?.frameworkId ?? 'hexo';
    int publishTimeZoneOffsetMinutes =
        existing?.publishTimeZoneOffsetMinutes ?? 480;
    bool postDatePrefix = existing?.fileNameRule.postDatePrefix ?? false;
    // 镜像仓库：每行 owner/repo|branch|token，同一文章同步推送
    final mirrorsCtrl = TextEditingController(
      text: (existing?.mirrorRemotes ?? const [])
          .map((m) =>
              '${m.fullName}|${m.branch.isEmpty ? 'main' : m.branch}|${m.token}')
          .join('\n'),
    );
    String? selectedTokenId = settings.activeGithubTokenId;
    if (existing?.token.isNotEmpty == true) {
      for (final t in settings.githubTokens) {
        if (t.token == existing!.token) {
          selectedTokenId = t.id;
          break;
        }
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            return AlertDialog(
              title: Text(existing == null ? '添加仓库' : '编辑仓库'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── 博客框架选择 ──
                    DropdownButtonFormField<String>(
                      value: frameworkId,
                      decoration: const InputDecoration(
                        labelText: '博客框架',
                        prefixIcon: Icon(Icons.web, size: 18),
                      ),
                      items: [
                        ...BlogFramework.presets.map(
                          (f) => DropdownMenuItem(
                            value: f.id,
                            child: Text('${f.name} (${f.defaultPostsPath})'),
                          ),
                        ),
                        const DropdownMenuItem(
                          value: 'custom',
                          child: Text('自定义'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setDlg(() {
                          frameworkId = v;
                          if (v != 'custom') {
                            final fw = BlogFramework.byId(v);
                            if (fw != null) {
                              posts.text = fw.defaultPostsPath;
                              pages.text = fw.defaultPagesPath;
                              postDatePrefix = fw.postDatePrefix;
                            }
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    // ── 发布时区选择 ──
                    DropdownButtonFormField<int>(
                      value: publishTimeZoneOffsetMinutes,
                      decoration: const InputDecoration(
                        labelText: '发布时区',
                        helperText:
                            'Front Matter 日期带该时区偏移，避免 Cloudflare(UTC) 构建日期错位',
                        prefixIcon: Icon(Icons.schedule, size: 18),
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('UTC (UTC+0)')),
                        DropdownMenuItem(value: 480, child: Text('北京 (UTC+8)')),
                        DropdownMenuItem(value: 540, child: Text('东京 (UTC+9)')),
                        DropdownMenuItem(
                          value: 600,
                          child: Text('悉尼 (UTC+10)'),
                        ),
                        DropdownMenuItem(
                          value: -300,
                          child: Text('纽约 (UTC-5)'),
                        ),
                        DropdownMenuItem(
                          value: -480,
                          child: Text('洛杉矶 (UTC-8)'),
                        ),
                        DropdownMenuItem(
                          value: 330,
                          child: Text('孟买 (UTC+5:30)'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDlg(() => publishTimeZoneOffsetMinutes = v);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: '显示名称'),
                    ),
                    TextField(
                      controller: owner,
                      decoration: const InputDecoration(labelText: 'Owner'),
                    ),
                    TextField(
                      controller: repo,
                      decoration: const InputDecoration(labelText: 'Repo'),
                    ),
                    TextField(
                      controller: branch,
                      decoration: const InputDecoration(labelText: 'Branch'),
                    ),
                    // ── 双目录配置 ──
                    TextField(
                      controller: posts,
                      decoration: const InputDecoration(
                        labelText: '博文目录 (posts)',
                        helperText: '例如: source/_posts, content/posts',
                      ),
                    ),
                    TextField(
                      controller: pages,
                      decoration: const InputDecoration(
                        labelText: '页面目录 (pages)',
                        helperText: '例如: source, content',
                      ),
                    ),
                    // ── 文件名规则 ──
                    CheckboxListTile(
                      title: const Text('博文自动日期前缀'),
                      subtitle: const Text('2026-08-02-title.md (Jekyll/Hugo)'),
                      value: postDatePrefix,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) =>
                          setDlg(() => postDatePrefix = v ?? false),
                    ),
                    TextField(
                      controller: site,
                      decoration: const InputDecoration(labelText: '站点 URL'),
                    ),
                    if (settings.githubTokens.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value:
                            settings.githubTokens.any(
                              (e) => e.id == selectedTokenId,
                            )
                            ? selectedTokenId
                            : null,
                        decoration: const InputDecoration(
                          labelText: '选用已登录 Token',
                          helperText: '可选择已保存令牌，或下方手动填写',
                        ),
                        items: [
                          ...settings.githubTokens.map(
                            (t) => DropdownMenuItem(
                              value: t.id,
                              child: Text(
                                t.displayLabel,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          final t = settings.githubTokens.firstWhere(
                            (e) => e.id == v,
                          );
                          setDlg(() {
                            selectedTokenId = t.id;
                            token.text = t.token;
                          });
                        },
                      ),
                    ],
                    TextField(
                      controller: token,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'GitHub Token',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: mirrorsCtrl,
                      maxLines: 4,
                      minLines: 2,
                      decoration: const InputDecoration(
                        labelText: '镜像仓库（可选）',
                        helperText:
                            '每行一个: owner/repo|branch|token，发布时同步推送到该远程（如 Gitee）',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;

    final tokenValue = token.text.trim();

    // ── 框架变更弹窗询问 ──
    bool updateTemplates = true;
    if (existing != null && frameworkId != originalFrameworkId) {
      updateTemplates =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('框架已变更'),
              content: Text(
                '当前仓库框架从 $originalFrameworkId 变更为 $frameworkId，\n是否更新仓库默认文章/页面模板？',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('保持现有模板不变'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('更新默认模板'),
                ),
              ],
            ),
          ) ??
          true;
    }

    // 自动绑定框架默认模板
    String? defaultPostId = existing?.defaultPostTemplateId;
    String? defaultPageId = existing?.defaultPageTemplateId;
    if (existing == null || updateTemplates) {
      defaultPostId = RepoConfig.defaultPostTemplateForFramework(frameworkId);
      defaultPageId = RepoConfig.defaultPageTemplateForFramework(frameworkId);
    }

    // 解析镜像仓库行：owner/repo|branch|token
    final mirrors = <RepoMirror>[];
    for (final raw in mirrorsCtrl.text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final parts = line.split('|');
      if (parts.isEmpty || !parts[0].contains('/')) continue;
      final full = parts[0].trim();
      final slash = full.indexOf('/');
      if (slash <= 0 || slash == full.length - 1) continue;
      mirrors.add(RepoMirror(
        owner: full.substring(0, slash).trim(),
        repo: full.substring(slash + 1).trim(),
        branch: (parts.length > 1 ? parts[1].trim() : 'main').isEmpty
            ? 'main'
            : parts[1].trim(),
        token: parts.length > 2 ? parts[2].trim() : '',
      ));
    }

    final cfg = RepoConfig(
      id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.text.trim().isEmpty ? repo.text.trim() : name.text.trim(),
      owner: owner.text.trim(),
      repo: repo.text.trim(),
      branch: branch.text.trim().isEmpty ? 'main' : branch.text.trim(),
      postsPath: posts.text.trim().isEmpty
          ? 'source/_posts'
          : posts.text.trim(),
      pagesPath: pages.text.trim().isEmpty ? 'source' : pages.text.trim(),
      frameworkId: frameworkId,
      postDatePrefix: postDatePrefix,
      fileNameRule: FileNameRule(
        postDatePrefix: postDatePrefix,
        dateFormat: existing?.fileNameRule.dateFormat ?? 'yyyy-MM-dd',
      ),
      siteUrl: site.text.trim(),
      token: tokenValue,
      isDefault: existing?.isDefault ?? repos.isEmpty,
      defaultPostTemplateId: defaultPostId,
      defaultPageTemplateId: defaultPageId,
      publishTimeZoneOffsetMinutes: publishTimeZoneOffsetMinutes,
      mirrorRemotes: mirrors,
    );
    if (existing == null) {
      repos.add(cfg);
      if (settings.activeRepoId.isEmpty) {
        settings = settings.copyWith(activeRepoId: cfg.id);
        await _persistSettings();
      }
    } else {
      final i = repos.indexWhere((e) => e.id == existing.id);
      if (i >= 0) repos[i] = cfg;
    }
    await _persistRepos();

    if (tokenValue.isNotEmpty) {
      final exists = settings.githubTokens.any((e) => e.token == tokenValue);
      if (!exists) {
        await _upsertGithubToken(
          GithubTokenProfile(
            id: 'gh_${DateTime.now().millisecondsSinceEpoch}',
            name: '仓库 ${cfg.name}',
            token: tokenValue,
          ),
          makeActive: settings.githubTokens.isEmpty,
        );
      } else {
        final pickedTokenId = selectedTokenId;
        if (pickedTokenId != null && pickedTokenId.isNotEmpty) {
          await _activateGithubToken(pickedTokenId);
        }
      }
    }

    if (mounted) _applyState(() {});
  }

  Future<void> _showCommitActions(GitCommitItem c) async {
    final pathController = TextEditingController(
      text: activeRepo == null ? 'source/_posts/' : '${activeRepo!.postsPath}/',
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提交详情 / 回滚'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.message),
            const SizedBox(height: 8),
            Text(
              '${c.sha}\n${c.author} · ${_fmt(c.date)}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pathController,
              decoration: const InputDecoration(
                labelText: '要回滚的文件路径',
                hintText: 'source/_posts/hello-world.md',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _doRollback(pathController.text.trim(), c.sha);
            },
            child: const Text('回滚该文件'),
          ),
        ],
      ),
    );
  }

  Future<void> _rollbackFile(String path) async {
    if (commits.isEmpty) await _refreshCommits();
    if (commits.isEmpty) {
      _showToast('无提交历史');
      return;
    }
    final sha = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView.builder(
        itemCount: commits.length,
        itemBuilder: (_, i) {
          final c = commits[i];
          return ListTile(
            title: Text(c.message.split('\n').first, maxLines: 1),
            subtitle: Text('${c.sha.substring(0, 7)} · ${_fmt(c.date)}'),
            onTap: () => Navigator.pop(ctx, c.sha),
          );
        },
      ),
    );
    if (sha != null) await _doRollback(path, sha);
  }

  Future<void> _doRollback(String path, String sha) async {
    final repo = effectiveRepo;
    if (repo == null) return;
    if (path.isEmpty) {
      _showToast('路径不能为空');
      return;
    }
    final ok = await _confirm('将 $path 恢复为 $sha 的内容并新建提交？');
    if (!ok) return;
    _applyState(() => busy = true);
    try {
      final article = await github.rollbackFile(repo, path, sha);
      _showToast('回滚成功: ${article.remotePath}');
      await _refreshRemote();
      await _refreshCommits();
    } catch (e) {
      _showToast('回滚失败: $e');
    } finally {
      if (mounted) _applyState(() => busy = false);
    }
  }

  /// 打开 CMS 远程文章到编辑器（多站点：先切换到文章所属站点）
  void _openRemotePostInEditor(BlogPost post) {
    // 静态站点文章：走 GitHub 文件加载链路
    if (post.siteId != null) {
      final identity = siteManager.getSiteIdentity(post.siteId!);
      if (identity != null && identity.isStatic) {
        _openStaticBlogPostInEditor(post);
        return;
      }
    }
    // 关闭抽屉
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.pop(context);
    }
    // 多站点模式下，切换到文章所属站点，确保后续发布到正确站点
    if (post.siteId != null && siteManager.activeSiteId != post.siteId) {
      final identity = siteManager.getSiteIdentity(post.siteId!);
      if (identity != null && identity.isDynamic) {
        siteManager.setActiveSite(post.siteId!);
      }
    }
    // 将 BlogPost 转为 Article 加载到编辑器
    final article = Article(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
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
    );
    _doc.setCurrentArticle(article);
    _editorRepo = null; // CMS 文章不使用 Git 仓库
    _doc.setEditorRepoId(null);
    _startAutoSave();
    _saveSession(SessionPageType.editor);
    _applyState(() => _currentPage = 0);
    _updateSystemBarStyle();
    logService.add('加载远程文章', '标题: ${post.title}');
    if (mounted) _showToast('已加载远程文章: ${post.title}');
  }

  /// 删除 CMS 远程文章（多站点：按文章所属站点解析适配器）
  Future<void> _deleteRemoteCmsPost(BlogPost post) async {
    // 静态站点文章无数字 id，需走 GitHub 文件删除链路
    if (post.siteId != null) {
      final identity = siteManager.getSiteIdentity(post.siteId!);
      if (identity != null && identity.isStatic) {
        await _deleteStaticBlogPost(post);
        return;
      }
    }
    if (post.id == null) {
      throw Exception('该文章缺少远程 ID，无法删除');
    }
    BlogRepository? adapter;
    if (post.siteId != null) {
      adapter = siteManager.getAdapter(post.siteId!);
    }
    adapter ??= siteManager.currentAdapter;
    if (adapter == null) return;
    try {
      await adapter.deletePost(post.id!);
      logService.add(
        '删除远程文章',
        '已从 ${adapter.config.type.name} 删除: ${post.title}',
      );
      if (mounted) _showToast('已删除: ${post.title}');
    } catch (e) {
      logService.add('删除远程文章失败', '$e', success: false);
      rethrow;
    }
  }

  Future<void> _deleteRemotePost(GitHubFileItem item) async {
    final repo = effectiveRepo;
    if (repo == null) return;
    final ok = await _confirm('确认删除远程文章 ${item.path}？此操作会提交到 GitHub，不可撤销。');
    if (!ok) return;
    _applyState(() => busy = true);
    try {
      final article = await github.getArticle(repo, item);
      await github.deleteArticle(repo, article);
      final idx = drafts.indexWhere(
        (d) => d.remotePath == item.path || d.fileName == item.name,
      );
      if (idx >= 0) {
        drafts[idx] = drafts[idx].copyWith(
          isDraft: true,
          published: false,
          remotePath: null,
          remoteSha: null,
        );
        await storage.saveDrafts(drafts);
      }
      _showToast('已删除远程文章');
      await _refreshRemote();
      await _refreshCommits();
    } catch (e) {
      _showToast('删除失败: $e');
    } finally {
      if (mounted) _applyState(() => busy = false);
    }
  }

  Future<void> _batchDeleteRemote(List<GitHubFileItem> items) async {
    final ok = await _confirm('确认批量删除 ${items.length} 篇远程文章？此操作不可撤销。');
    if (!ok) return;
    _applyState(() => busy = true);
    int success = 0;
    int fail = 0;
    for (final item in items) {
      try {
        final repo = effectiveRepo;
        if (repo == null) continue;
        final article = await github.getArticle(repo, item);
        await github.deleteArticle(repo, article);
        success++;
      } catch (e) {
        debugPrint('App: site data load failed: $e');
        fail++;
      }
    }
    await _refreshRemote();
    await _refreshCommits();
    if (mounted) {
      _applyState(() => busy = false);
      _showToast('删除完成: $success 成功, $fail 失败');
    }
  }

}
