import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../models/article.dart';
import '../services/github_service.dart';
import '../services/image_service.dart';

// ────────────────────────────────────────────────────────────
// 图床图片项
// ────────────────────────────────────────────────────────────
class _ImageBedItem {
  final String name;
  final String path;
  final String sha;
  final int size;
  final String downloadUrl;
  final String cdnUrl;
  DateTime? lastModified;

  _ImageBedItem({
    required this.name,
    required this.path,
    required this.sha,
    required this.size,
    required this.downloadUrl,
    required this.cdnUrl,
  });

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get formattedDate =>
      lastModified != null
          ? '${lastModified!.year}-${lastModified!.month.toString().padLeft(2, '0')}-${lastModified!.day.toString().padLeft(2, '0')}'
          : '--';
}

// ────────────────────────────────────────────────────────────
// 死链检测结果
// ────────────────────────────────────────────────────────────
class _DeadLinkResult {
  final String url;
  final bool isAlive;
  final int statusCode;
  final String error;
  final List<String> articleTitles;

  _DeadLinkResult({
    required this.url,
    required this.isAlive,
    this.statusCode = 0,
    this.error = '',
    this.articleTitles = const [],
  });
}

// ────────────────────────────────────────────────────────────
// URL 替换预览
// ────────────────────────────────────────────────────────────
class _UrlReplacePreview {
  final String articleTitle;
  final int matchCount;
  final String contentPreview;

  _UrlReplacePreview({
    required this.articleTitle,
    required this.matchCount,
    required this.contentPreview,
  });
}

// ────────────────────────────────────────────────────────────
// 主屏幕
// ────────────────────────────────────────────────────────────
class ImageBedScreen extends StatefulWidget {
  final AppSettings settings;
  final GitHubService githubService;
  final ImageService imageService;
  final List<Article> allArticles;
  final Function(String oldUrl, String newUrl) onUrlReplaced;

  const ImageBedScreen({
    super.key,
    required this.settings,
    required this.githubService,
    required this.imageService,
    required this.allArticles,
    required this.onUrlReplaced,
  });

  @override
  State<ImageBedScreen> createState() => _ImageBedScreenState();
}

