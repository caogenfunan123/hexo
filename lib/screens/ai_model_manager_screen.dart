import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/ai/ai_model_entity.dart';
import '../core/ai/ai_model_manager.dart';
import '../core/ai/ai_session_manager.dart';
import '../models/ai_profile.dart';
import '../models/app_settings.dart';
import '../services/ai_service.dart';

/// 预置模型库
class _ModelPreset {
  final String modelId;
  final String modelName;
  final String baseUrl;
  final String group;
  const _ModelPreset(this.modelId, this.modelName, this.baseUrl, this.group);
}

const _presetModels = [
  _ModelPreset('deepseek-chat', 'DeepSeek V3', 'https://api.deepseek.com/v1', 'code'),
  _ModelPreset('deepseek-reasoner', 'DeepSeek R1', 'https://api.deepseek.com/v1', 'code'),
  _ModelPreset('qwen-max', '通义千问 Max', 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'general'),
  _ModelPreset('qwen-plus', '通义千问 Plus', 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'general'),
  _ModelPreset('glm-4', '智谱 GLM-4', 'https://open.bigmodel.cn/api/paas/v4', 'general'),
  _ModelPreset('glm-4-flash', '智谱 GLM-4-Flash', 'https://open.bigmodel.cn/api/paas/v4', 'general'),
  _ModelPreset('moonshot-v1-8k', '月之暗面 Kimi', 'https://api.moonshot.cn/v1', 'general'),
  _ModelPreset('doubao-1-5-pro-32k-250115', '豆包 1.5 Pro', 'https://ark.cn-beijing.volces.com/api/v3', 'longtext'),
  _ModelPreset('gpt-4o-mini', 'GPT-4o-mini', 'https://api.openai.com/v1', 'general'),
  _ModelPreset('gpt-4o', 'GPT-4o', 'https://api.openai.com/v1', 'general'),
  _ModelPreset('claude-3-5-sonnet-20241022', 'Claude 3.5 Sonnet', 'https://api.anthropic.com/v1', 'general'),
  _ModelPreset('gemini-2.0-flash', 'Gemini 2.0 Flash', 'https://generativelanguage.googleapis.com/v1beta', 'general'),
];
class AiModelManagerScreen extends StatefulWidget {
  final AiModelManager modelManager;
  final AiService aiService;
  final AppSettings settings;
  final Future<void> Function(AppSettings) onSettingsChanged;

