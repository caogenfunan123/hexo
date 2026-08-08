/// FrontMatter 控制器 — 统一管理 YAML/TOML 头信息
///
/// 职责：标题/标签/分类/封面/模板/日期的读写与校验、模板占位符展开
/// 对标：MarkText YAML 解析
library;

import 'package:flutter/material.dart';

/// FrontMatter 数据
class FrontMatterData {
  final String title;
  final List<String> tags;
  final List<String> categories;
  final String? cover;
  final DateTime? date;
  final String? template;
  final String articleType;
  final bool isDraft;
  final Map<String, dynamic> extra;

  const FrontMatterData({
    this.title = '',
    this.tags = const [],
    this.categories = const [],
    this.cover,
    this.date,
    this.template,
    this.articleType = 'post',
    this.isDraft = true,
    this.extra = const {},
  });

  FrontMatterData copyWith({
    String? title,
    List<String>? tags,
    List<String>? categories,
    String? cover,
    DateTime? date,
    String? template,
    String? articleType,
    bool? isDraft,
    Map<String, dynamic>? extra,
  }) {
    return FrontMatterData(
      title: title ?? this.title,
      tags: tags ?? this.tags,
      categories: categories ?? this.categories,
      cover: cover ?? this.cover,
      date: date ?? this.date,
      template: template ?? this.template,
      articleType: articleType ?? this.articleType,
      isDraft: isDraft ?? this.isDraft,
      extra: extra ?? this.extra,
    );
  }

  /// 生成 YAML 格式的 FrontMatter 字符串
  String toYaml() {
    final buffer = StringBuffer();
    buffer.writeln('---');
    buffer.writeln('title: ${_escapeYaml(title)}');
    if (date != null) {
      final d = date!;
      buffer.writeln(
          'date: ${d.toIso8601String().split('T').first} ${d.toIso8601String().split('T').last.substring(0, 8)}');
    }
    if (tags.isNotEmpty) {
      buffer.writeln('tags:');
      for (final tag in tags) {
        buffer.writeln('  - ${_escapeYaml(tag)}');
      }
    }
    if (categories.isNotEmpty) {
      buffer.writeln('categories:');
      for (final cat in categories) {
        buffer.writeln('  - ${_escapeYaml(cat)}');
      }
    }
    if (cover != null && cover!.isNotEmpty) {
      final c = cover!;
      buffer.writeln('cover: ${_escapeYaml(c)}');
    }
    if (template != null && template!.isNotEmpty) {
      final t = template!;
      buffer.writeln('template: ${_escapeYaml(t)}');
    }
    buffer.writeln('type: $articleType');
    buffer.writeln('draft: $isDraft');
    for (final entry in extra.entries) {
      buffer.writeln('${entry.key}: ${_escapeYaml(entry.value.toString())}');
    }
    buffer.writeln('---');
    return buffer.toString();
  }

  /// 从 YAML 字符串解析 FrontMatter
  static FrontMatterData fromYaml(String yaml) {
    String title = '';
    final List<String> tags = [];
    final List<String> categories = [];
    String? cover;
    DateTime? date;
    String? template;
    String articleType = 'post';
    bool isDraft = true;
    final Map<String, dynamic> extra = {};

    final lines = yaml.split('\n');
    String? currentList;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed == '---') continue;

      // 列表项
      if (trimmed.startsWith('- ')) {
        final value = _stripQuotes(trimmed.substring(2).trim());
        if (currentList == 'tags') {
          tags.add(value);
        } else if (currentList == 'categories') {
          categories.add(value);
        }
        continue;
      }

      currentList = null;
      final colonIndex = trimmed.indexOf(':');
      if (colonIndex < 0) continue;

      final key = trimmed.substring(0, colonIndex).trim();
      final value = _stripQuotes(trimmed.substring(colonIndex + 1).trim());

