/// 博客平台类型
/// 静态博客（本地文件 + Git 仓库）和动态 CMS（远程 API）统一枚举
enum BlogType {
  // ── 静态博客 ──
  hexo,
  hugo,
  astro,
  jekyll,
  vuepress,
  gatsby,
  nextjs,
  pelican,
  elevenly, // 11ty
  custom,

  // ── 动态 CMS ──
  wordpress,
  ghost,
  typecho,
  ;

  /// 是否为静态博客（基于本地文件 + Git）
  bool get isStatic => switch (this) {
        hexo || hugo || astro || jekyll || vuepress || gatsby || nextjs || pelican || elevenly || custom => true,
        _ => false,
      };

  /// 是否为动态 CMS（基于远程 API）
  bool get isDynamic => !isStatic;

  /// 是否为 WordPress
  bool get isWordPress => this == BlogType.wordpress;

  /// 是否为 Ghost
  bool get isGhost => this == BlogType.ghost;

  /// 是否为 Typecho
  bool get isTypecho => this == BlogType.typecho;

  /// 显示名称
  String get displayName => switch (this) {
        hexo => 'Hexo',
        hugo => 'Hugo',
        astro => 'Astro',
        jekyll => 'Jekyll',
        vuepress => 'VuePress',
        gatsby => 'Gatsby',
        nextjs => 'Next.js',
        pelican => 'Pelican',
        elevenly => '11ty',
        custom => '自定义',
        wordpress => 'WordPress',
        ghost => 'Ghost',
        typecho => 'Typecho',
      };

  /// 从字符串解析
  static BlogType fromString(String? s) {
    if (s == null || s.isEmpty) return hexo;
    return BlogType.values.firstWhere(
      (t) => t.name == s,
      orElse: () => hexo,
    );
  }
}

/// 动态 CMS 站点配置
/// 与静态博客的 [RepoConfig] 并行，互不干扰
class BlogSiteConfig {
  final String id;
  final String name;
  final BlogType type;

  /// 站点 URL（如 https://example.com）
  final String siteUrl;

  /// 是否忽略 SSL 证书错误（自签名证书场景）
  final bool ignoreSsl;

  /// ── WordPress 专属 ──
  final String? wpUsername;
  final String? wpAppPassword;

  /// ── Ghost 专属 ──
  /// Admin API Key，格式为 "id:secret"
  final String? ghostAdminApiKey;

  /// ── Typecho 专属 ──
  /// 自定义 API 端点（如 /api/posts，默认自动探测）
  final String? typechoApiEndpoint;
  /// 插件生成的 Token
  final String? typechoToken;

  /// 是否为默认站点
  final bool isDefault;

  /// ── 模板绑定 ──
  /// 默认文章模板 ID（CMS 站点也有模板概念）
  final String? defaultPostTemplateId;
  final String? defaultPageTemplateId;

  /// 创建时间
  final DateTime createdAt;

  const BlogSiteConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.siteUrl,
    this.ignoreSsl = false,
    this.wpUsername,
    this.wpAppPassword,
    this.ghostAdminApiKey,
    this.typechoApiEndpoint,
    this.typechoToken,
    this.isDefault = false,
    this.defaultPostTemplateId,
    this.defaultPageTemplateId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 判断指定类型的必填字段是否齐全
  bool get isValid {
    final urlOk = siteUrl.isNotEmpty;
    if (!urlOk) return false;
    return switch (type) {
      BlogType.wordpress => (wpUsername?.isNotEmpty ?? false) && (wpAppPassword?.isNotEmpty ?? false),
      BlogType.ghost => (ghostAdminApiKey?.isNotEmpty ?? false) && ghostAdminApiKey!.contains(':'),
      BlogType.typecho => (typechoToken?.isNotEmpty ?? false),
      _ => false,
    };
  }

  /// 获取鉴权状态描述
  String get authStatus {
    if (!isValid) return '未配置鉴权信息';
    return switch (type) {
      BlogType.wordpress => 'Application Password',
      BlogType.ghost => 'Admin API Key',
      BlogType.typecho => 'Token',
      _ => '未知',
    };
  }

  BlogSiteConfig copyWith({
    String? id,
    String? name,
    BlogType? type,
    String? siteUrl,
    bool? ignoreSsl,
    Object? wpUsername = _sentinel,
    Object? wpAppPassword = _sentinel,
    Object? ghostAdminApiKey = _sentinel,
    Object? typechoApiEndpoint = _sentinel,
    Object? typechoToken = _sentinel,
    bool? isDefault,
    Object? defaultPostTemplateId = _sentinel,
    Object? defaultPageTemplateId = _sentinel,
    DateTime? createdAt,
  }) {
    return BlogSiteConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      siteUrl: siteUrl ?? this.siteUrl,
      ignoreSsl: ignoreSsl ?? this.ignoreSsl,
      wpUsername: identical(wpUsername, _sentinel) ? this.wpUsername : wpUsername as String?,
      wpAppPassword: identical(wpAppPassword, _sentinel) ? this.wpAppPassword : wpAppPassword as String?,
      ghostAdminApiKey: identical(ghostAdminApiKey, _sentinel) ? this.ghostAdminApiKey : ghostAdminApiKey as String?,
      typechoApiEndpoint: identical(typechoApiEndpoint, _sentinel) ? this.typechoApiEndpoint : typechoApiEndpoint as String?,
      typechoToken: identical(typechoToken, _sentinel) ? this.typechoToken : typechoToken as String?,
      isDefault: isDefault ?? this.isDefault,
      defaultPostTemplateId: identical(defaultPostTemplateId, _sentinel) ? this.defaultPostTemplateId : defaultPostTemplateId as String?,
      defaultPageTemplateId: identical(defaultPageTemplateId, _sentinel) ? this.defaultPageTemplateId : defaultPageTemplateId as String?,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static const Object _sentinel = Object();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'siteUrl': siteUrl,
        'ignoreSsl': ignoreSsl,
        if (wpUsername != null) 'wpUsername': wpUsername,
        if (wpAppPassword != null) 'wpAppPassword': wpAppPassword,
        if (ghostAdminApiKey != null) 'ghostAdminApiKey': ghostAdminApiKey,
        if (typechoApiEndpoint != null) 'typechoApiEndpoint': typechoApiEndpoint,
        if (typechoToken != null) 'typechoToken': typechoToken,
        'isDefault': isDefault,
        'createdAt': createdAt.toIso8601String(),
        if (defaultPostTemplateId != null) 'defaultPostTemplateId': defaultPostTemplateId,
        if (defaultPageTemplateId != null) 'defaultPageTemplateId': defaultPageTemplateId,
      };

  factory BlogSiteConfig.fromJson(Map<String, dynamic> j) {
    return BlogSiteConfig(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      type: BlogType.fromString(j['type']?.toString()),
      siteUrl: j['siteUrl']?.toString() ?? '',
      ignoreSsl: j['ignoreSsl'] == true,
      wpUsername: j['wpUsername']?.toString(),
      wpAppPassword: j['wpAppPassword']?.toString(),
      ghostAdminApiKey: j['ghostAdminApiKey']?.toString(),
      typechoApiEndpoint: j['typechoApiEndpoint']?.toString(),
      typechoToken: j['typechoToken']?.toString(),
      isDefault: j['isDefault'] == true,
      createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
      defaultPostTemplateId: j['defaultPostTemplateId']?.toString(),
      defaultPageTemplateId: j['defaultPageTemplateId']?.toString(),
    );
  }

  @override
  String toString() => 'BlogSiteConfig($name, $type, $siteUrl)';
}