  const AiModelManagerScreen({
    super.key,
    required this.modelManager,
    required this.aiService,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  State<AiModelManagerScreen> createState() => _AiModelManagerScreenState();
}

class _AiModelManagerScreenState extends State<AiModelManagerScreen> {
  List<AiModelEntity> _models = [];
  Map<String, ModelStats> _stats = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _models = await widget.modelManager.loadAll();
      _stats = await widget.modelManager.loadStats();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetchFromProxy() async {
    final apiBaseCtrl = TextEditingController(
      text: widget.settings.aiBaseUrl,
    );
    final apiKeyCtrl = TextEditingController(
      text: widget.settings.aiApiKey,
    );
    final customUrlCtrl = TextEditingController();
    String group = 'general';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('从中转站拉取模型'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: apiBaseCtrl,
                  decoration: const InputDecoration(
                    labelText: '中转 API 地址',
                    hintText: 'https://ai-models.app.baizhi.cloud/api/openai',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: apiKeyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'API Token',
                    hintText: 'sk-...',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: customUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: '自定义模型列表地址（选填）',
                    hintText: '留空则使用标准 /v1/models',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: group,
                  decoration: const InputDecoration(labelText: '模型分组'),
                  items: const [
                    DropdownMenuItem(value: 'general', child: Text('通用对话')),
                    DropdownMenuItem(value: 'code', child: Text('代码优选')),
                    DropdownMenuItem(value: 'longtext', child: Text('长文本')),
                  ],
                  onChanged: (v) => setDlg(() => group = v ?? 'general'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('拉取列表'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    List<String> modelIds;
    try {
      modelIds = await widget.aiService.listModels(
        widget.settings,
        profile: AiProfile(
          id: 'temp',
          name: '临时',
          baseUrl: apiBaseCtrl.text.trim(),
          apiKey: apiKeyCtrl.text.trim(),
          model: '',
        ),
        customModelsUrl: customUrlCtrl.text.trim().isEmpty ? null : customUrlCtrl.text.trim(),
      );
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;

      // 根据错误类型显示不同提示
      String errorMsg;
      bool showFallback = true;
      if (e is FetchModelException) {
        switch (e.error) {
          case FetchModelError.emptyList:
            errorMsg = '密钥未开通可用模型，请检查账号额度';
            break;
          case FetchModelError.notImplemented:
            errorMsg = '该服务商未实现标准模型列表接口\n你可填写上方「自定义模型列表地址」重试，或使用内置预设';
            break;
          case FetchModelError.tokenInvalid:
            errorMsg = 'API Token 鉴权失败，请核对密钥';
            showFallback = false;
            break;
          case FetchModelError.forbidden:
            errorMsg = '该密钥被禁止访问模型列表接口';
            break;
          case FetchModelError.timeout:
            errorMsg = '网络超时，请检查网络与 API 地址';
            break;
          case FetchModelError.unknown:
            errorMsg = e.message;
            break;
        }
      } else {
        errorMsg = e.toString();
      }

      final useFallback = showFallback && await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('拉取失败'),
          content: Text('$errorMsg\n\n是否使用内置预设模型列表代替？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('使用预设')),
          ],
        ),
      ) == true;

      if (useFallback) {
        modelIds = _presetModels.map((p) => p.modelId).toList();
        await _showModelSelectionDialog(apiBaseCtrl.text.trim(), apiKeyCtrl.text.trim(), group, modelIds);
      } else if (!showFallback) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg)));
        }
      }
      return;
    }

