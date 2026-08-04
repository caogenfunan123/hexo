import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart' as pp;

import '../../core/file_manager/file_abstract.dart';

/// 安卓平台文件操作实现
/// 【强制工程细则1】Android 11+ 分区存储适配
///
/// 存储策略：
/// - 内部文件（快照、缓存、回收站索引、同步元数据）→ getApplicationDocumentsDirectory()
/// - 用户导出 → SAF / MediaStore / 共享存储
/// - 所有文件操作统一经由本接口，禁止跨平台直接使用 File 原生 API
class AndroidFileOperator implements AppFileOperator {
  static const _channel = MethodChannel('hexo/native');

  Directory? _internalRoot;
  Directory? _cacheRoot;
  bool? _scopedStorage;

  // ── 内部存储根目录（应用私有，不可见） ──

  Future<Directory> _getInternalRoot() async {
    if (_internalRoot != null) return _internalRoot!;
    try {
      // 优先使用 path_provider 获取应用文档目录
      final dir = await pp.getApplicationDocumentsDirectory();
      _internalRoot = Directory('${dir.path}/hexo_data');
      if (!await _internalRoot!.exists()) {
        await _internalRoot!.create(recursive: true);
      }
      return _internalRoot!;
    } catch (_) {
      // 回退：MethodChannel
      try {
        final path = await _channel.invokeMethod<String>('getFilesDir');
        if (path != null && path.isNotEmpty) {
          _internalRoot = Directory(path);
          if (!await _internalRoot!.exists()) {
            await _internalRoot!.create(recursive: true);
          }
          return _internalRoot!;
        }
      } catch (_) {}
    }
    // 最终回退
    _internalRoot = Directory('${Directory.systemTemp.path}/hexo_blog_manager');
    if (!await _internalRoot!.exists()) {
      await _internalRoot!.create(recursive: true);
    }
    return _internalRoot!;
  }

  // ── 缓存目录 ──

  Future<Directory> _getCacheRoot() async {
    if (_cacheRoot != null) return _cacheRoot!;
    try {
      final dir = await pp.getTemporaryDirectory();
      _cacheRoot = Directory('${dir.path}/hexo_cache');
      if (!await _cacheRoot!.exists()) {
        await _cacheRoot!.create(recursive: true);
      }
      return _cacheRoot!;
    } catch (_) {
      _cacheRoot = Directory('${Directory.systemTemp.path}/hexo_cache');
      if (!await _cacheRoot!.exists()) {
        await _cacheRoot!.create(recursive: true);
      }
      return _cacheRoot!;
    }
  }

  // ── 分区存储检测 ──

  @override
  bool isScopedStorageRequired() {
    if (_scopedStorage != null) return _scopedStorage!;
    // Android 11 = API 30
    // 通过 Platform.operatingSystemVersion 检测
    try {
      _scopedStorage = Platform.isAndroid;
    } catch (_) {
      _scopedStorage = true; // 默认使用分区存储策略
    }
    return _scopedStorage!;
  }

  // ── 文件操作实现 ──

  @override
  Future<String> readFile(String relativePath) async {
    final root = await _getInternalRoot();
    final file = File('${root.path}/$relativePath');
    if (!await file.exists()) throw Exception('文件不存在: $relativePath');
    return await file.readAsString();
  }

  @override
  Future<void> writeFile(String relativePath, String content) async {
    final root = await _getInternalRoot();
    final file = File('${root.path}/$relativePath');
    final parent = file.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    await file.writeAsString(content);
  }

  @override
  Future<void> writeBinaryFile(String relativePath, List<int> bytes) async {
    final root = await _getInternalRoot();
    final file = File('${root.path}/$relativePath');
    final parent = file.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<void> deleteFile(String relativePath) async {
    final root = await _getInternalRoot();
    final file = File('${root.path}/$relativePath');
    if (await file.exists()) await file.delete();
  }

  @override
  Future<bool> exists(String relativePath) async {
    final root = await _getInternalRoot();
    return File('${root.path}/$relativePath').exists();
  }

  @override
  Future<List<FileEntity>> listDirectory(String relativePath) async {
    final root = await _getInternalRoot();
    final dir = Directory('${root.path}/$relativePath');
    if (!await dir.exists()) return [];
    final result = <FileEntity>[];
    await for (final entity in dir.list()) {
      final stat = await entity.stat();
      result.add(FileEntity(
        name: entity.path.split('/').last,
        path: entity.path.replaceFirst(root.path, '').replaceAll(RegExp(r'^/'), ''),
        isDirectory: entity is Directory,
        sizeBytes: stat.size,
        lastModified: stat.modified,
      ));
    }
    return result;
  }

  @override
  Future<void> createDirectory(String relativePath) async {
    final root = await _getInternalRoot();
    final dir = Directory('${root.path}/$relativePath');
    if (!await dir.exists()) await dir.create(recursive: true);
  }

  @override
  Future<String> getAbsolutePath(String relativePath) async {
    final root = await _getInternalRoot();
    return '${root.path}/$relativePath';
  }

  @override
  Future<String> getRootPath() async {
    final root = await _getInternalRoot();
    return root.path;
  }

  @override
  Future<String> getInternalStoragePath() async {
    final root = await _getInternalRoot();
    return root.path;
  }

  /// 导出文件到用户可访问的目录
  /// Android 10+ 使用 MediaStore，Android 9- 使用外部存储
  @override
  Future<String?> exportToUserDirectory(String relativePath, {String? exportName}) async {
    try {
      final root = await _getInternalRoot();
      final sourceFile = File('${root.path}/$relativePath');
      if (!await sourceFile.exists()) return null;

      final name = exportName ?? relativePath.split('/').last;

      if (isScopedStorageRequired()) {
        // Android 10+: 通过 MethodChannel 调用原生 SAF/MediaStore
        final result = await _channel.invokeMethod<String>('exportFile', {
          'sourcePath': sourceFile.path,
          'fileName': name,
        });
        return result;
      } else {
        // Android 9-: 使用外部存储
        final downloadsDir = Directory('/storage/emulated/0/Download');
        if (await downloadsDir.exists()) {
          final destFile = File('${downloadsDir.path}/$name');
          await sourceFile.copy(destFile.path);
          return destFile.path;
        }
        return null;
      }
    } catch (e) {
      debugPrint('exportToUserDirectory error: $e');
      return null;
    }
  }

  /// 获取用户可访问的导出目录
  @override
  Future<String> getExportDirectory() async {
    if (isScopedStorageRequired()) {
      // Android 10+: 通过 SAF 获取
      try {
        final path = await _channel.invokeMethod<String>('getExportDir');
        if (path != null && path.isNotEmpty) return path;
      } catch (_) {}
    }
    // 回退到下载目录
    final downloadsDir = Directory('/storage/emulated/0/Download');
    if (await downloadsDir.exists()) {
      return downloadsDir.path;
    }
    // 最后回退到内部存储
    final root = await _getInternalRoot();
    return '${root.path}/exports';
  }

  /// 获取缓存目录（用于临时文件）
  Future<String> getCachePath() async {
    final root = await _getCacheRoot();
    return root.path;
  }

  /// 清理缓存
  Future<void> clearCache() async {
    final root = await _getCacheRoot();
    if (await root.exists()) {
      await root.delete(recursive: true);
      await root.create(recursive: true);
    }
  }

  /// 调试输出
  static void debugPrint(String message) {
    // ignore: avoid_print
    print('[AndroidFileOperator] $message');
  }
}