import 'package:flutter/material.dart';

import '../core/utils/word_count_util.dart';

/// 顶部栏实时精准字数统计徽标
///
/// - 空白无文字时自动隐藏
/// - 双统计规则：含标点总字符 / 过滤 MD 符号、标点的纯写作文字
/// - 点击数字弹窗，分别查看标题、正文单独字数
class WordCountBadge extends StatefulWidget {
  final TextEditingController titleCtrl;
  final TextEditingController contentCtrl;
  final Color textColor;

  const WordCountBadge({
    super.key,
    required this.titleCtrl,
    required this.contentCtrl,
    this.textColor = const Color(0xFF94A3B8),
  });

  @override
  State<WordCountBadge> createState() => _WordCountBadgeState();
}

class _WordCountBadgeState extends State<WordCountBadge> {
  int _totalChars = 0;
  int _pureChars = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
    widget.titleCtrl.addListener(_refresh);
    widget.contentCtrl.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.titleCtrl.removeListener(_refresh);
    widget.contentCtrl.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    final title = widget.titleCtrl.text;
    final content = widget.contentCtrl.text;
    final combined = '$title\n$content';
    final stats = countWords(combined);
    if (stats.totalChars == _totalChars && stats.pureChars == _pureChars)
      return;
    setState(() {
      _totalChars = stats.totalChars;
      _pureChars = stats.pureChars;
    });
  }

  void _showDetail() {
    final titleStats = countWords(widget.titleCtrl.text);
    final contentStats = countWords(widget.contentCtrl.text);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('字数统计'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statRow('标题', titleStats),
            const Divider(height: 20),
            _statRow('正文', contentStats),
            const Divider(height: 20),
            _statRow(
              '总计',
              countWords(
                '${widget.titleCtrl.text}\n${widget.contentCtrl.text}',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, WordCountResult stats) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
          ),
          Expanded(
            child: Text(
              '总字符 ${stats.totalChars}  ·  纯写作 ${stats.pureChars}',
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_totalChars == 0) return const SizedBox.shrink();
    // 淡色小字，紧贴右上角三点菜单角落；空白无文字时自动隐藏
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _showDetail,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Text(
            '$_totalChars',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: widget.textColor,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}
