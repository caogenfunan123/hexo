import 'dart:math';

/// 行级差异类型
enum LineChangeType { added, removed, unchanged }

/// 单行差异
class LineChange {
  final LineChangeType type;
  final int newLineNumber; // 新文本行号（unchanged/added 有效，removed 为 -1）
  final int oldLineNumber; // 旧文本行号（unchanged/removed 有效，added 为 -1）
  final String text;

  const LineChange({
    required this.type,
    required this.newLineNumber,
    required this.oldLineNumber,
    required this.text,
  });
}

/// 行级差异结果
class LineDiffResult {
  final List<LineChange> changes;
  final bool isNewFile; // 旧文本为空 → 新建文件

  const LineDiffResult({required this.changes, this.isNewFile = false});

  int get addedCount =>
      changes.where((c) => c.type == LineChangeType.added).length;
  int get removedCount =>
      changes.where((c) => c.type == LineChangeType.removed).length;
  bool get hasChanges => addedCount > 0 || removedCount > 0;
}

/// Myers 行级 diff 计算器。
///
/// 将 [oldText] 与 [newText] 按行拆分，计算最小编辑脚本并输出带行号、
/// 类型的差异行序列，供发布前预览展示新增/删除/未变化内容。
class MarkdownDiff {
  static const LineDiffResult empty = LineDiffResult(changes: []);

  static LineDiffResult diffText(String oldText, String newText) {
    final oldLines = _splitLines(oldText);
    final newLines = _splitLines(newText);
    if (oldLines.isEmpty) {
      return LineDiffResult(
        isNewFile: true,
        changes: newLines
            .asMap()
            .entries
            .map((e) => LineChange(
                  type: LineChangeType.added,
                  newLineNumber: e.key + 1,
                  oldLineNumber: -1,
                  text: e.value,
                ))
            .toList(),
      );
    }

    // 最长公共子序列（LCS）→ 回溯得到编辑操作
    final n = oldLines.length;
    final m = newLines.length;
    final lcs = _lcsTable(oldLines, newLines);
    var ops = <_Op>[];
    var i = n;
    var j = m;
    while (i > 0 && j > 0) {
      if (oldLines[i - 1] == newLines[j - 1]) {
        ops.add(_Op(_OpKind.keep, oldLines[i - 1]));
        i--;
        j--;
      } else if (lcs[i - 1][j] >= lcs[i][j - 1]) {
        ops.add(_Op(_OpKind.del, oldLines[i - 1]));
        i--;
      } else {
        ops.add(_Op(_OpKind.add, newLines[j - 1]));
        j--;
      }
    }
    while (i > 0) {
      ops.add(_Op(_OpKind.del, oldLines[i - 1]));
      i--;
    }
    while (j > 0) {
      ops.add(_Op(_OpKind.add, newLines[j - 1]));
      j--;
    }
    ops = ops.reversed.toList();

    final changes = <LineChange>[];
    var oldLine = 0;
    var newLine = 0;
    for (final op in ops) {
      switch (op.kind) {
        case _OpKind.keep:
          oldLine++;
          newLine++;
          changes.add(LineChange(
            type: LineChangeType.unchanged,
            newLineNumber: newLine,
            oldLineNumber: oldLine,
            text: op.text,
          ));
          break;
        case _OpKind.del:
          oldLine++;
          changes.add(LineChange(
            type: LineChangeType.removed,
            newLineNumber: -1,
            oldLineNumber: oldLine,
            text: op.text,
          ));
          break;
        case _OpKind.add:
          newLine++;
          changes.add(LineChange(
            type: LineChangeType.added,
            newLineNumber: newLine,
            oldLineNumber: -1,
            text: op.text,
          ));
          break;
      }
    }

    return LineDiffResult(changes: changes);
  }

  static List<String> _splitLines(String text) {
    if (text.isEmpty) return const [];
    return text.split('\n');
  }

  static List<List<int>> _lcsTable(List<String> a, List<String> b) {
    final n = a.length;
    final m = b.length;
    final table = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        table[i][j] = a[i - 1] == b[j - 1]
            ? table[i - 1][j - 1] + 1
            : max(table[i - 1][j], table[i][j - 1]);
      }
    }
    return table;
  }
}

enum _OpKind { keep, add, del }

class _Op {
  final _OpKind kind;
  final String text;
  const _Op(this.kind, this.text);
}
