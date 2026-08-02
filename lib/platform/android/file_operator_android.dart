import 'dart:io';
import 'package:flutter/services.dart';
import '../../core/file_manager/file_abstract.dart';

/// 安卓平台文件操作实现
/// 使用 MethodChannel 调用原生 SAF / 沙盒
class AndroidFileOperator implements AppFileOperator {
  static const _channel = MethodChannel('hexo/native');

  Directory? _root;

  Future<Directory> _getRoot() async {
    if (_root != null) return _root!;
    try {
      final path = await _channel.invokeMethod<String>('getFilesDir');
      if (path != null && path.isNotEmpty) {
        _root = Directory(path);
        if (!await _root!.exists()) await _root!.create(recursive: true);
        return _root!;
      }
    } catch (_) {}
    _root = Directory('${Directory.systemTemp.path}/hexo_blog_manager');
    if (!await _root!.exists()) await _root!.create(recursive: true);
    return _root!;
  }

  @override
  Future<String> readFile(String relativePath) async {
    final root = await _getRoot();
    final file = File('${root.path}/$relativePath');
    if (!await file.exists()) throw Exception('文件不存在: $relativePath');
    return await file.readAsString();
  }

  @override
  Future<void> writeFile(String relativePath, String content) async {
    final root = await _getRoot();
    final file = File('${root.path}/$relativePath');
    final parent = file.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    await file.writeAsString(content);
  }

  @override
  Future<void> writeBinaryFile(String relativePath, List<int> bytes) async {
    final root = await _getRoot();
    final file = File('${root.path}/$relativePath');
    final parent = file.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<void> deleteFile(String relativePath) async {
    final root = await _getRoot();
    final file = File('${root.path}/$relativePath');
    if (await file.exists()) await file.delete();
  }

  @override
  Future<bool> exists(String relativePath) async {
    final root = await _getRoot();
    return File('${root.path}/$relativePath').exists();
  }

  @override
  Future<List<FileEntity>> listDirectory(String relativePath) async {
    final root = await _getRoot();
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
    final root = await _getRoot();
    final dir = Directory('${root.path}/$relativePath');
    if (!await dir.exists()) await dir.create(recursive: true);
  }

  @override
  Future<String> getAbsolutePath(String relativePath) async {
    final root = await _getRoot();
    return '${root.path}/$relativePath';
  }

  @override
  Future<String> getRootPath() async {
    final root = await _getRoot();
    return root.path;
  }
}