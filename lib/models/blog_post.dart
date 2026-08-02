import 'blog_site_config.dart';

/// 动态 CMS 文章模型
/// 与静态博客 [Article] 并行，不共享字段，避免冗余和混淆
///
/// 单向流转：Markdown 是唯一可信源
/// - 编辑时使用 contentMd
/// - 发布时根据平台转换为 contentHtml（Gutenberg HTML / Mobiledoc JSON / HTML）
/// - P0 不做"拉回编辑"，contentHtml 仅用于发布
class BlogPost {
  /// 远程 CMS 文章 ID（发布后由平台分配）
  final int? id;

  /// 文章标题
  final String title;

  /// Markdown 正文（唯一可信源）
  final String contentMd;

  /// 转换后的平台格式（Gutenberg HTML / Mobiledoc JSON / HTML）
  final String? contentHtml;

  /// 创建日期
  final DateTime date;

  /// 修改日期
  final DateTime modifiedDate;

  /// 发布状态：publish / draft / pending / trash
  final String status;

  /// URL slug
  final String? slug;

  /// 标签列表
  final List<String> tags;

  /// 分类列表
  final List<String> categories;

  /// 所属站点 ID（对应 BlogSiteConfig.id）
  final String? siteId;

  /// 所属站点类型
  final BlogType? siteType;

  /// 文章链接（发布后由平台返回）
  final String? link;

  const BlogPost({
    this.id,
    required this.title,
    required this.contentMd,
    this.contentHtml,
    required this.date,
    DateTime? modifiedDate,
    this.status = 'draft',
    this.slug,
    this.tags = const [],
    this.categories = const [],
    this.siteId,
    this.siteType,
    this.link,
  }) : modifiedDate = modifiedDate ?? date;

  /// 是否为已发布状态
  bool get isPublished => status == 'publish';

  /// 是否为草稿
  bool get isDraft => status == 'draft';

  /// 是否有远程 ID（已发布到平台）
  bool get hasRemoteId => id != null && id! > 0;

  BlogPost copyWith({
    Object? id = _sentinel,
    String? title,
    String? contentMd,
    Object? contentHtml = _sentinel,
    DateTime? date,
    DateTime? modifiedDate,
    String? status,
    Object? slug = _sentinel,
    List<String>? tags,
    List<String>? categories,
    Object? siteId = _sentinel,
    Object? siteType = _sentinel,
    Object? link = _sentinel,
  }) {
    return BlogPost(
      id: identical(id, _sentinel) ? this.id : id as int?,
      title: title ?? this.title,
      contentMd: contentMd ?? this.contentMd,
      contentHtml: identical(contentHtml, _sentinel) ? this.contentHtml : contentHtml as String?,
      date: date ?? this.date,
      modifiedDate: modifiedDate ?? this.modifiedDate,
      status: status ?? this.status,
      slug: identical(slug, _sentinel) ? this.slug : slug as String?,
      tags: tags ?? this.tags,
      categories: categories ?? this.categories,
      siteId: identical(siteId, _sentinel) ? this.siteId : siteId as String?,
      siteType: identical(siteType, _sentinel) ? this.siteType : siteType as BlogType?,
      link: identical(link, _sentinel) ? this.link : link as String?,
    );
  }

  static const Object _sentinel = Object();

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'title': title,
        'contentMd': contentMd,
        if (contentHtml != null) 'contentHtml': contentHtml,
        'date': date.toIso8601String(),
        'modifiedDate': modifiedDate.toIso8601String(),
        'status': status,
        if (slug != null) 'slug': slug,
        'tags': tags,
        'categories': categories,
        if (siteId != null) 'siteId': siteId,
        if (siteType != null) 'siteType': siteType!.name,
        if (link != null) 'link': link,
      };

  factory BlogPost.fromJson(Map<String, dynamic> j) {
    return BlogPost(
      id: (j['id'] as num?)?.toInt(),
      title: j['title']?.toString() ?? '',
      contentMd: j['contentMd']?.toString() ?? '',
      contentHtml: j['contentHtml']?.toString(),
      date: DateTime.tryParse(j['date']?.toString() ?? '') ?? DateTime.now(),
      modifiedDate: DateTime.tryParse(j['modifiedDate']?.toString() ?? '') ?? DateTime.now(),
      status: j['status']?.toString() ?? 'draft',
      slug: j['slug']?.toString(),
      tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
      categories: (j['categories'] as List?)?.map((e) => e.toString()).toList() ?? [],
      siteId: j['siteId']?.toString(),
      siteType: BlogType.fromString(j['siteType']?.toString()),
      link: j['link']?.toString(),
    );
  }

  @override
  String toString() => 'BlogPost($id, $title, $status)';
}