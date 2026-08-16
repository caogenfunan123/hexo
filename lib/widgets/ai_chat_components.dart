/// AI 对话面板纯展示组件（从 ai_chat_panel.dart 拆分）。
library;

import 'package:flutter/material.dart';

/// 思考动画：三个跳动的点
class AiThinkingDots extends StatefulWidget {
  final Color color;
  const AiThinkingDots({required this.color});

  @override
  State<AiThinkingDots> createState() => AiThinkingDotsState();
}

class AiThinkingDotsState extends State<AiThinkingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animations = List.generate(3, (i) {
      return Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: Interval(i * 0.2, 0.6 + i * 0.2, curve: Curves.easeInOut),
        ),
      );
    });
    _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('思考中',
            style: TextStyle(fontSize: 13, color: widget.color.withOpacity(0.7))),
        const SizedBox(width: 6),
        ...List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _animations[i],
            builder: (_, child) => Padding(
              padding: EdgeInsets.only(left: i > 0 ? 3 : 0),
              child: Opacity(
                opacity: _animations[i].value,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// 流式文本：带闪烁光标
class AiStreamingText extends StatefulWidget {
  final String text;
  final ColorScheme cs;
  final bool showCursor;

  const AiStreamingText({
    required this.text,
    required this.cs,
    required this.showCursor,
  });

  @override
  State<AiStreamingText> createState() => AiStreamingTextState();
}

class AiStreamingTextState extends State<AiStreamingText>
    with SingleTickerProviderStateMixin {
  late AnimationController _cursorCtrl;

  @override
  void initState() {
    super.initState();
    _cursorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _cursorCtrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _cursorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _cursorCtrl,
      builder: (_, child) {
        return RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: 14,
              color: widget.cs.onSurface,
              fontFamily: 'monospace',
              height: 1.5,
            ),
            children: [
              TextSpan(text: widget.text),
              if (widget.showCursor)
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: Opacity(
                    opacity: _cursorCtrl.value,
                    child: Container(
                      width: 2,
                      height: 16,
                      margin: const EdgeInsets.only(left: 1),
                      decoration: BoxDecoration(
                        color: widget.cs.primary,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 会话标题栏按钮
class AiSessionHeaderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onTap;

  const AiSessionHeaderButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: enabled ? cs.primary : cs.outline),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: enabled ? cs.primary : cs.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
