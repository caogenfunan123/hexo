import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import '../models/article.dart';
import '../models/article_type.dart';

class _LinkResult {
  final Article article;
  final String linkText;
  final String url;
  final bool isInternal;
  LinkStatus status;
  int? httpCode;
  String? error;

  _LinkResult({
    required this.article,
    required this.linkText,
    required this.url,
    required this.isInternal,
    this.status = LinkStatus.unknown,
    this.httpCode,
    this.error,
  });
}

enum LinkStatus { alive, dead, unknown, checking }

class LinkCheckerScreen extends StatefulWidget {
  final List<Article> articles;
  final void Function(Article article) onOpenArticle;
  final void Function(List<Article>)? onArticlesChanged;

  const LinkCheckerScreen({
    super.key,
    required this.articles,
    required this.onOpenArticle,
    this.onArticlesChanged,
  });

  @override
  State<LinkCheckerScreen> createState() => _LinkCheckerScreenState();
}

class _LinkCheckerScreenState extends State<LinkCheckerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<_LinkResult> _internalResults = [];
  List<_LinkResult> _externalResults = [];
  bool _isScanning = false;
  String _scanStatus = '';

  // Internal link cache: all known file paths from articles
  final Set<String> _knownPaths = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _buildKnownPaths();
    _runFullScan();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _buildKnownPaths() {
    _knownPaths.clear();
    for (final article in widget.articles) {
      final name = article.fileName();
      _knownPaths.add(name);
      _knownPaths.add('/$name');
      _knownPaths.add('./$name');
      // Also add paths based on article type
      if (article.articleType == ArticleType.post) {
        _knownPaths.add('posts/$name');
        _knownPaths.add('/posts/$name');
        _knownPaths.add('./posts/$name');
        // Slug-based path
        final slug = article.title
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), '-')
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
        if (slug.isNotEmpty) {
          _knownPaths.add('/$slug');
          _knownPaths.add('/$slug/');
          _knownPaths.add('./$slug');
          _knownPaths.add('./$slug/');
          _knownPaths.add('$slug');
          _knownPaths.add('$slug/');
        }
      } else if (article.articleType == ArticleType.page) {
        final slug = article.title
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), '-')
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
        if (slug.isNotEmpty) {
          _knownPaths.add('/$slug');
          _knownPaths.add('/$slug/');
          _knownPaths.add('./$slug');
          _knownPaths.add('./$slug/');
          _knownPaths.add('$slug');
          _knownPaths.add('$slug/');
        }
      }
    }
  }

  Future<void> _runFullScan() async {
    setState(() {
      _isScanning = true;
      _scanStatus = '正在提取链接...';
      _internalResults = [];
      _externalResults = [];
    });

    // Extract all links
    final internalLinks = <_LinkResult>[];
    final externalLinks = <_LinkResult>[];

    final linkRegex = RegExp(r'\[([^\]]*)\]\(([^)]+)\)');

    for (final article in widget.articles) {
      final matches = linkRegex.allMatches(article.content);
      for (final m in matches) {
        final linkText = m.group(1) ?? '';
        final url = m.group(2) ?? '';
        if (url.isEmpty) continue;

        final isExternal = url.startsWith('http://') || url.startsWith('https://');
        final result = _LinkResult(
          article: article,
          linkText: linkText,
          url: url,
          isInternal: !isExternal,
          status: LinkStatus.unknown,
        );

        if (isExternal) {
          externalLinks.add(result);
        } else {
          internalLinks.add(result);
        }
      }
    }

    // Check internal links
    setState(() {
      _scanStatus = '正在检测 ${internalLinks.length} 个内部链接...';
      _internalResults = internalLinks;
    });

    for (final link in internalLinks) {
      _checkInternalLink(link);
    }

    setState(() {});

    // Check external links
    final httpClient = HttpClient();
    httpClient.connectionTimeout = const Duration(seconds: 10);

    for (int i = 0; i < externalLinks.length; i++) {
      final link = externalLinks[i];
      setState(() {
        _scanStatus = '正在检测外部链接 (${i + 1}/${externalLinks.length})...';
        _externalResults = externalLinks.sublist(0, i + 1);
        if (i < externalLinks.length) {
          link.status = LinkStatus.checking;
        }
      });

      await _checkExternalLink(link, httpClient);
      setState(() {});
    }

    httpClient.close();

    setState(() {
      _isScanning = false;
      _scanStatus = '扫描完成：内部 ${_internalResults.where((l) => l.status == LinkStatus.dead).length}/${_internalResults.length} 个死链，外部 ${_externalResults.where((l) => l.status == LinkStatus.dead).length}/${_externalResults.length} 个死链';
      _externalResults = externalLinks;
    });
  }

  void _checkInternalLink(_LinkResult link) {
    final url = link.url.trim();

    // Skip anchor-only links
    if (url.startsWith('#')) {
      link.status = LinkStatus.alive;
      return;
    }

    // Check against known paths
    if (_knownPaths.contains(url)) {
      link.status = LinkStatus.alive;
      return;
    }

    // Check if it's a relative path that exists
    final normalizedUrl = url
        .replaceAll(RegExp(r'^\./'), '')
        .replaceAll(RegExp(r'^/'), '');
    if (_knownPaths.any((p) => p.replaceAll(RegExp(r'^\./'), '').replaceAll(RegExp(r'^/'), '') == normalizedUrl)) {
      link.status = LinkStatus.alive;
      return;
    }

    // Check if any known path ends with the normalized URL
    if (_knownPaths.any((p) {
      final np = p.replaceAll(RegExp(r'^\./'), '').replaceAll(RegExp(r'^/'), '');
      return np == normalizedUrl || np.endsWith('/$normalizedUrl');
    })) {
      link.status = LinkStatus.alive;
      return;
    }

    link.status = LinkStatus.dead;
  }

  Future<void> _checkExternalLink(_LinkResult link, HttpClient client) async {
    try {
      final uri = Uri.tryParse(link.url);
      if (uri == null) {
        link.status = LinkStatus.dead;
        link.error = 'Invalid URL';
        return;
      }

      final request = await client.headUrl(uri);
      request.headers.set('User-Agent', 'HexoLinkChecker/1.0');
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );

      link.httpCode = response.statusCode;
      if (response.statusCode >= 200 && response.statusCode < 400) {
        link.status = LinkStatus.alive;
      } else if (response.statusCode == 404 ||
          response.statusCode == 410 ||
          response.statusCode >= 500) {
        link.status = LinkStatus.dead;
      } else {
        link.status = LinkStatus.alive;
      }
    } on SocketException {
      link.status = LinkStatus.dead;
      link.error = 'Connection refused';
    } on HttpException {
      link.status = LinkStatus.dead;
      link.error = 'HTTP error';
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        link.status = LinkStatus.dead;
        link.error = 'Timeout';
      } else {
        link.status = LinkStatus.unknown;
        link.error = e.toString();
      }
    }
  }

  void _addTargetBlankToAllExternalLinks() {
    final modifiedArticles = <String, String>{};
    final linkRegex = RegExp(r'(\[([^\]]*)\]\((https?://[^)]+)\))');

    for (final article in widget.articles) {
      final matches = linkRegex.allMatches(article.content);
      if (matches.isEmpty) continue;

      String newContent = article.content;
      bool modified = false;

      for (final m in matches.toList().reversed) {
        final fullMatch = m.group(0)!;
        final linkText = m.group(2) ?? '';
        final url = m.group(3) ?? '';

        if (!fullMatch.contains('target=')) {
          final replacement = '[$linkText]($url){target="_blank"}';
          final start = m.start;
          final end = m.end;
          newContent =
              newContent.substring(0, start) + replacement + newContent.substring(end);
          modified = true;
        }
      }

      if (modified) {
        modifiedArticles[article.id] = newContent;
      }
    }

    if (modifiedArticles.isNotEmpty) {
      final newArticles = widget.articles.map((a) {
        final newContent = modifiedArticles[a.id];
        return newContent != null ? a.copyWith(content: newContent) : a;
      }).toList();
      widget.onArticlesChanged?.call(newArticles);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已为 ${modifiedArticles.length} 篇文章的外部链接添加 target="_blank"')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有需要修改的外部链接')),
      );
    }
  }

  void _batchReplaceDeadInternalLinks() {
    final deadLinks = _internalResults.where((l) => l.status == LinkStatus.dead).toList();
    if (deadLinks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有需要修复的死链接')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => _BatchReplaceDialog(
        deadLinks: deadLinks,
        knownPaths: _knownPaths.toList()..sort(),
        onReplace: (replacements) {
          _applyReplacements(replacements);
        },
      ),
    );
  }

  void _applyReplacements(Map<String, String> replacements) {
    final modifiedArticles = <String, String>{};

    for (final entry in replacements.entries) {
      final oldUrl = entry.key;
      final newUrl = entry.value;
      if (oldUrl == newUrl) continue;

      for (final link in _internalResults) {
        if (link.url == oldUrl) {
          final article = link.article;
          final escaped = RegExp.escape(oldUrl);
          final regex = RegExp('\\[([^\\]]*)\\]\\($escaped\\)');
          final newContent = article.content.replaceAll(regex, '[${link.linkText}]($newUrl)');
          modifiedArticles[article.id] = newContent;
        }
      }
    }

    final newArticles = widget.articles.map((a) {
      final newContent = modifiedArticles[a.id];
      return newContent != null ? a.copyWith(content: newContent) : a;
    }).toList();
    widget.onArticlesChanged?.call(newArticles);

    // Re-scan
    _buildKnownPaths();
    _runFullScan();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已修复 ${modifiedArticles.length} 篇文章中的死链接')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('链接检测'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              text: _internalResults.any((l) => l.status == LinkStatus.dead)
                  ? '内部链接检测 (${_internalResults.where((l) => l.status == LinkStatus.dead).length}死)'
                  : '内部链接检测',
            ),
            Tab(
              text: _externalResults.any((l) => l.status == LinkStatus.dead)
                  ? '外部链接检测 (${_externalResults.where((l) => l.status == LinkStatus.dead).length}死)'
                  : '外部链接检测',
            ),
          ],
        ),
        actions: [
          if (_isScanning)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 200,
                  child: Text(
                    _scanStatus,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新扫描',
            onPressed: _isScanning ? null : () {
              _buildKnownPaths();
              _runFullScan();
            },
          ),
          PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (value) {
              switch (value) {
                case 'target_blank':
                  _addTargetBlankToAllExternalLinks();
                  break;
                case 'batch_replace':
                  _batchReplaceDeadInternalLinks();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'target_blank',
                child: ListTile(
                  leading: Icon(Icons.open_in_new),
                  title: Text('统一设置新窗口打开'),
                  subtitle: Text('为所有外部链接添加 target="_blank"'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'batch_replace',
                child: ListTile(
                  leading: Icon(Icons.link_off),
                  title: Text('批量修复死链接'),
                  subtitle: Text('替换已失效的内部链接'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isScanning)
            LinearProgressIndicator(
              value: _internalResults.isEmpty && _externalResults.isEmpty
                  ? null
                  : (_internalResults.length + _externalResults.length) /
                      (_internalResults.length +
                          _externalResults.length +
                          widget.articles.fold<int>(
                              0,
                              (sum, a) =>
                                  sum +
                                  RegExp(r'\[([^\]]*)\]\(([^)]+)\)')
                                      .allMatches(a.content)
                                      .length -
                                  _externalResults.length -
                                  _internalResults.length)),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildLinkList(_internalResults, isInternal: true),
                _buildLinkList(_externalResults, isInternal: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkList(List<_LinkResult> results, {required bool isInternal}) {
    if (results.isEmpty && !_isScanning) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isInternal ? Icons.insert_link : Icons.language,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              isInternal ? '没有找到内部链接' : '没有找到外部链接',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    if (results.isEmpty && _isScanning) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final link = results[index];
        return _LinkResultTile(
          link: link,
          onTap: () => widget.onOpenArticle(link.article),
        );
      },
    );
  }
}

class _LinkResultTile extends StatelessWidget {
  final _LinkResult link;
  final VoidCallback onTap;

  const _LinkResultTile({
    required this.link,
    required this.onTap,
  });

  IconData _statusIcon() {
    switch (link.status) {
      case LinkStatus.alive:
        return Icons.check_circle;
      case LinkStatus.dead:
        return Icons.cancel;
      case LinkStatus.checking:
        return Icons.hourglass_top;
      case LinkStatus.unknown:
        return Icons.help_outline;
    }
  }

  Color _statusColor() {
    switch (link.status) {
      case LinkStatus.alive:
        return Colors.green;
      case LinkStatus.dead:
        return Colors.red;
      case LinkStatus.checking:
        return Colors.orange;
      case LinkStatus.unknown:
        return Colors.grey;
    }
  }

  String _statusText() {
    switch (link.status) {
      case LinkStatus.alive:
        return '正常';
      case LinkStatus.dead:
        return '失效';
      case LinkStatus.checking:
        return '检测中...';
      case LinkStatus.unknown:
        return '未知';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      link.article.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(_statusIcon(), size: 18, color: _statusColor()),
                  const SizedBox(width: 4),
                  Text(
                    _statusText(),
                    style: TextStyle(
                      color: _statusColor(),
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.link, size: 14, color: Colors.blueGrey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      link.url,
                      style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 13,
                        decoration: TextDecoration.underline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (link.linkText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.text_fields, size: 14, color: Colors.blueGrey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        link.linkText,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (link.httpCode != null || link.error != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (link.httpCode != null) ...[
                      const Icon(Icons.http, size: 14, color: Colors.blueGrey),
                      const SizedBox(width: 4),
                      Text(
                        'HTTP ${link.httpCode}',
                        style: TextStyle(
                          color: link.httpCode! >= 200 && link.httpCode! < 400
                              ? Colors.green
                              : Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (link.error != null) ...[
                      if (link.httpCode != null)
                        const SizedBox(width: 12),
                      const Icon(Icons.error_outline, size: 14, color: Colors.red),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          link.error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BatchReplaceDialog extends StatefulWidget {
  final List<_LinkResult> deadLinks;
  final List<String> knownPaths;
  final void Function(Map<String, String>) onReplace;

  const _BatchReplaceDialog({
    required this.deadLinks,
    required this.knownPaths,
    required this.onReplace,
  });

  @override
  State<_BatchReplaceDialog> createState() => _BatchReplaceDialogState();
}

class _BatchReplaceDialogState extends State<_BatchReplaceDialog> {
  final Map<String, TextEditingController> _controllers = {};
  late List<String> _filteredPaths;

  @override
  void initState() {
    super.initState();
    _filteredPaths = List.from(widget.knownPaths);
    for (final link in widget.deadLinks) {
      _controllers[link.url] = TextEditingController(text: link.url);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uniqueUrls = widget.deadLinks.map((l) => l.url).toSet().toList();

    return AlertDialog(
      title: const Text('批量修复死链接'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '共 ${uniqueUrls.length} 个失效的内部链接需要修复',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                hintText: '搜索可用的路径...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (query) {
                setState(() {
                  _filteredPaths = query.isEmpty
                      ? List.from(widget.knownPaths)
                      : widget.knownPaths
                          .where((p) =>
                              p.toLowerCase().contains(query.toLowerCase()))
                          .toList();
                });
              },
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: uniqueUrls.map((url) {
                  final articles = widget.deadLinks
                      .where((l) => l.url == url)
                      .map((l) => l.article.title)
                      .toSet()
                      .toList();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.link_off,
                                size: 16, color: Colors.red),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                url,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (articles.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 20, top: 2),
                            child: Text(
                              '引用自: ${articles.join(', ')}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _controllers[url],
                                decoration: const InputDecoration(
                                  hintText: '输入新路径...',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
                                ),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        if (_filteredPaths.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            runSpacing: 2,
                            children: _filteredPaths.take(10).map((path) {
                              return ActionChip(
                                label: Text(
                                  path,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: () {
                                  _controllers[url]?.text = path;
                                },
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final replacements = <String, String>{};
            for (final entry in _controllers.entries) {
              replacements[entry.key] = entry.value.text;
            }
            widget.onReplace(replacements);
            Navigator.of(context).pop();
          },
          child: const Text('应用替换'),
        ),
      ],
    );
  }
}