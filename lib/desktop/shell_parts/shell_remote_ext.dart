// 远程内容 / 回滚扩展（desktop_shell.dart 的 part，与主类同 library，可访问私有成员）。
// 由 desktop_shell.dart 拆分而来（修复1），方法体保持零变更；
// setState 经宿主 _applyState 包装调用。
part of '../desktop_shell.dart';

extension DesktopShellRemoteExt on DesktopShellState {
  Future<void> _refreshRemote() async {
    final repo = effectiveRepo;
    if (repo == null || repo.token.isEmpty) return;
    _applyState(() => busy = true);
    try {
      remotePosts = await github.listPosts(repo);
    } catch (e) {
      debugPrint('List remote posts error: $e');
    }
    if (mounted) _applyState(() => busy = false);
  }

  Future<void> _refreshRss() async {
    final url = settings.sitePreviewUrl.isNotEmpty
        ? settings.sitePreviewUrl
        : (activeRepo?.siteUrl.isNotEmpty == true ? activeRepo!.siteUrl : '');
    try {
      rssItems = await rssService.fetch(url);
    } catch (e) {
      debugPrint('RSS fetch error: $e');
    }
  }

  Future<void> _refreshCommits() async {
    final repo = effectiveRepo;
    if (repo == null || repo.token.isEmpty) return;
    try {
      commits = await github.listCommits(repo);
    } catch (e) {
      debugPrint('List commits error: $e');
    }
  }

  void _openRemote() {
    if (siteManager.isDynamicSite) {
      final adapter = siteManager.currentAdapter;
      if (adapter == null) {
        _showToast('未配置 CMS 站点');
        return;
      }
      _openTab(
        'remote_posts',
        '远程文章',
        Icons.cloud_outlined,
        RemotePostsScreen(
          adapter: adapter,
          allAdapters: _allCmsAdapters,
          logService: logService,
          onOpenInEditor: (post) {
            // 打开远程文章到编辑器；多站点先切换到文章所属站点
            if (post.siteId != null &&
                siteManager.activeSiteId != post.siteId) {
              final identity = siteManager.getSiteIdentity(post.siteId!);
              if (identity != null && identity.isDynamic) {
                siteManager.setActiveSite(post.siteId!);
              }
            }
            _openExistingArticle(
              Article(
                // 用站点 + 远程 id 生成稳定 tab id，避免同一文章每次打开都新建标签
                id:
                    'cms_${post.siteId ?? 'cms'}_${post.id ?? post.title.hashCode}',
                title: post.title,
                content: post.contentMd,
                tags: post.tags,
                categories: post.categories,
                createdAt: post.date,
                updatedAt: DateTime.now(),
                isDraft: true,
                remoteSha: post.id?.toString(),
              ),
            );
          },
          onDeletePost: (post) async {
            if (post.id == null) return;
            BlogRepository? target = post.siteId != null
                ? siteManager.getAdapter(post.siteId!)
                : null;
            target ??= adapter;
            try {
              await target.deletePost(post.id!);
              _showToast('已删除');
            } catch (e) {
              _showToast('删除失败: $e');
            }
          },
        ),
      );
    } else {
      _openTab(
        'remote',
        '远程文章',
        Icons.cloud_outlined,
        RemoteScreen(
          posts: remotePosts,
          activeRepo: activeRepo,
          effectiveRepo: effectiveRepo,
          github: github,
          onRefresh: _refreshRemote,
          onOpen: (item) async {
            final repo = effectiveRepo;
            if (repo == null) return;
            try {
              final a = await github.getArticle(repo, item);
              _openExistingArticle(a);
            } catch (e) {
              _showToast('打开失败: $e');
            }
          },
          onDelete: (item) async {
            try {
              final repo = effectiveRepo;
              if (repo != null && item.sha != null) {
                await github.deleteRawFile(repo, item.path, item.sha!);
                _refreshRemote();
                _showToast('已删除');
              }
            } catch (e) {
              _showToast('删除失败: $e');
            }
          },
          onBatchDelete: _batchDeleteRemoteFiles,
          onRollback: _rollbackRemoteFile,
        ),
      );
    }
  }

  Future<void> _batchDeleteRemoteFiles(List<GitHubFileItem> items) async {
    if (items.isEmpty) return;
    final repo = effectiveRepo;
    if (repo == null) {
      _showToast('未配置仓库');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('批量删除 ${items.length} 篇远程文章？'),
        content: const Text(
          '将删除远程仓库中的对应文件，此操作不可撤销。',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    int success = 0;
    int fail = 0;
    for (final item in items) {
      try {
        final article = await github.getArticle(repo, item);
        await github.deleteArticle(repo, article);
        success++;
      } catch (e) {
        debugPrint('Batch delete remote failed: $e');
        fail++;
      }
    }
    await _refreshRemote();
    await _refreshCommits();
    _showToast('删除完成: $success 成功, $fail 失败');
  }

  Future<void> _rollbackRemoteFile(String path) async {
    final repo = effectiveRepo;
    if (repo == null) {
      _showToast('未配置仓库');
      return;
    }
    if (path.isEmpty) {
      _showToast('路径不能为空');
      return;
    }
    if (commits.isEmpty) await _refreshCommits();
    if (commits.isEmpty) {
      _showToast('无提交历史');
      return;
    }
    final sha = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('回滚 $path'),
        content: SizedBox(
          width: 480,
          height: 360,
          child: ListView.builder(
            itemCount: commits.length,
            itemBuilder: (_, i) {
              final c = commits[i];
              final dateStr = c.date
                  .toIso8601String()
                  .substring(0, 16)
                  .replaceFirst('T', ' ');
              return ListTile(
                dense: true,
                title: Text(c.message.split('\n').first,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${c.sha.substring(0, 7)} · $dateStr'),
                onTap: () => Navigator.pop(ctx, c.sha),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (sha == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认回滚'),
        content: Text(
          '将 $path 恢复为 ${sha.substring(0, 7)} 的内容并新建提交？',
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('回滚'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final article = await github.rollbackFile(repo, path, sha);
      _showToast('回滚成功: ${article.remotePath}');
      await _refreshRemote();
      await _refreshCommits();
    } catch (e) {
      _showToast('回滚失败: $e');
    }
  }
}