      switch (key) {
        case 'title':
          title = value;
          break;
        case 'date':
          try {
            date = DateTime.parse(value);
          } catch (e) { debugPrint('FrontMatter: parse draft failed: $e'); }
          break;
        case 'tags':
          currentList = 'tags';
          tags.addAll(_parseInlineList(value));
          break;
        case 'categories':
          currentList = 'categories';
          categories.addAll(_parseInlineList(value));
          break;
        case 'cover':
          cover = value;
          break;
        case 'template':
          template = value;
          break;
        case 'type':
          articleType = value;
          break;
        case 'draft':
          isDraft = value.toLowerCase() == 'true';
          break;
        default:
          extra[key] = value;
      }
    }

    return FrontMatterData(
      title: title,
      tags: tags,
      categories: categories,
      cover: cover,
      date: date,
      template: template,
      articleType: articleType,
      isDraft: isDraft,
      extra: extra,
    );
  }

  static String _escapeYaml(String value) {
    // 含特殊字符（冒号、井号、引号、前后空格、换行、反斜杠等）时用双引号包裹
    if (value.contains(':') || value.contains('#') || value.contains('"') ||
        value.contains("'") || value.contains('\\') || value.contains('\n') ||
        value.contains('\t') || value.startsWith(' ') || value.endsWith(' ') ||
        value.isEmpty) {
      return '"${_escapeYamlString(value)}"';
    }
    return value;
  }

  /// 对双引号包裹的 YAML 字符串内容做转义（反斜杠、双引号、换行）
  static String _escapeYamlString(String value) {
    final buf = StringBuffer();
    for (final rune in value.runes) {
      final c = String.fromCharCode(rune);
      switch (c) {
        case '\\':
          buf.write('\\\\');
        case '"':
          buf.write('\\"');
        case '\n':
          buf.write('\\n');
        case '\t':
          buf.write('\\t');
        case '\r':
          buf.write('\\r');
        default:
          buf.write(c);
      }
    }
    return buf.toString();
  }

  /// 解析行内列表形式，如 `tags: [a, b]`
  static List<String> _parseInlineList(String value) {
    final v = value.trim();
    if (v.isEmpty) return const [];
    if (v.startsWith('[') && v.endsWith(']')) {
      return v
          .substring(1, v.length - 1)
          .split(',')
          .map((e) => _stripQuotes(e.trim()))
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return [value];
  }

  static String _stripQuotes(String value) {
    final v = value.trim();
    if ((v.startsWith('"') && v.endsWith('"')) ||
        (v.startsWith("'") && v.endsWith("'"))) {
      final inner = v.substring(1, v.length - 1);
      // 还原转义（双引号字符串）
      if (v.startsWith('"')) {
        return inner
            .replaceAll('\\n', '\n')
            .replaceAll('\\t', '\t')
            .replaceAll('\\r', '\r')
            .replaceAll('\\"', '"')
            .replaceAll('\\\\', '\\');
      }
      return inner;
    }
    return value;
  }
}

/// 模板占位符
class TemplatePlaceholders {
  static const title = '{{title}}';
  static const date = '{{date}}';
  static const tags = '{{tags}}';
  static const categories = '{{categories}}';
  static const cover = '{{cover}}';
  static const slug = '{{slug}}';
  static const author = '{{author}}';
  static const year = '{{year}}';
  static const month = '{{month}}';
  static const day = '{{day}}';
}

class FrontMatterController extends ChangeNotifier {
  // ── 当前 FrontMatter 数据 ──
  FrontMatterData _data = const FrontMatterData();

  // ── 模板列表 ──
  final List<Map<String, String>> _templates = [];

  // ── Getters ──
  FrontMatterData get data => _data;
  List<Map<String, String>> get templates => List.unmodifiable(_templates);

  String get title => _data.title;
  List<String> get tags => _data.tags;
  List<String> get categories => _data.categories;
  String? get cover => _data.cover;
  DateTime? get date => _data.date;
  String? get template => _data.template;
  String get articleType => _data.articleType;
  bool get isDraft => _data.isDraft;

