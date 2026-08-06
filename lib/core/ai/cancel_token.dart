import 'dart:async';

class CancelToken {
  final StreamController<void> _cancelCtrl = StreamController.broadcast();
  Stream<void> get onCancel => _cancelCtrl.stream;
  bool get isCancelled => _cancelCtrl.isClosed;

  void cancel() {
    if (!_cancelCtrl.isClosed) {
      _cancelCtrl.add(null);
      _cancelCtrl.close();
    }
  }
}