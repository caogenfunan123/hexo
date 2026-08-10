import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../core/ai/ai_model_entity.dart';
import '../core/ai/ai_model_manager.dart';
import '../core/ai/ai_provider.dart';
import '../core/ai/ai_session_manager.dart';
import '../models/ai_profile.dart';
import '../models/app_settings.dart';
import '../models/local_model_settings.dart';
import '../services/ai_service.dart';
import '../services/gguf_model_service.dart';
import '../services/storage_service.dart';
import '../core/ai/local_llama_provider.dart';
import 'token_usage_screen.dart';

/// 预置模型库
class _ModelPreset {
  final String modelId;
  final String modelName;
  final String baseUrl;
  final String group;
  const _ModelPreset(this.modelId, this.modelName, this.baseUrl, this.group);
}

const _presetModels = [
  _ModelPreset(
      'deepseek-chat', 'DeepSeek V3', 'https://api.deepseek.com/v1', 'code'),
  _ModelPreset('deepseek-reasoner', 'DeepSeek R1',
      'https://api.deepseek.com/v1', 'code'),
  _ModelPreset('qwen-max', '通义千问 Max',
      'https://dashscope.aliyuncs.com/compatible-mode/v1', 'general'),
  _ModelPreset('qwen-plus', '通义千问 Plus',
      'https://dashscope.aliyuncs.com/compatible-mode/v1', 'general'),
  _ModelPreset(
      'glm-4', '智谱 GLM-4', 'https://open.bigmodel.cn/api/paas/v4', 'general'),
  _ModelPreset('glm-4-flash', '智谱 GLM-4-Flash',
      'https://open.bigmodel.cn/api/paas/v4', 'general'),
  _ModelPreset(
      'moonshot-v1-8k', '月之暗面 Kimi', 'https://api.moonshot.cn/v1', 'general'),
  _ModelPreset('doubao-1-5-pro-32k-250115', '豆包 1.5 Pro',
      'https://ark.cn-beijing.volces.com/api/v3', 'longtext'),
  _ModelPreset(
      'gpt-4o-mini', 'GPT-4o-mini', 'https://api.openai.com/v1', 'general'),
  _ModelPreset('gpt-4o', 'GPT-4o', 'https://api.openai.com/v1', 'general'),
  _ModelPreset('claude-3-5-sonnet-20241022', 'Claude 3.5 Sonnet',
      'https://api.anthropic.com/v1', 'general'),
  _ModelPreset('gemini-2.0-flash', 'Gemini 2.0 Flash',
      'https://generativelanguage.googleapis.com/v1beta', 'general'),
];

class AiModelManagerScreen extends StatefulWidget {
  final AiModelManager modelManager;
  final AiService aiService;
  final AppSettings settings;
  final Future<void> Function(AppSettings) onSettingsChanged;
  final StorageService? storageService;

