import 'package:flutter/foundation.dart';
import 'file_manager/file_abstract.dart';
import '../platform/android/file_operator_android.dart';
import '../platform/desktop/file_operator_desktop.dart';

/// 平台解析器：自动判断当前平台，加载对应实现
/// 使用方式：final fileOp = PlatformResolver.fileOperator;
class PlatformResolver {
  static AppFileOperator? _cached;

  /// 获取当前平台的文件操作实现
  static AppFileOperator get fileOperator {
    if (_cached != null) return _cached!;
    _cached = _create();
    return _cached!;
  }

  static AppFileOperator _create() {
    try {
      if (kIsWeb) {
        // Web 平台使用桌面实现（基于 IndexedDB 等）
        return DesktopFileOperator();
      }
      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        return AndroidFileOperator();
      }
      // Windows / macOS / Linux
      return DesktopFileOperator();
    } catch (_) {
      // 降级到桌面实现
      return DesktopFileOperator();
    }
  }

  /// 是否在移动平台上
  static bool get isMobile {
    try {
      if (kIsWeb) return false;
      return defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;
    } catch (_) {
      return false;
    }
  }

  /// 是否在桌面平台上
  static bool get isDesktop {
    try {
      if (kIsWeb) return false;
      return defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux;
    } catch (_) {
      return false;
    }
  }
}