  // ── 数据更新 ──
  void updateTitle(String title) {
    _data = _data.copyWith(title: title);
    notifyListeners();
  }

  void updateTags(List<String> tags) {
    _data = _data.copyWith(tags: tags);
    notifyListeners();
  }

  void addTag(String tag) {
    if (tag.isNotEmpty && !_data.tags.contains(tag)) {
      _data = _data.copyWith(tags: [..._data.tags, tag]);
      notifyListeners();
    }
  }

  void removeTag(String tag) {
    _data = _data.copyWith(tags: _data.tags.where((t) => t != tag).toList());
    notifyListeners();
  }

  void updateCategories(List<String> categories) {
    _data = _data.copyWith(categories: categories);
    notifyListeners();
  }

  void updateCover(String? cover) {
    _data = _data.copyWith(cover: cover);
    notifyListeners();
  }

  void updateDate(DateTime? date) {
    _data = _data.copyWith(date: date);
    notifyListeners();
  }

  void updateTemplate(String? template) {
    _data = _data.copyWith(template: template);
    notifyListeners();
  }

  void updateArticleType(String type) {
    _data = _data.copyWith(articleType: type);
    notifyListeners();
  }

  void updateIsDraft(bool isDraft) {
    _data = _data.copyWith(isDraft: isDraft);
    notifyListeners();
  }

  void updateExtra(Map<String, dynamic> extra) {
    _data = _data.copyWith(extra: extra);
    notifyListeners();
  }

  /// 从完整数据更新
  void setData(FrontMatterData data) {
    _data = data;
    notifyListeners();
  }

  /// 重置为新文章
  void reset({String articleType = 'post'}) {
    _data = FrontMatterData(
      title: '',
      date: DateTime.now(),
      articleType: articleType,
      isDraft: true,
    );
    notifyListeners();
  }

  // ── 模板管理 ──
  void setTemplates(List<Map<String, String>> templates) {
    _templates
      ..clear()
      ..addAll(templates);
    notifyListeners();
  }

  /// 展开模板占位符
  String expandTemplate(String templateContent, {String? slug}) {
    final now = DateTime.now();
    return templateContent
        .replaceAll(TemplatePlaceholders.title, _data.title)
        .replaceAll(TemplatePlaceholders.date,
            _data.date?.toIso8601String() ?? now.toIso8601String())
        .replaceAll(TemplatePlaceholders.tags, _data.tags.join(', '))
        .replaceAll(
            TemplatePlaceholders.categories, _data.categories.join(', '))
        .replaceAll(TemplatePlaceholders.cover, _data.cover ?? '')
        .replaceAll(TemplatePlaceholders.slug, slug ?? '')
        .replaceAll(TemplatePlaceholders.year, now.year.toString())
        .replaceAll(
            TemplatePlaceholders.month, now.month.toString().padLeft(2, '0'))
        .replaceAll(
            TemplatePlaceholders.day, now.day.toString().padLeft(2, '0'));
  }

  // ── 生成完整 Markdown（含 FrontMatter） ──
  String toMarkdownWithFrontMatter(String content) {
    return '${_data.toYaml()}\n$content';
  }

  /// 从 Markdown 文本解析 FrontMatter 和正文
  static (FrontMatterData, String) parseMarkdown(String markdown) {
    // 逐行解析，仅当结束 `---` 独占一行时才视为 FrontMatter 结束，
    // 避免正文中的水平分割线 `---` 被误判
    if (markdown.startsWith('---')) {
      final lines = markdown.split('\n');
      if (lines.length >= 2) {
        for (var i = 1; i < lines.length; i++) {
          if (lines[i].trimRight() == '---') {
            final yaml = lines.sublist(1, i).join('\n').trim();
            final content = lines.sublist(i + 1).join('\n').trimLeft();
            return (FrontMatterData.fromYaml(yaml), content);
          }
        }
      }
    }
    return (const FrontMatterData(), markdown);
  }
}