import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/repo_config.dart';
import '../services/cloud_sync_service.dart';
import '../services/log_service.dart';

/// 云同步设置页面
///
/// 支持多后端配置：
/// - GitHub 私有仓库同步
/// - WebDAV 网盘同步
/// - 自动同步开关
class SyncSettingsScreen extends StatefulWidget {
  final CloudSyncService cloudSyncService;
  final LogService logService;
  final AppSettings settings;
  final List<RepoConfig> repos;
  final void Function(AppSettings) onSettingsChanged;
  final VoidCallback onPushAll;
  final VoidCallback onPullAll;

  const SyncSettingsScreen({
    super.key,
    required this.cloudSyncService,
    required this.logService,
    required this.settings,
    required this.repos,
    required this.onSettingsChanged,
    required this.onPushAll,
    required this.onPullAll,
  });

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final githubBackend = widget.cloudSyncService.getBackend(SyncBackendType.github);
    final webdavBackend = widget.cloudSyncService.getBackend(SyncBackendType.webdav);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 标题 ──
        Text('云同步',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cs.primary)),
        const SizedBox(height: 4),
        Text('将草稿、设置、同步映射同步到云端，实现手机版与桌面版数据互通',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(height: 24),

        // ── 手动操作 ──
        _sectionTitle('手动同步'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _actionButton(
                icon: Icons.cloud_upload_outlined,
                label: '全部推送',
                subtitle: '上传到云端',
                color: cs.primary,
                onTap: widget.onPushAll,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionButton(
                icon: Icons.cloud_download_outlined,
                label: '全部拉取',
                subtitle: '从云端下载',
                color: const Color(0xFF059669),
                onTap: widget.onPullAll,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ── GitHub 同步 ──
        _sectionTitle('方案一：GitHub 仓库同步'),
        const SizedBox(height: 4),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('使用独立的专用仓库保存草稿和同步数据，避免污染网站站点仓库',
              style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
        ),
        _buildGitHubConfig(githubBackend as GitHubSyncBackend),
        const SizedBox(height: 16),

        // ── WebDAV 同步 ──
        _sectionTitle('方案二：WebDAV 网盘同步'),
        const SizedBox(height: 8),
        _backendCard(
          icon: Icons.cloud,
          name: 'WebDAV 网盘',
          description: '支持坚果云、Nextcloud 等 WebDAV 协议网盘，文件级同步，自动检测冲突',
          isConfigured: webdavBackend?.isConfigured ?? false,
          configWidget: _buildWebDavConfig(),
        ),
        const SizedBox(height: 24),

        // ── 草稿同步开关 ──
        _sectionTitle('草稿同步'),
        const SizedBox(height: 8),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: Colors.white,
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('启用草稿云同步', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('将草稿自动同步到配置的云端仓库，默认关闭'),
                  value: widget.settings.draftSyncEnabled,
                  onChanged: (v) {
                    widget.onSettingsChanged(
                      widget.settings.copyWith(draftSyncEnabled: v),
                    );
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                if (widget.settings.draftSyncEnabled) ...[
                  const Divider(),
                  ListTile(
                    title: const Text('同步间隔', style: TextStyle(fontSize: 14)),
                    subtitle: Text('${widget.settings.webdavAutoSyncIntervalSeconds ~/ 60} 分钟'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showIntervalPicker(),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('仅 WiFi 下同步', style: TextStyle(fontSize: 14)),
                    value: widget.settings.webdavSyncWifiOnly,
                    onChanged: (v) {
                      widget.onSettingsChanged(
                        widget.settings.copyWith(webdavSyncWifiOnly: v),
                      );
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),

        // ── 安全说明 ──
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.amber.withOpacity(0.3)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.security, size: 18, color: Colors.amber),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '敏感数据（Token、API Key、密码）在同步前会经过 XOR 加密处理，'
                  '不同设备使用不同密钥，即使同步文件泄露也无法解密。',
                  style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade500,
            letterSpacing: 0.5));
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: color.withOpacity(0.2)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(label,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: color)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _backendCard({
    required IconData icon,
    required String name,
    required String description,
    required bool isConfigured,
    required Widget configWidget,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isConfigured
                        ? const Color(0xFF059669).withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon,
                      size: 20,
                      color: isConfigured ? const Color(0xFF059669) : Colors.grey),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(description,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isConfigured
                        ? const Color(0xFF059669).withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isConfigured ? '已配置' : '未配置',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isConfigured ? const Color(0xFF059669) : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            configWidget,
          ],
        ),
      ),
    );
  }

  Widget _buildGitHubConfig(GitHubSyncBackend backend) {
    final isConfigured = backend.isConfigured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isConfigured) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow('仓库', '${widget.settings.syncRepoOwner}/${widget.settings.syncRepoName}'),
                _infoRow('分支', widget.settings.syncRepoBranch),
                _infoRow('Token', widget.settings.syncRepoToken.isNotEmpty ? '已配置' : '未配置'),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          icon: Icon(isConfigured ? Icons.edit : Icons.add, size: 16),
          label: Text(isConfigured ? '修改同步仓库' : '配置同步仓库'),
          onPressed: () => _showGitHubSyncRepoDialog(backend),
        ),
      ],
    );
  }

  Widget _buildWebDavConfig() {
    final isConfigured = widget.settings.webdavUrl.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isConfigured) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow('地址', widget.settings.webdavUrl),
                _infoRow('账号', widget.settings.webdavUsername),
                _infoRow('目录', widget.settings.webdavFolder),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          icon: Icon(isConfigured ? Icons.edit : Icons.add, size: 16),
          label: Text(isConfigured ? '修改配置' : '配置 WebDAV'),
          onPressed: () => _showWebDavConfigDialog(),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Future<void> _showGitHubSyncRepoDialog(GitHubSyncBackend backend) async {
    final ownerCtrl = TextEditingController(text: widget.settings.syncRepoOwner);
    final repoCtrl = TextEditingController(text: widget.settings.syncRepoName);
    final branchCtrl = TextEditingController(text: widget.settings.syncRepoBranch);
    final tokenCtrl = TextEditingController(text: widget.settings.syncRepoToken);

    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('配置同步仓库'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ownerCtrl,
                decoration: const InputDecoration(
                  labelText: '仓库 Owner',
                  hintText: 'your-github-username',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: repoCtrl,
                decoration: const InputDecoration(
                  labelText: '仓库名称',
                  hintText: 'hexo-sync-backup',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: branchCtrl,
                decoration: const InputDecoration(
                  labelText: '分支',
                  hintText: 'main',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tokenCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'GitHub Token',
                  hintText: 'ghp_xxxxxxxxxxxx',
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '请使用与网站仓库不同的独立仓库，避免同步草稿污染网站代码',
                  style: TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final newSettings = widget.settings.copyWith(
                syncRepoOwner: ownerCtrl.text.trim(),
                syncRepoName: repoCtrl.text.trim(),
                syncRepoBranch: branchCtrl.text.trim().isEmpty ? 'main' : branchCtrl.text.trim(),
                syncRepoToken: tokenCtrl.text.trim(),
              );
              widget.onSettingsChanged(newSettings);
              backend.configureFromSyncSettings(newSettings.sync);
              setState(() {});
              widget.logService.add('云同步', '已配置 GitHub 同步仓库: ${ownerCtrl.text.trim()}/${repoCtrl.text.trim()}');
              Navigator.pop(ctx, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _showWebDavConfigDialog() async {
    final urlCtrl = TextEditingController(text: widget.settings.webdavUrl);
    final userCtrl = TextEditingController(text: widget.settings.webdavUsername);
    final passCtrl = TextEditingController(text: widget.settings.webdavPassword);
    final folderCtrl = TextEditingController(text: widget.settings.webdavFolder);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('WebDAV 配置'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'WebDAV 地址',
                  hintText: 'https://dav.jianguoyun.com/dav',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: userCtrl,
                decoration: const InputDecoration(labelText: '账号'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: folderCtrl,
                decoration: const InputDecoration(
                  labelText: '同步目录',
                  hintText: 'hexo-sync',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              widget.onSettingsChanged(
                widget.settings.copyWith(
                  webdavUrl: urlCtrl.text.trim(),
                  webdavUsername: userCtrl.text.trim(),
                  webdavPassword: passCtrl.text,
                  webdavFolder: folderCtrl.text.trim().isEmpty
                      ? 'hexo-sync'
                      : folderCtrl.text.trim(),
                ),
              );
              // 同步配置到 WebDAV 后端
              final backend = widget.cloudSyncService.getBackend(SyncBackendType.webdav);
              if (backend is WebDavSyncBackend) {
                backend.configureFromSettings(widget.settings);
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      setState(() {});
    }
  }

  void _showIntervalPicker() {
    showDialog(
      context: context,
      builder: (ctx) {
        final current = widget.settings.webdavAutoSyncIntervalSeconds ~/ 60;
        return AlertDialog(
          title: const Text('同步间隔'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [1, 3, 5, 10, 15, 30].map((min) {
              return RadioListTile<int>(
                title: Text('$min 分钟'),
                value: min,
                groupValue: current,
                onChanged: (v) {
                  if (v != null) {
                    widget.onSettingsChanged(
                      widget.settings.copyWith(
                        webdavAutoSyncIntervalSeconds: v * 60,
                      ),
                    );
                    Navigator.pop(ctx);
                  }
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }
}