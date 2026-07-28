class RepoConfig {
  final String id;
  final String name;
  final String owner;
  final String repo;
  final String branch;
  final String postsPath;
  final String siteUrl;
  final String token;
  final bool isDefault;

  const RepoConfig({
    required this.id,
    required this.name,
    required this.owner,
    required this.repo,
    this.branch = 'main',
    this.postsPath = 'source/_posts',
    this.siteUrl = '',
    required this.token,
    this.isDefault = false,
  });

  RepoConfig copyWith({
    String? id,
    String? name,
    String? owner,
    String? repo,
    String? branch,
    String? postsPath,
    String? siteUrl,
    String? token,
    bool? isDefault,
  }) {
    return RepoConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      owner: owner ?? this.owner,
      repo: repo ?? this.repo,
      branch: branch ?? this.branch,
      postsPath: postsPath ?? this.postsPath,
      siteUrl: siteUrl ?? this.siteUrl,
      token: token ?? this.token,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'owner': owner,
        'repo': repo,
        'branch': branch,
        'postsPath': postsPath,
        'siteUrl': siteUrl,
        'token': token,
        'isDefault': isDefault,
      };

  factory RepoConfig.fromJson(Map<String, dynamic> j) => RepoConfig(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        owner: j['owner']?.toString() ?? '',
        repo: j['repo']?.toString() ?? '',
        branch: j['branch']?.toString() ?? 'main',
        postsPath: j['postsPath']?.toString() ?? 'source/_posts',
        siteUrl: j['siteUrl']?.toString() ?? '',
        token: j['token']?.toString() ?? '',
        isDefault: j['isDefault'] == true,
      );

  String get fullName => '$owner/$repo';
  String get apiBase => 'https://api.github.com/repos/$owner/$repo';
}
