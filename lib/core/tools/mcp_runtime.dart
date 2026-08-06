import 'dart:convert';

import '../ai/ai_tool_manager.dart';
import 'builtin_tools.dart';
import 'instruction_parser.dart';
import 'skill_manager.dart';
import 'tool_entity.dart';
import 'tool_registry.dart';
import 'tool_schema_validator.dart';

/// MCP 运行时指令执行结果
class McpRuntimeResult {
  final bool success;
  final String message;
  final String? error;
  final Map<String, dynamic>? data;

  const McpRuntimeResult({
    required this.success,
    required this.message,
    this.error,
    this.data,
  });
}

/// MCP 运行时：解析并执行 AI 输出的指令
class McpRuntime {
  final SkillManager _skillManager;
  final ToolRegistry _registry;
  final ToolSchemaValidator _validator;
  final AiToolManager? _toolManager;

  /// 当前站点 ID（站点私有工具归属）
  String? siteId;

  /// 是否允许 AI 自动保存工具（设置页总开关）
  bool allowAutoSave = true;

  McpRuntime(
    this._skillManager,
    this._registry, {
    AiToolManager? toolManager,
    String? siteId,
    this.allowAutoSave = true,
  })  : _toolManager = toolManager,
        _validator = ToolSchemaValidator(),
        siteId = siteId;

  /// 执行解析出的指令列表
  Future<List<McpRuntimeResult>> executeInstructions(
    List<ParsedInstruction> instructions,
  ) async {
    final results = <McpRuntimeResult>[];
    for (final inst in instructions) {
      results.add(await executeInstruction(inst));
    }
    return results;
  }

  /// 执行单个指令
  Future<McpRuntimeResult> executeInstruction(ParsedInstruction inst) async {
    switch (inst.type) {
      case InstructionType.newMcp:
        return await _handleNewMcp(inst);
      case InstructionType.newSkill:
        return _handleNewSkill(inst);
      case InstructionType.mcpCall:
        return _handleMcpCall(inst);
      case InstructionType.skillRun:
        return _handleSkillRun(inst);
      case InstructionType.webSearch:
        return _handleWebSearch(inst);
      case InstructionType.webFetch:
        return _handleWebFetch(inst);
      case InstructionType.filePath:
        return _handleFilePath(inst);
      case InstructionType.callTool:
        return _handleCallTool(inst);
      case InstructionType.none:
        return const McpRuntimeResult(success: true, message: '');
    }
  }

  /// 处理【NEW_MCP】—— 保存新的 MCP 工具
  Future<McpRuntimeResult> _handleNewMcp(ParsedInstruction inst) async {
    if (inst.jsonData == null) {
      return McpRuntimeResult(
        success: false,
        message: 'MCP JSON 解析失败',
        error: 'JSON 格式无效',
      );
    }

    final json = inst.jsonData!;
    final meta = json['meta'] as Map<String, dynamic>?;
    if (meta == null) {
      return McpRuntimeResult(
        success: false,
        message: 'MCP 定义缺少 meta 字段',
        error: '格式不符合规范',
      );
    }

    final name = meta['name']?.toString() ?? '';
    final displayName = meta['display_name']?.toString() ?? name;
    final description = meta['description']?.toString() ?? '';
    final riskLevel = meta['risk_level']?.toString() ?? 'middle';

    // ── 双重校验：格式 + 危险操作黑名单 ──
    final validation = _validator.validateMcp(json);
    if (!validation.pass) {
      return McpRuntimeResult(
        success: false,
        message: 'MCP 定义未通过校验，未保存',
        error: validation.message,
        data: {'validation': validation.message, 'blocked_by': validation.blockedBy},
      );
    }

    // ── 解析参数 ──
    final paramsList = <ToolParam>[];
    final paramsRaw = json['params'] as List?;
    if (paramsRaw != null) {
      for (final p in paramsRaw) {
        if (p is Map) {
          paramsList.add(ToolParam(
            name: p['key']?.toString() ?? '',
            type: p['type']?.toString() ?? 'string',
            description: p['description']?.toString() ?? '',
            required: p['required'] == true,
            defaultValue: p['default'],
          ));
        }
      }
    }

    // 自动保存总开关：关闭时仅返回校验通过信息，不落库
    if (!allowAutoSave) {
      return McpRuntimeResult(
        success: false,
        message: 'MCP 校验通过，但 AI 自动保存已关闭',
        error: '请前往设置开启「允许 AI 自动保存工具」，或在工具箱手动创建',
        data: {'validation_passed': true, 'risk_level': riskLevel},
      );
    }

    // 持久化到磁盘（通过 SkillManager），带作用域与来源标记
    try {
      final scope = _resolveScope(meta);
      final tool = await _skillManager.registerMcpTool(
        name: displayName,
        description: description,
        endpoint: name,
        parameters: paramsList,
        scope: scope,
        source: ToolSource.ai,
        siteId: scope == ToolScope.sitePrivate ? siteId : null,
        riskLevel: riskLevel,
      );
      return McpRuntimeResult(
        success: true,
        message: 'MCP工具 "$displayName" 已保存到工具库',
        data: {
          'tool_id': tool.id,
          'risk_level': riskLevel,
          'scope': scope.name,
        },
      );
    } catch (e) {
      return McpRuntimeResult(
        success: false,
        message: '保存 MCP 工具失败',
        error: e.toString(),
      );
    }
  }

