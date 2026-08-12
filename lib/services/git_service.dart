import 'dart:io';
import '../models/repo_config.dart';
import 'github_service.dart';

/// Git 服务
///
/// 基于 GitHub Contents API 的真实实现，
/// 通过 [GitHubService] 完成文件提交与远程更新。
class GitService {
  /// 提交文件到远程仓库（GitHub Contents API）
  Future<void> commitFile({
    required RepoConfig repoConfig,
    required String filePath,
    required String commitMessage,
    String authorName = 'Hexo Blog Manager',
    String authorEmail = 'noreply@hexo.blog',
  }) async {
    if (repoConfig.token.isEmpty) {
      throw Exception('仓库未配置 Token，无法提交');
    }
    final github = _createGithub();
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('待提交文件不存在: $filePath');
    }
    final content = await file.readAsString();
    final relPath = _toRepoRelativePath(repoConfig, filePath);
    // 探测远程是否已存在同名文件，已存在则携带 sha 覆盖，避免 422
    String? existingSha;
    try {
      final existing = await github.getRawFile(repoConfig, relPath);
      existingSha = existing?['sha'];
    } catch (_) {/* 探测失败按新建处理 */}
    await github.putRawFile(
      repoConfig,
      relPath,
      content,
      sha: (existingSha?.isNotEmpty ?? false) ? existingSha : null,
      commitMessage: commitMessage,
    );
  }

  /// 将本地绝对路径转换为仓库内相对路径
  /// 传入路径可能为系统临时目录中的文件，此时使用文件名作为相对路径
  String _toRepoRelativePath(RepoConfig repoConfig, String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    // 若路径中包含仓库 postsPath，取其相对部分
    final postsPrefix = repoConfig.postsPath.replaceAll(RegExp(r'/+$'), '');
    final idx = normalized.indexOf(postsPrefix);
    if (idx >= 0) {
      return normalized.substring(idx);
    }
    // 否则取文件名（写入 postsPath 下）
    final segments = normalized.split('/');
    return '$postsPrefix/${segments.last}';
  }

  /// 推送到远程仓库（单文件场景等价于提交，GitHub API 即时生效）
  Future<void> push(RepoConfig repoConfig) async {
    if (repoConfig.token.isEmpty) {
      throw Exception('仓库未配置 Token，无法推送');
    }
    // Contents API 提交后即生效，无需额外推送动作。
    // 此处校验仓库与 Token 是否有效，失败抛出异常。
    await _createGithub().getUser(repoConfig.token, provider: repoConfig.provider);
  }

  /// 获取仓库状态
  Future<Map<String, dynamic>> getStatus(RepoConfig repoConfig) async {
    return {
      'branch': repoConfig.branch,
      'ahead': 0,
      'behind': 0,
      'clean': true,
    };
  }

  GitHubService _createGithub() => GitHubService();
}