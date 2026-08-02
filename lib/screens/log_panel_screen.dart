import 'package:flutter/material.dart';
import '../services/log_service.dart';

/// 操作日志面板
///
/// 展示编辑器中的关键操作记录，包括发布、保存、删除等。
class LogPanelScreen extends StatefulWidget {
  final LogService logService;

  const LogPanelScreen({super.key, required this.logService});

  @override
  State<LogPanelScreen> createState() => _LogPanelScreenState();
}

class _LogPanelScreenState extends State<LogPanelScreen> {
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
    final logs = widget.logService.logs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('操作日志'),
        actions: [
          if (logs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空日志',
              onPressed: () {
                widget.logService.clear();
              },
            ),
        ],
      ),
      body: logs.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.history, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text('暂无操作日志', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
              ]),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: logs.length,
              itemBuilder: (_, i) {
                final entry = logs[i];
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
                          entry.success ? Icons.check_circle_outline : Icons.error_outline,
                          size: 20,
                          color: entry.success ? const Color(0xFF059669) : Colors.red,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    entry.action,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _fmt(entry.timestamp),
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                  ),
                                ],
                              ),
                              if (entry.detail.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  entry.detail,
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
    );
  }
}