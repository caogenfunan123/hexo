import 'package:flutter/material.dart';
import 'dart:convert';
import '../models/article.dart';
import '../models/article_type.dart';
import '../models/git_provider.dart';
import '../models/repo_config.dart';
import '../services/github_service.dart';

class BatchToolsScreen extends StatefulWidget {
  final List<Article> articles;
  final Function(List<Article> updatedArticles) onArticlesUpdated;
  final GitHubService? github;
  final List<RepoConfig> repos;

  const BatchToolsScreen({
    super.key,
    required this.articles,
    required this.onArticlesUpdated,
    this.github,
    this.repos = const [],
  });

  @override
  State<BatchToolsScreen> createState() => _BatchToolsScreenState();
}

class _BatchToolsScreenState extends State<BatchToolsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<Article> _articles;

  // FrontMatter state
  final Set<String> _selectedFields = {};
  final Map<String, TextEditingController> _fieldControllers = {};
  String _fmTargetType = 'all'; // all, draft, published
  final Set<String> _fmSelectedArticleIds = {};

  // Image path state
  String _imageConversionMode = 'rel2abs'; // rel2abs, abs2rel
  String _imageBasePath = '';
  final Set<String> _imgSelectedArticleIds = {};

  // Format state
  bool _formatHeadings = true;
  bool _formatLists = true;
  bool _formatCodeBlocks = true;
  final Set<String> _fmtSelectedArticleIds = {};

  // Publish-to-site state
  String? _pubRepoId;
  final Set<String> _pubSelectedArticleIds = {};

  // Undo snapshots
  List<Article>? _fmUndoSnapshot;
  List<Article>? _imgUndoSnapshot;
  List<Article>? _fmtUndoSnapshot;

  bool _isProcessing = false;
  double _progress = 0.0;
  int _progressTotal = 0;

  static const List<String> _fmFields = ['tags', 'categories', 'author', 'template'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _articles = List<Article>.from(widget.articles);
    for (final field in _fmFields) {
      _fieldControllers[field] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _fieldControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<Article> _getFilteredArticles(String targetType) {
    switch (targetType) {
      case 'draft':
        return _articles.where((a) => a.isDraft).toList();
      case 'published':
        return _articles.where((a) => !a.isDraft).toList();
      default:
        return _articles;
    }
  }

  void _toggleSelectAll(String tab, {bool select = true}) {
    setState(() {
      final target = _getFilteredArticles(
        tab == 'fm' ? _fmTargetType : (tab == 'img' ? 'all' : 'all'),
      );
      final ids = target.map((a) => a.id).toSet();
      final selectedSet = tab == 'fm'
          ? _fmSelectedArticleIds
          : tab == 'img'
              ? _imgSelectedArticleIds
              : tab == 'fmt'
                  ? _fmtSelectedArticleIds
                  : _pubSelectedArticleIds;
      if (select) {
        selectedSet.addAll(ids);
      } else {
        selectedSet.removeAll(ids);
      }
    });
  }

  // ─── FrontMatter Modification ───────────────────────────────────────────

  void _previewFrontMatterChanges() {
    final selected = _articles.where((a) => _fmSelectedArticleIds.contains(a.id)).toList();
    if (selected.isEmpty) {
      _showSnackBar('请先选择目标文章');
      return;
    }
    if (_selectedFields.isEmpty) {
      _showSnackBar('请选择要修改的字段');
      return;
    }

    final previews = <Map<String, String>>[];
    for (final article in selected) {
      final oldValues = <String>[];
      final newValues = <String>[];
      for (final field in _selectedFields) {
        final newVal = _fieldControllers[field]?.text.trim() ?? '';
        if (field == 'tags') {
          oldValues.add('tags: ${article.tags.join(', ')}');
          newValues.add('tags: $newVal');
        } else if (field == 'categories') {
          oldValues.add('categories: ${article.categories.join(', ')}');
          newValues.add('categories: $newVal');
        } else if (field == 'author') {
          final currentAuthor = _extractFrontMatterField(article.content, 'author');
          oldValues.add('author: $currentAuthor');
          newValues.add('author: $newVal');
        } else if (field == 'template') {
          oldValues.add('template: ${article.templateId ?? '无'}');
          newValues.add('template: $newVal');
        }
      }
      previews.add({
        'title': article.title,
        'old': oldValues.join('\n'),
        'new': newValues.join('\n'),
      });
    }

    _showPreviewDialog(
      title: 'FrontMatter 修改预览',
      previews: previews,
      onApply: () => _applyFrontMatterChanges(selected),
    );
  }

  Future<void> _applyFrontMatterChanges(List<Article> selected) async {
    _fmUndoSnapshot = List<Article>.from(_articles);
    _startProgress(selected.length);

    final updated = List<Article>.from(_articles);
    for (int i = 0; i < selected.length; i++) {
      final article = selected[i];
      final idx = _articles.indexWhere((a) => a.id == article.id);
      if (idx < 0) continue;
      var newArticle = article;
      for (final field in _selectedFields) {
        final val = _fieldControllers[field]?.text.trim() ?? '';
        switch (field) {
          case 'tags':
            newArticle = newArticle.copyWith(
              tags: val.isEmpty ? [] : val.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
            );
            break;
          case 'categories':
            newArticle = newArticle.copyWith(
              categories: val.isEmpty ? [] : val.split(',').map((c) => c.trim()).where((c) => c.isNotEmpty).toList(),
            );
            break;
          case 'author':
            newArticle = newArticle.copyWith(
              content: _setFrontMatterField(newArticle.content, 'author', val),
            );
            break;
          case 'template':
            newArticle = newArticle.copyWith(templateId: val.isEmpty ? null : val);
            break;
        }
      }
      updated[idx] = newArticle;
      _updateProgress(i + 1);
    }

    _articles = updated;
    _fmSelectedArticleIds.clear();
    _endProgress();
    _showSnackBar('FrontMatter 批量修改完成');
    widget.onArticlesUpdated(_articles);
  }

  void _undoFrontMatterChanges() {
    if (_fmUndoSnapshot == null) return;
    setState(() {
      _articles = List<Article>.from(_fmUndoSnapshot!);
      _fmUndoSnapshot = null;
    });
    widget.onArticlesUpdated(_articles);
    _showSnackBar('已撤销 FrontMatter 修改');
  }

  // ─── Image Path Conversion ──────────────────────────────────────────────

  void _previewImagePathChanges() {
    final selected = _articles.where((a) => _imgSelectedArticleIds.contains(a.id)).toList();
    if (selected.isEmpty) {
      _showSnackBar('请先选择目标文章');
      return;
    }

    final previews = <Map<String, String>>[];
    for (final article in selected) {
      final oldPaths = _extractImagePaths(article.content);
      final newPaths = oldPaths.map((p) => _convertImagePath(p)).toList();
      if (oldPaths.isNotEmpty && !_listsEqual(oldPaths, newPaths)) {
        previews.add({
          'title': article.title,
          'old': oldPaths.join('\n'),
          'new': newPaths.join('\n'),
        });
      }
    }

    if (previews.isEmpty) {
      _showSnackBar('所选文章中没有需要转换的图片路径');
      return;
    }

    _showPreviewDialog(
      title: '图片路径转换预览',
      previews: previews,
      onApply: () => _applyImagePathChanges(selected),
    );
  }

  Future<void> _applyImagePathChanges(List<Article> selected) async {
    _imgUndoSnapshot = List<Article>.from(_articles);
    _startProgress(selected.length);

    final updated = List<Article>.from(_articles);
    for (int i = 0; i < selected.length; i++) {
      final article = selected[i];
      final idx = _articles.indexWhere((a) => a.id == article.id);
      if (idx < 0) continue;
      final newContent = _convertImagePathsInContent(article.content);
      updated[idx] = article.copyWith(content: newContent);
      _updateProgress(i + 1);
    }

    _articles = updated;
    _imgSelectedArticleIds.clear();
    _endProgress();
    _showSnackBar('图片路径批量转换完成');
    widget.onArticlesUpdated(_articles);
  }

  void _undoImagePathChanges() {
    if (_imgUndoSnapshot == null) return;
    setState(() {
      _articles = List<Article>.from(_imgUndoSnapshot!);
      _imgUndoSnapshot = null;
    });
    widget.onArticlesUpdated(_articles);
    _showSnackBar('已撤销图片路径转换');
  }

  // ─── Batch Formatting ───────────────────────────────────────────────────

  void _previewFormatChanges() {
    final selected = _articles.where((a) => _fmtSelectedArticleIds.contains(a.id)).toList();
    if (selected.isEmpty) {
      _showSnackBar('请先选择目标文章');
      return;
    }

    final previews = <Map<String, String>>[];
    for (final article in selected) {
      final formatted = _formatMarkdown(article.content);
      if (formatted != article.content) {
        final oldPreview = article.content.length > 200
            ? '${article.content.substring(0, 200)}...'
            : article.content;
        final newPreview = formatted.length > 200
            ? '${formatted.substring(0, 200)}...'
            : formatted;
        previews.add({
          'title': article.title,
          'old': oldPreview,
          'new': newPreview,
        });
      }
    }

    if (previews.isEmpty) {
      _showSnackBar('所选文章无需格式化');
      return;
    }

    _showPreviewDialog(
      title: '格式化预览',
      previews: previews,
      onApply: () => _applyFormatChanges(selected),
    );
  }

  Future<void> _applyFormatChanges(List<Article> selected) async {
    _fmtUndoSnapshot = List<Article>.from(_articles);
    _startProgress(selected.length);

    final updated = List<Article>.from(_articles);
    for (int i = 0; i < selected.length; i++) {
      final article = selected[i];
      final idx = _articles.indexWhere((a) => a.id == article.id);
      if (idx < 0) continue;
      updated[idx] = article.copyWith(content: _formatMarkdown(article.content));
      _updateProgress(i + 1);
    }

    _articles = updated;
    _fmtSelectedArticleIds.clear();
    _endProgress();
    _showSnackBar('批量格式化完成');
    widget.onArticlesUpdated(_articles);
  }

  void _undoFormatChanges() {
    if (_fmtUndoSnapshot == null) return;
    setState(() {
      _articles = List<Article>.from(_fmtUndoSnapshot!);
      _fmtUndoSnapshot = null;
    });
    widget.onArticlesUpdated(_articles);
    _showSnackBar('已撤销格式化');
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  String _extractFrontMatterField(String content, String field) {
    final trimmed = content.trimLeft();
    if (!trimmed.startsWith('---')) return '';
    final end = content.indexOf('\n---', 3);
    if (end < 0) return '';
    final fm = content.substring(3, end);
    for (final line in fm.split('\n')) {
      final t = line.trim();
      if (t.startsWith('$field:')) {
        final v = t.substring(field.length + 1).trim();
        if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
          return v.substring(1, v.length - 1);
        }
        return v;
      }
    }
    return '';
  }

  String _setFrontMatterField(String content, String field, String value) {
    final trimmed = content.trimLeft();
    if (!trimmed.startsWith('---')) {
      if (value.isEmpty) return content;
      return '---\n$field: $value\n---\n\n$content';
    }
    final end = content.indexOf('\n---', 3);
    if (end < 0) return content;
    final fm = content.substring(3, end);
    final body = content.substring(end + 4);
    final lines = fm.split('\n');
    final newLines = <String>[];
    bool found = false;
    for (final line in lines) {
      final t = line.trim();
      if (t.startsWith('$field:')) {
        found = true;
        if (value.isNotEmpty) {
          newLines.add('$field: $value');
        }
      } else {
        newLines.add(line);
      }
    }
    if (!found && value.isNotEmpty) {
      newLines.add('$field: $value');
    }
    return '---\n${newLines.join('\n')}\n---$body';
  }

  List<String> _extractImagePaths(String content) {
    final regex = RegExp(r'!\[.*?\]\((.*?)\)');
    final paths = <String>[];
    for (final m in regex.allMatches(content)) {
      paths.add(m.group(1)!);
    }
    return paths;
  }

  String _convertImagePath(String path) {
    if (_imageConversionMode == 'rel2abs') {
      if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('/')) {
        return path;
      }
      final base = _imageBasePath.isEmpty ? '/' : _imageBasePath.replaceAll(RegExp(r'/+$'), '');
      return '$base/${path.replaceAll(RegExp(r'^/+'), '')}';
    } else {
      if (path.startsWith('http://') || path.startsWith('https://')) {
        final uri = Uri.tryParse(path);
        if (uri != null) {
          return uri.path.replaceAll(RegExp(r'^/+'), '');
        }
        return path;
      }
      if (_imageBasePath.isNotEmpty && path.startsWith(_imageBasePath)) {
        return path.substring(_imageBasePath.length).replaceAll(RegExp(r'^/+'), '');
      }
      if (path.startsWith('/')) {
        return path.substring(1);
      }
      return path;
    }
  }

  String _convertImagePathsInContent(String content) {
    final regex = RegExp(r'!\[(.*?)\]\((.*?)\)');
    return content.replaceAllMapped(regex, (m) {
      final alt = m.group(1)!;
      final oldPath = m.group(2)!;
      final newPath = _convertImagePath(oldPath);
      return '![$alt]($newPath)';
    });
  }

  String _formatMarkdown(String content) {
    var result = content;

    if (_formatHeadings) {
      result = result.replaceAllMapped(
        RegExp(r'^(#{1,6})([^\s#])', multiLine: true),
        (m) => '${m.group(1)} ${m.group(2)}',
      );
      result = result.replaceAllMapped(
        RegExp(r'(\n|^)(#{1,6}[^\n]+)(\n)(?!\n)', multiLine: true),
        (m) => '${m.group(1)}${m.group(2)}\n\n',
      );
      result = result.replaceAllMapped(
        RegExp(r'(\n)(?!\n)(#{1,6}[^\n]+)', multiLine: true),
        (m) => '\n\n${m.group(2)}',
      );
      result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    }

    if (_formatLists) {
      result = result.replaceAllMapped(
        RegExp(r'^(\s*)[\*\-+] (.*)$', multiLine: true),
        (m) => '${m.group(1)}- ${m.group(2)}',
      );
      result = result.replaceAllMapped(
        RegExp(r'^(\s*)(\d+)\.(\S)', multiLine: true),
        (m) => '${m.group(1)}${m.group(2)}. ${m.group(3)}',
      );
    }

    if (_formatCodeBlocks) {
      result = result.replaceAllMapped(
        RegExp(r'```(\s*)\n', multiLine: true),
        (m) => '```text\n',
      );
      result = result.replaceAllMapped(
        RegExp(r'```(\w+)\n', multiLine: true),
        (m) => '```${m.group(1)!.toLowerCase()}\n',
      );
    }

    return result;
  }

  bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _startProgress(int total) {
    setState(() {
      _isProcessing = true;
      _progress = 0.0;
      _progressTotal = total;
    });
  }

  void _updateProgress(int current) {
    setState(() {
      _progress = _progressTotal > 0 ? current / _progressTotal : 0.0;
    });
  }

  void _endProgress() {
    setState(() {
      _isProcessing = false;
      _progress = 0.0;
    });
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _showPreviewDialog({
    required String title,
    required List<Map<String, String>> previews,
    required VoidCallback onApply,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: MediaQuery.of(ctx).size.width * 0.8,
          height: MediaQuery.of(ctx).size.height * 0.6,
          child: ListView.builder(
            itemCount: previews.length,
            itemBuilder: (_, i) {
              final p = previews[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p['title']!,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _previewBlock('修改前', p['old']!, Colors.red.shade50, Colors.red.shade700),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _previewBlock('修改后', p['new']!, Colors.green.shade50, Colors.green.shade700),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onApply();
            },
            child: const Text('确认应用'),
          ),
        ],
      ),
    );
  }

  Widget _previewBlock(String label, String text, Color bg, Color fg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label, style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 4),
        Text(
          text.isEmpty ? '(空)' : text,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        ),
      ],
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('批量处理工具'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: cs.onPrimary,
          unselectedLabelColor: cs.onPrimary.withOpacity(0.6),
          indicatorColor: cs.onPrimary,
          tabs: const [
            Tab(text: 'FrontMatter'),
            Tab(text: '图片路径'),
            Tab(text: '格式化'),
            Tab(text: '发布到站点'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              _buildFrontMatterTab(cs),
              _buildImagePathTab(cs),
              _buildFormatTab(cs),
              _buildPublishTab(cs),
            ],
          ),
          if (_isProcessing)
            Container(
              color: Colors.black38,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      '处理中 ${(_progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 200,
                      child: LinearProgressIndicator(value: _progress),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Tab 1: FrontMatter ─────────────────────────────────────────────────

  Widget _buildFrontMatterTab(ColorScheme cs) {
    final filtered = _getFilteredArticles(_fmTargetType);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Section header
        Row(
          children: [
            Icon(Icons.article_outlined, color: cs.primary),
            const SizedBox(width: 8),
            Text('批量修改 FrontMatter', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.primary)),
          ],
        ),
        const SizedBox(height: 16),

        // Field selection
        Text('选择要修改的字段', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: _fmFields.map((field) {
            final selected = _selectedFields.contains(field);
            return FilterChip(
              label: Text(field),
              selected: selected,
              onSelected: (v) {
                setState(() {
                  if (v) {
                    _selectedFields.add(field);
                  } else {
                    _selectedFields.remove(field);
                    _fieldControllers[field]?.clear();
                  }
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // Field value inputs
        ..._selectedFields.map((field) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _fieldControllers[field],
              decoration: InputDecoration(
                labelText: field == 'tags' || field == 'categories' ? '$field (逗号分隔)' : field,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          );
        }),

        // Target type selector
        const SizedBox(height: 8),
        Text('目标文章范围', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'all', label: Text('全部')),
            ButtonSegment(value: 'draft', label: Text('草稿')),
            ButtonSegment(value: 'published', label: Text('已发布')),
          ],
          selected: {_fmTargetType},
          onSelectionChanged: (v) {
            setState(() {
              _fmTargetType = v.first;
              _fmSelectedArticleIds.clear();
            });
          },
        ),
        const SizedBox(height: 16),

        // Select all / deselect all
        Row(
          children: [
            Text('文章列表 (${filtered.length})', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.select_all, size: 18),
              label: const Text('全选'),
              onPressed: () => _toggleSelectAll('fm', select: true),
            ),
            TextButton.icon(
              icon: const Icon(Icons.deselect, size: 18),
              label: const Text('取消全选'),
              onPressed: () => _toggleSelectAll('fm', select: false),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Article list
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('没有匹配的文章', style: TextStyle(color: Colors.grey))),
          )
        else
          ...filtered.map((article) => CheckboxListTile(
                dense: true,
                value: _fmSelectedArticleIds.contains(article.id),
                title: Text(
                  article.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  article.isDraft ? '草稿' : '已发布',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5)),
                ),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _fmSelectedArticleIds.add(article.id);
                    } else {
                      _fmSelectedArticleIds.remove(article.id);
                    }
                  });
                },
              )),
        const SizedBox(height: 16),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.preview),
                label: const Text('预览修改'),
                onPressed: _fmSelectedArticleIds.isNotEmpty && _selectedFields.isNotEmpty
                    ? _previewFrontMatterChanges
                    : null,
              ),
            ),
            if (_fmUndoSnapshot != null) ...[
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.undo),
                label: const Text('撤销'),
                onPressed: _undoFrontMatterChanges,
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ─── Tab 2: Image Path ──────────────────────────────────────────────────

  Widget _buildImagePathTab(ColorScheme cs) {
    final filtered = _articles;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(Icons.image_outlined, color: cs.primary),
            const SizedBox(width: 8),
            Text('批量图片路径转换', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.primary)),
          ],
        ),
        const SizedBox(height: 16),

        // Conversion mode
        Text('转换模式', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'rel2abs', label: Text('相对 → 绝对')),
            ButtonSegment(value: 'abs2rel', label: Text('绝对 → 相对')),
          ],
          selected: {_imageConversionMode},
          onSelectionChanged: (v) {
            setState(() => _imageConversionMode = v.first);
          },
        ),
        const SizedBox(height: 12),

        // Base path
        TextField(
          decoration: InputDecoration(
            labelText: _imageConversionMode == 'rel2abs' ? '基础路径（如 /images/）' : '要去除的前缀路径',
            hintText: _imageConversionMode == 'rel2abs' ? '/images/' : '/images/',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => _imageBasePath = v,
        ),
        const SizedBox(height: 16),

        // Select all / deselect all
        Row(
          children: [
            Text('文章列表 (${filtered.length})', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.select_all, size: 18),
              label: const Text('全选'),
              onPressed: () => _toggleSelectAll('img', select: true),
            ),
            TextButton.icon(
              icon: const Icon(Icons.deselect, size: 18),
              label: const Text('取消全选'),
              onPressed: () => _toggleSelectAll('img', select: false),
            ),
          ],
        ),
        const SizedBox(height: 8),

        ...filtered.map((article) => CheckboxListTile(
              dense: true,
              value: _imgSelectedArticleIds.contains(article.id),
              title: Text(
                article.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                article.isDraft ? '草稿' : '已发布',
                style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5)),
              ),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _imgSelectedArticleIds.add(article.id);
                  } else {
                    _imgSelectedArticleIds.remove(article.id);
                  }
                });
              },
            )),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.preview),
                label: const Text('预览转换'),
                onPressed: _imgSelectedArticleIds.isNotEmpty ? _previewImagePathChanges : null,
              ),
            ),
            if (_imgUndoSnapshot != null) ...[
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.undo),
                label: const Text('撤销'),
                onPressed: _undoImagePathChanges,
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ─── Tab 3: Format ──────────────────────────────────────────────────────

  Widget _buildFormatTab(ColorScheme cs) {
    final filtered = _articles;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(Icons.format_align_left_outlined, color: cs.primary),
            const SizedBox(width: 8),
            Text('批量格式化', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.primary)),
          ],
        ),
        const SizedBox(height: 16),

        // Format options
        Text('格式化选项', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
        const SizedBox(height: 8),
        CheckboxListTile(
          dense: true,
          value: _formatHeadings,
          title: const Text('标准化标题间距', style: TextStyle(fontSize: 14)),
          subtitle: const Text('确保标题前后有适当空行，标题 # 与文字间有空格', style: TextStyle(fontSize: 12)),
          onChanged: (v) => setState(() => _formatHeadings = v ?? true),
        ),
        CheckboxListTile(
          dense: true,
          value: _formatLists,
          title: const Text('统一列表格式', style: TextStyle(fontSize: 14)),
          subtitle: const Text('统一使用 - 作为无序列表标记，确保有序列表数字后有空格', style: TextStyle(fontSize: 12)),
          onChanged: (v) => setState(() => _formatLists = v ?? true),
        ),
        CheckboxListTile(
          dense: true,
          value: _formatCodeBlocks,
          title: const Text('代码块语言标签', style: TextStyle(fontSize: 14)),
          subtitle: const Text('为无语言标签的代码块添加 text，统一语言标签为小写', style: TextStyle(fontSize: 12)),
          onChanged: (v) => setState(() => _formatCodeBlocks = v ?? true),
        ),
        const SizedBox(height: 16),

        // Select all / deselect all
        Row(
          children: [
            Text('文章列表 (${filtered.length})', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.select_all, size: 18),
              label: const Text('全选'),
              onPressed: () => _toggleSelectAll('fmt', select: true),
            ),
            TextButton.icon(
              icon: const Icon(Icons.deselect, size: 18),
              label: const Text('取消全选'),
              onPressed: () => _toggleSelectAll('fmt', select: false),
            ),
          ],
        ),
        const SizedBox(height: 8),

        ...filtered.map((article) => CheckboxListTile(
              dense: true,
              value: _fmtSelectedArticleIds.contains(article.id),
              title: Text(
                article.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                article.isDraft ? '草稿' : '已发布',
                style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5)),
              ),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _fmtSelectedArticleIds.add(article.id);
                  } else {
                    _fmtSelectedArticleIds.remove(article.id);
                  }
                });
              },
            )),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.preview),
                label: const Text('预览格式化'),
                onPressed: _fmtSelectedArticleIds.isNotEmpty ? _previewFormatChanges : null,
              ),
            ),
            if (_fmtUndoSnapshot != null) ...[
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.undo),
                label: const Text('撤销'),
                onPressed: _undoFormatChanges,
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ─── Tab 4: Publish to Site ─────────────────────────────────────────────

  Widget _buildPublishTab(ColorScheme cs) {
    final repos = widget.repos;
    final filtered = _articles.where((a) => a.isDraft).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(Icons.rocket_launch_outlined, color: cs.primary),
            const SizedBox(width: 8),
            Text('批量发布到建站仓库', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.primary)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '将选中的草稿一次性提交到站点仓库，触发一次 CI 构建，全部文章同时上线',
          style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)),
        ),
        const SizedBox(height: 16),

        if (repos.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(Icons.storage_outlined, color: cs.onSurface.withOpacity(0.3), size: 40),
                const SizedBox(height: 8),
                Text('暂无站点仓库', style: TextStyle(color: cs.onSurface.withOpacity(0.6))),
                const SizedBox(height: 4),
                Text('请先在「站点管理」中配置仓库', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.4))),
              ],
            ),
          )
        else ...[
          Text('目标仓库', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _pubRepoId ?? (repos.isNotEmpty ? repos.first.id : null),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: repos.map((r) => DropdownMenuItem(
              value: r.id,
              child: Text('${r.name} (${r.fullName})'),
            )).toList(),
            onChanged: (v) => setState(() => _pubRepoId = v),
          ),
          const SizedBox(height: 16),
        ],

        // Article selection
        Row(
          children: [
            Text('草稿列表 (${filtered.length})', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.select_all, size: 18),
              label: const Text('全选'),
              onPressed: filtered.isEmpty ? null : () => _toggleSelectAll('pub', select: true),
            ),
            TextButton.icon(
              icon: const Icon(Icons.deselect, size: 18),
              label: const Text('取消全选'),
              onPressed: filtered.isEmpty ? null : () => _toggleSelectAll('pub', select: false),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('没有草稿可发布', style: TextStyle(color: cs.onSurface.withOpacity(0.6))),
            ),
          )
        else
          ...filtered.map((article) => CheckboxListTile(
                dense: true,
                value: _pubSelectedArticleIds.contains(article.id),
                title: Text(
                  article.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  article.schedulePublishAt == null
                      ? '未设置定时'
                      : '定时 ${_fmtTime(article.schedulePublishAt!)}',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5)),
                ),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _pubSelectedArticleIds.add(article.id);
                    } else {
                      _pubSelectedArticleIds.remove(article.id);
                    }
                  });
                },
              )),
        const SizedBox(height: 16),

        FilledButton.icon(
          icon: const Icon(Icons.cloud_upload_outlined),
          label: Text('发布选中的 ${_pubSelectedArticleIds.length} 篇文章'),
          onPressed: (repos.isEmpty || _pubSelectedArticleIds.isEmpty)
              ? null
              : _publishSelected,
        ),
        const SizedBox(height: 8),
        if (widget.github == null)
          Text(
            '当前未接入发布服务，请在主界面打开批量工具',
            style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5)),
          ),
      ],
    );
  }

  String _fmtTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  /// 批量发布：一次 Git Data commit 上传全部选中草稿，触发一次 CI 构建
  Future<void> _publishSelected() async {
    final github = widget.github;
    if (github == null) {
      _showSnackBar('未接入发布服务');
      return;
    }
    final repo = widget.repos.where((r) => r.id == _pubRepoId).firstOrNull;
    if (repo == null || repo.token.isEmpty) {
      _showSnackBar('请先选择已配置 Token 的站点仓库');
      return;
    }
    final selected =
        _articles.where((a) => _pubSelectedArticleIds.contains(a.id)).toList();
    if (selected.isEmpty) {
      _showSnackBar('请先选择要发布的草稿');
      return;
    }

    setState(() {
      _isProcessing = true;
      _progress = 0;
      _progressTotal = selected.length;
    });

    try {
      if (repo.provider == GitProviderType.github) {
        // GitHub：一次 Git Data commit 批量上传，触发一次 CI
        final files = <({String path, List<int> bytes})>[];
        for (final a in selected) {
          final isPage = a.articleType == ArticleType.page;
          final basePath = isPage
              ? repo.pagesPath.replaceAll(RegExp(r'/+$'), '')
              : repo.postsPath.replaceAll(RegExp(r'/+$'), '');
          final fileName = a.fileNameForRepo(repo);
          final path = a.remotePath ?? '$basePath/$fileName';
          final md = a.toMarkdownWithFrontMatterForRepo(repo);
          files.add((path: path, bytes: utf8.encode(md)));
        }
        await github.uploadBatchViaGitData(
          token: repo.token,
          owner: repo.owner,
          repo: repo.repo,
          branch: repo.branch,
          files: files,
          message: 'docs: batch publish ${selected.length} articles',
        );
      } else {
        // 非 GitHub：逐篇写入
        for (var i = 0; i < selected.length; i++) {
          await github.upsertArticle(repo, selected[i]);
          setState(() => _progress = (i + 1) / selected.length);
        }
      }

      // 更新本地状态为已发布
      final publishedIds = selected.map((a) => a.id).toSet();
      final updated = _articles.map((a) {
        if (publishedIds.contains(a.id)) {
          return a.copyWith(isDraft: false, published: true, repoId: repo.id);
        }
        return a;
      }).toList();
      setState(() {
        _articles = updated;
        _pubSelectedArticleIds.clear();
        _progress = 1;
      });
      widget.onArticlesUpdated(updated);
      _showSnackBar('批量发布完成：${selected.length} 篇文章已提交到 ${repo.fullName}，CI 构建中');
    } catch (e) {
      _showSnackBar('批量发布失败: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }
}