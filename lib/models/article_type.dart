/// 文章类型枚举
/// 替换原有的 String articleType ('post'/'page')
enum ArticleType {
  post('post', '文章'),
  page('page', '页面');

  final String value;
  final String label;
  const ArticleType(this.value, this.label);

  static ArticleType fromString(String s) {
    switch (s.toLowerCase()) {
      case 'page':
        return ArticleType.page;
      default:
        return ArticleType.post;
    }
  }

  static ArticleType fromJson(dynamic v) {
    if (v is String) return fromString(v);
    return ArticleType.post;
  }
}