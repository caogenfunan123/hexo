/// 速记入口服务：封装 Android 原生通道（桌面小部件 / 通知栏磁贴）
///
/// 原生侧约定（MainActivity.java / QuickNoteIntent）：
/// - 通道 `hexo/quick_note`：原生 → Flutter 热启动推送（invokeMethod "onQuickNote"）
/// - 通道 `hexo/native` 方法 `getLaunchQuickNote`：Flutter 冷启动拉取
/// - 参数 Map：{ mode: "new", text?: "预填文本" }
library;

import 'dart:async';
import 'package:flutter/services.dart';

/// 一次速记请求（来自小部件 / 磁贴）
class QuickNoteRequest {
  final String mode;
  final String text;

  const QuickNoteRequest({required this.mode, this.text = ''});

  bool get isNew => mode == 'new';

  Map<String, dynamic> toMap() => {
        'mode': mode,
        if (text.isNotEmpty) 'text': text,
      };
}

/// 速记入口通道
class QuickNoteService {
  static const MethodChannel _channel = MethodChannel('hexo/native');
  static const MethodChannel _pushChannel = MethodChannel('hexo/quick_note');

  final StreamController<QuickNoteRequest> _controller =
      StreamController<QuickNoteRequest>.broadcast();

  Stream<QuickNoteRequest> get requests => _controller.stream;

  bool _listening = false;

  /// 拉取冷启动时携带的速记参数（应用刚启动时调用一次）
  Future<QuickNoteRequest?> fetchLaunchRequest() async {
    try {
      final data = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getLaunchQuickNote',
      );
      return _toRequest(data);
    } catch (_) {
      return null;
    }
  }

  /// 监听原生侧热启动推送（onNewIntent 时）
  void startListening() {
    if (_listening) return;
    _listening = true;
    _pushChannel.setMethodCallHandler((call) async {
      if (call.method == 'onQuickNote') {
        final req = _toRequest((call.arguments as Map?)?.cast<String, dynamic>());
        if (req != null) _controller.add(req);
      }
    });
  }

  QuickNoteRequest? _toRequest(Map<dynamic, dynamic>? data) {
    if (data == null) return null;
    final mode = data['mode']?.toString();
    if (mode == null) return null;
    return QuickNoteRequest(
      mode: mode,
      text: data['text']?.toString() ?? '',
    );
  }

  void dispose() {
    _controller.close();
  }
}
