import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/article.dart';
import '../models/article_type.dart';
import '../models/git_provider.dart';
import '../models/repo_config.dart';
import '../models/template_item.dart';
import 'git_models.dart';
import 'git_provider_adapter.dart';
import 'git_providers.dart';

export 'git_models.dart' show GitHubFileItem, GitCommitItem;

/// 多平台仓库服务门面。
///
/// 内部按 [RepoConfig.provider] 分发到对应平台适配器，
/// 对外保留原 GitHubService 的全部方法签名与返回结构。
class GitHubService {
  // ── 平台适配器分发 ──

  static GitProviderAdapter adapterFor(GitProviderType type) {
    switch (type) {
      case GitProviderType.github:
        return const GitHubProvider();
      case GitProviderType.gitlab:
        return const GitLabProvider();
      case GitProviderType.gitee:
        return const GiteeProvider();
      case GitProviderType.bitbucket:
        return const BitbucketProvider();
    }
  }

  GitProviderAdapter adapter(RepoConfig repo) => adapterFor(repo.provider);

  Future<bool> testToken(RepoConfig repo) async {
    try {
      final acc = await adapter(repo).getUser(repo.token);
      return acc.isValid;
    } catch (e) {
      debugPrint('Git: testToken failed: $e');
      return false;
    }
  }

  /// 用原始 token 校验并返回平台用户信息；失败抛异常。
  /// 返回结构与原 GitHub /user 一致：{login, avatar_url, html_url}
  Future<Map<String, dynamic>> getUser(
    String token, {
    GitProviderType provider = GitProviderType.github,
  }) async {
    final acc = await adapterFor(provider).getUser(token);
    if (!acc.isValid) throw Exception('无法解析用户信息');
    return {
      'login': acc.login,
      'avatar_url': acc.avatarUrl,
      'html_url': acc.htmlUrl,
    };
  }

  Future<bool> verifyToken(
    String token, {
    GitProviderType provider = GitProviderType.github,
  }) async {
    if (token.trim().isEmpty) return false;
    try {
      final user = await getUser(token.trim(), provider: provider);
      return user['login']?.toString().isNotEmpty == true;
    } catch (e) {
      debugPrint('Git: verifyToken failed: $e');
      return false;
    }
  }

  Future<List<GitHubFileItem>> listPosts(RepoConfig repo,
      {String? path, bool recursive = false}) async {
    if (recursive) {
      // 递归遍历子目录，收集全部 .md 文章，避免漏掉分类/日期子目录中的文章
      final all = <GitHubFileItem>[];
      await _collectMarkdownFiles(repo, path ?? repo.postsPath, all);
      if (all.isEmpty) return all;
      await _enrichCommitDates(repo, all);
      all.sort((a, b) {
        final ad = a.lastModified;
        final bd = b.lastModified;
        if (ad != null && bd != null) return bd.compareTo(ad);
        return b.name.compareTo(a.name);
      });
      return all;
    }
    final p = path ?? repo.postsPath;
    final data = await adapter(repo).listContents(repo, p);
    final items = data
        .where((e) => !e.isDir && e.name.endsWith('.md'))
        .toList();
    if (items.isEmpty) return items;
    await _enrichCommitDates(repo, items);
    items.sort((a, b) {
      final ad = a.lastModified;
      final bd = b.lastModified;
      if (ad != null && bd != null) return bd.compareTo(ad);
      return b.name.compareTo(a.name);
    });
    return items;
  }

  /// 列出目录下的全部文件（不限扩展名），供云同步等非文章场景使用
  ///
  /// [recursive] 为 true 时递归遍历子目录；否则仅列出直接子项。
  /// 返回结果含文件与目录（目录的 [GitHubFileItem.isDir] 为 true）。
  Future<List<GitHubFileItem>> listFiles(RepoConfig repo, String path,
      {bool recursive = false}) async {
    final all = <GitHubFileItem>[];
    await _collectAllFiles(repo, path, all, recursive: recursive);
    return all;
  }

