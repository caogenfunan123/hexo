import 'git_http.dart';

/// Cloudflare Pages 提供商（模式二）
///
/// 基于 [gitHttpRequest] 复用 HTTP 层，鉴权统一 `Authorization: Bearer <apiToken>`。
/// API 基址 `https://api.cloudflare.com/client/v4`。
class CloudflarePagesProvider {
  const CloudflarePagesProvider();

  static const String _base = 'https://api.cloudflare.com/client/v4';

  /// Cloudflare API 通用请求：2xx 返回 result 字段（或完整响应），否则抛异常。
  Future<dynamic> _cfRequest(
    String method,
    String path,
    String apiToken, {
    Object? body,
  }) async {
    final headers = <String, String>{
      'Authorization': 'Bearer $apiToken',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': 'HexoBlogManager',
    };
    final data = await gitHttpRequest(method, '$_base$path', headers,
        jsonBody: body);
    if (data is! Map) throw Exception('Cloudflare API 响应异常');
    // 非 2xx 由 gitHttpRequest 抛异常；此处仅校验 success 标志
    final ok = data['success'] == true;
    if (!ok) {
      final errors = data['errors'];
      final msg = errors is List && errors.isNotEmpty
          ? errors
              .map((e) => e is Map
                  ? (e['message']?.toString() ?? '未知错误')
                  : e.toString())
              .join('; ')
          : 'Cloudflare API 请求失败';
      throw Exception(msg);
    }
    return data['result'];
  }

  /// 校验 API Token 有效性。成功返回 token 状态 map，失败抛异常。
  Future<Map<String, dynamic>> verifyToken(String apiToken) async {
    final data = await _cfRequest('GET', '/user/tokens/verify', apiToken);
    if (data is! Map) throw Exception('Token 校验响应异常');
    return Map<String, dynamic>.from(data);
  }

  /// 列出指定账号下的所有 Pages 项目。返回项目 map 列表。
  Future<List<Map<String, dynamic>>> listProjects(
      String apiToken, String accountId) async {
    final data = await _cfRequest(
        'GET', '/accounts/$accountId/pages/projects?per_page=100', apiToken);
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// 获取单个 Pages 项目详情（含 deploy_hooks 数组）。
  Future<Map<String, dynamic>> getProject(
      String apiToken, String accountId, String projectName) async {
    final data = await _cfRequest(
        'GET',
        '/accounts/$accountId/pages/projects/${Uri.encodeComponent(projectName)}',
        apiToken);
    if (data is! Map) throw Exception('读取 Pages 项目失败: $projectName');
    return Map<String, dynamic>.from(data);
  }

  /// 获取某次部署详情（用于轮询部署状态）。
  Future<Map<String, dynamic>> getDeployment(
      String apiToken,
      String accountId,
      String projectName,
      String deploymentId) async {
    final data = await _cfRequest(
        'GET',
        '/accounts/$accountId/pages/projects/${Uri.encodeComponent(projectName)}/deployments/$deploymentId',
        apiToken);
    if (data is! Map) throw Exception('读取部署详情失败');
    return Map<String, dynamic>.from(data);
  }

  /// 删除 Pages 项目（回滚用）。
  Future<void> deleteProject(
      String apiToken, String accountId, String projectName) async {
    await _cfRequest(
        'DELETE',
        '/accounts/$accountId/pages/projects/${Uri.encodeComponent(projectName)}',
        apiToken);
  }

  // ────────────────────────────────────────────────
  // 模式二衔接逻辑（Requirement 5 AC 6）
  // ────────────────────────────────────────────────

  /// 从项目详情解析 deploy_hooks 数组，返回首个 Deploy Hook URL。
  /// deploy_hooks 为空返回 null（由上层决定提示用户手动添加）。
  static String? parseDeployHookUrl(Map<String, dynamic> project) {
    final hooks = project['deploy_hooks'];
    if (hooks is! List || hooks.isEmpty) return null;
    for (final h in hooks) {
      if (h is Map) {
        final url = h['url']?.toString() ?? '';
        if (url.isNotEmpty) return url;
      }
    }
    return null;
  }

  /// 轮询到目标 Pages 项目并返回其 Deploy Hook URL。
  ///
  /// 轮询 [maxAttempts] * [intervalMs] 仍未检测到项目时返回 null（不抛异常）。
  /// 检测到项目但 deploy_hooks 为空也返回 null（由调用方提示用户）。
  Future<String?> waitForProjectWithHook(
    String apiToken,
    String accountId, {
    required String projectName,
    int maxAttempts = 60,
    int intervalMs = 1000,
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      await Future<void>.delayed(Duration(milliseconds: intervalMs));
      try {
        final project =
            await getProject(apiToken, accountId, projectName);
        final hook = parseDeployHookUrl(project);
        if (hook != null) return hook;
        // 项目存在但无 hook，继续等待（可能用户刚创建，hooks 尚未同步）
      } catch (_) {
        // 项目尚未创建，继续轮询
      }
    }
    return null;
  }
}

/// 部署状态解析辅助：将 Cloudflare 部署详情归一化为 (status, url)。
/// status ∈ success / failure / in_progress / unknown
class CloudflareDeploymentStatus {
  final String status;
  final String url;

  const CloudflareDeploymentStatus({required this.status, required this.url});

  static CloudflareDeploymentStatus fromDeployment(
      Map<String, dynamic> deployment) {
    final stages = deployment['stages'];
    var status = 'in_progress';
    if (stages is List && stages.isNotEmpty) {
      // 各 stage 的 status 取最先出现的非 pending 状态
      for (final s in stages) {
        if (s is Map) {
          final st = s['status']?.toString() ?? '';
          if (st == 'success' || st == 'failure') {
            status = st;
            break;
          }
        }
      }
    }
    final latestStage = deployment['latest_stage'] as Map?;
    if (latestStage != null) {
      final st = latestStage['status']?.toString() ?? '';
      if (st == 'success' || st == 'failure') status = st;
    }
    return CloudflareDeploymentStatus(
      status: status,
      url: deployment['url']?.toString() ?? '',
    );
  }
}
