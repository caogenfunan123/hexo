import 'article_type.dart';
import 'blog_framework.dart';
import 'repo_config.dart';
import 'template_item.dart';

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

  /// 卷宗分类（如 卷1 / 卷2），简易模式首页按此分组；null 归「未分类」
  final String? volume;

  /// 定时发布时间（未来日期）：设置后 front matter date 使用该时间，
  /// 触发 Hexo/Hugo 原生 future posts 机制定时展示。null 表示立即发布。
  final DateTime? schedulePublishAt;

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
    this.volume,
    this.schedulePublishAt,
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
    Object? volume = _undefined,
    Object? schedulePublishAt = _undefined,
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
      volume: identical(volume, _undefined) ? this.volume : volume as String?,
      schedulePublishAt: identical(schedulePublishAt, _undefined)
          ? this.schedulePublishAt
          : schedulePublishAt as DateTime?,
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
        'volume': volume,
        'schedulePublishAt': schedulePublishAt?.toIso8601String(),
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
        volume: j['volume']?.toString(),
        schedulePublishAt:
            DateTime.tryParse(j['schedulePublishAt']?.toString() ?? ''),
      );

  /// 用指定框架预设生成 FrontMatter + 正文
  /// 如果提供了 [templates] 且文章有 [templateId]，优先使用自定义模板
  String toMarkdownWithFrontMatter({String frameworkId = 'hexo', List<TemplateItem>? templates, int? timezoneOffsetMinutes}) {
    // 优先查找自定义模板
    if (templateId != null && templateId!.isNotEmpty && templates != null) {
      final customTemplate = templates.where((t) => t.id == templateId).firstOrNull;
      if (customTemplate != null) {
        return _applyCustomTemplate(customTemplate, repoFrameworkId: frameworkId, timezoneOffsetMinutes: timezoneOffsetMinutes);
      }
    }

    // 定时发布：保留 schedulePublishAt 的未来日期，触发 Hexo/Hugo future posts 机制。
    // 否则走未来日期保护：如果 createdAt 在未来，使用当前日期，
    // 避免因时区差异导致 Cloudflare 构建时文章被判定为"未来文章"而不显示。
    final now = DateTime.now();
    final effectiveDate = schedulePublishAt ?? (createdAt.isAfter(now) ? now : createdAt);

    // 按发布时区转换墙钟时间（默认北京时间 +08:00）
    // Cloudflare Pages 构建机为 UTC，必须把设备本地时间映射到目标时区并带偏移，
    // 否则构建机按 UTC 解析日期会导致文章日期偏移 8 小时
    final offset = timezoneOffsetMinutes ?? 480;
    final tzDate = effectiveDate.toUtc().add(Duration(minutes: offset));

    final dateFull =
        '${tzDate.year.toString().padLeft(4, '0')}-${tzDate.month.toString().padLeft(2, '0')}-${tzDate.day.toString().padLeft(2, '0')} ${tzDate.hour.toString().padLeft(2, '0')}:${tzDate.minute.toString().padLeft(2, '0')}:${tzDate.second.toString().padLeft(2, '0')}';
    final dateShort =
        '${tzDate.year.toString().padLeft(4, '0')}-${tzDate.month.toString().padLeft(2, '0')}-${tzDate.day.toString().padLeft(2, '0')}';
    final timeFull =
        '${tzDate.hour.toString().padLeft(2, '0')}:${tzDate.minute.toString().padLeft(2, '0')}:${tzDate.second.toString().padLeft(2, '0')}';
    // 按框架生成日期格式（均带时区偏移，避免 Cloudflare UTC 构建机误解析）：
    // - Hugo: RFC3339 含偏移，instant 明确
    // - Jekyll: 完整日期时间，模板中附加 +0800 时区
    // - Astro: ISO 8601 格式（含时区），符合 Zod schema 校验
    // - 其他: 完整日期时间 + 偏移
    String dateForFramework;
    switch (frameworkId) {
      case 'hugo':
        dateForFramework = '${dateShort}T${timeFull}${_isoOffset(offset)}';
        break;
      case 'jekyll':
        dateForFramework = dateFull; // 模板中已有 +0800
        break;
      case 'astro':
        dateForFramework = '${dateShort}T${timeFull}${_isoOffset(offset)}';
        break;
      default:
        dateForFramework = '$dateFull ${_formatOffset(offset)}';
    }
    final tagsStr = tags.isEmpty
        ? '[]'
        : '[${tags.map((t) => t.contains(' ') ? '"$t"' : t).join(', ')}]';
    final catsStr = categories.isEmpty
        ? '[]'
        : '[${categories.map((c) => c.contains(' ') ? '"$c"' : c).join(', ')}]';

    // Pelican 使用逗号分隔的元数据格式，不是 YAML 数组
    // 空值时设为空字符串，后续会移除空行
    final pelicanTagsStr = tags.isEmpty ? '' : tags.join(', ');
    final pelicanCatsStr = categories.isEmpty ? '' : categories.join(', ');

    // ASCII slug：非 ASCII 标题（如中文）使用时间戳，避免 URL 编码问题
    final hasNonAscii = title.codeUnits.any((c) => c > 127);
    final slugValue = hasNonAscii
        ? 'post-${effectiveDate.millisecondsSinceEpoch}'
        : title.toLowerCase().replaceAll(RegExp(r'\s+'), '-');

    final fw = BlogFramework.byId(frameworkId);
    if (fw != null) {
      final template = articleType == ArticleType.page ? fw.pageFrontMatter : fw.postFrontMatter;
      if (template.isNotEmpty) {
        // 根据框架选择标签/分类格式
        final effectiveTagsStr = frameworkId == 'pelican' ? pelicanTagsStr : tagsStr;
        final effectiveCatsStr = frameworkId == 'pelican' ? pelicanCatsStr : catsStr;

        var fm = template
            .replaceAll('{{title}}', title.isEmpty ? '未命名' : title)
            .replaceAll('{{date}}', dateForFramework)
            .replaceAll('{{tags}}', effectiveTagsStr)
            .replaceAll('{{categories}}', effectiveCatsStr);
        if (cover != null && cover!.isNotEmpty) {
          fm = fm.replaceAll('{{cover}}', cover!);
        } else {
          // 移除包含 {{cover}} 的整行，避免生成空值
          fm = fm.replaceAll(RegExp(r'^.*\{\{cover\}\}.*\n', multiLine: true), '');
        }
        fm = fm.replaceAll('{{draft}}', isDraft.toString());
        fm = fm.replaceAll('{{slug}}', slugValue);
        // 移除所有未解析的模板占位符整行（如 {{summary}} 等）
        fm = fm.replaceAll(RegExp(r'^.*\{\{[^}]+\}\}.*\n', multiLine: true), '');

        // Pelican: 移除值为空的元数据行（如 "Tags: \n"、"Category: \n"）
        if (frameworkId == 'pelican') {
          fm = fm.replaceAll(RegExp(r'^(Tags|Category):\s*\n', multiLine: true), '');
        }

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

  /// 绑定框架 + 自定义模板的 toMarkdownWithFrontMatter
  ///
  /// 优先级：自定义模板 > 框架预设模板 > 通用回退
  /// [templates] 为可选的自定义模板列表，用于查找用户自定义的模板
  String toMarkdownWithFrontMatterForRepo(RepoConfig repo, {List<TemplateItem>? templates}) {
    // 1. 优先查找自定义模板
    if (templateId != null && templateId!.isNotEmpty && templates != null) {
      final customTemplate = templates.where((t) => t.id == templateId).firstOrNull;
      if (customTemplate != null) {
        // 生成时日期等动态值必须跟随"仓库绑定的框架"，避免
        // 模板所属框架与目标框架不一致导致生成非法 FrontMatter、
        // 文章在博客上不显示（如 Hugo 误用 Hexo 模板的完整日期格式）。
        return _applyCustomTemplate(customTemplate,
            repoFrameworkId: repo.frameworkId,
            timezoneOffsetMinutes: repo.publishTimeZoneOffsetMinutes);
      }
    }
    // 2. 回退到框架预设
    return toMarkdownWithFrontMatter(
        frameworkId: repo.frameworkId,
        timezoneOffsetMinutes: repo.publishTimeZoneOffsetMinutes);
  }

  /// 使用自定义模板生成 Markdown
  ///
  /// [repoFrameworkId] 为仓库绑定的博客框架 ID。模板仅决定 FrontMatter
  /// 的字段结构，日期 / 标签等动态值的格式一律跟随目标框架。
  String _applyCustomTemplate(TemplateItem template,
      {String? repoFrameworkId, int? timezoneOffsetMinutes}) {
    // 定时发布保留未来日期；否则未来日期保护
    final now = DateTime.now();
    final effectiveDate = schedulePublishAt ?? (createdAt.isAfter(now) ? now : createdAt);

    // 按发布时区转换墙钟时间（默认北京时间 +08:00）
    final offset = timezoneOffsetMinutes ?? 480;
    final tzDate = effectiveDate.toUtc().add(Duration(minutes: offset));

    final dateFull =
        '${tzDate.year.toString().padLeft(4, '0')}-${tzDate.month.toString().padLeft(2, '0')}-${tzDate.day.toString().padLeft(2, '0')} ${tzDate.hour.toString().padLeft(2, '0')}:${tzDate.minute.toString().padLeft(2, '0')}:${tzDate.second.toString().padLeft(2, '0')}';
    final dateShort =
        '${tzDate.year.toString().padLeft(4, '0')}-${tzDate.month.toString().padLeft(2, '0')}-${tzDate.day.toString().padLeft(2, '0')}';
    final timeFull =
        '${tzDate.hour.toString().padLeft(2, '0')}:${tzDate.minute.toString().padLeft(2, '0')}:${tzDate.second.toString().padLeft(2, '0')}';
    // 动态值格式跟随目标框架（仓库绑定框架优先）
    final targetFramework = repoFrameworkId ?? template.frameworkId;
    String dateForTemplate;
    switch (targetFramework) {
      case 'hugo':
        dateForTemplate = '${dateShort}T${timeFull}${_isoOffset(offset)}';
        break;
      case 'jekyll':
        dateForTemplate = dateFull; // 模板中已有 +0800
        break;
      case 'astro':
        dateForTemplate = '${dateShort}T${timeFull}${_isoOffset(offset)}';
        break;
      default:
        dateForTemplate = '$dateFull ${_formatOffset(offset)}';
    }
    final tagsStr = tags.isEmpty
        ? '[]'
        : '[${tags.map((t) => t.contains(' ') ? '"$t"' : t).join(', ')}]';
    final catsStr = categories.isEmpty
        ? '[]'
        : '[${categories.map((c) => c.contains(' ') ? '"$c"' : c).join(', ')}]';

    // Pelican 使用逗号分隔格式
    final pelicanTagsStr = tags.isEmpty ? '' : tags.join(', ');
    final pelicanCatsStr = categories.isEmpty ? '' : categories.join(', ');

    // ASCII slug：非 ASCII 标题使用时间戳
    final hasNonAscii = title.codeUnits.any((c) => c > 127);
    final slug = hasNonAscii
        ? 'post-${effectiveDate.millisecondsSinceEpoch}'
        : title.toLowerCase().replaceAll(RegExp(r'\s+'), '-');

    // 标签/分类格式跟随目标框架（Pelican 使用逗号分隔）
    final effectiveTagsStr = targetFramework == 'pelican' ? pelicanTagsStr : tagsStr;
    final effectiveCatsStr = targetFramework == 'pelican' ? pelicanCatsStr : catsStr;

    var fm = template.frontMatter
        .replaceAll('{{title}}', title.isEmpty ? '未命名' : title)
        .replaceAll('{{date}}', dateForTemplate)
        .replaceAll('{{date_short}}', dateShort)
        .replaceAll('{{tags}}', effectiveTagsStr)
        .replaceAll('{{categories}}', effectiveCatsStr)
        .replaceAll('{{slug}}', slug)
        .replaceAll('{{draft}}', isDraft.toString())
        .replaceAll('{{year}}', tzDate.year.toString())
        .replaceAll('{{month}}', tzDate.month.toString().padLeft(2, '0'))
        .replaceAll('{{day}}', tzDate.day.toString().padLeft(2, '0'));

    if (cover != null && cover!.isNotEmpty) {
      fm = fm.replaceAll('{{cover}}', cover!);
    } else {
      // 移除包含 {{cover}} 的整行，避免生成空值
      fm = fm.replaceAll(RegExp(r'^.*\{\{cover\}\}.*\n', multiLine: true), '');
    }

    // 移除所有未解析的模板占位符整行（如 {{summary}} 等）
    fm = fm.replaceAll(RegExp(r'^.*\{\{[^}]+\}\}.*\n', multiLine: true), '');

    // Pelican: 移除值为空的元数据行
    if (targetFramework == 'pelican') {
      fm = fm.replaceAll(RegExp(r'^(Tags|Category):\s*\n', multiLine: true), '');
    }

    return '$fm\n$content';
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
    bool isDraft = false;
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

  /// 将分钟偏移格式化为 +0800 / -0530 形式
  static String _formatOffset(int offsetMinutes) {
    final sign = offsetMinutes < 0 ? '-' : '+';
    final abs = offsetMinutes.abs();
    final h = (abs ~/ 60).toString().padLeft(2, '0');
    final m = (abs % 60).toString().padLeft(2, '0');
    return '$sign$h$m';
  }

  /// 将分钟偏移格式化为 ISO 8601 的 +08:00 / -05:30 形式
  static String _isoOffset(int offsetMinutes) {
    final base = _formatOffset(offsetMinutes);
    return '${base.substring(0, 3)}:${base.substring(3)}';
  }

  String fileName({bool postDatePrefix = false}) {
    // 未来日期保护：文件名中的日期前缀也不应为未来日期
    final effectiveDate = createdAt.isAfter(DateTime.now()) ? DateTime.now() : createdAt;
    final datePrefix = postDatePrefix
        ? '${effectiveDate.year.toString().padLeft(4, '0')}-${effectiveDate.month.toString().padLeft(2, '0')}-${effectiveDate.day.toString().padLeft(2, '0')}-'
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

  /// 根据仓库配置生成文件名
  /// Jekyll 等框架要求 YYYY-MM-DD-title.md 格式，由 repo.fileNameRule.postDatePrefix 控制
  String fileNameForRepo(RepoConfig repo) {
    return fileName(postDatePrefix: repo.fileNameRule.postDatePrefix);
  }
}

/// copyWith 哨兵类型：区分"未传递"与"显式传 null"
class _Undefined {
  const _Undefined();
}

extension ArticleSlug on Article {
  /// 生成 SEO 友好的 slug（处理中文、特殊符号）
  /// 非 ASCII 标题（如中文）使用时间戳，避免 URL 编码问题
  String toSlug() {
    final hasNonAscii = title.codeUnits.any((c) => c > 127);
    if (hasNonAscii) {
      // 未来日期保护
      final effectiveDate = createdAt.isAfter(DateTime.now()) ? DateTime.now() : createdAt;
      return 'post-${effectiveDate.millisecondsSinceEpoch}';
    }
    return title
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .toLowerCase();
  }
}