/// AI 对话消息模型（从 ai_chat_panel.dart 拆分）。
library;

/// 解析出的文件操作
class ParsedFileOp {
  final String path;
  final String content;
  final String language;
  bool written;
  String? writeError;

  ParsedFileOp({
    required this.path,
    required this.content,
    this.language = 'text',
    this.written = false,
    this.writeError,
  });

  ParsedFileOp copy() => ParsedFileOp(
        path: path,
        content: content,
        language: language,
        written: written,
        writeError: writeError,
      );
}

/// 单条聊天消息（UI 视图模型）
class ChatMessage {
  final String role;
  final String content;
  final DateTime time;
  final List<Map<String, dynamic>>? toolCalls; // assistant 消息携带的工具调用
  final String? toolCallId; // tool 消息携带的调用 ID
  final String? reasoningContent; // assistant 消息的推理过程

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? time,
    this.toolCalls,
    this.toolCallId,
    this.reasoningContent,
  }) : time = time ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'time': time.toIso8601String(),
        if (toolCalls != null) 'toolCalls': toolCalls,
        if (toolCallId != null) 'toolCallId': toolCallId,
        if (reasoningContent != null) 'reasoningContent': reasoningContent,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        role: j['role']?.toString() ?? 'system',
        content: j['content']?.toString() ?? '',
        time: DateTime.tryParse(j['time']?.toString() ?? '') ?? DateTime.now(),
        toolCalls: (j['toolCalls'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        toolCallId: j['toolCallId']?.toString(),
        reasoningContent: j['reasoningContent']?.toString(),
      );

  /// 是否能在 UI 中显示（system / user / assistant 可显示，tool 不可显示）
  bool get showInUi => role == 'system' || role == 'user' || role == 'assistant';

  /// 从 dispatcher 的 Map 格式创建
  factory ChatMessage.fromContextMap(Map<String, dynamic> m) => ChatMessage(
        role: m['role']?.toString() ?? 'system',
        content: m['content']?.toString() ?? '',
        toolCalls: (m['tool_calls'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        toolCallId: m['tool_call_id']?.toString(),
        reasoningContent: m['reasoning_content']?.toString() ??
            m['reasoningContent']?.toString(),
      );
}

/// web_search 结果条目
class SearchEntry {
  final String title;
  final String url;
  const SearchEntry(this.title, this.url);
}
