/// 增量同步服务
///
/// 参考 flutter_udp_broadcast (https://github.com/crazecoder/flutter_udp_broadcast)：
/// - 基于文件修改时间的增量同步
/// - SHA256 校验
/// - 仅同步变更的文件
/// - 冲突检测（基于 originDevice ID）
library;

import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:crypto/crypto.dart';

/// 增量同步文件条目
class SyncFileEntry {
  final String path;
  final String content;
  final DateTime modifiedAt;
  final String sha256;
  final int size;
  final String originDeviceId;

  const SyncFileEntry({
    required this.path,
    required this.content,
    required this.modifiedAt,
    required this.sha256,
    required this.size,
    required this.originDeviceId,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'content': content,
        'modifiedAt': modifiedAt.toIso8601String(),
        'sha256': sha256,
        'size': size,
        'originDeviceId': originDeviceId,
      };

  factory SyncFileEntry.fromJson(Map<String, dynamic> j) => SyncFileEntry(
        path: j['path']?.toString() ?? '',
        content: j['content']?.toString() ?? '',
        modifiedAt:
            DateTime.tryParse(j['modifiedAt']?.toString() ?? '') ??
                DateTime.now(),
        sha256: j['sha256']?.toString() ?? '',
        size: (j['size'] as num?)?.toInt() ?? 0,
        originDeviceId: j['originDeviceId']?.toString() ?? '',
      );
}

/// 同步冲突信息
class SyncConflict {
  final String filePath;
  final SyncFileEntry localEntry;
  final SyncFileEntry remoteEntry;
  final String localSha256;
  final String remoteSha256;

  const SyncConflict({
    required this.filePath,
    required this.localEntry,
    required this.remoteEntry,
    required this.localSha256,
    required this.remoteSha256,
  });

  bool get isRealConflict => localSha256 != remoteSha256;
}

/// 同步状态
enum SyncState {
  idle,
  scanning,
  comparing,
  syncing,
  completed,
  error,
}

/// 增量同步结果
class SyncResult {
  final int filesScanned;
  final int filesChanged;
  final int filesSynced;
  final int filesSkipped;
  final int conflicts;
  final Duration duration;
  final List<SyncConflict> conflictDetails;

  const SyncResult({
    required this.filesScanned,
    required this.filesChanged,
    required this.filesSynced,
    required this.filesSkipped,
    required this.conflicts,
    required this.duration,
    this.conflictDetails = const [],
  });
}

/// P2P 增量同步服务
///
/// 基于文件修改时间和 SHA256 校验实现增量同步，仅同步变更的文件。
/// 支持冲突检测和 originDevice ID 追踪。
class P2PIncrementalSyncService {
  final String originDeviceId;
  final Directory _baseDir;

  SyncState _state = SyncState.idle;
  String? _errorMessage;

  final StreamController<SyncState> _stateController =
      StreamController<SyncState>.broadcast();
  final StreamController<String> _progressController =
      StreamController<String>.broadcast();
  final StreamController<SyncConflict> _conflictController =
      StreamController<SyncConflict>.broadcast();

  /// 上次同步时间记录文件
  File get _lastSyncFile => File('${_baseDir.path}/.last_sync');

  P2PIncrementalSyncService({
    required this.originDeviceId,
    required Directory baseDir,
  }) : _baseDir = baseDir;

  // ── Getters ──

  SyncState get state => _state;
  String? get errorMessage => _errorMessage;
  Stream<SyncState> get onStateChange => _stateController.stream;
  Stream<String> get onProgress => _progressController.stream;
  Stream<SyncConflict> get onConflict => _conflictController.stream;

  // ============================================================
  // 变更检测
  // ============================================================

  /// 获取自指定时间以来变更的文件
  ///
  /// [since] 起始时间，null 表示获取所有文件
  /// [extensions] 文件扩展名过滤，默认 [.md, .json, .yaml, .yml]
  Future<List<String>> getChangedFiles(
    DateTime since, {
    List<String> extensions = const ['.md', '.json', '.yaml', '.yml'],
  }) async {
    final changedFiles = <String>[];
    final dirs = [
      '${_baseDir.path}/posts',
      '${_baseDir.path}/drafts',
      '${_baseDir.path}/templates',
    ];

    for (final dirPath in dirs) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;

      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) continue;
        if (!extensions.any((ext) => entity.path.endsWith(ext))) continue;

