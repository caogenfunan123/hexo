/// UI 状态控制器 — 管理全局 loading 状态与设置持久化入口
///
/// 桌面端和手机端共用。
/// 仅保留 loading 职责：toast/错误/搜索状态因全仓零外部调用已删除
/// （2026-09 全量复盘；toast 由 shell/mobile 各自的 _showToast 承担）。
library;

import 'package:flutter/material.dart';

class UiStateController extends ChangeNotifier {
  bool _loading = true;

  // ── Getters ──
  bool get loading => _loading;

  // ── Setters ──
  void setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }
}
