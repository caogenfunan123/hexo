/// 主题商店条目：内置精选开源主题索引
///
/// 索引只保存元数据（不内置主题包），安装时从源仓库 codeload 下载。
class ThemeStoreItem {
  final String id;
  final String name;
  final String description;
  final String author;
  final String frameworkId; // hexo / hugo / jekyll / astro 等
  final String repoOwner;
  final String repoName;
  final String defaultBranch;
  final String? screenshotUrl;

  /// 站点配置文件中主题字段名（Hexo 为 theme，Hugo 为 theme）
  final String configKey;

  const ThemeStoreItem({
    required this.id,
    required this.name,
    required this.description,
    required this.author,
    required this.frameworkId,
    required this.repoOwner,
    required this.repoName,
    this.defaultBranch = 'master',
    this.screenshotUrl,
    this.configKey = 'theme',
  });

  /// 源仓库 GitHub 全名（owner/name）
  String get fullName => '$repoOwner/$repoName';

  /// codeload tar.gz 下载地址
  String get tarballUrl =>
      'https://codeload.github.com/$repoOwner/$repoName/tar.gz/refs/heads/$defaultBranch';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'author': author,
        'frameworkId': frameworkId,
        'repoOwner': repoOwner,
        'repoName': repoName,
        'defaultBranch': defaultBranch,
        'screenshotUrl': screenshotUrl,
        'configKey': configKey,
      };

  factory ThemeStoreItem.fromJson(Map<String, dynamic> j) => ThemeStoreItem(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
        author: j['author']?.toString() ?? '',
        frameworkId: j['frameworkId']?.toString() ?? 'hexo',
        repoOwner: j['repoOwner']?.toString() ?? '',
        repoName: j['repoName']?.toString() ?? '',
        defaultBranch: j['defaultBranch']?.toString() ?? 'master',
        screenshotUrl: j['screenshotUrl']?.toString(),
        configKey: j['configKey']?.toString() ?? 'theme',
      );
}
