import 'dart:convert';
import 'dart:io';

import '../core/ai/ai_model_entity.dart';
import '../core/ai/ai_model_manager.dart';
import '../core/ai/ai_provider.dart';
import 'storage_service.dart';

/// 本地 GGUF 模型扫描与登记服务。
///
/// 模型文件约定存放于 `{storageRoot}/models/` 目录（可含子目录）。
/// 扫描到的 `.gguf` 文件会登记进 `AiModelManager`（provider = local），
/// 使本地模型可被模型选择器与请求调度统一使用。
class GgufModelService {
  static const _modelsDirName = 'models';
  static const _localIndexFile = 'local_models.json';

  final StorageService _storage;
  final AiModelManager _modelManager;

  GgufModelService(this._storage, this._modelManager);

  /// 模型目录绝对路径（自动创建）。
  Future<Directory> modelsDir() async {
    final root = await _storage.root;
    final dir = Directory('${root.path}/$_modelsDirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 递归扫描模型目录，返回全部 .gguf 文件。
  Future<List<File>> scanGgufFiles() async {
    final dir = await modelsDir();
    final out = <File>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.gguf')) {
        out.add(entity);
      }
    }
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }

  /// 将模型目录中的全部 GGUF 登记进模型管理器。
  /// 已存在（modelId 相同）的项会被更新而非重复添加。
  Future<int> syncFromDisk() async {
    final files = await scanGgufFiles();
    final all = await _modelManager.loadAll();
    var added = 0;
    for (final f in files) {
      final modelId = 'local:${f.path.split('/').last.split('\\').last}';
      final contextLimit = await getContextSize(modelId);
      final idx = all.indexWhere((m) => m.modelId == modelId);
      if (idx >= 0) {
        all[idx] = all[idx].copyWith(
          modelName: _displayName(f.path),
          apiBase: f.path,
          contextLimit: contextLimit,
        );
      } else {
        all.add(AiModelEntity(
          modelId: modelId,
          modelName: _displayName(f.path),
          apiBase: f.path,
          apiKey: '',
          provider: ModelProvider.local,
          group: 'general',
          contextLimit: contextLimit,
          priority: 0,
        ));
        added++;
      }
    }
    await _modelManager.saveAll(all);
    return added;
  }

  /// 把外部文件复制进模型目录并登记。
  /// [sourcePath] 为待导入的 .gguf 路径（来自 file_picker）。
  /// 返回登记的 modelId；失败抛出异常。
  Future<String> importGguf(String sourcePath) async {
    final src = File(sourcePath);
    if (!await src.exists()) {
      throw Exception('模型文件不存在: $sourcePath');
    }
    final dir = await modelsDir();
    final fileName = src.path.split('/').last.split('\\').last;
    final dest = File('${dir.path}/$fileName');
    if (!await dest.exists()) {
      await src.copy(dest.path);
    }
    final modelId = 'local:$fileName';
    final contextLimit = await getContextSize(modelId);
    final all = await _modelManager.loadAll();
    final idx = all.indexWhere((m) => m.modelId == modelId);
    if (idx >= 0) {
      all[idx] = all[idx].copyWith(
        modelName: _displayName(dest.path),
        apiBase: dest.path,
        contextLimit: contextLimit,
      );
    } else {
      all.add(AiModelEntity(
        modelId: modelId,
        modelName: _displayName(dest.path),
        apiBase: dest.path,
        apiKey: '',
        provider: ModelProvider.local,
        group: 'general',
        contextLimit: contextLimit,
        priority: 0,
      ));
    }
    await _modelManager.saveAll(all);
    return modelId;
  }

  /// 已登记的本地模型列表（provider == local）。
  Future<List<AiModelEntity>> localModels() async {
    final all = await _modelManager.loadAll();
    return all.where((m) => m.provider == ModelProvider.local).toList();
  }

  /// 从路径推导展示名（去掉 .gguf 后缀）。
  static String _displayName(String path) {
    var name = path.split('/').last.split('\\').last;
    if (name.toLowerCase().endsWith('.gguf')) {
      name = name.substring(0, name.length - 5);
    }
    return name;
  }

  /// 读取模型文件大小（MB），用于 UI 展示。
  static Future<double> fileSizeMb(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return 0;
      final s = await f.length();
      return s / (1024 * 1024);
    } catch (_) {
      return 0;
    }
  }

  // ── 独立索引（可选，记录模型路径与已导入状态） ──
  Future<Map<String, dynamic>> _readIndex() async {
    final f = File('${(await _storage.root).path}/$_localIndexFile');
    if (!await f.exists()) return {};
    try {
      final text = await f.readAsString();
      return text.trim().isEmpty
          ? {}
          : Map<String, dynamic>.from(jsonDecode(text) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeIndex(Map<String, dynamic> index) async {
    final f = File('${(await _storage.root).path}/$_localIndexFile');
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(index));
  }

  /// 读取指定模型的上下文长度设置（默认 4096）。
  Future<int> getContextSize(String modelId) async {
    final index = await _readIndex();
    final entry = index[modelId];
    if (entry is Map) {
      final v = entry['contextSize'];
      if (v is num) return v.toInt();
    }
    return 4096;
  }

  /// 保存指定模型的上下文长度设置。
  Future<void> setContextSize(String modelId, int contextSize) async {
    final index = await _readIndex();
    final entry = (index[modelId] as Map? ?? {}) as Map;
    index[modelId] = {...entry, 'contextSize': contextSize};
    await _writeIndex(index);
  }
}
