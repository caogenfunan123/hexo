import '../../models/app_settings.dart';
import '../../services/ai_service.dart';
import 'ai_session_manager.dart';

/// AI 生成内容后自动自检系统
class AiSelfChecker {
  final AiService _aiService;

  AiSelfChecker(this._aiService);

  /// 对 AI 输出内容进行自检
  /// 返回自检结果
  Future<SelfCheckResult> check({
    required AppSettings settings,
    required String generatedContent,
    required AiSessionType sessionType,
    String? blogFramework,
  }) async {
    // 文章类会话且不含文件操作指令时，只做本地完整性检查，
    // 不调用面向源码的 AI 深度自检（源码自检会对普通文章正文误判）
    if ((sessionType == AiSessionType.article ||
            sessionType == AiSessionType.page) &&
        !generatedContent.contains('【文件路径】')) {
      return _checkArticleContent(generatedContent);
    }

    // 先做本地快速检查
    final localIssues = _localCheck(generatedContent, blogFramework: blogFramework);

    // 只有本地检查发现严重错误（❌）时才跳过AI深度检查
    final hasError = localIssues.any((i) => i.startsWith('❌'));
    if (hasError) {
      return SelfCheckResult(
        level: CheckLevel.error,
        message: '本地检查发现严重错误，需先修复',
        issues: localIssues,
      );
    }

    try {
      final prompt = AiSessionManager.selfCheckPrompt;
      final userPrompt = '''
请检查以下生成内容：

会话类型：${sessionType.name}
博客框架：${blogFramework ?? '未指定'}

=== 生成内容 ===
$generatedContent
=== 结束 ===
''';

      final result = await _aiService.complete(
        settings: settings,
        systemPrompt: prompt,
        userPrompt: userPrompt,
        temperature: 0.3,
      );

      final aiResult = SelfCheckResult.fromResponse(result);
      // 合并本地警告到AI结果
      final mergedIssues = [...localIssues, ...aiResult.issues];
      return SelfCheckResult(
        level: aiResult.level,
        message: aiResult.message,
        issues: mergedIssues,
      );
    } catch (e) {
      return SelfCheckResult(
        level: CheckLevel.warning,
        message: '自检执行异常: $e',
        issues: [...localIssues, '自检服务不可用，请手动检查代码'],
      );
    }
  }

  /// 文章内容的本地完整性检查（无需 AI 调用）
  ///
  /// 仅拦截空正文 / 明显异常的情况，避免源码类 AI 自检对普通文章误判。
  static SelfCheckResult _checkArticleContent(String content) {
    final text = content.trim();
    if (text.isEmpty) {
      return const SelfCheckResult(
        level: CheckLevel.error,
        message: '正文为空，无法发布空文章',
        issues: ['❌ 正文为空，请先输入文章内容再发布'],
      );
    }
    return const SelfCheckResult(
      level: CheckLevel.pass,
      message: '自检完成，正文内容完整，可正常发布',
    );
  }

  /// 本地快速检查（无需 AI 调用）
  static List<String> _localCheck(String content, {String? blogFramework}) {
    final issues = <String>[];

    // 1. HTML 标签闭合检查
    _checkHtmlTags(content, issues);

    // 2. CSS url() 路径检查
    _checkCssPaths(content, issues);

    // 3. YAML/TOML 格式检查
    _checkConfigFormat(content, issues);

    // 4. Markdown 代码块闭合检查
    _checkCodeBlockClosure(content, issues);

    // 5. EJS 模板标签闭合检查
    _checkEJSTags(content, issues);

    // 6. 文件路径引用检查
    _checkFileReferences(content, issues);

    return issues;
  }

  static void _checkHtmlTags(String content, List<String> issues) {
    final openTags = <String>[];
    final tagRegex = RegExp(r'</?(\w+)[^>]*>');
    final selfClosing = {'br', 'hr', 'img', 'input', 'meta', 'link', 'area', 'base', 'col', 'embed', 'source', 'track', 'wbr'};

    for (final match in tagRegex.allMatches(content)) {
      final fullTag = match.group(0)!;
      final tagName = match.group(1)!.toLowerCase();
      if (selfClosing.contains(tagName)) continue;
      if (fullTag.startsWith('</')) {
        if (openTags.isEmpty || openTags.last != tagName) {
          if (openTags.contains(tagName)) {
            issues.add('⚠️ HTML 标签闭合顺序异常: <$tagName> 与 </${openTags.last}> 交叉');
          } else {
            issues.add('⚠️ 多余的闭合标签: </$tagName>');
          }
        } else {
          openTags.removeLast();
        }
      } else if (!fullTag.endsWith('/>')) {
        openTags.add(tagName);
      }
    }
    for (final tag in openTags) {
      issues.add('⚠️ 未闭合的 HTML 标签: <$tag>');
    }
  }

