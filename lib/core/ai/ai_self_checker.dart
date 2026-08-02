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

      return SelfCheckResult.fromResponse(result);
    } catch (e) {
      return SelfCheckResult(
        level: CheckLevel.warning,
        message: '自检执行异常: $e',
        issues: ['自检服务不可用，请手动检查代码'],
      );
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