    if (mounted) setState(() => _loading = false);
    if (mounted) {
      await _showModelSelectionDialog(apiBaseCtrl.text.trim(), apiKeyCtrl.text.trim(), group, modelIds);
    }
  }

  /// 展示模型选择列表（勾选 + 别名），选中后批量导入
  Future<void> _showModelSelectionDialog(String apiBase, String apiKey, String group, List<String> modelIds) async {
    final selected = Set<String>.from(modelIds);
    final aliases = <String, TextEditingController>{};
    final searchCtrl = TextEditingController();
    var searchQuery = '';

    for (final id in modelIds) {
      aliases[id] = TextEditingController();
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final filtered = searchQuery.isEmpty
              ? modelIds
              : modelIds.where((id) => id.toLowerCase().contains(searchQuery.toLowerCase())).toList();

          return AlertDialog(
            title: const Text('选择要导入的模型'),
            content: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: searchCtrl,
                    decoration: const InputDecoration(
                      hintText: '搜索模型...',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (v) => setDlg(() => searchQuery = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => setDlg(() {
                          if (selected.length == filtered.length) {
                            selected.clear();
                          } else {
                            selected.addAll(filtered);
                          }
                        }),
                        child: Text(selected.length == filtered.length ? '取消全选' : '全选'),
                      ),
                      Text('${selected.length}/${modelIds.length} 个选中', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final id = filtered[i];
                        final aliasCtrl = aliases[id]!;
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: selected.contains(id),
                          onChanged: (v) => setDlg(() {
                            if (v == true) {
                              selected.add(id);
                            } else {
                              selected.remove(id);
                            }
                          }),
                          title: Text(id, style: const TextStyle(fontSize: 13)),
                          subtitle: SizedBox(
                            height: 32,
                            child: TextField(
                              controller: aliasCtrl,
                              decoration: const InputDecoration(
                                hintText: '别名（可选）',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                border: OutlineInputBorder(),
                              ),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  if (selected.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('请至少选择一个模型')));
                    return;
                  }
                  Navigator.pop(ctx);
                  _importSelectedModels(apiBase, apiKey, group, selected, aliases);
                },
                child: Text('导入 ${selected.length} 个'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _importSelectedModels(String apiBase, String apiKey, String group, Set<String> selected, Map<String, TextEditingController> aliases) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final models = selected.map((id) {
        final alias = aliases[id]?.text.trim() ?? '';
        return AiModelEntity(
          modelId: id,
          modelName: alias.isNotEmpty ? alias : id,
          apiBase: apiBase,
          apiKey: apiKey,
          group: group,
          enable: true,
          priority: 0,
        );
      }).toList();

      await widget.modelManager.batchImport(models);
      await _loadModels();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功导入 ${models.length} 个模型')),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addModel() async {
    final idCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final baseCtrl = TextEditingController(text: widget.settings.aiBaseUrl);
    final keyCtrl = TextEditingController(text: widget.settings.aiApiKey);
    String group = 'general';
    int timeout = 50;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('添加模型'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '显示名称'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: idCtrl,
                  decoration: const InputDecoration(labelText: '模型 ID', hintText: 'gpt-4o-mini'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: baseCtrl,
                  decoration: const InputDecoration(labelText: 'API Base URL'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: keyCtrl,
                  decoration: const InputDecoration(labelText: 'API Key'),
                  obscureText: true,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: group,
                  decoration: const InputDecoration(labelText: '分组'),
                  items: const [
                    DropdownMenuItem(value: 'general', child: Text('📝 通用对话')),
                    DropdownMenuItem(value: 'code', child: Text('🧑‍💻 代码优选')),
                    DropdownMenuItem(value: 'longtext', child: Text('📄 长文本')),
                  ],
                  onChanged: (v) => setDlg(() => group = v ?? 'general'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('添加')),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final model = AiModelEntity(
      modelId: idCtrl.text.trim(),
      modelName: nameCtrl.text.trim().isEmpty ? idCtrl.text.trim() : nameCtrl.text.trim(),
      apiBase: baseCtrl.text.trim(),
      apiKey: keyCtrl.text.trim(),
      group: group,
      timeoutSecond: timeout,
    );

    await widget.modelManager.addModel(model);
    await _loadModels();
  }

  /// 一键导入常用模型
  Future<void> _addPresetModels() async {
    final apiKeyCtrl = TextEditingController();
    final baseCtrl = TextEditingController();
    final selected = Set<String>.from(_presetModels.map((p) => p.modelId));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('一键添加常用模型'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('选择要添加的模型，输入 API Key 后批量导入：',
                      style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: apiKeyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'API Key',
                      hintText: '所有选中模型共用此 Key',
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: baseCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Base URL 覆盖（可选）',
                      hintText: '留空则使用各模型默认 Base URL',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('选择模型：', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  ..._presetModels.map((p) => CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text('${p.modelName}（${p.modelId}）',
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(p.baseUrl, style: const TextStyle(fontSize: 11)),
                        value: selected.contains(p.modelId),
                        onChanged: (v) {
                          setDlg(() {
                            if (v == true) {
                              selected.add(p.modelId);
                            } else {
                              selected.remove(p.modelId);
                            }
                          });
                        },
                      )),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('导入 ${selected.length} 个'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final key = apiKeyCtrl.text.trim();
    if (key.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写 API Key')));
      return;
    }

    final overrideBase = baseCtrl.text.trim();
    final models = _presetModels
        .where((p) => selected.contains(p.modelId))
        .map((p) => AiModelEntity(
              modelId: p.modelId,
              modelName: p.modelName,
              apiBase: overrideBase.isNotEmpty ? overrideBase : p.baseUrl,
              apiKey: key,
              group: p.group,
              enable: true,
            ))
        .toList();

    await widget.modelManager.batchImport(models);
    await _loadModels();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功导入 ${models.length} 个模型')),
      );
    }
  }

  Future<void> _toggleModel(AiModelEntity model) async {
    await widget.modelManager.toggleModel(model.modelId, model.apiBase, !model.enable);
    await _loadModels();
  }

  Future<void> _deleteModel(AiModelEntity model) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模型'),
        content: Text('确认删除「${model.displayLabel}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await widget.modelManager.deleteModel(model.modelId, model.apiBase);
    await _loadModels();
  }

  Future<void> _exportModels() async {
    final json = widget.modelManager.exportToJson(_models);
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('模型配置已复制到剪贴板')),
      );
    }
  }

  Future<void> _importModels() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('剪贴板为空')),
        );
      }
      return;
    }

    try {
      final imported = widget.modelManager.importFromJson(data.text!);
      if (imported.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未解析到有效模型配置')),
          );
        }
        return;
      }
      await widget.modelManager.batchImport(imported);
      await _loadModels();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功导入 ${imported.length} 个模型')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  Future<void> _testModel(AiModelEntity model) async {
    setState(() => _loading = true);
    try {
      await widget.aiService.complete(
        settings: widget.settings,
        systemPrompt: AiSessionManager.modelTestPrompt,
        userPrompt: '回复 OK',
        profile: AiProfile(
          id: model.modelId,
          name: model.modelName,
          baseUrl: model.apiBase,
          apiKey: model.apiKey,
          model: model.modelId,
          apiPath: model.apiPath,
          useBearer: model.useBearer,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${model.modelName} ✅ 连通正常')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${model.modelName} ❌ 失败: $e')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: true,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('AI 模型管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: '导入',
            onPressed: _importModels,
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: '导出',
            onPressed: _exportModels,
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'presets',
            onPressed: _addPresetModels,
            tooltip: '一键添加常用模型',
            child: const Icon(Icons.library_books_outlined),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'fetch',
            onPressed: _fetchFromProxy,
            tooltip: '批量拉取',
            child: const Icon(Icons.cloud_download_outlined),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'add',
            onPressed: _addModel,
            tooltip: '添加模型',
            child: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: cs.error),
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: cs.error)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _loadModels, child: const Text('重试')),
                    ],
                  ),
                )
              : _models.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.psychology_outlined, size: 64, color: cs.outline),
                          const SizedBox(height: 16),
                          Text('暂无模型', style: TextStyle(color: cs.outline, fontSize: 16)),
                          const SizedBox(height: 8),
                          Text('点击右下角按钮添加模型或批量拉取',
                              style: TextStyle(color: cs.outline, fontSize: 13)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 100),
                      itemCount: _models.length,
                      itemBuilder: (ctx, i) {
                        final m = _models[i];
                        final statKey = '${m.apiBase}|${m.modelId}';
                        final stat = _stats[statKey];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: m.enable
                                  ? cs.primaryContainer
                                  : cs.surfaceContainerHighest,
                              child: Icon(
                                m.group == 'code' ? Icons.code : Icons.chat_outlined,
                                size: 20,
                                color: m.enable ? cs.onPrimaryContainer : cs.outline,
                              ),
                            ),
                            title: Text(
                              m.modelName,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: m.enable ? null : cs.outline,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.modelId,
                                  style: TextStyle(fontSize: 12, color: cs.outline),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (stat != null && stat.totalCalls > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        Icon(Icons.speed, size: 12, color: cs.primary),
                                        const SizedBox(width: 2),
                                        Text(
                                          '${stat.avgLabel}  ',
                                          style: TextStyle(fontSize: 11, color: cs.primary),
                                        ),
                                        Icon(Icons.check_circle_outline, size: 12, color: Colors.green),
                                        const SizedBox(width: 2),
                                        Text(
                                          stat.successLabel,
                                          style: const TextStyle(fontSize: 11, color: Colors.green),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${stat.totalCalls}次',
                                          style: TextStyle(fontSize: 11, color: cs.outline),
                                        ),
                                        if (stat.fastestMs > 0) ...[
                                          const SizedBox(width: 4),
                                          Text(
                                            '最快${stat.fastestMs}ms',
                                            style: TextStyle(fontSize: 11, color: cs.outline),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: cs.primaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    m.groupLabel,
                                    style: TextStyle(fontSize: 10, color: cs.onPrimaryContainer),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.wifi_find, size: 18, color: cs.primary),
                                  tooltip: '测试连通性',
                                  onPressed: () => _testModel(m),
                                ),
                                Switch(
                                  value: m.enable,
                                  onChanged: (_) => _toggleModel(m),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
                                  onPressed: () => _deleteModel(m),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
      ),
    );
  }
}