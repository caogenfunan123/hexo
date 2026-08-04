/// 编辑器全局动画
///
/// 提供编辑器内各类过渡动画的工厂方法：
/// - 模式切换过渡动画（普通 -> 专注 -> 打字机）
/// - 保存成功/失败动画
/// - 发布成功动画
/// - 面板展开/收起动画
library;

import 'package:flutter/material.dart';

/// 编辑器动画封装
///
/// 提供统一的动画构建方法，确保编辑器内所有动画效果一致。
class EditorAnimations {
  EditorAnimations._();

  // ============================================================
  // 基础过渡动画
  // ============================================================

  /// 淡入淡出过渡
  static Widget fadeTransition(Widget child, Animation<double> animation) {
    return FadeTransition(opacity: animation, child: child);
  }

  /// 滑动过渡
  static Widget slideTransition(Widget child, Animation<Offset> animation) {
    return SlideTransition(position: animation, child: child);
  }

  /// 缩放过渡
  static Widget scaleTransition(Widget child, Animation<double> animation) {
    return ScaleTransition(scale: animation, child: child);
  }

  /// 组合过渡：淡入 + 缩放
  static Widget fadeScaleTransition(Widget child, Animation<double> animation) {
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.95, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOut),
        ),
        child: child,
      ),
    );
  }

  /// 组合过渡：淡入 + 上滑
  static Widget fadeSlideUpTransition(Widget child, Animation<double> animation) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
    );
  }

  // ============================================================
  // 模式切换动画
  // ============================================================

  /// 模式切换过渡（普通 -> 专注 -> 打字机）
  ///
  /// 使用 AnimatedSwitcher 实现平滑的模式切换效果。
  static Widget modeSwitchTransition({
    required Widget child,
    required Duration duration,
    Curve curve = Curves.easeInOut,
  }) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: curve,
      switchOutCurve: curve,
      transitionBuilder: (widget, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: curve),
            ),
            child: widget,
          ),
        );
      },
      child: child,
    );
  }

  // ============================================================
  // 保存动画
  // ============================================================

  /// 保存成功动画 Widget
  ///
  /// 显示一个绿色对勾图标，带缩放弹出效果。
  static Widget saveSuccessAnimation({
    required BuildContext context,
    Duration duration = const Duration(milliseconds: 600),
  }) {
    return _AnimatedStatusIcon(
      icon: Icons.check_circle,
      color: const Color(0xFF4CAF50),
      duration: duration,
    );
  }

  /// 保存失败动画 Widget
  ///
  /// 显示一个红色错误图标，带抖动效果。
  static Widget saveErrorAnimation({
    required BuildContext context,
    Duration duration = const Duration(milliseconds: 600),
  }) {
    return _AnimatedStatusIcon(
      icon: Icons.error,
      color: const Color(0xFFEF5350),
      duration: duration,
    );
  }

  // ============================================================
  // 发布动画
  // ============================================================

  /// 发布成功动画 Widget
  ///
  /// 显示火箭图标，带向上飞行动画。
  static Widget publishSuccessAnimation({
    required BuildContext context,
    Duration duration = const Duration(milliseconds: 800),
  }) {
    return _AnimatedStatusIcon(
      icon: Icons.rocket_launch,
      color: const Color(0xFF7C4DFF),
      duration: duration,
      useSlide: true,
    );
  }

  // ============================================================
  // 面板动画
  // ============================================================

  /// 面板展开/收起动画
  static Widget panelExpandAnimation({
    required Widget child,
    required bool isExpanded,
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.easeInOut,
  }) {
    return AnimatedCrossFade(
      firstChild: const SizedBox.shrink(),
      secondChild: child,
      crossFadeState:
          isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      duration: duration,
      firstCurve: curve,
      secondCurve: curve,
      sizeCurve: curve,
    );
  }

  /// 抽屉滑入/滑出动画
  static Widget drawerSlideAnimation({
    required Widget child,
    required bool isOpen,
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.easeOut,
    double width = 300,
  }) {
    return AnimatedContainer(
      duration: duration,
      curve: curve,
      width: isOpen ? width : 0,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: child,
    );
  }
}

/// 内部：带动画的状态图标
class _AnimatedStatusIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final Duration duration;
  final bool useSlide;

  const _AnimatedStatusIcon({
    required this.icon,
    required this.color,
    required this.duration,
    this.useSlide = false,
  });

  @override
  State<_AnimatedStatusIcon> createState() => _AnimatedStatusIconState();
}

class _AnimatedStatusIconState extends State<_AnimatedStatusIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.3), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));

    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(_controller);

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.translate(
            offset: widget.useSlide
                ? _slideAnimation.value
                : Offset.zero,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Icon(
                widget.icon,
                color: widget.color,
                size: 48,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 编辑器操作反馈 Toast
///
/// 在编辑器底部显示操作反馈，自动消失。
class EditorActionToast {
  /// 显示保存成功 Toast
  static void showSaveSuccess(BuildContext context, {String? message}) {
    _showToast(
      context,
      message: message ?? '已保存',
      icon: Icons.check_circle,
      color: const Color(0xFF4CAF50),
    );
  }

  /// 显示保存失败 Toast
  static void showSaveError(BuildContext context, {String? message}) {
    _showToast(
      context,
      message: message ?? '保存失败',
      icon: Icons.error,
      color: const Color(0xFFEF5350),
    );
  }

  /// 显示发布成功 Toast
  static void showPublishSuccess(BuildContext context, {String? message}) {
    _showToast(
      context,
      message: message ?? '发布成功',
      icon: Icons.cloud_done,
      color: const Color(0xFF7C4DFF),
    );
  }

  /// 显示信息 Toast
  static void showInfo(BuildContext context, {required String message}) {
    _showToast(
      context,
      message: message,
      icon: Icons.info_outline,
      color: const Color(0xFF2196F3),
    );
  }

  static void _showToast(
    BuildContext context, {
    required String message,
    required IconData icon,
    required Color color,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: color.withOpacity(0.9),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: '关闭',
          textColor: Colors.white70,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }
}