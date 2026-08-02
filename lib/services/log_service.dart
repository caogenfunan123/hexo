import 'package:flutter/foundation.dart';

/// 操作日志条目
class LogEntry {
  final DateTime timestamp;
  final String action;
  final String detail;
  final bool success;

  const LogEntry({
    required this.timestamp,
    required this.action,
    required this.detail,
    required this.success,
  });
}

/// 操作日志服务
///
/// 全局单例，记录编辑器中的关键操作（发布、保存、删除等），
/// 最多保留 200 条日志。
class LogService extends ChangeNotifier {
  static final LogService _instance = LogService._();
  factory LogService() => _instance;
  LogService._();

  final List<LogEntry> _logs = [];
  static const int _maxLogs = 200;

  List<LogEntry> get logs => List.unmodifiable(_logs);

  void add(String action, String detail, {bool success = true}) {
    _logs.insert(0, LogEntry(
      timestamp: DateTime.now(),
      action: action,
      detail: detail,
      success: success,
    ));
    if (_logs.length > _maxLogs) {
      _logs.removeRange(_maxLogs, _logs.length);
    }
    notifyListeners();
  }

  void clear() {
    _logs.clear();
    notifyListeners();
  }
}