import 'package:flutter/material.dart';
import '../models/repo_config.dart';
import '../services/github_service.dart';

class SiteEditorScreen extends StatefulWidget {
  final RepoConfig repo;
  final GitHubService github;
  final VoidCallback onSaved;

  const SiteEditorScreen({
    super.key,
    required this.repo,
    required this.github,
    required this.onSaved,
  });

  @override
  State<SiteEditorScreen> createState() => _SiteEditorScreenState();
}

class _SiteEditorScreenState extends State<SiteEditorScreen> {
  late TextEditingController _descCtrl;
  late TextEditingController _titleCtrl;
  late TextEditingController _subtitleCtrl;
  late TextEditingController _authorCtrl;
  late TextEditingController _avatarCtrl;
  late TextEditingController _headerCtrl;
  late TextEditingController _footerCtrl;
  late TextEditingController _aboutCtrl;
  late TextEditingController _guestbookCtrl;
  late TextEditingController _nowCtrl;
  late TextEditingController _worksCtrl;
  late TextEditingController _indexCtrl;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _descCtrl = TextEditingController(text: '个人博客 - 分享技术、生活与思考');
    _titleCtrl = TextEditingController(text: '小子的博客');
    _subtitleCtrl = TextEditingController(text: '记录生活的点滴');
    _authorCtrl = TextEditingController(text: '小子');
    _avatarCtrl = TextEditingController();
    _headerCtrl = TextEditingController();
    _footerCtrl = TextEditingController();
    _aboutCtrl = TextEditingController();
    _guestbookCtrl = TextEditingController();
    _nowCtrl = TextEditingController();
    _worksCtrl = TextEditingController();
    _indexCtrl = TextEditingController();
    _loadSiteData();
  }

  Future<void> _loadSiteData() async {
    try {
      final g = GitHubService();
      final configRaw = await g.getRawFile(widget.repo, '_config.yml');
      if (configRaw != null) {
        final c = configRaw['content']!;
        final titleMatch =
            RegExp(r'^title:\s*(.*)$', multiLine: true).firstMatch(c);
        if (titleMatch != null) _titleCtrl.text = titleMatch.group(1)!.trim();
        final subtitleMatch =
            RegExp(r"^subtitle:\s*'([^']*)'", multiLine: true).firstMatch(c);
        if (subtitleMatch != null)
          _subtitleCtrl.text = subtitleMatch.group(1)!.trim();
        final authorMatch =
            RegExp(r'^author:\s*(.*)$', multiLine: true).firstMatch(c);
        final descMatch =
            RegExp(r"^description:\s*'([^']*)'", multiLine: true).firstMatch(c);
        if (descMatch != null) _descCtrl.text = descMatch.group(1)!.trim();
        if (authorMatch != null) _authorCtrl.text = authorMatch.group(1)!.trim();
      }

      final themeRaw =
          await g.getRawFile(widget.repo, 'themes/A4/_config.yml');
      if (themeRaw != null) {
        final tc = themeRaw['content']!;
        for (final line in tc.split('\n')) {
          final t = line.trim();
          if (t.startsWith('favicon:')) _avatarCtrl.text = t.substring(8).trim();
        }
        final footerMatch = RegExp(r'footer:\s*"([^"]*)"').firstMatch(tc);
        if (footerMatch != null)
          _footerCtrl.text = footerMatch.group(1) ?? '';
        final headerMatch =
            RegExp(r'header:\s*\n((?:\s*-\s*"[^"]*"\n?)+)').firstMatch(tc);
        if (headerMatch != null) {
          _headerCtrl.text = headerMatch
              .group(1)!
              .split(RegExp(r'\s*-\s*"|"\n?\s*'))
              .where((s) => s.isNotEmpty)
              .join('\n');
        }
      }

      final aboutRaw = await g.getRawFile(widget.repo, 'source/about/index.md');
      if (aboutRaw != null) _aboutCtrl.text = aboutRaw['content']!;
      final guestbookRaw =
          await g.getRawFile(widget.repo, 'source/comments/index.md');
      if (guestbookRaw != null) _guestbookCtrl.text = guestbookRaw['content']!;
      final nowRaw = await g.getRawFile(widget.repo, 'source/now/index.md');
      if (nowRaw != null) _nowCtrl.text = nowRaw['content']!;
      final worksRaw = await g.getRawFile(widget.repo, 'source/works/index.md');
      if (worksRaw != null) _worksCtrl.text = worksRaw['content']!;
      final indexRaw =
          await g.getRawFile(widget.repo, 'source/index/index.md');
      if (indexRaw != null) _indexCtrl.text = indexRaw['content']!;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _authorCtrl.dispose();
    _avatarCtrl.dispose();
    _headerCtrl.dispose();
    _footerCtrl.dispose();
    _aboutCtrl.dispose();
    _guestbookCtrl.dispose();
    _nowCtrl.dispose();
    _worksCtrl.dispose();
    _indexCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final g = GitHubService();

      // 1. Update _config.yml
      final configRaw = await g.getRawFile(widget.repo, '_config.yml');
      if (configRaw != null) {
        String cc = configRaw['content']!;
        cc = cc
            .replaceAll(RegExp(r'^title:.*$', multiLine: true),
                'title: ${_titleCtrl.text.trim()}')
            .replaceAll(
                RegExp(r'^subtitle:.*$', multiLine: true),
                "subtitle: '${_subtitleCtrl.text.trim()}'")
            .replaceAll(RegExp(r'^author:.*$', multiLine: true),
                'author: ${_authorCtrl.text.trim()}')
            .replaceAll(
                RegExp(r'^description:.*$', multiLine: true),
                "description: '${_descCtrl.text.trim()}'");
        await g.putRawFile(widget.repo, '_config.yml', cc,
            sha: configRaw['sha']);
      }

      // 2. Update themes/A4/_config.yml
      final themeRaw =
          await g.getRawFile(widget.repo, 'themes/A4/_config.yml');
      if (themeRaw != null) {
        String tc = themeRaw['content']!;
        tc = tc
            .replaceAll(RegExp(r'^favicon:.*$', multiLine: true),
                'favicon: ${_avatarCtrl.text.trim()}')
            .replaceAll(
                RegExp(r'^  footer:.*$', multiLine: true),
                '  footer: "${_footerCtrl.text.trim()}"');
        final headerBlockRe = RegExp(r'^  header:.*?(?=^\s{2}\w)',
            multiLine: true, dotAll: true);
        final headerVal = _headerCtrl.text.trim();
        if (headerVal.isNotEmpty) {
          final lines =
              headerVal.split('\n').map((l) => '    - "${l.trim()}"').join('\n');
          tc = tc.replaceAllMapped(headerBlockRe, (m) => '  header:\n$lines');
        }
        await g.putRawFile(widget.repo, 'themes/A4/_config.yml', tc,
            sha: themeRaw['sha']);
      }

      // 3. Update page files
      Future<void> savePage(String path, String content) async {
        final existing = await g.getRawFile(widget.repo, path);
        await g.putRawFile(widget.repo, path, content,
            sha: existing?['sha']);
      }

      await savePage('source/about/index.md', _aboutCtrl.text);
      await savePage('source/comments/index.md', _guestbookCtrl.text);
      await savePage('source/now/index.md', _nowCtrl.text);
      await savePage('source/works/index.md', _worksCtrl.text);
      await savePage('source/index/index.md', _indexCtrl.text);

      if (mounted) {
        setState(() => _saving = false);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('站点内容已同步到 GitHub，稍后自动部署')),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('网站页面编辑'),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('保存'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('编辑后保存将直接同步到 GitHub 仓库，自动触发部署',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            const SizedBox(height: 16),
            TextField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                    labelText: '网站描述 (description)',
                    hintText: '个人博客 - 分享技术、生活与思考')),
            const SizedBox(height: 12),
            TextField(
                controller: _avatarCtrl,
                decoration: const InputDecoration(
                    labelText: '头像 / Favicon 路径',
                    hintText: '/img/favicon.png')),
            const SizedBox(height: 12),
            TextField(
                controller: _titleCtrl,
                decoration:
                    const InputDecoration(labelText: '网站标题 (title)')),
            const SizedBox(height: 12),
            TextField(
                controller: _subtitleCtrl,
                decoration:
                    const InputDecoration(labelText: '副标题 (subtitle)')),
            const SizedBox(height: 12),
            TextField(
                controller: _authorCtrl,
                decoration: const InputDecoration(labelText: '作者 (author)')),
            const SizedBox(height: 12),
            TextField(
                controller: _headerCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: '首页头部文字 (每行一句)',
                    hintText: '记录生活美好\n写字，是为了把日子留住\n看过大海的人不会忘记海的广阔',
                    helperText: '每行一句，保存后会自动替换首页头部')),
            const SizedBox(height: 12),
            TextField(
                controller: _footerCtrl,
                decoration:
                    const InputDecoration(labelText: '页脚信息')),
            const SizedBox(height: 16),
            const Divider(),
            const Text('页面内容 (Markdown)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
                controller: _aboutCtrl,
                maxLines: 5,
                decoration: const InputDecoration(
                    labelText: '关于页面 (source/about/index.md)',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: _guestbookCtrl,
                maxLines: 5,
                decoration: const InputDecoration(
                    labelText: '留言页面 (source/comments/index.md)',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: _nowCtrl,
                maxLines: 5,
                decoration: const InputDecoration(
                    labelText: 'Now 页面 (source/now/index.md)',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: _worksCtrl,
                maxLines: 5,
                decoration: const InputDecoration(
                    labelText: '作品页面 (source/works/index.md)',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: _indexCtrl,
                maxLines: 5,
                decoration: const InputDecoration(
                    labelText: '首页内容 (source/index/index.md)',
                    border: OutlineInputBorder())),
            const SizedBox(height: 32),
            Center(
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload),
                label: Text(_saving ? '保存中…' : '保存并同步到 GitHub'),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}