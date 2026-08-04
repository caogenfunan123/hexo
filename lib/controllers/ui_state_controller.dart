/// UI 状态控制器 — 管理全局 UI 状态（加载、弹窗、错误提示等）
///
/// 桌面端和手机端共用
library;

import 'package:flutter/material.dart';

class UiStateController extends ChangeNotifier {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _toastMessage;
  String _searchQuery = '';
  bool _searchLoading = false;

  // ── Getters ──
  bool get loading => _loading;
  bool get busy => _busy;
  String? get error => _error;
  String? get toastMessage => _toastMessage;
  String get searchQuery => _searchQuery;
  bool get searchLoading => _searchLoading;

  // ── Setters ──
  void setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }

  void setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  void setError(String? error) {
    _error = error;
    notifyListeners();
  }

  void showToast(String message) {
    _toastMessage = message;
    notifyListeners();
    // 自动清除
    Future.delayed(const Duration(seconds: 3), () {
      if (_toastMessage == message) {
        _toastMessage = null;
        notifyListeners();
      }
    });
  }

  void clearToast() {
    _toastMessage = null;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setSearchLoading(bool value) {
    _searchLoading = value;
    notifyListeners();
  }
}