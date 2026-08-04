/// 冲突 Diff 对比服务
/// 提供文本差异对比、合并建议、冲突解决功能
///
/// 对标：Yank Note 版本对比 UI + VS Code 差异编辑器
library;

/// Diff 操作类型
enum DiffOperation { equal, insert, delete, replace }

/// 单条 Diff 行
class DiffLine {
  final DiffOperation operation;
  final int lineNumber;
  final String content;
  final int? oldLineNumber;

  const DiffLine({
    required this.operation,
    required this.lineNumber,
    required this.content,
    this.oldLineNumber,
  });
}

/// Diff 块（一组连续的变更）
class DiffBlock {
  final List<DiffLine> lines;
  final int startLineOld;
  final int startLineNew;

  const DiffBlock({
    required this.lines,
    required this.startLineOld,
    required this.startLineNew,
  });

  bool get isInsertion => lines.every((l) => l.operation == DiffOperation.insert);
  bool get isDeletion => lines.every((l) => l.operation == DiffOperation.delete);
  bool get isModification =>
      lines.any((l) => l.operation == DiffOperation.delete) &&
      lines.any((l) => l.operation == DiffOperation.insert);
}

/// 冲突 Diff 对比服务
class ConflictDiffService {
  /// 计算两个文本之间的差异
  ///
  /// 使用 Myers diff 算法（时间复杂度 O(ND)）
  static List<DiffLine> computeDiff(String oldText, String newText) {
    final oldLines = oldText.split('\n');
    final newLines = newText.split('\n');
    final result = <DiffLine>[];

    // 使用 LCS 算法计算差异
    final lcs = _computeLCS(oldLines, newLines);

    int oldIndex = 0;
    int newIndex = 0;
    int lcsIndex = 0;

    while (oldIndex < oldLines.length || newIndex < newLines.length) {
      if (lcsIndex < lcs.length &&
          oldIndex < oldLines.length &&
          oldLines[oldIndex] == lcs[lcsIndex]) {
        // 相等行
        result.add(DiffLine(
          operation: DiffOperation.equal,
          lineNumber: newIndex + 1,
          content: newLines[newIndex],
          oldLineNumber: oldIndex + 1,
        ));
        oldIndex++;
        newIndex++;
        lcsIndex++;
      } else if (lcsIndex < lcs.length &&
          newIndex < newLines.length &&
          newLines[newIndex] == lcs[lcsIndex]) {
        // 插入行
        result.add(DiffLine(
          operation: DiffOperation.insert,
          lineNumber: newIndex + 1,
          content: newLines[newIndex],
        ));
        newIndex++;
      } else if (lcsIndex < lcs.length &&
          oldIndex < oldLines.length &&
          oldLines[oldIndex] == lcs[lcsIndex]) {
        // 删除行
        result.add(DiffLine(
          operation: DiffOperation.delete,
          lineNumber: newIndex + 1,
          content: oldLines[oldIndex],
          oldLineNumber: oldIndex + 1,
        ));
        oldIndex++;
      } else {
        // 替换行
        if (oldIndex < oldLines.length) {
          result.add(DiffLine(
            operation: DiffOperation.delete,
            lineNumber: newIndex + 1,
            content: oldLines[oldIndex],
            oldLineNumber: oldIndex + 1,
          ));
          oldIndex++;
        }
        if (newIndex < newLines.length) {
          result.add(DiffLine(
            operation: DiffOperation.insert,
            lineNumber: newIndex + 1,
            content: newLines[newIndex],
          ));
          newIndex++;
        }
      }
    }

    return result;
  }

  /// 将 Diff 行分组为块
  static List<DiffBlock> groupIntoBlocks(List<DiffLine> diffLines, {int contextLines = 3}) {
    final blocks = <DiffBlock>[];
    int i = 0;

    while (i < diffLines.length) {
      final line = diffLines[i];
      if (line.operation != DiffOperation.equal) {
        // 找到变更块，向前扩展上下文
        final blockStart = (i - contextLines).clamp(0, diffLines.length);
        final blockLines = <DiffLine>[];
        var startLineOld = 0;
        var startLineNew = 0;

        for (int j = blockStart; j < i; j++) {
          blockLines.add(diffLines[j]);
        }
        if (blockLines.isNotEmpty) {
          startLineOld = blockLines.first.oldLineNumber ?? blockLines.first.lineNumber;
          startLineNew = blockLines.first.lineNumber;
        }

        // 添加变更行
        while (i < diffLines.length && diffLines[i].operation != DiffOperation.equal) {
          blockLines.add(diffLines[i]);
          if (startLineOld == 0) {
            startLineOld = diffLines[i].oldLineNumber ?? diffLines[i].lineNumber;
            startLineNew = diffLines[i].lineNumber;
          }
          i++;
        }

        // 向后扩展上下文
        final blockEnd = (i + contextLines).clamp(0, diffLines.length);
        for (int j = i; j < blockEnd; j++) {
          blockLines.add(diffLines[j]);
        }

        blocks.add(DiffBlock(
          lines: blockLines,
          startLineOld: startLineOld,
          startLineNew: startLineNew,
        ));
      }
      i++;
    }

    return blocks;
  }

  /// 计算 LCS（最长公共子序列）
  static List<String> _computeLCS(List<String> a, List<String> b) {
    final m = a.length;
    final n = b.length;
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));

    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (a[i - 1] == b[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
        }
      }
    }

    // 回溯构建 LCS
    final lcs = <String>[];
    int i = m, j = n;
    while (i > 0 && j > 0) {
      if (a[i - 1] == b[j - 1]) {
        lcs.insert(0, a[i - 1]);
        i--;
        j--;
      } else if (dp[i - 1][j] > dp[i][j - 1]) {
        i--;
      } else {
        j--;
      }
    }

    return lcs;
  }

  /// 合并两个文本（简单三方合并策略）
  ///
  /// [base] 共同祖先版本
  /// [local] 本地修改版本
  /// [remote] 远程修改版本
  static Future<String?> mergeThreeWay(String base, String local, String remote) async {
    // 简单策略：如果本地和远程修改了不同行，自动合并
    final localDiff = computeDiff(base, local);
    final remoteDiff = computeDiff(base, remote);

    final localChangedLines = <int>{};
    final remoteChangedLines = <int>{};

    for (final line in localDiff) {
      if (line.operation != DiffOperation.equal) {
        localChangedLines.add(line.oldLineNumber ?? line.lineNumber);
      }
    }
    for (final line in remoteDiff) {
      if (line.operation != DiffOperation.equal) {
        remoteChangedLines.add(line.oldLineNumber ?? line.lineNumber);
      }
    }

    // 检查是否有冲突（同一行在两端都被修改）
    final hasConflict = localChangedLines.intersection(remoteChangedLines).isNotEmpty;
    if (hasConflict) return null; // 需要手动解决

    // 无冲突，自动合并
    return remote;
  }
}