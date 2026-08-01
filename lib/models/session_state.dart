import 'dart:convert';

/// 页面类型
enum SessionPageType {
  home,    // 写文章首页
  reader,  // 阅读页
  editor,  // 编辑器
}

/// 文章来源类型
enum ArticleSource {
  local,   // 本地草稿
  remote,  // 远程文章
}

/// 全局会话快照，用于 APP 重启后恢复状态
class SessionState {
  final SessionPageType pageType;
  final String articleId;
  final ArticleSource articleSource;
  final String articleTitle;
  final String articleContent;
  final String articleTags;
  final String articleCategories;
  final String articleCover;
  final String articleRepoId;
  final String articleRemotePath;
  final String articleRemoteSha;
  final double scrollOffset;
  final DateTime savedAt;

  SessionState({
    this.pageType = SessionPageType.home,
    this.articleId = '',
    this.articleSource = ArticleSource.local,
    this.articleTitle = '',
    this.articleContent = '',
    this.articleTags = '',
    this.articleCategories = '',
    this.articleCover = '',
    this.articleRepoId = '',
    this.articleRemotePath = '',
    this.articleRemoteSha = '',
    this.scrollOffset = 0.0,
    DateTime? savedAt,
  }) : savedAt = savedAt ?? DateTime.now();

  bool get hasArticle => articleId.isNotEmpty;

  bool get isHome => pageType == SessionPageType.home;

  Map<String, dynamic> toJson() => {
        'pageType': pageType.index,
        'articleId': articleId,
        'articleSource': articleSource.index,
        'articleTitle': articleTitle,
        'articleContent': articleContent,
        'articleTags': articleTags,
        'articleCategories': articleCategories,
        'articleCover': articleCover,
        'articleRepoId': articleRepoId,
        'articleRemotePath': articleRemotePath,
        'articleRemoteSha': articleRemoteSha,
        'scrollOffset': scrollOffset,
        'savedAt': savedAt.toIso8601String(),
      };

  factory SessionState.fromJson(Map<String, dynamic> j) {
    return SessionState(
      pageType: SessionPageType.values[j['pageType'] as int? ?? 0],
      articleId: j['articleId']?.toString() ?? '',
      articleSource: ArticleSource.values[j['articleSource'] as int? ?? 0],
      articleTitle: j['articleTitle']?.toString() ?? '',
      articleContent: j['articleContent']?.toString() ?? '',
      articleTags: j['articleTags']?.toString() ?? '',
      articleCategories: j['articleCategories']?.toString() ?? '',
      articleCover: j['articleCover']?.toString() ?? '',
      articleRepoId: j['articleRepoId']?.toString() ?? '',
      articleRemotePath: j['articleRemotePath']?.toString() ?? '',
      articleRemoteSha: j['articleRemoteSha']?.toString() ?? '',
      scrollOffset: (j['scrollOffset'] as num?)?.toDouble() ?? 0.0,
      savedAt: j['savedAt'] != null
          ? DateTime.tryParse(j['savedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// 空会话（首页状态）
  static final empty = SessionState();

  String toJsonString() => jsonEncode(toJson());

  factory SessionState.fromJsonString(String s) {
    try {
      return SessionState.fromJson(
          Map<String, dynamic>.from(jsonDecode(s)));
    } catch (_) {
      return SessionState.empty;
    }
  }
}