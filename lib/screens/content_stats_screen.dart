import 'package:flutter/material.dart';

import '../models/article.dart';
import '../models/repo_config.dart';
import '../services/writing_stats_service.dart';

/// 内容统计面板：聚合本地草稿与已发布文章，展示写作全景。
///
/// 数据全部来自本地 drafts + repos，无需网络与 AI。
/// 统计维度：总量指标、标签云、分类分布、近 30 天写作趋势、站点分布。
class ContentStatsScreen extends StatefulWidget {
  final List<Article> drafts;
  final List<RepoConfig> repos;

  const ContentStatsScreen({
    super.key,
    required this.drafts,
    required this.repos,
  });

  @override
  State<ContentStatsScreen> createState() => _ContentStatsScreenState();
}

class _ContentStatsScreenState extends State<ContentStatsScreen> {
  _ContentStats? _cached;
  List<Article>? _cachedDrafts;
  List<RepoConfig>? _cachedRepos;

  _ContentStats _stats() {
    if (_cached == null ||
        _cachedDrafts != widget.drafts ||
        _cachedRepos != widget.repos) {
      _cached = _buildStats();
      _cachedDrafts = widget.drafts;
      _cachedRepos = widget.repos;
    }
    return _cached!;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final drafts = widget.drafts;
    final stats = _stats();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('内容统计',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface)),
            const Spacer(),
            Text('共 ${drafts.length} 篇 · ${stats.totalWords} 字',
                style: TextStyle(fontSize: 12.5, color: cs.outline)),
          ],
        ),
        const SizedBox(height: 16),
        // ── 总量指标 ──
        Row(children: [
          _statCard(context, '总字数', '${stats.totalWords}', Icons.notes,
              const Color(0xFF0EA5E9)),
          const SizedBox(width: 10),
          _statCard(context, '草稿总数', '${drafts.length}', Icons.article_outlined,
              const Color(0xFF10B981)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _statCard(context, '已发布', '${stats.publishedCount}',
              Icons.public, const Color(0xFF8B5CF6)),
          const SizedBox(width: 10),
          _statCard(context, '今日更新', '${stats.todayDrafts}',
              Icons.today, const Color(0xFFF59E0B)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _statCard(context, '总标签数', '${stats.tagCount}',
              Icons.label_outline, const Color(0xFFF43F5E)),
          const SizedBox(width: 10),
          _statCard(context, '总分类数', '${stats.categoryCount}',
              Icons.folder_outlined, const Color(0xFF14B8A6)),
        ]),
        const SizedBox(height: 20),
        // ── 标签云 ──
        _sectionTitle(context, '标签分布'),
        const SizedBox(height: 8),
        if (stats.tagCount == 0)
          _emptyHint('暂无标签')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in stats.topTags)
                Chip(
                  label: Text('${t.$1} ×${t.$2}',
                      style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: cs.primary.withOpacity(0.1),
                  side: BorderSide(color: cs.primary.withOpacity(0.3)),
                ),
            ],
          ),
        const SizedBox(height: 20),
        // ── 分类分布 ──
        _sectionTitle(context, '分类分布'),
        const SizedBox(height: 8),
        if (stats.categoryCount == 0)
          _emptyHint('暂无分类')
        else
          Column(
            children: [
              for (final c in stats.topCategories)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 140,
                          child: Text(c.$1,
                              style: const TextStyle(fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: stats.maxCategory == 0
                                ? 0
                                : c.$2 / stats.maxCategory,
                            minHeight: 8,
                            backgroundColor: cs.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                          width: 32,
                          child: Text('${c.$2}',
                              style: const TextStyle(fontSize: 12),
                              textAlign: TextAlign.right)),
                    ],
                  ),
                ),
            ],
          ),
        const SizedBox(height: 20),
        // ── 近 30 天写作趋势 ──
        _sectionTitle(context, '近 30 天写作趋势'),
        const SizedBox(height: 12),
        _trendChart(context, stats.dailyTrend),
        const SizedBox(height: 20),
        // ── 站点分布 ──
        _sectionTitle(context, '站点分布'),
        const SizedBox(height: 8),
        if (stats.siteCount == 0)
          _emptyHint('暂无站点文章')
        else
          Column(
            children: [
              for (final s in stats.topSites)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 180,
                          child: Text(s.$1,
                              style: const TextStyle(fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: stats.maxSite == 0
                                ? 0
                                : s.$2 / stats.maxSite,
                            minHeight: 8,
                            backgroundColor: cs.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                          width: 32,
                          child: Text('${s.$2}',
                              style: const TextStyle(fontSize: 12),
                              textAlign: TextAlign.right)),
                    ],
                  ),
                ),
            ],
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  _ContentStats _buildStats() {
    int totalWords = 0;
    int todayDrafts = 0;
    int published = 0;
    final tagCount = <String, int>{};
    final catCount = <String, int>{};
    final siteCount = <String, int>{};
    final todayKey = _dateKey(DateTime.now());

    for (final a in widget.drafts) {
      final words = WritingStatsService.countWords(a.content);
      totalWords += words;
      if (a.published || !a.isDraft) published++;
      if (_dateKey(a.updatedAt) == todayKey) todayDrafts++;
      for (final t in a.tags) {
        // 大小写归一化，避免同一标签重复计数
        final k = t.trim().toLowerCase();
        if (k.isNotEmpty) tagCount[k] = (tagCount[k] ?? 0) + 1;
      }
      for (final c in a.categories) {
        final k = c.trim().toLowerCase();
        if (k.isNotEmpty) catCount[k] = (catCount[k] ?? 0) + 1;
      }
      final siteId = a.repoId;
      if (siteId != null && siteId.isNotEmpty) {
        siteCount[siteId] = (siteCount[siteId] ?? 0) + 1;
      }
    }

    // 近 30 天趋势：按 updatedAt 统计每日更新篇数
    final now = DateTime.now();
    final dailyTrend = <String, int>{};
    for (var i = 29; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      dailyTrend[_dateKey(d)] = 0;
    }
    for (final a in widget.drafts) {
      final k = _dateKey(a.updatedAt);
      if (dailyTrend.containsKey(k)) dailyTrend[k] = dailyTrend[k]! + 1;
    }

    final topTags = tagCount.entries
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCategories = catCount.entries
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topSites = siteCount.entries
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 站点名映射
    final nameById = <String, String>{
      for (final r in widget.repos) r.id: r.name,
    };
    final siteEntries = <(String, int)>[
      for (final e in topSites)
        (nameById[e.key] ?? e.key, e.value),
    ];

    return _ContentStats(
      totalWords: totalWords,
      todayDrafts: todayDrafts,
      publishedCount: published,
      tagCount: tagCount.length,
      categoryCount: catCount.length,
      topTags: topTags.map((e) => (e.key, e.value)).toList(),
      topCategories: topCategories.map((e) => (e.key, e.value)).toList(),
      topSites: siteEntries,
      dailyTrend: dailyTrend,
    );
  }

  Widget _statCard(BuildContext context, String label, String value,
      IconData icon, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Card(
        color: cs.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: color),
              ),
              const SizedBox(height: 10),
              Text(value,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(fontSize: 12, color: cs.outline)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    final cs = Theme.of(context).colorScheme;
    return Text(title,
        style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface));
  }

  Widget _emptyHint(String text) {
    return Text(text,
        style: const TextStyle(fontSize: 13, color: Colors.grey));
  }

  Widget _trendChart(BuildContext context, Map<String, int> trend) {
    final cs = Theme.of(context).colorScheme;
    final entries = trend.entries.toList();
    final maxValue = entries.fold<int>(0, (m, e) => e.value > m ? e.value : m);
    final height = 120.0;
    final barWidth = 8.0;
    return SizedBox(
      height: height + 24,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: CustomPaint(
              painter: _TrendBarPainter(
                entries: entries,
                maxValue: maxValue == 0 ? 1 : maxValue,
                barWidth: barWidth,
                barColor: cs.primary,
                height: height,
              ),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }

  static String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

class _ContentStats {
  final int totalWords;
  final int todayDrafts;
  final int publishedCount;
  final int tagCount;
  final int categoryCount;
  final List<(String, int)> topTags;
  final List<(String, int)> topCategories;
  final List<(String, int)> topSites;
  final Map<String, int> dailyTrend;

  const _ContentStats({
    required this.totalWords,
    required this.todayDrafts,
    required this.publishedCount,
    required this.tagCount,
    required this.categoryCount,
    required this.topTags,
    required this.topCategories,
    required this.topSites,
    required this.dailyTrend,
  });

  int get maxCategory =>
      topCategories.fold<int>(0, (m, e) => e.$2 > m ? e.$2 : m);
  int get maxSite => topSites.fold<int>(0, (m, e) => e.$2 > m ? e.$2 : m);
  int get siteCount => topSites.length;
}

/// 近 30 天写作趋势柱状图
class _TrendBarPainter extends CustomPainter {
  final List<MapEntry<String, int>> entries;
  final int maxValue;
  final double barWidth;
  final Color barColor;
  final double height;

  _TrendBarPainter({
    required this.entries,
    required this.maxValue,
    required this.barWidth,
    required this.barColor,
    required this.height,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty) return;
    final gap = size.width / entries.length;
    final paint = Paint()..color = barColor;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e.value <= 0) continue;
      final ratio = e.value / maxValue;
      final barHeight = (ratio * height).clamp(2.0, height);
      final x = i * gap + (gap - barWidth) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, height - barHeight, barWidth, barHeight),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_TrendBarPainter oldDelegate) =>
      oldDelegate.entries != entries ||
      oldDelegate.maxValue != maxValue ||
      oldDelegate.barColor != barColor;
}
