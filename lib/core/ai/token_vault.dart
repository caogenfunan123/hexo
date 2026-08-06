/// 令牌保险库：从当前站点安全提取鉴权凭据，脱敏后注入工具调用环境
library;

import '../../models/blog_site_config.dart';
import '../../models/repo_config.dart';

/// 站点凭据（脱敏表示，供 AI 感知存在性）
class SiteCredentials {
  final String kind;        // git / wordpress / ghost / typecho
  final String maskedToken; // 掩码表示
  final String envName;     // 服务层注入真实值用的环境变量名
  final bool hasToken;

  const SiteCredentials({
    required this.kind,
    this.maskedToken = '',
    this.envName = '',
    this.hasToken = false,
  });

  bool get valid => hasToken && maskedToken.isNotEmpty;
}

/// 从静态仓库（RepoConfig）或动态 CMS（BlogSiteConfig）提取并脱敏令牌。
///
/// 真实令牌只写入服务层调用环境，AI 上下文只持有掩码与环境变量名。
class TokenVault {
  /// 从静态仓库配置提取 Git Token
  SiteCredentials fromRepo(RepoConfig repo) {
    final token = repo.token;
    if (token.isEmpty) {
      return SiteCredentials(kind: 'git');
    }
    return SiteCredentials(
      kind: 'git',
      maskedToken: _mask(token),
      envName: 'SITE_GIT_TOKEN',
      hasToken: true,
    );
  }

  /// 从动态 CMS 站点配置提取凭据
  SiteCredentials fromBlogSite(BlogSiteConfig site) {
    switch (site.type) {
      case BlogType.wordpress:
        final pw = site.wpAppPassword ?? '';
        if (pw.isEmpty) return SiteCredentials(kind: 'wordpress');
        return SiteCredentials(
          kind: 'wordpress',
          maskedToken: _mask(pw),
          envName: 'SITE_WP_APP_PASSWORD',
          hasToken: true,
        );
      case BlogType.ghost:
        final key = site.ghostAdminApiKey ?? '';
        if (key.isEmpty) return SiteCredentials(kind: 'ghost');
        return SiteCredentials(
          kind: 'ghost',
          maskedToken: _mask(key),
          envName: 'SITE_GHOST_API_KEY',
          hasToken: true,
        );
      case BlogType.typecho:
        final token = site.typechoToken ?? '';
        if (token.isEmpty) return SiteCredentials(kind: 'typecho');
        return SiteCredentials(
          kind: 'typecho',
          maskedToken: _mask(token),
          envName: 'SITE_TYPECHO_TOKEN',
          hasToken: true,
        );
      default:
        return SiteCredentials(kind: site.type.name);
    }
  }

  /// 掩码脱敏：保留前 4 位与后 4 位，中间用星号代替
  static String _mask(String token) {
    if (token.length <= 10) return '****';
    final head = token.substring(0, 4);
    final tail = token.substring(token.length - 4);
    return '$head****$tail';
  }
}
