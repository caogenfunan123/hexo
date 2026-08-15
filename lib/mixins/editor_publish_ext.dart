// 编辑器发布/上传/保存扩展（由 main.dart part 引入，与原类同 library，可访问私有成员）
part of '../main.dart';

extension EditorPublishExt on _RootShellState {
  // --- Editor methods ---
  Article _collect({bool draft = true}) {
    _doc.setEditorRepoId(_editorRepo?.id);
    return _doc.collectArticle(draft: draft);
  }

  Future<void> _saveLocal() async {
    final a = _collect(draft: true);
    _applyState(() {
      _doc.setCurrentArticle(a);
      _editorStatus = '本地已保存';
    });
    await _saveDraft(a);
    // 记录今日写作字数增量
    _recordWritingStats(a);
    // 动态 CMS 站点：同时保存到 SQLite 草稿表
    if (siteManager.isDynamicSite) {
      final adapter = siteManager.currentAdapter;
      if (adapter != null) {
        final post = BlogPost(
          title: a.title,
          contentMd: a.content,
          status: 'draft',
          slug: _generateSlug(a.title),
          tags: a.tags,
          categories: a.categories,
          date: DateTime.now(),
          siteId: adapter.config.id,
          siteType: adapter.config.type,
        );
        await cmsDraftService.saveDraft(post);
      }
    }
    logService.add('保存草稿', '标题: ${a.title.isNotEmpty ? a.title : "(无标题)"}');
    if (mounted) _showToast('草稿已保存到本地');

  }

  /// 记录写作字数增量（按草稿 id 差分，避免重复累计）
  void _recordWritingStats(Article a) {
    final stats = _statsService;
    if (stats == null) return;
    final words = WritingStatsService.countWords(a.content);
    final last = _lastWordCounts[a.id] ?? 0;
    final added = words - last;
    _lastWordCounts[a.id] = words;
    if (added > 0) {
      stats.recordTodayWords(added);
    }
  }

  Future<void> _publish() async {
    // ── 发布确认对话框 ──
    final publishTarget = siteManager.isDynamicSite
        ? siteManager.currentBlogType.displayName
        : (_resolvedRepo?.fullName ?? 'GitHub');
    final dynamicSiteCount = siteManager.dynamicSites.length;
    final staticRepoCount = siteManager.staticRepos.length;
    bool saveMdBackup = false;
    bool publishToAllStatic = false;

    final confirmed = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.cloud_upload_outlined,
                color: Theme.of(context).colorScheme.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Text('确认发布', style: TextStyle(fontSize: 17)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '即将发布到: $publishTarget',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '标题: ${_doc.titleCtrl.text.isNotEmpty ? _doc.titleCtrl.text : "(无标题)"}',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              // 保存 MD 备份选项
              CheckboxListTile(
                value: saveMdBackup,
                onChanged: (v) {
                  setDialogState(() => saveMdBackup = v ?? false);
                },
                title: const Text(
                  '同时保存一份 MD 备份到本地目录',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  '备份到文档目录的 hexo_backups/ 文件夹',
                  style: TextStyle(fontSize: 11),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              // 静态站点：同时发布到所有静态博客站点
              if (!siteManager.isDynamicSite && staticRepoCount > 1)
                CheckboxListTile(
                  value: publishToAllStatic,
                  onChanged: (v) {
                    setDialogState(() => publishToAllStatic = v ?? false);
                  },
                  title: const Text(
                    '同时发布到所有静态博客站点',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    '将本文发布到全部 $staticRepoCount 个静态仓库',
                    style: const TextStyle(fontSize: 11),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 0),
              child: const Text('取消'),
            ),
            // 多动态站点：一键发布到全部站点
            if (siteManager.isDynamicSite && dynamicSiteCount > 1)
              TextButton.icon(
                icon: const Icon(Icons.cloud_done_outlined, size: 18),
                label: Text('发布到全部站点 ($dynamicSiteCount)'),
                onPressed: () => Navigator.pop(ctx, 2),
              ),
            FilledButton.icon(
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: const Text('确认发布'),
              onPressed: () => Navigator.pop(ctx, 1),
            ),
          ],
        ),
      ),
    );

    if (confirmed == null || confirmed == 0 || !mounted) return;

    // ── 保存 MD 备份 ──
    if (saveMdBackup) {
      await _saveMdBackup();
    }

    // 一键发布到全部动态 CMS 站点
    if (confirmed == 2) {
      await _publishToAllCmsSites();
      return;
    }