        final stat = await entity.stat();
        if (stat.modified.isAfter(since)) {
          changedFiles.add(entity.path);
        }
      }
    }

    return changedFiles;
  }

  /// 获取需要同步的文件条目列表
  ///
  /// [since] 起始时间
  /// [extensions] 文件扩展名过滤
  Future<List<SyncFileEntry>> getChangedFileEntries(
    DateTime since, {
    List<String> extensions = const ['.md', '.json', '.yaml', '.yml'],
  }) async {
    final files = await getChangedFiles(since, extensions: extensions);
    final entries = <SyncFileEntry>[];

    for (final filePath in files) {
      final file = File(filePath);
      final content = await file.readAsString();
      final stat = await file.stat();
      final sha256Hash = sha256.convert(utf8.encode(content)).toString();

      entries.add(SyncFileEntry(
        path: filePath.replaceFirst(_baseDir.path, ''),
        content: content,
        modifiedAt: stat.modified,
        sha256: sha256Hash,
        size: stat.size,
        originDeviceId: originDeviceId,
      ));
    }

    return entries;
  }

  // ============================================================
  // 增量同步
  // ============================================================

  /// 执行增量同步
  ///
  /// [remoteFiles] 远程设备的文件条目列表
  /// [conflictResolver] 冲突解决策略回调，返回 true 表示使用远程版本
  Future<SyncResult> syncFiles(
    List<SyncFileEntry> remoteFiles, {
    Future<bool> Function(SyncConflict conflict)? conflictResolver,
  }) async {
    final startTime = DateTime.now();
    _setState(SyncState.scanning);

    int filesScanned = 0;
    int filesChanged = 0;
    int filesSynced = 0;
    int filesSkipped = 0;
    int conflicts = 0;
    final conflictDetails = <SyncConflict>[];

    try {
      _setState(SyncState.comparing);
      _progress('开始增量同步，扫描 ${remoteFiles.length} 个远程文件...');

      for (final remoteEntry in remoteFiles) {
        filesScanned++;
        final localPath = '${_baseDir.path}${remoteEntry.path}';
        final localFile = File(localPath);

        if (!await localFile.exists()) {
          // 本地不存在，直接创建
          await _ensureParentDir(localPath);
          await localFile.writeAsString(remoteEntry.content);
          filesSynced++;
          _progress('新增: ${remoteEntry.path}');
          continue;
        }

        // 本地存在，比较 SHA256
        final localContent = await localFile.readAsString();
        final localSha256 =
            sha256.convert(utf8.encode(localContent)).toString();

        if (localSha256 == remoteEntry.sha256) {
          // 内容相同，跳过
          filesSkipped++;
          continue;
        }

        // 内容不同，检查是否有冲突
        final localStat = await localFile.stat();
        final localEntry = SyncFileEntry(
          path: remoteEntry.path,
          content: localContent,
          modifiedAt: localStat.modified,
          sha256: localSha256,
          size: localStat.size,
          originDeviceId: originDeviceId,
        );

        final conflict = SyncConflict(
          filePath: remoteEntry.path,
          localEntry: localEntry,
          remoteEntry: remoteEntry,
          localSha256: localSha256,
          remoteSha256: remoteEntry.sha256,
        );

        // 如果两端的 originDeviceId 相同，说明是同一设备的更新，直接覆盖
        if (remoteEntry.originDeviceId == originDeviceId) {
          await localFile.writeAsString(remoteEntry.content);
          filesSynced++;
          _progress('更新: ${remoteEntry.path} (同设备)');
          continue;
        }

        // 两端都修改了，需要解决冲突
        conflicts++;
        conflictDetails.add(conflict);
        _conflictController.add(conflict);
        _progress('冲突: ${remoteEntry.path}');

        if (conflictResolver != null) {
          final useRemote = await conflictResolver(conflict);
          if (useRemote) {
            await localFile.writeAsString(remoteEntry.content);
            filesSynced++;
            _progress('已解决: ${remoteEntry.path} (使用远程版本)');
          } else {
            filesSkipped++;
            _progress('已解决: ${remoteEntry.path} (保留本地版本)');
          }
        }
      }

      // 更新最后同步时间
      await _updateLastSyncTime();

      filesChanged = filesSynced + conflicts;
    } catch (e) {
      _setState(SyncState.error);
      _errorMessage = '同步失败: $e';
      _progress('同步失败: $e');
    }

    final duration = DateTime.now().difference(startTime);
    _setState(SyncState.completed);
    _progress(
        '同步完成: 扫描 $filesScanned, 变更 $filesChanged, 同步 $filesSynced, '
        '跳过 $filesSkipped, 冲突 $conflicts (${duration.inSeconds}s)');

    return SyncResult(
      filesScanned: filesScanned,
      filesChanged: filesChanged,
      filesSynced: filesSynced,
      filesSkipped: filesSkipped,
      conflicts: conflicts,
      duration: duration,
      conflictDetails: conflictDetails,
    );
  }

  /// 计算文件的 SHA256 哈希
  static String computeSha256(String content) {
    return sha256.convert(utf8.encode(content)).toString();
  }

  /// 获取上次同步时间
  Future<DateTime> getLastSyncTime() async {
    if (!await _lastSyncFile.exists()) {
      return DateTime(2000); // 返回一个很早的时间，表示首次同步
    }
    try {
      final content = await _lastSyncFile.readAsString();
      return DateTime.tryParse(content.trim()) ?? DateTime(2000);
    } catch (_) {
      return DateTime(2000);
    }
  }

  /// 更新最后同步时间
  Future<void> _updateLastSyncTime() async {
    await _lastSyncFile.writeAsString(DateTime.now().toIso8601String());
  }

  /// 确保父目录存在
  Future<void> _ensureParentDir(String filePath) async {
    final dir = Directory(filePath).parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  // ============================================================
  // 冲突解决策略
  // ============================================================

  /// 默认冲突解决：优先使用本地版本
  static Future<bool> preferLocal(SyncConflict conflict) async => false;

  /// 冲突解决：优先使用远程版本
  static Future<bool> preferRemote(SyncConflict conflict) async => true;

  /// 冲突解决：优先使用较新的版本
  static Future<bool> preferNewer(SyncConflict conflict) async {
    return conflict.remoteEntry.modifiedAt
        .isAfter(conflict.localEntry.modifiedAt);
  }

  // ============================================================
  // 内部方法
  // ============================================================

  void _setState(SyncState newState) {
    _state = newState;
    if (newState != SyncState.error) {
      _errorMessage = null;
    }
    _stateController.add(newState);
  }

  void _progress(String message) {
    _progressController.add(message);
  }

  void dispose() {
    _stateController.close();
    _progressController.close();
    _conflictController.close();
    _state = SyncState.idle;
  }
}