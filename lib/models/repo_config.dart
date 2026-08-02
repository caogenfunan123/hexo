/// 同步类型
enum SyncType {
  gitRemote,   // Git 远程仓库（手机端）
  localFolder, // 本地文件夹（PC端）
}

/// 文件名命名规则
class FileNameRule {
  final bool postDatePrefix; // 博文文件名是否自动加日期前缀
  final String dateFormat;   // 日期格式，默认 yyyy-MM-dd

  const FileNameRule({
    this.postDatePrefix = false,
    this.dateFormat = 'yyyy-MM-dd',
  });

  Map<String, dynamic> toJson() => {
        'postDatePrefix': postDatePrefix,
        'dateFormat': dateFormat,
      };

  factory FileNameRule.fromJson(Map<String, dynamic> j) => FileNameRule(
        postDatePrefix: j['postDatePrefix'] == true,
        dateFormat: j['dateFormat']?.toString() ?? 'yyyy-MM-dd',
      );

  /// 从框架预设生成默认规则
  factory FileNameRule.fromFramework(String frameworkId) {
    switch (frameworkId) {
      case 'hugo':
      case 'jekyll':
      case 'gatsby':
        return const FileNameRule(postDatePrefix: true);
      default:
        return const FileNameRule(postDatePrefix: false);
    }
  }
}

class RepoConfig {
  final String id;
  final String name;
  final String owner;
  final String repo;
  final String branch;
  final String postsPath;
  final String pagesPath; // 独立页面目录
  final String frameworkId; // 博客框架ID
  final bool postDatePrefix; // 博文文件名是否自动加日期前缀（兼容旧字段）
  final FileNameRule fileNameRule; // 文件名命名规则
  final String siteUrl;
  final String token;
  final bool isDefault;

  // ── 仓库 ↔ 模板联动核心字段 ──
  final String? defaultPostTemplateId; // 仓库默认文章模板ID
  final String? defaultPageTemplateId; // 仓库默认页面模板ID
  final SyncType syncType; // 同步类型

  const RepoConfig({
    required this.id,
    required this.name,
    required this.owner,
    required this.repo,
    this.branch = 'main',
    this.postsPath = 'source/_posts',
    this.pagesPath = 'source',
    this.frameworkId = 'hexo',
    this.postDatePrefix = false,
    FileNameRule? fileNameRule,
    this.siteUrl = '',
    required this.token,
    this.isDefault = false,
    this.defaultPostTemplateId,
    this.defaultPageTemplateId,
    this.syncType = SyncType.gitRemote,
  }) : fileNameRule = fileNameRule ??
            FileNameRule.fromFramework(frameworkId);

  RepoConfig copyWith({
    String? id,
    String? name,
    String? owner,
    String? repo,
    String? branch,
    String? postsPath,
    String? pagesPath,
    String? frameworkId,
    bool? postDatePrefix,
    FileNameRule? fileNameRule,
    String? siteUrl,
    String? token,
    bool? isDefault,
    Object? defaultPostTemplateId = _sentinel,
    Object? defaultPageTemplateId = _sentinel,
    SyncType? syncType,
  }) {
    // 切换框架时，如果未显式传入 fileNameRule，自动从框架预设生成
    final effectiveFrameworkId = frameworkId ?? this.frameworkId;
    final effectiveFileNameRule = fileNameRule ??
        (frameworkId != null && frameworkId != this.frameworkId
            ? FileNameRule.fromFramework(frameworkId)
            : this.fileNameRule);
    return RepoConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      owner: owner ?? this.owner,
      repo: repo ?? this.repo,
      branch: branch ?? this.branch,
      postsPath: postsPath ?? this.postsPath,
      pagesPath: pagesPath ?? this.pagesPath,
      frameworkId: effectiveFrameworkId,
      postDatePrefix: postDatePrefix ?? this.postDatePrefix,
      fileNameRule: effectiveFileNameRule,
      siteUrl: siteUrl ?? this.siteUrl,
      token: token ?? this.token,
      isDefault: isDefault ?? this.isDefault,
      defaultPostTemplateId: identical(defaultPostTemplateId, _sentinel)
          ? this.defaultPostTemplateId
          : defaultPostTemplateId as String?,
      defaultPageTemplateId: identical(defaultPageTemplateId, _sentinel)
          ? this.defaultPageTemplateId
          : defaultPageTemplateId as String?,
      syncType: syncType ?? this.syncType,
    );
  }

  static const Object _sentinel = Object();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'owner': owner,
        'repo': repo,
        'branch': branch,
        'postsPath': postsPath,
        'pagesPath': pagesPath,
        'frameworkId': frameworkId,
        'postDatePrefix': postDatePrefix,
        'fileNameRule': fileNameRule.toJson(),
        'siteUrl': siteUrl,
        'token': token,
        'isDefault': isDefault,
        'defaultPostTemplateId': defaultPostTemplateId,
        'defaultPageTemplateId': defaultPageTemplateId,
        'syncType': syncType.name,
      };

  factory RepoConfig.fromJson(Map<String, dynamic> j) {
    // 兼容旧版本没有 fileNameRule
    FileNameRule fnRule;
    if (j['fileNameRule'] is Map) {
      fnRule = FileNameRule.fromJson(Map<String, dynamic>.from(j['fileNameRule']));
    } else {
      fnRule = FileNameRule(
        postDatePrefix: j['postDatePrefix'] == true,
      );
    }

    // 兼容旧版本没有 syncType
    SyncType st = SyncType.gitRemote;
    final stStr = j['syncType']?.toString();
    if (stStr == 'localFolder') st = SyncType.localFolder;

    return RepoConfig(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      owner: j['owner']?.toString() ?? '',
      repo: j['repo']?.toString() ?? '',
      branch: j['branch']?.toString() ?? 'main',
      postsPath: j['postsPath']?.toString() ?? 'source/_posts',
      pagesPath: j['pagesPath']?.toString() ?? 'source',
      frameworkId: j['frameworkId']?.toString() ?? 'hexo',
      postDatePrefix: j['postDatePrefix'] == true,
      fileNameRule: fnRule,
      siteUrl: j['siteUrl']?.toString() ?? '',
      token: j['token']?.toString() ?? '',
      isDefault: j['isDefault'] == true,
      defaultPostTemplateId: j['defaultPostTemplateId']?.toString(),
      defaultPageTemplateId: j['defaultPageTemplateId']?.toString(),
      syncType: st,
    );
  }

  String get fullName => '$owner/$repo';
  String get apiBase => 'https://api.github.com/repos/$owner/$repo';

  /// 根据框架预设自动绑定默认模板ID
  static String? defaultPostTemplateForFramework(String frameworkId) {
    switch (frameworkId) {
      case 'hexo': return 'builtin_hexo_post';
      case 'hugo': return 'builtin_hugo_post';
      case 'jekyll': return 'builtin_jekyll_post';
      case 'vuepress': return 'builtin_vuepress_post';
      case 'gatsby': return 'builtin_gatsby_post';
      case 'nextjs': return 'builtin_nextjs_post';
      case 'astro': return 'builtin_astro_post';
      case 'pelican': return 'builtin_pelican_post';
      case '11ty': return 'builtin_11ty_post';
      default: return null;
    }
  }

  static String? defaultPageTemplateForFramework(String frameworkId) {
    switch (frameworkId) {
      case 'hexo': return 'builtin_hexo_page';
      case 'hugo': return 'builtin_hugo_page';
      case 'jekyll': return 'builtin_jekyll_page';
      case 'astro': return 'builtin_astro_page';
      default: return 'builtin_hexo_page'; // 通用回退
    }
  }
}