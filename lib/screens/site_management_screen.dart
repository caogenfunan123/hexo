import 'dart:async';

import 'package:flutter/material.dart';

import '../core/site_manager.dart';
import '../models/blog_site_config.dart';
import '../models/repo_config.dart';
import '../services/github_service.dart';
import 'blog_site_editor_screen.dart';
import 'site_editor_screen.dart';

/// 站点管理面板
///
/// 统一管理静态仓库（RepoConfig）和动态 CMS 站点（BlogSiteConfig），
/// 支持编辑、删除、批量连通性测试。
class SiteManagementScreen extends StatefulWidget {
  final SiteManager siteManager;
  final List<RepoConfig> repos;
  final void Function() onChanged;

  const SiteManagementScreen({
    super.key,
    required this.siteManager,
    required this.repos,
    required this.onChanged,
  });

  @override
  State<SiteManagementScreen> createState() => _SiteManagementScreenState();
}

class _SiteManagementScreenState extends State<SiteManagementScreen> {
  bool _testing = false;
  final Map<String, bool?> _testResults = {};
  final GitHubService _githubService = GitHubService();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('站点管理', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          // 添加动态 CMS 站点
          TextButton.icon(
            onPressed: _addDynamicSite,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加CMS'),
          ),
          const SizedBox(width: 4),
          // 批量测试按钮
          TextButton.icon(
            onPressed: _testing ? null : _batchTestConnections,
            icon: _testing
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_find, size: 18),
            label: Text(_testing ? '测试中...' : '批量测试'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // ── 静态博客站点 ──
          _buildSectionHeader('静态博客', Icons.folder_outlined, cs),
          const SizedBox(height: 6),
          if (widget.repos.isEmpty)
            _buildEmptyHint('暂无静态博客站点'),
          ...widget.repos.map((r) => _buildStaticSiteCard(r, cs)),
          const SizedBox(height: 20),
          // ── 动态 CMS 站点 ──
          _buildSectionHeader('动态 CMS', Icons.cloud_outlined, cs),
          const SizedBox(height: 6),
          if (widget.siteManager.dynamicSites.isEmpty)
            _buildEmptyHint('暂无动态 CMS 站点'),
          ...widget.siteManager.dynamicSites.map((s) => _buildDynamicSiteCard(s, cs)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, ColorScheme cs) {
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 6),
        Text(title, style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface,
        )),
        const Spacer(),
        Text('${widget.repos.length + widget.siteManager.dynamicSites.length} 个站点',
            style: TextStyle(fontSize: 12, color: cs.outline)),
      ],
    );
  }

  Widget _buildEmptyHint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(text, style: TextStyle(fontSize: 13, color: Colors.grey[500])),
      ),
    );
  }

  Widget _buildStaticSiteCard(RepoConfig repo, ColorScheme cs) {
    final testResult = _testResults[repo.id];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.black.withOpacity(0.05)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: _testIcon(testResult, cs),
        title: Text(repo.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          '${repo.fullName}  ·  ${repo.frameworkId}',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _actionButton(Icons.edit_outlined, '编辑', () => _editStaticSite(repo)),
            const SizedBox(width: 4),
            _actionButton(Icons.delete_outline, '删除', () => _deleteStaticSite(repo),
                color: Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicSiteCard(BlogSiteConfig config, ColorScheme cs) {
    final testResult = _testResults[config.id];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.black.withOpacity(0.05)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: _testIcon(testResult, cs),
        title: Row(
          children: [
            Text(config.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(width: 6),
            _platformChip(config.type),
          ],
        ),
        subtitle: Text(
          '${config.siteUrl}  ·  ${config.authStatus}',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _actionButton(Icons.edit_outlined, '编辑', () => _editDynamicSite(config)),
            const SizedBox(width: 4),
            _actionButton(Icons.delete_outline, '删除', () => _deleteDynamicSite(config),
                color: Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _platformChip(BlogType type) {
    final label = type.displayName;
    final color = switch (type) {
      BlogType.wordpress => const Color(0xFF21759B),
      BlogType.ghost => const Color(0xFF15171A),
      BlogType.typecho => const Color(0xFFE14D43),
      _ => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _actionButton(IconData icon, String tooltip, VoidCallback? onTap, {Color? color}) {
    return IconButton(
      icon: Icon(icon, size: 18, color: color ?? Colors.grey[600]),
      onPressed: onTap,
      tooltip: tooltip,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
    );
  }

  Widget _testIcon(bool? result, ColorScheme cs) {
    if (result == null) {
      return Icon(Icons.circle_outlined, size: 16, color: Colors.grey[400]);
    }
    return Icon(
      result ? Icons.check_circle : Icons.error,
      size: 18,
      color: result ? Colors.green : Colors.red,
    );
  }

  // ── 编辑静态站点 ──
  void _editStaticSite(RepoConfig repo) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SiteEditorScreen(
        repo: repo,
        github: _githubService,
        onSaved: () {
          widget.onChanged();
          setState(() {});
        },
      ),
    ));
  }

  // ── 删除静态站点 ──
  Future<void> _deleteStaticSite(RepoConfig repo) async {
    final confirmed = await _confirmDelete(repo.name);
    if (confirmed != true) return;
    widget.repos.removeWhere((r) => r.id == repo.id);
    if (widget.siteManager.activeSiteId == repo.id) {
      final first = widget.siteManager.allSites.firstOrNull;
      if (first != null) widget.siteManager.setActiveSite(first.id);
    }
    widget.onChanged();
    setState(() {});
  }

  // ── 编辑动态站点 ──
  void _editDynamicSite(BlogSiteConfig config) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BlogSiteEditorScreen(
        existingConfig: config,
        appSettings: widget.siteManager.appSettings,
        onSaved: (updated) async {
          widget.siteManager.updateDynamicSite(updated);
          widget.onChanged();
          setState(() {});
        },
      ),
    ));
  }

  // ── 添加动态站点 ──
  void _addDynamicSite() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BlogSiteEditorScreen(
        appSettings: widget.siteManager.appSettings,
        onSaved: (updated) async {
          widget.siteManager.dynamicSites.add(updated);
          widget.onChanged();
          setState(() {});
        },
      ),
    ));
  }

  // ── 删除动态站点 ──
  Future<void> _deleteDynamicSite(BlogSiteConfig config) async {
    final confirmed = await _confirmDelete(config.name);
    if (confirmed != true) return;
    widget.siteManager.removeDynamicSite(config.id);
    widget.onChanged();
    setState(() {});
  }

  Future<bool?> _confirmDelete(String name) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange),
            SizedBox(width: 8),
            Text('确认删除'),
          ],
        ),
        content: Text('确定要删除站点「$name」吗？\n\n此操作不可撤销，但不会影响远端服务器上的实际内容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
  }

  // ── 批量连通性测试 ──
  Future<void> _batchTestConnections() async {
    setState(() => _testing = true);
    _testResults.clear();

    // 测试动态 CMS 站点
    for (final site in widget.siteManager.dynamicSites) {
      final adapter = widget.siteManager.getAdapter(site.id);
      if (adapter == null) {
        _testResults[site.id] = false;
        continue;
      }
      try {
        final result = await adapter.testConnection();
        _testResults[site.id] = result.success;
      } catch (e) { debugPrint('SiteMgmt: load sites failed: $e'); _testResults[site.id] = false; }
    }

    // 静态站点：尝试读取仓库信息验证
    for (final repo in widget.repos) {
      if (repo.token.isEmpty) {
        _testResults[repo.id] = false;
        continue;
      }
      try {
        await _githubService.testToken(repo);
        _testResults[repo.id] = true;
      } catch (e) { debugPrint('SiteMgmt: save sites failed: $e'); _testResults[repo.id] = false; }
    }

    if (mounted) {
      setState(() => _testing = false);
      final passCount = _testResults.values.where((v) => v == true).length;
      _showToast('测试完成: $passCount/${_testResults.length} 个站点连通正常');
    }
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }
}