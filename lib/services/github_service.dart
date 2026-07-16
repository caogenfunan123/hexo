import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/article.dart';
import '../models/repo_config.dart';

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
}

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
      date: DateTime.tryParse(author['date']?.toString() ?? '') ?? DateTime.now(),
      htmlUrl: j['html_url']?.toString() ?? '',
    );
  }
}

class GitHubService {
  Future<Map<String, String>> _headers(String token) async => {
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer $token',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'HexoBlogManager',
        'Content-Type': 'application/json',
      };

  Future<dynamic> _request(
    String method,
    String url,
    String token, {
    Object? body,
  }) async {
    final client = HttpClient();
    try {
      final req = await client.openUrl(method, Uri.parse(url));
      final headers = await _headers(token);
      headers.forEach(req.headers.set);
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        req.headers.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (text.isEmpty) return null;
        return jsonDecode(text);
      }
      throw Exception('GitHub $method ${res.statusCode}: $text');
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> testToken(RepoConfig repo) async {
    final data = await getUser(repo.token);
    return data != null && (data['login']?.toString().isNotEmpty ?? false);
  }

  /// 用原始 token 校验并返回 /user 信息；失败抛异常。
  Future<Map<String, dynamic>> getUser(String token) async {
    final data = await _request('GET', 'https://api.github.com/user', token);
    if (data is Map) return Map<String, dynamic>.from(data);
    throw Exception('无法解析 GitHub 用户信息');
  }

  Future<bool> verifyToken(String token) async {
    if (token.trim().isEmpty) return false;
    try {
      final user = await getUser(token.trim());
      return user['login']?.toString().isNotEmpty == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<GitHubFileItem>> listPosts(RepoConfig repo, {String? path}) async {
    final p = path ?? repo.postsPath;
    final url =
        '${repo.apiBase}/contents/${_encPath(p)}?ref=${Uri.encodeComponent(repo.branch)}';
    final data = await _request('GET', url, repo.token);
    if (data is List) {
      final items = data
          .whereType<Map>()
          .map((e) => GitHubFileItem.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.type == 'file' && e.name.endsWith('.md'))
          .toList();
      await Future.wait(items.map((item) async {
        try {
          final curl = '${repo.apiBase}/commits?path=${_encPath(item.path)}&sha=${Uri.encodeComponent(repo.branch)}&per_page=1';
          final cd = await _request('GET', curl, repo.token);
          if (cd is List && cd.isNotEmpty) {
            final cm = (cd[0] as Map)['commit'] as Map?;
            final au = cm?['author'] as Map?;
            if (au != null) {
              item.lastModified = DateTime.tryParse(au['date']?.toString() ?? '');
            }
          }
        } catch (_) {}
      }));
      items.sort((a, b) {
        final ad = a.lastModified;
        final bd = b.lastModified;
        if (ad != null && bd != null) return bd.compareTo(ad);
        return b.name.compareTo(a.name);
      });
      return items;
    }
    return [];
  }

  Future<Article> getArticle(RepoConfig repo, GitHubFileItem item) async {
    final url =
        '${repo.apiBase}/contents/${_encPath(item.path)}?ref=${Uri.encodeComponent(repo.branch)}';
    final data = await _request('GET', url, repo.token);
    if (data is! Map) throw Exception('无效的文件响应');
    final contentB64 = (data['content']?.toString() ?? '').replaceAll('\n', '');
    final sha = data['sha']?.toString();
    final path = data['path']?.toString() ?? item.path;
    final bytes = base64Decode(contentB64);
    final md = utf8.decode(bytes);
    return Article.fromMarkdown(
      md,
      id: 'remote_${sha ?? path}',
      remotePath: path,
      remoteSha: sha,
      repoId: repo.id,
    );
  }

  Future<Article> upsertArticle(RepoConfig repo, Article article, {String? commitMessage}) async {
    final path = article.remotePath ??
        '${repo.postsPath.replaceAll(RegExp(r'/+$'), '')}/${article.fileName()}';
    final md = article.toMarkdownWithFrontMatter();
    final content = base64Encode(utf8.encode(md));
    final message = commitMessage ??
        (article.remoteSha == null
            ? 'docs: add ${article.title}'
            : 'docs: update ${article.title}');
    final body = <String, dynamic>{
      'message': message,
      'content': content,
      'branch': repo.branch,
    };
    if (article.remoteSha != null && article.remoteSha!.isNotEmpty) {
      body['sha'] = article.remoteSha;
    }
    final url = '${repo.apiBase}/contents/${_encPath(path)}';
    final data = await _request('PUT', url, repo.token, body: body);
    String? newSha;
    if (data is Map && data['content'] is Map) {
      newSha = (data['content'] as Map)['sha']?.toString();
    }
    return article.copyWith(
      remotePath: path,
      remoteSha: newSha ?? article.remoteSha,
      repoId: repo.id,
      isDraft: false,
      published: true,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> deleteArticle(RepoConfig repo, Article article, {String? commitMessage}) async {
    if (article.remotePath == null || article.remoteSha == null) {
      throw Exception('缺少远程路径或 SHA');
    }
    final body = {
      'message': commitMessage ?? 'docs: delete ${article.title}',
      'sha': article.remoteSha,
      'branch': repo.branch,
    };
    final url = '${repo.apiBase}/contents/${_encPath(article.remotePath!)}';
    await _request('DELETE', url, repo.token, body: body);
  }

  /// 获取仓库任意文件内容（文本），返回 {content, sha}
  Future<Map<String, String>?> getRawFile(RepoConfig repo, String path) async {
    final url = '${repo.apiBase}/contents/${_encPath(path)}?ref=${Uri.encodeComponent(repo.branch)}';
    try {
      final data = await _request('GET', url, repo.token);
      if (data is! Map) return null;
      final contentB64 = (data['content']?.toString() ?? '').replaceAll('\n', '');
      if (contentB64.isEmpty) return null;
      final content = utf8.decode(base64Decode(contentB64));
      final sha = data['sha']?.toString();
      return {'content': content, 'sha': sha ?? ''};
    } catch (_) {
      return null;
    }
  }

  /// 写入仓库任意文件
  Future<void> putRawFile(RepoConfig repo, String path, String content, {String? sha, String? commitMessage}) async {
    final body = <String, dynamic>{
      'message': commitMessage ?? 'chore: update $path',
      'content': base64Encode(utf8.encode(content)),
      'branch': repo.branch,
    };
    if (sha != null && sha.isNotEmpty) {
      body['sha'] = sha;
    }
    final url = '${repo.apiBase}/contents/${_encPath(path)}';
    await _request('PUT', url, repo.token, body: body);
  }

  /// 删除仓库任意文件
  Future<void> deleteRawFile(RepoConfig repo, String path, String sha, {String? commitMessage}) async {
    final body = <String, dynamic>{
      'message': commitMessage ?? 'chore: delete $path',
      'sha': sha,
      'branch': repo.branch,
    };
    final url = '${repo.apiBase}/contents/${_encPath(path)}';
    await _request('DELETE', url, repo.token, body: body);
  }

  Future<List<GitCommitItem>> listCommits(RepoConfig repo, {int perPage = 30}) async {
    final url =
        '${repo.apiBase}/commits?sha=${Uri.encodeComponent(repo.branch)}&per_page=$perPage';
    final data = await _request('GET', url, repo.token);
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => GitCommitItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }

  /// 回滚：将指定文件恢复到某次 commit 的内容并新建一次提交
  Future<Article> rollbackFile(
    RepoConfig repo,
    String path,
    String commitSha,
  ) async {
    final url =
        '${repo.apiBase}/contents/${_encPath(path)}?ref=${Uri.encodeComponent(commitSha)}';
    final data = await _request('GET', url, repo.token);
    if (data is! Map) throw Exception('无法读取历史文件');
    final contentB64 = (data['content']?.toString() ?? '').replaceAll('\n', '');
    final md = utf8.decode(base64Decode(contentB64));

    // 当前文件 sha
    String? currentSha;
    try {
      final cur = await _request(
        'GET',
        '${repo.apiBase}/contents/${_encPath(path)}?ref=${Uri.encodeComponent(repo.branch)}',
        repo.token,
      );
      if (cur is Map) currentSha = cur['sha']?.toString();
    } catch (_) {}

    final body = <String, dynamic>{
      'message': 'revert: restore $path to ${commitSha.substring(0, 7)}',
      'content': base64Encode(utf8.encode(md)),
      'branch': repo.branch,
    };
    if (currentSha != null) body['sha'] = currentSha;
    final put = await _request(
      'PUT',
      '${repo.apiBase}/contents/${_encPath(path)}',
      repo.token,
      body: body,
    );
    String? newSha;
    if (put is Map && put['content'] is Map) {
      newSha = (put['content'] as Map)['sha']?.toString();
    }
    return Article.fromMarkdown(
      md,
      id: 'remote_${newSha ?? path}',
      remotePath: path,
      remoteSha: newSha,
      repoId: repo.id,
    );
  }

  Future<String> uploadBinary({
    required String token,
    required String owner,
    required String repo,
    required String branch,
    required String path,
    required List<int> bytes,
    String message = 'chore: upload image',
  }) async {
    // 若已存在则带 sha 覆盖
    String? sha;
    try {
      final existing = await _request(
        'GET',
        'https://api.github.com/repos/$owner/$repo/contents/${_encPath(path)}?ref=${Uri.encodeComponent(branch)}',
        token,
      );
      if (existing is Map) sha = existing['sha']?.toString();
    } catch (_) {}

    final body = <String, dynamic>{
      'message': message,
      'content': base64Encode(bytes),
      'branch': branch,
    };
    if (sha != null) body['sha'] = sha;
    final data = await _request(
      'PUT',
      'https://api.github.com/repos/$owner/$repo/contents/${_encPath(path)}',
      token,
      body: body,
    );
    if (data is Map && data['content'] is Map) {
      final download = (data['content'] as Map)['download_url']?.toString();
      if (download != null && download.isNotEmpty) return download;
    }
    return 'https://raw.githubusercontent.com/$owner/$repo/$branch/$path';
  }

  /// 仓库内全文搜索（GitHub Code Search）。返回匹配文件列表。
  Future<List<GitHubSearchHit>> searchCode(
    RepoConfig repo,
    String query, {
    String? pathPrefix,
    int perPage = 30,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final parts = <String>[
      q,
      'repo:${repo.owner}/${repo.repo}',
      'in:file',
      'extension:md',
    ];
    final prefix = (pathPrefix ?? repo.postsPath).trim();
    if (prefix.isNotEmpty) {
      parts.add('path:${prefix.replaceAll(RegExp(r"^/+|/+$"), "")}');
    }
    final encoded = Uri.encodeQueryComponent(parts.join(' '));
    final url =
        'https://api.github.com/search/code?q=$encoded&per_page=$perPage';
    final data = await _request('GET', url, repo.token);
    if (data is! Map) return [];
    final items = data['items'];
    if (items is! List) return [];
    return items
        .whereType<Map>()
        .map((e) => GitHubSearchHit.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 兼容旧调用：返回格式化 JSON 字符串
  Future<String> searchCodeRaw(RepoConfig repo, String query) async {
    final hits = await searchCode(repo, query);
    return const JsonEncoder.withIndent('  ').convert(
      hits.map((e) => e.toJson()).toList(),
    );
  }

  String _encPath(String path) =>
      path.split('/').where((e) => e.isNotEmpty).map(Uri.encodeComponent).join('/');
}

class GitHubSearchHit {
  final String name;
  final String path;
  final String? sha;
  final String? htmlUrl;
  final double? score;

  GitHubSearchHit({
    required this.name,
    required this.path,
    this.sha,
    this.htmlUrl,
    this.score,
  });

  factory GitHubSearchHit.fromJson(Map<String, dynamic> j) => GitHubSearchHit(
        name: j['name']?.toString() ?? '',
        path: j['path']?.toString() ?? '',
        sha: j['sha']?.toString(),
        htmlUrl: j['html_url']?.toString(),
        score: (j['score'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'sha': sha,
        'htmlUrl': htmlUrl,
        'score': score,
      };

  GitHubFileItem toFileItem() => GitHubFileItem(
        name: name,
        path: path,
        type: 'file',
        sha: sha,
      );
}