  static void _checkCssPaths(String content, List<String> issues) {
    // 检查 CSS url() 中引用的路径
    final urlRegex = RegExp(r'''url\(['"]?([^'"()]+)['"]?\)''');
    for (final match in urlRegex.allMatches(content)) {
      final path = match.group(1)!.trim();
      if (path.startsWith('http') || path.startsWith('data:')) continue;
      if (path.contains('..')) {
        issues.add('⚠️ CSS 路径使用了相对上级目录: $path');
      }
      if (path.startsWith('/') && !path.startsWith('/assets/') && !path.startsWith('/images/') && !path.startsWith('/css/') && !path.startsWith('/js/')) {
        issues.add('⚠️ CSS 绝对路径可能不正确: $path');
      }
    }
  }

  static void _checkConfigFormat(String content, List<String> issues) {
    // 检查 YAML 缩进一致性
    final yamlLines = <String>[];
    bool inYaml = false;
    for (final line in content.split('\n')) {
      if (line.trim() == '---') {
        inYaml = !inYaml;
        continue;
      }
      if (inYaml) yamlLines.add(line);
    }

    // 检查 YAML 中使用 Tab 缩进
    for (final line in yamlLines) {
      if (line.startsWith('\t')) {
        issues.add('⚠️ YAML 配置中使用了 Tab 缩进，应使用空格');
        break;
      }
    }

    // 检查 TOML 格式
    if (content.contains('+++') || content.contains('[dependencies]')) {
      final tomlKeyVal = RegExp(r'^\s*(\w+)\s*=\s*(.+)$', multiLine: true);
      for (final match in tomlKeyVal.allMatches(content)) {
        final val = match.group(2)!.trim();
        if ((val.startsWith('"') && !val.endsWith('"')) || (val.startsWith("'") && !val.endsWith("'"))) {
          issues.add('⚠️ TOML 字符串值引号不匹配: ${match.group(1)} = $val');
        }
      }
    }
  }

  static void _checkCodeBlockClosure(String content, List<String> issues) {
    int openBlocks = 0;
    for (final line in content.split('\n')) {
      if (line.trim().startsWith('```')) {
        if (openBlocks == 0) {
          openBlocks++;
        } else {
          openBlocks--;
        }
      }
    }
    if (openBlocks > 0) {
      issues.add('⚠️ 代码块未闭合: 有 $openBlocks 个 \`\`\` 未匹配');
    }
  }

  static void _checkEJSTags(String content, List<String> issues) {
    // 检查 EJS 标签闭合
    int depth = 0;
    for (final line in content.split('\n')) {
      final opens = '<%'.allMatches(line).length;
      final closes = '%>'.allMatches(line).length;
      depth += opens - closes;
      if (depth < 0) {
        issues.add('⚠️ EJS 模板标签闭合异常: 多余的 %>');
        depth = 0;
      }
    }
    if (depth > 0) {
      issues.add('⚠️ EJS 模板标签未闭合: 缺少 $depth 个 %>');
    }
  }

  static void _checkFileReferences(String content, List<String> issues) {
    // 检查引用的文件路径
    final refRegex = RegExp(r"""(?:src|href|include|extends|layout)\s*[=:]\s*['\"]([^'\"]+)['\"]""");
    final seenPaths = <String>{};
    for (final match in refRegex.allMatches(content)) {
      final path = match.group(1)!.trim();
      if (path.contains('../') || path.contains('..\\')) {
        issues.add('⚠️ 文件引用使用了上级目录: $path');
      }
      if (path.contains('\\')) {
        issues.add('⚠️ 文件路径使用了反斜杠（Windows 风格）: $path');
      }
      seenPaths.add(path);
    }
  }
}

enum CheckLevel { pass, warning, error }

class SelfCheckResult {
  final CheckLevel level;
  final String message;
  final List<String> issues;

  const SelfCheckResult({
    required this.level,
    required this.message,
    this.issues = const [],
  });

  factory SelfCheckResult.fromResponse(String response) {
    final r = response.trim();
    if (r.contains('检测通过') || r.contains('未发现明显问题')) {
      return SelfCheckResult(
        level: CheckLevel.pass,
        message: '自检完成，未发现明显问题，请推送远端仓库构建测试',
      );
    } else if (r.contains('严重错误') || r.contains('❌')) {
      return SelfCheckResult(
        level: CheckLevel.error,
        message: r,
        issues: _extractIssues(r),
      );
    } else {
      return SelfCheckResult(
        level: CheckLevel.warning,
        message: r,
        issues: _extractIssues(r),
      );
    }
  }

  static List<String> _extractIssues(String text) {
    final issues = <String>[];
    for (final line in text.split('\n')) {
      final t = line.trim();
      if (t.startsWith('❌') || t.startsWith('⚠️') || t.startsWith('-')) {
        issues.add(t);
      }
    }
    return issues;
  }

  bool get isPassed => level == CheckLevel.pass;
  bool get hasError => level == CheckLevel.error;
}