/// 精准字数统计工具
///
/// 双统计规则：
/// - 总字符：去除空白（空格/换行/tab）后，含标点、含 MD 符号的全部字符数
/// - 纯写作文字：在总字符基础上再过滤 MD 语法符号与中英文标点后的字数
library;

final RegExp _mdSymbols = RegExp(r'[#*_`~\[\]\(\)<>|\\\+\=\-\{\}]');
final RegExp _punctuation = RegExp(
    "[，。！？；：、（）【】《》〈〉“”‘’…—·,.!?;:()\\[\\]{}'\"<>|/\\\\@#\\\$%^&*_+=~\\-]");

/// 单文本字数统计结果
class WordCountResult {
  /// 含标点总字符（已去除空白）
  final int totalChars;

  /// 过滤 MD 符号、标点后的纯写作文字数
  final int pureChars;

  const WordCountResult({required this.totalChars, required this.pureChars});

  bool get isEmpty => totalChars == 0 && pureChars == 0;
}

/// 计算文本字数统计
WordCountResult countWords(String text) {
  final noWhitespace = text.replaceAll(RegExp(r'\s'), '');
  final totalChars = noWhitespace.length;
  final pure = noWhitespace
      .replaceAll(_mdSymbols, '')
      .replaceAll(_punctuation, '');
  return WordCountResult(
    totalChars: totalChars,
    pureChars: pure.length,
  );
}
