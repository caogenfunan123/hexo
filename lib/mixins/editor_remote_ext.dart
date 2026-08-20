// 远程内容/分享预览扩展（由 main.dart part 引入，与原类同 library，可访问私有成员）
part of '../main.dart';

extension EditorRemoteExt on _RootShellState {
  /// 预览文章（复用原 AppBar 预览逻辑，支持 Mermaid 与公式）
  void _openArticlePreview() {
    if (_editorBusy) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppTheme.bg,
          appBar: AppBar(
            title: Text(
              _doc.titleCtrl.text.isEmpty ? '预览' : _doc.titleCtrl.text,
            ),
          ),
          body: MarkdownPreviewSmooth(
            markdown: _doc.contentCtrl.text.isEmpty
                ? '*暂无内容*'
                : _doc.contentCtrl.text,
            darkTheme: isDark,
            onOpenLink: (url) async {
              final uri = Uri.tryParse(url);
              if (uri != null &&
                  (uri.scheme == 'http' || uri.scheme == 'https')) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ),
      ),
    );
  }

  /// 系统分享当前文章
  Future<void> _shareArticle() async {
    try {
      final a = _collect(draft: true);
      final text = a.content.isNotEmpty
          ? '${a.title.isNotEmpty ? '${a.title}\n\n' : ''}${a.content}'
          : a.title;
      await Share.share(text, subject: a.title);
    } catch (e) {
      if (mounted) _showToast('分享失败: $e');
    }
  }

  /// 生成标准 .md 文件并唤起系统分享（写入 临时分享文件/ 分类目录）
  Future<void> _shareMdFile() async {
    try {
      final a = _collect(draft: true);
      final dir = await storage.shareTempDir();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final safeTitle = a.title.isNotEmpty
          ? a.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          : 'untitled';
      final fileName = '${timestamp}_$safeTitle.md';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(
        a.title.isNotEmpty ? '# ${a.title}\n\n${a.content}' : a.content,
      );
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/markdown')],
        subject: a.title,
        text: a.content.isNotEmpty
            ? '${a.title.isNotEmpty ? '${a.title}\n\n' : ''}${a.content}'
            : a.title,
      );
      if (mounted) _showToast('MD 文件已生成: ${dir.path}/$fileName');
    } catch (e) {
      if (mounted) _showToast('MD 分享失败: $e');
    }
  }

  /// 打开本地文件区（应用内浏览/暂存，替代原生文件管理器）
  ///
  /// 原生 openFolder 在 Android 私有沙盒与 iOS/桌面无 channel 时必报错，
  /// 统一改为应用内本地文件区：浏览根目录、编辑暂存、仓库下载/上传。
  Future<void> _openStorageFolder() async {
    try {
      await storage.root;
      if (!mounted) return;
await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) {
          final repo = activeRepo;
          return LocalFileZoneScreen(
            storage: storage,
            github: github,
            activeRepo: repo == null ? null : _resolvedRepoFor(repo),
          );
        },
      ),
    );
    } catch (e) {
      if (mounted) _showToast('打开本地文件区失败: $e');
    }
  }

  /// 导出正文为 PNG 长图（Markdown 渲染后截图保存到 文章长图/）
  Future<void> _exportPngLongImage() async {
    try {
      final a = _collect(draft: false);
      final dir = await storage.longImagesDir();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final safeTitle = a.title.isNotEmpty
          ? a.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          : 'untitled';
      final filePath = '${dir.path}/${timestamp}_$safeTitle.png';

      // 渲染长图：标题 + Markdown 正文
      final mdStyle = createMobileMarkdownStyle(context: context);
      final width = MediaQuery.of(context).size.width;
      final boundaryKey = GlobalKey();

      final overlay = Overlay.of(context);
      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (_) => Positioned(
          left: -100000,
          top: 0,
          child: RepaintBoundary(
            key: boundaryKey,
            child: Container(
              width: width,
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (a.title.isNotEmpty)
                    Text(
                      a.title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                  const SizedBox(height: 12),
                  MarkdownBody(
                    data: a.content.isEmpty ? '*（无内容）*' : a.content,
                    styleSheet: mdStyle,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      overlay.insert(entry);
      await Future.delayed(const Duration(milliseconds: 300));
      final boundary =
          boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 3);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final bytes = byteData.buffer.asUint8List();
          // 写入私有目录作为兜底
          final file = File(filePath);
          await file.writeAsBytes(bytes);
          // 尝试写入 SAF 导出文件夹
          final savedToSaf = await storage.savePngToExternalSaf(
            '${timestamp}_$safeTitle.png',
            bytes,
          );
          if (mounted) {
            if (savedToSaf) {
              _showToast('PNG 长图已保存到导出文件夹');
            } else {
              _showToast('PNG 长图已保存到内部目录\n$filePath');
            }
          }
        }
      }
      entry.remove();
    } catch (e) {
      if (mounted) _showToast('导出失败: $e');
    }
  }

  /// 打开静态博客文章管理界面（一键批量发布已保存的文章）
  Future<void> _showStaticBlogPosts() async {
    if (repos.isEmpty) {
      _showToast('请先在设置中添加仓库');
      return;
    }
    RepoConfig repo;
    if (repos.length == 1) {
      repo = repos.first;
    } else {
      final selected = await showDialog<RepoConfig>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('选择静态博客仓库'),
          children: [
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);
                _showAllStaticBlogs();
              },
              child: const Row(
                children: [
                  Icon(Icons.library_books_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('全部博客管理（聚合所有仓库）'),
                ],
              ),
            ),
            const Divider(height: 1),
            ...repos
                .map(
                  (r) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, r),
                    child: Text('${r.name} (${r.fullName})'),
                  ),
                )
                .toList(),
          ],
        ),
      );
      if (selected == null) return;
      repo = selected;
    }
    final resolved = _resolvedRepoFor(repo);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => StaticBlogPostsScreen(
          repoConfig: resolved,
          siteManager: siteManager,
          settings: settings,
          githubService: github,
          logService: logService,
          onOpenInEditor: _openStaticBlogPostInEditor,
          onDeletePost: _deleteStaticBlogPost,
        ),
      ),
    );
  }

  /// 打开全部静态博客聚合管理界面（跨仓库批量选择、批量删除）
  Future<void> _showAllStaticBlogs() async {
    if (repos.isEmpty) {
      _showToast('请先在设置中添加仓库');
      return;
    }
    final resolved = repos.map(_resolvedRepoFor).toList();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AllStaticBlogsScreen(
          repos: resolved,
          settings: settings,
          githubService: github,
          logService: logService,
          snapshotRootProvider: () async {
            final root = await storage.root;
            return Directory('${root.path}/同步缓存');
          },
          onOpenInEditor: _openStaticBlogPostInEditor,
          onDeletePost: _deleteStaticBlogPost,
        ),
      ),
    );
  }

  /// 在仓库中查找与文章对应的 GitHub 文件项
  Future<GitHubFileItem?> _findStaticFileItem(BlogPost post) async {
    final repo =
        repos.where((r) => r.id == post.siteId).firstOrNull ?? activeRepo;
    if (repo == null) return null;
    final resolved = _resolvedRepoFor(repo);
    final items = await github.listPosts(resolved, recursive: true);
    if (items.isEmpty) return null;
    final slug = post.slug?.toLowerCase().replaceAll(RegExp(r'\.md$'), '');
    final title = post.title.trim();
    return items.where((i) {
      final name = i.name.toLowerCase();
      if (slug != null && name == '$slug.md') return true;
      if (title.isNotEmpty && name == '$title.md') return true;
      return i.path.contains(post.slug ?? post.title);
    }).firstOrNull;
  }

  /// 打开静态博客远程文章到编辑器
  void _openStaticBlogPostInEditor(BlogPost post) {
    _openStaticBlogPostAsync(post);
  }

  Future<void> _openStaticBlogPostAsync(BlogPost post) async {
    try {
      final item = await _findStaticFileItem(post);
      final repo =
          repos.where((r) => r.id == post.siteId).firstOrNull ?? activeRepo;
      if (item == null || repo == null) {
        _showToast('未在仓库中找到该文章');
        return;
      }
      final article = await github.getArticle(_resolvedRepoFor(repo), item);
      _openExistingArticle(article);
    } catch (e) {
      logService.add('打开静态博客文章失败', '$e', success: false);
      if (mounted) _showToast('打开失败: $e');
    }
  }

  /// 删除静态博客远程文章
  Future<void> _deleteStaticBlogPost(BlogPost post) async {
    final item = await _findStaticFileItem(post);
    final repo =
        repos.where((r) => r.id == post.siteId).firstOrNull ?? activeRepo;
    if (item == null || repo == null) {
      throw Exception('未在仓库中找到该文章');
    }
    final article = await github.getArticle(_resolvedRepoFor(repo), item);
    await github.deleteArticle(_resolvedRepoFor(repo), article);
  }

}
