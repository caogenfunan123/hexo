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
      );

  String toMarkdownWithFrontMatter() {
    final date =
        '${createdAt.year.toString().padLeft(4, '0')}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}:${createdAt.second.toString().padLeft(2, '0')}';
    final tagsStr = tags.isEmpty
        ? '[]'
        : '[${tags.map((t) => t.contains(' ') ? '"$t"' : t).join(', ')}]';
    final catsStr = categories.isEmpty
        ? '[]'
        : '[${categories.map((c) => c.contains(' ') ? '"$c"' : c).join(', ')}]';
    final buf = StringBuffer()
      ..writeln('---')
      ..writeln('title: ${title.isEmpty ? '未命名' : title}')
      ..writeln('date: $date')
      ..writeln('tags: $tagsStr')
      ..writeln('categories: $catsStr');
    if (cover != null && cover!.isNotEmpty) {
      buf.writeln('cover: $cover');
    }
    buf
      ..writeln('---')
      ..writeln()
      ..write(content);
    return buf.toString();
  }

  static Article fromMarkdown(String md, {String? id, String? remotePath, String? remoteSha, String? repoId}) {
    String title = '未命名';
    DateTime created = DateTime.now();
    List<String> tags = [];
    List<String> categories = [];
    String? cover;
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

  String fileName() {
    final base = title.isEmpty
        ? 'untitled'
        : title
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
            .replaceAll(RegExp(r'\s+'), '-')
            .toLowerCase();
    return base.endsWith('.md') ? base : '$base.md';
  }
}
