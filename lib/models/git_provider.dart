/// 仓库托管平台类型
enum GitProviderType { github, gitlab, gitee, bitbucket }

extension GitProviderTypeX on GitProviderType {
  String get label {
    switch (this) {
      case GitProviderType.github:
        return 'GitHub';
      case GitProviderType.gitlab:
        return 'GitLab';
      case GitProviderType.gitee:
        return 'Gitee';
      case GitProviderType.bitbucket:
        return 'Bitbucket';
    }
  }

  String get key {
    switch (this) {
      case GitProviderType.github:
        return 'github';
      case GitProviderType.gitlab:
        return 'gitlab';
      case GitProviderType.gitee:
        return 'gitee';
      case GitProviderType.bitbucket:
        return 'bitbucket';
    }
  }

  /// 从序列化键解析平台，未知值回退为 GitHub
  static GitProviderType fromKey(String? key) {
    switch (key) {
      case 'gitlab':
        return GitProviderType.gitlab;
      case 'gitee':
        return GitProviderType.gitee;
      case 'bitbucket':
        return GitProviderType.bitbucket;
      default:
        return GitProviderType.github;
    }
  }
}

/// 平台用户信息（各平台 /user 接口归一化后的结果）
class GitAccount {
  final String login;
  final String avatarUrl;
  final String htmlUrl;

  const GitAccount({
    this.login = '',
    this.avatarUrl = '',
    this.htmlUrl = '',
  });

  bool get isValid => login.isNotEmpty;
}
