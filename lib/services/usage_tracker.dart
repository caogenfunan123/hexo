/// Token 用量统计：记录每次 AI 调用的 token 消耗并持久化，
/// 提供按模型 / 按天聚合（对标 MonkeyCode backend/biz/llmproxy/usage_capture.go）。

import 'dart:convert';
import 'dart:io';

/// 单次调用的 token 用量记录
class TokenUsage {
  final String id;
  final DateTime time;
  final String model;
  final String provider;       // interfaceType：openaiChat / openaiResponses / anthropic
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheCreationTokens;
  final int reasoningTokens;
  final bool usedTools;
  final String? sessionType;   // 会话类型（写作 / 工具 / 巡检等）

  const TokenUsage({
    required this.id,
    required this.time,
    required this.model,
    this.provider = 'openaiChat',
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheCreationTokens = 0,
    this.reasoningTokens = 0,
    this.usedTools = false,
    this.sessionType,
  });

  int get totalTokens => inputTokens + outputTokens + cacheReadTokens;

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time.toIso8601String(),
        'model': model,
        'provider': provider,
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        'cacheReadTokens': cacheReadTokens,
        'cacheCreationTokens': cacheCreationTokens,
        'reasoningTokens': reasoningTokens,
        'usedTools': usedTools,
        'sessionType': sessionType,
      };

  factory TokenUsage.fromJson(Map<String, dynamic> j) => TokenUsage(
        id: j['id']?.toString() ?? '',
        time: DateTime.tryParse(j['time']?.toString() ?? '') ?? DateTime.now(),
        model: j['model']?.toString() ?? '',
        provider: j['provider']?.toString() ?? 'openaiChat',
        inputTokens: (j['inputTokens'] as num?)?.toInt() ?? 0,
        outputTokens: (j['outputTokens'] as num?)?.toInt() ?? 0,
        cacheReadTokens: (j['cacheReadTokens'] as num?)?.toInt() ?? 0,
        cacheCreationTokens: (j['cacheCreationTokens'] as num?)?.toInt() ?? 0,
        reasoningTokens: (j['reasoningTokens'] as num?)?.toInt() ?? 0,
        usedTools: j['usedTools'] == true,
        sessionType: j['sessionType']?.toString(),
      );
}

/// 从 OpenAI / Anthropic 响应 body 中抽取 usage
class UsageParser {
  static Map<String, dynamic> fromOpenAiChat(Map data) {
    final u = data['usage'];
    if (u is! Map) return const {};
    final detail = u['prompt_tokens_details'] as Map? ?? const {};
    final compDetail = u['completion_tokens_details'] as Map? ?? const {};
    return {
      'inputTokens': (u['prompt_tokens'] as num?)?.toInt() ?? 0,
      'outputTokens': (u['completion_tokens'] as num?)?.toInt() ?? 0,
      'cacheReadTokens': (detail['cached_tokens'] as num?)?.toInt() ?? 0,
      'reasoningTokens': (compDetail['reasoning_tokens'] as num?)?.toInt() ?? 0,
    };
  }

  static Map<String, dynamic> fromOpenAiResponses(Map data) {
    final u = data['usage'];
    if (u is! Map) return const {};
    final inDetail = u['input_tokens_details'] as Map? ?? const {};
    return {
      'inputTokens': (u['input_tokens'] as num?)?.toInt() ?? 0,
      'outputTokens': (u['output_tokens'] as num?)?.toInt() ?? 0,
      'cacheReadTokens': (inDetail['cached_tokens'] as num?)?.toInt() ?? 0,
    };
  }

  static Map<String, dynamic> fromAnthropic(Map data) {
    final u = data['usage'];
    if (u is! Map) return const {};
    return {
      'inputTokens': (u['input_tokens'] as num?)?.toInt() ?? 0,
      'outputTokens': (u['output_tokens'] as num?)?.toInt() ?? 0,
      'cacheReadTokens': (u['cache_read_input_tokens'] as num?)?.toInt() ?? 0,
      'cacheCreationTokens':
          (u['cache_creation_input_tokens'] as num?)?.toInt() ?? 0,
    };
  }
}

/// Token 用量聚合结果
class UsageAggregate {
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheCreationTokens;
  final int callCount;

