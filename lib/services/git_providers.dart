import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/git_provider.dart';
import '../models/repo_config.dart';
import 'git_http.dart';
import 'git_models.dart';
import 'git_provider_adapter.dart';

/// GitHub 适配器（默认平台）
class GitHubProvider implements GitProviderAdapter {
  const GitHubProvider();

  @override
  GitProviderType get type => GitProviderType.github;

  @override
  String apiBase(RepoConfig repo) =>
      'https://api.github.com/repos/${repo.owner}/${repo.repo}';

  @override
  Future<GitAccount> getUser(String token) async {
    final data = await request('GET', 'https://api.github.com/user', token);
    if (data is! Map) throw Exception('无法解析 GitHub 用户信息');
    return GitAccount(
      login: data['login']?.toString() ?? '',
      avatarUrl: data['avatar_url']?.toString() ?? '',
      htmlUrl: data['html_url']?.toString() ?? '',
    );
  }

  @override
  Future<dynamic> request(
    String method,
    String url,
    String token, {
    Object? body,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'HexoBlogManager',
      'Content-Type': 'application/json',
    };
    if (token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    return gitHttpRequest(method, url, headers, jsonBody: body);
  }

  @override
  Future<List<GitHubFileItem>> listContents(
      RepoConfig repo, String path) async {
    final p = path.replaceAll(RegExp(r'/+$'), '');
    final url =
        '${apiBase(repo)}/contents/${encPathSegments(p)}?ref=${Uri.encodeComponent(repo.branch)}';
    final data = await request('GET', url, repo.token);
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((e) => GitHubFileItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<Map<String, String>?> readFile(
      RepoConfig repo, String path) async {
    return _read(repo, path, repo.branch);
  }

  @override
  Future<Map<String, String>?> readFileAtRef(
      RepoConfig repo, String path, String ref) async {
    return _read(repo, path, ref);
  }

  Future<Map<String, String>?> _read(
      RepoConfig repo, String path, String ref) async {
    final url =
        '${apiBase(repo)}/contents/${encPathSegments(path)}?ref=${Uri.encodeComponent(ref)}';
    try {
      final data = await request('GET', url, repo.token);
      if (data is! Map) return null;
      final contentB64 =
          (data['content']?.toString() ?? '').replaceAll('\n', '');
      if (contentB64.isEmpty) return null;
      return {
        'content': utf8.decode(base64Decode(contentB64)),
        'sha': data['sha']?.toString() ?? '',
      };
    } catch (e) {
      debugPrint('GitHub: readFile failed: $e');
      return null;
    }
  }

  @override
  Future<String?> writeFile(
    RepoConfig repo,
    String path,
    List<int> bytes, {
    String? sha,
    required String message,
  }) async {
    final body = <String, dynamic>{
      'message': message,
      'content': base64Encode(bytes),
      'branch': repo.branch,
    };
    if (sha != null && sha.isNotEmpty) body['sha'] = sha;
    final data = await request(
      'PUT',
      '${apiBase(repo)}/contents/${encPathSegments(path)}',
      repo.token,
      body: body,
    );
    if (data is Map && data['content'] is Map) {
      return (data['content'] as Map)['sha']?.toString();
    }
    return null;
  }

  @override
  Future<void> deleteFile(
    RepoConfig repo,
    String path,
    String sha, {
    required String message,
  }) async {
    final body = <String, dynamic>{
      'message': message,
      'sha': sha,
      'branch': repo.branch,
    };
    await request(
      'DELETE',
      '${apiBase(repo)}/contents/${encPathSegments(path)}',
      repo.token,
      body: body,
    );
  }

  @override
  Future<List<GitCommitItem>> listCommits(
    RepoConfig repo, {
    int perPage = 30,
    String? path,
  }) async {
    final pathParam = (path != null && path.isNotEmpty)
        ? '&path=${Uri.encodeComponent(path)}'
        : '';
    final url =
        '${apiBase(repo)}/commits?sha=${Uri.encodeComponent(repo.branch)}&per_page=$perPage$pathParam';
    final data = await request('GET', url, repo.token);
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((e) => GitCommitItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<DateTime?> latestCommitDate(RepoConfig repo, String path) async {
    final url =
        '${apiBase(repo)}/commits?path=${encPathSegments(path)}&sha=${Uri.encodeComponent(repo.branch)}&per_page=1';
    final data = await request('GET', url, repo.token);
    if (data is List && data.isNotEmpty) {
      final cm = (data[0] as Map)['commit'] as Map?;
      final au = cm?['author'] as Map?;
      return DateTime.tryParse(au?['date']?.toString() ?? '');
    }
    return null;
  }

  @override
  String rawUrl(RepoConfig repo, String path) =>
      'https://raw.githubusercontent.com/${repo.owner}/${repo.repo}/${repo.branch}/${encPathSegments(path)}';

  /// Git Data API 批量提交：一次 commit 上传多个文件。
  ///
  /// 流程：POST /git/blobs 创建每个文件的 blob → POST /git/trees
  /// 组装 tree（基于当前分支 tip）→ POST /git/commits 创建 commit →
  /// PATCH /git/refs/heads/{branch} 更新分支引用。
  /// 相比 Contents API 逐文件 PUT，此方式只需一次 commit，速度更快、
  /// 减少 422 并发冲突，且支持同一 commit 原子提交全部文件。
  Future<void> writeBatch(
    RepoConfig repo,
    List<({String path, List<int> bytes})> files, {
    required String message,
    String? authorName,
    String? authorEmail,
  }) async {
    if (files.isEmpty) return;
    final base = apiBase(repo);
    final branchRef = 'heads/${repo.branch}';

    // 1. 取当前分支 tip commit sha
    final refData = await request(
        'GET', '$base/git/ref/$branchRef', repo.token);
    if (refData is! Map) throw Exception('获取分支引用失败');
    final tipCommit = refData['object']?['sha']?.toString();
    if (tipCommit == null || tipCommit.isEmpty) {
      throw Exception('分支 ${repo.branch} 不存在');
    }

    // 2. 逐文件创建 blob
    final blobs = <String, String>{};
    for (final f in files) {
      final body = <String, dynamic>{
        'content': base64Encode(f.bytes),
        'encoding': 'base64',
      };
      final data =
          await request('POST', '$base/git/blobs', repo.token, body: body);
      if (data is! Map) throw Exception('创建 blob 失败: ${f.path}');
      blobs[f.path] = data['sha']?.toString() ?? '';
    }

    // 3. 组装 tree（含子目录路径拆解）
    final treeEntries = <Map<String, dynamic>>[];
    for (final f in files) {
      treeEntries.add({
        'path': f.path,
        'mode': '100644',
        'type': 'blob',
        'sha': blobs[f.path],
      });
    }
    final treeBody = <String, dynamic>{
      'base_tree': tipCommit,
      'tree': treeEntries,
    };
    final treeData =
        await request('POST', '$base/git/trees', repo.token, body: treeBody);
    if (treeData is! Map) throw Exception('创建 tree 失败');
    final treeSha = treeData['sha']?.toString() ?? '';
    if (treeSha.isEmpty) throw Exception('创建 tree 失败');

    // 4. 创建 commit
    final commitBody = <String, dynamic>{
      'message': message,
      'tree': treeSha,
      'parents': [tipCommit],
    };
    if ((authorName?.isNotEmpty ?? false) ||
        (authorEmail?.isNotEmpty ?? false)) {
      commitBody['author'] = {
        'name': authorName ?? 'Hexo Blog Manager',
        'email': authorEmail ?? 'noreply@hexo.blog',
      };
      commitBody['committer'] = {
        'name': authorName ?? 'Hexo Blog Manager',
        'email': authorEmail ?? 'noreply@hexo.blog',
      };
    }
    final commitData =
        await request('POST', '$base/git/commits', repo.token,
            body: commitBody);
    if (commitData is! Map) throw Exception('创建 commit 失败');
    final commitSha = commitData['sha']?.toString() ?? '';
    if (commitSha.isEmpty) throw Exception('创建 commit 失败');

    // 5. 更新分支引用（fast-forward）
    await request(
      'PATCH',
      '$base/git/refs/$branchRef',
      repo.token,
      body: {'sha': commitSha, 'force': false},
    );
  }

  // ────────────────────────────────────────────────
  // 一键建站扩展（Requirement 3/5/7/10）
  // ────────────────────────────────────────────────

  /// 创建仓库。返回完整仓库 JSON（含 default_branch / full_name）。
  /// 默认分支由账号设置决定，可能是 main 或 master，随后用 [initDefaultBranch] 规整。
  Future<Map<String, dynamic>> createRepository(
      String token, String name, bool private) async {
    final data = await request('POST', 'https://api.github.com/user/repos',
        token,
        body: {
          'name': name,
          'private': private,
          'auto_init': true, // 带初始 commit，保证有默认分支
          'description': '一键建站生成的博客仓库',
        });
    if (data is! Map) throw Exception('创建 GitHub 仓库失败');
    return Map<String, dynamic>.from(data);
  }

  /// 规整默认分支为 main：若默认分支不是 main，从默认分支创建 main 引用。
  Future<void> initDefaultBranch(
      String token, String owner, String name) async {
    final base = 'https://api.github.com/repos/$owner/$name';
    final repoData =
        await request('GET', base, token);
    if (repoData is! Map) throw Exception('读取仓库信息失败');
    final defaultBranch = repoData['default_branch']?.toString() ?? 'main';
    if (defaultBranch == 'main') return;

    final refData = await request(
        'GET', '$base/git/ref/heads/$defaultBranch', token);
    if (refData is! Map) throw Exception('读取默认分支引用失败');
    final sha = refData['object']?['sha']?.toString();
    if (sha == null || sha.isEmpty) {
      throw Exception('默认分支 $defaultBranch 无提交');
    }
    await request('POST', '$base/git/refs', token, body: {
      'ref': 'refs/heads/main',
      'sha': sha,
    });
  }

  /// 启用 GitHub Pages（source = GitHub Actions，站点由仓库内 CI 构建）。
  Future<void> enablePages(String token, String owner, String name) async {
    try {
      final data = await request(
          'POST', 'https://api.github.com/repos/$owner/$name/pages', token,
          body: {
            'build_type': 'workflow', // 与 source 互斥，勿同时传，否则 422
          });
      // 202 / 201 均视为成功；部分账号首次启用返回 201
      if (data is! Map && data != null) {
        throw Exception('启用 GitHub Pages 失败');
      }
    } catch (e) {
      final msg = e.toString();
      // 409：Pages 已启用（幂等成功）；其余错误上抛
      if (msg.contains('HTTP 409')) {
        debugPrint('GitHub Pages 已启用，忽略 409: $e');
        return;
      }
      rethrow;
    }
  }

  /// 查询指定分支最近一次 workflow run。返回 run JSON；无匹配 run 返回 null。
  Future<Map<String, dynamic>?> getActionsRun(
      String token, String owner, String name,
      {String branch = 'main'}) async {
    final data = await request(
        'GET',
        'https://api.github.com/repos/$owner/$name/actions/runs?branch=${Uri.encodeComponent(branch)}&per_page=1',
        token);
    if (data is! Map) return null;
    final runs = data['workflow_runs'];
    if (runs is! List || runs.isEmpty) return null;
    final first = runs.first;
    if (first is! Map) return null;
    return Map<String, dynamic>.from(first);
  }

  /// 删除仓库（回滚用）。
  Future<void> deleteRepository(
      String token, String owner, String name) async {
    await request(
        'DELETE', 'https://api.github.com/repos/$owner/$name', token);
  }

  /// 校验 token scope。返回 {scopes, missing, plan, scope_unknown}：
  /// scopes 为完整 scope 列表；missing 为缺少的必要 scope（repo/workflow）；
  /// plan 为账号计划名（free / pro / team / enterprise）；
  /// scope_unknown 为 true 表示无法读取 scope（fine-grained PAT 不返回 X-OAuth-Scopes 头），
  /// 此时不判定缺失，由后续真实 API 调用验证权限。
  /// GitHub 免费账号私有仓库不能启用 Pages（Correctness 14）。
  Future<Map<String, dynamic>> verifyScopes(String token) async {
    final scopes = await _getGitHubScopes(token);
    // fine-grained PAT 不返回 X-OAuth-Scopes 头，无法静态校验，放行由后续调用验证
    final scopeUnknown = scopes.isEmpty;
    final missing = <String>[];
    if (!scopeUnknown) {
      if (!scopes.contains('repo')) missing.add('repo');
      if (!scopes.contains('workflow')) missing.add('workflow');
    }

    var plan = '';
    try {
      final user = await request('GET', 'https://api.github.com/user', token);
      if (user is Map) {
        final p = user['plan'];
        if (p is Map) plan = p['name']?.toString() ?? '';
      }
    } catch (_) {}

    return {
      'scopes': scopes,
      'missing': missing,
      'plan': plan,
      'scope_unknown': scopeUnknown,
    };
  }

  /// 读取 GitHub /user 的 X-OAuth-Scopes 响应头（gitHttpRequest 不返回头，单独请求）。
  Future<List<String>> _getGitHubScopes(String token) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client
          .getUrl(Uri.parse('https://api.github.com/user'));
      req.headers.set('Authorization', 'Bearer $token');
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('X-GitHub-Api-Version', '2022-11-28');
      req.headers.set('User-Agent', 'HexoBlogManager');
      final res = await req.close().timeout(const Duration(seconds: 30));
      await res.drain<void>();
      final raw = res.headers.value('X-OAuth-Scopes') ?? '';
      return raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } finally {
      client.close(force: true);
    }
  }

  /// 切换仓库可见性（站点管理）。
  Future<void> updateVisibility(
      String token, String owner, String name, bool private) async {
    await request('PATCH', 'https://api.github.com/repos/$owner/$name', token,
        body: {'private': private});
  }

  /// 设置自定义域名（PUT /repos/{owner}/{name}/pages 的 cname 字段）。
  Future<void> setCustomDomain(
      String token, String owner, String name, String cname) async {
    final body = <String, dynamic>{'cname': cname};
    if (cname.isEmpty) body['cname'] = null;
    await request(
        'PUT', 'https://api.github.com/repos/$owner/$name/pages', token,
        body: body);
  }
}

/// GitLab 适配器（gitlab.com）
class GitLabProvider implements GitProviderAdapter {
  const GitLabProvider();

  @override
  GitProviderType get type => GitProviderType.gitlab;

  @override
  String apiBase(RepoConfig repo) =>
      'https://gitlab.com/api/v4/projects/${Uri.encodeComponent('${repo.owner}/${repo.repo}')}';

  @override
  Future<GitAccount> getUser(String token) async {
    final data =
        await request('GET', 'https://gitlab.com/api/v4/user', token);
    if (data is! Map) throw Exception('无法解析 GitLab 用户信息');
    return GitAccount(
      login: data['username']?.toString() ?? '',
      avatarUrl: data['avatar_url']?.toString() ?? '',
      htmlUrl: data['web_url']?.toString() ?? '',
    );
  }

  @override
  Future<dynamic> request(
    String method,
    String url,
    String token, {
    Object? body,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'HexoBlogManager',
      'Content-Type': 'application/json',
    };
    if (token.isNotEmpty) headers['PRIVATE-TOKEN'] = token;
    return gitHttpRequest(method, url, headers, jsonBody: body);
  }

  @override
  Future<List<GitHubFileItem>> listContents(
      RepoConfig repo, String path) async {
    final p = path.replaceAll(RegExp(r'/+$'), '');
    final items = <GitHubFileItem>[];
    final pathParam = p.isEmpty ? '' : '&path=${Uri.encodeComponent(p)}';
    // GitLab tree 接口按 100/页 分页，最多拉取 5 页避免无限循环
    for (var page = 1; page <= 5; page++) {
      final url =
          '${apiBase(repo)}/repository/tree?ref=${Uri.encodeComponent(repo.branch)}$pathParam&per_page=100&page=$page';
      final data = await request('GET', url, repo.token);
      if (data is! List || data.isEmpty) break;
      for (final e in data.whereType<Map>()) {
        final m = Map<String, dynamic>.from(e);
        items.add(GitHubFileItem(
          name: m['name']?.toString() ?? '',
          path: m['path']?.toString() ?? '',
          type: m['type']?.toString() == 'tree' ? 'dir' : 'file',
        ));
      }
      if (data.length < 100) break;
    }
    return items;
  }

  @override
  Future<Map<String, String>?> readFile(
      RepoConfig repo, String path) async {
    return _read(repo, path, repo.branch);
  }

  @override
  Future<Map<String, String>?> readFileAtRef(
      RepoConfig repo, String path, String ref) async {
    return _read(repo, path, ref);
  }

  Future<Map<String, String>?> _read(
      RepoConfig repo, String path, String ref) async {
    final url =
        '${apiBase(repo)}/repository/files/${encPathFull(path)}?ref=${Uri.encodeComponent(ref)}';
    try {
      final data = await request('GET', url, repo.token);
      if (data is! Map) return null;
      final contentB64 =
          (data['content']?.toString() ?? '').replaceAll('\n', '');
      if (contentB64.isEmpty) return null;
      return {
        'content': utf8.decode(base64Decode(contentB64)),
        'sha': data['blob_id']?.toString() ?? '',
      };
    } catch (e) {
      debugPrint('GitLab: readFile failed: $e');
      return null;
    }
  }

  @override
  Future<String?> writeFile(
    RepoConfig repo,
    String path,
    List<int> bytes, {
    String? sha,
    required String message,
  }) async {
    final body = <String, dynamic>{
      'branch': repo.branch,
      'content': base64Encode(bytes),
      'encoding': 'base64',
      'commit_message': message,
    };
    final data = await request(
      'PUT',
      '${apiBase(repo)}/repository/files/${encPathFull(path)}',
      repo.token,
      body: body,
    );
    if (data is Map) {
      return data['blob_id']?.toString();
    }
    return null;
  }

  @override
  Future<void> deleteFile(
    RepoConfig repo,
    String path,
    String sha, {
    required String message,
  }) async {
    final body = <String, dynamic>{
      'branch': repo.branch,
      'commit_message': message,
    };
    await request(
      'DELETE',
      '${apiBase(repo)}/repository/files/${encPathFull(path)}',
      repo.token,
      body: body,
    );
  }

  @override
  Future<List<GitCommitItem>> listCommits(
    RepoConfig repo, {
    int perPage = 30,
    String? path,
  }) async {
    final pathParam = (path != null && path.isNotEmpty)
        ? '&path=${Uri.encodeComponent(path)}'
        : '';
    final url =
        '${apiBase(repo)}/repository/commits?ref_name=${Uri.encodeComponent(repo.branch)}&per_page=$perPage$pathParam';
    final data = await request('GET', url, repo.token);
    if (data is! List) return [];
    return data.whereType<Map>().map((e) {
      final m = Map<String, dynamic>.from(e);
      return GitCommitItem(
        sha: m['id']?.toString() ?? '',
        message: m['message']?.toString() ?? m['title']?.toString() ?? '',
        author: m['author_name']?.toString() ?? '',
        date:
            DateTime.tryParse(m['committed_date']?.toString() ?? '') ??
            DateTime.now(),
        htmlUrl: m['web_url']?.toString() ?? '',
      );
    }).toList();
  }

  @override
  Future<DateTime?> latestCommitDate(RepoConfig repo, String path) async {
    final url =
        '${apiBase(repo)}/repository/commits?path=${Uri.encodeComponent(path)}&ref_name=${Uri.encodeComponent(repo.branch)}&per_page=1';
    final data = await request('GET', url, repo.token);
    if (data is List && data.isNotEmpty) {
      return DateTime.tryParse(
          (data[0] as Map)['committed_date']?.toString() ?? '');
    }
    return null;
  }

  @override
  String rawUrl(RepoConfig repo, String path) =>
      'https://gitlab.com/${repo.owner}/${repo.repo}/-/raw/${repo.branch}/${encPathSegments(path)}';

  // ────────────────────────────────────────────────
  // 一键建站扩展（Requirement 3/5/7/10）
  // ────────────────────────────────────────────────

  /// 创建 GitLab 项目。返回完整项目 JSON（含 id / default_branch / path_with_namespace）。
  Future<Map<String, dynamic>> createProject(
      String token, String name, bool private) async {
    final data = await request('POST', 'https://gitlab.com/api/v4/projects',
        token,
        body: {
          'name': name,
          'visibility': private ? 'private' : 'public',
          'initialize_with_readme': true, // 带初始 README，保证有 main 分支
          'default_branch': 'main',
          'description': '一键建站生成的博客项目',
        });
    if (data is! Map) throw Exception('创建 GitLab 项目失败');
    return Map<String, dynamic>.from(data);
  }

  /// 规整默认分支为 main：若默认分支不是 main，从默认分支创建 main 引用。
  Future<void> initDefaultBranch(
      String token, String projectId, String? defaultBranch) async {
    final branch =
        (defaultBranch == null || defaultBranch.isEmpty) ? 'main' : defaultBranch;
    if (branch == 'main') return;
    // GitLab 需要先读取默认分支 tip 才能创建新分支
    final tip = await request(
        'GET',
        'https://gitlab.com/api/v4/projects/$projectId/repository/branches/$branch',
        token);
    if (tip is! Map) throw Exception('读取默认分支 $branch 失败');
    await request(
        'POST',
        'https://gitlab.com/api/v4/projects/$projectId/repository/branches',
        token,
        body: {
          'branch': 'main',
          'ref': branch,
        });
  }

  /// 启用 GitLab Pages。
  ///
  /// gitlab.com 上 Pages 在首次成功部署后自动启用，此调用主要用于确保域名相关设置。
  /// 使用 PATCH /projects/{id}/pages（PUT 已在 GitLab 17.0 起废弃）。
  /// 若 Pages 尚未部署或端点不可用，静默忽略——不应阻塞建站流程。
  Future<void> enablePages(String token, String projectId) async {
    try {
      await request(
          'PATCH',
          'https://gitlab.com/api/v4/projects/$projectId/pages',
          token,
          body: {'pages_https_only': true});
    } catch (e) {
      // GitLab Pages 首次部署后自动启用；此处失败不阻塞建站
      debugPrint('GitLab enablePages 忽略失败: $e');
    }
  }

  /// 查询最近一次 pipeline。返回 pipeline JSON；无任何 pipeline 返回 null。
  Future<Map<String, dynamic>?> getPipeline(
      String token, String projectId) async {
    final data = await request(
        'GET',
        'https://gitlab.com/api/v4/projects/$projectId/pipelines?per_page=1',
        token);
    if (data is! List || data.isEmpty) return null;
    final first = data.first;
    if (first is! Map) return null;
    return Map<String, dynamic>.from(first);
  }

  /// 删除项目（回滚用）。
  Future<void> deleteProject(String token, String projectId) async {
    await request('DELETE',
        'https://gitlab.com/api/v4/projects/$projectId', token);
  }

  /// 校验 token scope。返回 {scopes, missing}：
  /// scopes 为完整 scope 列表；missing 为缺少的必要 scope（api）。
  Future<Map<String, dynamic>> verifyScopes(String token) async {
    // GitLab 的 PAT scope 只能从 /oauth/token/info 获取（/user 不返回 scopes）。
    // 该端点要求 Bearer 认证。
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'HexoBlogManager',
      'Authorization': 'Bearer $token',
    };
    final data = await gitHttpRequest(
        'GET', 'https://gitlab.com/api/v4/oauth/token/info', headers);
    final scopes = <String>[];
    if (data is Map) {
      final raw = data['scopes'];
      if (raw is List) {
        scopes.addAll(raw.map((e) => e.toString()));
      } else if (data['scope'] is String) {
        scopes.addAll((data['scope'] as String).split(' '));
      }
    }
    final missing = <String>[];
    if (!scopes.contains('api')) missing.add('api');
    return {'scopes': scopes, 'missing': missing, 'plan': ''};
  }

  /// 设置自定义域名（PUT /api/v4/projects/{id}/pages 的 domain 字段）。
  Future<void> setCustomDomain(
      String token, String projectId, String cname) async {
    final body = <String, dynamic>{'domain': cname};
    if (cname.isEmpty) body['domain'] = null;
    await request('PUT',
        'https://gitlab.com/api/v4/projects/$projectId/pages', token,
        body: body);
  }
}

/// Gitee 适配器（gitee.com，API 结构与 GitHub 高度一致）
class GiteeProvider implements GitProviderAdapter {
  const GiteeProvider();

  @override
  GitProviderType get type => GitProviderType.gitee;

  @override
  String apiBase(RepoConfig repo) =>
      'https://gitee.com/api/v5/repos/${repo.owner}/${repo.repo}';

  @override
  Future<GitAccount> getUser(String token) async {
    final data = await request('GET', 'https://gitee.com/api/v5/user', token);
    if (data is! Map) throw Exception('无法解析 Gitee 用户信息');
    return GitAccount(
      login: data['login']?.toString() ?? '',
      avatarUrl: data['avatar_url']?.toString() ?? '',
      htmlUrl: data['html_url']?.toString() ?? '',
    );
  }

  @override
  Future<dynamic> request(
    String method,
    String url,
    String token, {
    Object? body,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'HexoBlogManager',
      'Content-Type': 'application/json',
    };
    // Gitee 个人访问令牌既支持 header 也支持 access_token query 参数，
    // 双通道携带确保私有仓库读写可靠
    if (token.isNotEmpty) headers['Authorization'] = 'token $token';
    var u = url;
    if (token.isNotEmpty) {
      final sep = u.contains('?') ? '&' : '?';
      u = '$u$sep${Uri.encodeQueryComponent('access_token')}=${Uri.encodeQueryComponent(token)}';
    }
    return gitHttpRequest(method, u, headers, jsonBody: body);
  }

  @override
  Future<List<GitHubFileItem>> listContents(
      RepoConfig repo, String path) async {
    final p = path.replaceAll(RegExp(r'/+$'), '');
    final url =
        '${apiBase(repo)}/contents/${encPathSegments(p)}?ref=${Uri.encodeComponent(repo.branch)}';
    final data = await request('GET', url, repo.token);
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((e) => GitHubFileItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<Map<String, String>?> readFile(
      RepoConfig repo, String path) async {
    return _read(repo, path, repo.branch);
  }

  @override
  Future<Map<String, String>?> readFileAtRef(
      RepoConfig repo, String path, String ref) async {
    return _read(repo, path, ref);
  }

  Future<Map<String, String>?> _read(
      RepoConfig repo, String path, String ref) async {
    final url =
        '${apiBase(repo)}/contents/${encPathSegments(path)}?ref=${Uri.encodeComponent(ref)}';
    try {
      final data = await request('GET', url, repo.token);
      if (data is! Map) return null;
      final contentB64 =
          (data['content']?.toString() ?? '').replaceAll('\n', '');
      if (contentB64.isEmpty) return null;
      return {
        'content': utf8.decode(base64Decode(contentB64)),
        'sha': data['sha']?.toString() ?? '',
      };
    } catch (e) {
      debugPrint('Gitee: readFile failed: $e');
      return null;
    }
  }

  @override
  Future<String?> writeFile(
    RepoConfig repo,
    String path,
    List<int> bytes, {
    String? sha,
    required String message,
  }) async {
    final body = <String, dynamic>{
      'message': message,
      'content': base64Encode(bytes),
      'branch': repo.branch,
    };
    if (sha != null && sha.isNotEmpty) body['sha'] = sha;
    final data = await request(
      'PUT',
      '${apiBase(repo)}/contents/${encPathSegments(path)}',
      repo.token,
      body: body,
    );
    if (data is Map && data['content'] is Map) {
      return (data['content'] as Map)['sha']?.toString();
    }
    return null;
  }

  @override
  Future<void> deleteFile(
    RepoConfig repo,
    String path,
    String sha, {
    required String message,
  }) async {
    final body = <String, dynamic>{
      'message': message,
      'sha': sha,
      'branch': repo.branch,
    };
    await request(
      'DELETE',
      '${apiBase(repo)}/contents/${encPathSegments(path)}',
      repo.token,
      body: body,
    );
  }

  @override
  Future<List<GitCommitItem>> listCommits(
    RepoConfig repo, {
    int perPage = 30,
    String? path,
  }) async {
    final pathParam = (path != null && path.isNotEmpty)
        ? '&path=${Uri.encodeComponent(path)}'
        : '';
    final url =
        '${apiBase(repo)}/commits/${Uri.encodeComponent(repo.branch)}?per_page=$perPage$pathParam';
    final data = await request('GET', url, repo.token);
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((e) => GitCommitItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<DateTime?> latestCommitDate(RepoConfig repo, String path) async {
    final url =
        '${apiBase(repo)}/commits/${Uri.encodeComponent(repo.branch)}?path=${encPathSegments(path)}&per_page=1';
    final data = await request('GET', url, repo.token);
    if (data is List && data.isNotEmpty) {
      final cm = (data[0] as Map)['commit'] as Map?;
      final au = cm?['author'] as Map?;
      return DateTime.tryParse(au?['date']?.toString() ?? '');
    }
    return null;
  }

  @override
  String rawUrl(RepoConfig repo, String path) =>
      'https://gitee.com/${repo.owner}/${repo.repo}/raw/${repo.branch}/${encPathSegments(path)}';
}

/// Bitbucket 适配器（api.bitbucket.org）。
///
/// 使用 App Password 鉴权，token 格式约定为 `username:app_password`；
/// 无文件 SHA 语义，[writeFile] 返回 null。
class BitbucketProvider implements GitProviderAdapter {
  const BitbucketProvider();

  @override
  GitProviderType get type => GitProviderType.bitbucket;

  @override
  String apiBase(RepoConfig repo) =>
      'https://api.bitbucket.org/2.0/repositories/${repo.owner}/${repo.repo}';

  @override
  Future<GitAccount> getUser(String token) async {
    final data = await request('GET', 'https://api.bitbucket.org/2.0/user', token);
    if (data is! Map) throw Exception('无法解析 Bitbucket 用户信息');
    final links = data['links'] is Map
        ? Map<String, dynamic>.from(data['links'] as Map)
        : <String, dynamic>{};
    String? hrefOf(String key) {
      final l = links[key];
      if (l is Map) return l['href']?.toString();
      return null;
    }

    return GitAccount(
      login: data['username']?.toString() ?? '',
      avatarUrl: hrefOf('avatar') ?? '',
      htmlUrl: hrefOf('html') ?? '',
    );
  }

  String _basicAuth(String token) {
    final t = token.trim();
    final sep = t.indexOf(':');
    final username = sep > 0 ? t.substring(0, sep) : t;
    final password = sep > 0 ? t.substring(sep + 1) : '';
    return 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
  }

  @override
  Future<dynamic> request(
    String method,
    String url,
    String token, {
    Object? body,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'HexoBlogManager',
      'Content-Type': 'application/json',
    };
    if (token.isNotEmpty) headers['Authorization'] = _basicAuth(token);
    return gitHttpRequest(method, url, headers, jsonBody: body);
  }

  @override
  Future<List<GitHubFileItem>> listContents(
      RepoConfig repo, String path) async {
    final p = path.replaceAll(RegExp(r'/+$'), '');
    final branch = Uri.encodeComponent(repo.branch);
    final url = p.isEmpty
        ? '${apiBase(repo)}/src/$branch?pagelen=100'
        : '${apiBase(repo)}/src/$branch/${encPathSegments(p)}?pagelen=100';
    final data = await request('GET', url, repo.token);
    if (data is! Map) return [];
    final values = data['values'];
    if (values is! List) return [];
    final prefix = p.isEmpty ? '' : '$p/';
    final result = <String, GitHubFileItem>{};
    for (final v in values.whereType<Map>()) {
      final full = v['path']?.toString() ?? '';
      final rest = full.startsWith(prefix) ? full.substring(prefix.length) : full;
      final segs = rest.split('/').where((e) => e.isNotEmpty).toList();
      if (segs.isEmpty) continue;
      final vtype = v['type']?.toString() ?? '';
      final isDir = vtype == 'commit_directory' || segs.length > 1;
      final key = segs.first;
      if (result.containsKey(key)) continue;
      result[key] = GitHubFileItem(
        name: key,
        path: '$p${p.isEmpty ? '' : '/'}$key',
        type: isDir ? 'dir' : 'file',
        size: isDir ? null : (v['size'] as num?)?.toInt(),
      );
    }
    return result.values.toList();
  }

  @override
  Future<Map<String, String>?> readFile(
      RepoConfig repo, String path) async {
    return _read(repo, path, repo.branch);
  }

  @override
  Future<Map<String, String>?> readFileAtRef(
      RepoConfig repo, String path, String ref) async {
    return _read(repo, path, ref);
  }

  Future<Map<String, String>?> _read(
      RepoConfig repo, String path, String ref) async {
    final url =
        '${apiBase(repo)}/src/${Uri.encodeComponent(ref)}/${encPathSegments(path)}';
    try {
      final res = await _rawGet(url, repo.token);
      final body = res.body;
      if (body.isEmpty) return null;
      // 目录请求返回 JSON 列表结构，判为非文件
      final trimmed = body.trimLeft();
      if (trimmed.startsWith('{') && trimmed.startsWith('{"pagelen"')) {
        return null;
      }
      return {'content': body, 'sha': ''};
    } catch (e) {
      debugPrint('Bitbucket: readFile failed: $e');
      return null;
    }
  }

  Future<_RawResponse> _rawGet(String url, String token) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'HexoBlogManager',
    };
    if (token.isNotEmpty) headers['Authorization'] = _basicAuth(token);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.openUrl('GET', Uri.parse(url));
      headers.forEach(req.headers.set);
      final res = await req.close().timeout(const Duration(seconds: 30));
      final bytes = await res
          .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return _RawResponse(utf8.decode(bytes, allowMalformed: true));
      }
      throw Exception('HTTP ${res.statusCode}: ${utf8.decode(bytes)}');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<String?> writeFile(
    RepoConfig repo,
    String path,
    List<int> bytes, {
    String? sha,
    required String message,
  }) async {
    final headers = <String, String>{
      'User-Agent': 'HexoBlogManager',
      'Content-Type': 'application/x-www-form-urlencoded',
    };
    if (repo.token.isNotEmpty) {
      headers['Authorization'] = _basicAuth(repo.token);
    }
    final formBody = [
      'message=${Uri.encodeQueryComponent(message)}',
      'branch=${Uri.encodeQueryComponent(repo.branch)}',
      'content=${Uri.encodeQueryComponent(utf8.decode(bytes, allowMalformed: true))}',
    ].join('&');
    await gitHttpRequest(
      'PUT',
      '${apiBase(repo)}/src/${Uri.encodeComponent(repo.branch)}/${encPathSegments(path)}',
      headers,
      formBody: formBody,
    );
    return null;
  }

  @override
  Future<void> deleteFile(
    RepoConfig repo,
    String path,
    String sha, {
    required String message,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'HexoBlogManager',
      'Content-Type': 'application/json',
    };
    if (repo.token.isNotEmpty) {
      headers['Authorization'] = _basicAuth(repo.token);
    }
    final url =
        '${apiBase(repo)}/src/${Uri.encodeComponent(repo.branch)}/${encPathSegments(path)}?message=${Uri.encodeQueryComponent(message)}';
    await gitHttpRequest('DELETE', url, headers);
  }

  @override
  Future<List<GitCommitItem>> listCommits(
    RepoConfig repo, {
    int perPage = 30,
    String? path,
  }) async {
    final pathParam = (path != null && path.isNotEmpty)
        ? '&path=${Uri.encodeQueryComponent(path)}'
        : '';
    final url =
        '${apiBase(repo)}/commits/${Uri.encodeComponent(repo.branch)}?pagelen=$perPage$pathParam';
    final data = await request('GET', url, repo.token);
    if (data is! Map) return [];
    final values = data['values'];
    if (values is! List) return [];
    return values.whereType<Map>().map((e) {
      final m = Map<String, dynamic>.from(e);
      final author = m['author'] is Map
          ? Map<String, dynamic>.from(m['author'] as Map)
          : <String, dynamic>{};
      return GitCommitItem(
        sha: m['hash']?.toString() ?? '',
        message: m['message']?.toString() ?? '',
        author: author['raw']?.toString() ?? '',
        date: DateTime.tryParse(m['date']?.toString() ?? '') ?? DateTime.now(),
        htmlUrl: m['links'] is Map
            ? (m['links'] as Map)['html'] is Map
                ? ((m['links'] as Map)['html'] as Map)['href']?.toString() ?? ''
                : ''
            : '',
      );
    }).toList();
  }

  @override
  Future<DateTime?> latestCommitDate(RepoConfig repo, String path) async {
    final url =
        '${apiBase(repo)}/commits/${Uri.encodeComponent(repo.branch)}?path=${Uri.encodeQueryComponent(path)}&pagelen=1';
    final data = await request('GET', url, repo.token);
    if (data is Map) {
      final values = data['values'];
      if (values is List && values.isNotEmpty) {
        return DateTime.tryParse((values[0] as Map)['date']?.toString() ?? '');
      }
    }
    return null;
  }

  @override
  String rawUrl(RepoConfig repo, String path) =>
      'https://bitbucket.org/${repo.owner}/${repo.repo}/raw/${repo.branch}/${encPathSegments(path)}';
}

class _RawResponse {
  final String body;
  const _RawResponse(this.body);
}


