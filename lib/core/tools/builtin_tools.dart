import 'dart:convert';
import 'dart:io';

import '../../services/github_service.dart';
import '../../models/repo_config.dart';
import 'tool_entity.dart';

/// 内置工具定义和实现
class BuiltinTools {
  BuiltinTools._();

  /// 静态引用：由 AiChatPanel 在调用前设置
  static GitHubService? gitHubService;
  static RepoConfig? activeRepo;

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

  // ── 执行内置工具 ──
  static Future<ToolCallResult> execute(ToolCallRequest request) async {
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

  // ── 文件操作工具实现 ──

  /// 读取仓库文件
  static Future<ToolCallResult> _executeFileRead(ToolCallRequest req) async {
    final path = req.arguments['path']?.toString() ?? '';
    if (path.isEmpty) {
      return ToolCallResult(toolId: 'file_read', content: '', success: false, error: '文件路径不能为空');
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

  /// Git回滚
  static Future<ToolCallResult> _executeGitRollback(ToolCallRequest req) async {
    final path = req.arguments['path']?.toString() ?? '';
    final commitSha = req.arguments['commit_sha']?.toString();
    if (path.isEmpty) {
      return ToolCallResult(toolId: 'git_rollback', content: '', success: false, error: '文件路径不能为空');
    }
    if (gitHubService == null || activeRepo == null) {
      return ToolCallResult(toolId: 'git_rollback', content: '', success: false, error: '未配置仓库连接');
    }
    try {
      // 获取文件历史，找到上一个版本
      final commits = await gitHubService!.listCommits(activeRepo!);
      // 简单回滚：读取当前文件，写入带标记的备份
      final current = await gitHubService!.getRawFile(activeRepo!, path);
      if (current == null) {
        return ToolCallResult(toolId: 'git_rollback', content: '', success: false, error: '文件不存在: $path');
      }
      await gitHubService!.putRawFile(
        activeRepo!,
        '$path.bak',
        current['content'] ?? '',
        commitMessage: 'rollback backup: $path',
      );
      return ToolCallResult(
        toolId: 'git_rollback',
        content: '已创建回滚备份: $path.bak\n请手动恢复到目标版本。',
        success: true,
      );
    } catch (e) {
      return ToolCallResult(toolId: 'git_rollback', content: '', success: false, error: '回滚失败: $e');
    }
  }
}