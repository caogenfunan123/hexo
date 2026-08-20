import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// 获取当前设备的主 ABI 标识（如 `arm64-v8a`、`armeabi-v7a`）
///
/// 非 Android 平台返回空字符串。
Future<String> getDeviceAbi() async {
  if (!Platform.isAndroid) return '';
  try {
    final channel = MethodChannel('hexo/native');
    final abi = await channel.invokeMethod<String>('getAbi');
    return abi ?? '';
  } catch (_) {
    return '';
  }
}