import 'package:flutter/material.dart';
import '../models/article.dart';
import '../models/blog_site_config.dart';
import '../models/repo_config.dart';

class DraftsScreen extends StatefulWidget {
  final List<Article> drafts;
  final List<RepoConfig> repos;
  final List<BlogSiteConfig> blogSiteConfigs;
  final void Function(Article) onOpen;
  final void Function(Article) onDelete;

  const DraftsScreen({
    super.key,
    required this.drafts,
    required this.repos,
    required this.blogSiteConfigs,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  State<DraftsScreen> createState() => _DraftsScreenState();
}

class _DraftsScreenState extends State<DraftsScreen> {
  String? _selectedSiteId; // null = 全部

  /// 获取站点名称
  String _siteName(String siteId) {
    for (final r in widget.repos) {
      if (r.id == siteId) return r.name;
    }
    for (final s in widget.blogSiteConfigs) {
      if (s.id == siteId) return s.name;
    }
    return '未知站点';
  }

  /// 获取所有站点选项
  List<MapEntry<String?, String>> get _siteOptions {
    final options = <MapEntry<String?, String>>[
      const MapEntry(null, '全部站点'),
    ];
    final seen = <String>{};
    for (final r in widget.repos) {
      if (seen.add(r.id)) {
        options.add(MapEntry(r.id, r.name));
      }
    }
    for (final s in widget.blogSiteConfigs) {
      if (seen.add(s.id)) {
        options.add(MapEntry(s.id, s.name));
      }
    }
    return options;
  }

  /// 按站点过滤后的草稿列表
  List<Article> get _filteredDrafts {
    if (_selectedSiteId == null) return widget.drafts;
    return widget.drafts.where((a) => a.repoId == _selectedSiteId).toList();
  }

  @override
  Widget build(BuildContext context) {
    final drafts = _filteredDrafts;

    return Column(
      children: [
        // ── 站点过滤栏 ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.white,
          child: Row(
            children: [
              const Icon(Icons.filter_list, size: 18, color: Color(0xFF64748B)),
              const SizedBox(width: 8),
              const Text('站点筛选：', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
              Expanded(
                child: DropdownButton<String?>(
                  value: _selectedSiteId,
                  isExpanded: true,
                  isDense: true,
                  underline: const SizedBox(),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                  items: _siteOptions.map((e) => DropdownMenuItem<String?>(
                    value: e.key,
                    child: Text(e.value, overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (v) => setState(() => _selectedSiteId = v),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // ── 草稿列表 ──
        Expanded(
          child: drafts.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.drafts_outlined, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text(
                      _selectedSiteId == null ? '暂无草稿' : '该站点暂无草稿',
                      style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
                    ),
                  ]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: drafts.length,
                  itemBuilder: (_, i) {
                    final a = drafts[i];
                    final wordCount = a.content.replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z]'), '').length;
                    final preview = a.content.replaceAll(RegExp(r'\s+'), ' ').trim();
                    final siteName = a.repoId != null ? _siteName(a.repoId!) : null;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      color: Colors.white,
                      elevation: 0,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => widget.onOpen(a),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(
                                child: Text(a.title.isEmpty ? '未命名' : a.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: a.published ? const Color(0xFF059669).withOpacity(0.1) : const Color(0xFFD97706).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(a.published ? '已发布' : '草稿', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: a.published ? const Color(0xFF059669) : const Color(0xFFD97706))),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'delete') {
                                    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                                      title: const Text('删除草稿'),
                                      content: Text('确认删除「${a.title}」？'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                                        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
                                      ],
                                    ));
                                    if (ok == true) widget.onDelete(a);
                                  }
                                },
                                icon: const Icon(Icons.more_horiz, size: 18, color: Color(0xFF64748B)),
                                itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('删除草稿'))],
                              ),
                            ]),
                            if (preview.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                            ],
                            const SizedBox(height: 8),
                            Row(children: [
                              Icon(Icons.access_time, size: 13, color: Colors.grey.shade400),
                              const SizedBox(width: 4),
                              Text(_fmt(a.updatedAt), style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                              if (siteName != null) ...[
                                const SizedBox(width: 12),
                                Icon(Icons.language, size: 13, color: Colors.grey.shade400),
                                const SizedBox(width: 4),
                                Text(siteName, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                              ],
                              if (wordCount > 0) ...[
                                const SizedBox(width: 12),
                                Icon(Icons.text_fields, size: 13, color: Colors.grey.shade400),
                                const SizedBox(width: 4),
                                Text('$wordCount 字', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                              ],
                            ]),
                            if (a.tags.isNotEmpty)
                              Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 4, runSpacing: 4, children: a.tags.take(4).map((t) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: const Color(0xFF0EA5E9).withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
                                child: Text('#$t', style: const TextStyle(fontSize: 11, color: Color(0xFF0EA5E9))),
                              )).toList())),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _fmt(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}