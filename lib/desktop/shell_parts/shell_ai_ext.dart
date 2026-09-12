// AI 功能扩展（desktop_shell.dart 的 part，与主类同 library，可访问私有成员）。
// 由 desktop_shell.dart 拆分而来（修复1），方法体保持零变更；
// setState 经宿主 _applyState 包装调用。
part of '../desktop_shell.dart';

extension DesktopShellAiExt on DesktopShellState {
  Future<void> _aiAction(String action) async {
    _editor.setEditorBusy(true);
    _editor.setEditorStatus('AI 处理中...');
    try {
      final text = _doc.contentCtrl.text;
      switch (action) {
        case 'polish':
          final result = await aiService.polish(settings, text);
          _doc.contentCtrl.text = result;
          _onContentChanged();
          break;
        case 'continue':
          final result = await aiService.continueWrite(settings, text);
          _insertText('\n\n$result');
          break;
        case 'summary':
          final result = await aiService.summarize(settings, text);
          if (mounted) {
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
          }
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
          final result = await aiService.generateCode(
            settings,
            ctrl.text.trim().isEmpty ? '生成一段实用的代码片段' : ctrl.text.trim(),
          );
          ctrl.dispose();
          _insertText('\n\n$result');
          break;
        case 'rewrite':
          final sel = _doc.contentCtrl.selection;
          if (!sel.isValid || sel.start == sel.end) {
            _editor.setEditorStatus('请先选中要改写的文本');
            break;
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
          final result2 = await aiService.rewriteSelection(
            settings,
            selected,
            instrCtrl.text.trim(),
          );
          instrCtrl.dispose();
          final txt = _doc.contentCtrl.text;
          _doc.contentCtrl.value = TextEditingValue(
            text: txt.replaceRange(sel.start, sel.end, result2),
            selection: TextSelection.collapsed(
              offset: sel.start + result2.length,
            ),
          );
          _doc.contentFocus.requestFocus();
          _onContentChanged();
          break;
        case 'format':
          final result3 = await aiService.polish(
            settings,
            '请对以下 Markdown 内容进行排版优化：统一标题层级、规范空行、修正列表缩进、对齐表格格式。\n\n$text',
          );
          _doc.contentCtrl.text = result3;
          _onContentChanged();
          break;
        case 'outline':
          final result = await aiService.generateOutline(settings, text);
          _insertText('\n$result');
          break;
        default:
          _editor.setEditorStatus('未知操作: $action');
          debugPrint('_aiAction: unknown action "$action"');
          break;
      }
      _editor.setEditorStatus('AI 完成');
    } catch (e) {
      _editor.setEditorStatus('AI 失败');
      if (mounted) _showToast('AI 处理失败: $e');
    } finally {
      if (mounted) _editor.setEditorBusy(false);
    }
  }

  void _openAiPromptTemplates() {
    showDialog(
      context: context,
      builder: (ctx) => AiPromptTemplatesScreen(
        onUseTemplate: (promptContent) {
          Navigator.pop(ctx);
          // 将模板内容插入 AI 聊天面板（等待面板挂载，避免动画期间消息丢失）
          _openRightDrawer(RightDrawerTab.aiChat);
          _sendToAiChatWhenReady(promptContent);
        },
      ),
    );
  }

  void _sendSelectionToAi() {
    final selection = _doc.contentCtrl.selection;
    if (!selection.isValid || selection.start == selection.end) {
      _showToast('请先选中一段文字');
      return;
    }
    final selectedText = selection.textInside(_doc.contentCtrl.text);
    if (selectedText.isEmpty) {
      _showToast('选中的文字为空');
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AiSelectionEditDialog(
        selectedText: selectedText,
        aiService: aiService,
        settings: settings,
        onAccept: (acceptedText) {
          // 将选中的原文替换为 AI 处理后的结果
          final fullText = _doc.contentCtrl.text;
          final start = selection.start;
          final end = selection.end;
          final newText =
              fullText.substring(0, start) +
              acceptedText +
              fullText.substring(end);
          _doc.contentCtrl.text = newText;
          _onContentChanged();
          _doc.markUnsaved();
          _editor.setEditorStatus('已接受AI选区编辑');
          _showToast('已应用AI选区编辑');
        },
      ),
    );
  }

  void _sendFullToAi() {
    final text = _doc.contentCtrl.text;
    if (text.trim().isEmpty) {
      _showToast('文章内容为空');
      return;
    }
    _openRightDrawer(RightDrawerTab.aiChat);
    _sendToAiChatWhenReady('请对以下文章进行润色优化：\n\n$text');
    _showToast('已发送全文到 AI');
  }

  void _sendToAiChatWhenReady(String message, {int maxAttempts = 20}) {
    var attempts = 0;
    void trySend() {
      attempts++;
      final state = _aiChatKey.currentState;
      if (state != null) {
        state.sendMessage(message);
        return;
      }
      if (attempts < maxAttempts) {
        Future.delayed(const Duration(milliseconds: 50), trySend);
      }
    }

    trySend();
  }

  void _showAiDiffPreview() {
    final original = _doc.contentCtrl.text;
    // 从 AI 聊天面板获取最新的 AI 回复
    final aiMessages = _aiChatKey.currentState?.messages ?? [];
    ChatMessage? lastAi;
    for (final m in aiMessages.reversed) {
      if (m.role == 'assistant') {
        lastAi = m;
        break;
      }
    }
    final lastAiResponse = lastAi?.content ?? '';

    if (lastAiResponse.isEmpty) {
      _showToast('暂无 AI 回复内容，请先在 AI 面板中发起对话');
      return;
    }

    final modified = lastAiResponse;
    final diffLines = _computeDiff(original, modified);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.compare_arrows, size: 22),
              SizedBox(width: 8),
              Text('AI 修改对比', style: TextStyle(fontSize: 17)),
            ],
          ),
          content: SizedBox(
            width: 800,
            height: 500,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildDiffLegend(),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.done_all, size: 16),
                      label: const Text('全部接受'),
                      onPressed: () {
                        _doc.contentCtrl.text = modified;
                        _onContentChanged();
                        _doc.markUnsaved();
                        _editor.setEditorStatus('已接受AI修改');
                        Navigator.pop(ctx);
                        _showToast('已全部接受AI修改');
                      },
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('全部拒绝'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showToast('已拒绝AI修改');
                      },
                    ),
                  ],
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: diffLines.length,
                    itemBuilder: (_, i) {
                      final line = diffLines[i];
                      Color bgColor;
                      Color textColor;
                      IconData? icon;
                      switch (line.type) {
                        case _DiffType.added:
                          bgColor = Colors.green.withOpacity(0.1);
                          textColor = Colors.green.shade700;
                          icon = Icons.add;
                          break;
                        case _DiffType.removed:
                          bgColor = Colors.red.withOpacity(0.1);
                          textColor = Colors.red.shade700;
                          icon = Icons.remove;
                          break;
                        default:
                          bgColor = Colors.transparent;
                          textColor = Colors.grey.shade700;
                          icon = null;
                      }
                      return Container(
                        color: bgColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (icon != null)
                              Icon(icon, size: 14, color: textColor),
                            if (icon != null) const SizedBox(width: 4),
                            Text(
                              '${line.lineNum.toString().padLeft(3)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                line.text.isEmpty ? ' ' : line.text,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  color: textColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('关闭'),
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('接受修改'),
                        onPressed: () {
                          _doc.contentCtrl.text = modified;
                          _onContentChanged();
                          _doc.markUnsaved();
                          _editor.setEditorStatus('已接受AI修改');
                          Navigator.pop(ctx);
                          _showToast('已接受AI修改，请保存');
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiffLegend() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        const Text('新增', style: TextStyle(fontSize: 11)),
        const SizedBox(width: 12),
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        const Text('删除', style: TextStyle(fontSize: 11)),
        const SizedBox(width: 12),
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.2),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        const Text('不变', style: TextStyle(fontSize: 11)),
      ],
    );
  }

  Future<void> _showAiManager() async {
    final baseUrlCtrl = TextEditingController();
    final apiKeyCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final profiles = List<AiProfile>.from(settings.aiProfiles);
            return AlertDialog(
              title: Row(
                children: [
                  const Expanded(
                    child: Text('AI 中转站配置', style: TextStyle(fontSize: 17)),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      final baseUrl = baseUrlCtrl.text.trim();
                      final apiKey = apiKeyCtrl.text.trim();
                      final model = modelCtrl.text.trim();
                      if (name.isEmpty || baseUrl.isEmpty || apiKey.isEmpty) {
                        _showToast('名称、Base URL 和 API Key 不能为空');
                        return;
                      }
                      final profile = AiProfile(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        name: name,
                        baseUrl: baseUrl,
                        apiKey: apiKey,
                        model: model,
                      );
                      profiles.add(profile);
                      await _updateSettings(
                        settings.copyWith(
                          ai: settings.ai.copyWith(
                            aiProfiles: profiles,
                            activeAiProfileId: profile.id,
                            aiBaseUrl: baseUrl,
                            aiApiKey: apiKey,
                            aiModel: model,
                            aiProvider: name,
                          ),
                        ),
                      );
                      nameCtrl.clear();
                      baseUrlCtrl.clear();
                      apiKeyCtrl.clear();
                      modelCtrl.clear();
                      setDialogState(() {});
                      _showToast('已保存 AI 配置: $name');
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('新增'),
                  ),
                ],
              ),
              content: SizedBox(
                width: 550,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (profiles.isNotEmpty) ...[
                      SizedBox(
                        height: 160,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: profiles.length,
                          itemBuilder: (_, i) {
                            final p = profiles[i];
                            final isActive = settings.activeAiProfileId == p.id;
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                isActive
                                    ? Icons.check_circle
                                    : Icons.smart_toy_outlined,
                                size: 18,
                                color: isActive
                                    ? Theme.of(ctx).colorScheme.primary
                                    : null,
                              ),
                              title: Text(
                                p.displayLabel,
                                style: const TextStyle(fontSize: 13),
                              ),
                              subtitle: Text(
                                '${p.baseUrl}\n模型: ${p.model.isEmpty ? "未选" : p.model}',
                                style: const TextStyle(fontSize: 11),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!isActive)
                                    TextButton(
                                      onPressed: () async {
                                        await _updateSettings(
                                          settings.copyWith(
                                            ai: settings.ai.copyWith(
                                              activeAiProfileId: p.id,
                                              aiBaseUrl: p.baseUrl,
                                              aiApiKey: p.apiKey,
                                              aiModel: p.model,
                                              aiProvider: p.name,
                                            ),
                                          ),
                                        );
                                        setDialogState(() {});
                                      },
                                      child: const Text(
                                        '启用',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 16,
                                      color: Colors.redAccent,
                                    ),
                                    onPressed: () async {
                                      profiles.removeAt(i);
                                      await _updateSettings(
                                        settings.copyWith(
                                          ai: settings.ai.copyWith(
                                            aiProfiles: profiles,
                                          ),
                                        ),
                                      );
                                      setDialogState(() {});
                                    },
                                    constraints: const BoxConstraints(),
                                    padding: EdgeInsets.zero,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const Divider(),
                    ],
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '配置名称',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: baseUrlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Base URL',
                        hintText: 'https://api.openai.com/v1',
                        isDense: true,
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: apiKeyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'API Key',
                        isDense: true,
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: modelCtrl,
                      decoration: const InputDecoration(
                        labelText: '模型名称（可选）',
                        hintText: 'gpt-4o',
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      baseUrlCtrl.dispose();
      apiKeyCtrl.dispose();
      modelCtrl.dispose();
      nameCtrl.dispose();
    }
  }

  void _showAgentWorkbench() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AgentWorkbenchScreen(
          settings: settings,
          activeRepo: effectiveRepo,
          repos: repos,
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

  Future<void> _showAiTemplateChat() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AgentWorkbenchScreen(
          settings: settings,
          activeRepo: effectiveRepo,
          repos: repos,
          aiService: aiService,
          modelManager: aiModelManager,
          dispatcher: aiDispatcher,
          selfChecker: aiSelfChecker,
          onSettingsChanged: _updateSettings,
          gitHubService: github,
          storageService: storage,
          initialTaskType: AgentTaskType.template,
        ),
      ),
    );
    if (!mounted) return;
    final t = await storage.loadAllTemplates();
    if (mounted) {
      _applyState(() => templates = t);
    }
  }

  void _showThemeStore() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThemeStoreScreen(
          repos: repos,
          onToast: _showToast,
          aiService: aiService,
          githubService: github,
          modelManager: aiModelManager,
          dispatcher: aiDispatcher,
          migrationService: themeMigrationService,
          selfChecker: aiSelfChecker,
          settings: settings,
          storageService: storage,
          snapshotService: versionSnapshotService,
          onSettingsChanged: _updateSettings,
        ),
      ),
    );
  }

  Future<void> _startAiSiteWizard() async {
    // 兼容两套模型配置体系：settings profile 或中转站模型（modelManager）任一可用即可。
    // 中转站模型已配置但 settings.activeAiProfile 为空时不应拦截。
    final hasModel =
        settings.ai.hasModelConfig || await aiModelManager.hasEnabledModels;
    if (!hasModel) {
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
          fallbackRepos: repos,
          onFallbackReposChanged: _updateRepos,
          initialMessage:
              '你是一键建站助手。用户想要创建一个新的静态博客站点。\n\n'
              '【自主原则】你有能力独立完成整个建站并修复任何错误，不要频繁向用户提问或让用户动手。'
              '只有遇到真正无法自行决定的冲突（如用户必须提供 Token / 明确二选一）才提问。'
              '你能调用 create_site / create_repo / write_welcome_post / poll_site_build / '
              'trigger_cf_deploy / register_site / verify_site / file_write / web_search 等全部工具，'
              '遇到缺失工具或缺失能力时，用 file_write 修改仓库文件、配置、CI 流水线来"创造"所需能力。\n\n'
              '若用户尚未配置 AI 模型，先引导其在 AI 设置中添加模型（填写 Base URL + API Key → 获取模型 → 保存），否则建站助手无法运行。\n\n'
              '收集信息（信息不足时逐项追问，一次最多问 3 项）：\n'
              '1. 建站模式：模式一（GitHub Pages / GitLab Pages，仓库内 CI 自动构建）还是模式二（Cloudflare Pages）\n'
              '2. Git 托管平台：GitHub 或 GitLab\n'
              '3. Git 访问令牌。获取方式：GitHub 访问 https://github.com/settings/tokens 生成 PAT（需勾选 repo + workflow scope）；'
              'GitLab 访问 https://gitlab.com/-/user_settings/personal_access_tokens 生成令牌（需勾选 api scope）\n'
              '4. 仓库名（同时作为站点项目名）\n'
              '5. 博客框架（hexo / hugo / jekyll / vuepress / gatsby / nextjs / astro / pelican / 11ty）\n'
              '6. 站点标题\n'
              '7. 仓库是否私有（默认私有；注意 GitHub 免费账号私有仓库无法启用 Pages）\n'
              '8. 是否生成欢迎文章（默认生成）\n'
              '9. 该账号是否首次建站（重要）：若是第一个站点且模式一，请设 root_domain=true，'
              '站点将使用顶层域名 <用户名>.github.io / <用户名>.gitlab.io（仓库名自动改为该形式，访问地址无路径后缀，'
              '如 https://username.github.io/ 而非 /my）；若非首个站点保持 root_domain=false（URL 为 https://username.github.io/仓库名/）。'
              '注意顶层仓库每账号只能建一个，已存在则不可用。模式二前缀本就可自选，root_domain 无效。\n'
              '若用户选择模式二（Cloudflare Pages），还需额外提供 Cloudflare API Token（需 pages:edit 权限，在 Cloudflare 控制台生成）与 Account ID。\n\n'
              '拿到模式、平台、Token、仓库名后即可开始建站，其余信息用合理默认值（框架 hexo、标题取仓库名、私有、生成欢迎文章）自行补全，不必逐项等用户确认。\n\n'
              '【部署协议（务必遵循，否则页面 404）】各平台静态托管协议：'
              'GitHub Pages：子目录部署地址为 https://<用户名>.github.io/<仓库名>/，'
              '站点必须把 base/root 设为 /<仓库名>/（骨架已自动配置），且资源/导航链接都要带上该前缀，否则页面能打开但点击全部 404；'
              'GitLab Pages 同理，子目录地址 https://<用户名>.gitlab.io/<项目>/；'
              '顶层站点（root_domain=true）地址为 https://<用户名>.github.io/ 或 https://<用户名>.gitlab.io/，无路径前缀。'
              'Cloudflare Pages 地址为 https://<项目名>.pages.dev/，顶层部署。'
              '若站点出现"能打开但点击 404"，优先检查并修复 base/root/pathPrefix/basePath 配置。\n\n'
              '【执行流程】调用 create_site 工具完成建站（可传 root_domain 参数）。'
              '建站成功（create_site 或 register_site 返回后）必须调用 verify_site 自检站点：'
              '传入站点访问地址（root_domain 顶层站点为 https://<用户名>.github.io/ 或 https://<用户名>.gitlab.io/）'
              '与 expected_title=站点标题，确认 HTTP 可达、页面非空、标题正常。'
              '若 create_site 失败，不要立即抛给用户，先诊断：可改用分步工具断点续跑自愈：'
              '先调用 create_repo 建仓库（可传 root_domain），'
              '再调用 write_welcome_post 写欢迎文章（可选）、poll_site_build 轮询构建获取站点地址；'
              '模式二用 poll_site_build 拿到 deploy_hook 后调用 trigger_cf_deploy 触发部署。'
              '【自愈循环】自检失败或构建失败时，根据失败项自行定位并修复：'
              '用 file_write 修改仓库文件（框架 base/root 配置、CI 流水线、主题、文章等）触发重新构建，'
              '用 poll_site_build 轮询重建，再 verify_site 复查，循环直到站点可访问且内容正确。'
              '每一步失败先用 web_search 查对应平台官方文档，不要急着问用户。'
              '全部完成后调用 register_site 将站点注册到站点管理，并再次 verify_site 确认最终状态。'
              '残留资源用 rollback_site 清理。'
              '全程自己做推送（写入仓库即触发）、自己做验证（verify_site），不要要求用户代为操作。',
        ),
      ),
    );
  }

  void _showAiModelManager() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiModelManagerScreen(
          modelManager: aiModelManager,
          aiService: aiService,
          settings: settings,
          onSettingsChanged: _updateSettings,
        ),
      ),
    );
  }

  void _showToolLibrary() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ToolLibraryScreen(skillManager: skillManager),
      ),
    );
  }
}