class _ImageBedScreenState extends State<ImageBedScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── 浏览图床 ──
  List<_ImageBedItem> _images = [];
  final Set<int> _selectedIndices = {};
  bool _isLoadingImages = false;
  String? _loadError;
  bool _isDeleting = false;

  // ── 死链检测 ──
  bool _isScanningDeadLinks = false;
  double _scanProgress = 0;
  String _scanStatus = '';
  List<_DeadLinkResult> _deadLinkResults = [];
  bool _showOnlyDead = true;

  // ── URL 替换 ──
  final TextEditingController _oldUrlController = TextEditingController();
  final TextEditingController _newUrlController = TextEditingController();
  bool _isPreviewing = false;
  bool _isReplacing = false;
  List<_UrlReplacePreview> _replacePreviews = [];
  String? _replaceError;

  HttpClient? _httpClient;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        if (!mounted) return;
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _oldUrlController.dispose();
    _newUrlController.dispose();
    _httpClient?.close(force: true);
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // GitHub API 请求辅助
  // ═══════════════════════════════════════════════════════════

  String get _token {
    final t = widget.settings.imageBedToken.isNotEmpty
        ? widget.settings.imageBedToken
        : widget.settings.effectiveGithubToken;
    return t;
  }

  String get _owner => widget.settings.imageBedOwner;
  String get _repo => widget.settings.imageBedRepo;
  String get _branch => widget.settings.imageBedBranch;
  String get _imagePath => widget.settings.imageBedPath;

  String _cdnUrlForPath(String path) {
    if (widget.settings.imageBedCdn.isNotEmpty) {
      final cdn = widget.settings.imageBedCdn.replaceAll(RegExp(r'/+$'), '');
      return '$cdn/$path';
    }
    return 'https://cdn.jsdelivr.net/gh/$_owner/$_repo@$_branch/$path';
  }

  Future<Map<String, String>> _apiHeaders() async => {
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer $_token',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'HexoBlogManager',
        'Content-Type': 'application/json',
      };

  Future<dynamic> _apiRequest(String method, String url,
      {Object? body}) async {
    final client = _httpClient ??= HttpClient();
    try {
      final req = await client.openUrl(method, Uri.parse(url));
      final headers = await _apiHeaders();
      headers.forEach(req.headers.set);
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        req.headers.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (text.isEmpty) return null;
        return jsonDecode(text);
      }
      throw Exception('GitHub $method ${res.statusCode}: $text');
    } catch (e) {
      // If the client is broken, reset it
      _httpClient?.close(force: true);
      _httpClient = null;
      rethrow;
    }
  }

  String _encPath(String path) => path
      .split('/')
      .where((e) => e.isNotEmpty)
      .map(Uri.encodeComponent)
      .join('/');

  // ═══════════════════════════════════════════════════════════
  // 浏览图床
  // ═══════════════════════════════════════════════════════════

  Future<void> _loadImages() async {
    if (_token.isEmpty) {
      setState(() => _loadError = '请先配置图床 Token');
      return;
    }
    if (_owner.isEmpty || _repo.isEmpty) {
      setState(() => _loadError = '请先配置图床仓库 owner/repo');
      return;
    }
    if (!mounted) return;
    setState(() {
      _isLoadingImages = true;
      _loadError = null;
    });

    try {
      final url =
          'https://api.github.com/repos/$_owner/$_repo/contents/${_encPath(_imagePath)}?ref=${Uri.encodeComponent(_branch)}';
      final data = await _apiRequest('GET', url);
      if (data is! List) {
        setState(() {
          _isLoadingImages = false;
          _images = [];
        });
        return;
      }

      final items = <_ImageBedItem>[];
      for (final e in data) {
        if (e is! Map) continue;
        final type = e['type']?.toString() ?? '';
        if (type == 'dir') continue;
        final name = e['name']?.toString() ?? '';
        // 过滤图片文件
        final lower = name.toLowerCase();
        if (!lower.endsWith('.png') &&
            !lower.endsWith('.jpg') &&
            !lower.endsWith('.jpeg') &&
            !lower.endsWith('.gif') &&
            !lower.endsWith('.webp') &&
            !lower.endsWith('.svg') &&
            !lower.endsWith('.bmp') &&
            !lower.endsWith('.ico')) {
          continue;
        }
        final path = e['path']?.toString() ?? '';
        final sha = e['sha']?.toString() ?? '';
        final size = (e['size'] as num?)?.toInt() ?? 0;
        final downloadUrl = e['download_url']?.toString() ?? '';
        items.add(_ImageBedItem(
          name: name,
          path: path,
          sha: sha,
          size: size,
          downloadUrl: downloadUrl,
          cdnUrl: _cdnUrlForPath(path),
        ));
      }

      setState(() {
        _images = items;
        _isLoadingImages = false;
        _selectedIndices.clear();
      });

      // 异步拉取最后修改时间
      _fetchLastModifiedDates(items);
    } catch (e) {
      setState(() {
        _isLoadingImages = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _fetchLastModifiedDates(List<_ImageBedItem> items) async {
    for (var i = 0; i < items.length; i++) {
      try {
        final url =
            'https://api.github.com/repos/$_owner/$_repo/commits?path=${_encPath(items[i].path)}&sha=${Uri.encodeComponent(_branch)}&per_page=1';
        final data = await _apiRequest('GET', url);
        if (data is List && data.isNotEmpty) {
          final commit = (data[0] as Map)['commit'] as Map?;
          final author = commit?['author'] as Map?;
          if (author != null) {
            final dateStr = author['date']?.toString();
            if (dateStr != null) {
              items[i].lastModified = DateTime.tryParse(dateStr);
            }
          }
        }
      } catch (e) { debugPrint('ImageBed: fetch date failed: $e'); }
    }
    if (mounted) setState(() {});
  }

  Future<void> _deleteSelectedImages() async {
    if (_selectedIndices.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${_selectedIndices.length} 张图片吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    setState(() => _isDeleting = true);
    int deleted = 0;
    int failed = 0;

    final toDelete = _selectedIndices.toList()
      ..sort((a, b) => b.compareTo(a)); // 从大到小删除，避免索引错乱

    for (final idx in toDelete) {
      if (idx >= _images.length) continue;
      final item = _images[idx];
      try {
        final url =
            'https://api.github.com/repos/$_owner/$_repo/contents/${_encPath(item.path)}';
        await _apiRequest('DELETE', url, body: {
          'message': 'chore: delete ${item.name}',
          'sha': item.sha,
          'branch': _branch,
        });
        deleted++;
      } catch (e) { debugPrint('ImageBed: delete failed: $e');
        failed++;
      }
    }

    setState(() {
      _isDeleting = false;
      _selectedIndices.clear();
    });

    await _loadImages();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('删除完成：成功 $deleted 张${failed > 0 ? '，失败 $failed 张' : ''}'),
        ),
      );
    }
  }

  Future<void> _copyUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 死链检测
  // ═══════════════════════════════════════════════════════════

  Future<void> _scanDeadLinks() async {
    setState(() {
      _isScanningDeadLinks = true;
      _scanProgress = 0;
      _scanStatus = '正在提取文章中的图片链接...';
      _deadLinkResults = [];
    });

    // 提取所有图片 URL
    final urlToArticles = <String, Set<String>>{};
    final imgRegex = RegExp(r"""!\[.*?\]\((https?://[^\s)]+)\)|<img[^>]+src=["'](https?://[^\s"']+)["']""");

    for (final article in widget.allArticles) {
      for (final match in imgRegex.allMatches(article.content)) {
        final url = (match.group(1) ?? match.group(2))?.trim();
        if (url == null || url.isEmpty) continue;
        urlToArticles.putIfAbsent(url, () => {}).add(article.title);
      }
    }

    final allUrls = urlToArticles.keys.toList();
    final total = allUrls.length;

    if (total == 0) {
      setState(() {
        _isScanningDeadLinks = false;
        _scanStatus = '未在文章中找到任何图片链接';
      });
      return;
    }

    setState(() {
      _scanStatus = '找到 $total 个图片链接，正在检测...';
    });

    final results = <_DeadLinkResult>[];
    final client = _httpClient ??= HttpClient();
    for (var i = 0; i < allUrls.length; i++) {
      final url = allUrls[i];
      setState(() {
        _scanProgress = (i + 1) / total;
        _scanStatus = '正在检测 ${i + 1}/$total: ${url.length > 60 ? '${url.substring(0, 60)}...' : url}';
      });

      bool alive = false;
      int statusCode = 0;
      String error = '';

      try {
        final req = await client.openUrl('HEAD', Uri.parse(url));
        req.headers.set('User-Agent', 'HexoBlogManager/1.0');
        final res = await req.close();
        statusCode = res.statusCode;
        alive = res.statusCode >= 200 && res.statusCode < 400;
        await res.drain();
      } catch (e) {
        error = e.toString();
        if (error.length > 100) error = '${error.substring(0, 100)}...';
      }

      results.add(_DeadLinkResult(
        url: url,
        isAlive: alive,
        statusCode: statusCode,
        error: error,
        articleTitles: urlToArticles[url]?.toList() ?? [],
      ));
    }

    setState(() {
      _isScanningDeadLinks = false;
      _deadLinkResults = results;
      _scanStatus = '检测完成：${results.where((r) => r.isAlive).length} 个正常，${results.where((r) => !r.isAlive).length} 个失效';
    });
  }

  // ═══════════════════════════════════════════════════════════
  // URL 替换
  // ═══════════════════════════════════════════════════════════

  Future<void> _previewReplace() async {
    final oldUrl = _oldUrlController.text.trim();
    final newUrl = _newUrlController.text.trim();

    if (oldUrl.isEmpty) {
      setState(() => _replaceError = '请输入旧 URL 模式');
      return;
    }
    if (newUrl.isEmpty) {
      setState(() => _replaceError = '请输入新 URL 模式');
      return;
    }

    setState(() {
      _isPreviewing = true;
      _replaceError = null;
      _replacePreviews = [];
    });

    final previews = <_UrlReplacePreview>[];
    for (final article in widget.allArticles) {
      final count = oldUrl.allMatches(article.content).length;
      if (count > 0) {
        // 生成预览：取匹配位置前后各 30 个字符
        String preview = '';
        final idx = article.content.indexOf(oldUrl);
        if (idx >= 0) {
          final start = (idx - 30).clamp(0, article.content.length);
          final end = (idx + oldUrl.length + 30).clamp(0, article.content.length);
          preview = '...${article.content.substring(start, end)}...';
        }
        previews.add(_UrlReplacePreview(
          articleTitle: article.title,
          matchCount: count,
          contentPreview: preview,
        ));
      }
    }

    setState(() {
      _isPreviewing = false;
      _replacePreviews = previews;
    });
  }

  Future<void> _executeReplace() async {
    final oldUrl = _oldUrlController.text.trim();
    final newUrl = _newUrlController.text.trim();
    if (oldUrl.isEmpty || newUrl.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认替换'),
        content: Text(
          '将把 ${_replacePreviews.length} 篇文章中的 "$oldUrl" 替换为 "$newUrl"，确定继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认替换'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isReplacing = true);
    int replaced = 0;

    try {
      widget.onUrlReplaced(oldUrl, newUrl);
      replaced = _replacePreviews.length;
    } catch (e) { debugPrint('ImageBed: scan failed: $e');
      replaced = 0;
    }

    setState(() {
      _isReplacing = false;
      _replacePreviews = [];
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(replaced > 0 ? '替换完成，已更新 $replaced 篇文章' : '替换失败'),
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('图床管理'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '浏览图床'),
            Tab(text: '死链检测'),
            Tab(text: 'URL替换'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBrowseTab(),
          _buildDeadLinkTab(),
          _buildUrlReplaceTab(),
        ],
      ),
    );
  }

  // ── 浏览图床 Tab ──

  Widget _buildBrowseTab() {
    return Column(
      children: [
        if (_loadError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.red.shade50,
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(_loadError!, style: const TextStyle(color: Colors.red))),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _loadImages,
                ),
              ],
            ),
          ),
        _buildBrowseToolbar(),
        Expanded(child: _buildImageGrid()),
      ],
    );
  }

  Widget _buildBrowseToolbar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          ElevatedButton.icon(
            onPressed: _isLoadingImages ? null : _loadImages,
            icon: _isLoadingImages
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 18),
            label: Text(_isLoadingImages ? '加载中...' : '刷新'),
          ),
          const SizedBox(width: 12),
          if (_images.isNotEmpty)
            Text(
              '共 ${_images.length} 张图片',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          const Spacer(),
          if (_selectedIndices.isNotEmpty) ...[
            Text(
              '已选 ${_selectedIndices.length} 项',
              style: const TextStyle(color: Colors.blue, fontSize: 13),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _isDeleting ? null : _deleteSelectedImages,
              icon: _isDeleting
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              label: Text(
                _isDeleting ? '删除中...' : '删除选中',
                style: const TextStyle(color: Colors.red),
              ),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.red,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImageGrid() {
    if (_isLoadingImages && _images.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_images.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              _loadError == null ? '暂无图片，点击"刷新"加载' : '加载失败',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.85,
          ),
          itemCount: _images.length,
          itemBuilder: (ctx, index) => _buildImageCard(index),
        );
      },
    );
  }

  Widget _buildImageCard(int index) {
    final item = _images[index];
    final isSelected = _selectedIndices.contains(index);

    return GestureDetector(
      onTap: () => setState(() {
        if (isSelected) {
          _selectedIndices.remove(index);
        } else {
          _selectedIndices.add(index);
        }
      }),
      onLongPress: () => _showImageDetail(item),
      child: Card(
        elevation: isSelected ? 4 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: isSelected
              ? BorderSide(color: Theme.of(context).primaryColor, width: 2)
              : BorderSide.none,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    child: Image.network(
                      item.cdnUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, _, __) => Container(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image, size: 40, color: Colors.grey),
                      ),
                      loadingBuilder: (ctx, child, progress) {
                        if (progress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            value: progress.expectedTotalBytes != null
                                ? progress.cumulativeBytesLoaded /
                                    progress.expectedTotalBytes!
                                : null,
                            strokeWidth: 2,
                          ),
                        );
                      },
                    ),
                  ),
                  if (isSelected)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check, color: Colors.white, size: 18),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        item.formattedSize,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      const Spacer(),
                      Text(
                        item.formattedDate,
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImageDetail(_ImageBedItem item) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _detailRow('大小', item.formattedSize),
            _detailRow('日期', item.formattedDate),
            _detailRow('SHA', item.sha.length > 10 ? '${item.sha.substring(0, 10)}...' : item.sha),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  _copyUrl(item.cdnUrl);
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('复制 CDN 链接'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  _copyUrl(item.downloadUrl);
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('复制原始链接'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ── 死链检测 Tab ──

  Widget _buildDeadLinkTab() {
    return Column(
      children: [
        _buildDeadLinkControls(),
        if (_isScanningDeadLinks) _buildScanProgress(),
        Expanded(child: _buildDeadLinkList()),
      ],
    );
  }

  Widget _buildDeadLinkControls() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isScanningDeadLinks ? null : _scanDeadLinks,
              icon: _isScanningDeadLinks
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search, size: 18),
              label: Text(_isScanningDeadLinks ? '检测中...' : '扫描死链'),
            ),
          ),
          if (_deadLinkResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '共 ${_deadLinkResults.length} 个链接，${_deadLinkResults.where((r) => !r.isAlive).length} 个失效',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _showOnlyDead = !_showOnlyDead),
                  child: Text(_showOnlyDead ? '显示全部' : '仅显示失效'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScanProgress() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          LinearProgressIndicator(value: _scanProgress),
          const SizedBox(height: 8),
          Text(
            _scanStatus,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildDeadLinkList() {
    if (_deadLinkResults.isEmpty && !_isScanningDeadLinks) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              '点击"扫描死链"检测文章中的图片链接',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    final displayResults = _showOnlyDead
        ? _deadLinkResults.where((r) => !r.isAlive).toList()
        : _deadLinkResults;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: displayResults.length,
      itemBuilder: (ctx, index) => _buildDeadLinkItem(displayResults[index]),
    );
  }

  Widget _buildDeadLinkItem(_DeadLinkResult result) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.isAlive ? Icons.check_circle : Icons.error,
                  color: result.isAlive ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.url,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: result.isAlive ? Colors.green.shade700 : Colors.red.shade700,
                      decoration: result.isAlive ? null : TextDecoration.lineThrough,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () => _copyUrl(result.url),
                  tooltip: '复制链接',
                ),
              ],
            ),
            if (!result.isAlive) ...[
              const SizedBox(height: 6),
              Text(
                result.error.isNotEmpty
                    ? '错误: ${result.error}'
                    : '状态码: ${result.statusCode}',
                style: TextStyle(fontSize: 12, color: Colors.red.shade400),
              ),
            ],
            if (result.articleTitles.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 2,
                children: result.articleTitles.map((title) => Chip(
                  label: Text(title, style: const TextStyle(fontSize: 11)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Colors.grey.shade100,
                )).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── URL 替换 Tab ──

  Widget _buildUrlReplaceTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _oldUrlController,
            decoration: const InputDecoration(
              labelText: '旧 URL 或 URL 模式',
              hintText: '例如: https://old-cdn.example.com/images',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link_off),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _newUrlController,
            decoration: const InputDecoration(
              labelText: '新 URL 或 URL 模式',
              hintText: '例如: https://new-cdn.example.com/images',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
            ),
          ),
          if (_replaceError != null) ...[
            const SizedBox(height: 8),
            Text(_replaceError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: (_isPreviewing || _isReplacing) ? null : _previewReplace,
                icon: _isPreviewing
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.preview, size: 18),
                label: const Text('预览影响范围'),
              ),
              const SizedBox(width: 12),
              if (_replacePreviews.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: _isReplacing ? null : _executeReplace,
                  icon: _isReplacing
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.swap_horiz, size: 18),
                  label: Text(_isReplacing ? '替换中...' : '执行替换'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
          if (_replacePreviews.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '共 ${_replacePreviews.length} 篇文章将被修改',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ..._replacePreviews.map((p) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.article, size: 16, color: Colors.blue),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            p.articleTitle,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${p.matchCount} 处',
                            style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                          ),
                        ),
                      ],
                    ),
                    if (p.contentPreview.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        p.contentPreview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )),
          ],
        ],
      ),
    );
  }
}