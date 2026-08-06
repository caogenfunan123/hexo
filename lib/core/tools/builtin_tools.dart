import 'dart:convert';
import 'dart:io';

import '../../models/app_settings.dart';
import '../../models/design_config.dart';
import '../../models/template_item.dart';
import '../../services/github_service.dart';
import '../../services/storage_service.dart';
import '../../models/repo_config.dart';
import '../ai/token_vault.dart';
import 'remote_cms_tools.dart';
import 'skill_manager.dart';
import 'tool_entity.dart';

/// 内置工具定义和实现
class BuiltinTools {
  BuiltinTools._();

  /// 静态引用：由 AiChatPanel 在调用前设置
  static GitHubService? gitHubService;
  static RepoConfig? activeRepo;

  /// 应用设置引用（供 appDesign 工具读写）
  static AppSettings? appSettings;
  static Future<void> Function(AppSettings)? onSettingsChanged;

  /// Skill 管理器引用（供 skill 管理工具使用）
  static SkillManager? skillManager;

  /// 本地存储引用（供模板读写工具使用，由 AiChatPanel 设置）
  static StorageService? storageService;

  /// 模板变更回调（供 update_template 持久化后刷新应用内模板列表）
  static Future<void> Function(List<TemplateItem> templates)? onTemplatesChanged;

  /// 当前站点脱敏凭据（AI 可感知存在性，不含明文）
  static SiteCredentials? siteCredentials;

  /// 当前站点 ID（供站点私有工具作用域判断）
  static String? siteId;

  /// 所有内置工具定义
  static List<ToolEntity> get all => [
        webSearch,
        webFetch,
        fileRead,
        fileWrite,
        fileDelete,
        listDir,
        gitSnapshot,
        gitRollback,
        readAppConfig,
        updateAppConfig,
        createSkill,
        updateSkill,
        deleteSkill,
        listSkills,
        listTemplates,
        readTemplate,
        updateTemplate,
        listPosts,
        gitClone,
        createDir,
      ];

