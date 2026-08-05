import 'dart:convert';

/// AI 输出指令解析结果
class ParsedInstruction {
  final InstructionType type;
  final String? rawContent;
  final Map<String, dynamic>? jsonData;
  final Map<String, String>? params;
  final String? queryText;

  const ParsedInstruction({
    required this.type,
    this.rawContent,
    this.jsonData,
    this.params,
    this.queryText,
  });

  bool get isActionable => type != InstructionType.none;
}

enum InstructionType {
  none,
  newMcp,        // 【NEW_MCP】
  newSkill,      // 【NEW_SKILL】
  mcpCall,       // 【MCP_CALL】
  skillRun,      // 【SKILL_RUN】
  webSearch,     // 【联网搜索】
  webFetch,      // 【网页抓取】
  filePath,      // 【文件路径】
  callTool,      // 【调用工具】
}

/// 指令解析器：拦截 AI 输出中的特殊指令标记
class InstructionParser {
  // ── 正则表达式 ──

  /// 匹配 【NEW_MCP】 + JSON代码块
  static final RegExp _newMcpRegex = RegExp(
    r'【NEW_MCP】\s*```json\s*([\s\S]*?)```',
    multiLine: true,
  );

  /// 匹配 【NEW_SKILL】 + JSON代码块
  static final RegExp _newSkillRegex = RegExp(
    r'【NEW_SKILL】\s*```json\s*([\s\S]*?)```',
    multiLine: true,
  );

  /// 匹配 【MCP_CALL】name=xxx;params={...}
  static final RegExp _mcpCallRegex = RegExp(
    r'【MCP_CALL】\s*name=([^;]+);\s*params=(\{[^}]+\})',
  );

  /// 匹配 【SKILL_RUN】skill_id=xxx;vars={...}
  static final RegExp _skillRunRegex = RegExp(
    r'【SKILL_RUN】\s*skill_id=([^;]+);\s*vars=(\{[^}]+\})',
  );

  /// 匹配 【联网搜索】关键词
  static final RegExp _webSearchRegex = RegExp(
    r'【联网搜索】(.+?)(?:\n|$)',
  );

  /// 匹配 【网页抓取】URL
  static final RegExp _webFetchRegex = RegExp(
    r'【网页抓取】(.+?)(?:\n|$)',
  );

  /// 匹配 【文件路径】path
  static final RegExp _filePathRegex = RegExp(
    r'【文件路径】(.+?)(?:\n|$)',
  );

  /// 匹配 【调用工具】名称(参数) 或 【调用工具】名称 | 参数
  static final RegExp _callToolRegex = RegExp(
    r'【调用工具】(.+?)(?:\n|$)',
  );

  /// 解析 AI 输出文本，提取所有指令
  static List<ParsedInstruction> parseAll(String text) {
    final instructions = <ParsedInstruction>[];

    // NEW_MCP
    for (final m in _newMcpRegex.allMatches(text)) {
      final jsonStr = m.group(1)?.trim() ?? '';
      Map<String, dynamic>? jsonData;
      try {
        jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (_) {}
      instructions.add(ParsedInstruction(
        type: InstructionType.newMcp,
        rawContent: jsonStr,
        jsonData: jsonData,
      ));
    }

    // NEW_SKILL
    for (final m in _newSkillRegex.allMatches(text)) {
      final jsonStr = m.group(1)?.trim() ?? '';
      Map<String, dynamic>? jsonData;
      try {
        jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (_) {}
      instructions.add(ParsedInstruction(
        type: InstructionType.newSkill,
        rawContent: jsonStr,
        jsonData: jsonData,
      ));
    }

    // MCP_CALL
    for (final m in _mcpCallRegex.allMatches(text)) {
      final name = m.group(1)?.trim() ?? '';
      final paramsStr = m.group(2)?.trim() ?? '{}';
      Map<String, String> params = {};
      try {
        final parsed = jsonDecode(paramsStr);
        if (parsed is Map) {
          params = parsed.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}
      instructions.add(ParsedInstruction(
        type: InstructionType.mcpCall,
        params: {'name': name, ...params},
      ));
    }

    // SKILL_RUN
    for (final m in _skillRunRegex.allMatches(text)) {
      final skillId = m.group(1)?.trim() ?? '';
      final varsStr = m.group(2)?.trim() ?? '{}';
      Map<String, String> params = {'skill_id': skillId};
      try {
        final parsed = jsonDecode(varsStr);
        if (parsed is Map) {
          params.addAll(parsed.map((k, v) => MapEntry(k.toString(), v.toString())));
        }
      } catch (_) {}
      instructions.add(ParsedInstruction(
        type: InstructionType.skillRun,
        params: params,
      ));
    }

    // 联网搜索
    for (final m in _webSearchRegex.allMatches(text)) {
      instructions.add(ParsedInstruction(
        type: InstructionType.webSearch,
        queryText: m.group(1)?.trim(),
      ));
    }

    // 网页抓取
    for (final m in _webFetchRegex.allMatches(text)) {
      instructions.add(ParsedInstruction(
        type: InstructionType.webFetch,
        queryText: m.group(1)?.trim(),
      ));
    }

    // 文件路径
    for (final m in _filePathRegex.allMatches(text)) {
      instructions.add(ParsedInstruction(
        type: InstructionType.filePath,
        queryText: m.group(1)?.trim(),
      ));
    }

    // 调用工具
    for (final m in _callToolRegex.allMatches(text)) {
      instructions.add(ParsedInstruction(
        type: InstructionType.callTool,
        queryText: m.group(1)?.trim(),
      ));
    }

    return instructions;
  }

  /// 检查文本中是否包含任何可执行指令
  static bool hasInstructions(String text) {
    return _newMcpRegex.hasMatch(text) ||
        _newSkillRegex.hasMatch(text) ||
        _mcpCallRegex.hasMatch(text) ||
        _skillRunRegex.hasMatch(text) ||
        _webSearchRegex.hasMatch(text) ||
        _webFetchRegex.hasMatch(text) ||
        _filePathRegex.hasMatch(text) ||
        _callToolRegex.hasMatch(text);
  }

  /// 从文本中移除指令标记，返回纯文本
  static String stripInstructions(String text) {
    var result = text;
    result = result.replaceAll(_newMcpRegex, '');
    result = result.replaceAll(_newSkillRegex, '');
    result = result.replaceAll(_mcpCallRegex, '');
    result = result.replaceAll(_skillRunRegex, '');
    result = result.replaceAll(_webSearchRegex, '');
    result = result.replaceAll(_webFetchRegex, '');
    result = result.replaceAll(_filePathRegex, '');
    result = result.replaceAll(_callToolRegex, '');
    // 清理多余空行
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return result.trim();
  }
}