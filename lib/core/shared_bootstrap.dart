/// 共享引导工具
///
/// 提取 desktop_shell.dart 和 main.dart 中重复的引导逻辑，
/// 消除 70%+ 重复代码。
library;

import '../models/app_settings.dart';
import '../models/github_token_profile.dart';
import '../models/repo_config.dart';

/// 确保旧版 Token 迁移到新版 Token 列表
///
/// 原分别在 desktop_shell.dart 和 main.dart 中各有一份逐行相同的实现。
/// 现在统一到这里。
AppSettings ensureGithubTokensFromLegacy(AppSettings s, List<RepoConfig> repos) {
  var tokens = List<GithubTokenProfile>.from(s.githubTokens);
  bool changed = false;

  if (s.defaultToken.isNotEmpty && !tokens.any((t) => t.token == s.defaultToken)) {
    tokens.add(GithubTokenProfile(
      id: 'legacy_token',
      name: '默认 Token',
      token: s.defaultToken,
    ));
    changed = true;
  }

  for (final r in repos) {
    if (r.token.isNotEmpty && !tokens.any((t) => t.token == r.token)) {
      tokens.add(GithubTokenProfile(
        id: 'repo_${r.id}',
        name: r.name,
        token: r.token,
      ));
      changed = true;
    }
  }

  if (changed) {
    final seen = <String>{};
    tokens = tokens.where((t) => seen.add(t.token.trim())).toList();
    return s.copyWith(
      github: s.github.copyWith(
        githubTokens: tokens,
        activeGithubTokenId: tokens.first.id,
      ),
    );
  }
  return s;
}

/// 确保 repos 有 Token（从 settings 回填）
List<RepoConfig> backfillRepoTokens(List<RepoConfig> repos, String effectiveToken) {
  if (effectiveToken.isEmpty) return repos;
  var changed = false;
  final result = repos.map((r) {
    if (r.token.isEmpty) {
      changed = true;
      return r.copyWith(token: effectiveToken);
    }
    return r;
  }).toList();
  return changed ? result : repos;
}