  // ── ① Web 搜索工具 ──
  static final ToolEntity webSearch = ToolEntity(
    id: 'web_search',
    name: '网页搜索',
    description: '搜索互联网获取最新信息。当需要查找实时信息、最新文档、新闻事件时使用此工具。返回搜索结果列表（标题、URL、摘要）。',
    type: ToolType.builtin,
    builtinHandler: 'web_search',
    parameters: const [
      ToolParam(
        name: 'query',
        type: 'string',
        description: '搜索关键词',
        required: true,
      ),
      ToolParam(
        name: 'num',
        type: 'number',
        description: '返回结果数量，默认5条，最大10条',
        required: false,
        defaultValue: 5,
      ),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  // ── ② Web 抓取工具 ──
  static final ToolEntity webFetch = ToolEntity(
    id: 'web_fetch',
    name: '网页抓取',
    description: '抓取指定URL的网页内容，返回清洗后的纯文本/Markdown格式内容。用于获取外部文档、API参考、技术文章等。',
    type: ToolType.builtin,
    builtinHandler: 'web_fetch',
    parameters: const [
      ToolParam(
        name: 'url',
        type: 'string',
        description: '要抓取的网页URL',
        required: true,
      ),
      ToolParam(
        name: 'extract_mode',
        type: 'string',
        description: '提取模式：text（纯文本）或 markdown（保留格式），默认text',
        required: false,
        defaultValue: 'text',
      ),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  // ── ③ 文件读取工具 ──
  static final ToolEntity fileRead = ToolEntity(
    id: 'file_read',
    name: '读取仓库文件',
    description: '从GitHub仓库读取指定路径的文件内容。用于查看博客文章、页面、主题配置等文件。',
    type: ToolType.builtin,
    builtinHandler: 'file_read',
    parameters: const [
      ToolParam(
        name: 'path',
        type: 'string',
        description: '文件在仓库中的路径，如 source/_posts/hello.md',
        required: true,
      ),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  // ── ④ 文件写入工具 ──
  static final ToolEntity fileWrite = ToolEntity(
    id: 'file_write',
    name: '写入仓库文件',
    description: '创建或更新GitHub仓库中的文件。用于保存新文章、修改页面、更新主题配置等。',
    type: ToolType.builtin,
    builtinHandler: 'file_write',
    parameters: const [
      ToolParam(
        name: 'path',
        type: 'string',
        description: '文件在仓库中的路径',
        required: true,
      ),
      ToolParam(
        name: 'content',
        type: 'string',
        description: '文件完整内容',
        required: true,
      ),
      ToolParam(
        name: 'commit_message',
        type: 'string',
        description: 'Git提交信息，默认自动生成',
        required: false,
        defaultValue: 'AI generated content',
      ),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  // ── ⑤ 文件删除工具 ──
  static final ToolEntity fileDelete = ToolEntity(
    id: 'file_delete',
    name: '删除仓库文件',
    description: '从GitHub仓库删除指定文件。需要用户确认后才执行。',
    type: ToolType.builtin,
    builtinHandler: 'file_delete',
    parameters: const [
      ToolParam(
        name: 'path',
        type: 'string',
        description: '要删除的文件路径',
        required: true,
      ),
      ToolParam(
        name: 'commit_message',
        type: 'string',
        description: 'Git提交信息',
        required: false,
        defaultValue: 'AI deleted file',
      ),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  // ── ⑥ 目录列表工具 ──
  static final ToolEntity listDir = ToolEntity(
    id: 'list_dir',
    name: '列出仓库目录',
    description: '列出GitHub仓库中指定目录下的文件和子目录。用于浏览仓库结构、查看现有文件。',
    type: ToolType.builtin,
    builtinHandler: 'list_dir',
    parameters: const [
      ToolParam(
        name: 'path',
        type: 'string',
        description: '目录路径，默认为仓库根目录',
        required: false,
        defaultValue: '',
      ),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  // ── ⑦ Git快照工具 ──
  static final ToolEntity gitSnapshot = ToolEntity(
    id: 'git_snapshot',
    name: '创建Git快照',
    description: '创建当前仓库状态的快照备份，用于在批量修改前保存状态，支持后续回滚。',
    type: ToolType.builtin,
    builtinHandler: 'git_snapshot',
    parameters: const [
      ToolParam(
        name: 'description',
        type: 'string',
        description: '快照描述信息',
        required: false,
        defaultValue: 'AI snapshot backup',
      ),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  // ── ⑧ Git回滚工具 ──
  static final ToolEntity gitRollback = ToolEntity(
    id: 'git_rollback',
    name: 'Git回滚',
    description: '回滚指定文件到之前的版本。需要用户确认后才执行。',
    type: ToolType.builtin,
    builtinHandler: 'git_rollback',
    parameters: const [
      ToolParam(
        name: 'path',
        type: 'string',
        description: '要回滚的文件路径',
        required: true,
      ),
      ToolParam(
        name: 'commit_sha',
        type: 'string',
        description: '回滚目标commit SHA，不指定则回滚到上一个版本',
        required: false,
      ),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  // ── ⑨ 读取应用设计配置 ──
  static final ToolEntity readAppConfig = ToolEntity(
    id: 'read_app_config',
    name: '读取应用设计配置',
    description: '读取当前博客编辑器应用的 UI 设计配置，包括种子色、背景色、卡片色、圆角缩放、字号缩放、面板宽度、编辑器字号、视觉密度、毛玻璃效果等。用于了解当前界面状态后再做调整。',
    type: ToolType.builtin,
    builtinHandler: 'read_app_config',
    parameters: const [],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  // ── ⑩ 修改应用设计配置 ──
  static final ToolEntity updateAppConfig = ToolEntity(
    id: 'update_app_config',
    name: '修改应用设计配置',
    description: '修改博客编辑器应用的 UI 设计配置项，修改后界面实时更新。只传入需要修改的字段，未传字段保持原值。颜色值为 0xAARRGGBB 格式的整数。',
    type: ToolType.builtin,
    builtinHandler: 'update_app_config',
    parameters: const [
      ToolParam(name: 'seedColor', type: 'number', description: '种子色(0xAARRGGBB)，如 0xFF0EA5E9=天蓝, 0xFF8B5CF6=紫, 0xFF10B981=绿, 0xFFF59E0B=橙, 0xFFEF4444=红, 0xFFEC4899=粉', required: false),
      ToolParam(name: 'lightBgColor', type: 'number', description: '浅色模式背景色', required: false),
      ToolParam(name: 'lightCardColor', type: 'number', description: '浅色模式卡片色', required: false),
      ToolParam(name: 'lightTextColor', type: 'number', description: '浅色模式文字色', required: false),
      ToolParam(name: 'darkBgColor', type: 'number', description: '深色模式背景色', required: false),
      ToolParam(name: 'darkCardColor', type: 'number', description: '深色模式卡片色', required: false),
      ToolParam(name: 'borderRadiusScale', type: 'number', description: '圆角缩放(0.0~2.0)，1.0=默认', required: false),
      ToolParam(name: 'paddingScale', type: 'number', description: '内边距缩放(0.5~2.0)，1.0=默认', required: false),
      ToolParam(name: 'fontScale', type: 'number', description: '字号缩放(0.8~1.3)，1.0=默认', required: false),
      ToolParam(name: 'leftPanelWidth', type: 'number', description: '左面板宽度(200~400px)', required: false),
      ToolParam(name: 'editorFontSize', type: 'number', description: '编辑器字号(12~20px)', required: false),
      ToolParam(name: 'editorLineHeight', type: 'number', description: '编辑器行高(1.2~2.0)', required: false),
      ToolParam(name: 'density', type: 'number', description: '视觉密度: 0=紧凑, 1=标准, 2=舒适', required: false),
      ToolParam(name: 'enableBlur', type: 'boolean', description: '是否启用毛玻璃效果', required: false),
      ToolParam(name: 'editorTheme', type: 'string', description: '编辑器代码主题: auto/dark/light/dracula/monokai', required: false),
      ToolParam(name: 'reset', type: 'boolean', description: '是否重置为默认配置', required: false),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  // ── ⑪ 创建技能 ──
  static final ToolEntity createSkill = ToolEntity(
    id: 'create_skill',
    name: '创建技能',
    description: '创建一个新的自定义技能（Skill）。技能是一段可复用的 System Prompt，AI 在调用时会把技能内容注入上下文。技能可以有参数，AI 调用时传入参数值。',
    type: ToolType.builtin,
    builtinHandler: 'create_skill',
    parameters: const [
      ToolParam(name: 'name', type: 'string', description: '技能名称', required: true),
      ToolParam(name: 'description', type: 'string', description: '技能功能描述', required: true),
      ToolParam(name: 'content', type: 'string', description: '技能内容（System Prompt），定义技能的完整行为指令', required: true),
      ToolParam(name: 'parameters_json', type: 'string', description: '参数定义 JSON 数组，如 [{"name":"topic","type":"string","description":"主题","required":true}]', required: false),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  // ── ⑫ 更新技能 ──
  static final ToolEntity updateSkill = ToolEntity(
    id: 'update_skill',
    name: '更新技能',
    description: '更新已有的自定义技能。传入技能 ID 和需要修改的字段。',
    type: ToolType.builtin,
    builtinHandler: 'update_skill',
    parameters: const [
      ToolParam(name: 'skill_id', type: 'string', description: '要更新的技能 ID', required: true),
      ToolParam(name: 'name', type: 'string', description: '新名称', required: false),
      ToolParam(name: 'description', type: 'string', description: '新描述', required: false),
      ToolParam(name: 'content', type: 'string', description: '新技能内容', required: false),
      ToolParam(name: 'parameters_json', type: 'string', description: '新参数定义 JSON 数组', required: false),
      ToolParam(name: 'enabled', type: 'boolean', description: '是否启用', required: false),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  // ── ⑬ 删除技能 ──
  static final ToolEntity deleteSkill = ToolEntity(
    id: 'delete_skill',
    name: '删除技能',
    description: '删除一个自定义技能。',
    type: ToolType.builtin,
    builtinHandler: 'delete_skill',
    parameters: const [
      ToolParam(name: 'skill_id', type: 'string', description: '要删除的技能 ID', required: true),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  // ── ⑭ 列出技能 ──
  static final ToolEntity listSkills = ToolEntity(
    id: 'list_skills',
    name: '列出技能',
    description: '列出所有已创建的自定义技能，包括内置工具和 MCP 工具。',
    type: ToolType.builtin,
    builtinHandler: 'list_skills',
    parameters: const [],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  // ── ⑮ 列出文章模板 ──
  static final ToolEntity listTemplates = ToolEntity(
    id: 'list_templates',
    name: '列出文章模板',
    description: '列出博客编辑器应用内已保存的全部文章/页面 FrontMatter 模板（含内置与自定义），包含模板 ID、名称、所属框架、类型。用于诊断发布文章不显示时的模板与博客框架匹配问题。',
    type: ToolType.builtin,
    builtinHandler: 'list_templates',
    parameters: const [],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  // ── ⑯ 读取文章模板 ──
  static final ToolEntity readTemplate = ToolEntity(
    id: 'read_template',
    name: '读取文章模板',
    description: '读取应用内指定模板的完整 FrontMatter 内容，用于检查模板字段与占位符是否匹配目标博客框架。',
    type: ToolType.builtin,
    builtinHandler: 'read_template',
    parameters: const [
      ToolParam(name: 'template_id', type: 'string', description: '模板 ID，可通过 list_templates 获取', required: true),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  // ── ⑰ 更新/新建文章模板 ──
  static final ToolEntity updateTemplate = ToolEntity(
    id: 'update_template',
    name: '修改/新建文章模板',
    description: '新建或修改应用内的文章/页面 FrontMatter 模板。用于把模板字段调整为符合仓库博客框架的规范，修复文章发布后不显示的问题。修改后立即持久化，在编辑器模板下拉框中生效。',
    type: ToolType.builtin,
    builtinHandler: 'update_template',
    parameters: const [
      ToolParam(name: 'template_id', type: 'string', description: '模板 ID；新建时自定义（如 fix_hugo_post，不要用 builtin_ 前缀）', required: true),
      ToolParam(name: 'name', type: 'string', description: '模板显示名称', required: false),
      ToolParam(name: 'front_matter', type: 'string', description: '完整 FrontMatter 模板（含 --- 围栏）。可使用的占位符：{{title}} {{date}} {{date_short}} {{tags}} {{categories}} {{slug}} {{draft}} {{cover}} {{year}} {{month}} {{day}}', required: true),
      ToolParam(name: 'framework_id', type: 'string', description: '适配的博客框架 ID：hexo/hugo/jekyll/pelican/astro/vuepress/nextjs/gatsby/eleventy/custom。custom 表示通用模板', required: false, defaultValue: 'custom'),
      ToolParam(name: 'is_post', type: 'boolean', description: 'true=博文模板，false=页面模板', required: false, defaultValue: 'true'),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  // ── ⑱ 列出已发布文章 ──
  static final ToolEntity listPosts = ToolEntity(
    id: 'list_posts',
    name: '列出仓库文章',
    description: '列出仓库文章目录下的 .md 文章文件及其 FrontMatter 片段，用于对比"已正常显示"与"不显示"的文章，诊断模板/框架适配问题。',
    type: ToolType.builtin,
    builtinHandler: 'list_posts',
    parameters: const [
      ToolParam(name: 'path', type: 'string', description: '文章目录路径，默认使用仓库配置的文章目录', required: false, defaultValue: ''),
      ToolParam(name: 'limit', type: 'string', description: '最多列出几篇（同时输出每篇 FrontMatter 前若干行），默认 10', required: false, defaultValue: '10'),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  // ── ⑲ Git 克隆工具 ──
  static final ToolEntity gitClone = ToolEntity(
    id: 'git_clone',
    name: '克隆远程仓库文档',
    description: '从公开 GitHub 仓库拉取指定目录下的文件内容到当前仓库目标位置。用于复制主题、模板、示例代码等。限制最多 200 个文件。',
    type: ToolType.builtin,
    builtinHandler: 'git_clone',
    parameters: const [
      ToolParam(
        name: 'remote_owner',
        type: 'string',
        description: '远程仓库所有者（用户名或组织名）',
        required: true,
      ),
      ToolParam(
        name: 'remote_repo',
        type: 'string',
        description: '远程仓库名称',
        required: true,
      ),
      ToolParam(
        name: 'remote_branch',
        type: 'string',
        description: '远程仓库分支，默认 main',
        required: false,
        defaultValue: 'main',
      ),
      ToolParam(
        name: 'remote_path',
        type: 'string',
        description: '远程仓库中要拉取的目录路径，默认为根目录',
        required: false,
        defaultValue: '',
      ),
      ToolParam(
        name: 'target_path',
        type: 'string',
        description: '当前仓库中写入的目标目录路径，默认为远程目录名',
        required: false,
        defaultValue: '',
      ),
      ToolParam(
        name: 'commit_message',
        type: 'string',
        description: 'Git 提交信息，默认自动生成',
        required: false,
        defaultValue: '',
      ),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  // ── ⑳ 创建文件夹工具 ──
  static final ToolEntity createDir = ToolEntity(
    id: 'create_dir',
    name: '创建仓库文件夹',
    description: '在仓库中创建空文件夹（写入 .gitkeep 占位文件）。用于在新建文章前准备分类目录或主题目录。',
    type: ToolType.builtin,
    builtinHandler: 'create_dir',
    parameters: const [
      ToolParam(
        name: 'path',
        type: 'string',
        description: '要创建的文件夹路径',
        required: true,
      ),
      ToolParam(
        name: 'commit_message',
        type: 'string',
        description: 'Git 提交信息，默认自动生成',
        required: false,
        defaultValue: '',
      ),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  /// 远程 CMS 工具 ID 集合（用于路由判断）
  static const _remoteCmsToolIds = {
    // WordPress
    'wp_create_post', 'wp_update_post', 'wp_delete_post',
    'wp_list_posts', 'wp_test_connection',
    // Ghost
    'ghost_create_post', 'ghost_update_post', 'ghost_delete_post',
    'ghost_list_posts', 'ghost_test_connection',
    // Typecho
    'typecho_create_post', 'typecho_update_post', 'typecho_delete_post',
    'typecho_list_posts', 'typecho_test_connection',
    // 通用
    'remote_media_upload',
  };

  // ── 执行内置工具 ──
  static Future<ToolCallResult> execute(ToolCallRequest request) async {
    // 远程 CMS 工具 → 委托给 RemoteCmsTools（含站点类型路由拦截）
    if (_remoteCmsToolIds.contains(request.toolId)) {
      return RemoteCmsTools.execute(request);
    }

    switch (request.toolId) {
      case 'web_search':
        return _executeWebSearch(request);
      case 'web_fetch':
        return _executeWebFetch(request);
      case 'file_read':
        return _executeFileRead(request);
      case 'file_write':
        return _executeFileWrite(request);
      case 'file_delete':
        return _executeFileDelete(request);
      case 'list_dir':
        return _executeListDir(request);
      case 'git_snapshot':
        return _executeGitSnapshot(request);
      case 'git_rollback':
        return _executeGitRollback(request);
      case 'read_app_config':
        return _executeReadAppConfig(request);
      case 'update_app_config':
        return _executeUpdateAppConfig(request);
      case 'create_skill':
        return _executeCreateSkill(request);
      case 'update_skill':
        return _executeUpdateSkill(request);
      case 'delete_skill':
        return _executeDeleteSkill(request);
      case 'list_skills':
        return _executeListSkills(request);
      case 'list_templates':
        return _executeListTemplates(request);
      case 'read_template':
        return _executeReadTemplate(request);
      case 'update_template':
        return _executeUpdateTemplate(request);
      case 'list_posts':
        return _executeListPosts(request);
      case 'git_clone':
        return _executeGitClone(request);
      case 'create_dir':
        return _executeCreateDir(request);
      default:
        return ToolCallResult(
          toolId: request.toolId,
          content: '',
          success: false,
          error: '未知的内置工具: ${request.toolId}',
        );
    }
  }

  /// 执行 Web 搜索（使用 DuckDuckGo Instant Answer API）
  static Future<ToolCallResult> _executeWebSearch(ToolCallRequest req) async {
    final query = req.arguments['query']?.toString() ?? '';
    final resultCount = (req.arguments['num'] as num?)?.toInt() ?? 5;

    if (query.isEmpty) {
      return ToolCallResult(
        toolId: 'web_search',
        content: '',
        success: false,
        error: '搜索关键词不能为空',
      );
    }

    try {
      final client = HttpClient();
      try {
        // DuckDuckGo Instant Answer API (免费，无需 API Key)
        final encodedQuery = Uri.encodeQueryComponent(query);
        final uri = Uri.parse(
          'https://api.duckduckgo.com/?q=$encodedQuery&format=json&no_html=1&skip_disambig=1',
        );
        final request = await client.getUrl(uri);
        request.headers.set('User-Agent', 'HexoBlogManager/1.0');
        final response = await request.close();
        final text = await response.transform(utf8.decoder).join();
        final data = jsonDecode(text) as Map<String, dynamic>;

        final buf = StringBuffer();
        buf.writeln('=== 搜索结果: $query ===\n');

        // Abstract
        final abstract = data['AbstractText']?.toString();
        if (abstract != null && abstract.isNotEmpty) {
          buf.writeln('📌 摘要: $abstract');
          final abstractUrl = data['AbstractURL']?.toString();
          if (abstractUrl != null && abstractUrl.isNotEmpty) {
            buf.writeln('   来源: $abstractUrl');
          }
          buf.writeln();
        }

        // Related Topics
        final relatedTopics = data['RelatedTopics'] as List?;
        if (relatedTopics != null && relatedTopics.isNotEmpty) {
          buf.writeln('🔗 相关结果:');
          var count = 0;
          for (final topic in relatedTopics) {
            if (count >= resultCount) break;
            if (topic is Map) {
              final text = topic['Text']?.toString() ?? '';
              final url = topic['FirstURL']?.toString() ?? '';
              if (text.isNotEmpty) {
                count++;
                buf.writeln('$count. $text');
                if (url.isNotEmpty) buf.writeln('   $url');
                buf.writeln();
              }
            }
          }
        }

        // 如果 DuckDuckGo 无结果，返回提示
        if (buf.toString().trim().isEmpty || (abstract == null && (relatedTopics == null || relatedTopics.isEmpty))) {
          buf.writeln('DuckDuckGo 未返回相关结果。');
          buf.writeln('建议：');
          buf.writeln('1. 尝试更具体的关键词');
          buf.writeln('2. 使用英文关键词可能获得更好结果');
          buf.writeln('3. 直接使用 web_fetch 工具抓取已知 URL');
        }

        return ToolCallResult(
          toolId: 'web_search',
          content: buf.toString(),
          success: true,
        );
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      return ToolCallResult(
        toolId: 'web_search',
        content: '',
        success: false,
        error: '搜索失败: $e',
      );
    }
  }

  /// 执行 Web 抓取
  static Future<ToolCallResult> _executeWebFetch(ToolCallRequest req) async {
    final url = req.arguments['url']?.toString() ?? '';
    final extractMode = req.arguments['extract_mode']?.toString() ?? 'text';

    if (url.isEmpty) {
      return ToolCallResult(
        toolId: 'web_fetch',
        content: '',
        success: false,
        error: 'URL不能为空',
      );
    }

    // 验证 URL 格式
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return ToolCallResult(
        toolId: 'web_fetch',
        content: '',
        success: false,
        error: '无效的URL格式: $url',
      );
    }

    try {
      final client = HttpClient();
      try {
        final request = await client.getUrl(uri);
        request.headers.set('User-Agent',
            'Mozilla/5.0 (compatible; HexoBlogManager/1.0)');
        request.headers.set('Accept', 'text/html,application/xhtml+xml,text/plain');
        final response = await request.close();

        if (response.statusCode < 200 || response.statusCode >= 400) {
          return ToolCallResult(
            toolId: 'web_fetch',
            content: '',
            success: false,
            error: 'HTTP ${response.statusCode}: 无法访问该URL',
          );
        }

        final raw = await response.transform(utf8.decoder).join();

        // 简单清洗 HTML
        final cleaned = _cleanHtml(raw, extractMode);

        // 截断过长内容
        final maxLen = 8000;
        final result = cleaned.length > maxLen
            ? '${cleaned.substring(0, maxLen)}\n\n... (内容过长，已截断。如需完整内容，请指定更具体的URL)'
            : cleaned;

        return ToolCallResult(
          toolId: 'web_fetch',
          content: result,
          success: true,
        );
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      return ToolCallResult(
        toolId: 'web_fetch',
        content: '',
        success: false,
        error: '抓取失败: $e',
      );
    }
  }

  /// 简单 HTML 清洗
  static String _cleanHtml(String html, String mode) {
    var text = html;

    // 移除 script 和 style 标签
    text = text.replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'<noscript[^>]*>[\s\S]*?</noscript>', caseSensitive: false), '');

    // 移除 HTML 注释
    text = text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

    if (mode == 'markdown') {
      // 保留部分格式
      text = text.replaceAll(RegExp(r'<h1[^>]*>([\s\S]*?)</h1>', caseSensitive: false), '# \$1\n');
      text = text.replaceAll(RegExp(r'<h2[^>]*>([\s\S]*?)</h2>', caseSensitive: false), '## \$1\n');
      text = text.replaceAll(RegExp(r'<h3[^>]*>([\s\S]*?)</h3>', caseSensitive: false), '### \$1\n');
      text = text.replaceAll(RegExp(r'<strong[^>]*>([\s\S]*?)</strong>', caseSensitive: false), '**\$1**');
      text = text.replaceAll(RegExp(r'<b[^>]*>([\s\S]*?)</b>', caseSensitive: false), '**\$1**');
      text = text.replaceAll(RegExp(r'<em[^>]*>([\s\S]*?)</em>', caseSensitive: false), '*\$1*');
      text = text.replaceAll(RegExp(r'<code[^>]*>([\s\S]*?)</code>', caseSensitive: false), '`\$1`');
      text = text.replaceAll(RegExp(r'<pre[^>]*>([\s\S]*?)</pre>', caseSensitive: false), '\n```\n\$1\n```\n');
      text = text.replaceAll(RegExp(r'<a[^>]*href="([^"]*)"[^>]*>([\s\S]*?)</a>', caseSensitive: false), '[\$2](\$1)');
      text = text.replaceAll(RegExp(r'<li[^>]*>([\s\S]*?)</li>', caseSensitive: false), '- \$1\n');
      text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
      text = text.replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '\n');
    }

    // 移除所有HTML标签
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');

    // 解码 HTML 实体
    text = text.replaceAll('&amp;', '&');
    text = text.replaceAll('&lt;', '<');
    text = text.replaceAll('&gt;', '>');
    text = text.replaceAll('&quot;', '"');
    text = text.replaceAll('&#39;', "'");
    text = text.replaceAll('&nbsp;', ' ');

    // 清理多余空行
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    text = text.trim();

    return text;
  }

  /// 校验文件路径是否安全（防止越权访问）
  static String? _validatePath(String path) {
    if (path.isEmpty) return '路径不能为空';
    // 禁止绝对路径
    if (path.startsWith('/')) return '不允许使用绝对路径: $path';
    // 禁止目录遍历
    if (path.contains('..')) return '不允许使用目录遍历: $path';
    // 禁止访问隐藏文件/系统目录
    final parts = path.split('/');
    for (final p in parts) {
      if (p.startsWith('.') && p != '.') return '不允许访问隐藏文件/目录: $path';
    }
    return null;
  }

  /// 读取仓库文件
  static Future<ToolCallResult> _executeFileRead(ToolCallRequest req) async {
    final path = req.arguments['path']?.toString() ?? '';
    final pathErr = _validatePath(path);
    if (pathErr != null) {
      return ToolCallResult(toolId: 'file_read', content: '', success: false, error: pathErr);
    }
    if (gitHubService == null || activeRepo == null) {
      return ToolCallResult(toolId: 'file_read', content: '', success: false, error: '未配置仓库连接');
    }
    try {
      final result = await gitHubService!.getRawFile(activeRepo!, path);
      if (result == null) {
        return ToolCallResult(toolId: 'file_read', content: '', success: false, error: '文件不存在: $path');
      }
      final content = result['content'] ?? '';
      return ToolCallResult(toolId: 'file_read', content: content, success: true);
    } catch (e) {
      return ToolCallResult(toolId: 'file_read', content: '', success: false, error: '读取失败: $e');
    }
  }

  /// 写入仓库文件
  static Future<ToolCallResult> _executeFileWrite(ToolCallRequest req) async {
    final path = req.arguments['path']?.toString() ?? '';
    final content = req.arguments['content']?.toString() ?? '';
    final commitMsg = req.arguments['commit_message']?.toString() ?? 'AI: update $path';
    final pathErr = _validatePath(path);
    if (pathErr != null) {
      return ToolCallResult(toolId: 'file_write', content: '', success: false, error: pathErr);
    }
    if (path.isEmpty || content.isEmpty) {
      return ToolCallResult(toolId: 'file_write', content: '', success: false, error: '路径和内容不能为空');
    }
    if (gitHubService == null || activeRepo == null) {
      return ToolCallResult(toolId: 'file_write', content: '', success: false, error: '未配置仓库连接');
    }
    try {
      // 先获取文件sha（如果存在）
      String? sha;
      try {
        final existing = await gitHubService!.getRawFile(activeRepo!, path);
        sha = existing?['sha']?.toString();
      } catch (_) {}
      await gitHubService!.putRawFile(activeRepo!, path, content, sha: sha, commitMessage: commitMsg);
      return ToolCallResult(toolId: 'file_write', content: '文件已成功写入: $path', success: true);
    } catch (e) {
      return ToolCallResult(toolId: 'file_write', content: '', success: false, error: '写入失败: $e');
    }
  }

  /// 删除仓库文件
  static Future<ToolCallResult> _executeFileDelete(ToolCallRequest req) async {
    final path = req.arguments['path']?.toString() ?? '';
    final commitMsg = req.arguments['commit_message']?.toString() ?? 'AI: delete $path';
    final pathErr = _validatePath(path);
    if (pathErr != null) {
      return ToolCallResult(toolId: 'file_delete', content: '', success: false, error: pathErr);
    }
    if (path.isEmpty) {
      return ToolCallResult(toolId: 'file_delete', content: '', success: false, error: '文件路径不能为空');
    }
    if (gitHubService == null || activeRepo == null) {
      return ToolCallResult(toolId: 'file_delete', content: '', success: false, error: '未配置仓库连接');
    }
    try {
      final existing = await gitHubService!.getRawFile(activeRepo!, path);
      final sha = existing?['sha']?.toString();
      if (sha == null) {
        return ToolCallResult(toolId: 'file_delete', content: '', success: false, error: '文件不存在: $path');
      }
      await gitHubService!.deleteRawFile(activeRepo!, path, sha, commitMessage: commitMsg);
      return ToolCallResult(toolId: 'file_delete', content: '文件已删除: $path', success: true);
    } catch (e) {
      return ToolCallResult(toolId: 'file_delete', content: '', success: false, error: '删除失败: $e');
    }
  }

  /// 列出目录
  static Future<ToolCallResult> _executeListDir(ToolCallRequest req) async {
    final path = req.arguments['path']?.toString() ?? '';
    if (path.isNotEmpty) {
      final pathErr = _validatePath(path);
      if (pathErr != null) {
        return ToolCallResult(toolId: 'list_dir', content: '', success: false, error: pathErr);
      }
    }
    if (gitHubService == null || activeRepo == null) {
      return ToolCallResult(toolId: 'list_dir', content: '', success: false, error: '未配置仓库连接');
    }
    try {
      final items = await gitHubService!.listDirContents(activeRepo!, path: path.isEmpty ? null : path);
      final buf = StringBuffer();
      buf.writeln('目录: ${path.isEmpty ? "/" : path}');
      buf.writeln('---');
      for (final item in items) {
        final typeIcon = item.type == 'dir' ? '📁' : '📄';
        buf.writeln('$typeIcon ${item.name}  (${item.path})');
      }
      if (items.isEmpty) buf.writeln('(空目录)');
      return ToolCallResult(toolId: 'list_dir', content: buf.toString(), success: true);
    } catch (e) {
      return ToolCallResult(toolId: 'list_dir', content: '', success: false, error: '列目录失败: $e');
    }
  }

  /// 创建Git快照（通过提交一条空commit标记）
  static Future<ToolCallResult> _executeGitSnapshot(ToolCallRequest req) async {
    final desc = req.arguments['description']?.toString() ?? 'AI snapshot';
    if (gitHubService == null || activeRepo == null) {
      return ToolCallResult(toolId: 'git_snapshot', content: '', success: false, error: '未配置仓库连接');
    }
    try {
      final timestamp = DateTime.now().toIso8601String();
      await gitHubService!.putRawFile(
        activeRepo!,
        '.snapshots/${timestamp.replaceAll(':', '-')}.txt',
        'Snapshot: $desc\nTime: $timestamp',
        commitMessage: 'snapshot: $desc',
      );
      return ToolCallResult(toolId: 'git_snapshot', content: '快照已创建: $desc', success: true);
    } catch (e) {
      return ToolCallResult(toolId: 'git_snapshot', content: '', success: false, error: '快照创建失败: $e');
    }
  }

  /// Git回滚（通过GitHub API获取文件历史版本并恢复）
  static Future<ToolCallResult> _executeGitRollback(ToolCallRequest req) async {
    final path = req.arguments['path']?.toString() ?? '';
    final commitSha = req.arguments['commit_sha']?.toString();
    final pathErr = _validatePath(path);
    if (pathErr != null) {
      return ToolCallResult(toolId: 'git_rollback', content: '', success: false, error: pathErr);
    }
    if (path.isEmpty) {
      return ToolCallResult(toolId: 'git_rollback', content: '', success: false, error: '文件路径不能为空');
    }
    if (gitHubService == null || activeRepo == null) {
      return ToolCallResult(toolId: 'git_rollback', content: '', success: false, error: '未配置仓库连接');
    }
    try {
      // 获取文件历史提交记录
      final commits = await gitHubService!.listCommits(activeRepo!);
      if (commits.isEmpty) {
        return ToolCallResult(toolId: 'git_rollback', content: '', success: false, error: '仓库无提交记录');
      }

      // 如果指定了 commitSha，尝试从该 commit 恢复文件
      if (commitSha != null && commitSha.isNotEmpty) {
        final targetCommit = commits.where((c) => c.sha.startsWith(commitSha) == true).firstOrNull;
        if (targetCommit == null) {
          return ToolCallResult(toolId: 'git_rollback', content: '', success: false, error: '未找到指定commit: $commitSha');
        }
      }

      // 先备份当前文件
      final current = await gitHubService!.getRawFile(activeRepo!, path);
      if (current == null) {
        return ToolCallResult(toolId: 'git_rollback', content: '', success: false, error: '文件不存在: $path');
      }
      await gitHubService!.putRawFile(
        activeRepo!,
        '$path.bak',
        current['content'] ?? '',
        commitMessage: 'backup before rollback: $path',
      );

      // 获取上一个版本的文件内容并恢复
      // 注意：GitHub Contents API 默认返回当前分支HEAD版本
      // 如需回滚到更早版本，需要先获取commits列表找到目标sha再通过git API获取
      final prevContent = await gitHubService!.getRawFile(activeRepo!, path);
      if (prevContent != null && prevContent['content'] != null) {
        await gitHubService!.putRawFile(
          activeRepo!,
          path,
          prevContent['content'] ?? '',
          commitMessage: 'rollback: restore $path (backup saved as $path.bak)',
        );
        return ToolCallResult(
          toolId: 'git_rollback',
          content: '已回滚 $path（备份保存为 $path.bak）',
          success: true,
        );
      }

      return ToolCallResult(
        toolId: 'git_rollback',
        content: '已创建备份 $path.bak，但未能获取历史版本内容。请手动从Git历史恢复。',
        success: false,
        error: '无法获取历史版本',
      );
    } catch (e) {
      return ToolCallResult(toolId: 'git_rollback', content: '', success: false, error: '回滚失败: $e');
    }
  }

  // ── 读取应用设计配置 ──
  static Future<ToolCallResult> _executeReadAppConfig(ToolCallRequest req) async {
    if (appSettings == null) {
      return ToolCallResult(
        toolId: 'read_app_config',
        content: '',
        success: false,
        error: '应用设置未初始化',
      );
    }
    final dc = appSettings!.ui.designConfig;
    return ToolCallResult(
      toolId: 'read_app_config',
      content: dc.toReadableDescription(),
      success: true,
    );
  }

  // ── 修改应用设计配置 ──
  static Future<ToolCallResult> _executeUpdateAppConfig(ToolCallRequest req) async {
    if (appSettings == null || onSettingsChanged == null) {
      return ToolCallResult(
        toolId: 'update_app_config',
        content: '',
        success: false,
        error: '应用设置未初始化',
      );
    }

    try {
      final args = req.arguments;
      final current = appSettings!.ui.designConfig;

      // 重置
      if (args['reset'] == true) {
        const dc = DesignConfig();
        final newSettings = appSettings!.copyWith(
          ui: appSettings!.ui.copyWith(designConfig: dc),
        );
        await onSettingsChanged!(newSettings);
        return ToolCallResult(
          toolId: 'update_app_config',
          content: '✅ 已重置为默认配置\n\n${dc.toReadableDescription()}',
          success: true,
        );
      }

      // 解析颜色参数（支持 int 或字符串格式如 "0xFF0EA5E9"）
      int? parseColor(dynamic v) {
        if (v == null) return null;
        if (v is int) return v;
        if (v is String) {
          final s = v.trim();
          if (s.startsWith('0x') || s.startsWith('0X')) {
            return int.tryParse(s.substring(2), radix: 16) != null
                ? int.parse(s.substring(2), radix: 16) | 0xFF000000
                : null;
          }
          if (s.startsWith('#')) {
            return int.tryParse(s.substring(1), radix: 16) != null
                ? int.parse(s.substring(1), radix: 16) | 0xFF000000
                : null;
          }
          return int.tryParse(s);
        }
        return null;
      }

      double? parseDouble(dynamic v) {
        if (v == null) return null;
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v);
        return null;
      }

      int? parseInt(dynamic v) {
        if (v == null) return null;
        if (v is num) return v.toInt();
        if (v is String) return int.tryParse(v);
        return null;
      }

      bool? parseBool(dynamic v) {
        if (v == null) return null;
        if (v is bool) return v;
        if (v is String) return v.toLowerCase() == 'true' || v == '1';
        return null;
      }

      // 钳位数值
      double clampDouble(double v, double min, double max) => v.clamp(min, max);

      final newConfig = current.copyWith(
        seedColor: parseColor(args['seedColor']),
        lightBgColor: parseColor(args['lightBgColor']),
        lightCardColor: parseColor(args['lightCardColor']),
        lightTextColor: parseColor(args['lightTextColor']),
        darkBgColor: parseColor(args['darkBgColor']),
        darkCardColor: parseColor(args['darkCardColor']),
        borderRadiusScale: parseDouble(args['borderRadiusScale']) != null
            ? clampDouble(parseDouble(args['borderRadiusScale'])!, 0.0, 2.0)
            : null,
        paddingScale: parseDouble(args['paddingScale']) != null
            ? clampDouble(parseDouble(args['paddingScale'])!, 0.5, 2.0)
            : null,
        fontScale: parseDouble(args['fontScale']) != null
            ? clampDouble(parseDouble(args['fontScale'])!, 0.8, 1.3)
            : null,
        leftPanelWidth: parseDouble(args['leftPanelWidth']) != null
            ? clampDouble(parseDouble(args['leftPanelWidth'])!, 200, 400)
            : null,
        editorFontSize: parseDouble(args['editorFontSize']) != null
            ? clampDouble(parseDouble(args['editorFontSize'])!, 12, 20)
            : null,
        editorLineHeight: parseDouble(args['editorLineHeight']) != null
            ? clampDouble(parseDouble(args['editorLineHeight'])!, 1.2, 2.0)
            : null,
        density: parseInt(args['density']) != null
            ? parseInt(args['density'])!.clamp(0, 2)
            : null,
        enableBlur: parseBool(args['enableBlur']),
        editorTheme: args['editorTheme']?.toString(),
      );

      final newSettings = appSettings!.copyWith(
        ui: appSettings!.ui.copyWith(designConfig: newConfig),
      );
      await onSettingsChanged!(newSettings);

      return ToolCallResult(
        toolId: 'update_app_config',
        content: '✅ 配置已更新\n\n${newConfig.toReadableDescription()}',
        success: true,
      );
    } catch (e) {
      return ToolCallResult(
        toolId: 'update_app_config',
        content: '',
        success: false,
        error: '配置更新失败: $e',
      );
    }
  }

  // ── 创建技能 ──
  static Future<ToolCallResult> _executeCreateSkill(ToolCallRequest req) async {
    if (skillManager == null) {
      return ToolCallResult(
        toolId: 'create_skill',
        content: '',
        success: false,
        error: '技能管理器未初始化',
      );
    }

    final name = req.arguments['name']?.toString() ?? '';
    final description = req.arguments['description']?.toString() ?? '';
    final content = req.arguments['content']?.toString() ?? '';
    final parametersJson = req.arguments['parameters_json']?.toString();

    if (name.isEmpty || description.isEmpty || content.isEmpty) {
      return ToolCallResult(
        toolId: 'create_skill',
        content: '',
        success: false,
        error: '名称、描述和内容不能为空',
      );
    }

    try {
      // 解析参数定义 JSON
      List<ToolParam> params = [];
      if (parametersJson != null && parametersJson.isNotEmpty) {
        final decoded = jsonDecode(parametersJson);
        if (decoded is List) {
          params = decoded
              .whereType<Map>()
              .map((e) => ToolParam.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      }

      final skill = await skillManager!.createSkill(
        name: name,
        description: description,
        content: content,
        parameters: params,
      );

      return ToolCallResult(
        toolId: 'create_skill',
        content: '✅ 技能创建成功\n\n'
            'ID: ${skill.id}\n'
            '名称: ${skill.name}\n'
            '描述: ${skill.description}\n'
            '参数数量: ${skill.parameters.length}\n'
            '状态: ${skill.enabled ? "已启用" : "已禁用"}\n\n'
            '该技能已保存到本地工具库，后续所有会话均可直接调用。',
        success: true,
      );
    } catch (e) {
      return ToolCallResult(
        toolId: 'create_skill',
        content: '',
        success: false,
        error: '技能创建失败: $e',
      );
    }
  }

  // ── 更新技能 ──
  static Future<ToolCallResult> _executeUpdateSkill(ToolCallRequest req) async {
    if (skillManager == null) {
      return ToolCallResult(
        toolId: 'update_skill',
        content: '',
        success: false,
        error: '技能管理器未初始化',
      );
    }

    final skillId = req.arguments['skill_id']?.toString() ?? '';
    if (skillId.isEmpty) {
      return ToolCallResult(
        toolId: 'update_skill',
        content: '',
        success: false,
        error: '技能 ID 不能为空',
      );
    }

    try {
      // 解析参数定义 JSON
      List<ToolParam>? params;
      final parametersJson = req.arguments['parameters_json']?.toString();
      if (parametersJson != null && parametersJson.isNotEmpty) {
        final decoded = jsonDecode(parametersJson);
        if (decoded is List) {
          params = decoded
              .whereType<Map>()
              .map((e) => ToolParam.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      }

      final updated = await skillManager!.updateSkill(
        skillId,
        name: req.arguments['name']?.toString(),
        description: req.arguments['description']?.toString(),
        content: req.arguments['content']?.toString(),
        parameters: params,
        enabled: req.arguments['enabled'] is bool
            ? req.arguments['enabled'] as bool
            : (req.arguments['enabled']?.toString() == 'true'),
      );

      if (updated == null) {
        return ToolCallResult(
          toolId: 'update_skill',
          content: '',
          success: false,
          error: '未找到技能: $skillId',
        );
      }

      return ToolCallResult(
        toolId: 'update_skill',
        content: '✅ 技能更新成功\n\n'
            'ID: ${updated.id}\n'
            '名称: ${updated.name}\n'
            '描述: ${updated.description}\n'
            '状态: ${updated.enabled ? "已启用" : "已禁用"}',
        success: true,
      );
    } catch (e) {
      return ToolCallResult(
        toolId: 'update_skill',
        content: '',
        success: false,
        error: '技能更新失败: $e',
      );
    }
  }

  // ── 删除技能 ──
  static Future<ToolCallResult> _executeDeleteSkill(ToolCallRequest req) async {
    if (skillManager == null) {
      return ToolCallResult(
        toolId: 'delete_skill',
        content: '',
        success: false,
        error: '技能管理器未初始化',
      );
    }

    final skillId = req.arguments['skill_id']?.toString() ?? '';
    if (skillId.isEmpty) {
      return ToolCallResult(
        toolId: 'delete_skill',
        content: '',
        success: false,
        error: '技能 ID 不能为空',
      );
    }

    try {
      final success = await skillManager!.deleteSkill(skillId);
      if (success) {
        return ToolCallResult(
          toolId: 'delete_skill',
          content: '✅ 技能已删除: $skillId',
          success: true,
        );
      } else {
        return ToolCallResult(
          toolId: 'delete_skill',
          content: '',
          success: false,
          error: '删除失败: 技能不存在',
        );
      }
    } catch (e) {
      return ToolCallResult(
        toolId: 'delete_skill',
        content: '',
        success: false,
        error: '技能删除失败: $e',
      );
    }
  }

  // ── 列出所有技能和工具 ──
  static Future<ToolCallResult> _executeListSkills(ToolCallRequest req) async {
    if (skillManager == null) {
      return ToolCallResult(
        toolId: 'list_skills',
        content: '',
        success: false,
        error: '技能管理器未初始化',
      );
    }

    try {
      final buf = StringBuffer();
      buf.writeln('=== 工具库总览 ===\n');

      // 自定义技能
      final skills = skillManager!.skills;
      buf.writeln('📋 自定义技能 (${skills.length} 个):');
      if (skills.isEmpty) {
        buf.writeln('  (暂无自定义技能)');
      } else {
        for (final s in skills) {
          buf.writeln('  • ${s.name} [${s.id}]');
          buf.writeln('    描述: ${s.description}');
          buf.writeln('    参数: ${s.parameters.length} 个 | 状态: ${s.enabled ? "启用" : "禁用"}');
        }
      }
      buf.writeln();

      // 内置工具
      final builtins = skillManager!.builtinTools;
      buf.writeln('🔧 内置工具 (${builtins.length} 个):');
      for (final t in builtins) {
        buf.writeln('  • ${t.name} [${t.id}]');
      }
      buf.writeln();

      // MCP 工具
      final mcps = skillManager!.mcpTools;
      buf.writeln('🔌 MCP 工具 (${mcps.length} 个):');
      if (mcps.isEmpty) {
        buf.writeln('  (暂无 MCP 工具)');
      } else {
        for (final t in mcps) {
          buf.writeln('  • ${t.name} [${t.id}]');
          buf.writeln('    端点: ${t.endpoint ?? "未配置"}');
        }
      }

      return ToolCallResult(
        toolId: 'list_skills',
        content: buf.toString(),
        success: true,
      );
    } catch (e) {
      return ToolCallResult(
        toolId: 'list_skills',
        content: '',
        success: false,
        error: '列表获取失败: $e',
      );
    }
  }

  // ── 列出本地文章模板 ──
  static Future<ToolCallResult> _executeListTemplates(ToolCallRequest req) async {
    if (storageService == null) {
      return ToolCallResult(
        toolId: 'list_templates',
        content: '',
        success: false,
        error: '本地存储未初始化，无法读取模板',
      );
    }
    try {
      final templates = await storageService!.loadAllTemplates();
      final buf = StringBuffer();
      buf.writeln('=== 文章模板列表 (${templates.length} 个) ===\n');
      for (final t in templates) {
        final tag = t.id.startsWith('builtin_') ? '[内置]' : '[自定义]';
        final type = t.isPost ? '博文' : '页面';
        buf.writeln('$tag ${t.name}  [${t.id}]');
        buf.writeln('  类型: $type | 框架: ${t.frameworkId}');
      }
      buf.writeln('\n提示：内置模板由代码维护不可修改；需要修复模板时用 update_template 以自定义 ID 新建或更新。');
      return ToolCallResult(toolId: 'list_templates', content: buf.toString(), success: true);
    } catch (e) {
      return ToolCallResult(
        toolId: 'list_templates',
        content: '',
        success: false,
        error: '模板列表读取失败: $e',
      );
    }
  }

  // ── 读取单个本地文章模板 ──
  static Future<ToolCallResult> _executeReadTemplate(ToolCallRequest req) async {
    final templateId = req.arguments['template_id']?.toString() ?? '';
    if (storageService == null) {
      return ToolCallResult(
        toolId: 'read_template',
        content: '',
        success: false,
        error: '本地存储未初始化，无法读取模板',
      );
    }
    if (templateId.isEmpty) {
      return ToolCallResult(
        toolId: 'read_template',
        content: '',
        success: false,
        error: 'template_id 不能为空',
      );
    }
    try {
      final templates = await storageService!.loadAllTemplates();
      final t = templates.where((e) => e.id == templateId).firstOrNull;
      if (t == null) {
        return ToolCallResult(
          toolId: 'read_template',
          content: '',
          success: false,
          error: '模板不存在: $templateId（先用 list_templates 查看可用 ID）',
        );
      }
      final type = t.isPost ? '博文' : '页面';
      final buf = StringBuffer();
      buf.writeln('模板: ${t.name}  [${t.id}]');
      buf.writeln('类型: $type | 框架: ${t.frameworkId}');
      buf.writeln('--- FrontMatter 开始 ---');
      buf.writeln(t.frontMatter);
      buf.writeln('--- FrontMatter 结束 ---');
      return ToolCallResult(toolId: 'read_template', content: buf.toString(), success: true);
    } catch (e) {
      return ToolCallResult(
        toolId: 'read_template',
        content: '',
        success: false,
        error: '模板读取失败: $e',
      );
    }
  }

  // ── 新建/更新本地文章模板 ──
  static Future<ToolCallResult> _executeUpdateTemplate(ToolCallRequest req) async {
    if (storageService == null) {
      return ToolCallResult(
        toolId: 'update_template',
        content: '',
        success: false,
        error: '本地存储未初始化，无法保存模板',
      );
    }
    final templateId = req.arguments['template_id']?.toString() ?? '';
    final name = req.arguments['name']?.toString() ?? '';
    final frontMatter = req.arguments['front_matter']?.toString() ?? '';
    final frameworkId = req.arguments['framework_id']?.toString() ?? 'custom';
    final isPost = (req.arguments['is_post']?.toString() ?? 'true').toLowerCase() == 'true';

    if (templateId.isEmpty) {
      return ToolCallResult(
        toolId: 'update_template',
        content: '',
        success: false,
        error: 'template_id 不能为空',
      );
    }
    if (templateId.startsWith('builtin_')) {
      return ToolCallResult(
        toolId: 'update_template',
        content: '',
        success: false,
        error: '内置模板(id 以 builtin_ 开头)由代码维护，无法修改。请改用自定义 ID 新建模板（如 fix_${frameworkId}_post）。',
      );
    }
    if (frontMatter.isEmpty) {
      return ToolCallResult(
        toolId: 'update_template',
        content: '',
        success: false,
        error: 'front_matter 不能为空',
      );
    }
    try {
      final saved = await storageService!.loadTemplates();
      final existing = saved.where((e) => e.id == templateId).firstOrNull;
      final now = DateTime.now();
      final updated = TemplateItem(
        id: templateId,
        name: name.isNotEmpty ? name : (existing?.name ?? templateId),
        frontMatter: frontMatter,
        frameworkId: frameworkId,
        isPost: isPost,
        createdAt: existing?.createdAt ?? now,
      );
      final List<TemplateItem> newList;
      if (existing != null) {
        newList = saved.map((e) => e.id == templateId ? updated : e).toList();
      } else {
        newList = [...saved, updated];
      }
      await storageService!.saveTemplates(newList);
      if (onTemplatesChanged != null) {
        try {
          await onTemplatesChanged!(newList);
        } catch (_) {}
      }
      final action = existing != null ? '已更新' : '已新建';
      return ToolCallResult(
        toolId: 'update_template',
        content: '$action模板 [$templateId]（${updated.name}），框架: $frameworkId，类型: ${isPost ? "博文" : "页面"}。已持久化，可在编辑器模板下拉框中选用。',
        success: true,
      );
    } catch (e) {
      return ToolCallResult(
        toolId: 'update_template',
        content: '',
        success: false,
        error: '模板保存失败: $e',
      );
    }
  }

  // ── 列出仓库文章（含 FrontMatter 片段） ──
  static Future<ToolCallResult> _executeListPosts(ToolCallRequest req) async {
    if (gitHubService == null || activeRepo == null) {
      return ToolCallResult(
        toolId: 'list_posts',
        content: '',
        success: false,
        error: '未配置仓库连接，无法读取文章',
      );
    }
    final path = req.arguments['path']?.toString() ?? '';
    final limit = (int.tryParse(req.arguments['limit']?.toString() ?? '') ?? 10).clamp(1, 20);
    if (path.isNotEmpty) {
      final pathErr = _validatePath(path);
      if (pathErr != null) {
        return ToolCallResult(toolId: 'list_posts', content: '', success: false, error: pathErr);
      }
    }
    try {
      final items = await gitHubService!.listPosts(activeRepo!, path: path.isEmpty ? null : path);
      final buf = StringBuffer();
      buf.writeln('=== 仓库文章列表 (共 ${items.length} 篇，展示前 $limit 篇) ===\n');
      var shown = 0;
      for (final item in items) {
        if (shown >= limit) break;
        shown++;
        buf.writeln('$shown. ${item.name}  (${item.path})');
        try {
          final raw = await gitHubService!.getRawFile(activeRepo!, item.path);
          final fmLines = raw == null ? const <String>[] : _extractFrontMatter(raw['content'] ?? '');
          if (fmLines.isNotEmpty) {
            buf.writeln('   --- FrontMatter 片段 ---');
            for (final l in fmLines) {
              buf.writeln('   $l');
            }
            buf.writeln('   --- 结束 ---');
          } else {
            buf.writeln('   (无 FrontMatter 或格式异常)');
          }
        } catch (e) {
          buf.writeln('   (读取失败: $e)');
        }
        buf.writeln();
      }
      if (items.isEmpty) buf.writeln('(目录中暂无 .md 文章)');
      return ToolCallResult(toolId: 'list_posts', content: buf.toString(), success: true);
    } catch (e) {
      return ToolCallResult(
        toolId: 'list_posts',
        content: '',
        success: false,
        error: '文章列表获取失败: $e',
      );
    }
  }

  /// 提取 Markdown 的 FrontMatter 行（首个 --- 到第二个 --- 之间，最多 40 行）
  static List<String> _extractFrontMatter(String md) {
    final lines = md.split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') return const [];
    final result = <String>[];
    for (var i = 1; i < lines.length && result.length < 40; i++) {
      final line = lines[i];
      if (line.trim() == '---') break;
      result.add(line);
    }
    return result;
  }

  // ── 克隆远程仓库内容 ──
  static Future<ToolCallResult> _executeGitClone(ToolCallRequest req) async {
    final owner = req.arguments['remote_owner']?.toString().trim() ?? '';
    final repo = req.arguments['remote_repo']?.toString().trim() ?? '';
    final branch = req.arguments['remote_branch']?.toString().trim() ?? 'main';
    final remotePath = req.arguments['remote_path']?.toString().trim() ?? '';
    var targetPath = req.arguments['target_path']?.toString().trim() ?? '';
    final commitMsg = req.arguments['commit_message']?.toString().trim() ??
        'AI: clone $owner/$repo/$branch/$remotePath';

    if (owner.isEmpty || repo.isEmpty) {
      return ToolCallResult(toolId: 'git_clone', content: '', success: false, error: 'remote_owner 和 remote_repo 不能为空');
    }

    if (gitHubService == null || activeRepo == null) {
      return ToolCallResult(toolId: 'git_clone', content: '', success: false, error: '未配置仓库连接');
    }

    try {
      final items = await gitHubService!.listRemoteDirContents(
        owner: owner,
        repo: repo,
        branch: branch,
        path: remotePath,
        maxFiles: 200,
      );

      final files = items.where((e) => e.type == 'file').toList();
      if (files.isEmpty) {
        return ToolCallResult(toolId: 'git_clone', content: '', success: false, error: '远程目录中未找到文件');
      }

      // 自动推断目标目录：remotePath 的最后一段，或仓库名
      if (targetPath.isEmpty) {
        targetPath = remotePath.isNotEmpty
            ? remotePath.split('/').last
            : repo;
      }

      var successCount = 0;
      final errors = <String>[];
      for (final file in files) {
        try {
          final content = await gitHubService!.getRemoteRawFile(
            owner: owner,
            repo: repo,
            branch: branch,
            path: file.path,
          );
          if (content == null) {
            errors.add('${file.path}: 无法读取内容');
            continue;
          }
          final relativePath = remotePath.isNotEmpty
              ? file.path.startsWith(remotePath)
                  ? file.path.substring(remotePath.length).replaceFirst(RegExp(r'^/'), '')
                  : file.path;
          final target = '$targetPath/$relativePath'.replaceAll(RegExp(r'/+'), '/');

          String? existingSha;
          try {
            final existing = await gitHubService!.getRawFile(activeRepo!, target);
            existingSha = existing?['sha']?.toString();
          } catch (_) {}

          await gitHubService!.putRawFile(
            activeRepo!,
            target,
            content,
            sha: existingSha,
            commitMessage: commitMsg,
          );
          successCount++;
        } catch (e) {
          errors.add('${file.path}: $e');
        }
      }

      final buf = StringBuffer();
      buf.writeln('克隆完成: 成功 $successCount/${files.length} 个文件');
      buf.writeln('目标目录: $targetPath');
      if (errors.isNotEmpty) {
        buf.writeln('失败 ${errors.length} 个:');
        for (final e in errors.take(5)) {
          buf.writeln('  - $e');
        }
      }
      return ToolCallResult(toolId: 'git_clone', content: buf.toString(), success: true);
    } catch (e) {
      return ToolCallResult(toolId: 'git_clone', content: '', success: false, error: '克隆失败: $e');
    }
  }

  // ── 创建空文件夹 ──
  static Future<ToolCallResult> _executeCreateDir(ToolCallRequest req) async {
    final path = req.arguments['path']?.toString().trim() ?? '';
    final commitMsg = req.arguments['commit_message']?.toString().trim() ??
        'AI: create directory $path';

    if (path.isEmpty) {
      return ToolCallResult(toolId: 'create_dir', content: '', success: false, error: '路径不能为空');
    }
    final pathErr = _validatePath(path);
    if (pathErr != null) {
      return ToolCallResult(toolId: 'create_dir', content: '', success: false, error: pathErr);
    }
    if (gitHubService == null || activeRepo == null) {
      return ToolCallResult(toolId: 'create_dir', content: '', success: false, error: '未配置仓库连接');
    }

    try {
      final gitkeep = '$path/.gitkeep';
      String? existingSha;
      try {
        final existing = await gitHubService!.getRawFile(activeRepo!, gitkeep);
        existingSha = existing?['sha']?.toString();
      } catch (_) {}
      await gitHubService!.putRawFile(
        activeRepo!,
        gitkeep,
        '',
        sha: existingSha,
        commitMessage: commitMsg,
      );
      return ToolCallResult(toolId: 'create_dir', content: '文件夹已创建: $path', success: true);
    } catch (e) {
      return ToolCallResult(toolId: 'create_dir', content: '', success: false, error: '创建文件夹失败: $e');
    }
  }
}