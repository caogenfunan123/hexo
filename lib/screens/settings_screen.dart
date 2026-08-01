import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_settings.dart';
import '../models/repo_config.dart';
import '../services/github_service.dart';
import '../services/storage_service.dart';
import '../services/webdav_service.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final List<RepoConfig> repos;
  final GitHubService github;
  final StorageService storage;
  final WebDavService webdavService;
  final Future<void> Function(AppSettings) onSettingsChanged;
  final Future<void> Function(List<RepoConfig>) onReposChanged;
  final VoidCallback onShowWebDavDialog;
  final VoidCallback onSyncWebDavToLocal;
  final VoidCallback onSyncDraftsToWebDav;
  final VoidCallback onShowAiManager;
  final VoidCallback onShowGithubTokenManager;
  final VoidCallback onShowRepoManager;
  final VoidCallback onShowSiteEditor;
  final VoidCallback onShowThemeColorPicker;
  final VoidCallback onShowPwaGuide;
  final VoidCallback onPersistSettings;
  final void Function(String) onShowToast;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.repos,
    required this.github,
    required this.storage,
    required this.webdavService,
    required this.onSettingsChanged,
    required this.onReposChanged,
    required this.onShowWebDavDialog,
    required this.onSyncWebDavToLocal,
    required this.onSyncDraftsToWebDav,
    required this.onShowAiManager,
    required this.onShowGithubTokenManager,
    required this.onShowRepoManager,
    required this.onShowSiteEditor,
    required this.onShowThemeColorPicker,
    required this.onShowPwaGuide,
    required this.onPersistSettings,
    required this.onShowToast,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _siteNameCtrl;
  late TextEditingController _siteBioCtrl;

  @override
  void initState() {
    super.initState();
    _siteNameCtrl = TextEditingController(text: widget.settings.siteName);
    _siteBioCtrl = TextEditingController(text: widget.settings.siteBio);
  }

  @override
  void dispose() {
    _siteNameCtrl.dispose();
    _siteBioCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final s = widget.settings.copyWith(
      siteName: _siteNameCtrl.text.trim(),
      siteBio: _siteBioCtrl.text.trim(),
    );
    await widget.onSettingsChanged(s);
    widget.onShowToast('设置已保存');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.settings;
    final activeRepo = widget.repos.isEmpty
        ? null
        : widget.repos.firstWhere(
            (r) => r.id == s.activeRepoId,
            orElse: () => widget.repos.firstWhere(
                  (r) => r.isDefault,
                  orElse: () => widget.repos.first,
                ),
          );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 基本信息 ──
        _sectionTitle('基本信息'),
        const SizedBox(height: 8),
        _settingsCard([
          _field(
            label: '网站名称',
            value: s.siteName,
            onChanged: (v) async {
              final ns = s.copyWith(siteName: v);
              await widget.onSettingsChanged(ns);
            },
          ),
          const SizedBox(height: 12),
          _field(
            label: '网站简介',
            value: s.siteBio,
            onChanged: (v) async {
              final ns = s.copyWith(siteBio: v);
              await widget.onSettingsChanged(ns);
            },
          ),
        ]),

        const SizedBox(height: 20),
        // ── GitHub 登录令牌 ──
        _sectionTitle('GitHub 登录令牌'),
        const SizedBox(height: 8),
        _settingsCard([
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.key_outlined),
            title: Text(
              s.activeGithubToken?.displayLabel ??
                  (s.effectiveGithubToken.isEmpty ? '尚未登录 Token' : '已配置 Token'),
            ),
            subtitle: Text(
              s.githubTokens.isEmpty
                  ? '保存过的 Token 可复用到多个仓库'
                  : '已保存 ${s.githubTokens.length} 个 · 点此管理',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onShowGithubTokenManager,
          ),
          if (s.githubTokens.isNotEmpty)
            DropdownButtonFormField<String>(
              value: s.githubTokens.any((e) => e.id == s.activeGithubTokenId)
                  ? s.activeGithubTokenId
                  : s.githubTokens.first.id,
              decoration: const InputDecoration(
                labelText: '当前登录令牌',
                prefixIcon: Icon(Icons.swap_horiz),
              ),
              items: s.githubTokens
                  .map((t) => DropdownMenuItem(
                        value: t.id,
                        child:
                            Text(t.displayLabel, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) async {
                if (v == null) return;
                for (final t in s.githubTokens) {
                  if (t.id == v) {
                    final ns = s.copyWith(
                      activeGithubTokenId: t.id,
                      defaultToken: t.token,
                    );
                    await widget.onSettingsChanged(ns);
                    widget.onPersistSettings();
                    final repo = widget.repos.isEmpty
                        ? null
                        : widget.repos.firstWhere(
                            (r) => r.id == s.activeRepoId,
                            orElse: () => widget.repos.firstWhere(
                                  (r) => r.isDefault,
                                  orElse: () => widget.repos.first,
                                ),
                          );
                    if (repo != null && repo.token.isEmpty) {
                      final idx = widget.repos.indexWhere((e) => e.id == repo.id);
                      if (idx >= 0) {
                        final updated = List<RepoConfig>.from(widget.repos);
                        updated[idx] = repo.copyWith(token: t.token);
                        await widget.onReposChanged(updated);
                      }
                    }
                    widget.onShowToast('已切换到 ${t.displayLabel}');
                    break;
                  }
                }
              },
            ),
          FilledButton.tonalIcon(
            onPressed: widget.onShowGithubTokenManager,
            icon: const Icon(Icons.login),
            label: const Text('管理已登录令牌'),
          ),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('多仓库管理'),
            subtitle: Text('当前 ${widget.repos.length} 个仓库'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onShowRepoManager,
          ),
          const Text(
            '登录过的 Token 会本地保存，可随时切换；新建/编辑仓库时可一键选用已登录令牌。',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ]),

        const SizedBox(height: 20),
        // ── WebDAV 云端备份 ──
        _sectionTitle('WebDAV 云端备份'),
        const SizedBox(height: 8),
        _settingsCard([
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('配置坚果云 / WebDAV 网盘'),
            subtitle: Text(s.webdavUrl.isEmpty
                ? '填写 WebDAV 地址、账号和密码'
                : '已配置: ${s.webdavUrl}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onShowWebDavDialog,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('上传草稿到 WebDAV'),
            subtitle: Text(s.webdavUrl.isEmpty ? '请先配置 WebDAV' : '同步本地草稿到云端'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onSyncDraftsToWebDav,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download_outlined),
            title: const Text('从 WebDAV 同步到本地'),
            subtitle: Text(s.webdavUrl.isEmpty ? '请先配置 WebDAV' : '下载云端草稿到本地'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onSyncWebDavToLocal,
          ),
        ]),

        const SizedBox(height: 20),
        // ── 图床（GitHub + CDN）──
        _sectionTitle('图床（GitHub + CDN）'),
        const SizedBox(height: 8),
        _settingsCard([
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sync_alt),
            title: const Text('一键同步当前仓库为图床'),
            subtitle: Text(
              activeRepo == null
                  ? '请先添加仓库'
                  : '使用 ${activeRepo!.fullName} / ${activeRepo!.branch}，Token 回退已登录令牌',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final r = activeRepo;
              if (r == null) {
                widget.onShowToast('请先添加仓库');
                return;
              }
              final ns = s.copyWith(
                imageBedOwner: r.owner,
                imageBedRepo: r.repo,
                imageBedBranch: r.branch,
                imageBedToken: s.imageBedToken.isNotEmpty
                    ? s.imageBedToken
                    : s.effectiveGithubToken,
                imageBedPath:
                    s.imageBedPath.isEmpty ? 'images' : s.imageBedPath,
              );
              await widget.onSettingsChanged(ns);
              widget.onShowToast('已同步图床仓库为 ${r.fullName}');
            },
          ),
          _field(
            label: '图床 Token（可留空用已登录令牌）',
            value: s.imageBedToken,
            obscure: true,
            onChanged: (v) async {
              await widget.onSettingsChanged(s.copyWith(imageBedToken: v));
            },
          ),
          _field(
            label: 'Owner',
            value: s.imageBedOwner,
            onChanged: (v) async {
              await widget.onSettingsChanged(s.copyWith(imageBedOwner: v));
            },
          ),
          _field(
            label: 'Repo',
            value: s.imageBedRepo,
            onChanged: (v) async {
              await widget.onSettingsChanged(s.copyWith(imageBedRepo: v));
            },
          ),
          _field(
            label: 'Branch',
            value: s.imageBedBranch,
            onChanged: (v) async {
              await widget.onSettingsChanged(s.copyWith(imageBedBranch: v));
            },
          ),
          _field(
            label: '目录路径',
            value: s.imageBedPath,
            onChanged: (v) async {
              await widget.onSettingsChanged(s.copyWith(imageBedPath: v));
            },
          ),
          _field(
            label: '自定义 CDN 前缀（可选）',
            value: s.imageBedCdn,
            onChanged: (v) async {
              await widget.onSettingsChanged(s.copyWith(imageBedCdn: v));
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('自动压缩图片'),
            subtitle: Text(
              '最大宽 ${s.compressMaxWidth}px / 质量 ${s.compressQuality}',
            ),
            value: s.autoCompressImage,
            onChanged: (v) async {
              await widget.onSettingsChanged(s.copyWith(autoCompressImage: v));
            },
          ),
        ]),

        const SizedBox(height: 20),
        // ── AI 中转站 ──
        _sectionTitle('AI 中转站（可多套切换）'),
        const SizedBox(height: 8),
        _settingsCard([
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.smart_toy_outlined),
            title: Text(
              s.activeAiProfile?.displayLabel ?? '尚未配置 AI',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              s.aiProfiles.isEmpty
                  ? '填写密钥和 URL，获取模型后保存；可添加多套任意切换'
                  : '已保存 ${s.aiProfiles.length} 套配置 · 点此管理',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onShowAiManager,
          ),
          if (s.aiProfiles.isNotEmpty)
            DropdownButtonFormField<String>(
              value: s.activeAiProfile?.id,
              decoration: const InputDecoration(
                labelText: '当前使用的 AI 配置',
                prefixIcon: Icon(Icons.swap_horiz),
              ),
              items: s.aiProfiles
                  .map((p) => DropdownMenuItem(
                        value: p.id,
                        child:
                            Text(p.displayLabel, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) async {
                if (v == null) return;
                final p = s.aiProfiles.firstWhere((e) => e.id == v);
                final ns = s.copyWith(
                  activeAiProfileId: p.id,
                  aiBaseUrl: p.baseUrl,
                  aiApiKey: p.apiKey,
                  aiModel: p.model,
                  aiProvider: p.name,
                );
                await widget.onSettingsChanged(ns);
                widget.onShowToast('已切换到 ${p.displayLabel}');
              },
            ),
          const SizedBox(height: 8),
          const Text(
            '兼容各类 OpenAI 中转站：填 Base URL + API Key → 点击获取模型 → 选择模型保存。',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ]),

        const SizedBox(height: 20),
        // ── 站点与 PWA ──
        _sectionTitle('站点与 PWA'),
        const SizedBox(height: 8),
        _settingsCard([
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.language),
            title: const Text('博客地址'),
            subtitle: Text(activeRepo?.siteUrl.isNotEmpty == true
                ? activeRepo!.siteUrl
                : 'https://caogenfunan.me/'),
            trailing: const Icon(Icons.copy),
            onTap: () {
              final u = activeRepo?.siteUrl.isNotEmpty == true
                  ? activeRepo!.siteUrl
                  : 'https://caogenfunan.me/';
              Clipboard.setData(ClipboardData(text: u));
              widget.onShowToast('已复制站点地址');
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.install_mobile),
            title: const Text('PWA 说明'),
            subtitle: const Text('站点已部署 Cloudflare Pages，可在浏览器"添加到主屏幕"'),
            onTap: widget.onShowPwaGuide,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.web),
            title: const Text('网站页面编辑'),
            subtitle: const Text('头像 · 名称 · 首页 · 关于 · 留言 · Now · 作品'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onShowSiteEditor,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.palette),
            title: const Text('主题颜色'),
            subtitle: const Text('点击切换主题色'),
            trailing: CircleAvatar(
              backgroundColor: Color(s.themeColor),
              radius: 14,
            ),
            onTap: widget.onShowThemeColorPicker,
          ),
        ]),

        const SizedBox(height: 20),
        // ── 关于 ──
        _sectionTitle('关于'),
        const SizedBox(height: 8),
        _settingsCard([
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Hexo 写作管理系统'),
            subtitle: Text(
              '本地草稿 · 离线编辑 · GitHub 发布 · 图床 · AI · RSS · 搜索 · 提交回滚',
            ),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('作者'),
            subtitle: Text('小子'),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('版本'),
            subtitle: Text('1.0.1'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('联系邮箱'),
            subtitle: const Text('1995@139.com'),
            trailing: const Icon(Icons.copy),
            onTap: () {
              Clipboard.setData(const ClipboardData(text: '1995@139.com'));
              widget.onShowToast('已复制邮箱地址');
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('仓库'),
            subtitle: const Text('github.com/caogenfunan123/xiamend'),
            trailing: const Icon(Icons.copy),
            onTap: () {
              Clipboard.setData(
                const ClipboardData(
                    text: 'https://github.com/caogenfunan123/xiamend'),
              );
              widget.onShowToast('已复制仓库地址');
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('导出目录'),
            subtitle: const Text('查看本地 drafts_md 导出路径'),
            onTap: () async {
              final dir = await widget.storage.draftsDir();
              Clipboard.setData(ClipboardData(text: dir.path));
              widget.onShowToast('导出目录已复制: ${dir.path}');
            },
          ),
        ]),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: Color(0xFF0F172A),
        ),
      ),
    );
  }

  Widget _settingsCard(List<Widget> children) {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < children.length; i++) ...[
              children[i],
              if (i != children.length - 1) const SizedBox(height: 12),
            ]
          ],
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    bool obscure = false,
  }) {
    return TextFormField(
      initialValue: value,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onChanged: onChanged,
    );
  }
}