  /// 递归收集指定目录下的全部文件（含子目录项）
  Future<void> _collectAllFiles(RepoConfig repo, String dirPath,
      List<GitHubFileItem> out, {required bool recursive}) async {
    final p = dirPath.replaceAll(RegExp(r'/+$'), '');
    final entries = await adapter(repo).listContents(repo, p);
    for (final e in entries) {
      if (e.isDir) {
        out.add(e);
        if (recursive) {
          await _collectAllFiles(repo, e.path, out, recursive: recursive);
        }
      } else {
        out.add(e);
      }
    }
  }

  /// 递归收集指定目录下的全部 .md 文件
  Future<void> _collectMarkdownFiles(
      RepoConfig repo, String dirPath, List<GitHubFileItem> out) async {
    final p = dirPath.replaceAll(RegExp(r'/+$'), '');
    final entries = await adapter(repo).listContents(repo, p);
    for (final e in entries) {
      if (e.isDir) {
        await _collectMarkdownFiles(repo, e.path, out);
      } else if (e.name.toLowerCase().endsWith('.md')) {
        out.add(e);
      }
    }
  }

  /// 批量补充文件最近提交时间（控制并发，避免触发平台限流）
  Future<void> _enrichCommitDates(
      RepoConfig repo, List<GitHubFileItem> items) async {
    const concurrency = 4;
    var index = 0;
    Future<void> worker() async {
      while (index < items.length) {
        final item = items[index];
        index++;
        try {
          final d = await adapter(repo).latestCommitDate(repo, item.path);
          if (d != null) item.lastModified = d;
        } catch (e) {
          debugPrint('Git: get commit history failed: $e');
        }
      }
    }

    final workers = List.generate(
        concurrency.clamp(1, items.length).toInt(), (_) => worker());
    await Future.wait(workers);
  }

  /// 列出仓库目录全部内容（含子目录与非 md 文件），供 AI 诊断仓库结构使用。
  /// 不做 commit 历史富化，仅按 目录在前、名称升序 排列。
  Future<List<GitHubFileItem>> listDirContents(RepoConfig repo,
      {String? path}) async {
    final p = path?.replaceAll(RegExp(r'/+$'), '');
    final items = await adapter(repo).listContents(repo, p ?? '');
    items.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return items;
  }

  Future<Article> getArticle(RepoConfig repo, GitHubFileItem item) async {
    final read = await adapter(repo).readFile(repo, item.path);
    if (read == null) throw Exception('无效的文件响应');
    final md = read['content'] ?? '';
    final sha = read['sha'] ?? '';
    return Article.fromMarkdown(
      md,
      id: 'remote_${sha.isEmpty ? item.path : sha}',
      remotePath: item.path,
      remoteSha: sha,
      repoId: repo.id,
    );
  }

  Future<Article> upsertArticle(RepoConfig repo, Article article,
      {String? commitMessage, List<TemplateItem>? templates}) async {
    final isPage = article.articleType == ArticleType.page;
    final basePath = isPage
        ? repo.pagesPath.replaceAll(RegExp(r'/+$'), '')
        : repo.postsPath.replaceAll(RegExp(r'/+$'), '');
    final fileName = article.fileNameForRepo(repo);
    final path = article.remotePath ?? '$basePath/$fileName';
    final md =
        article.toMarkdownWithFrontMatterForRepo(repo, templates: templates);
    final message = commitMessage ??
        (article.remoteSha == null
            ? 'docs: add ${article.title}'
            : 'docs: update ${article.title}');
    var effectiveSha = article.remoteSha;
    if (effectiveSha == null || effectiveSha.isEmpty) {
      // 本地未记录 SHA 时先探测远程是否已存在同名文件，
      // 已存在则必须带 sha 覆盖，否则平台返回 422
      try {
        final existing = await adapter(repo).readFile(repo, path);
        if (existing != null && (existing['sha'] ?? '').isNotEmpty) {
          effectiveSha = existing['sha'];
        }
      } catch (_) {/* 探测失败按新建处理 */}
    }
    final newSha = await adapter(repo).writeFile(
      repo,
      path,
      utf8.encode(md),
      sha: (effectiveSha != null && effectiveSha.isNotEmpty)
          ? effectiveSha
          : null,
      message: message,
    );
    return article.copyWith(
      remotePath: path,
      remoteSha: newSha ?? effectiveSha,
      repoId: repo.id,
      isDraft: false,
      published: true,
      updatedAt: DateTime.now(),
    );
  }