    // 动态 CMS 站点：推送到远程 CMS
    if (siteManager.isDynamicSite) {
      await _publishToCms();
      return;
    }
    // 静态站点：勾选了"同时发布到所有静态站点"则批量发布
    if (publishToAllStatic) {
      await _publishToAllStaticSites();
      return;
    }
    // 静态站点：Git 推送
    final repo = _resolvedRepo;
    if (repo == null || repo.token.isEmpty) {
      _showToast('请先配置仓库与 Token');
      return;
    }
    _applyState(() {
      _editorBusy = true;
      _editorStatus = '正在发布...';
    });
    try {
      final a = _collect(draft: false);
      final pub = await github.publishArticleWithMirrors(repo, a, templates: templates);
      if (mounted)
        _applyState(() {
          _doc.setCurrentArticle(pub);
          _editorStatus = '已发布';
        });
      await _saveDraft(pub.copyWith(isDraft: false, published: true));
      await _refreshRemote();
      // 触发全部部署钩子（Cloudflare / Vercel / Netlify 等）
      if (settings.deployHooks.isNotEmpty) {
        final ok = await GitHubService.triggerDeployHooks(settings.deployHooks);
        logService.add(
          '部署钩子',
          ok == settings.deployHooks.length
              ? '已触发 ${ok} 个重新部署'
              : '部署钩子部分失败（${ok}/${settings.deployHooks.length}）',
          success: ok == settings.deployHooks.length,
        );
      }
      logService.add('发布成功', '已发布到 ${repo.fullName}: ${pub.title}');
      if (mounted) _showToast('已发布到 ${repo.fullName}');
    } catch (e) {
      if (mounted) _applyState(() => _editorStatus = '发布失败');
      logService.add('发布失败', '$e', success: false);
      if (mounted) _showToast('发布失败: $e');
    } finally {
      if (mounted) _applyState(() => _editorBusy = false);
    }

  }

  /// 发布到动态 CMS（WordPress / Ghost / Typecho）
  Future<void> _publishToCms() async {
    final adapter = siteManager.currentAdapter;
    if (adapter == null) {
      _showToast('当前站点未配置动态 CMS 适配器，请先添加 CMS 站点');
      return;
    }

    final a = _collect(draft: false);

    // ── 发布前置校验 ──
    if (settings.activeAiProfile != null) {
      final checkResult = await aiSelfChecker.check(
        settings: settings,
        generatedContent: a.content,
        sessionType: AiSessionType.article,
        blogFramework: adapter.config.type.displayName,
      );
      if (checkResult.hasError) {
        if (!mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange),
                SizedBox(width: 8),
                Text('发布前自检发现问题'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    checkResult.message,
                    style: const TextStyle(fontSize: 14),
                  ),
                  if (checkResult.issues.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      '具体问题:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ...checkResult.issues.map(
                      (i) => Padding(
                        padding: const EdgeInsets.only(top: 4, left: 8),
                        child: Text(
                          i,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消发布'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('仍然发布'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      } else if (!checkResult.isPassed && checkResult.issues.isNotEmpty) {
        // 仅有警告，记录但不阻断
        if (mounted) {
          _showToast('自检警告: ${checkResult.issues.first}');
        }
      }
    }

    _applyState(() {
      _editorBusy = true;
      final isUpdate = _doc.currentArticle.remoteSha != null;
      _editorStatus = isUpdate
          ? '正在更新到 ${adapter.config.type.displayName}...'
          : '正在发布到 ${adapter.config.type.displayName}...';
    });
    try {
      // 从 remoteSha 中提取远程文章 ID（加载远程文章时记录）
      final remoteId = _doc.currentArticle.remoteSha != null
          ? int.tryParse(_doc.currentArticle.remoteSha!)
          : null;
      final post = BlogPost(
        id: remoteId,
        title: a.title,
        contentMd: a.content,
        status: 'publish',
        slug: _generateSlug(a.title),
        tags: a.tags,
        categories: a.categories,
        date: DateTime.now(),
        siteId: adapter.config.id,
        siteType: adapter.config.type,
      );

      // ── 带重试的发布/更新 ──
      _publishCancelToken.reset();
      BlogPost? result;
      int attempts = 0;
      const maxRetries = 3;
      while (result == null) {
        _publishCancelToken.throwIfCancelled();
        attempts++;
        // 防止 createPost/updatePost 正常返回 null 时无限忙循环
        if (attempts > maxRetries) {
          throw BlogRepositoryException(
            500,
            '发布失败：远端未返回有效文章数据，请重试',
            '${adapter.config.type.displayName} 未返回文章 ID',
          );
        }
        try {
          if (attempts > 1) {
            final action = remoteId != null ? '更新' : '发布';
            if (mounted)
              _applyState(() => _editorStatus = '正在重试$action (第 $attempts 次)...');
          }
          result = remoteId != null
              ? await adapter.updatePost(post)
              : await adapter.createPost(post);
        } on BlogRepositoryException catch (e) {
          // 4xx 客户端错误不重试（鉴权失败、参数错误等）
          if (e.statusCode >= 400 && e.statusCode < 500) {
            rethrow;
          }
          // 5xx 服务端错误，尝试重试
          if (attempts >= maxRetries) rethrow;
          if (mounted)
            _applyState(() => _editorStatus = '发布失败，${2 * attempts}s 后重试...');
          await Future.delayed(Duration(seconds: 2 * attempts));
          _publishCancelToken.throwIfCancelled();
        } catch (e) {
          if (e is CancelledException) rethrow;
          // 网络错误等其他异常，也尝试重试
          if (attempts >= maxRetries) rethrow;
          if (mounted)
            _applyState(() => _editorStatus = '网络异常，${2 * attempts}s 后重试...');
          await Future.delayed(Duration(seconds: 2 * attempts));
          _publishCancelToken.throwIfCancelled();
        }
      }
      final finalResult = result;
      final isUpdate = remoteId != null;
      // 更新本地文章状态，记录远程 ID
      final pub = a.copyWith(
        isDraft: false,
        published: true,
        remotePath: finalResult.link,
        remoteSha: finalResult.id?.toString(),
      );
      if (mounted)
        _applyState(() {
          _doc.setCurrentArticle(pub);
          _editorStatus = isUpdate
              ? '已更新到 ${adapter.config.type.displayName}'
              : '已发布到 ${adapter.config.type.displayName}';
        });
      await _saveDraft(pub);
      // 保存到 CMS SQLite 草稿表
      await cmsDraftService.saveDraft(finalResult);
      // 更新同步映射
      if (finalResult.id != null) {
        syncService.setMapping(
          SyncMapping(
            localArticleId: pub.id,
            remotePostId: finalResult.id!,
            siteId: adapter.config.id,
            lastSyncAt: DateTime.now(),
            localModifiedAt: pub.updatedAt,
            remoteModifiedAt: finalResult.modifiedDate,
          ),
        );
      }
      final actionLabel = isUpdate ? '更新' : '发布';
      logService.add(
        'CMS$actionLabel成功',
        '已${actionLabel}到 ${adapter.config.type.displayName}: ${finalResult.title}',
      );
      if (mounted) {
        _showToast(
          '已${actionLabel}到 ${adapter.config.type.displayName}: ${finalResult.link ?? finalResult.title}',
        );
      }
    } on BlogRepositoryException catch (e) {
      if (mounted) _applyState(() => _editorStatus = '发布失败');
      logService.add('CMS发布失败', e.message, success: false);
      if (mounted) _showToast('发布失败: ${e.message}');
    } on CancelledException {
      if (mounted) _applyState(() => _editorStatus = '已取消发布');
      logService.add('发布已取消', '用户取消了发布操作');
      if (mounted) _showToast('发布已取消');
    } catch (e) {
      if (mounted) _applyState(() => _editorStatus = '发布失败');
      logService.add('CMS发布失败', '$e', success: false);
      if (mounted) _showToast('发布失败: $e');
    } finally {
      if (mounted) _applyState(() => _editorBusy = false);
    }

  }

  /// 一键发布当前文章到所有已保存的动态 CMS 站点
  /// 每个站点使用其自身的适配器（Typecho/WordPress/Ghost 等）；
  /// 若该站点已有映射（此前发布过），则更新，否则新建。
  Future<void> _publishToAllCmsSites() async {
    final adapters = _allCmsAdapters;
    if (adapters.isEmpty) {
      _showToast('没有已保存的动态 CMS 站点，请先在「设置」中添加');
      return;
    }

    final a = _collect(draft: false);
    if (a.title.trim().isEmpty) {
      _showToast('请先填写文章标题');
      return;
    }
    final slug = _generateSlug(a.title);

    _applyState(() {
      _editorBusy = true;
      _editorStatus = '正在发布到 ${adapters.length} 个站点...';
    });

    int success = 0;
    final details = <String, String>{};
    try {
      for (final adapter in adapters) {
        final siteName = adapter.config.name;
        if (mounted) _applyState(() => _editorStatus = '正在发布到 $siteName...');
        try {
          // 该站点已有远程映射 → 更新；否则新建
          final existing = syncService.findByLocalId(adapter.config.id, a.id);
          final post = BlogPost(
            id: existing?.remotePostId,
            title: a.title,
            contentMd: a.content,
            status: 'publish',
            slug: slug,
            tags: a.tags,
            categories: a.categories,
            date: DateTime.now(),
            siteId: adapter.config.id,
            siteType: adapter.config.type,
          );
          final result = existing != null
              ? await adapter.updatePost(post)
              : await adapter.createPost(post);
          success++;
          details[siteName] = '成功 (ID: ${result.id})';
          await cmsDraftService.saveDraft(result);
          if (result.id != null) {
            syncService.setMapping(
              SyncMapping(
                localArticleId: a.id,
                remotePostId: result.id!,
                siteId: adapter.config.id,
                lastSyncAt: DateTime.now(),
                localModifiedAt: a.updatedAt,
                remoteModifiedAt: result.modifiedDate,
              ),
            );
          }
        } catch (e) {
          final msg = e is BlogRepositoryException ? e.message : '$e';
          details[siteName] = '失败: $msg';
          logService.add('多站点发布失败', '$siteName: $msg', success: false);
        }
      }
    } finally {
      if (mounted) {
        _applyState(() {
          _editorBusy = false;
          _editorStatus = '多站点发布完成: 成功 $success/${adapters.length}';
        });
      }
    }

    logService.add('多站点发布', '《${a.title}》成功 $success/${adapters.length} 个站点');
    if (mounted) {
      _showToast('多站点发布完成: 成功 $success/${adapters.length} 个站点');
      final lines = details.entries
          .map((e) => '${e.key}: ${e.value}')
          .join('\n');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('发布结果 ($success/${adapters.length})'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Text(lines, style: const TextStyle(fontSize: 13)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }

  }

  /// 从标题生成 URL slug
  String _generateSlug(String title) {
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return slug.isEmpty ? 'untitled' : slug;

  }

  /// 一键发布当前文章到所有静态博客站点（带预览确认）
  Future<void> _publishToAllStaticSites() async {
    final a = _collect(draft: false);
    if (a.title.trim().isEmpty) {
      _showToast('请先填写文章标题');
      return;
    }
    final slug = _generateSlug(a.title);
    final post = BlogPost(
      title: a.title,
      contentMd: a.content,
      status: 'publish',
      slug: slug,
      tags: a.tags,
      categories: a.categories,
      date: DateTime.now(),
    );

    _applyState(() {
      _editorBusy = true;
      _editorStatus = '正在生成多站点发布预览...';
    });

    final service = StaticBlogBatchPublishService(
      siteManager: siteManager,
      githubService: github,
    );

    try {
      final preview = await service.buildPreview(post);
      if (!mounted) return;
      final confirmed = await _showStaticPublishPreviewDialog(preview);
      if (confirmed != true) {
        if (mounted) _applyState(() => _editorStatus = '已取消');
        return;
      }

      await service.publishFromPreview(
        post,
        preview,
        onProgress: (current, total, message) {
          if (mounted) _applyState(() => _editorStatus = message);
        },
        onComplete: (success, message, results) {
          logService.add('多静态站点发布', message, success: success);
          if (mounted) {
            _applyState(() {
              _editorBusy = false;
              _editorStatus = message;
            });
            _showStaticPublishResult(results);
          }
          // siteUrl 回填：发布成功且站点地址为空时，重新查询平台构建状态（Correctness 15）
          if (success) {
            for (final repo in siteManager.staticRepos) {
              if (repo.siteUrl.isEmpty && repo.siteProjectName.isNotEmpty) {
                _backfillPublishSiteUrl(repo);
              }
            }
          }
        },
      );
    } catch (e) {
      logService.add('多静态站点发布失败', '$e', success: false);
      if (mounted) {
        _applyState(() {
          _editorBusy = false;
          _editorStatus = '发布失败';
        });
        _showToast('发布失败: $e');
      }
    }

  }

  /// 发布成功后回填 siteUrl（Correctness 15）
  Future<void> _backfillPublishSiteUrl(RepoConfig repo) async {
    if (repo.token.isEmpty) return;
    String? backfilled;
    try {
      if (repo.provider == GitProviderType.github) {
        final run = await GitHubProvider()
            .getActionsRun(repo.token, repo.owner, repo.repo);
        final status = run?['status']?.toString();
        final conclusion = run?['conclusion']?.toString();
        if (status == 'completed' && conclusion == 'success') {
          backfilled = 'https://${repo.owner}.github.io/${repo.repo}/';
        }
      } else if (repo.provider == GitProviderType.gitlab) {
        final pipeline = await GitLabProvider().getPipeline(
          repo.token,
          Uri.encodeComponent('${repo.owner}/${repo.repo}'),
        );
        if (pipeline?['status']?.toString() == 'success') {
          backfilled = 'https://${repo.owner}.gitlab.io/${repo.repo}/';
        }
      }
    } catch (e) {
      logService.add('siteUrl 回填失败', '${repo.fullName}: $e', success: false);
      return;
    }
    if (backfilled == null) return;
    final idx = repos.indexWhere((r) => r.id == repo.id);
    if (idx < 0) return;
    repos[idx] = repo.copyWith(siteUrl: backfilled);
    await _updateRepos(List<RepoConfig>.from(repos));
  }

  /// 展示静态站点发布预览确认对话框
  Future<bool?> _showStaticPublishPreviewDialog(
    MultiSitePublishPreview preview,
  ) async {
    final sites = preview.publishable;
    final skipped = preview.skippedCount;
    final title = _doc.titleCtrl.text.isNotEmpty
        ? _doc.titleCtrl.text
        : '(无标题)';

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('多站点发布预览'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '《$title》将发布到以下站点:',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: sites.map<Widget>((site) {
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.cloud_done_outlined,
                          size: 18,
                          color: const Color(0xFF059669),
                        ),
                        title: Text(
                          site.siteName,
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          site.path,
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: const Text(
                          '可发布',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF059669),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              if (skipped > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '$skipped 个站点未配置 Token 将被跳过',
                    style: const TextStyle(fontSize: 12, color: Colors.orange),
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
          FilledButton.icon(
            icon: const Icon(Icons.cloud_upload_outlined, size: 18),
            label: const Text('确认发布'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

  }

  /// 展示静态站点发布结果
  Future<void> _showStaticPublishResult(Map<String, dynamic> results) async {
    final lines = results.entries
        .map((e) {
          final v = e.value;
          final ok = v is Map && v['success'] == true;
          final msg = v is Map ? (v['message']?.toString() ?? '') : '$v';
          return '${ok ? '✓' : '✗'} ${e.key}: $msg';
        })
        .join('\n');

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发布结果'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              lines.isEmpty ? '无结果' : lines,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );

  }

  Future<void> _insertImage() async {
    _applyState(() {
      _editorBusy = true;
      _editorStatus = '正在选择图片...';
    });
    try {
      final bytes = await imageService.pickImageBytes();
      if (bytes == null) {
        if (mounted) _applyState(() => _editorStatus = '已取消');
        return;
      }
      _failedImageBytes = bytes; // 缓存以备重试
      final sizeKB = (bytes.length / 1024).toStringAsFixed(1);
      if (mounted) _applyState(() => _editorStatus = '正在上传图片 ($sizeKB KB)...');
      final url = await imageService.uploadToImageBed(bytes, settings);
      _insertText(imageService.markdownImage(url));
      _failedImageBytes = null; // 清除失败缓存
      if (mounted) _applyState(() => _editorStatus = '图片已插入');
    } catch (e) {
      // 缓存失败图片字节，插入重试标记
      final retryMark = '\n> ⚠️ 图片上传失败，[点击重试](#retry-upload)\n';
      _insertText(retryMark);
      if (mounted) _applyState(() => _editorStatus = '上传失败（可点击重试）');
      if (mounted) _showToast('上传失败，点击文中标记可重试');
    } finally {
      if (mounted) _applyState(() => _editorBusy = false);
    }

  }

  /// 批量插入图片并上传到图床（含预处理）
  Future<void> _batchInsertImages() async {
    _applyState(() {
      _editorBusy = true;
      _editorStatus = '正在选择图片...';
    });
    try {
      final bytesList = await imageService.pickMultipleImageBytes();
      if (bytesList == null || bytesList.isEmpty) {
        if (mounted) _applyState(() => _editorStatus = '已取消');
        return;
      }
      final total = bytesList.length;

      // ── 预处理阶段：批量压缩 ──
      if (mounted) _applyState(() => _editorStatus = '正在预处理 $total 张图片...');
      final preResult = await imageService.preprocessImages(
        bytesList,
        settings,
        onProgress: (current, total, beforeKB, afterKB) {
          if (mounted) {
            _applyState(
              () => _editorStatus =
                  '预处理 $current/$total: ${beforeKB}KB → ${afterKB}KB',
            );
          }
        },
      );
      logService.add('图片预处理', preResult.summary);

      // ── 上传阶段 ──
      int uploaded = 0;
      int failed = 0;
      final buf = StringBuffer();
      for (var i = 0; i < total; i++) {
        if (mounted)
          _applyState(() => _editorStatus = '正在上传图片 ${i + 1}/$total...');
        try {
          final url = await imageService.uploadToImageBed(
            preResult.images[i],
            settings,
            skipCompress: true, // 已预处理，跳过重复压缩
          );
          buf.writeln(imageService.markdownImage(url));
          uploaded++;
        } catch (e) {
          debugPrint('App: image pick failed: $e');
          // 缓存失败图片字节，写标准重试标记，使用户可点击重试
          _failedImageBytes = preResult.images[i];
          buf.writeln('\n> ⚠️ 图片上传失败，[点击重试](#retry-upload)');
          failed++;
        }
      }
      _insertText('\n\n${buf.toString()}');
      logService.add('批量上传图片', '成功: $uploaded, 失败: $failed');
      if (mounted) _applyState(() => _editorStatus = '完成: $uploaded/$total 张上传成功');
    } catch (e) {
      if (mounted) _applyState(() => _editorStatus = '批量上传失败');
      if (mounted) _showToast('批量上传失败: $e');
    } finally {
      if (mounted) _applyState(() => _editorBusy = false);
    }

  }

  /// 重试上传失败图片
  Future<void> _retryUploadImage() async {
    final bytes = _failedImageBytes;
    if (bytes == null) {
      _showToast('没有可重试的图片');
      return;
    }
    // 移除重试标记文本
    final txt = _doc.contentCtrl.text;
    final retryIdx = txt.indexOf('> ⚠️ 图片上传失败');
    if (retryIdx >= 0) {
      final markIdx = txt.indexOf('#retry-upload', retryIdx);
      if (markIdx >= 0) {
        final endIdx = txt.indexOf('\n', markIdx);
        final removeEnd = endIdx >= 0 ? endIdx + 1 : txt.length;
        _doc.contentCtrl.text = txt.replaceRange(retryIdx, removeEnd, '');
        _onContentChanged();
      }
    }

    _applyState(() {
      _editorBusy = true;
      _editorStatus = '正在重试上传...';
    });
    try {
      final url = await imageService.uploadToImageBed(bytes, settings);
      _insertText(imageService.markdownImage(url));
      _failedImageBytes = null;
      if (mounted) _applyState(() => _editorStatus = '图片已插入');
    } catch (e) {
      if (mounted) _applyState(() => _editorStatus = '重试失败');
      if (mounted) _showToast('重试上传失败: $e');
    } finally {
      if (mounted) _applyState(() => _editorBusy = false);
    }

  }

  // --- Data methods ---
  Future<void> _saveDraft(Article a) async {
    final i = drafts.indexWhere((e) => e.id == a.id);
    if (i >= 0)
      drafts[i] = a;
    else
      drafts.insert(0, a);
    drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await storage.saveDrafts(drafts);
    await storage.exportDraftMarkdown(a);
    if (mounted) _applyState(() {});

  }

  Future<void> _deleteDraft(Article a) async {
    // 先移入回收站，防止误删除
    final rb = _recycleBin;
    if (rb != null) {
      try {
        final dir = await storage.mdArticlesDir();
        final filePath = '${dir.path}/${a.id}_${a.fileName()}';
        await rb.moveToTrash(filePath, a);
      } catch (e) { debugPrint('RecycleBin: moveToTrash failed: $e'); }
    }
    drafts.removeWhere((e) => e.id == a.id);
    await storage.saveDrafts(drafts);
    logService.add('删除草稿', '标题: ${a.title.isNotEmpty ? a.title : "(无标题)"}');
    if (mounted) _applyState(() {});
  }

  Future<void> _saveMdBackup() async {
    try {
      final a = _collect(draft: false);
      final dir = await storage.mdArticlesDir();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final safeTitle = a.title.isNotEmpty
          ? a.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          : 'untitled';
      final fileName = '${timestamp}_$safeTitle.md';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(a.content);
      if (mounted)
        _showToast(
          'MD 已保存到 ${StorageService.dirMdArticles}/$fileName\n${dir.path}',
        );
    } catch (e) {
      if (mounted) _showToast('MD 保存失败: $e');
    }
  }
}