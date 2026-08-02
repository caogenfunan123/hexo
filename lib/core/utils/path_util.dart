import 'package:flutter/foundation.dart';

/// 跨平台路径处理工具
/// 【规则】所有路径拼接、路径判断统一在此处理，禁止到处手写分隔符
class PathUtil {
  /// 路径分隔符（Windows \ / Unix /）
  static String get separator {
    if (kIsWeb) return '/';
    // defaultTargetPlatform 在非 Flutter 环境可能不可用，此处兜底 /
    try {
      if (defaultTargetPlatform == TargetPlatform.windows) return '\\';
    } catch (_) {}
    return '/';
  }

  /// 拼接路径（自动处理分隔符）
  static String join(String part1, String part2,
      [String? part3, String? part4, String? part5]) {
    var result = _normalize(part1);
    for (final p in [part2, part3, part4, part5]) {
      if (p == null || p.isEmpty) continue;
      result = '$result${result.endsWith(separator) ? '' : separator}${_normalize(p)}';
    }
    return result;
  }

  /// 获取目录名
  static String dirname(String path) {
    final normalized = _normalize(path);
    final idx = normalized.lastIndexOf(separator);
    if (idx <= 0) return '';
    return normalized.substring(0, idx);
  }

  /// 获取文件名
  static String basename(String path) {
    final normalized = _normalize(path);
    final idx = normalized.lastIndexOf(separator);
    if (idx < 0) return normalized;
    return normalized.substring(idx + 1);
  }

  /// 获取扩展名（不含点）
  static String extension(String path) {
    final name = basename(path);
    final idx = name.lastIndexOf('.');
    if (idx < 0) return '';
    return name.substring(idx + 1);
  }

  /// 移除扩展名
  static String withoutExtension(String path) {
    final idx = path.lastIndexOf('.');
    if (idx < 0) return path;
    return path.substring(0, idx);
  }

  /// 规范化路径（统一分隔符，去除多余分隔符）
  static String _normalize(String path) {
    var p = path
        .replaceAll('\\', separator)
        .replaceAll('/', separator);
    // 去掉末尾分隔符
    while (p.endsWith(separator) && p.length > 1) {
      p = p.substring(0, p.length - 1);
    }
    // 去掉开头多余分隔符
    while (p.startsWith(separator) && p.length > 1) {
      p = p.substring(1);
    }
    return p;
  }

  /// 确保路径以分隔符结尾
  static String ensureTrailingSeparator(String path) {
    final normalized = _normalize(path);
    if (normalized.isEmpty) return separator;
    return normalized.endsWith(separator) ? normalized : '$normalized$separator';
  }

  /// 相对路径转安全文件名（去除非法字符）
  static String sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
  }

  /// 判断是否为绝对路径
  static bool isAbsolute(String path) {
    if (path.isEmpty) return false;
    // Unix 绝对路径
    if (path.startsWith('/')) return true;
    // Windows 绝对路径 (C:\ 或 \\)
    if (path.length >= 2 && path[1] == ':') return true;
    if (path.startsWith('\\\\')) return true;
    return false;
  }
}