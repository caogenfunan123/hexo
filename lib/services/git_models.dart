/// 仓库文件/目录条目（各平台 contents/tree 接口归一化结果）
class GitHubFileItem {
  final String name;
  final String path;
  final String type;
  final String? sha;
  final int? size;
  final String? downloadUrl;
  DateTime? lastModified;

  GitHubFileItem({
    required this.name,
    required this.path,
    required this.type,
    this.sha,
    this.size,
    this.downloadUrl,
    this.lastModified,
  });

  factory GitHubFileItem.fromJson(Map<String, dynamic> j) => GitHubFileItem(
        name: j['name']?.toString() ?? '',
        path: j['path']?.toString() ?? '',
        type: j['type']?.toString() ?? '',
        sha: j['sha']?.toString(),
        size: (j['size'] as num?)?.toInt(),
        downloadUrl: j['download_url']?.toString(),
      );

  bool get isDir => type == 'dir' || type == 'tree';
}

/// 提交条目
class GitCommitItem {
  final String sha;
  final String message;
  final String author;
  final DateTime date;
  final String htmlUrl;

  GitCommitItem({
    required this.sha,
    required this.message,
    required this.author,
    required this.date,
    required this.htmlUrl,
  });

  /// GitHub 结构的提交条目解析
  factory GitCommitItem.fromJson(Map<String, dynamic> j) {
    final commit = j['commit'] is Map
        ? Map<String, dynamic>.from(j['commit'] as Map)
        : <String, dynamic>{};
    final author = commit['author'] is Map
        ? Map<String, dynamic>.from(commit['author'] as Map)
        : <String, dynamic>{};
    return GitCommitItem(
      sha: j['sha']?.toString() ?? '',
      message: commit['message']?.toString() ?? '',
      author: author['name']?.toString() ?? '',
      date:
          DateTime.tryParse(author['date']?.toString() ?? '') ?? DateTime.now(),
      htmlUrl: j['html_url']?.toString() ?? '',
    );
  }
}
