import 'dart:async';

import 'package:flutter/material.dart';

import '../core/site_manager.dart';
import '../models/blog_site_config.dart';
import '../models/git_provider.dart';
import '../models/repo_config.dart';
import '../services/github_service.dart';
import '../services/git_providers.dart';
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
  void initState() {
    super.initState();
    // siteUrl 回填：siteUrl 为空但已建站的站点，重新查询平台构建状态
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final repo in widget.repos) {
        if (repo.siteUrl.isEmpty && repo.siteProjectName.isNotEmpty) {
          _backfillSiteUrl(repo);
        }
      }
    });
  }

  /// siteUrl 回填（Requirement 6 AC 8 / Correctness 15）
  Future<void> _backfillSiteUrl(RepoConfig repo) async {
    if (repo.token.isEmpty) return;
    String? backfilled;
    try {
      if (repo.provider == GitProviderType.github) {
        final run = await GitHubProvider()
            .getActionsRun(repo.token, repo.owner, repo.repo);
        final status = run?['status']?.toString();
        final conclusion = run?['conclusion']?.toString();
        if (status == 'completed' && conclusion == 'success') {
          backfilled = 'https://${repo.owner}.github.io/${repo.repo}/';
        }
      } else if (repo.provider == GitProviderType.gitlab) {
        final pipeline = await GitLabProvider().getPipeline(
          repo.token,
          Uri.encodeComponent('${repo.owner}/${repo.repo}'),
        );
        final status = pipeline?['status']?.toString();
        if (status == 'success') {
          backfilled = 'https://${repo.owner}.gitlab.io/${repo.repo}/';
        }
      }
    } catch (e) {
      debugPrint('SiteMgmt: backfill siteUrl failed: $e');
      return;
    }
    if (backfilled == null || !mounted) return;
    final index = widget.repos.indexWhere((r) => r.id == repo.id);
    if (index < 0) return;
    widget.repos[index] = repo.copyWith(siteUrl: backfilled);
    widget.onChanged();
    setState(() {});
  }

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
          // 统计接入引导
          TextButton.icon(
            onPressed: _openAnalyticsGuide,
            icon: const Icon(Icons.query_stats, size: 18),
            label: const Text('统计接入'),
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
          [
            repo.fullName,
            if (repo.siteProjectName.isNotEmpty) '站点项目：${repo.siteProjectName}',
            if (repo.siteUrl.isNotEmpty) repo.siteUrl else if (repo.deployHooks.isNotEmpty) '站点构建中，地址待回填',
          ].join('  ·  '),
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (repo.provider == GitProviderType.github)
              _actionButton(Icons.public, '切换可见性', () => _toggleVisibility(repo)),
            if (repo.siteProjectName.isNotEmpty || repo.deployHooks.isNotEmpty)
              _actionButton(Icons.language, '绑定自定义域名', () => _bindCustomDomain(repo)),
            const SizedBox(width: 4),
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

  // ── 切换可见性（GitHub 模式一） ──
  Future<void> _toggleVisibility(RepoConfig repo) async {
    if (repo.token.isEmpty) {
      _showToast('该站点未配置令牌，无法切换可见性');
      return;
    }
    // 查询当前可见性
    bool? current;
    try {
      final data = await GitHubProvider().request(
        'GET', 'https://api.github.com/repos/${repo.owner}/${repo.repo}', repo.token);
      current = data is Map ? data['private'] == true : null;
    } catch (e) {
      _showToast('查询可见性失败：$e');
      return;
    }
    final target = current == true ? false : true;
    final freeNotice = target == true
        ? '\n\n注意：GitHub 免费账号私有仓库无法启用 Pages，该操作可能导致站点停用。'
        : '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(target ? '切换为私有' : '切换为公开'),
        content: Text('确认将仓库「${repo.name}」切换为${target ? '私有' : '公开'}？$freeNotice'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认切换'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await GitHubProvider()
          .updateVisibility(repo.token, repo.owner, repo.repo, target);
      _showToast('已切换为${target ? '私有' : '公开'}');
    } catch (e) {
      _showToast('切换失败：$e');
    }
  }

  // ── 绑定自定义域名 ──
  Future<void> _bindCustomDomain(RepoConfig repo) async {
    final ctrl = TextEditingController(text: repo.siteUrl.isNotEmpty && !repo.siteUrl.startsWith('https://')
        ? repo.siteUrl
        : '');
    final cname = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('绑定自定义域名'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'GitHub：先在 DNS 服务商添加 CNAME 记录指向 ${repo.repo}.${repo.owner}.github.io，再填写下方域名。\n'
              'GitLab：在 GitLab Pages 设置中添加自定义域名。\n'
              'Cloudflare：在 Cloudflare 控制台的 Pages 项目自定义域中配置。\n',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: '自定义域名',
                hintText: 'blog.example.com',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (cname == null || cname.isEmpty || !mounted) return;
    try {
      if (repo.provider == GitProviderType.github) {
        if (repo.token.isEmpty) {
          _showToast('该站点未配置令牌，无法绑定域名');
          return;
        }
        await GitHubProvider()
            .setCustomDomain(repo.token, repo.owner, repo.repo, cname);
      }
      // GitLab / Cloudflare：DNS 引导已在对话框展示，由用户在平台侧配置
      final updated = repo.copyWith(siteUrl: cname);
      final index = widget.repos.indexWhere((r) => r.id == repo.id);
      if (index >= 0) widget.repos[index] = updated;
      widget.onChanged();
      setState(() {});
      _showToast('已保存自定义域名，等待 DNS 生效后访问');
    } catch (e) {
      _showToast('绑定失败：$e');
    }
  }

  // ── 统计接入引导 ──

  /// 弹窗：选择仓库并配置统计（Umami / GA），注入 _config.yml 与主题 head
  Future<void> _openAnalyticsGuide() async {
    if (widget.repos.isEmpty) {
      _showToast('暂无建站仓库，请先添加站点');
      return;
    }
    final selectedRepo = await showDialog<RepoConfig>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择要配置统计的站点'),
        children: widget.repos
            .map((r) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, r),
                  child: Row(
                    children: [
                      const Icon(Icons.language, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Text('${r.name} (${r.fullName})')),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
    if (selectedRepo == null || !mounted) return;

    final typeCtrl = <String, String>{'type': 'umami'};
    final urlCtrl = TextEditingController();
    final siteIdCtrl = TextEditingController();
    final gaIdCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isUmami = typeCtrl['type'] == 'umami';
          return AlertDialog(
            title: const Text('接入站点统计'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('选择统计服务', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'umami', label: Text('Umami')),
                      ButtonSegment(value: 'ga', label: Text('Google Analytics')),
                    ],
                    selected: {typeCtrl['type']!},
                    onSelectionChanged: (s) => setDialogState(() {
                      typeCtrl['type'] = s.first;
                    }),
                  ),
                  const SizedBox(height: 16),
                  if (isUmami) ...[
                    TextField(
                      controller: urlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Umami 服务地址',
                        hintText: 'https://analytics.example.com',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: siteIdCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Umami 站点 ID',
                        hintText: 'umami 后台创建站点后获得的 id',
                        isDense: true,
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: gaIdCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Google Analytics 测量 ID',
                        hintText: 'G-XXXXXXXXXX',
                        isDense: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    '配置将写入仓库的 _config.yml 与主题 head，推送后触发重新部署。',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消')),
              FilledButton(
                onPressed: () async {
                  final script = isUmami
                      ? '<script async src="${urlCtrl.text.trim()}/script.js" data-website-id="${siteIdCtrl.text.trim()}"></script>'
                      : '<script async src="https://www.googletagmanager.com/gtag/js?id=${gaIdCtrl.text.trim()}"></script><script>window.dataLayer = window.dataLayer || []; function gtag(){dataLayer.push(arguments);} gtag("js", new Date()); gtag("config", "${gaIdCtrl.text.trim()}");</script>';
                  Navigator.pop(ctx);
                  await _applyAnalytics(selectedRepo, isUmami, script);
                },
                child: const Text('保存并部署'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 写入 _config.yml analytics 段 + 主题 head 注入脚本
  Future<void> _applyAnalytics(
      RepoConfig repo, bool isUmami, String script) async {
    if (repo.token.isEmpty) {
      _showToast('该站点未配置令牌，无法写入统计配置');
      return;
    }
    try {
      // 1. 更新 _config.yml 的 analytics 段
      final configRaw = await _githubService.getRawFile(repo, '_config.yml');
      if (configRaw != null) {
        String cc = configRaw['content']!;
        final key = isUmami ? 'umami' : 'google_analytics';
        // 移除旧的 analytics 段再追加
        cc = cc.replaceAll(
            RegExp(r'^analytics:\s*[\s\S]*?(?=^\S|\Z)', multiLine: true), '');
        cc = '$cc\nanalytics:\n  $key: true\n'.trimRight();
        await _githubService.putRawFile(repo, '_config.yml', '$cc\n',
            sha: configRaw['sha']);
      }

      // 2. 尝试注入主题 head（Hexo 主题常见路径）
      final injected = await _injectThemeHead(repo, script);
      _showToast(injected
          ? '统计配置已写入并注入主题，重新部署后生效'
          : '统计配置已写入 _config.yml，主题需手动在 head 添加脚本');
    } catch (e) {
      _showToast('统计配置写入失败: $e');
    }
  }

  /// 尝试在主题 head 模板注入统计脚本；返回是否注入成功
  Future<bool> _injectThemeHead(RepoConfig repo, String script) async {
    // 探测常见 head 模板路径
    const candidates = [
      'themes/A4/layout/_partial/head.ejs',
      'themes/A4/layout/head.ejs',
      'themes/A4/layout/_partial/header.ejs',
      'themes/A4/source/head.html',
    ];
    for (final path in candidates) {
      final raw = await _githubService.getRawFile(repo, path);
      if (raw == null) continue;
      var content = raw['content']!;
      if (content.contains('analytics')) {
        content = content.replaceAll(
            RegExp(r'<!-- analytics:start -->[\s\S]*?<!-- analytics:end -->'),
            '<!-- analytics:start -->\n$script\n<!-- analytics:end -->');
      } else {
        // 注入到 </head> 前
        content = content.replaceAll(
            '</head>', '<!-- analytics:start -->\n$script\n<!-- analytics:end -->\n</head>');
      }
      await _githubService.putRawFile(repo, path, content, sha: raw['sha']);
      return true;
    }
    return false;
  }

  // ── 编辑静态站点 ──
  void _editStaticSite(RepoConfig repo) {    Navigator.of(context).push(MaterialPageRoute(
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