  const UsageAggregate({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheCreationTokens = 0,
    this.callCount = 0,
  });

  int get totalTokens => inputTokens + outputTokens + cacheReadTokens;

  UsageAggregate operator +(UsageAggregate o) => UsageAggregate(
        inputTokens: inputTokens + o.inputTokens,
        outputTokens: outputTokens + o.outputTokens,
        cacheReadTokens: cacheReadTokens + o.cacheReadTokens,
        cacheCreationTokens: cacheCreationTokens + o.cacheCreationTokens,
        callCount: callCount + o.callCount,
      );
}

/// Token 用量追踪器：持久化 + 聚合
class UsageTracker {
  static const _usageFile = 'ai_usage.json';
  static const maxRecords = 5000; // 环形裁剪，防止无限增长

  final Directory _root;

  UsageTracker(this._root);

  /// 记录一次调用用量
  Future<void> record(TokenUsage usage) async {
    final all = await loadAll();
    all.add(usage);
    if (all.length > maxRecords) {
      all.removeRange(0, all.length - maxRecords);
    }
    await _save(all);
  }

  /// 批量记录
  Future<void> recordAll(List<TokenUsage> usages) async {
    if (usages.isEmpty) return;
    final all = await loadAll();
    all.addAll(usages);
    if (all.length > maxRecords) {
      all.removeRange(0, all.length - maxRecords);
    }
    await _save(all);
  }

  Future<List<TokenUsage>> loadAll() async {
    try {
      final f = File('${_root.path}/$_usageFile');
      if (!await f.exists()) return [];
      final text = await f.readAsString();
      if (text.trim().isEmpty) return [];
      final data = jsonDecode(text);
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => TokenUsage.fromJson(Map<String, dynamic>.from(e)))
            .toList()
          ..sort((a, b) => b.time.compareTo(a.time));
      }
    } catch (_) {}
    return [];
  }

  Future<void> _save(List<TokenUsage> usages) async {
    final f = File('${_root.path}/$_usageFile');
    await f.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        usages.map((u) => u.toJson()).toList(),
      ),
    );
  }

  /// 总体聚合
  Future<UsageAggregate> aggregateAll() async {
    final all = await loadAll();
    return all.fold<UsageAggregate>(const UsageAggregate(), (acc, u) {
      return acc +
          UsageAggregate(
            inputTokens: u.inputTokens,
            outputTokens: u.outputTokens,
            cacheReadTokens: u.cacheReadTokens,
            cacheCreationTokens: u.cacheCreationTokens,
            callCount: 1,
          );
    });
  }

  /// 按模型聚合
  Future<Map<String, UsageAggregate>> aggregateByModel() async {
    final all = await loadAll();
    final map = <String, UsageAggregate>{};
    for (final u in all) {
      map[u.model] = (map[u.model] ?? const UsageAggregate()) +
          UsageAggregate(
            inputTokens: u.inputTokens,
            outputTokens: u.outputTokens,
            cacheReadTokens: u.cacheReadTokens,
            cacheCreationTokens: u.cacheCreationTokens,
            callCount: 1,
          );
    }
    return map;
  }

  /// 近 N 天按天聚合
  Future<List<(DateTime, UsageAggregate)>> aggregateByDay(int days) async {
    final all = await loadAll();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(
      Duration(days: days - 1),
    );
    final map = <String, UsageAggregate>{};
    for (final u in all) {
      if (u.time.isBefore(start)) continue;
      final day = DateTime(u.time.year, u.time.month, u.time.day);
      final key = day.toIso8601String().substring(0, 10);
      map[key] = (map[key] ?? const UsageAggregate()) +
          UsageAggregate(
            inputTokens: u.inputTokens,
            outputTokens: u.outputTokens,
            cacheReadTokens: u.cacheReadTokens,
            cacheCreationTokens: u.cacheCreationTokens,
            callCount: 1,
          );
    }
    final out = <(DateTime, UsageAggregate)>[];
    for (var i = 0; i < days; i++) {
      final day = start.add(Duration(days: i));
      final key = day.toIso8601String().substring(0, 10);
      out.add((day, map[key] ?? const UsageAggregate()));
    }
    return out;
  }
}
