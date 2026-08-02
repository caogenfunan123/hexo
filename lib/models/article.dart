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
  final String articleType; // 'post' 或 'page'
  final String? templateId; // 使用的模板ID

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
    this.articleType = 'post',
    this.templateId,
  });

  Article copyWith({
    String? id,
    String? title,
    String? content,
    List<String>? tags,
    List<String>? categories,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDraft,
    Object? remotePath = _sentinel,
    Object? remoteSha = _sentinel,
    Object? repoId = _sentinel,
    Object? cover = _sentinel,
    bool? published,
    String? articleType,
    Object? templateId = _sentinel,
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
      remotePath: identical(remotePath, _sentinel) ? this.remotePath : remotePath as String?,
      remoteSha: identical(remoteSha, _sentinel) ? this.remoteSha : remoteSha as String?,
      repoId: identical(repoId, _sentinel) ? this.repoId : repoId as String?,
      cover: identical(cover, _sentinel) ? this.cover : cover as String?,
      published: published ?? this.published,
      articleType: articleType ?? this.articleType,
      templateId: identical(templateId, _sentinel) ? this.templateId : templateId as String?,
    );
  }

  static const Object _sentinel = Object();

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
        'articleType': articleType,
        'templateId': templateId,
      };

  factory Article.fromJson(Map<String, dynamic> j) => Article(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        content: j['content']?.toString() ?? '',
        tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
        categories:
            (j['categories'] as List?)?.map((e) => e.toString()).toList() ??
                [],
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(j['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
        isDraft: j['isDraft'] != false,
        remotePath: j['remotePath']?.toString(),
        remoteSha: j['remoteSha']?.toString(),
        repoId: j['repoId']?.toString(),
        cover: j['cover']?.toString(),
        published: j['published'] == true,
        articleType: j['articleType']?.toString() ?? 'post',
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

    // 尝试从框架预设获取模板
    final fw = BlogFramework.byId(frameworkId);
    if (fw != null) {
      final template = articleType == 'page' ? fw.pageFrontMatter : fw.postFrontMatter;
      if (template.isNotEmpty) {
        var fm = template
            .replaceAll('{{title}}', title.isEmpty ? '未命名' : title)
            .replaceAll('{{date}}', fw.id == 'jekyll' ? dateFull : dateFull)
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
    if (articleType == 'page') {
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

  static Article fromMarkdown(String md, {String? id, String? remotePath, String? remoteSha, String? repoId}) {
    String title = '未命名';
    DateTime created = DateTime.now();
    List<String> tags = [];
    List<String> categories = [];
    String? cover;
    String articleType = 'post';
    String? templateId;
    String body = md;

    if (md.trimLeft().startsWith('---')) {
      final end = md.indexOf('\n---', 3);
      if (end > 0) {
        final fm = md.substring(3, end).trim();
        body = md.substring(end + 4).replaceFirst(RegExp(r'^\s*\n'), '');
        for (final line in fm.split('\n')) {
          final t = line.trim();
          if (t.startsWith('title:')) {
            title = t.substring(6).trim().replaceAll(RegExp(r'^["' "'" r']|["' "'" r']$'), '');
          } else if (t.startsWith('date:')) {
            created = DateTime.tryParse(t.substring(5).trim().replaceFirst(' ', 'T')) ?? created;
          } else if (t.startsWith('tags:')) {
            tags = _parseList(t.substring(5).trim());
          } else if (t.startsWith('categories:')) {
            categories = _parseList(t.substring(11).trim());
          } else if (t.startsWith('cover:')) {
            cover = _stripQuotes(t.substring(6).trim());
          } else if (t.startsWith('type:') && t.substring(5).trim().toLowerCase() == 'page') {
            articleType = 'page';
          } else if (t.startsWith('layout:') && t.substring(7).trim().toLowerCase() == 'page') {
            articleType = 'page';
          } else if (t.startsWith('articleType:')) {
            articleType = t.substring(12).trim().toLowerCase() == 'page' ? 'page' : 'post';
          } else if (t.startsWith('templateId:')) {
            templateId = _stripQuotes(t.substring(11).trim());
          }
        }
      }
    }

    final now = DateTime.now();
    return Article(
      id: id ?? now.millisecondsSinceEpoch.toString(),
      title: title,
      content: body,
      tags: tags,
      categories: categories,
      createdAt: created,
      updatedAt: now,
      isDraft: false,
      remotePath: remotePath,
      remoteSha: remoteSha,
      repoId: repoId,
      cover: cover,
      published: true,
      articleType: articleType,
      templateId: templateId,
    );
  }

  static String _stripQuotes(String s) {
    var out = s.trim();
    if ((out.startsWith('"') && out.endsWith('"')) ||
        (out.startsWith("'") && out.endsWith("'"))) {
      out = out.substring(1, out.length - 1);
    }
    return out.trim();
  }

  static List<String> _parseList(String raw) {
    var s = raw.trim();
    if (s.startsWith('[') && s.endsWith(']')) {
      s = s.substring(1, s.length - 1);
    }
    if (s.isEmpty) return [];
    return s
        .split(',')
        .map((e) => e.trim().replaceAll(RegExp(r'^["' "'" r']|["' "'" r']$'), ''))
        .where((e) => e.isNotEmpty)
        .toList();
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

  /// 根据仓库配置生成文件名（页面永不加日期）
  String fileNameForRepo(RepoConfig repo) {
    if (articleType == 'page') return fileName(postDatePrefix: false);
    return fileName(postDatePrefix: repo.fileNameRule.postDatePrefix);
  }
}
