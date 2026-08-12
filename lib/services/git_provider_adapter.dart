import '../models/git_provider.dart';
import '../models/repo_config.dart';
import 'git_models.dart';

/// 仓库平台适配器：屏蔽 GitHub/GitLab/Gitee/Bitbucket 的 API 差异。
///
/// 各平台 contents 读写 + commit 语义一致，差异集中在：
/// 鉴权头、API 根地址、路径编码、响应结构、文件 SHA 语义。
abstract class GitProviderAdapter {
  GitProviderType get type;

  /// 仓库 API 根地址（不含尾部斜杠）
  String apiBase(RepoConfig repo);

  /// 校验 token 并返回平台用户信息；失败抛异常
  Future<GitAccount> getUser(String token);

  /// 通用 JSON 请求（携带平台鉴权头，body 以 JSON 编码）
  Future<dynamic> request(
    String method,
    String url,
    String token, {
    Object? body,
  });

  /// 列出目录内容，归一化为条目列表
  Future<List<GitHubFileItem>> listContents(RepoConfig repo, String path);

  /// 读取文件，返回 {content, sha}；文件不存在返回 null
  Future<Map<String, String>?> readFile(RepoConfig repo, String path);

  /// 读取文件在指定 ref（branch/tag/commit）下的内容，返回 {content, sha}
  Future<Map<String, String>?> readFileAtRef(
    RepoConfig repo,
    String path,
    String ref,
  );

  /// 写入文件，返回新 sha（无 sha 语义的平台返回 null）
  Future<String?> writeFile(
    RepoConfig repo,
    String path,
    List<int> bytes, {
    String? sha,
    required String message,
  });

  /// 删除文件
  Future<void> deleteFile(
    RepoConfig repo,
    String path,
    String sha, {
    required String message,
  });

  /// 提交历史
  Future<List<GitCommitItem>> listCommits(
    RepoConfig repo, {
    int perPage = 30,
    String? path,
  });

  /// 单文件最近一次提交时间（供列表排序）
  Future<DateTime?> latestCommitDate(RepoConfig repo, String path);

  /// 文件公开访问 URL（上传二进制后返回下载链接）
  String rawUrl(RepoConfig repo, String path);
}
