import 'package:flutter/material.dart';

import '../models/repo_config.dart';
import '../services/site_health_monitor.dart';

/// 站点运维与监控面板
///
/// 聚合展示所有建站仓库的健康状态：CI 构建、HTTP 可达性、内容非空、
/// 最后提交时间；支持一键健康检查与一键触发构建。
class SiteOperationsScreen extends StatefulWidget {
  final List<RepoConfig> repos;
  final SiteHealthMonitor? monitor;
  final void Function(String message)? onToast;

  const SiteOperationsScreen({
    super.key,
    this.repos = const [],
    this.monitor,
    this.onToast,
  });

  @override
  State<SiteOperationsScreen> createState() => _SiteOperationsScreenState();
}

class _SiteOperationsScreenState extends State<SiteOperationsScreen> {
  late final SiteHealthMonitor _monitor;
  final Map<String, SiteHealthStatus> _results = {};
  final Set<String> _checking = {};
  String? _triggeringRepoId;

  @override
  void initState() {
    super.initState();
    _monitor = widget.monitor ?? SiteHealthMonitor();
  }

  Future<void> _checkAll() async {
    for (final repo in widget.repos) {
      await _checkRepo(repo);
    }
    _toast('健康检查完成');
  }

  Future<void> _checkRepo(RepoConfig repo) async {
    setState(() => _checking.add(repo.id));
    try {
      final status = await _monitor.check(repo);
      if (mounted) {
        setState(() => _results[repo.id] = status);
      }
    } catch (e) {
      _toast('检查 ${repo.name} 失败: $e');
    } finally {
      if (mounted) {
        setState(() => _checking.remove(repo.id));
      }
    }
  }

  Future<void> _triggerBuild(RepoConfig repo) async {
    setState(() => _triggeringRepoId = repo.id);
    try {
      await _monitor.triggerBuild(repo);
      _toast('已触发 ${repo.name} 构建，稍后自动刷新状态');
      await Future.delayed(const Duration(seconds: 3));
      await _checkRepo(repo);
    } catch (e) {
      _toast('触发构建失败: $e');
    } finally {
      if (mounted) {
        setState(() => _triggeringRepoId = null);
      }
    }
  }

  void _toast(String message) {
    if (widget.onToast != null) {
      widget.onToast!(message);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('站点运维与监控'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '全部检查',
            onPressed: widget.repos.isEmpty ? null : _checkAll,
          ),
        ],
      ),
      body: widget.repos.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.storage_outlined,
                      color: cs.onSurface.withOpacity(0.3), size: 48),
                  const SizedBox(height: 12),
                  Text('暂无建站仓库',
                      style: TextStyle(color: cs.onSurface.withOpacity(0.6))),
                  const SizedBox(height: 4),
                  Text('请先通过「一键建站」或「站点管理」配置仓库',
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.4))),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _checkAll,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: widget.repos.length,
                itemBuilder: (context, i) =>
                    _buildRepoCard(cs, widget.repos[i]),
              ),
            ),
    );
  }

  Widget _buildRepoCard(ColorScheme cs, RepoConfig repo) {
    final status = _results[repo.id];
    final checking = _checking.contains(repo.id);
    final triggering = _triggeringRepoId == repo.id;

    Color statusColor(ColorScheme c, String? state) {
      switch (state) {
        case 'ok':
        case 'success':
          return Colors.green;
        case 'in_progress':
          return Colors.orange;
        case 'failure':
        case 'error':
        case 'redirect':
          return c.error;
        default:
          return c.onSurface.withOpacity(0.3);
      }
    }

    final healthy = status?.isHealthy;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  healthy == null
                      ? Icons.circle_outlined
                      : healthy
                          ? Icons.check_circle
                          : Icons.error_outline,
                  color: statusColor(
                      cs, healthy == null ? null : healthy ? 'ok' : 'failure'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        repo.name,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${repo.fullName} · ${repo.frameworkId}',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                if (checking)
                  const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: '检查此站点',
                  onPressed: checking ? null : () => _checkRepo(repo),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 状态明细
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _statusChip(cs,
                    icon: Icons.rocket_launch_outlined,
                    label: 'CI: ${_ciLabel(status?.ciStatus)}',
                    color: statusColor(cs, _ciColorKey(status?.ciStatus))),
                _statusChip(cs,
                    icon: Icons.language,
                    label: 'HTTP: ${_httpLabel(status?.httpStatus)}',
                    color: statusColor(cs, status?.httpStatus)),
                _statusChip(cs,
                    icon: Icons.description_outlined,
                    label: status?.contentNonEmpty == null
                        ? '内容: 未检查'
                        : status!.contentNonEmpty
                            ? '内容: 非空'
                            : '内容: 为空',
                    color: status?.contentNonEmpty == null
                        ? cs.onSurface.withOpacity(0.3)
                        : status!.contentNonEmpty
                            ? Colors.green
                            : cs.error),
                if (status?.lastCommit != null)
                  _statusChip(cs,
                      icon: Icons.history,
                      label: '更新: ${_fmtTime(status!.lastCommit!)}',
                      color: cs.onSurface.withOpacity(0.5)),
              ],
            ),

            if (status?.httpMessage != null &&
                status!.httpStatus != 'ok') ...[
              const SizedBox(height: 6),
              Text(
                status.httpMessage!,
                style: TextStyle(fontSize: 12, color: cs.error),
              ),
            ],

            // 操作
            if (status != null || repo.siteUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (status?.canTriggerBuild ?? false) ...[
                    FilledButton.tonalIcon(
                      icon: triggering
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.play_arrow, size: 18),
                      label: const Text('触发构建'),
                      onPressed: triggering
                          ? null
                          : () => _triggerBuild(repo),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (repo.siteUrl.isNotEmpty)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('打开站点'),
                      onPressed: () => _openUrl(repo.siteUrl),
                    ),
                  if (status?.ciRunId != null) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.track_changes, size: 18),
                      label: const Text('CI #${status!.ciRunId}'),
                      onPressed: () => _openUrl(
                          'https://github.com/${repo.fullName}/actions'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _ciLabel(String? s) {
    switch (s) {
      case 'success':
        return '成功';
      case 'failure':
        return '失败';
      case 'in_progress':
        return '构建中';
      case 'unknown':
        return '未知';
      default:
        return '未检查';
    }
  }

  String? _ciColorKey(String? s) =>
      s == 'success' || s == 'failure' || s == 'in_progress' ? s : null;

  String _httpLabel(String? s) {
    switch (s) {
      case 'ok':
        return '正常';
      case 'redirect':
        return '重定向';
      case 'error':
        return '异常';
      default:
        return '未检查';
    }
  }

  Widget _statusChip(ColorScheme cs,
      {required IconData icon, required String label, required Color color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 12, color: cs.onSurface)),
      ],
    );
  }

  String _fmtTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }

  void _openUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (widget.onToast != null) {
      widget.onToast!('打开链接（桌面环境请使用系统浏览器）: $url');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('打开链接: $url'),
      duration: const Duration(seconds: 2),
    ));
  }
}
