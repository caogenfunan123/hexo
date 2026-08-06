/// 模型探测服务：后台轻量探测各模型响应速度，维护动态优先级队列
library;

import 'ai_model_entity.dart';
import 'ai_model_manager.dart';

/// 模型探测结果
class ProbeResult {
  final String modelId;
  final String apiBase;
  final int latencyMs;
  final bool success;
  final DateTime probedAt;

  const ProbeResult({
    required this.modelId,
    required this.apiBase,
    required this.latencyMs,
    required this.success,
    DateTime? probedAt,
  }) : probedAt = probedAt ?? DateTime.now();
}

/// 模型探测服务：
/// - probeAll: 后台对全部已启用模型发起轻量 ping，统计 RT
/// - getPriorityQueue: 返回按延迟 + 成功率排序的模型优先级队列
class AiModelProbeService {
  final AiModelManager _manager;

  AiModelProbeService(this._manager);

  /// 后台探测所有已启用模型，结果回写 ModelStats
  ///
  /// [ping] 自定义探测函数；默认使用 GET /v1/models 轻量探测。
  /// [concurrency] 并发探测数，默认 2，避免瞬时流量过高。
  Future<List<ProbeResult>> probeAll({
    required Future<bool> Function(AiModelEntity model) ping,
    int concurrency = 2,
  }) async {
    final models = await _manager.getEnabled();
    if (models.isEmpty) return [];

    final results = <ProbeResult>[];
    final queue = List<AiModelEntity>.from(models);
    final working = <Future<void>>[];

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final model = queue.removeAt(0);
        final stopwatch = Stopwatch()..start();
        try {
          final ok = await ping(model);
          stopwatch.stop();
          results.add(ProbeResult(
            modelId: model.modelId,
            apiBase: model.apiBase,
            latencyMs: stopwatch.elapsedMilliseconds,
            success: ok,
          ));
          await _manager.recordCall(
            model.modelId,
            model.apiBase,
            stopwatch.elapsedMilliseconds,
            ok,
          );
        } catch (e) {
          stopwatch.stop();
          results.add(ProbeResult(
            modelId: model.modelId,
            apiBase: model.apiBase,
            latencyMs: stopwatch.elapsedMilliseconds,
            success: false,
          ));
          await _manager.recordCall(
            model.modelId,
            model.apiBase,
            stopwatch.elapsedMilliseconds,
            false,
          );
        }
      }
    }

    final count = concurrency.clamp(1, models.length);
    for (var i = 0; i < count; i++) {
      working.add(worker());
    }
    await Future.wait(working);
    return results;
  }

  /// 获取模型优先级队列（用于自动择优）
  ///
  /// [autoOptimal] 为 true 时按延迟 + 成功率排序，否则仅按用户优先级。
  /// [fixedModel] 指定后仅返回该模型（手动固定模式）。
  Future<List<AiModelEntity>> getPriorityQueue({
    bool autoOptimal = true,
    AiModelEntity? fixedModel,
    String? group,
  }) async {
    if (fixedModel != null) return [fixedModel];

    final models = await _manager.getEnabled(group: group);
    if (!autoOptimal) return models;

    final stats = await _manager.loadStats();
    // 按综合得分排序：延迟越低、成功率越高、用户优先级越高，越靠前
    models.sort((a, b) {
      final aScore = _score(a, stats);
      final bScore = _score(b, stats);
      if (aScore != bScore) return aScore.compareTo(bScore);
      return b.priority.compareTo(a.priority);
    });
    return models;
  }

  /// 综合评分：值越小越优
  static double _score(AiModelEntity model, Map<String, ModelStats> stats) {
    final stat = stats['${model.apiBase}|${model.modelId}'];
    if (stat == null || stat.totalCalls == 0) {
      return 1e9 - model.priority; // 无样本时按用户优先级
    }
    final latencyFactor = stat.avgDurationMs / 1000.0; // 平均耗时（秒）
    final failFactor = (1 - stat.successRate) * 10; // 失败惩罚
    final priorityFactor = -model.priority * 0.1; // 用户手动优先级微调
    return latencyFactor + failFactor + priorityFactor;
  }

  /// 获取模型最近探测状态
  Future<ModelStats?> statsFor(String modelId, String apiBase) {
    return _manager.getStatsFor(modelId, apiBase);
  }
}
