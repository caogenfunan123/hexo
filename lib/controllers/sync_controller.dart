/// 同步控制器 — 统一管理桌面端和手机端的同步状态
///
/// 职责：GitHub 同步、WebDAV 同步、CMS 双向同步、局域网 P2P 同步、自动同步定时器、
///       同步日志、冲突检测
library;

import 'dart:async';
import 'package:flutter/material.dart';

/// 同步状态
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

/// 同步冲突条目
class SyncConflict {
  final String filePath;
  final String localContent;
  final String remoteContent;
  final DateTime localModified;
  final DateTime remoteModified;

  const SyncConflict({
    required this.filePath,
    required this.localContent,
    required this.remoteContent,
    required this.localModified,
    required this.remoteModified,
  });
}

class SyncController extends ChangeNotifier {
  // ── 同步状态 ──
  SyncStatus _status = SyncStatus.idle;
  SyncBackend _activeBackend = SyncBackend.github;
  bool _isSyncing = false;
  String? _errorMessage;

  // ── 同步日志 ──
  final List<SyncLogEntry> _logs = [];
  static const int _maxLogs = 200;

  // ── 冲突 ──
  final List<SyncConflict> _conflicts = [];

  // ── 自动同步 ──
  Timer? _autoSyncTimer;
  bool _autoSyncEnabled = false;
  int _autoSyncIntervalSeconds = 300;

  // ── P2P 同步 ──
  final List<String> _discoveredDevices = [];
  String? _connectedDevice;
  DateTime? _lastSyncTimestamp;

  // ── 同步回调（由外部注入） ──
  Future<void> Function()? onPushAll;
  Future<void> Function()? onPullAll;
  Future<void> Function()? onAutoSyncToCloud;
  Future<void> Function()? onAutoPullFromCloud;

  // ── Getters ──
  SyncStatus get status => _status;
  SyncBackend get activeBackend => _activeBackend;
  bool get isSyncing => _isSyncing;
  String? get errorMessage => _errorMessage;
  List<SyncLogEntry> get logs => List.unmodifiable(_logs);
  List<SyncConflict> get conflicts => List.unmodifiable(_conflicts);
  bool get autoSyncEnabled => _autoSyncEnabled;
  int get autoSyncIntervalSeconds => _autoSyncIntervalSeconds;
  List<String> get discoveredDevices => List.unmodifiable(_discoveredDevices);
  String? get connectedDevice => _connectedDevice;
  DateTime? get lastSyncTimestamp => _lastSyncTimestamp;

  // ── 状态管理 ──
  void setStatus(SyncStatus status) {
    _status = status;
    _isSyncing = status == SyncStatus.syncing ||
        status == SyncStatus.pushing ||
        status == SyncStatus.pulling;
    notifyListeners();
  }

  void setError(String? error) {
    _errorMessage = error;
    if (error != null) {
      _status = SyncStatus.error;
    }
    notifyListeners();
  }

  void setActiveBackend(SyncBackend backend) {
    _activeBackend = backend;
    notifyListeners();
  }

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

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  // ── 冲突 ──
  void addConflict(SyncConflict conflict) {
    _conflicts.add(conflict);
    notifyListeners();
  }

  void resolveConflict(String filePath, String resolution) {
    _conflicts.removeWhere((c) => c.filePath == filePath);
    addLog('已解决冲突: $filePath → $resolution');
    notifyListeners();
  }

  void clearConflicts() {
    _conflicts.clear();
    notifyListeners();
  }

  // ── 自动同步 ──
  void startAutoSync() {
    _autoSyncEnabled = true;
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(
      Duration(seconds: _autoSyncIntervalSeconds),
      (_) => _runAutoSync(),
    );
    notifyListeners();
  }

  void stopAutoSync() {
    _autoSyncEnabled = false;
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    notifyListeners();
  }

  void setAutoSyncInterval(int seconds) {
    _autoSyncIntervalSeconds = seconds;
    if (_autoSyncEnabled) {
      stopAutoSync();
      startAutoSync();
    }
  }

  Future<void> _runAutoSync() async {
    if (!_autoSyncEnabled) return;
    try {
      await onAutoSyncToCloud?.call();
    } catch (_) {
      // 自动同步失败不提示用户
    }
  }

  // ── P2P 同步 ──
  void addDiscoveredDevice(String device) {
    if (!_discoveredDevices.contains(device)) {
      _discoveredDevices.add(device);
      notifyListeners();
    }
  }

  void removeDiscoveredDevice(String device) {
    _discoveredDevices.remove(device);
    notifyListeners();
  }

  void connectToDevice(String device) {
    _connectedDevice = device;
    addLog('已连接到设备: $device', backend: SyncBackend.p2p);
    notifyListeners();
  }

  void disconnectDevice() {
    if (_connectedDevice != null) {
      addLog('已断开设备: $_connectedDevice', backend: SyncBackend.p2p);
    }
    _connectedDevice = null;
    notifyListeners();
  }

  void updateSyncTimestamp() {
    _lastSyncTimestamp = DateTime.now();
    notifyListeners();
  }

  // ── 清理 ──
  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }
}