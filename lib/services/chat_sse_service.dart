import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/ai/cancel_token.dart';

/// SSE 会话事件类型
enum SseChatEventType {
  chunk,
  toolCall,
  finish,
  error,
  cancel,
}

/// SSE 会话事件
class SseChatEvent {
  final SseChatEventType type;
  final String? content;
  final Map<String, dynamic>? toolPayload;
  final Object? error;

  SseChatEvent({required this.type, this.content, this.toolPayload, this.error});
}

/// 独立 SSE 流式服务，完全脱离 Widget 生命周期。
///
/// 核心设计：
/// - 闲置超时（多久未收到分片），而不是总请求超时
/// - 坏分片跳过不终止会话
/// - 完整事件抛出上层，UI 可见报错
/// - 和调度器共用同一个 CancelToken，仅用户手动停止/调度器降级才关闭连接
/// - 可选 chunkTransform 回调，用于火山方舟等非标准格式适配
class ChatSseService {
  HttpClient? _client;
  StreamController<SseChatEvent>? _eventController;
  bool _isClosed = false;

  /// 发起 SSE 流式对话
  ///
  /// [idleTimeout] 闲置超时：如 25 秒没收到新分片判定超时，不是总时长
  /// [cancelToken] 与调度器共用的取消令牌
  /// [chunkTransform] 可选的 chunk 转换回调，用于火山方舟等非标准格式适配
  Stream<SseChatEvent> startStream({
    required Uri url,
    required Map<String, String> headers,
    required Map<String, dynamic> body,
    required Duration idleTimeout,
    required CancelToken cancelToken,
    Map<String, dynamic>? Function(Map<String, dynamic> chunk)? chunkTransform,
  }) {
    _client = HttpClient();
    _eventController = StreamController<SseChatEvent>();
    _isClosed = false;

    final stream = _eventController!.stream;
    _runTask(url, headers, body, idleTimeout, cancelToken, chunkTransform: chunkTransform);
    return stream;
  }

  Future<void> _runTask(
    Uri url,
    Map<String, String> headers,
    Map<String, dynamic> body,
    Duration idleTimeout,
    CancelToken cancelToken, {
    Map<String, dynamic>? Function(Map<String, dynamic> chunk)? chunkTransform,
  }) async {
    try {
      final request = await _client!.postUrl(url);
      headers.forEach((k, v) => request.headers.set(k, v));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'text/event-stream');

      final bytes = utf8.encode(jsonEncode(body));
      request.contentLength = bytes.length;
      request.add(bytes);

      final response = await request.close();

      cancelToken.onCancel.listen((_) {
        _emit(SseChatEventType.cancel);
        _safeClose();
      });

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorText = await response.transform(utf8.decoder).join();
        _emit(SseChatEventType.error, error: 'HTTP ${response.statusCode}: $errorText');
        _safeClose();
        return;
      }

      String buffer = '';
      Timer? idleTimer;

      void resetIdleTimer() {
        idleTimer?.cancel();
        idleTimer = Timer(idleTimeout, () {
          _emit(SseChatEventType.error, error: '流闲置超时，长时间没有返回数据');
          _safeClose();
        });
      }
      resetIdleTimer();

      await for (final chunk in response.transform(utf8.decoder)) {
        if (_isClosed) break;
        resetIdleTimer();

        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast();

        for (final line in lines) {
          final trimLine = line.trim();
          if (trimLine.isEmpty) continue;

          if (trimLine == 'data: [DONE]') {
            _emit(SseChatEventType.finish);
            idleTimer?.cancel();
            _safeClose();
            return;
          }

          if (!trimLine.startsWith('data:')) continue;

          final rawData = trimLine.substring(5).trim();
          try {
            var jsonObj = jsonDecode(rawData);
            // 应用 chunk 转换器（火山方舟等非标准格式适配）
            if (chunkTransform != null && jsonObj is Map<String, dynamic>) {
              final transformed = chunkTransform(jsonObj);
              if (transformed != null) {
                jsonObj = transformed;
              }
            }
            if (jsonObj is Map && jsonObj['choices'] is List) {
              final choices = jsonObj['choices'] as List;
              if (choices.isNotEmpty) {
                final choice = choices.first;
                if (choice is Map) {
                  final delta = choice['delta'];
                  if (delta is Map) {
                    if (delta['content'] != null && delta['content'].toString().isNotEmpty) {
                      _emit(SseChatEventType.chunk, content: delta['content'].toString());
                    }
                    if (delta['tool_calls'] != null) {
                      _emit(SseChatEventType.toolCall, toolPayload: delta as Map<String, dynamic>?);
                    }
                  }
                  final finish = choice['finish_reason'];
                  if (finish != null && finish.toString().isNotEmpty) {
                    _emit(SseChatEventType.finish);
                    idleTimer?.cancel();
                    _safeClose();
                    return;
                  }
                }
              }
            }
          } catch (_) {
            continue;
          }
        }
      }

      idleTimer?.cancel();
      if (!_isClosed) {
        _emit(SseChatEventType.finish);
      }
    } catch (e) {
      if (!_isClosed) {
        _emit(SseChatEventType.error, error: e);
      }
    } finally {
      _safeClose();
    }
  }

  void _emit(SseChatEventType type, {String? content, Map<String, dynamic>? toolPayload, Object? error}) {
    if (_isClosed || _eventController == null) return;
    _eventController!.add(SseChatEvent(type: type, content: content, toolPayload: toolPayload, error: error));
  }

  void _safeClose() {
    if (_isClosed) return;
    _isClosed = true;
    _client?.close(force: true);
    _eventController?.close();
  }
}