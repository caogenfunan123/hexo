import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart' as pp;
import '../../core/file_manager/file_abstract.dart';

/// 桌面平台（Windows/Mac/Linux）文件操作实现
/// 直接使用本地文件系统，无需沙盒
class DesktopFileOperator extends AppFileOperator {
  final String _rootPath;

  DesktopFileOperator({String? rootPath})
      : _rootPath = rootPath ?? _defaultRoot();

  static String _defaultRoot() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '/tmp';
    return '$home/Documents/拓墨';
  }

  Future<void> _ensureRoot() async {
    final dir = Directory(_rootPath);
    if (!await dir.exists()) await dir.create(recursive: true);
  }

  @override
  Future<String> readFile(String relativePath) async {
    final file = File('$_rootPath/$relativePath');
    if (!await file.exists()) throw Exception('文件不存在: $relativePath');
    return await file.readAsString();
  }

  @override
  Future<void> writeFile(String relativePath, String content) async {
    await _ensureRoot();
    final file = File('$_rootPath/$relativePath');
    final parent = file.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    await file.writeAsString(content);
  }

  @override
  Future<void> writeBinaryFile(String relativePath, List<int> bytes) async {
    await _ensureRoot();
    final file = File('$_rootPath/$relativePath');
    final parent = file.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<void> deleteFile(String relativePath) async {
    final file = File('$_rootPath/$relativePath');
    if (await file.exists()) await file.delete();
  }

  @override
  Future<bool> exists(String relativePath) async {
    return File('$_rootPath/$relativePath').exists();
  }

  @override
  Future<List<FileEntity>> listDirectory(String relativePath) async {
    final dir = Directory('$_rootPath/$relativePath');
    if (!await dir.exists()) return [];
    final result = <FileEntity>[];
    await for (final entity in dir.list()) {
      final stat = await entity.stat();
      result.add(FileEntity(
        name: entity.path.split(Platform.pathSeparator).last,
        path: entity.path.replaceFirst(_rootPath, '').replaceAll(RegExp(r'^[/\\]'), ''),
        isDirectory: entity is Directory,
        sizeBytes: stat.size,
        lastModified: stat.modified,
      ));
    }
    return result;
  }

  @override
  Future<void> createDirectory(String relativePath) async {
    await _ensureRoot();
    final dir = Directory('$_rootPath/$relativePath');
    if (!await dir.exists()) await dir.create(recursive: true);
  }

  @override
  Future<String> getAbsolutePath(String relativePath) async {
    return '$_rootPath/$relativePath';
  }

  @override
  Future<String> getRootPath() async {
    return _rootPath;
  }

  @override
  Future<String?> exportToUserDirectory(String relativePath, {String? exportName}) async {
    try {
      final source = File('$_rootPath/$relativePath');
      if (!await source.exists()) return null;

      final destName = exportName ?? relativePath.split('/').last;
      final downloadsDir = await pp.getDownloadsDirectory();
      if (downloadsDir == null) return null;
      final dest = File('${downloadsDir.path}/$destName');
      await source.copy(dest.path);
      return dest.path;
    } catch (e) {
      debugPrint('DesktopFileOperator: exportToUserDirectory error: $e');
      return null;
    }
  }
}