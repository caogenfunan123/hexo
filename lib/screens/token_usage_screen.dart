import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../services/usage_tracker.dart';

/// Token 用量统计仪表盘：总体聚合 + 按模型 + 近 7 天趋势
class TokenUsageScreen extends StatefulWidget {
  const TokenUsageScreen({super.key});

  @override
  State<TokenUsageScreen> createState() => _TokenUsageScreenState();
}

class _TokenUsageScreenState extends State<TokenUsageScreen> {
  final _storage = StorageService();
  UsageAggregate? _total;
  Map<String, UsageAggregate> _byModel = {};
  List<(DateTime, UsageAggregate)> _byDay = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final root = await _storage.root;
    final tracker = UsageTracker(root);
    final total = await tracker.aggregateAll();
    final byModel = await tracker.aggregateByModel();
    final byDay = await tracker.aggregateByDay(7);
    if (!mounted) return;
    setState(() {
      _total = total;
      _byModel = byModel;
      _byDay = byDay;
      _loading = false;
    });
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Token 用量'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // 总体统计卡片
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('总消耗',
                            style: TextStyle(fontSize: 13, color: cs.outline)),
                        const SizedBox(height: 8),
                        Text(
                          _fmt(_total?.totalTokens ?? 0),
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _metric('调用次数', _total?.callCount ?? 0, cs),
                            _metric('输入', _total?.inputTokens ?? 0, cs),
                            _metric('输出', _total?.outputTokens ?? 0, cs),
                            _metric('缓存读取', _total?.cacheReadTokens ?? 0, cs),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('近 7 天趋势',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _buildTrendChart(cs),
                const SizedBox(height: 16),
                Text('按模型',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (_byModel.isEmpty)
                  Text('暂无数据',
                      style: TextStyle(color: cs.outline, fontSize: 13))
                else
                  ..._byModel.entries.map((e) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: cs.primary.withOpacity(0.1),
                            child: Icon(Icons.memory, color: cs.primary, size: 20),
                          ),
                          title: Text(e.key,
                              style: const TextStyle(fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          subtitle: Text('${e.value.callCount} 次调用'),
                          trailing: Text(
                            _fmt(e.value.totalTokens),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            ),
                          ),
                        ),
                      )),
              ],
            ),
    );
  }

  Widget _metric(String label, int value, ColorScheme cs) {
    return Column(
      children: [
        Text(_fmt(value),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: cs.outline)),
      ],
    );
  }

  Widget _buildTrendChart(ColorScheme cs) {
    final maxVal = _byDay.fold<int>(0, (m, e) {
      final v = e.$2.totalTokens;
      return v > m ? v : m;
    });
    if (maxVal == 0) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('暂无消耗数据', style: TextStyle(color: cs.outline, fontSize: 13)),
      );
    }
    return Container(
      height: 140,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: _byDay.map((e) {
          final day = e.$1;
          final val = e.$2.totalTokens;
          final height = val == 0 ? 2.0 : (val / maxVal) * 100.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(_fmt(val),
                      style: TextStyle(fontSize: 9, color: cs.outline)),
                  const SizedBox(height: 2),
                  Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: val == 0 ? cs.outlineVariant : cs.primary,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${day.month}/${day.day}',
                      style: TextStyle(fontSize: 9, color: cs.outline)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
