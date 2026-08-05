/// Markdown 文本格式化工具
/// 自动格式化：表格对齐、列表缩进、空行规范、中英文间距
library;

/// Markdown 格式化操作
class MarkdownFormatter {
  /// 格式化完整文档
  static String formatDocument(String text) {
    var result = text;

    // 1. 统一换行符
    result = result.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // 2. 中英文之间添加空格
    result = _addChineseEnglishSpace(result);

    // 3. 格式化表格
    result = _formatTables(result);

    // 4. 确保文档末尾有换行
    if (!result.endsWith('\n')) {
      result += '\n';
    }

    // 5. 移除多余空行（超过 2 个连续空行合并为 1 个）
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    // 6. 标题前后确保有空行
    result = result.replaceAll(RegExp(r'([^\n])\n(#{1,6}\s)', multiLine: true), r'$1\n\n$2');

    // 7. 代码块前后确保有空行
    result = result.replaceAll(RegExp(r'([^\n])\n(```)', multiLine: true), r'$1\n\n$2');

    return result;
  }

  /// 中英文之间添加空格
  static String _addChineseEnglishSpace(String text) {
    // 中文后跟英文/数字
    var result = text.replaceAll(
      RegExp(r'([\u4e00-\u9fff\u3400-\u4dbf])([a-zA-Z0-9(])'),
      r'$1 $2',
    );
    // 英文/数字后跟中文
    result = result.replaceAll(
      RegExp(r'([a-zA-Z0-9)%])([\u4e00-\u9fff\u3400-\u4dbf])'),
      r'$1 $2',
    );
    return result;
  }

  /// 格式化 Markdown 表格，对齐列
  static String _formatTables(String text) {
    final lines = text.split('\n');
    final tableLines = <int>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('|') && line.endsWith('|')) {
        tableLines.add(i);
      }
    }

    if (tableLines.length < 3) return text;

    // 分组连续的表格行
    var groupStart = 0;
    for (var i = 1; i <= tableLines.length; i++) {
      final isLast = i == tableLines.length;
      final isBreak = isLast || tableLines[i] != tableLines[i - 1] + 1;

      if (isBreak) {
        final group = tableLines.sublist(groupStart, i);
        if (group.length >= 3) {
          _formatTableGroup(lines, group);
        }
        groupStart = i;
      }
    }

    return lines.join('\n');
  }

  /// 格式化一个表格组
  static void _formatTableGroup(List<String> lines, List<int> indices) {
    // 解析每行的列
    final rows = <List<String>>[];
    for (final idx in indices) {
      final cells = lines[idx]
          .split('|')
          .map((c) => c.trim())
          .toList();
      // 移除首尾空元素
      if (cells.isNotEmpty && cells.first.isEmpty) cells.removeAt(0);
      if (cells.isNotEmpty && cells.last.isEmpty) cells.removeLast();
      rows.add(cells);
    }

    if (rows.isEmpty) return;

    // 计算每列最大宽度
    final colCount = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    final colWidths = List<int>.filled(colCount, 0);
    for (final row in rows) {
      for (var c = 0; c < row.length && c < colCount; c++) {
        if (row[c].length > colWidths[c]) {
          colWidths[c] = row[c].length;
        }
      }
    }

    // 重新格式化每行
    for (var r = 0; r < rows.length; r++) {
      final formatted = StringBuffer('| ');
      for (var c = 0; c < colCount; c++) {
        final cell = c < rows[r].length ? rows[r][c] : '';
        formatted.write(cell.padRight(colWidths[c]));
        if (c < colCount - 1) formatted.write(' | ');
      }
      formatted.write(' |');
      lines[indices[r]] = formatted.toString();
    }
  }

  /// 统计字数（中文按字，英文按词）
  static int countWords(String text) {
    if (text.isEmpty) return 0;
    // 中文字符
    final chinese = RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf]').allMatches(text).length;
    // 英文单词
    final english = text
        .replaceAll(RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    return chinese + english;
  }

  /// 计算阅读时间（中文约 400 字/分钟）
  static int estimateReadMinutes(String text) {
    final chars = text.length;
    return chars > 0 ? (chars / 400).ceil().clamp(1, 120) : 0;
  }
}