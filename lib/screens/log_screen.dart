import 'package:flutter/material.dart';
import '../services/log_service.dart';

/// 操作日志面板
///
/// 展示最近的操作记录，包括发布、保存、删除等关键操作，
/// 支持按成功/失败筛选和清空日志。
class LogScreen extends StatefulWidget {
  final LogService logService;

  const LogScreen({super.key, required this.logService});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  bool? _filterSuccess; // null = 全部, true = 成功, false = 失败

  List<LogEntry> get _filteredLogs {
    final logs = widget.logService.logs;
    if (_filterSuccess == null) return logs;
    return logs.where((l) => l.success == _filterSuccess).toList();
  }

  @override
  void initState() {
    super.initState();
    widget.logService.addListener(_onLogsChanged);
  }

  @override
  void dispose() {
    widget.logService.removeListener(_onLogsChanged);
    super.dispose();
  }

  void _onLogsChanged() {
    if (mounted) setState(() {});
  }

  String _fmt(DateTime dt) {
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final logs = _filteredLogs;

    return Column(
      children: [
        // ── 筛选栏 ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.white,
          child: Row(
            children: [
              const Icon(Icons.history, size: 18, color: Color(0xFF64748B)),
              const SizedBox(width: 8),
              const Text('操作日志', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              // 筛选按钮
              ChoiceChip(
                label: const Text('全部', style: TextStyle(fontSize: 12)),
                selected: _filterSuccess == null,
                onSelected: (_) => setState(() => _filterSuccess = null),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              ChoiceChip(
                label: const Text('成功', style: TextStyle(fontSize: 12)),
                selected: _filterSuccess == true,
                onSelected: (_) => setState(() => _filterSuccess = true),
                selectedColor: Colors.green.withOpacity(0.2),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              ChoiceChip(
                label: const Text('失败', style: TextStyle(fontSize: 12)),
                selected: _filterSuccess == false,
                onSelected: (_) => setState(() => _filterSuccess = false),
                selectedColor: Colors.red.withOpacity(0.2),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_sweep, size: 18),
                tooltip: '清空日志',
                onPressed: logs.isEmpty
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('清空日志'),
                            content: const Text('确认清空所有操作日志？'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                              FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('清空')),
                            ],
                          ),
                        );
                        if (ok == true) widget.logService.clear();
                      },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // ── 日志列表 ──
        Expanded(
          child: logs.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('暂无操作日志', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                  ]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: logs.length,
                  itemBuilder: (_, i) {
                    final log = logs[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      color: Colors.white,
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              log.success ? Icons.check_circle_outline : Icons.error_outline,
                              size: 18,
                              color: log.success ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        log.action,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: log.success ? const Color(0xFF0F172A) : Colors.red,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        _fmt(log.timestamp),
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                      ),
                                    ],
                                  ),
                                  if (log.detail.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      log.detail,
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}