  /// 处理【NEW_SKILL】—— 保存新的 Skill
  Future<McpRuntimeResult> _handleNewSkill(ParsedInstruction inst) async {
    if (inst.jsonData == null) {
      return McpRuntimeResult(
        success: false,
        message: 'Skill JSON 解析失败',
        error: 'JSON 格式无效',
      );
    }

    final json = inst.jsonData!;
    final meta = json['meta'] as Map<String, dynamic>?;
    if (meta == null) {
      return McpRuntimeResult(
        success: false,
        message: 'Skill 定义缺少 meta 字段',
        error: '格式不符合规范',
      );
    }

    final name = meta['name']?.toString() ?? '';
    final displayName = meta['display_name']?.toString() ?? name;
    final description = meta['description']?.toString() ?? '';

    // ── 双重校验：格式 + 危险操作黑名单 ──
    final validation = _validator.validateSkill(json);
    if (!validation.pass) {
      return McpRuntimeResult(
        success: false,
        message: 'Skill 定义未通过校验，未保存',
        error: validation.message,
        data: {'validation': validation.message, 'blocked_by': validation.blockedBy},
      );
    }

    // 自动保存总开关：关闭时仅返回校验通过信息，不落库
    if (!allowAutoSave) {
      return McpRuntimeResult(
        success: false,
        message: 'Skill 校验通过，但 AI 自动保存已关闭',
        error: '请前往设置开启「允许 AI 自动保存工具」，或在工具箱手动创建',
        data: {'validation_passed': true},
      );
    }

    try {
      final scope = _resolveScope(meta);
      await _skillManager.createSkill(
        name: displayName,
        description: description,
        content: const JsonEncoder.withIndent('  ').convert(json),
        scope: scope,
        source: ToolSource.ai,
        siteId: scope == ToolScope.sitePrivate ? siteId : null,
        riskLevel: meta['risk_level']?.toString() ?? 'middle',
      );
      return McpRuntimeResult(
        success: true,
        message: 'Skill "$displayName" 已保存到工具库',
        data: {'skill_name': name, 'scope': scope.name},
      );
    } catch (e) {
      return McpRuntimeResult(
        success: false,
        message: '保存 Skill 失败',
        error: e.toString(),
      );
    }
  }

  /// 解析工具作用域：AI 标记 site_private 或 global_available=false 时为站点私有
  ToolScope _resolveScope(Map<String, dynamic> meta) {
    final scopeRaw = meta['scope']?.toString() ?? meta['global_available']?.toString();
    if (scopeRaw == 'site_private' || scopeRaw == 'site' || scopeRaw == 'false') {
      return ToolScope.sitePrivate;
    }
    return ToolScope.global;
  }

  /// 处理【MCP_CALL】—— 执行 MCP 工具
  Future<McpRuntimeResult> _handleMcpCall(ParsedInstruction inst) async {
    final name = inst.params?['name'] ?? '';
    if (name.isEmpty) {
      return McpRuntimeResult(
        success: false,
        message: 'MCP_CALL 缺少工具名称',
        error: '格式错误',
      );
    }

    final tool = _registry.get('mcp_$name') ?? _registry.get(name);
    if (tool == null) {
      return McpRuntimeResult(
        success: false,
        message: '未找到工具: $name',
        error: '工具不存在',
      );
    }

    // 站点私有工具越权拦截：仅归属站点会话可调用
    if (tool.scope == ToolScope.sitePrivate &&
        (siteId == null || siteId!.isEmpty || tool.siteId != siteId)) {
      return McpRuntimeResult(
        success: false,
        message: '工具 "$name" 为站点私有，当前会话无权调用',
        error: '无权限: 站点私有工具',
      );
    }

    // 构建调用参数
    final args = <String, dynamic>{};
    inst.params?.forEach((k, v) {
      if (k != 'name') args[k] = v;
    });

    final request = ToolCallRequest(toolId: tool.id, arguments: args);

    // 执行工具
    try {
      final result = await BuiltinTools.execute(request);
      return McpRuntimeResult(
        success: result.success,
        message: result.success ? result.content : '工具执行失败',
        error: result.error,
        data: {'result': result.content},
      );
    } catch (e) {
      return McpRuntimeResult(
        success: false,
        message: '工具执行异常',
        error: e.toString(),
      );
    }
  }

