import 'dart:convert';
import 'dart:io';

import '../../services/storage_service.dart';
import 'ai_model_entity.dart';
import 'ai_provider.dart';

/// AI 模型管理器：批量拉取中转站模型、本地持久化 CRUD
class AiModelManager {
  final StorageService _storage;
  static const _modelsFile = 'ai_models.json';

  AiModelManager(this._storage);

  Future<List<AiModelEntity>> loadAll() async {
    try {
      final f = File('${(await _storage.root).path}/$_modelsFile');
      if (!await f.exists()) return [];
      final text = await f.readAsString();
      if (text.trim().isEmpty) return [];
      final list = jsonDecode(text);
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => AiModelEntity.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<AiModelEntity> models) async {
    final f = File('${(await _storage.root).path}/$_modelsFile');
    await f.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        models.map((e) => e.toJson()).toList(),
      ),
    );
  }

  Future<List<AiModelEntity>> getEnabled({String? group}) async {
    final all = await loadAll();
    var filtered = all.where((m) => m.enable).toList();
    if (group != null) {
      filtered = filtered.where((m) => m.group == group).toList();
    }
    filtered.sort((a, b) => b.priority.compareTo(a.priority));
    return filtered;
  }

  Future<void> addModel(AiModelEntity model) async {
    final all = await loadAll();
    // 去重：同 modelId + apiBase 只保留一份
    all.removeWhere(
        (m) => m.modelId == model.modelId && m.apiBase == model.apiBase);
    all.add(model);
    await saveAll(all);
  }

  Future<void> updateModel(AiModelEntity model) async {
    final all = await loadAll();
    final idx = all.indexWhere(
        (m) => m.modelId == model.modelId && m.apiBase == model.apiBase);
    if (idx >= 0) {
      all[idx] = model;
    } else {
      all.add(model);
    }
    await saveAll(all);
  }

  Future<void> deleteModel(String modelId, String apiBase) async {
    final all = await loadAll();
    all.removeWhere((m) => m.modelId == modelId && m.apiBase == apiBase);
    await saveAll(all);
  }

  Future<void> toggleModel(String modelId, String apiBase, bool enable) async {
    final all = await loadAll();
    for (final m in all) {
      if (m.modelId == modelId && m.apiBase == apiBase) {
        final idx = all.indexOf(m);
        all[idx] = m.copyWith(enable: enable);
        break;
      }
    }
    await saveAll(all);
  }

  Future<void> batchImport(List<AiModelEntity> models) async {
    final all = await loadAll();
    for (final model in models) {
      all.removeWhere(
          (m) => m.modelId == model.modelId && m.apiBase == model.apiBase);
      all.add(model);
    }
    await saveAll(all);
  }

  Future<List<AiModelEntity>> exportModels() async {
    return await loadAll();
  }

  String exportToJson(List<AiModelEntity> models) {
    return const JsonEncoder.withIndent('  ').convert(
      models.map((e) => e.toJson()).toList(),
    );
  }

  List<AiModelEntity> importFromJson(String json) {
    final list = jsonDecode(json);
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => AiModelEntity.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ── 响应速度统计 ──

  static const _statsFile = 'ai_model_stats.json';

  Future<Map<String, ModelStats>> loadStats() async {
    try {
      final f = File('${(await _storage.root).path}/$_statsFile');
      if (!await f.exists()) return {};
      final text = await f.readAsString();
      if (text.trim().isEmpty) return {};
      final list = jsonDecode(text);
      if (list is! List) return {};
      final map = <String, ModelStats>{};
      for (final e in list) {
        if (e is Map) {
          final s = ModelStats.fromJson(Map<String, dynamic>.from(e));
          map['${s.apiBase}|${s.modelId}'] = s;
        }
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveStats(Map<String, ModelStats> stats) async {
    final f = File('${(await _storage.root).path}/$_statsFile');
    await f.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        stats.values.map((e) => e.toJson()).toList(),
      ),
    );
  }

  Future<ModelStats?> getStatsFor(String modelId, String apiBase) async {
    final stats = await loadStats();
    return stats['$apiBase|$modelId'];
  }

  Future<void> recordCall(
      String modelId, String apiBase, int durationMs, bool success) async {
    final stats = await loadStats();
    final key = '$apiBase|$modelId';
    final existing = stats[key];
    stats[key] = (existing ?? ModelStats(modelId: modelId, apiBase: apiBase))
        .recordCall(durationMs, success);
    await saveStats(stats);
  }

  /// 按 Provider 拉取模型列表（对标 MonkeyCode GetProviderModelList）
  /// - OpenAI 兼容系列: GET {base}/models
  /// - Ollama: GET {base}/api/tags
  Future<List<String>> getProviderModelList({
    required ModelProvider provider,
    required String baseUrl,
    required String apiKey,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      var base = baseUrl.trim();
      while (base.endsWith('/')) base = base.substring(0, base.length - 1);

      if (provider == ModelProvider.ollama) {
        final uri = Uri.parse('$base/api/tags');
        final req = await client.getUrl(uri);
        final res = await req.close().timeout(timeout);
        final text = await res.transform(utf8.decoder).join().timeout(timeout);
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw Exception('HTTP ${res.statusCode}: $text');
        }
        final data = jsonDecode(text);
        final models = data['models'] as List? ?? [];
        return models
            .map((m) {
              final name = (m as Map)['name']?.toString() ?? '';
              return name;
            })
            .where((n) => n.isNotEmpty)
            .toList()
          ..sort();
      }

      final uri = Uri.parse('$base/models');
      final req = await client.getUrl(uri);
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Accept', 'application/json');
      if (apiKey.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $apiKey');
      }
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join().timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('HTTP ${res.statusCode}: $text');
      }
      final data = jsonDecode(text);
      final items = data['data'] as List? ?? data['models'] as List? ?? [];
      return items
          .map((m) {
            if (m is Map && m['id'] != null) return m['id'].toString();
            return m.toString();
          })
          .where((n) => n.isNotEmpty)
          .toList()
        ..sort();
    } finally {
      client.close(force: true);
    }
  }

  /// 批量拉取中转站模型列表
  Future<List<AiModelEntity>> fetchModelsFromProxy({
    required String apiBase,
    required String apiKey,
    String? apiPath,
    bool useBearer = true,
    String group = 'general',
    Future<List<String>> Function({
      required String baseUrl,
      required String apiKey,
      String? apiPath,
      bool? useBearer,
    })? fetcher,
  }) async {
    if (fetcher != null) {
      final ids = await fetcher(
        baseUrl: apiBase,
        apiKey: apiKey,
        apiPath: apiPath,
        useBearer: useBearer,
      );
      return ids
          .map((id) => AiModelEntity(
                modelId: id,
                modelName: id,
                apiBase: apiBase,
                apiKey: apiKey,
                apiPath: apiPath,
                useBearer: useBearer,
                group: group,
              ))
          .toList();
    }
    // 默认：尝试从 /v1/models 端点拉取模型列表
    try {
      final uri = Uri.parse('$apiBase${apiPath ?? '/v1/models'}');
      final client = HttpClient();
      try {
        final req = await client.getUrl(uri);
        req.headers.set('Content-Type', 'application/json');
        if (useBearer) {
          req.headers.set('Authorization', 'Bearer $apiKey');
        } else {
          req.headers.set('Authorization', 'ApiKey $apiKey');
        }
        final res = await req.close();
        if (res.statusCode == 200) {
          final body = await res.transform(utf8.decoder).join();
          final data = jsonDecode(body) as Map<String, dynamic>;
          final models = data['data'] as List?;
          if (models != null) {
            return models.map((m) {
              final id = (m as Map<String, dynamic>)['id']?.toString() ?? '';
              return AiModelEntity(
                modelId: id,
                modelName: id,
                apiBase: apiBase,
                apiKey: apiKey,
                apiPath: apiPath,
                useBearer: useBearer,
                group: group,
              );
            }).toList();
          }
        }
      } finally {
        client.close();
      }
    } catch (_) {
      // 降级：返回空列表，不抛异常
    }
    return [];
  }

  // ── 连通性检测（CheckByConfig，对标 MonkeyCode llm.HealthCheck） ──

  /// 校验一组模型配置的连通性（添加前验证 base_url + api_key + model 是否可用）。
  /// 支持 openai_chat / openai_responses / anthropic 三种接口协议。
  /// 返回校验结果；不修改本地存储。
  Future<ModelCheckResult> checkByConfig({
    required String baseUrl,
    required String apiKey,
    required String model,
    InterfaceType interfaceType = InterfaceType.openaiChat,
    Duration timeout = const Duration(seconds: 30),
    bool useBearer = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      await _pingModel(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        interfaceType: interfaceType,
        timeout: timeout,
        useBearer: useBearer,
      );
      stopwatch.stop();
      return ModelCheckResult(
          success: true, durationMs: stopwatch.elapsedMilliseconds);
    } catch (e) {
      stopwatch.stop();
      return ModelCheckResult(
        success: false,
        error: e.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  Future<void> _pingModel({
    required String baseUrl,
    required String apiKey,
    required String model,
    required InterfaceType interfaceType,
    required Duration timeout,
    bool useBearer = false,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      var base = baseUrl.trim();
      while (base.endsWith('/')) base = base.substring(0, base.length - 1);
      base = base
          .replaceAll(RegExp(r'/chat/completions$'), '')
          .replaceAll(RegExp(r'/responses$'), '')
          .replaceAll(RegExp(r'/messages$'), '')
          .replaceAll(RegExp(r'/v\d+/chat/completions$'), '')
          .replaceAll(RegExp(r'/v\d+/responses$'), '')
          .replaceAll(RegExp(r'/v\d+/messages$'), '');
      final uri = switch (interfaceType) {
        InterfaceType.anthropic => Uri.parse('$base/messages'),
        InterfaceType.openaiResponses => Uri.parse('$base/responses'),
        InterfaceType.openaiChat => Uri.parse('$base/chat/completions'),
      };
      final body = switch (interfaceType) {
        InterfaceType.anthropic => {
            'model': model,
            'max_tokens': 1,
            'messages': [
              {'role': 'user', 'content': 'hi'},
            ],
          },
        InterfaceType.openaiResponses => {
            'model': model,
            'max_output_tokens': 1,
            'input': [
              {'role': 'user', 'content': 'hi'},
            ],
          },
        InterfaceType.openaiChat => {
            'model': model,
            'messages': [
              {'role': 'user', 'content': 'hi'},
            ],
            'max_tokens': 1,
          },
      };

      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Accept', 'application/json');
      if (interfaceType == InterfaceType.anthropic) {
        if (useBearer) {
          req.headers.set('Authorization', 'Bearer $apiKey');
        } else {
          req.headers.set('x-api-key', apiKey);
        }
        req.headers.set('anthropic-version', '2023-06-01');
      } else if (useBearer) {
        req.headers.set('Authorization', 'Bearer $apiKey');
      } else {
        req.headers.set('Authorization', apiKey);
        req.headers.set('api-key', apiKey);
        req.headers.set('x-api-key', apiKey);
      }
      final bytes = utf8.encode(jsonEncode(body));
      req.contentLength = bytes.length;
      req.add(bytes);
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join().timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        // 提取上游错误信息（部分服务商返回 {error:{message}}）
        String detail = text.length > 300 ? text.substring(0, 300) : text;
        try {
          final data = jsonDecode(text);
          if (data is Map && data['error'] is Map) {
            final msg = (data['error'] as Map)['message']?.toString();
            if (msg != null && msg.isNotEmpty) detail = msg;
          }
        } catch (_) {}
        throw Exception('HTTP ${res.statusCode}: $detail');
      }
    } finally {
      client.close(force: true);
    }
  }

  /// 更新某模型的连通性检查结果（对标 MonkeyCode UpdateCheckResult）
  Future<void> updateCheckResult(
    String modelId,
    String apiBase,
    ModelCheckResult result,
  ) async {
    await _saveCheckState(modelId, apiBase, result.toJson());
  }

  static const _checkFile = 'ai_model_checks.json';

  Future<void> _saveCheckState(
      String modelId, String apiBase, Map<String, dynamic> check) async {
    final f = File('${(await _storage.root).path}/$_checkFile');
    Map<String, dynamic> all = {};
    if (await f.exists()) {
      try {
        final data = jsonDecode(await f.readAsString());
        if (data is Map) all = Map<String, dynamic>.from(data);
      } catch (_) {}
    }
    all['$apiBase|$modelId'] = check;
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(all));
  }

  Future<ModelCheckResult?> getCheckResult(
      String modelId, String apiBase) async {
    try {
      final f = File('${(await _storage.root).path}/$_checkFile');
      if (!await f.exists()) return null;
      final data = jsonDecode(await f.readAsString());
      if (data is Map && data['$apiBase|$modelId'] is Map) {
        return ModelCheckResult.fromJson(
          Map<String, dynamic>.from(data['$apiBase|$modelId'] as Map),
        );
      }
    } catch (_) {}
    return null;
  }
}

/// 健康检查结果（连通性检测，对标 MonkeyCode llm.HealthCheck）
class ModelCheckResult {
  final bool success;
  final String? error;
  final DateTime checkedAt;
  final int durationMs;

  ModelCheckResult({
    required this.success,
    this.error,
    DateTime? checkedAt,
    this.durationMs = 0,
  }) : checkedAt = checkedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'success': success,
        if (error != null) 'error': error,
        'checkedAt': checkedAt.toIso8601String(),
        'durationMs': durationMs,
      };

  factory ModelCheckResult.fromJson(Map<String, dynamic> j) => ModelCheckResult(
        success: j['success'] == true,
        error: j['error']?.toString(),
        checkedAt: DateTime.tryParse(j['checkedAt']?.toString() ?? '') ??
            DateTime.now(),
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
      );
}
