/// 同步控制器 — 集中管理同步日志
///
/// 仅保留日志职责（addLog/logs）：同步状态与进度由各功能界面自持，
/// 原状态机/自动同步定时器/冲突/P2P 设备管理因全仓零外部调用已删除
/// （2026-09 全量复盘，见 docs/fixes/codebase-review-2026-09-13.md）。
library;

import 'package:flutter/material.dart';

/// 同步状态（日志条目标注用）
enum SyncStatus {
  idle,
  syncing,
  pushing,
  pulling,
  error,
  success,
}

/// 同步后端类型
enum SyncBackend {
  github,
  webdav,
  cms,
  p2p,
}

/// 同步日志条目
class SyncLogEntry {
  final DateTime timestamp;
  final String message;
  final SyncStatus status;
  final SyncBackend backend;

  const SyncLogEntry({
    required this.timestamp,
    required this.message,
    this.status = SyncStatus.idle,
    this.backend = SyncBackend.github,
  });
}

class SyncController extends ChangeNotifier {
  // ── 同步日志 ──
  final List<SyncLogEntry> _logs = [];
  static const int _maxLogs = 200;

  SyncBackend _activeBackend = SyncBackend.github;

  // ── Getters ──
  List<SyncLogEntry> get logs => List.unmodifiable(_logs);

  // ── 日志 ──
  void addLog(String message, {SyncStatus status = SyncStatus.idle, SyncBackend? backend}) {
    _logs.add(SyncLogEntry(
      timestamp: DateTime.now(),
      message: message,
      status: status,
      backend: backend ?? _activeBackend,
    ));
    if (_logs.length > _maxLogs) {
      _logs.removeRange(0, _logs.length - _maxLogs);
    }
    notifyListeners();
  }
}