  const AiModelManagerScreen({
    super.key,
    required this.modelManager,
    required this.aiService,
    required this.settings,
    required this.onSettingsChanged,
    this.storageService,
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
        customModelsUrl: customUrlCtrl.text.trim().isEmpty
            ? null
            : customUrlCtrl.text.trim(),
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

      final useFallback = showFallback &&
          await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('拉取失败'),
                  content: Text('$errorMsg\n\n是否使用内置预设模型列表代替？'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('使用预设')),
                  ],
                ),
              ) ==
              true;

      if (useFallback) {
        modelIds = _presetModels.map((p) => p.modelId).toList();
        await _showModelSelectionDialog(
            apiBaseCtrl.text.trim(), apiKeyCtrl.text.trim(), group, modelIds);
      } else if (!showFallback) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(errorMsg)));
        }
      }
      return;
    }

    if (mounted) setState(() => _loading = false);
    if (mounted) {
      await _showModelSelectionDialog(
          apiBaseCtrl.text.trim(), apiKeyCtrl.text.trim(), group, modelIds);
    }
  }

  /// 展示模型选择列表（勾选 + 别名），选中后批量导入
  Future<void> _showModelSelectionDialog(String apiBase, String apiKey,
      String group, List<String> modelIds) async {
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
              : modelIds
                  .where((id) =>
                      id.toLowerCase().contains(searchQuery.toLowerCase()))
                  .toList();

          return AlertDialog(
            title: const Text('选择要导入的模型'),
            content: SizedBox(
              width: 450,
              height: 520,
              child: Column(
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
                        child: Text(
                            selected.length == filtered.length ? '取消全选' : '全选'),
                      ),
                      Text('${selected.length}/${modelIds.length} 个选中',
                          style: const TextStyle(fontSize: 12)),
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
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
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
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  if (selected.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('请至少选择一个模型')));
                    return;
                  }
                  Navigator.pop(ctx);
                  _importSelectedModels(
                      apiBase, apiKey, group, selected, aliases);
                },
                child: Text('导入 ${selected.length} 个'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _importSelectedModels(
      String apiBase,
      String apiKey,
      String group,
      Set<String> selected,
      Map<String, TextEditingController> aliases) async {
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
                  decoration: const InputDecoration(
                      labelText: '模型 ID', hintText: 'gpt-4o-mini'),
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
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('添加')),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final model = AiModelEntity(
      modelId: idCtrl.text.trim(),
      modelName: nameCtrl.text.trim().isEmpty
          ? idCtrl.text.trim()
          : nameCtrl.text.trim(),
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
                  const Text('选择模型：',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  ..._presetModels.map((p) => CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text('${p.modelName}（${p.modelId}）',
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(p.baseUrl,
                            style: const TextStyle(fontSize: 11)),
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
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
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
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('请填写 API Key')));
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
    await widget.modelManager
        .toggleModel(model.modelId, model.apiBase, !model.enable);
    await _loadModels();
  }

  Future<void> _deleteModel(AiModelEntity model) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模型'),
        content: Text('确认删除「${model.displayLabel}」？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
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

  Future<void> _importLocalGguf() async {
    final storage = widget.storageService;
    if (storage == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('本地模型导入暂不可用（缺少存储服务）')),
        );
      }
      return;
    }
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gguf'],
      allowMultiple: true,
    );
    if (res == null || res.files.isEmpty) return;
    try {
      final service = GgufModelService(storage, widget.modelManager);
      var count = 0;
      for (final f in res.files) {
        final path = f.path;
        if (path == null) continue;
        await service.importGguf(path);
        count++;
      }
      await _loadModels();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功导入 $count 个本地 GGUF 模型')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入本地模型失败: $e')),
        );
      }
    }
  }

  /// 打开「本地模型设置」完整界面：设备选择、上下文参数、采样参数、停止词。
  Future<void> _editLocalModelSettings(AiModelEntity model) async {
    final storage = widget.storageService;
    if (storage == null || model.provider != ModelProvider.local) return;
    final service = GgufModelService(storage, widget.modelManager);
    final initial = model.localSettings ??
        await service.getLocalSettings(model.modelId);
    var settings = initial;

    final ctrlContext = TextEditingController(
      text: settings.contextSize.toString(),
    );
    final ctrlThreads = TextEditingController(
      text: settings.threads > 0 ? settings.threads.toString() : '',
    );
    final ctrlGpuLayers = TextEditingController(
      text: settings.gpuLayers > 0 ? settings.gpuLayers.toString() : '',
    );
    final ctrlTemp = TextEditingController(
      text: settings.temperature.toStringAsFixed(2),
    );
    final ctrlTopK = TextEditingController(text: settings.topK.toString());
    final ctrlTopP = TextEditingController(
      text: settings.topP.toStringAsFixed(2),
    );
    final ctrlMinP = TextEditingController(
      text: settings.minP.toStringAsFixed(2),
    );
    final ctrlRepeat = TextEditingController(
      text: settings.repeatPenalty.toStringAsFixed(2),
    );
    final ctrlPresence = TextEditingController(
      text: settings.presencePenalty.toStringAsFixed(2),
    );
    final ctrlMaxTokens = TextEditingController(
      text: settings.maxTokens == -1
          ? ''
          : settings.maxTokens.toString(),
    );
    final ctrlStop = TextEditingController(
      text: settings.stopSequences.join('\n'),
    );
    final ctrlChatTemplate = TextEditingController(
      text: settings.chatTemplate ?? '',
    );

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          void update(LocalModelSettings next) {
            setSheetState(() => settings = next);
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.9,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (ctx, scrollController) => Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    '本地模型设置',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _settingsSection('设备与加速', [
                        _choiceTile<String>(
                          settings.device,
                          '推理设备',
                          const {
                            'auto': '自动（探测 GPU，无则回退 CPU）',
                            'cpu': '纯 CPU（最稳，最慢）',
                            'vulkan': 'Vulkan GPU（快，要求设备支持）',
                          },
                          (v) => update(settings.copyWith(device: v)),
                        ),
                        _numberField(
                          ctrlGpuLayers,
                          'GPU 层数',
                          '留空/0 = 自动全部层，填数字自定义（配合设备选择生效）',
                          onChanged: () {
                            final v = int.tryParse(ctrlGpuLayers.text.trim());
                            update(settings.copyWith(
                              gpuLayers: (v == null || v < 0) ? 0 : v,
                            ));
                          },
                        ),
                      ]),
                      _settingsSection('上下文与批处理', [
                        _numberField(
                          ctrlContext,
                          '上下文长度（n_ctx）',
                          '越大占内存越高，建议 2048-8192',
                          onChanged: () {
                            final v = int.tryParse(ctrlContext.text.trim());
                            update(settings.copyWith(
                              contextSize: (v == null || v < 512)
                                  ? 4096
                                  : v,
                            ));
                          },
                        ),
                        _choiceTile<String>(
                          settings.cacheTypeK,
                          'KV Cache K',
                          const {
                            'f16': 'FP16（默认，质量最高）',
                            'q8_0': '8-bit（省一半内存）',
                            'q4_0': '4-bit（最省内存）',
                          },
                          (v) => update(settings.copyWith(cacheTypeK: v)),
                        ),
                        _choiceTile<String>(
                          settings.cacheTypeV,
                          'KV Cache V',
                          const {
                            'f16': 'FP16（默认，质量最高）',
                            'q8_0': '8-bit（省一半内存）',
                            'q4_0': '4-bit（最省内存）',
                          },
                          (v) => update(settings.copyWith(cacheTypeV: v)),
                        ),
                        _choiceTile<String>(
                          settings.flashAttention,
                          'FlashAttention',
                          const {
                            'auto': '自动（推荐）',
                            'enabled': '启用',
                            'disabled': '禁用',
                          },
                          (v) => update(settings.copyWith(flashAttention: v)),
                        ),
                        _toggleTile(
                          '统一 KV Cache（kv_unified）',
                          settings.kvUnified,
                          '统一 K/V 缓存可显著节省内存；个别模型不支持',
                          (v) => update(settings.copyWith(kvUnified: v)),
                        ),
                        _toggleTile(
                          '内存映射（use_mmap）',
                          settings.useMmap,
                          '内存映射加载权重，降低启动内存峰值',
                          (v) => update(settings.copyWith(useMmap: v)),
                        ),
                        _toggleTile(
                          '锁定权重常驻（use_mlock）',
                          settings.useMlock,
                          '将模型权重锁定在内存中，避免被换出（占用更多内存）',
                          (v) => update(settings.copyWith(useMlock: v)),
                        ),
                        _numberField(
                          ctrlThreads,
                          '线程数',
                          '留空 = 自动（默认 4，过大反而变慢）',
                          onChanged: () {
                            final v = int.tryParse(ctrlThreads.text.trim());
                            update(settings.copyWith(
                              threads: (v == null || v < 1) ? 0 : v,
                            ));
                          },
                        ),
                      ]),
                      _settingsSection('采样参数', [
                        _numberField(
                          ctrlTemp,
                          'Temperature',
                          '0.0-2.0，越高越随机（默认 0.7）',
                          onChanged: () {
                            final v = double.tryParse(ctrlTemp.text.trim());
                            update(settings.copyWith(
                              temperature: (v == null || v < 0) ? 0.7 : v,
                            ));
                          },
                        ),
                        _numberField(
                          ctrlTopK,
                          'Top-K',
                          '只从概率最高的 K 个 token 中采样（默认 40）',
                          onChanged: () {
                            final v = int.tryParse(ctrlTopK.text.trim());
                            update(settings.copyWith(
                              topK: (v == null || v < 1) ? 40 : v,
                            ));
                          },
                        ),
                        _numberField(
                          ctrlTopP,
                          'Top-P',
                          '累积概率截断（0-1，默认 0.95）',
                          onChanged: () {
                            final v = double.tryParse(ctrlTopP.text.trim());
                            update(settings.copyWith(
                              topP: (v == null || v < 0) ? 0.95 : v,
                            ));
                          },
                        ),
                        _numberField(
                          ctrlMinP,
                          'Min-P',
                          '相对概率下限（0 关闭，默认 0.05）',
                          onChanged: () {
                            final v = double.tryParse(ctrlMinP.text.trim());
                            update(settings.copyWith(
                              minP: (v == null || v < 0) ? 0.05 : v,
                            ));
                          },
                        ),
                        _numberField(
                          ctrlRepeat,
                          '重复惩罚',
                          '1.0 = 不惩罚，越大越抑制重复（默认 1.0）',
                          onChanged: () {
                            final v = double.tryParse(ctrlRepeat.text.trim());
                            update(settings.copyWith(
                              repeatPenalty: (v == null || v < 1) ? 1.0 : v,
                            ));
                          },
                        ),
                        _numberField(
                          ctrlPresence,
                          'Presence 惩罚',
                          '对已出现 token 的加性惩罚（默认 0）',
                          onChanged: () {
                            final v =
                                double.tryParse(ctrlPresence.text.trim());
                            update(settings.copyWith(
                              presencePenalty: (v == null || v < 0) ? 0 : v,
                            ));
                          },
                        ),
                        _numberField(
                          ctrlMaxTokens,
                          '最大输出（n_predict）',
                          '留空 = 无限（直到结束符）',
                          onChanged: () {
                            final v = int.tryParse(ctrlMaxTokens.text.trim());
                            update(settings.copyWith(
                              maxTokens: v == null ? -1 : v,
                            ));
                          },
                        ),
                        _textField(
                          ctrlStop,
                          '停止词（每行一个）',
                          '生成到这些词时停止（默认 </s>）',
                          onChanged: () => update(settings.copyWith(
                            stopSequences: ctrlStop.text
                                .split('\n')
                                .map((e) => e.trim())
                                .where((e) => e.isNotEmpty)
                                .toList(),
                          )),
                        ),
                      ]),
                      _settingsSection('模型模板', [
                        _textField(
                          ctrlChatTemplate,
                          'Chat Template（可选）',
                          '覆盖模型内置模板，留空使用模型默认',
                          onChanged: () => update(settings.copyWith(
                            chatTemplate: ctrlChatTemplate.text.trim().isEmpty
                                ? null
                                : ctrlChatTemplate.text.trim(),
                          )),
                        ),
                      ]),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('保存'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    for (final c in [
      ctrlContext,
      ctrlThreads,
      ctrlGpuLayers,
      ctrlTemp,
      ctrlTopK,
      ctrlTopP,
      ctrlMinP,
      ctrlRepeat,
      ctrlPresence,
      ctrlMaxTokens,
      ctrlStop,
      ctrlChatTemplate,
    ]) {
      c.dispose();
    }

    if (result != true) return;
    try {
      await service.setLocalSettings(model.modelId, settings);
      await widget.modelManager.updateModel(model.copyWith(
        contextLimit: settings.effectiveContextSize,
        localSettings: settings,
      ));
      await _loadModels();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('本地模型设置已保存')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存本地模型设置失败: $e')),
        );
      }
    }
  }

  Widget _settingsSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }

  /// 单选分组（设备 / KV 类型 / flash attention）。
  Widget _choiceTile<T>(T value, String label,
      Map<T, String> options, void Function(T) onSelect) {
    return ListTile(
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: options.entries
              .map((e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(
                      e.value,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onSelect(v);
          },
          isExpanded: false,
        ),
      ),
    );
  }

  /// 数字输入项。
  Widget _numberField(
    TextEditingController ctrl,
    String label,
    String helper, {
    VoidCallback? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(
          signed: true,
          decimal: true,
        ),
        style: const TextStyle(fontSize: 14),
        onChanged: (_) => onChanged?.call(),
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  /// 多行文本输入项。
  Widget _textField(
    TextEditingController ctrl,
    String label,
    String helper, {
    VoidCallback? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: TextField(
        controller: ctrl,
        maxLines: 3,
        minLines: 1,
        style: const TextStyle(fontSize: 14),
        onChanged: (_) => onChanged?.call(),
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  /// 开关项。
  Widget _toggleTile(
    String title,
    bool value,
    String subtitle,
    void Function(bool) onChanged,
  ) {
    return SwitchListTile(
      dense: true,
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 11),
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  /// 本地模型设置摘要（上下文 + 设备 + KV 类型），用于列表展示。
  String _localSummary(AiModelEntity m) {
    final s = m.localSettings;
    if (s == null) {
      return '上下文 ${m.contextLimit > 0 ? m.contextLimit : 4096}';
    }
    final deviceLabel = switch (s.device) {
      'cpu' => 'CPU',
      'vulkan' => 'Vulkan',
      _ => '自动',
    };
    final kv = s.cacheTypeK == s.cacheTypeV ? s.cacheTypeK : 'K${s.cacheTypeK}/V${s.cacheTypeV}';
    return 'ctx ${s.effectiveContextSize} · $deviceLabel · KV $kv'
        '${s.flashAttention == 'enabled' ? ' · FA' : ''}'
        '${s.temperature != 0.7 ? ' · t=${s.temperature}' : ''}';
  }

  Future<void> _manageKeyPool(AiModelEntity model) async {    final ctrl = TextEditingController(
      text: [model.apiKey, ...model.keyPool].join('\n'),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('密钥池 · ${model.modelName}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('每行一个密钥，第一行为当前主密钥。'
                  '请求连续失败 3 次后自动轮换到下一个密钥。'),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                maxLines: 8,
                minLines: 4,
                decoration: const InputDecoration(
                  hintText: 'sk-...\nsk-...',
                  border: OutlineInputBorder(),
                ),
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
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final keys = ctrl.text
        .split('\n')
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .toList();
    try {
      await widget.modelManager.setKeyPool(model, keys);
      await _loadModels();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('密钥池已更新（共 ${keys.length} 个密钥）')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新密钥池失败: $e')),
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
          apiKey: model.effectiveKey,
          model: model.modelId,
          apiPath: model.apiPath,
          useBearer: model.useBearer,
          interfaceType: model.interfaceType,
          localModelPath:
              model.provider == ModelProvider.local ? model.apiBase : null,
          localContextSize:
              model.provider == ModelProvider.local && model.contextLimit > 0
                  ? model.contextLimit
                  : null,
          localSettings:
              model.provider == ModelProvider.local
                  ? model.localSettings
                  : null,
        ),
      );
      if (mounted) {
        String backendHint = '';
        if (model.provider == ModelProvider.local) {
          final llama = LocalLlamaProvider.instance;
          final name = llama.backendName;
          if (name != null && name.trim().isNotEmpty) {
            backendHint = ' · 后端: $name';
            final vram = llama.vram;
            if (vram != null && vram.total > 0) {
              backendHint +=
                  ' · 显存: ${(vram.free / (1024 * 1024)).toStringAsFixed(0)}MB';
            }
          } else {
            backendHint = ' · 后端信息暂不可用';
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${model.modelName} ✅ 连通正常$backendHint')),
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
              icon: const Icon(Icons.bar_chart),
              tooltip: 'Token 用量',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TokenUsageScreen()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.memory_outlined),
              tooltip: '导入本地 GGUF 模型',
              onPressed: _importLocalGguf,
            ),
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
                        FilledButton(
                            onPressed: _loadModels, child: const Text('重试')),
                      ],
                    ),
                  )
                : _models.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.psychology_outlined,
                                size: 64, color: cs.outline),
                            const SizedBox(height: 16),
                            Text('暂无模型',
                                style:
                                    TextStyle(color: cs.outline, fontSize: 16)),
                            const SizedBox(height: 8),
                            Text('点击右下角按钮添加模型或批量拉取',
                                style:
                                    TextStyle(color: cs.outline, fontSize: 13)),
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
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: m.enable
                                    ? cs.primaryContainer
                                    : cs.surfaceContainerHighest,
                                child: Icon(
                                  m.group == 'code'
                                      ? Icons.code
                                      : Icons.chat_outlined,
                                  size: 20,
                                  color: m.enable
                                      ? cs.onPrimaryContainer
                                      : cs.outline,
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
                                    style: TextStyle(
                                        fontSize: 12, color: cs.outline),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (m.hasKeyPool)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(top: 4),
                                      child: Row(
                                        children: [
                                          Icon(Icons.vpn_key_outlined,
                                              size: 12, color: cs.tertiary),
                                          const SizedBox(width: 2),
                                          Text(
                                            '密钥池 ${m.allKeys.where((k) => k.isNotEmpty).length} 个 · 当前第${m.keyPoolIndex + 1}个'
                                            '${m.consecutiveFailures > 0 ? ' · 连续失败${m.consecutiveFailures}次' : ''}',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: cs.tertiary),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (stat != null && stat.totalCalls > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Row(
                                        children: [
                                          Icon(Icons.speed,
                                              size: 12, color: cs.primary),
                                          const SizedBox(width: 2),
                                          Text(
                                            '${stat.avgLabel}  ',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: cs.primary),
                                          ),
                                          Icon(Icons.check_circle_outline,
                                              size: 12, color: Colors.green),
                                          const SizedBox(width: 2),
                                          Text(
                                            stat.successLabel,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.green),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${stat.totalCalls}次',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: cs.outline),
                                          ),
                                          if (stat.fastestMs > 0) ...[
                                            const SizedBox(width: 4),
                                            Text(
                                              '最快${stat.fastestMs}ms',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: cs.outline),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  if (m.provider == ModelProvider.local)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Row(
                                        children: [
                                          Icon(Icons.memory_outlined,
                                              size: 12, color: cs.secondary),
                                          const SizedBox(width: 2),
                                          Flexible(
                                            child: Text(
                                              _localSummary(m),
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: cs.secondary),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: cs.primaryContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      m.groupLabel,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: cs.onPrimaryContainer),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.vpn_key,
                                        size: 18, color: cs.tertiary),
                                    tooltip: '管理密钥池',
                                    onPressed: () => _manageKeyPool(m),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.wifi_find,
                                        size: 18, color: cs.primary),
                                    tooltip: '测试连通性',
                                    onPressed: () => _testModel(m),
                                  ),
                                  if (m.provider == ModelProvider.local)
                                    IconButton(
                                      icon: Icon(Icons.tune,
                                          size: 18, color: cs.secondary),
                                      tooltip: '本地模型设置',
                                      onPressed: () =>
                                          _editLocalModelSettings(m),
                                    ),
                                  Switch(
                                    value: m.enable,
                                    onChanged: (_) => _toggleModel(m),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline,
                                        size: 18, color: cs.error),
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
