import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;

import '../models/article.dart';
import '../models/repo_config.dart';
import '../services/github_service.dart';

class PreviewScreen extends StatefulWidget {
  final List<RepoConfig> repos;
  final GitHubService github;

  const PreviewScreen({
    super.key,
    required this.repos,
    required this.github,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  Article? _article;
  bool _loading = false;
  String? _error;
  RepoConfig? _repo;
  List<GitHubFileItem> _items = [];
  int _selectedIndex = 0;
  bool _rendered = false;

  @override
  void initState() {
    super.initState();
    if (widget.repos.isNotEmpty) {
      _repo = widget.repos.first;
      _loadRepoFiles();
    }
  }

  Future<void> _loadRepoFiles() async {
    if (_repo == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.github.listPosts(_repo!);
      setState(() {
        _items = items;
        _selectedIndex = 0;
        _loading = false;
      });
      if (items.isNotEmpty) {
        _loadArticle(items.first);
      }
    } catch (e) {
      setState(() {
        _error = '加载文件列表失败: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadArticle(GitHubFileItem item) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final article = await widget.github.getArticle(_repo!, item);
      setState(() {
        _article = article;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '加载文章失败: $e';
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    if (_repo != null) {
      await _loadRepoFiles();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 左侧文件列表
        SizedBox(
          width: 200,
          child: Column(
            children: [
              _buildSidebarHeader(),
              const Divider(height: 1),
              Expanded(
                child: _loading && _items.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _items.isEmpty
                        ? const Center(child: Text('暂无文件'))
                        : _buildFileList(),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // 右侧预览区域
        Expanded(
          child: Column(
            children: [
              _buildToolbar(),
              const Divider(height: 1),
              Expanded(
                child: _buildPreviewArea(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidebarHeader() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.grey.shade100,
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<RepoConfig?>(
              value: _repo,
              hint: const Text('选择仓库'),
              isExpanded: true,
              items: [
                for (final r in widget.repos)
                  DropdownMenuItem(
                    value: r,
                    child: Text(
                      r.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
              onChanged: (v) async {
                setState(() {
                  _repo = v;
                  _items = [];
                  _article = null;
                });
                if (v != null) await _loadRepoFiles();
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: '刷新',
          ),
        ],
      ),
    );
  }

  Widget _buildFileList() {
    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (context, i) {
        final item = _items[i];
        final isSelected = i == _selectedIndex;
        return ListTile(
          dense: true,
          selected: isSelected,
          tileColor: isSelected ? Colors.blue.shade50 : null,
          title: Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          trailing: item.lastModified != null
              ? Text(
                  '${item.lastModified!.month}/${item.lastModified!.day}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                )
              : null,
          onTap: () {
            setState(() => _selectedIndex = i);
            _loadArticle(item);
          },
        );
      },
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.grey.shade100,
      child: Row(
        children: [
          Expanded(
            child: Text(
              _article?.title ?? '未选择文章',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Markdown')),
              ButtonSegment(value: true, label: Text('预览')),
            ],
            selected: {_rendered},
            onSelectionChanged: (v) => setState(() => _rendered = v.first),
            style: ButtonStyle(
              textStyle: WidgetStateProperty.all(TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
          if (_article != null && _article!.remotePath != null)
            Text(
              _article!.remotePath!,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  Widget _buildPreviewArea() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.red.shade700)),
          ],
        ),
      );
    }
    if (_article == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('选择左侧文件进行预览'),
          ],
        ),
      );
    }

    if (_rendered) {
      // 渲染 Markdown 预览
      return Markdown(
        data: _article!.toMarkdownWithFrontMatter(),
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          h1: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          h2: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          h3: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          code: const TextStyle(
            fontFamily: 'monospace',
            backgroundColor: Color(0xfff0f0f0),
          ),
          codeblockDecoration: BoxDecoration(
            color: const Color(0xfff0f0f0),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );
    } else {
      // 原始 Markdown 源码
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          _article!.toMarkdownWithFrontMatter(),
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
          ),
        ),
      );
    }
  }
}
