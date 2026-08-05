import 'dart:convert';
import 'dart:io';

import '../../models/app_settings.dart';
import '../../models/design_config.dart';
import '../../services/github_service.dart';
import '../../models/repo_config.dart';
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
      final items = await gitHubService!.listPosts(activeRepo!, path: path.isEmpty ? null : path);
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
}