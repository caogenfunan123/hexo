/// 专注模式覆盖层
///
/// 参考 MarkText (https://github.com/marktext/marktext) 沉浸式写作布局：
/// - 半透明覆盖层，高亮当前编辑段落
/// - 隐藏所有工具栏和导航
/// - 点击覆盖层退出专注模式
/// - 进入/退出动画
library;

import 'package:flutter/material.dart';

/// 专注模式覆盖层
///
/// 进入专注模式时，在当前编辑区域上方渲染半透明覆盖层，
/// 只高亮当前编辑段落，其余部分变暗，帮助用户集中注意力。
class FocusModeOverlay extends StatefulWidget {
  /// 子组件（通常是编辑器内容）
  final Widget child;

  /// 是否启用专注模式
  final bool enabled;

  /// 退出专注模式的回调
  final VoidCallback? onExit;

  /// 当前高亮的段落索引（null 表示高亮全部可视区域）
  final int? highlightedParagraphIndex;

  /// 覆盖层透明度 (0.0 - 1.0)
  final double overlayOpacity;

  /// 覆盖层颜色
  final Color? overlayColor;

  const FocusModeOverlay({
    super.key,
    required this.child,
    required this.enabled,
    this.onExit,
    this.highlightedParagraphIndex,
    this.overlayOpacity = 0.6,
    this.overlayColor,
  });

  @override
  State<FocusModeOverlay> createState() => _FocusModeOverlayState();
}

class _FocusModeOverlayState extends State<FocusModeOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );

    if (widget.enabled) {
      _animController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(FocusModeOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) {
      _animController.forward();
    } else if (!widget.enabled && oldWidget.enabled) {
      _animController.reverse();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled && _animController.isDismissed) {
      return widget.child;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlayColor = widget.overlayColor ??
        (isDark ? Colors.black : const Color(0xFF1A1A2E));

    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return Stack(
          children: [
            // 底层：实际内容
            widget.child,
            // 上层：半透明覆盖层
            if (_fadeAnimation.value > 0.0)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    // 点击覆盖层边缘退出专注模式
                    widget.onExit?.call();
                  },
                  child: Container(
                    color: overlayColor.withOpacity(
                      widget.overlayOpacity * _fadeAnimation.value,
                    ),
                  ),
                ),
              ),
            // 退出按钮
            if (_fadeAnimation.value > 0.3)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 16,
                child: Opacity(
                  opacity: _fadeAnimation.value,
                  child: Material(
                    color: Colors.transparent,
                    child: IconButton(
                      icon: Icon(
                        Icons.fullscreen_exit,
                        color: isDark ? Colors.white70 : Colors.white,
                        size: 22,
                      ),
                      tooltip: '退出专注模式',
                      onPressed: widget.onExit,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withOpacity(0.3),
                      ),
                    ),
                  ),
                ),
              ),
            // 底部提示
            if (_fadeAnimation.value > 0.5)
              Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Opacity(
                  opacity: _fadeAnimation.value,
                  child: Center(
                    child: Text(
                      '专注模式 · 点击任意位置退出',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.white54,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 段落高亮包装器
///
/// 在专注模式下高亮特定段落，其余部分变暗。
/// 可与 [FocusModeOverlay] 配合使用，也可以独立使用。
class ParagraphHighlighter extends StatelessWidget {
  final Widget child;
  final bool isHighlighted;
  final double dimOpacity;

  const ParagraphHighlighter({
    super.key,
    required this.child,
    required this.isHighlighted,
    this.dimOpacity = 0.4,
  });

  @override
  Widget build(BuildContext context) {
    if (isHighlighted) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: child,
      );
    }

    return Opacity(
      opacity: dimOpacity,
      child: child,
    );
  }
}

/// 进入/退出专注模式的动画过渡 Widget
class FocusModeTransition extends StatelessWidget {
  final Widget child;
  final Animation<double> animation;

  const FocusModeTransition({
    super.key,
    required this.child,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Opacity(
          opacity: 1.0 - (animation.value * 0.3),
          child: child,
        );
      },
    );
  }
}