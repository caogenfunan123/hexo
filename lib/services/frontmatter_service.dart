import 'dart:convert';

import '../models/article.dart';
import 'log_service.dart';

/// FrontMatter 模板
///
/// 每个站点可拥有多个模板，模板包含 YAML 格式的 FrontMatter 内容，
/// 支持 {{title}}、{{date}}、{{tags}}、{{categories}}、{{cover}}、{{draft}} 占位符。
class FrontMatterTemplate {
  final String id;
  final String name;
  final String siteId;
  final String yamlContent;
  final bool isDefault;
  final DateTime createdAt;

  const FrontMatterTemplate({
    required this.id,
    required this.name,
    required this.siteId,
    required this.yamlContent,
    this.isDefault = false,
    required this.createdAt,
  });

  FrontMatterTemplate copyWith({
    String? id,
    String? name,
    String? siteId,
    String? yamlContent,
    bool? isDefault,
    DateTime? createdAt,
  }) {
    return FrontMatterTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      siteId: siteId ?? this.siteId,
      yamlContent: yamlContent ?? this.yamlContent,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'siteId': siteId,
        'yamlContent': yamlContent,
        'isDefault': isDefault,
        'createdAt': createdAt.toIso8601String(),
      };

  factory FrontMatterTemplate.fromJson(Map<String, dynamic> j) {
    return FrontMatterTemplate(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      siteId: j['siteId']?.toString() ?? '',
      yamlContent: j['yamlContent']?.toString() ?? '',
      isDefault: j['isDefault'] == true,
      createdAt:
          DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

/// FrontMatter 校验结果
class FrontMatterValidationResult {
  final bool isValid;
  final List<String> missingFields;
  final List<String> warnings;

  const FrontMatterValidationResult({
    required this.isValid,
    this.missingFields = const [],
    this.warnings = const [],
  });
}

/// FrontMatter 服务
///
/// 提供 FrontMatter 模板管理、发布前校验、标签/分类全局管理功能。
class FrontMatterService {
  final LogService _logService;
  final Map<String, List<FrontMatterTemplate>> _templates = {};

  /// 全局标签/分类集合（由外部传入文章列表维护）
  final Set<String> _globalTags = {};
  final Set<String> _globalCategories = {};

  FrontMatterService(this._logService);

  // ============================================================
  // 模板管理
  // ============================================================

  /// 加载指定站点的所有模板
  List<FrontMatterTemplate> loadTemplates(String siteId) {
    return List.unmodifiable(_templates[siteId] ?? []);
  }

  /// 保存或更新模板
  void saveTemplate(FrontMatterTemplate template) {
    _templates.putIfAbsent(template.siteId, () => []);
    final list = _templates[template.siteId]!;
    final idx = list.indexWhere((t) => t.id == template.id);

    if (template.isDefault) {
      // 确保该站点只有一个默认模板
      for (var i = 0; i < list.length; i++) {
        if (list[i].id != template.id && list[i].isDefault) {
          list[i] = list[i].copyWith(isDefault: false);
        }
      }
    }

    if (idx >= 0) {
      list[idx] = template;
    } else {
      list.add(template);
    }

    _logService.add('模板管理', '已保存模板「${template.name}」');
  }

  /// 删除模板
  void deleteTemplate(String templateId) {
    for (final entry in _templates.entries) {
      final list = entry.value;
      final idx = list.indexWhere((t) => t.id == templateId);
      if (idx >= 0) {
        final name = list[idx].name;
        list.removeAt(idx);
        _logService.add('模板管理', '已删除模板「$name」');
        return;
      }
    }
  }

  /// 获取指定站点的默认模板，无则返回 null
  FrontMatterTemplate? getTemplateForSite(String siteId) {
    final list = _templates[siteId];
    if (list == null || list.isEmpty) return null;
    final defaultTemplate = list.cast<FrontMatterTemplate?>().firstWhere(
      (t) => t!.isDefault,
      orElse: () => null,
    );
    return defaultTemplate ?? list.first;
  }

  /// 将模板应用到文章，填充缺失字段
  ///
  /// 仅当文章对应字段为空时，才从模板占位符中提取默认值填充。
  Article applyTemplate(Article article, String siteId) {
    final template = getTemplateForSite(siteId);
    if (template == null) return article;

    var updated = article;

    // 如果标题为空，尝试从模板提取默认标题
    if (updated.title.isEmpty || updated.title == '未命名') {
      final defaultTitle = _extractPlaceholderDefault(template.yamlContent, 'title');
      if (defaultTitle != null && defaultTitle.isNotEmpty) {
        updated = updated.copyWith(title: defaultTitle);
      }
    }

    // 如果封面为空，尝试从模板提取默认封面
    if (updated.cover == null || updated.cover!.isEmpty) {
      final defaultCover = _extractPlaceholderDefault(template.yamlContent, 'cover');
      if (defaultCover != null && defaultCover.isNotEmpty) {
        updated = updated.copyWith(cover: defaultCover);
      }
    }

    _logService.add('模板应用', '已对「${updated.title}」应用模板「${template.name}」');
    return updated;
  }

  /// 从 YAML 模板内容中提取占位符对应的默认值
  /// 格式：字段名: {{field}} 或 字段名: "默认值"
  String? _extractPlaceholderDefault(String yamlContent, String field) {
    // 匹配 YAML 行中该字段的非占位符值
    final regex = RegExp('^$field:\\s*(.+?)\\s*\$', multiLine: true);
    final match = regex.firstMatch(yamlContent);
    if (match != null) {
      var value = match.group(1)!.trim();
      // 去掉引号
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      // 如果是占位符（如 {{title}}），返回 null
      if (value.startsWith('{{') && value.endsWith('}}')) {
        return null;
      }
      return value;
    }
    return null;
  }

  // ============================================================
  // 校验
  // ============================================================

  /// 校验文章 FrontMatter 必填字段
  ///
  /// 返回 [FrontMatterValidationResult]，包含缺失字段和警告信息。
  FrontMatterValidationResult validate(Article article) {
    final missingFields = <String>[];
    final warnings = <String>[];

    // 标题校验：检查是否为空、未命名或默认占位符
    if (article.title.isEmpty || 
        article.title == '未命名' ||
        article.title == 'Untitled' ||
        article.title == '无标题') {
      missingFields.add('title');
    }

    // 日期校验
    // createdAt 始终存在（Article 构造时默认 DateTime.now()），
    // 但检查是否在合理范围内
    if (article.createdAt.isAfter(DateTime.now().add(const Duration(days: 1)))) {
      warnings.add('date 设置为未来日期');
    }

    // 内容校验
    if (article.content.trim().isEmpty) {
      warnings.add('内容为空');
    }

    // 封面警告
    if (article.cover != null && article.cover!.isNotEmpty) {
      final cover = article.cover!.trim();
      if (!cover.startsWith('http://') &&
          !cover.startsWith('https://') &&
          !cover.startsWith('/')) {
        warnings.add('封面 URL 格式可能无效: $cover');
      }
    }

    // 标签为空警告
    if (article.tags.isEmpty) {
      warnings.add('未设置标签');
    }

    // 分类为空警告
    if (article.categories.isEmpty) {
      warnings.add('未设置分类');
    }

    final isValid = missingFields.isEmpty;

    if (!isValid) {
      _logService.add(
        'FrontMatter 校验',
        '「${article.title}」缺少字段: ${missingFields.join(', ')}',
        success: false,
      );
    }

    return FrontMatterValidationResult(
      isValid: isValid,
      missingFields: missingFields,
      warnings: warnings,
    );
  }

  // ============================================================
  // 标签/分类全局管理
  // ============================================================

  /// 从文章列表中收集所有标签和分类，刷新全局集合
  void refreshFromArticles(List<Article> articles) {
    _globalTags.clear();
    _globalCategories.clear();
    for (final article in articles) {
      _globalTags.addAll(article.tags);
      _globalCategories.addAll(article.categories);
    }
  }

  /// 获取所有已收集的标签
  List<String> getAllTags() {
    return _globalTags.toList()..sort();
  }

  /// 获取所有已收集的分类
  List<String> getAllCategories() {
    return _globalCategories.toList()..sort();
  }

  /// 添加新标签
  void addTag(String tag) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty) return;
    if (_globalTags.add(trimmed)) {
      _logService.add('标签管理', '已添加标签「$trimmed」');
    }
  }

  /// 移除标签
  void removeTag(String tag) {
    if (_globalTags.remove(tag)) {
      _logService.add('标签管理', '已移除标签「$tag」');
    }
  }

  /// 合并重复标签：将 oldTag 替换为 newTag，并从全局集合中移除 oldTag
  void mergeTags(String oldTag, String newTag) {
    if (oldTag == newTag) return;
    final removed = _globalTags.remove(oldTag);
    _globalTags.add(newTag.trim());
    if (removed) {
      _logService.add('标签管理', '已将标签「$oldTag」合并为「${newTag.trim()}」');
    }
  }

  /// 添加新分类
  void addCategory(String category) {
    final trimmed = category.trim();
    if (trimmed.isEmpty) return;
    if (_globalCategories.add(trimmed)) {
      _logService.add('分类管理', '已添加分类「$trimmed」');
    }
  }

  /// 移除分类
  void removeCategory(String category) {
    if (_globalCategories.remove(category)) {
      _logService.add('分类管理', '已移除分类「$category」');
    }
  }

  /// 合并重复分类：将 oldCategory 替换为 newCategory
  void mergeCategories(String oldCategory, String newCategory) {
    if (oldCategory == newCategory) return;
    final removed = _globalCategories.remove(oldCategory);
    _globalCategories.add(newCategory.trim());
    if (removed) {
      _logService.add(
        '分类管理',
        '已将分类「$oldCategory」合并为「${newCategory.trim()}」',
      );
    }
  }

  /// 获取标签建议（基于已有标签前缀匹配）
  List<String> getTagSuggestions(String prefix) {
    if (prefix.isEmpty) return getAllTags();
    final lower = prefix.toLowerCase();
    return _globalTags
        .where((t) => t.toLowerCase().startsWith(lower))
        .toList()
      ..sort();
  }

  /// 获取分类建议（基于已有分类前缀匹配）
  List<String> getCategorySuggestions(String prefix) {
    if (prefix.isEmpty) return getAllCategories();
    final lower = prefix.toLowerCase();
    return _globalCategories
        .where((c) => c.toLowerCase().startsWith(lower))
        .toList()
      ..sort();
  }

  // ============================================================
  // 序列化
  // ============================================================

  /// 序列化所有模板为 JSON 字符串
  String templatesToJsonString() {
    final allTemplates = <Map<String, dynamic>>[];
    for (final list in _templates.values) {
      for (final t in list) {
        allTemplates.add(t.toJson());
      }
    }
    return jsonEncode(allTemplates);
  }

  /// 从 JSON 字符串反序列化模板
  void templatesFromJsonString(String json) {
    try {
      final list = jsonDecode(json) as List;
      for (final item in list) {
        final template =
            FrontMatterTemplate.fromJson(item as Map<String, dynamic>);
        saveTemplate(template);
      }
    } catch (e) {
      _logService.add('加载模板失败', '$e', success: false);
    }
  }

  /// 清空所有模板
  void clearTemplates() {
    _templates.clear();
  }

  /// 清空全局标签和分类
  void clearTaxonomy() {
    _globalTags.clear();
    _globalCategories.clear();
  }

  /// 清空全部数据
  void clear() {
    _templates.clear();
    _globalTags.clear();
    _globalCategories.clear();
  }
}