// 编辑器 AI 功能扩展（由 main.dart part 引入，与原类同 library，可访问私有成员）
part of '../main.dart';

extension EditorAiExt on _RootShellState {
  Future<void> _aiAction(String action) async {
    _applyState(() {
      _editorBusy = true;
      _editorStatus = 'AI 处理中...';
    });
    try {
      String result;
      final text = _doc.contentCtrl.text;
      switch (action) {
        case 'polish':
          result = await aiService.polish(settings, text);
          _doc.contentCtrl.text = result;
          _onContentChanged();
          break;
        case 'continue':
          result = await aiService.continueWrite(settings, text);
          _insertText('\n\n$result');
          break;
        case 'summary':
          result = await aiService.summarize(settings, text);
          if (mounted)
            await showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('AI 摘要'),
                content: Text(result),
                actions: [
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: result));
                      Navigator.pop(context);
                    },
                    child: const Text('复制'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            );
          break;
        case 'outline':
          result = await aiService.generateOutline(
            settings,
            _doc.titleCtrl.text.isEmpty ? text : _doc.titleCtrl.text,
          );
          _doc.contentCtrl.text = result;
          _onContentChanged();
          break;
        case 'code':
          final ctrl = TextEditingController();
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('AI 生成代码'),
              content: TextField(
                controller: ctrl,
                maxLines: 5,
                decoration: const InputDecoration(hintText: '描述需要的代码'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('生成'),
                ),
              ],
            ),
          );
          if (ok != true) {
            ctrl.dispose();
            break;
          }
          result = await aiService.generateCode(
            settings,
            ctrl.text.trim().isEmpty ? '写一段示例代码' : ctrl.text.trim(),
          );
          ctrl.dispose();
          _insertText('\n\n$result\n');
          break;
        case 'rewrite':
          final sel = _doc.contentCtrl.selection;
          if (!sel.isValid || sel.start == sel.end) {
            throw Exception('请先选中要改写的文字');
          }
          final selected = text.substring(sel.start, sel.end);
          final instrCtrl = TextEditingController(text: '更简洁专业');
          final ok2 = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('AI 改写'),
              content: TextField(controller: instrCtrl),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('改写'),
                ),
              ],
            ),
          );
          if (ok2 != true) {
            instrCtrl.dispose();
            break;
          }
          result = await aiService.rewriteSelection(
            settings,
            selected,
            instrCtrl.text.trim(),
          );
          instrCtrl.dispose();
          final txt = _doc.contentCtrl.text;
          _doc.contentCtrl.value = TextEditingValue(
            text: txt.replaceRange(sel.start, sel.end, result),
            selection: TextSelection.collapsed(
              offset: sel.start + result.length,
            ),
          );
          _doc.contentFocus.requestFocus();
          _onContentChanged();
          break;
        case 'format':
          result = await aiService.polish(
            settings,
            '请对以下 Markdown 内容进行排版优化：统一标题层级、规范空行、修正列表缩进、对齐表格格式。\n\n$text',
          );
          _doc.contentCtrl.text = result;
          _onContentChanged();
          break;
      }
      if (mounted) _applyState(() => _editorStatus = 'AI 完成');
    } catch (e) {
      if (mounted) _showToast('AI 失败: $e');
    } finally {
      if (mounted) _applyState(() => _editorBusy = false);
    }
  }

  /// 移动端 AI 选区编辑：选中文本后弹出 AI 编辑工具栏
  void _showAiSelectionEdit() {
    final sel = _doc.contentCtrl.selection;
    if (!sel.isValid || sel.start == sel.end) {
      _showToast('请先选中要编辑的文本');
      return;
    }
    final selectedText = _doc.contentCtrl.text.substring(sel.start, sel.end);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AiSelectionEditMobile(
        selectedText: selectedText,
        aiService: aiService,
        settings: settings,
        onAccept: (acceptedText) {
          final txt = _doc.contentCtrl.text;
          _doc.contentCtrl.value = TextEditingValue(
            text: txt.replaceRange(sel.start, sel.end, acceptedText),
            selection: TextSelection.collapsed(
              offset: sel.start + acceptedText.length,
            ),
          );
          _doc.contentFocus.requestFocus();
          _onContentChanged();
        },
      ),
    );
  }

  Future<AiProfile?> _editAiProfile(AiProfile? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '中转站');
    final baseCtrl = TextEditingController(
      text: existing?.baseUrl.isNotEmpty == true
          ? existing!.baseUrl
          : (settings.aiBaseUrl.isNotEmpty
                ? settings.aiBaseUrl
                : 'https://api.openai.com/v1'),
    );
    final keyCtrl = TextEditingController(
      text: existing?.apiKey.isNotEmpty == true
          ? existing!.apiKey
          : settings.aiApiKey,
    );
    final modelCtrl = TextEditingController(
      text: existing?.model ?? settings.aiModel,
    );
    var models = List<String>.from(existing?.cachedModels ?? const <String>[]);
    var selectedModel = existing?.model ?? '';
    var fetching = false;
    var useBearer = existing?.useBearer ?? true;
    String? err;

    return showDialog<AiProfile>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            Future<void> fetchModels() async {
              setDlg(() {
                fetching = true;
                err = null;
              });
              try {
                final temp = AiProfile(
                  id: existing?.id ?? 'tmp',
                  name: nameCtrl.text.trim().isEmpty
                      ? '中转站'
                      : nameCtrl.text.trim(),
                  baseUrl: baseCtrl.text.trim(),
                  apiKey: keyCtrl.text.trim(),
                  model: modelCtrl.text.trim(),
                  useBearer: useBearer,
                  cachedModels: models,
                );
                final list = await AiService().listModels(
                  settings,
                  profile: temp,
                );
                setDlg(() {
                  models = list;
                  if (selectedModel.isEmpty && list.isNotEmpty) {
                    selectedModel = list.first;
                    modelCtrl.text = selectedModel;
                  } else if (selectedModel.isNotEmpty &&
                      list.contains(selectedModel)) {
                    modelCtrl.text = selectedModel;
                  }
                  fetching = false;
                });
                if (list.isEmpty) {
                  _showToast('未拉到模型，可手动填写模型名');
                } else {
                  _showToast('已获取 ${list.length} 个模型');
                }
              } catch (e) {
                setDlg(() {
                  fetching = false;
                  err = e.toString();
                });
              }
            }

            return AlertDialog(
              title: Text(existing == null ? '新增 AI 配置' : '编辑 AI 配置'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: '名称',
                          hintText: '如 DeepSeek / 硅基流动 / 自建中转',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: baseCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Base URL',
                          hintText: 'https://api.xxx.com/v1',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: keyCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'API Key',
                          hintText: 'sk-...',
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Bearer 鉴权'),
                        subtitle: const Text('关闭则同时发送 api-key / x-api-key'),
                        value: useBearer,
                        onChanged: (v) => setDlg(() => useBearer = v),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: modelCtrl,
                              decoration: const InputDecoration(
                                labelText: '模型',
                                hintText: '可手动填写或从列表选择',
                              ),
                              onChanged: (v) => selectedModel = v.trim(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            onPressed: fetching ? null : fetchModels,
                            child: fetching
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('获取模型'),
                          ),
                        ],
                      ),
                      if (err != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          err!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (models.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: models.contains(selectedModel)
                              ? selectedModel
                              : null,
                          decoration: const InputDecoration(
                            labelText: '从列表选择模型',
                          ),
                          items: models
                              .map(
                                (m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(
                                    m,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setDlg(() {
                              selectedModel = v;
                              modelCtrl.text = v;
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim().isEmpty
                        ? '中转站'
                        : nameCtrl.text.trim();
                    final base = baseCtrl.text.trim();
                    final key = keyCtrl.text.trim();
                    final model = modelCtrl.text.trim();
                    if (base.isEmpty) {
                      _showToast('请填写 Base URL');
                      return;
                    }
                    if (key.isEmpty) {
                      _showToast('请填写 API Key');
                      return;
                    }
                    if (model.isEmpty) {
                      _showToast('请选择或填写模型');
                      return;
                    }
                    final id =
                        existing?.id ??
                        'ai_${DateTime.now().millisecondsSinceEpoch}';
                    Navigator.pop(
                      ctx,
                      AiProfile(
                        id: id,
                        name: name,
                        baseUrl: base,
                        apiKey: key,
                        model: model,
                        useBearer: useBearer,
                        cachedModels: models,
                      ),
                    );
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAgentWorkbench() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AgentWorkbenchScreen(
          settings: settings,
          activeRepo: effectiveRepo,
          aiService: aiService,
          modelManager: aiModelManager,
          dispatcher: aiDispatcher,
          selfChecker: aiSelfChecker,
          onSettingsChanged: _updateSettings,
          gitHubService: github,
          storageService: storage,
        ),
      ),
    );
  }

  void _showAiArticleChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiArticleChatScreen(
          settings: settings,
          activeRepo: effectiveRepo,
          aiService: aiService,
          modelManager: aiModelManager,
          dispatcher: aiDispatcher,
          selfChecker: aiSelfChecker,
          isPage: false,
          onSettingsChanged: _updateSettings,
          gitHubService: github,
          storageService: storage,
        ),
      ),
    );
  }

  void _showAiPageChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiArticleChatScreen(
          settings: settings,
          activeRepo: effectiveRepo,
          aiService: aiService,
          modelManager: aiModelManager,
          dispatcher: aiDispatcher,
          selfChecker: aiSelfChecker,
          isPage: true,
          onSettingsChanged: _updateSettings,
          gitHubService: github,
          storageService: storage,
        ),
      ),
    );
  }

  /// 一键建站入口（AI 对话主模式）。
  /// 校验 AI 模型已配置；未配置提示跳转 AI 设置，已配置打开 AI 对话并预置建站意图。
  void _startAiSiteWizard() {
    if (settings.effectiveAiApiKey.isEmpty || settings.activeAiProfile == null) {
      _showToast('请先在 AI 设置中配置模型，再使用一键建站');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiArticleChatScreen(
          settings: settings,
          activeRepo: effectiveRepo,
          aiService: aiService,
          modelManager: aiModelManager,
          dispatcher: aiDispatcher,
          selfChecker: aiSelfChecker,
          isPage: false,
          onSettingsChanged: _updateSettings,
          gitHubService: github,
          storageService: storage,
          showWizardFallback: true,
          initialMessage: '你是一键建站助手。用户想要创建一个新的静态博客站点。\n\n'
              '请先向用户确认以下信息（信息不足时逐项追问，一次最多问 3 项）：\n'
              '1. 建站模式：模式一（GitHub Pages / GitLab Pages，仓库内 CI 自动构建）还是模式二（Cloudflare Pages）\n'
              '2. Git 托管平台：GitHub 或 GitLab\n'
              '3. Git 访问令牌（GitHub PAT 需含 repo+workflow scope；GitLab PAT 需含 api scope）\n'
              '4. 仓库名（同时作为站点项目名）\n'
              '5. 博客框架（hexo / hugo / jekyll / vuepress / gatsby / nextjs / astro / pelican / 11ty）\n'
              '6. 站点标题\n'
              '7. 仓库是否私有（默认私有；注意 GitHub 免费账号私有仓库无法启用 Pages）\n'
              '8. 是否生成欢迎文章（默认生成）\n\n'
              '用户确认全部信息后，调用 create_site 工具完成建站。若用户选择模式二，还需提供 Cloudflare API Token 与账号 ID。',
        ),
      ),
    );
  }

  void _showAiThemeChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiThemeChatScreen(
          settings: settings,
          activeRepo: effectiveRepo,
          aiService: aiService,
          modelManager: aiModelManager,
          dispatcher: aiDispatcher,
          selfChecker: aiSelfChecker,
          onSettingsChanged: _updateSettings,
          gitHubService: github,
          storageService: storage,
        ),
      ),
    );
  }

  void _showAiAudit() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiAuditScreen(
          settings: settings,
          activeRepo: effectiveRepo,
          aiService: aiService,
          modelManager: aiModelManager,
          dispatcher: aiDispatcher,
          selfChecker: aiSelfChecker,
          onSettingsChanged: _updateSettings,
          gitHubService: github,
          storageService: storage,
        ),
      ),
    );
  }

  void _showAiTemplateChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiTemplateChatScreen(
          settings: settings,
          activeRepo: effectiveRepo,
          aiService: aiService,
          modelManager: aiModelManager,
          dispatcher: aiDispatcher,
          selfChecker: aiSelfChecker,
          onSettingsChanged: _updateSettings,
          gitHubService: github,
          storageService: storage,
          onTemplatesChanged: (_) async {
            if (!mounted) return;
            final t = await storage.loadAllTemplates();
            _applyState(() => templates = t);
          },
        ),
      ),
    );
  }

}
