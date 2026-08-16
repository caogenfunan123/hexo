/// 发送给模型前的消息内容清理（移植 Operit ChatUtils / ChatMarkupRegex）。
///
/// 深度思考模型（DeepSeek reasoner 等）可能把推理内容以 <think>...</think>
/// 混入正文；Gemini 会在内容中追加 <meta provider="gemini:thought_signature">
/// 签名。两者既浪费 token 又干扰模型判断，发送与摘要输入前统一剥离。
class AiMessageCleaner {
  const AiMessageCleaner._();

  /// 移除 <think>/<thinking> 与 <search> 标签块，含未闭合到末尾的情况。
  static String removeThinkingContent(String content) {
    final think = RegExp(
      r'<think(?:ing)?>.*?(</think(?:ing)?>|$)',
      dotAll: true,
    );
    final search = RegExp(
      r'<search>.*?(</search>|$)',
      dotAll: true,
    );
    return content.replaceAll(think, '').replaceAll(search, '').trim();
  }

  /// 移除 Gemini thought signature 的 <meta provider="gemini:thought_signature">
  /// 标签，保留其它 <meta>（业务侧自定义标签不受影响）。
  static String stripGeminiThoughtSignatureMeta(String content) {
    final metaTag = RegExp(
      r'<meta\b[^>]*>(?:(?!<meta\b)[\s\S])*?</meta>',
      caseSensitive: false,
      dotAll: true,
    );
    return content.replaceAllMapped(metaTag, (m) {
      final tag = m.group(0) ?? '';
      if (tag.toLowerCase().contains('gemini:thought_signature')) {
        return '';
      }
      return tag;
    });
  }

  /// 发送给模型前的统一清理：先剥 thinking，再剥 Gemini 签名。
  static String cleanForModel(String content) {
    if (content.isEmpty) return content;
    return stripGeminiThoughtSignatureMeta(removeThinkingContent(content));
  }
}
