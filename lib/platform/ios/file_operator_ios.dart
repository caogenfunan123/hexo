import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart' as pp;

import '../../core/file_manager/file_abstract.dart';

/// iOS 平台文件操作实现
///
/// iOS 沙盒策略：
/// - 内部文件 → getApplicationDocumentsDirectory()（应用私有文档目录）
/// - 用户导出 → 写入应用文档目录，由调用方通过 share 或 Files 应用访问
/// - iOS 无分区存储概念，不需要 SAF/MediaStore
class IosFileOperator extends AppFileOperator {
  static const _channel = MethodChannel('hexo/native');

  Directory? _internalRoot;
  Directory? _exportRoot;

  Future<Directory> _getInternalRoot() async {
    if (_internalRoot != null) return _internalRoot!;
    try {
      final dir = await pp.getApplicationDocumentsDirectory();
      _internalRoot = Directory('${dir.path}/hexo_data');
      if (!await _internalRoot!.exists()) {
        await _internalRoot!.create(recursive: true);
      }
      return _internalRoot!;
    } catch (_) {
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
    _internalRoot = Directory('${Directory.systemTemp.path}/hexo_blog_manager');
    if (!await _internalRoot!.exists()) {
      await _internalRoot!.create(recursive: true);
    }
    return _internalRoot!;
  }

  Future<Directory> _getExportRoot() async {
    if (_exportRoot != null) return _exportRoot!;
    try {
      final docs = await pp.getApplicationDocumentsDirectory();
      _exportRoot = Directory('${docs.path}/导出');
      if (!await _exportRoot!.exists()) {
        await _exportRoot!.create(recursive: true);
      }
      return _exportRoot!;
    } catch (_) {
      return _getInternalRoot();
    }
  }

  Future<File> _resolveFile(String relativePath) async {
    final root = await getRootPath();
    return File('$root/$relativePath');
  }

  @override
  Future<String> readFile(String relativePath) async {
    final file = await _resolveFile(relativePath);
    if (!await file.exists()) {
      throw FileSystemException('文件不存在', relativePath);
    }
    return await file.readAsString();
  }

  @override
  Future<void> writeFile(String relativePath, String content) async {
    final file = await _resolveFile(relativePath);
    final parent = file.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    await file.writeAsString(content);
  }

  @override
  Future<void> writeBinaryFile(String relativePath, List<int> bytes) async {
    final file = await _resolveFile(relativePath);
    final parent = file.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<void> deleteFile(String relativePath) async {
    final file = await _resolveFile(relativePath);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<bool> exists(String relativePath) async {
    return (await _resolveFile(relativePath)).exists();
  }

  @override
  Future<List<FileEntity>> listDirectory(String relativePath) async {
    final dir = Directory('${(await getRootPath())}/$relativePath');
    if (!await dir.exists()) return [];
    final result = <FileEntity>[];
    await for (final entity in dir.list()) {
      final stat = await entity.stat();
      result.add(FileEntity(
        name: entity.path.split('/').last,
        path: entity.path.replaceFirst(await getRootPath(), '')
            .replaceAll(RegExp(r'^[/\\]'), ''),
        isDirectory: entity is Directory,
        sizeBytes: stat.size,
        lastModified: stat.modified,
      ));
    }
    return result;
  }

  @override
  Future<void> createDirectory(String relativePath) async {
    final dir = Directory('${(await getRootPath())}/$relativePath');
    if (!await dir.exists()) await dir.create(recursive: true);
  }

  @override
  Future<String> getAbsolutePath(String relativePath) async {
    return '${await getRootPath()}/$relativePath';
  }

  @override
  Future<String> getRootPath() async {
    return (await _getInternalRoot()).path;
  }

  @override
  bool isScopedStorageRequired() => false;

  @override
  Future<String?> exportToUserDirectory(String relativePath,
      {String? exportName}) async {
    // iOS 无分区存储，直接复制到应用"导出"目录
    final source = File('${await getRootPath()}/$relativePath');
    if (!await source.exists()) return null;
    final exportDir = await _getExportRoot();
    final destName = exportName ?? relativePath.split('/').last;
    final dest = File('${exportDir.path}/$destName');
    await source.copy(dest.path);
    return dest.path;
  }

  @override
  Future<String> getInternalStoragePath() async {
    return await getRootPath();
  }

  @override
  Future<String> getExportDirectory() async {
    return (await _getExportRoot()).path;
  }

  @override
  Future<int> getSdkVersion() async => 0;
}