  /// 处理【SKILL_RUN】—— 启动 Skill 流水线
  Future<McpRuntimeResult> _handleSkillRun(ParsedInstruction inst) async {
    final skillId = inst.params?['skill_id'] ?? '';
    if (skillId.isEmpty) {
      return McpRuntimeResult(
        success: false,
        message: 'SKILL_RUN 缺少 skill_id',
        error: '格式错误',
      );
    }

    final skills = _skillManager.skills;
    final skill = skills.where((s) => s.id == skillId || s.name == skillId).firstOrNull;
    if (skill == null) {
      return McpRuntimeResult(
        success: false,
        message: '未找到 Skill: $skillId',
        error: 'Skill 不存在',
      );
    }

    if (skill.skillContent == null) {
      return McpRuntimeResult(
        success: false,
        message: 'Skill 内容为空',
        error: '无效的 Skill',
      );
    }

    // 解析 Skill JSON 获取步骤
    try {
      final skillJson = jsonDecode(skill.skillContent!) as Map<String, dynamic>;
      final steps = skillJson['steps'] as List? ?? [];

      final results = <String>[];
      for (final step in steps) {
        if (step is Map) {
          final stepId = step['step_id']?.toString() ?? '';
          final stepType = step['type']?.toString() ?? '';
          results.add('步骤 $stepId ($stepType): 已触发');
        }
      }

      return McpRuntimeResult(
        success: true,
        message: 'Skill "${skill.name}" 流水线已启动\n${results.join('\n')}',
        data: {'steps': results},
      );
    } catch (e) {
      return McpRuntimeResult(
        success: false,
        message: 'Skill 解析失败',
        error: e.toString(),
      );
    }
  }

  /// 处理【联网搜索】
  Future<McpRuntimeResult> _handleWebSearch(ParsedInstruction inst) async {
    final query = inst.queryText ?? '';
    if (query.isEmpty) {
      return McpRuntimeResult(
        success: false,
        message: '搜索关键词为空',
        error: '参数缺失',
      );
    }

    final request = ToolCallRequest(
      toolId: 'web_search',
      arguments: {'query': query, 'num': 5},
    );

    try {
      final result = await BuiltinTools.execute(request);
      return McpRuntimeResult(
        success: result.success,
        message: result.success ? '搜索完成' : '搜索失败',
        error: result.error,
        data: {'result': result.content},
      );
    } catch (e) {
      return McpRuntimeResult(
        success: false,
        message: '搜索异常',
        error: e.toString(),
      );
    }
  }

  /// 处理【网页抓取】
  Future<McpRuntimeResult> _handleWebFetch(ParsedInstruction inst) async {
    final url = inst.queryText ?? '';
    if (url.isEmpty) {
      return McpRuntimeResult(
        success: false,
        message: '抓取URL为空',
        error: '参数缺失',
      );
    }

    final request = ToolCallRequest(
      toolId: 'web_fetch',
      arguments: {'url': url, 'extract_mode': 'text'},
    );

    try {
      final result = await BuiltinTools.execute(request);
      return McpRuntimeResult(
        success: result.success,
        message: result.success ? '抓取完成' : '抓取失败',
        error: result.error,
        data: {'result': result.content},
      );
    } catch (e) {
      return McpRuntimeResult(
        success: false,
        message: '抓取异常',
        error: e.toString(),
      );
    }
  }

  /// 处理【文件路径】
  McpRuntimeResult _handleFilePath(ParsedInstruction inst) {
    final path = inst.queryText ?? '';
    if (path.isEmpty) {
      return McpRuntimeResult(
        success: false,
        message: '文件路径为空',
        error: '参数缺失',
      );
    }

    return McpRuntimeResult(
      success: true,
      message: '文件路径已识别: $path',
      data: {'file_path': path},
    );
  }

  /// 处理【调用工具】
  McpRuntimeResult _handleCallTool(ParsedInstruction inst) {
    final text = inst.queryText ?? '';
    // 解析格式: 工具名称 | 参数xxx 或 工具名称(参数)
    final parts = text.split(RegExp(r'[|(]'));
    final toolName = parts.isNotEmpty ? parts[0].trim() : '';

    return McpRuntimeResult(
      success: true,
      message: '工具调用请求: $toolName',
      data: {'tool_name': toolName, 'raw': text},
    );
  }
}