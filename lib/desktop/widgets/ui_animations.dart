/// UI 动画系统
/// 统一的界面过渡动画配置，覆盖面板、抽屉、标签页、主题、按钮、Toast
/// 对标：Material 3 动画规范 + MarkText 专注模式切换
library;

import 'package:flutter/material.dart';

/// 动画配置常量（对齐 UI 规范）
class AnimationConfig {
  // 时长
  static const Duration panel = Duration(milliseconds: 200);
  static const Duration drawer = Duration(milliseconds: 250);
  static const Duration tab = Duration(milliseconds: 150);
  static const Duration theme = Duration(milliseconds: 400);
  static const Duration button = Duration(milliseconds: 100);
  static const Duration toast = Duration(milliseconds: 200);
  static const Duration modeSwitch = Duration(milliseconds: 300);
  static const Duration focusHighlight = Duration(milliseconds: 150);

  // 曲线
  static const Curve panelCurve = Curves.easeInOut;
  static const Curve drawerCurve = Curves.easeOut;
  static const Curve tabCurve = Curves.ease;
  static const Curve themeCurve = Curves.easeInOut;
  static const Curve buttonCurve = Curves.easeOut;
  static const Curve toastCurve = Curves.easeInOut;
  static const Curve modeSwitchCurve = Curves.easeInOut;
  static const Curve focusHighlightCurve = Curves.easeOut;
}

/// 面板动画包装器
/// 用于左侧面板和右侧抽屉的展开/折叠动画
class PanelAnimation extends StatelessWidget {
  final Widget child;
  final bool isVisible;
  final AxisDirection direction;
  final double width;

  const PanelAnimation({
    super.key,
    required this.child,
    required this.isVisible,
    this.direction = AxisDirection.left,
    this.width = 260,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AnimationConfig.panel,
      curve: AnimationConfig.panelCurve,
      width: isVisible ? width : 0,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: AnimatedOpacity(
        duration: AnimationConfig.panel,
        curve: AnimationConfig.panelCurve,
        opacity: isVisible ? 1.0 : 0.0,
        child: SizedBox(width: width, child: child),
      ),
    );
  }
}

/// 抽屉动画包装器
class DrawerAnimation extends StatelessWidget {
  final Widget child;
  final bool isOpen;
  final double width;

  const DrawerAnimation({
    super.key,
    required this.child,
    required this.isOpen,
    this.width = 320,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: AnimationConfig.drawer,
      curve: AnimationConfig.drawerCurve,
      right: isOpen ? 0 : -width,
      top: 0,
      bottom: 0,
      width: width,
      child: child,
    );
  }
}

/// 标签页切换动画
class TabSwitchAnimation extends StatelessWidget {
  final Widget child;
  final AnimationController? controller;

  const TabSwitchAnimation({
    super.key,
    required this.child,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AnimationConfig.tab,
      switchInCurve: AnimationConfig.tabCurve,
      switchOutCurve: AnimationConfig.tabCurve,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.02, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: AnimationConfig.tabCurve,
            )),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// 主题切换动画
class ThemeTransition extends StatelessWidget {
  final Widget child;
  final bool isDark;

  const ThemeTransition({
    super.key,
    required this.child,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AnimationConfig.theme,
      curve: AnimationConfig.themeCurve,
      color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF5F5F7),
      child: child,
    );
  }
}

/// 按钮动画
class ButtonAnimation extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const ButtonAnimation({
    super.key,
    required this.child,
    this.onTap,
  });

  @override
  State<ButtonAnimation> createState() => _ButtonAnimationState();
}

class _ButtonAnimationState extends State<ButtonAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AnimationConfig.button,
      vsync: this,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: AnimationConfig.buttonCurve),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

/// Toast 动画
class ToastAnimation extends StatefulWidget {
  final Widget child;
  final bool isVisible;
  final VoidCallback? onDismiss;

  const ToastAnimation({
    super.key,
    required this.child,
    required this.isVisible,
    this.onDismiss,
  });

  @override
  State<ToastAnimation> createState() => _ToastAnimationState();
}

class _ToastAnimationState extends State<ToastAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AnimationConfig.toast,
      vsync: this,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: AnimationConfig.toastCurve),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: AnimationConfig.toastCurve),
    );
  }

  @override
  void didUpdateWidget(ToastAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _controller.forward();
    } else if (!widget.isVisible && oldWidget.isVisible) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WidgetAnimator(
      listenable: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.translate(
            offset: _slide.value,
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// 工作模式切换动画
class ModeSwitchAnimation extends StatelessWidget {
  final Widget child;
  final AnimationController? controller;

  const ModeSwitchAnimation({
    super.key,
    required this.child,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AnimationConfig.modeSwitch,
      switchInCurve: AnimationConfig.modeSwitchCurve,
      switchOutCurve: AnimationConfig.modeSwitchCurve,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1.0).animate(
              CurvedAnimation(
                parent: animation,
                curve: AnimationConfig.modeSwitchCurve,
              ),
            ),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// 专注模式遮罩动画
class FocusMaskAnimation extends StatelessWidget {
  final Widget child;
  final bool isFocusMode;

  const FocusMaskAnimation({
    super.key,
    required this.child,
    required this.isFocusMode,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: AnimationConfig.focusHighlight,
      curve: AnimationConfig.focusHighlightCurve,
      color: isFocusMode
          ? (isDark ? Colors.black : const Color(0xFFF0F0F0))
          : Colors.transparent,
      child: child,
    );
  }
}

/// 用于构建动画的便捷适配器
class WidgetAnimator extends AnimatedWidget {
  final TransitionBuilder builder;
  final Widget? child;

  const WidgetAnimator({
    super.key,
    required super.listenable,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}