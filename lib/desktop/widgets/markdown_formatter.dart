/// Markdown 文本格式化工具
/// 自动格式化：表格对齐、列表缩进、空行规范、中英文间距
library;

/// Markdown 格式化操作
class MarkdownFormatter {
  /// 格式化完整文档（围栏代码块内部原样保留）
  static String formatDocument(String text) {
    var result = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // 按围栏代码块切段：外部段应用格式化，内部段原样保留
    final parts = <String>[];
    final inFenceParts = <bool>[];
    final lines = result.split('\n');
    final buf = StringBuffer();
    var inFence = false;
    String? fenceMarker;

    void flush() {
      if (buf.isEmpty) return;
      parts.add(buf.toString());
      inFenceParts.add(inFence);
      buf.clear();
    }

    for (final line in lines) {
      // 围栏标记行：三反引号起止，也兼容四反引号（常见于嵌入三反引号示例）
      final fenceMatch =
          RegExp(r'^(`{3,}|~{3,})').firstMatch(line.trimLeft());
      if (fenceMatch != null) {
        final marker = fenceMatch.group(1)!;
        if (!inFence) {
          fenceMarker = marker;
          flush();
          buf.writeln(line);
          flush();
          inFence = true;
        } else if (marker.startsWith(fenceMarker![0]) &&
            marker.length >= fenceMarker.length) {
          flush();
          buf.writeln(line);
          flush();
          inFence = false;
          fenceMarker = null;
        } else {
          // 围栏内误命中（如普通文本里的 ```），原样保留，不切换状态
          buf.writeln(line);
        }
      } else {
        buf.writeln(line);
      }
    }
    flush();

    final sb = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      sb.write(inFenceParts[i] ? parts[i] : _formatSegment(parts[i]));
    }
    result = sb.toString();

    // 确保文档末尾有换行
    if (!result.endsWith('\n')) {
      result += '\n';
    }
    return result;
  }

  /// 格式化一段围栏外的文本
  static String _formatSegment(String seg) {
    var result = seg;

    // 1. 中英文之间添加空格
    result = _addChineseEnglishSpace(result);

    // 2. 格式化表格
    result = _formatTables(result);

    // 3. 移除多余空行（超过 2 个连续空行合并为 1 个）
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    // 4. 标题前后确保有空行
    result = result.replaceAll(RegExp(r'([^\n])\n(#{1,6}\s)', multiLine: true), r'$1\n\n$2');

    return result;
  }

  /// 中英文之间添加空格（跳过行内代码和行内链接 URL，避免污染语法）
  static String _addChineseEnglishSpace(String text) {
    // 先提取并保护行内代码段（反引号包裹）与行内链接 URL（小括号内）
    final placeholders = <String, String>{};
    var protected = text;
    var counter = 0;
    String protect(String content) {
      final key = '\u0000S$counter\u0000';
      counter++;
      placeholders[key] = content;
      return key;
    }

    // 保护行内代码 `...`（含多反引号包裹）
    protected = protected.replaceAllMapped(
      RegExp(r'(`+)(.*?)\1'),
      (m) => m[1]! + protect(m[2]!) + m[1]!,
    );
    // 保护行内链接目标 (url "title")
    protected = protected.replaceAllMapped(
      RegExp(r'\]\(([^()\s]+)(?:\s+"[^"]*")?\)'),
      (m) => '](' + protect(m[1]!) + (m[2] ?? '') + ')',
    );

    var result = protected;
    result = result.replaceAll(
      RegExp(r'([\u4e00-\u9fff\u3400-\u4dbf])([a-zA-Z0-9(])'),
      r'$1 $2',
    );
    result = result.replaceAll(
      RegExp(r'([a-zA-Z0-9)%])([\u4e00-\u9fff\u3400-\u4dbf])'),
      r'$1 $2',
    );

    // 还原保护内容
    placeholders.forEach((key, value) {
      result = result.replaceAll(key, value);
    });
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