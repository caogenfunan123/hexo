import 'dart:convert';
import 'dart:io';

import '../../services/storage_service.dart';
import 'ai_model_entity.dart';

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
    all.removeWhere((m) => m.modelId == model.modelId && m.apiBase == model.apiBase);
    all.add(model);
    await saveAll(all);
  }

  Future<void> updateModel(AiModelEntity model) async {
    final all = await loadAll();
    final idx = all.indexWhere((m) => m.modelId == model.modelId && m.apiBase == model.apiBase);
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
      all.removeWhere((m) => m.modelId == model.modelId && m.apiBase == model.apiBase);
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
      return ids.map((id) => AiModelEntity(
        modelId: id,
        modelName: id,
        apiBase: apiBase,
        apiKey: apiKey,
        apiPath: apiPath,
        useBearer: useBearer,
        group: group,
      )).toList();
    }
    throw Exception('需要提供模型拉取器');
  }
}