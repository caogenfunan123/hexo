/// 可取消操作令牌
///
/// 用于发布、上传等耗时操作的中断控制。
/// 由于 Dart 原生 HttpClient 不支持中途取消已发送的请求，
/// 此令牌在关键检查点生效：重试间隔、循环等待等。
class CancelToken {
  bool _cancelled = false;

  /// 是否已被取消
  bool get isCancelled => _cancelled;

  /// 取消操作
  void cancel() {
    _cancelled = true;
  }

  /// 如果已取消则抛出 [CancelledException]
  void throwIfCancelled() {
    if (_cancelled) throw CancelledException();
  }

  /// 重置令牌
  void reset() {
    _cancelled = false;
  }
}

/// 操作被取消异常
class CancelledException implements Exception {
  @override
  String toString() => '操作已被用户取消';
}