  /// 发布到主仓库并同步到全部镜像仓库（如 GitHub + Gitee）。
  /// 返回主仓库发布结果；镜像推送失败不阻断主仓库发布。
  Future<Article> publishArticleWithMirrors(RepoConfig repo, Article article,
      {String? commitMessage, List<TemplateItem>? templates}) async {
    final published = await upsertArticle(repo, article,
        commitMessage: commitMessage, templates: templates);
    for (final mirror in repo.mirrorRemotes) {
      final mirrorRepo = repo.copyWith(
        id: '${repo.id}_mirror_${mirror.fullName}',
        name: mirror.fullName,
        owner: mirror.owner,
        repo: mirror.repo,
        branch: mirror.branch.isEmpty ? repo.branch : mirror.branch,
        token: mirror.token,
        provider: mirror.provider,
      );
      try {
        await upsertArticle(mirrorRepo, article,
            commitMessage: commitMessage, templates: templates);
      } catch (e) {
        debugPrint('Mirror publish to ${mirror.fullName} failed: $e');
      }
    }
    return published;
  }

  /// 读取仓库关键文件用于 AI 分析（配置文件 + 示例文章）
  ///
  /// 返回一个 Map，key 为文件路径，value 为文件内容
  Future<Map<String, String>> readRepoAnalysisFiles(RepoConfig repo) async {
    final result = <String, String>{};
    // 关键配置文件列表
    const configFiles = [
      '_config.yml',
      '_config.yaml',
      'config.toml',
      'hugo.toml',
      'package.json',
      'Gemfile',
      'astro.config.mjs',
      'gatsby-config.js',
      'next.config.js',
      'pelicanconf.py',
      '.eleventy.js',
      'config.js',
      'config.ts',
    ];
    // 读取配置文件
    for (final file in configFiles) {
      try {
        final data = await getRawFile(repo, file);
        if (data != null) {
          result[file] = data['content'] ?? '';
        }
      } catch (_) {/* 文件不存在，跳过 */}
    }
    // 读取 posts 目录下最近 2 篇文章的 FrontMatter
    try {
      final posts = await listPosts(repo);
      for (final post in posts.take(2)) {
        try {
          final data = await getRawFile(repo, post.path);
          if (data != null) {
            // 只取 FrontMatter 部分（第一个 --- 到第二个 --- 之间）
            final raw = data['content'] ?? '';
            final firstSep = raw.indexOf('---');
            if (firstSep >= 0) {
              final secondSep = raw.indexOf('---', firstSep + 3);
              if (secondSep > firstSep) {
                result['sample:${post.name}'] = raw.substring(0, secondSep + 3);
              }
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
    return result;
  }

  Future<void> deleteArticle(RepoConfig repo, Article article,
      {String? commitMessage}) async {
    if (article.remotePath == null || article.remoteSha == null) {
      throw Exception('缺少远程路径或 SHA');
    }
    await adapter(repo).deleteFile(
      repo,
      article.remotePath!,
      article.remoteSha!,
      message: commitMessage ?? 'docs: delete ${article.title}',
    );
  }

  /// 获取仓库任意文件内容（文本），返回 {content, sha}
  Future<Map<String, String>?> getRawFile(RepoConfig repo, String path) async {
    final read = await adapter(repo).readFile(repo, path);
    if (read == null) return null;
    return {'content': read['content'] ?? '', 'sha': read['sha'] ?? ''};
  }

  /// 写入仓库任意文件
  Future<void> putRawFile(RepoConfig repo, String path, String content,
      {String? sha, String? commitMessage}) async {
    await adapter(repo).writeFile(
      repo,
      path,
      utf8.encode(content),
      sha: sha,
      message: commitMessage ?? 'chore: update $path',
    );
  }

  /// 写入仓库二进制文件（图片、字体、压缩包等非文本内容）
  Future<void> putRawBytes(RepoConfig repo, String path, List<int> bytes,
      {String? sha, String? commitMessage}) async {
    await adapter(repo).writeFile(
      repo,
      path,
      bytes,
      sha: sha,
      message: commitMessage ?? 'chore: update $path',
    );
  }

  /// 删除仓库任意文件
  Future<void> deleteRawFile(RepoConfig repo, String path, String sha,
      {String? commitMessage}) async {
    await adapter(repo).deleteFile(
      repo,
      path,
      sha,
      message: commitMessage ?? 'chore: delete $path',
    );
  }

  Future<List<GitCommitItem>> listCommits(RepoConfig repo,
      {int perPage = 30, String? path}) async {
    return adapter(repo).listCommits(repo, perPage: perPage, path: path);
  }

  /// 回滚：将指定文件恢复到某次 commit 的内容并新建一次提交
  Future<Article> rollbackFile(
    RepoConfig repo,
    String path,
    String commitSha,
  ) async {
    final hist = await adapter(repo).readFileAtRef(repo, path, commitSha);
    if (hist == null) throw Exception('无法读取历史文件');
    final md = hist['content'] ?? '';

    // 当前文件 sha
    String? currentSha;
    try {
      final cur = await adapter(repo).readFile(repo, path);
      if (cur != null && (cur['sha'] ?? '').isNotEmpty) {
        currentSha = cur['sha'];
      }
    } catch (e) {
      debugPrint('Git: rollback get SHA failed: $e');
    }

    final newSha = await adapter(repo).writeFile(
      repo,
      path,
      utf8.encode(md),
      sha: currentSha,
      message:
          'revert: restore $path to ${commitSha.length >= 7 ? commitSha.substring(0, 7) : commitSha}',
    );
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
    GitProviderType provider = GitProviderType.github,
  }) async {
    // 按所选平台构造临时仓库配置
    final tmp = RepoConfig(
      id: '',
      name: '',
      owner: owner,
      repo: repo,
      branch: branch,
      token: token,
      provider: provider,
    );
    final adapter = adapterFor(provider);
    // 若已存在则带 sha 覆盖
    String? sha;
    try {
      final existing = await adapter.readFile(tmp, path);
      if (existing != null && (existing['sha'] ?? '').isNotEmpty) {
        sha = existing['sha'];
      }
    } catch (e) {
      debugPrint('Git: uploadBinary get SHA failed: $e');
    }
    await adapter.writeFile(tmp, path, bytes, sha: sha, message: message);
    return adapter.rawUrl(tmp, path);
  }

  /// Git Data API 批量提交（方法B）：一次 commit 上传多个文件。
  ///
  /// 适用于 GitHub。相比逐文件 Contents API，提交更快、原子、减少并发冲突。
  /// [files] 的元素为 (path, bytes)，path 为仓库内相对路径。
  Future<void> uploadBatchViaGitData({
    required String token,
    required String owner,
    required String repo,
    required String branch,
    required List<({String path, List<int> bytes})> files,
    String message = 'chore: batch upload',
    String? authorName,
    String? authorEmail,
  }) async {
    if (files.isEmpty) return;
    final tmp = RepoConfig(
      id: '',
      name: '',
      owner: owner,
      repo: repo,
      branch: branch,
      token: token,
      provider: GitProviderType.github,
    );
    final provider = adapterFor(GitProviderType.github);
    if (provider is! GitHubProvider) {
      throw Exception('Git Data API 仅支持 GitHub');
    }
    await provider.writeBatch(
      tmp,
      files,
      message: message,
      authorName: authorName,
      authorEmail: authorEmail,
    );
  }

  /// git CLI 提交推送（方法C）：本地 clone 后批量写文件，再 commit + push。
  ///
  /// 仅桌面平台且系统存在 git 命令时可用。上传前需确保本地仓库完整，
  /// 因此先 clone（分支存在则检出）到临时目录，写文件后提交推送。
  Future<void> uploadViaGitCli({
    required String token,
    required String owner,
    required String repo,
    required String branch,
    required List<({String path, List<int> bytes})> files,
    String message = 'chore: batch upload',
    String? authorName,
    String? authorEmail,
    String? baseUrl,
  }) async {
    if (files.isEmpty) return;
    if (!Platform.isWindows &&
        !Platform.isLinux &&
        !Platform.isMacOS) {
      throw Exception('git CLI 方式仅支持桌面端');
    }
    final git = await Process.run('which', ['git']);
    if (git.exitCode != 0 ||
        (git.stdout?.toString() ?? '').trim().isEmpty) {
      throw Exception('未检测到 git 命令，无法使用 CLI 方式');
    }
    final root = await Directory.systemTemp.createTemp('hexo_batch_');
    try {
      final originUrl = Uri.parse(
              baseUrl?.isNotEmpty == true
                  ? baseUrl!
                  : 'https://github.com/$owner/$repo.git')
          .replace(
        queryParameters: null,
        fragment: null,
      );
      // 带 token 的 clone URL，避免后续 push 需要交互式凭据
      final authUrl = originUrl.replace(
        userInfo: Uri.encodeComponent('oauth2') +
            ':' +
            Uri.encodeComponent(token),
      ).toString();
      final cloneArgs = <String>['clone', '--depth', '1'];
      cloneArgs.addAll(['-b', branch, authUrl, root.path]);
      final clone = await _runCli(
          'git', cloneArgs, workingDirectory: null, noAuthUrl: originUrl.toString());
      if (!clone.ok) {
        // 分支可能不存在：全量 clone 后本地建分支
        final bare = root.path;
        final cloneAll = await _runCli(
            'git', ['clone', '--depth', '1', originUrl.toString(), bare],
            workingDirectory: null, noAuthUrl: originUrl.toString());
        if (!cloneAll.ok) {
          throw Exception('git clone 失败');
        }
      }
      // 写入文件
      for (final f in files) {
        final target = File('${root.path}/${f.path}');
        await target.parent.create(recursive: true);
        await target.writeAsBytes(f.bytes, flush: true);
      }
      final add = await _runCli('git', ['add', '-A'],
          workingDirectory: root.path);
      if (!add.ok) throw Exception('git add 失败');
      if (authorName?.isNotEmpty == true || authorEmail?.isNotEmpty == true) {
        final nm = authorName ?? 'Hexo Blog Manager';
        final em = authorEmail ?? 'noreply@hexo.blog';
        await _runCli('git', ['config', 'user.name', nm],
            workingDirectory: root.path);
        await _runCli('git', ['config', 'user.email', em],
            workingDirectory: root.path);
      }
      final commit = await _runCli('git', ['commit', '-m', message],
          workingDirectory: root.path);
      if (!commit.ok) {
        // 无改动时视为成功（全部文件已存在且内容相同）
        if (commit.stderr.contains('nothing to commit')) return;
        throw Exception('git commit 失败');
      }
      final push = await _runCli(
        'git',
        ['push', 'origin', 'HEAD:$branch'],
        workingDirectory: root.path,
      );
      if (!push.ok) throw Exception('git push 失败');
    } finally {
      if (root.existsSync()) {
        try {
          await root.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// 执行 CLI 命令，返回 ok/输出。调用 git 时隐藏 URL 中的凭据。
  Future<({bool ok, String stdout, String stderr})> _runCli(
    String cmd,
    List<String> args, {
    required String? workingDirectory,
    String? noAuthUrl,
  }) async {
    final result = await Process.run(cmd, args,
        workingDirectory: workingDirectory ?? Directory.current.path);
    final out = (result.stdout?.toString() ?? '').trim();
    final err = (result.stderr?.toString() ?? '').trim();

    // 隐藏 URL 中的 token 凭据（args / stdout / stderr 全量脱敏）
    String redact(String s) =>
        s.replaceAll(RegExp('//[^/@\\s]+@'), '//***@');
    final shownArgs = args.map(redact).toList();
    final shownOut = noAuthUrl != null ? redact(out) : out;
    final shownErr = noAuthUrl != null ? redact(err) : err;

    debugPrint('CLI: $cmd $shownArgs\n  out: $shownOut\n  err: $shownErr');
    return (ok: result.exitCode == 0, stdout: out, stderr: shownErr);
  }

  /// 仓库内全文搜索。GitHub Code Search 为 GitHub 独有能力，
  /// 其他平台不提供搜索返回空列表。
  Future<List<GitHubSearchHit>> searchCode(
    RepoConfig repo,
    String query, {
    String? pathPrefix,
    int perPage = 30,
  }) async {
    if (repo.provider != GitProviderType.github) return [];
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

    final results = <GitHubSearchHit>[];
    // 翻页拉取（最多 3 页，避免逐页请求过多触发次级限流）
    for (var page = 1; page <= 3; page++) {
      final data = await const GitHubProvider()
          .request('GET', '$url&page=$page', repo.token);
      if (data is! Map) break;
      final items = data['items'];
      final total = (data['total_count'] as num?)?.toInt() ?? 0;
      if (items is! List) break;
      final pageHits = items
          .whereType<Map>()
          .map((e) => GitHubSearchHit.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      results.addAll(pageHits);
      // 已拉完或到总数则停止
      if (pageHits.isEmpty || results.length >= total || total == 0) break;
    }
    return results;
  }

  /// 兼容旧调用：返回格式化 JSON 字符串
  Future<String> searchCodeRaw(RepoConfig repo, String query) async {
    final hits = await searchCode(repo, query);
    return const JsonEncoder.withIndent('  ').convert(
      hits.map((e) => e.toJson()).toList(),
    );
  }

  /// 列出远程公开仓库目录内容（GitHub），递归到指定深度/文件数上限
  Future<List<GitHubFileItem>> listRemoteDirContents({
    required String owner,
    required String repo,
    required String branch,
    String path = '',
    String? token,
    int maxFiles = 200,
  }) async {
    final result = <GitHubFileItem>[];
    final provider = const GitHubProvider();
    final tmp = RepoConfig(
      id: '',
      name: '',
      owner: owner,
      repo: repo,
      branch: branch,
      token: token ?? '',
    );

    Future<void> recurse(String p) async {
      if (result.length >= maxFiles) return;
      try {
        final entries = await provider.listContents(tmp, p);
        for (final item in entries) {
          if (result.length >= maxFiles) break;
          result.add(item);
          if (item.isDir) {
            await recurse(item.path);
          }
        }
      } catch (_) {}
    }

    await recurse(path);
    return result;
  }

  /// 获取远程公开仓库文件的原始内容（文本，GitHub）
  Future<String?> getRemoteRawFile({
    required String owner,
    required String repo,
    required String branch,
    required String path,
    String? token,
  }) async {
    final tmp = RepoConfig(
      id: '',
      name: '',
      owner: owner,
      repo: repo,
      branch: branch,
      token: token ?? '',
    );
    try {
      final read = await const GitHubProvider().readFile(tmp, path);
      return read?['content'];
    } catch (_) {
      return null;
    }
  }

  /// 触发 Cloudflare Pages 重新部署
  /// [deployHookUrl] 为 Cloudflare Pages 的 Deploy Hook URL
  /// 成功返回 true，失败返回 false
  /// 触发部署钩子（Cloudflare/Vercel/Netlify Deploy Hook 均为通用 POST webhook）
  static Future<bool> triggerCloudflareDeploy(String deployHookUrl) async {
    if (deployHookUrl.isEmpty) return false;
    try {
      final client = HttpClient();
      try {
        final req = await client.openUrl('POST', Uri.parse(deployHookUrl));
        req.headers.contentType = ContentType.json;
        final res = await req.close();
        await res.drain<void>();
        return res.statusCode >= 200 && res.statusCode < 300;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      debugPrint('Deploy hook failed: $e');
      return false;
    }
  }

  /// 批量触发全部部署钩子，返回成功数量
  static Future<int> triggerDeployHooks(List<String> urls) async {
    var ok = 0;
    for (final url in urls) {
      if (await triggerCloudflareDeploy(url)) ok++;
    }
    return ok;
  }
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
