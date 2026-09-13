import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/git_provider.dart';
import '../models/repo_config.dart';
import 'github_service.dart';
import 'git_providers.dart';

/// 站点健康状态
class SiteHealthStatus {
  final RepoConfig repo;

  /// CI 构建状态：success / failure / in_progress / unknown
  final String ciStatus;
  final String? ciRunId;

  /// HTTP 可达性：200 / 重定向 / 失败 / 未检查
  final String httpStatus;
  final String? httpMessage;

  /// 页面非空
  final bool contentNonEmpty;

  /// 最后一次提交时间（该路径）
  final DateTime? lastCommit;

  /// 综合判定：一切正常
  bool get isHealthy =>
      ciStatus != 'failure' && httpStatus == 'ok' && contentNonEmpty;

  /// 一键触发构建是否可用（GitHub 且 CI 配置存在）
  final bool canTriggerBuild;

  final DateTime checkedAt;

  const SiteHealthStatus({
    required this.repo,
    required this.ciStatus,
    this.ciRunId,
    required this.httpStatus,
    this.httpMessage,
    required this.contentNonEmpty,
    this.lastCommit,
    required this.canTriggerBuild,
    required this.checkedAt,
  });
}

/// 站点运维监控服务
///
/// 聚合多个站点，执行：CI 状态查询、HTTP 健康检查（复用 verify_site 思路）、
/// 最后提交时间查询、一键触发构建。
class SiteHealthMonitor {
  SiteHealthMonitor({GitHubProvider? githubProvider})
      : _github = githubProvider ?? const GitHubProvider();

  final GitHubProvider _github;

  static const _timeout = Duration(seconds: 20);

  /// 检查单个站点
  Future<SiteHealthStatus> check(RepoConfig repo) async {
    final checkedAt = DateTime.now();
    String ciStatus = 'unknown';
    String? ciRunId;
    bool canTriggerBuild = false;

    if (repo.provider == GitProviderType.github && repo.token.isNotEmpty) {
      try {
        final run =
            await _github.getActionsRun(repo.token, repo.owner, repo.repo,
                branch: repo.branch);
        if (run != null) {
          ciStatus = run['status']?.toString() == 'completed'
              ? (run['conclusion']?.toString() ?? 'unknown')
              : 'in_progress';
          ciRunId = run['id']?.toString();
          canTriggerBuild = true;
        }
      } catch (e) {
        debugPrint('SiteHealthMonitor: CI 查询失败 ${repo.fullName}: $e');
        ciStatus = 'unknown';
      }
    }

    // HTTP 健康检查
    var httpStatus = 'not_checked';
    String? httpMessage;
    var contentNonEmpty = false;
    final siteUrl = repo.siteUrl;
    if (siteUrl.isNotEmpty) {
      final r = await _checkHttp(siteUrl);
      httpStatus = r.$1;
      httpMessage = r.$2;
      contentNonEmpty = r.$3;
    }

    // 最后提交时间
    DateTime? lastCommit;
    if (repo.token.isNotEmpty) {
      try {
        final adapter = GitHubService().adapter(repo);
        lastCommit = await adapter.latestCommitDate(repo, repo.postsPath);
      } catch (e) {
        debugPrint('SiteHealthMonitor: 最后提交查询失败: $e');
      }
    }

    return SiteHealthStatus(
      repo: repo,
      ciStatus: ciStatus,
      ciRunId: ciRunId,
      httpStatus: httpStatus,
      httpMessage: httpMessage,
      contentNonEmpty: contentNonEmpty,
      lastCommit: lastCommit,
      canTriggerBuild: canTriggerBuild,
      checkedAt: checkedAt,
    );
  }

  /// 触发 GitHub Actions 重新构建（创建空提交触发 push 事件 CI）。
  /// 统一走 GitHubProvider.request（认证/请求头/超时集中管理），
  /// 不再自建 HttpClient 硬编码 api.github.com。
  Future<void> triggerBuild(RepoConfig repo) async {
    if (repo.provider != GitProviderType.github) {
      throw Exception('仅支持 GitHub 站点触发构建');
    }
    final base = 'https://api.github.com';
    final owner = Uri.encodeComponent(repo.owner);
    final name = Uri.encodeComponent(repo.repo);
    final branch = Uri.encodeComponent(repo.branch);
    final refPath = '/repos/$owner/$name/git/refs/heads/$branch';

    // 1. 取当前 tip commit sha
    final refData = await _mapRequest(
        _github.request('GET', '$base$refPath', repo.token));
    final tip = refData?['object']?['sha']?.toString();
    if (tip == null || tip.isEmpty) {
      throw Exception('获取分支引用失败');
    }

    // 2. 取 tip tree sha（保持内容不变）
    final treeData = await _mapRequest(_github.request(
        'GET', '$base/repos/$owner/$name/git/trees/$tip', repo.token));
    final treeSha = treeData?['sha']?.toString();
    if (treeSha == null || treeSha.isEmpty) {
      throw Exception('获取 tree 失败');
    }

    // 3. 创建空提交
    final commitData = await _mapRequest(_github.request(
        'POST', '$base/repos/$owner/$name/git/commits', repo.token,
        body: {
          'message': 'chore: trigger CI build (site operations)',
          'tree': treeSha,
          'parents': [tip],
        }));
    final commitSha = commitData?['sha']?.toString();
    if (commitSha == null || commitSha.isEmpty) {
      throw Exception('创建 commit 失败');
    }

    // 4. fast-forward 更新分支引用
    await _github.request('PATCH', '$base$refPath', repo.token,
        body: {'sha': commitSha, 'force': false});
  }

  /// request 返回 dynamic：等待并收敛为 Map（失败原样抛出）
  Future<Map<String, dynamic>?> _mapRequest(Future<dynamic> f) async {
    final data = await f;
    if (data == null) return null;
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  /// HTTP 健康检查：返回 (状态, 消息, 内容非空)
  Future<(String, String, bool)> _checkHttp(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      return ('error', '无效 URL', false);
    }
    try {
      final client = HttpClient()
        ..connectionTimeout = _timeout;
      try {
        final request = await client.getUrl(uri);
        request.headers.set(
            'User-Agent', 'Mozilla/5.0 (compatible; HexoBlogManager/1.0 HealthCheck)');
        request.headers
            .set('Accept', 'text/html,application/xhtml+xml,text/plain');
        final response =
            await request.close().timeout(const Duration(seconds: 30));
        final raw = await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final cleaned = _stripHtml(raw).trim();
          return ('ok', 'HTTP 200 · ${cleaned.length} 字符', cleaned.isNotEmpty);
        }
        if (response.statusCode >= 300 && response.statusCode < 400) {
          return ('redirect', 'HTTP ${response.statusCode} 重定向', false);
        }
        return ('error', 'HTTP ${response.statusCode}', false);
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      return ('error', '请求失败: $e', false);
    }
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
