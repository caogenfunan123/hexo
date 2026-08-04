import 'dart:convert';
import 'dart:io';

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

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'action': action,
    'detail': detail,
    'success': success,
  };

  factory LogEntry.fromJson(Map<String, dynamic> j) => LogEntry(
    timestamp: DateTime.tryParse(j['timestamp']?.toString() ?? '') ?? DateTime.now(),
    action: j['action']?.toString() ?? '',
    detail: j['detail']?.toString() ?? '',
    success: j['success'] == true,
  );
}

/// 操作日志服务
///
/// 全局单例，记录编辑器中的关键操作（发布、保存、删除等），
/// 最多保留 200 条内存日志，同时持久化最近 500 条到文件。
class LogService extends ChangeNotifier {
  static final LogService _instance = LogService._();
  factory LogService() => _instance;
  LogService._();

  final List<LogEntry> _logs = [];
  static const int _maxLogs = 200;
  static const int _maxFileLogs = 500;

  Directory? _logDir;

  /// 初始化日志目录（可选，调用后启用文件持久化）
  Future<void> init(Directory appDir) async {
    _logDir = Directory('${appDir.path}/logs');
    if (!await _logDir!.exists()) {
      await _logDir!.create(recursive: true);
    }
    // 加载历史日志
    await _loadFromFile();
  }

  List<LogEntry> get logs => List.unmodifiable(_logs);

  void add(String action, String detail, {bool success = true}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      action: action,
      detail: detail,
      success: success,
    );
    _logs.insert(0, entry);
    if (_logs.length > _maxLogs) {
      _logs.removeRange(_maxLogs, _logs.length);
    }
    notifyListeners();
    _persistToFile();
  }

  void clear() {
    _logs.clear();
    notifyListeners();
    _deleteLogFile();
  }

  // ── 文件持久化 ──

  File get _logFile {
    final now = DateTime.now();
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return File('${_logDir!.path}/app_$dateStr.log');
  }

  Future<void> _persistToFile() async {
    if (_logDir == null) return;
    try {
      final allLogs = [..._logs];
      // 合并已有文件日志
      final existing = await _loadFileLogs();
      final merged = <LogEntry>[...allLogs];
      for (final e in existing) {
        if (!merged.any((m) => m.timestamp == e.timestamp && m.action == e.action)) {
          merged.add(e);
        }
      }
      // 只保留最近 _maxFileLogs 条
      merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (merged.length > _maxFileLogs) {
        merged.removeRange(_maxFileLogs, merged.length);
      }
      final jsonList = merged.map((e) => e.toJson()).toList();
      await _logFile.writeAsString(const JsonEncoder.withIndent(null).convert(jsonList));
    } catch (_) {
      // 静默失败，不影响主流程
    }
  }

  Future<List<LogEntry>> _loadFileLogs() async {
    if (_logDir == null) return [];
    try {
      final file = _logFile;
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.isEmpty) return [];
      final list = jsonDecode(content) as List;
      return list.map((j) => LogEntry.fromJson(j as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _loadFromFile() async {
    try {
      final fileLogs = await _loadFileLogs();
      for (final entry in fileLogs.take(_maxLogs)) {
        _logs.add(entry);
      }
    } catch (_) {}
  }

  Future<void> _deleteLogFile() async {
    if (_logDir == null) return;
    try {
      if (await _logFile.exists()) {
        await _logFile.delete();
      }
    } catch (_) {}
  }
}