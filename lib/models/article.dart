import 'article_type.dart';
import 'blog_framework.dart';
import 'repo_config.dart';

class Article {
  final String id;
  final String title;
  final String content;
  final List<String> tags;
  final List<String> categories;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDraft;
  final String? remotePath;
  final String? remoteSha;
  final String? repoId;
  final String? cover;
  final bool published;
  final ArticleType articleType;
  final String? templateId;

  const Article({
    required this.id,
    required this.title,
    required this.content,
    this.tags = const [],
    this.categories = const [],
    required this.createdAt,
    required this.updatedAt,
    this.isDraft = true,
    this.remotePath,
    this.remoteSha,
    this.repoId,
    this.cover,
    this.published = false,
    this.articleType = ArticleType.post,
    this.templateId,
  });

  /// copyWith 哨兵值：区分"未传递"与"传 null"的标记
  /// 使用方式：调用方省略参数时保持原值，显式传 null 时清空字段值
  static const _Undefined _undefined = _Undefined();

  Article copyWith({
    String? id,
    String? title,
    String? content,
    List<String>? tags,
    List<String>? categories,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDraft,
    Object? remotePath = _undefined,
    Object? remoteSha = _undefined,
    Object? repoId = _undefined,
    Object? cover = _undefined,
    bool? published,
    ArticleType? articleType,
    Object? templateId = _undefined,
  }) {
    return Article(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      tags: tags ?? this.tags,
      categories: categories ?? this.categories,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDraft: isDraft ?? this.isDraft,
      remotePath: identical(remotePath, _undefined) ? this.remotePath : remotePath as String?,
      remoteSha: identical(remoteSha, _undefined) ? this.remoteSha : remoteSha as String?,
      repoId: identical(repoId, _undefined) ? this.repoId : repoId as String?,
      cover: identical(cover, _undefined) ? this.cover : cover as String?,
      published: published ?? this.published,
      articleType: articleType ?? this.articleType,
      templateId: identical(templateId, _undefined) ? this.templateId : templateId as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'tags': tags,
        'categories': categories,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'isDraft': isDraft,
        'remotePath': remotePath,
        'remoteSha': remoteSha,
        'repoId': repoId,
        'cover': cover,
        'published': published,
        'articleType': articleType.value,
        'templateId': templateId,
      };

  factory Article.fromJson(Map<String, dynamic> j) => Article(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        content: j['content']?.toString() ?? '',
        tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
        categories:
            (j['categories'] as List?)?.map((e) => e.toString()).toList() ?? [],
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(j['updatedAt']?.toString() ?? '') ?? DateTime.now(),
        isDraft: j['isDraft'] != false,
        remotePath: j['remotePath']?.toString(),
        remoteSha: j['remoteSha']?.toString(),
        repoId: j['repoId']?.toString(),
        cover: j['cover']?.toString(),
        published: j['published'] == true,
        articleType: ArticleType.fromJson(j['articleType']),
        templateId: j['templateId']?.toString(),
      );

  /// 用指定框架预设生成 FrontMatter + 正文
  String toMarkdownWithFrontMatter({String frameworkId = 'hexo'}) {
    final dateFull =
        '${createdAt.year.toString().padLeft(4, '0')}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}:${createdAt.second.toString().padLeft(2, '0')}';
    final dateShort =
        '${createdAt.year.toString().padLeft(4, '0')}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';
    final tagsStr = tags.isEmpty
        ? '[]'
        : '[${tags.map((t) => t.contains(' ') ? '"$t"' : t).join(', ')}]';
    final catsStr = categories.isEmpty
        ? '[]'
        : '[${categories.map((c) => c.contains(' ') ? '"$c"' : c).join(', ')}]';

    final fw = BlogFramework.byId(frameworkId);
    if (fw != null) {
      final template = articleType == ArticleType.page ? fw.pageFrontMatter : fw.postFrontMatter;
      if (template.isNotEmpty) {
        var fm = template
            .replaceAll('{{title}}', title.isEmpty ? '未命名' : title)
            .replaceAll('{{date}}', dateFull)
            .replaceAll('{{tags}}', tagsStr)
            .replaceAll('{{categories}}', catsStr);
        if (cover != null && cover!.isNotEmpty) {
          fm = fm.replaceAll('{{cover}}', cover!);
        }
        fm = fm.replaceAll('{{draft}}', isDraft.toString());
        fm = fm.replaceAll('{{slug}}', title.toLowerCase().replaceAll(RegExp(r'\s+'), '-'));
        return '$fm\n$content';
      }
    }

    // 回退：通用 Hexo 格式
    final buf = StringBuffer()
      ..writeln('---')
      ..writeln('title: ${title.isEmpty ? '未命名' : title}')
      ..writeln('date: $dateFull')
      ..writeln('tags: $tagsStr')
      ..writeln('categories: $catsStr');
    if (articleType == ArticleType.page) {
      buf.writeln('type: page');
    }
    if (isDraft) {
      buf.writeln('draft: true');
    }
    if (cover != null && cover!.isNotEmpty) {
      buf.writeln('cover: $cover');
    }
    buf
      ..writeln('---')
      ..writeln()
      ..write(content);
    return buf.toString();
  }

  /// 绑定框架的 toMarkdownWithFrontMatter
  String toMarkdownWithFrontMatterForRepo(RepoConfig repo) {
    return toMarkdownWithFrontMatter(
      frameworkId: repo.frameworkId,
    );
  }

  /// 从 Markdown 文本解析 Article（修复版：正确处理 YAML 列表、嵌套引号、published 字段）
  static Article fromMarkdown(String md, {String? id, String? remotePath, String? remoteSha, String? repoId}) {
    String title = '未命名';
    DateTime created = DateTime.now();
    List<String> tags = [];
    List<String> categories = [];
    String? cover;
    ArticleType articleType = ArticleType.post;
    String? templateId;
    bool isDraft = true;
    bool published = false;
    String body = md;

    if (md.trimLeft().startsWith('---')) {
      final endIndex = md.indexOf('\n---', 3);
      if (endIndex > 0) {
        final fm = md.substring(3, endIndex).trim();
        body = md.substring(endIndex + 4).replaceFirst(RegExp(r'^\s*\n'), '');

        String? currentListKey;

        for (final line in fm.split('\n')) {
          final trimmed = line.trim();

          // 跳过空行和注释
          if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

          // YAML 列表项（- value）
          if (trimmed.startsWith('- ')) {
            final value = _stripQuotes(trimmed.substring(2).trim());
            if (currentListKey == 'tags' && value.isNotEmpty) {
              tags.add(value);
            } else if (currentListKey == 'categories' && value.isNotEmpty) {
              categories.add(value);
            }
            continue;
          }

          // 键值对
          currentListKey = null;
          final colonIndex = trimmed.indexOf(':');
          if (colonIndex < 0) continue;

          final key = trimmed.substring(0, colonIndex).trim();
          final rawValue = trimmed.substring(colonIndex + 1).trim();

          switch (key) {
            case 'title':
              title = _stripQuotes(rawValue);
              break;
            case 'date':
              created = DateTime.tryParse(rawValue.replaceAll(' ', 'T')) ?? created;
              break;
            case 'tags':
              if (rawValue.startsWith('[') && rawValue.endsWith(']')) {
                tags = _parseInlineArray(rawValue);
              } else if (rawValue.isNotEmpty && !rawValue.startsWith('[')) {
                tags = [_stripQuotes(rawValue)];
              } else {
                currentListKey = 'tags';
              }
              break;
            case 'categories':
              if (rawValue.startsWith('[') && rawValue.endsWith(']')) {
                categories = _parseInlineArray(rawValue);
              } else if (rawValue.isNotEmpty && !rawValue.startsWith('[')) {
                categories = [_stripQuotes(rawValue)];
              } else {
                currentListKey = 'categories';
              }
              break;
            case 'cover':
              cover = _stripQuotes(rawValue);
              break;
            case 'type':
            case 'layout':
              if (rawValue.toLowerCase() == 'page') {
                articleType = ArticleType.page;
              }
              break;
            case 'articleType':
              articleType = ArticleType.fromString(rawValue);
              break;
            case 'templateId':
              templateId = _stripQuotes(rawValue);
              break;
            case 'draft':
              isDraft = rawValue.toLowerCase() == 'true';
              break;
            case 'published':
              published = rawValue.toLowerCase() == 'true';
              break;
          }
        }
      }
    }

    // 如果明确标记了 published，则 isDraft 取反；否则以 draft 字段为准
    final effectiveDraft = published ? false : isDraft;
    final now = DateTime.now();
    return Article(
      id: id ?? now.millisecondsSinceEpoch.toString(),
      title: title,
      content: body,
      tags: tags,
      categories: categories,
      createdAt: created,
      updatedAt: now,
      isDraft: effectiveDraft,
      remotePath: remotePath,
      remoteSha: remoteSha,
      repoId: repoId,
      cover: cover,
      published: published || !effectiveDraft,
      articleType: articleType,
      templateId: templateId,
    );
  }

  /// 解析内联数组: [value1, value2, "value with \"quotes\" and, commas"]
  /// 支持 YAML 嵌套引号，逗号在引号内不拆分
  static List<String> _parseInlineArray(String raw) {
    var s = raw.trim();
    if (s.startsWith('[') && s.endsWith(']')) {
      s = s.substring(1, s.length - 1).trim();
    }
    if (s.isEmpty) return [];
    final result = <String>[];
    final buf = StringBuffer();
    bool inDoubleQuote = false;
    bool inSingleQuote = false;

    for (int i = 0; i < s.length; i++) {
      final ch = s[i];

      if (ch == '"' && !inSingleQuote) {
        if (inDoubleQuote && i > 0 && s[i - 1] == '\\') {
          buf.write(ch);
        } else {
          inDoubleQuote = !inDoubleQuote;
        }
        continue;
      }
      if (ch == "'" && !inDoubleQuote) {
        inSingleQuote = !inSingleQuote;
        continue;
      }

      if (ch == ',' && !inDoubleQuote && !inSingleQuote) {
        final cleaned = buf.toString().trim();
        if (cleaned.isNotEmpty) result.add(cleaned);
        buf.clear();
        continue;
      }

      buf.write(ch);
    }

    final last = buf.toString().trim();
    if (last.isNotEmpty) result.add(last);

    return result;
  }

  static String _stripQuotes(String s) {
    var out = s.trim();
    if ((out.startsWith('"') && out.endsWith('"')) ||
        (out.startsWith("'") && out.endsWith("'"))) {
      out = out.substring(1, out.length - 1);
    }
    return out.trim();
  }

  String fileName({bool postDatePrefix = false}) {
    final datePrefix = postDatePrefix
        ? '${createdAt.year.toString().padLeft(4, '0')}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}-'
        : '';
    final base = title.isEmpty
        ? 'untitled'
        : title
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
            .replaceAll(RegExp(r'\s+'), '-')
            .toLowerCase();
    final name = base.endsWith('.md') ? base : '$base.md';
    return '$datePrefix$name';
  }

  /// 根据仓库配置生成文件名（页面永不加日期前缀）
  String fileNameForRepo(RepoConfig repo) {
    if (articleType == ArticleType.page) return fileName(postDatePrefix: false);
    return fileName(postDatePrefix: repo.fileNameRule.postDatePrefix);
  }
}

/// copyWith 哨兵类型：区分"未传递"与"显式传 null"
class _Undefined {
  const _Undefined();
}

extension ArticleSlug on Article {
  /// 生成 SEO 友好的 slug（处理中文、特殊符号）
  String toSlug() {
    return title
        .replaceAll(RegExp(r'[^\w\s\u4e00-\u9fff-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .toLowerCase();
  }
}