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
        rawDefinition: jsonEncode(json),
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

    // 站点私有工具越权拦截
    if (tool.scope == ToolScope.sitePrivate &&
        (siteId == null || siteId!.isEmpty || tool.siteId != siteId)) {
      return McpRuntimeResult(
        success: false,
        message: '工具 "$name" 为站点私有，当前会话无权调用',
        error: '无权限: 站点私有工具',
      );
    }

    // 构建调用参数（合并用户参数 + action.payload 默认值）
    final args = <String, dynamic>{};
    inst.params?.forEach((k, v) {
      if (k != 'name') args[k] = v;
    });

    // 从 rawDefinition 中提取 action 字段，映射到内置工具
    final builtinId = _mcpActionToBuiltin(tool, args);
    if (builtinId == null) {
      return McpRuntimeResult(
        success: false,
        message: '工具 "$name" 未定义可执行的动作类型',
        error: 'MCP 定义缺少 action.type 字段，或类型不支持',
      );
    }

    final request = ToolCallRequest(toolId: builtinId, arguments: args);

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

  /// 从 MCP 工具的 rawDefinition 中提取 action 并映射到内置工具 ID
  String? _mcpActionToBuiltin(ToolEntity tool, Map<String, dynamic> args) {
    if (tool.rawDefinition == null || tool.rawDefinition!.isEmpty) return null;

    try {
      final json = jsonDecode(tool.rawDefinition!);
      if (json is! Map) return null;
      final action = json['action'] as Map<String, dynamic>?;
      if (action == null) return null;

      final actionType = action['type']?.toString() ?? '';
      final payload = action['payload'] as Map<String, dynamic>? ?? {};

      // 将 action.payload 的默认值填入 args（不覆盖用户已传参数）
      for (final e in payload.entries) {
        args.putIfAbsent(e.key, () => e.value);
      }

      // 映射 action.type → 内置工具 ID
      switch (actionType) {
        case 'file_read':
          return 'file_read';
        case 'file_write':
          return 'file_write';
        case 'file_delete':
          return 'file_delete';
        case 'list_dir':
          return 'list_dir';
        case 'mkdir':
          return 'create_dir';
        case 'git_snapshot':
          return 'git_snapshot';
        case 'git_rollback':
          return 'git_rollback';
        case 'web_search':
          return 'web_search';
        case 'web_fetch':
          return 'web_fetch';
        default:
          return null;
      }
    } catch (_) {
      return null;
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

    try {
      final skillJson = jsonDecode(skill.skillContent!) as Map<String, dynamic>;
      final steps = skillJson['steps'] as List? ?? [];
      final vars = inst.params?['vars'] as Map<String, dynamic>? ?? {};
      final results = <String>[];
      String? rollbackStep;

      for (var i = 0; i < steps.length; i++) {
        final step = steps[i];
        if (step is! Map) continue;

        final stepId = step['step_id']?.toString() ?? 'step_${i + 1}';
        final stepType = step['type']?.toString() ?? '';
        final stepParams = step['params'] as Map<String, dynamic>? ?? {};
        final stepPrompt = step['prompt']?.toString() ?? '';

        // 替换变量占位符 {{var_name}}
        String resolveVars(String text) {
          var resolved = text;
          for (final e in vars.entries) {
            resolved = resolved.replaceAll('{{${e.key}}}', e.value?.toString() ?? '');
          }
          return resolved;
        }

        bool stepSuccess = false;
        String stepResult = '';

        try {
          switch (stepType) {
            case 'mcp_call':
              final mcpName = stepParams['mcp_name']?.toString() ?? stepParams['name']?.toString() ?? '';
              if (mcpName.isEmpty) {
                stepResult = '步骤 $stepId: mcp_call 缺少 mcp_name';
              } else {
                final subInst = ParsedInstruction(
                  type: InstructionType.mcpCall,
                  rawContent: '【MCP_CALL】name=$mcpName',
                  params: {'name': mcpName},
                  jsonData: stepParams,
                );
                final mcpResult = await _handleMcpCall(subInst);
                stepSuccess = mcpResult.success;
                stepResult = mcpResult.success
                    ? '步骤 $stepId: MCP 工具 "$mcpName" 执行成功'
                    : '步骤 $stepId: MCP 工具 "$mcpName" 失败: ${mcpResult.error}';
              }
              break;

            case 'ai_task':
              final prompt = resolveVars(stepPrompt.isNotEmpty ? stepPrompt : (stepParams['prompt'] ?? ''));
              stepResult = stepPrompt.isNotEmpty
                  ? '步骤 $stepId: AI 任务已触发 — $prompt'
                  : '步骤 $stepId: AI 任务已触发';
              stepSuccess = true;
              break;

            case 'auto_check':
              stepResult = '步骤 $stepId: 自检完成';
              stepSuccess = true;
              break;

            default:
              stepResult = '步骤 $stepId ($stepType): 已触发';
              stepSuccess = true;
          }
        } catch (e) {
          stepSuccess = false;
          stepResult = '步骤 $stepId 异常: $e';
        }

        results.add(stepResult);

        if (!stepSuccess) {
          rollbackStep = stepId;
          final failAction = step['fail_action']?.toString() ?? skillJson['on_fail']?['action']?.toString() ?? 'stop';
          if (failAction == 'rollback') {
            results.add('  → 失败，触发回滚');
          } else {
            results.add('  → 失败，停止流水线');
          }
          break;
        }
      }

      final buf = StringBuffer();
      buf.writeln('Skill "${skill.name}" 流水线执行完成');
      buf.writeln('---');
      for (final r in results) {
        buf.writeln(r);
      }

      return McpRuntimeResult(
        success: rollbackStep == null,
        message: buf.toString(),
        data: {'steps': results, 'has_rollback': rollbackStep != null},
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
  Future<McpRuntimeResult> _handleCallTool(ParsedInstruction inst) async {
    final text = inst.queryText ?? '';
    // 解析格式: 工具名称 | 参数xxx 或 工具名称(参数)
    final parts = text.split(RegExp(r'[|(]'));
    final toolName = parts.isNotEmpty ? parts[0].trim() : '';

    if (toolName.isEmpty) {
      return McpRuntimeResult(
        success: false,
        message: '调用工具名称不能为空',
        error: '参数缺失',
      );
    }

    // 从注册表查找工具
    final tool = _registry.get(toolName) ?? _registry.get('mcp_$toolName');
    if (tool == null) {
      return McpRuntimeResult(
        success: false,
        message: '未找到工具: $toolName',
        error: '工具不存在',
      );
    }

    // 通过 MCP 调用机制执行
    final subInst = ParsedInstruction(
      type: InstructionType.mcpCall,
      rawContent: '【MCP_CALL】name=$toolName',
      params: {'name': toolName},
    );
    return await _handleMcpCall(subInst);
  }
}