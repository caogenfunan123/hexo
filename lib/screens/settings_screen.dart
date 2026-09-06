import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';
import '../models/app_settings.dart';
import '../models/git_provider.dart';
import '../models/repo_config.dart';
import '../services/github_service.dart';
import '../services/storage_service.dart';
import '../core/utils/abi_util.dart';
import '../services/update_checker_service.dart';
import '../services/draft_encryption_service.dart';
import '../services/webdav_service.dart';
import '../l10n/app_localizations.dart';
import '../models/ui_settings.dart';
import '../desktop/feature_entries.dart';
import 'local_file_zone_screen.dart';

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
  final VoidCallback? onShowBlogSiteManager;
  final VoidCallback? onShowCreateSite;

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
    this.onShowBlogSiteManager,
    this.onShowCreateSite,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static String _cachedVersion = '1.0.12';
  late TextEditingController _siteNameCtrl;
  late TextEditingController _siteBioCtrl;
  late TextEditingController _quickNoteAnchorCtrl;

  /// 设置页折叠的分区 key 集合（默认全部折叠，保持上次状态）
  late final Set<String> _collapsedSettingsSections;

  @override
  void initState() {
    super.initState();
    _siteNameCtrl = TextEditingController(text: widget.settings.siteName);
    _siteBioCtrl = TextEditingController(text: widget.settings.siteBio);
    _quickNoteAnchorCtrl = TextEditingController(
      text: widget.settings.ui.quickNoteAnchor,
    );
    _collapsedSettingsSections =
        (widget.settings.ui.collapsedSettingsSections.isNotEmpty
                ? widget.settings.ui.collapsedSettingsSections
                : _settingsSectionKeys)
            .toSet();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) {
        _cachedVersion = info.version;
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  /// 手动检查更新：读取 release.json 清单并弹窗展示
  Future<void> _checkForUpdates() async {
    final l10n = AppLocalizations.ofContext(context);
    final checker = UpdateCheckerService(currentVersion: _cachedVersion);
    showDialog<void>(
      context: context,
      builder: (ctx) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Text('正在检查更新...'),
          ],
        ),
      ),
    );
    final result = await checker.check();
    checker.dispose();
    if (!mounted) return;
    Navigator.pop(context);
    if (result.hasUpdate) {
      final r = result.release!;
      final artifact = Platform.isAndroid
          ? (r.androidArtifact(await getDeviceAbi()) ?? r.firstArtifact)
          : (r.artifactFor(_platformKey) ?? r.firstArtifact);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('发现新版本'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '当前 ${result.currentVersion} → 最新 ${r.version}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (r.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    r.notes.trim(),
                    style: const TextStyle(fontSize: 12, height: 1.4),
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (artifact != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '下载: ${artifact.url}',
                    style:
                        const TextStyle(fontSize: 11, color: Colors.blue),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (artifact.sha256 != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'SHA256: ${artifact.sha256}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: Colors.grey,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('稍后'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _openUrl(artifact?.url ?? r.version);
              },
              child: const Text('去更新'),
            ),
          ],
        ),
      );
    } else {
      widget.onShowToast('当前已是最新版本');
    }
  }

  /// 当前运行平台标识（与 release.json platforms 键对齐）
  String get _platformKey {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    return 'other';
  }

  @override
  void dispose() {
    _siteNameCtrl.dispose();
    _siteBioCtrl.dispose();
    _quickNoteAnchorCtrl.dispose();
    super.dispose();
  }

  /// 更新语言设置
  Future<void> _updateLanguage(String languageCode) async {
    final newSettings = widget.settings.copyWith(language: languageCode);
    await widget.onSettingsChanged(newSettings);
    widget.onShowToast(
      AppLocalizations.ofContext(context).translate('language_updated'),
    );
  }

  /// 获取语言显示名称
  String _getLanguageDisplayName(String languageCode) {
    return AppLanguage.fromCode(languageCode).displayName;
  }

  // ── 全局文件存储目录 ──

  /// 桌面端选择全局存储根目录（移动端改用 SAF 导出文件夹）
  Future<void> _pickStorageRoot() async {
    final l10n = AppLocalizations.ofContext(context);
    var path = '';
    try {
      const channel = MethodChannel('hexo/native');
      final picked = await channel.invokeMethod<String>('pickDirectory');
      if (picked != null && picked.isNotEmpty && picked.startsWith('/')) {
        path = picked;
      }
    } catch (_) {}
    if (path.isEmpty) {
      try {
        final picked = await FilePicker.platform.getDirectoryPath(
          dialogTitle: l10n.translate('pick_global_storage_root'),
        );
        if (picked != null && picked.isNotEmpty) path = picked;
      } catch (_) {}
    }
    if (path.isEmpty) {
      widget.onShowToast(l10n.translate('pick_dir_failed'));
      return;
    }
    final ns = widget.settings.copyWith(storageRootDir: path);
    await widget.onSettingsChanged(ns);
    widget.onShowToast(
      l10n.translate('global_storage_set', params: {'path': path}),
    );
  }

  /// 复制当前存储根目录路径
  Future<void> _copyStorageRootPath() async {
    final l10n = AppLocalizations.ofContext(context);
    final dir = await widget.storage.root;
    await Clipboard.setData(ClipboardData(text: dir.path));
    widget.onShowToast(
      l10n.translate('export_dir_copied', params: {'path': dir.path}),
    );
  }

  /// 打开本地文件区（应用内浏览/暂存，替代原生文件管理器）
  Future<void> _openStorageFolderInSettings() async {
    final dir = await widget.storage.root;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LocalFileZoneScreen(
          storage: widget.storage,
          github: widget.github,
          activeRepo: widget.repos.isNotEmpty ? widget.repos.first : null,
        ),
      ),
    );
  }

  /// 重置为默认存储根目录
  Future<void> _resetStorageRoot() async {
    final l10n = AppLocalizations.ofContext(context);
    final ns = widget.settings.copyWith(storageRootDir: '');
    await widget.onSettingsChanged(ns);
    widget.onShowToast(l10n.translate('global_storage_reset'));
  }

  /// Android SAF：选择外部导出文件夹（持久化 content:// URI）
  Future<void> _pickExternalSafDir() async {
    final l10n = AppLocalizations.ofContext(context);
    try {
      final dir = await widget.storage.pickExternalSafDir();
      if (dir == null) return;
      final ns = widget.settings.copyWith(externalSafUri: dir.uri);
      await widget.onSettingsChanged(ns);
      widget.onShowToast(
        l10n.translate('external_saf_dir_set', params: {'name': dir.name}),
      );
    } catch (e) {
      widget.onShowToast(l10n.translate('pick_dir_failed'));
    }
  }

  /// Android SAF：清除外部导出文件夹授权
  Future<void> _clearExternalSafDir() async {
    final l10n = AppLocalizations.ofContext(context);
    final ns = widget.settings.copyWith(externalSafUri: null);
    await widget.onSettingsChanged(ns);
    widget.onShowToast(l10n.translate('external_saf_dir_cleared'));
  }

  /// Android SAF：查看导出文件夹内容（列出目录下文件）
  Future<void> _showExternalSafDirDialog() async {
    final l10n = AppLocalizations.ofContext(context);
    if (widget.settings.externalSafUri == null ||
        widget.settings.externalSafUri!.isEmpty) {
      widget.onShowToast(l10n.translate('pick_export_folder_first'));
      return;
    }
    final files = await widget.storage.listExternalSafDir();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.translate('export_folder_contents')),
          content: SizedBox(
            width: double.maxFinite,
            child: files.isEmpty
                ? Text(l10n.translate('export_folder_empty'))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: files.length,
                    itemBuilder: (ctx, i) {
                      final f = files[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.insert_drive_file_outlined),
                        title: Text(f.name),
                        trailing: Text(
                          '${(f.length / 1024).toStringAsFixed(1)} KB',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.translate('cancel')),
            ),
          ],
        );
      },
    );
  }

  /// 一键迁移旧目录全部历史文件到当前全局根目录（带进度对话框）
  Future<void> _migrateStorageRoot(String oldRoot) async {
    final l10n = AppLocalizations.ofContext(context);
    final progress = ValueNotifier<int>(0);
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.translate('migrating_title')),
          content: ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (ctx, done, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    l10n.translate('migrating_progress',
                        params: {'count': '$done'}),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
    try {
      final count = await widget.storage
          .migrateFrom(oldRoot, onProgress: (d, _) => progress.value = d);
      progress.dispose();
      if (mounted) Navigator.of(context).pop();
      widget.onShowToast(
        l10n.translate('global_storage_migrated', params: {'count': '$count'}),
      );
    } catch (e) {
      progress.dispose();
      if (mounted) Navigator.of(context).pop();
      widget.onShowToast('$e');
    }
  }

  /// 选择自定义壁纸图片
  Future<void> _pickWallpaper() async {
    final l10n = AppLocalizations.ofContext(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        dialogTitle: '选择壁纸图片',
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.first.path;
      if (path == null || path.isEmpty) {
        widget.onShowToast('无法读取所选文件');
        return;
      }
      final file = File(path);
      if (!file.existsSync()) {
        widget.onShowToast('所选文件不存在');
        return;
      }
      // 复制到应用存储目录，避免外部路径失效
      final rootDir = await widget.storage.root;
      final wallDir = Directory('${rootDir.path}/wallpaper');
      if (!wallDir.existsSync()) wallDir.createSync(recursive: true);
      final ext = file.path.contains('.')
          ? file.path.split('.').last.split('?').first
          : 'jpg';
      final target = File(
        '${wallDir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await file.copy(target.path);
      final et = widget.settings.ui.editorTheme.copyWith(
        bgMode: 2,
        wallpaperPath: target.path,
      );
      await widget.onSettingsChanged(
        widget.settings.copyWith(
          ui: widget.settings.ui.copyWith(editorTheme: et),
        ),
      );
      widget.onShowToast('壁纸已应用');
    } catch (_) {
      widget.onShowToast(l10n.translate('pick_dir_failed'));
    }
  }

  Widget _storageActionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return OutlinedButton.icon(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 17, color: const Color(0xFF475569)),
      label: Text(label, style: const TextStyle(color: Color(0xFF475569))),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// 显示语言选择器
  void _showLanguageSelector() {
    final l10n = AppLocalizations.ofContext(context);
    final languages = AppLanguage.supportedLanguages;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('select_language')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: languages.map((lang) {
            return RadioListTile<String>(
              title: Text(lang.displayName),
              value: lang.locale,
              groupValue: widget.settings.language,
              onChanged: (value) {
                if (value != null) {
                  Navigator.of(context).pop();
                  _updateLanguage(value);
                }
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.translate('cancel')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final l10n = AppLocalizations.ofContext(context);
    final mode = s.ui.appMode;
    final extras = s.ui.simpleModeExtras;
    bool sectionVisible(String id) =>
        SettingsEntries.visibleEntry(id, mode, extras);
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
        _section('basic_info', l10n.translate('settings_basic_info'), [
          _field(
            label: l10n.translate('website_name'),
            value: s.siteName,
            onChanged: (v) async {
              final ns = s.copyWith(siteName: v);
              await widget.onSettingsChanged(ns);
            },
          ),
          const SizedBox(height: 12),
          _field(
            label: l10n.translate('website_bio'),
            value: s.siteBio,
            onChanged: (v) async {
              final ns = s.copyWith(siteBio: v);
              await widget.onSettingsChanged(ns);
            },
          ),
          const SizedBox(height: 12),
          _field(
            label: l10n.translate('site_preview_url'),
            value: s.sitePreviewUrl,
            hint: 'https://your-site.com/',
            onChanged: (v) async {
              final ns = s.copyWith(sitePreviewUrl: v);
              await widget.onSettingsChanged(ns);
            },
          ),
          const SizedBox(height: 12),
          _field(
            label: l10n.translate('language'),
            value: _getLanguageDisplayName(s.language),
            hint: l10n.translate('language_selector_hint'),
            readOnly: true,
            onTap: () => _showLanguageSelector(),
          ),
        ]),

        const SizedBox(height: 20),
        // ── 简易普通用户模式 ──
        if (sectionVisible('app_mode')) ...[
          _section('app_mode', '简易普通用户模式', [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: mode == AppMode.simple,
              title: const Text(
                '简易普通用户模式',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                '隐藏专业开发与运维入口，保留写作、同步与 AI 配置',
                style: TextStyle(fontSize: 12),
              ),
              secondary: const Icon(Icons.auto_stories_outlined),
              onChanged: (v) async {
                final ns = s.copyWith(
                  ui: s.ui.copyWith(
                    appMode: v ? AppMode.simple : AppMode.standard,
                  ),
                );
                await widget.onSettingsChanged(ns);
              },
            ),
          ]),
          const SizedBox(height: 20),
          if (mode == AppMode.simple) ...[
            _section('simple_extras', '简易模式显示功能', [
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  '以下功能在简易模式下默认隐藏，可按需加回侧边栏：',
                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
              ),
              ..._buildOptInTiles(s),
            ]),
            const SizedBox(height: 20),
          ],
        ],

        // ── GitHub 登录令牌 ──
        _section('github_token', l10n.translate('settings_github_token'), [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.key_outlined),
            title: Text(
              s.activeGithubToken?.displayLabel ??
                  (s.effectiveGithubToken.isEmpty
                      ? l10n.translate('not_logged_in')
                      : l10n.translate('token_configured')),
            ),
            subtitle: Text(
              s.githubTokens.isEmpty
                  ? l10n.translate('saved_tokens_reuse')
                  : l10n
                        .translate('saved_tokens_count')
                        .replaceAll('{count}', '${s.githubTokens.length}'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onShowGithubTokenManager,
          ),
          if (s.githubTokens.isNotEmpty)
            DropdownButtonFormField<String>(
              value: s.githubTokens.any((e) => e.id == s.activeGithubTokenId)
                  ? s.activeGithubTokenId
                  : s.githubTokens.first.id,
              decoration: InputDecoration(
                labelText: l10n.translate('current_token'),
                prefixIcon: Icon(Icons.swap_horiz),
              ),
              items: s.githubTokens
                  .map(
                    (t) => DropdownMenuItem(
                      value: t.id,
                      child: Text(
                        t.displayLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
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
                      final idx = widget.repos.indexWhere(
                        (e) => e.id == repo.id,
                      );
                      if (idx >= 0) {
                        final updated = List<RepoConfig>.from(widget.repos);
                        updated[idx] = repo.copyWith(token: t.token);
                        await widget.onReposChanged(updated);
                      }
                    }
                    widget.onShowToast(
                      '${l10n.translate('switched_to')} ${t.displayLabel}',
                    );
                    break;
                  }
                }
              },
            ),
          FilledButton.tonalIcon(
            onPressed: widget.onShowGithubTokenManager,
            icon: const Icon(Icons.login),
            label: Text(l10n.translate('manage_tokens')),
          ),
          const SizedBox(height: 4),
          if (widget.onShowBlogSiteManager != null) ...[
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cloud_outlined),
              title: Text(l10n.translate('dynamic_blog_login')),
              subtitle: Text(
                widget.settings.blogSiteConfigs.isEmpty
                    ? 'WordPress / Ghost / Typecho'
                    : l10n
                          .translate('sites_configured')
                          .replaceAll(
                            '{count}',
                            '${widget.settings.blogSiteConfigs.length}',
                          ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.onShowBlogSiteManager,
            ),
          ],
          if (widget.onShowCreateSite != null) ...[
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add_business_outlined),
              title: const Text('一键建站'),
              subtitle: const Text(
                'AI 对话自动建站：GitHub Pages / GitLab Pages / Cloudflare Pages',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.onShowCreateSite,
            ),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.translate('multi_repo_manage')),
            subtitle: Text(
              l10n
                  .translate('repos_count')
                  .replaceAll('{count}', '${widget.repos.length}'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onShowRepoManager,
          ),
          Text(
            l10n.translate('token_hint'),
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ]),

        const SizedBox(height: 20),
        // ── WebDAV 云端备份 ──
        _section('webdav', l10n.translate('settings_webdav'), [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cloud_outlined),
            title: Text(l10n.translate('config_nutstore')),
            subtitle: Text(
              s.webdavUrl.isEmpty
                  ? l10n.translate('webdav_placeholder')
                  : l10n
                        .translate('webdav_configured')
                        .replaceAll('{url}', s.webdavUrl),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onShowWebDavDialog,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.upload_file_outlined),
            title: Text(l10n.translate('upload_drafts_webdav')),
            subtitle: Text(
              s.webdavUrl.isEmpty
                  ? l10n.translate('webdav_not_configured')
                  : l10n.translate('upload_drafts_hint'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onSyncDraftsToWebDav,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download_outlined),
            title: Text(l10n.translate('sync_webdav_local')),
            subtitle: Text(
              s.webdavUrl.isEmpty
                  ? l10n.translate('webdav_not_configured')
                  : l10n.translate('download_drafts_hint'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onSyncWebDavToLocal,
          ),
        ]),

        const SizedBox(height: 20),
        // ── 草稿自动保存 ──
        _section('draft_backup', l10n.translate('settings_draft_backup'), [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.translate('local_auto_save')),
            subtitle: Text(
              l10n
                  .translate('auto_save_interval_hint')
                  .replaceAll('{count}', '${s.autoSaveIntervalSeconds}'),
            ),
            value: s.autoSaveEnabled,
            onChanged: (v) async {
              await widget.onSettingsChanged(s.copyWith(autoSaveEnabled: v));
            },
          ),
          if (s.autoSaveEnabled)
            DropdownButtonFormField<int>(
              value: s.autoSaveIntervalSeconds,
              decoration: InputDecoration(
                labelText: l10n.translate('auto_save_interval'),
                prefixIcon: const Icon(Icons.timer_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 10, child: Text('10 秒')),
                DropdownMenuItem(value: 30, child: Text('30 秒')),
                DropdownMenuItem(value: 60, child: Text('1 分钟')),
                DropdownMenuItem(value: 180, child: Text('3 分钟')),
                DropdownMenuItem(value: 300, child: Text('5 分钟')),
              ],
              onChanged: (v) async {
                if (v != null) {
                  await widget.onSettingsChanged(
                    s.copyWith(autoSaveIntervalSeconds: v),
                  );
                }
              },
            ),
          if (s.autoSaveEnabled) ...[
            const SizedBox(height: 12),
            _field(
              label: l10n.translate('auto_save_dir'),
              value: s.autoSaveDir,
              onChanged: (v) async {
                await widget.onSettingsChanged(s.copyWith(autoSaveDir: v));
              },
            ),
            const SizedBox(height: 12),
            _field(
              label: l10n.translate('backup_dir'),
              value: s.backupDir,
              onChanged: (v) async {
                await widget.onSettingsChanged(s.copyWith(backupDir: v));
              },
            ),
          ],
          const SizedBox(height: 4),
          Text(
            l10n.translate('auto_save_hint'),
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
          const Divider(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.translate('netdisk_auto_sync')),
            subtitle: Text(
              s.webdavAutoSyncEnabled
                  ? l10n
                        .translate('webdav_auto_sync_enabled')
                        .replaceAll(
                          '{count}',
                          '${s.webdavAutoSyncIntervalSeconds ~/ 60}',
                        )
                  : l10n.translate('webdav_auto_sync_disabled'),
            ),
            value: s.webdavAutoSyncEnabled,
            onChanged: (v) async {
              await widget.onSettingsChanged(
                s.copyWith(webdavAutoSyncEnabled: v),
              );
            },
          ),
          if (s.webdavAutoSyncEnabled) ...[
            DropdownButtonFormField<int>(
              value: s.webdavAutoSyncIntervalSeconds,
              decoration: InputDecoration(
                labelText: l10n.translate('netdisk_sync_interval'),
                prefixIcon: const Icon(Icons.cloud_sync_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 60, child: Text('1 分钟')),
                DropdownMenuItem(value: 300, child: Text('5 分钟')),
                DropdownMenuItem(value: 600, child: Text('10 分钟')),
                DropdownMenuItem(value: 1800, child: Text('30 分钟')),
              ],
              onChanged: (v) async {
                if (v != null) {
                  await widget.onSettingsChanged(
                    s.copyWith(webdavAutoSyncIntervalSeconds: v),
                  );
                }
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.translate('only_wifi_sync')),
              subtitle: Text(l10n.translate('only_wifi_sync_hint')),
              value: s.webdavSyncWifiOnly,
              onChanged: (v) async {
                await widget.onSettingsChanged(
                  s.copyWith(webdavSyncWifiOnly: v),
                );
              },
            ),
          ],
          const Divider(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.translate('restore_last_session')),
            subtitle: Text(l10n.translate('restore_last_session_hint')),
            value: s.restoreSession,
            onChanged: (v) async {
              await widget.onSettingsChanged(s.copyWith(restoreSession: v));
            },
          ),
        ]),

        const SizedBox(height: 20),
        // ── 文件存储区域 ──
        // 桌面端：全局文件存储目录（路径选择）
        // 移动端：SAF 授权导出文件夹（content:// URI）
        if (kIsWeb || !Platform.isAndroid)
          _section('global_storage', l10n.translate('settings_global_storage'), [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.folder_outlined,
                color: Color(0xFF6366F1),
              ),
              title: Text(l10n.translate('global_storage_root')),
              subtitle: Text(
                s.storageRootDir.isEmpty
                    ? l10n.translate('global_storage_default')
                    : s.storageRootDir,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickStorageRoot,
            ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: _storageActionBtn(
                    icon: Icons.copy_outlined,
                    label: l10n.translate('copy_path'),
                    onTap: () => _copyStorageRootPath(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _storageActionBtn(
                    icon: Icons.restart_alt,
                    label: l10n.translate('reset_storage_root'),
                    onTap: _resetStorageRoot,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _storageActionBtn(
                    icon: Icons.folder_open_outlined,
                    label: l10n.translate('open_save_dir'),
                    onTap: () => _openStorageFolderInSettings(),
                  ),
                ),
              ],
            ),
            if (s.storageRootDir.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _storageActionBtn(
                      icon: Icons.drive_file_move_outline,
                      label: l10n.translate('migrate_storage_root'),
                      onTap: () => _migrateStorageRoot(s.storageRootDir),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Text(
              l10n.translate('global_storage_hint'),
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
          ]),
        if (Platform.isAndroid)
          _section('export_folder', l10n.translate('settings_export_folder'), [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.sd_card_outlined,
                color: Color(0xFF6366F1),
              ),
              title: Text(l10n.translate('export_folder_title')),
              subtitle: Text(
                s.externalSafUri != null && s.externalSafUri!.isNotEmpty
                    ? s.externalSafUri!
                    : l10n.translate('export_folder_not_set'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickExternalSafDir,
            ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: _storageActionBtn(
                    icon: Icons.folder_open_outlined,
                    label: l10n.translate('pick_export_folder'),
                    onTap: _pickExternalSafDir,
                  ),
                ),
                if (s.externalSafUri != null && s.externalSafUri!.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _storageActionBtn(
                      icon: Icons.close,
                      label: l10n.translate('clear_export_folder'),
                      onTap: _clearExternalSafDir,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _storageActionBtn(
                    icon: Icons.folder_open_outlined,
                    label: l10n.translate('view_export_folder'),
                    onTap: _showExternalSafDirDialog,
                  ),
                ),
                if (s.storageRootDir.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _storageActionBtn(
                      icon: Icons.drive_file_move_outline,
                      label: l10n.translate('migrate_storage_root'),
                      onTap: () => _migrateStorageRoot(s.storageRootDir),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.translate('export_folder_hint'),
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
          ]),

        const SizedBox(height: 20),
        // ── 发布状态预设 ──
        _section('publish_status', l10n.translate('settings_publish_status'), [
          _statusPresetManager(s),
          const Divider(height: 24),
          Text(
            l10n.translate('status_preset_hint'),
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ]),

        const SizedBox(height: 20),
        // ── 网络超时设置 ──
        _section('network', l10n.translate('settings_network'), [
          DropdownButtonFormField<int>(
            value: s.httpTimeoutSeconds,
            decoration: InputDecoration(
              labelText: l10n.translate('http_timeout'),
              prefixIcon: const Icon(Icons.timer_outlined),
            ),
            items: const [
              DropdownMenuItem(value: 10, child: Text('10 秒')),
              DropdownMenuItem(value: 15, child: Text('15 秒')),
              DropdownMenuItem(value: 30, child: Text('30 秒')),
              DropdownMenuItem(value: 60, child: Text('60 秒')),
              DropdownMenuItem(value: 120, child: Text('120 秒')),
            ],
            onChanged: (v) async {
              if (v != null) {
                await widget.onSettingsChanged(
                  s.copyWith(httpTimeoutSeconds: v),
                );
              }
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.translate('allow_insecure_https')),
            subtitle: Text(l10n.translate('allow_insecure_https_hint')),
            value: s.allowInsecureHttps,
            onChanged: (v) async {
              await widget.onSettingsChanged(s.copyWith(allowInsecureHttps: v));
            },
          ),
          const Divider(height: 24),
          Text(
            l10n.translate('http_timeout_hint'),
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ]),

        const SizedBox(height: 20),
        // ── 写作界面主题与背景 ──
        _section('editor_theme', '写作界面主题', [
          Text(
            '全屏背景铺满整机，消除分层边框；标题与正文透明无底色。',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                label: Text('纯白'),
                icon: Icon(Icons.brightness_high_outlined, size: 16),
              ),
              ButtonSegment(
                value: 1,
                label: Text('纯黑'),
                icon: Icon(Icons.dark_mode_outlined, size: 16),
              ),
              ButtonSegment(
                value: 2,
                label: Text('自定义壁纸'),
                icon: Icon(Icons.wallpaper_outlined, size: 16),
              ),
            ],
            selected: {s.ui.editorTheme.bgMode},
            onSelectionChanged: (sel) async {
              final mode = sel.first;
              final et = s.ui.editorTheme.copyWith(bgMode: mode);
              await widget.onSettingsChanged(
                s.copyWith(ui: s.ui.copyWith(editorTheme: et)),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickWallpaper,
                  icon: const Icon(Icons.image_outlined, size: 17),
                  label: Text(
                    s.ui.editorTheme.wallpaperPath.isEmpty ? '选择壁纸图片' : '更换壁纸',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
              if (s.ui.editorTheme.wallpaperPath.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () async {
                    final et = s.ui.editorTheme.copyWith(wallpaperPath: '');
                    await widget.onSettingsChanged(
                      s.copyWith(ui: s.ui.copyWith(editorTheme: et)),
                    );
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: '清除壁纸',
                ),
              ],
            ],
          ),
          const Divider(height: 24),
          Text(
            '强制字体颜色（互斥）：不勾选时根据背景亮度自动适配。',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('强制黑色字体'),
            value: s.ui.editorTheme.forceTextMode == 1,
            onChanged: (val) async {
              final mode = (val == true) ? 1 : 0;
              final et = s.ui.editorTheme.copyWith(forceTextMode: mode);
              await widget.onSettingsChanged(
                s.copyWith(ui: s.ui.copyWith(editorTheme: et)),
              );
            },
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('强制白色字体'),
            value: s.ui.editorTheme.forceTextMode == 2,
            onChanged: (val) async {
              final mode = (val == true) ? 2 : 0;
              final et = s.ui.editorTheme.copyWith(forceTextMode: mode);
              await widget.onSettingsChanged(
                s.copyWith(ui: s.ui.copyWith(editorTheme: et)),
              );
            },
          ),
        ]),

        const SizedBox(height: 20),
        // ── 图床（GitHub + CDN）──
        _section('image_host', l10n.translate('settings_image_host'), [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sync_alt),
            title: Text(l10n.translate('image_host_sync')),
            subtitle: Text(
              activeRepo == null
                  ? l10n.translate('image_host_no_repo')
                  : l10n
                        .translate('image_host_repo_hint')
                        .replaceAll('{name}', activeRepo.fullName)
                        .replaceAll('{branch}', activeRepo.branch),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final r = activeRepo;
              if (r == null) {
                widget.onShowToast(l10n.translate('image_host_no_repo'));
                return;
              }
              final ns = s.copyWith(
                imageBedOwner: r.owner,
                imageBedRepo: r.repo,
                imageBedBranch: r.branch,
                imageBedType: r.provider.key,
                imageBedToken: s.imageBedToken.isNotEmpty
                    ? s.imageBedToken
                    : s.effectiveGithubToken,
                imageBedPath: s.imageBedPath.isEmpty
                    ? 'images'
                    : s.imageBedPath,
              );
              await widget.onSettingsChanged(ns);
              widget.onShowToast(
                l10n
                    .translate('image_host_synced')
                    .replaceAll('{name}', r.fullName),
              );
            },
          ),
          DropdownButtonFormField<GitProviderType>(
            key: ValueKey(s.imageBedType),
            initialValue: GitProviderTypeX.fromKey(s.imageBedType),
            decoration: InputDecoration(
              labelText: '图床平台',
              prefixIcon: const Icon(Icons.cloud_outlined),
            ),
            items: [
              for (final p in GitProviderType.values)
                DropdownMenuItem(value: p, child: Text(p.label)),
            ],
            onChanged: (v) async {
              if (v == null) return;
              await widget.onSettingsChanged(s.copyWith(imageBedType: v.key));
            },
          ),
          _field(
            label: l10n.translate('image_bed_token'),
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
            label: l10n.translate('dir_path'),
            value: s.imageBedPath,
            onChanged: (v) async {
              await widget.onSettingsChanged(s.copyWith(imageBedPath: v));
            },
          ),
          _field(
            label: l10n.translate('cdn_prefix'),
            value: s.imageBedCdn,
            onChanged: (v) async {
              await widget.onSettingsChanged(s.copyWith(imageBedCdn: v));
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.translate('auto_compress_image')),
            subtitle: Text(
              l10n
                  .translate('compress_hint')
                  .replaceAll('{width}', '${s.compressMaxWidth}')
                  .replaceAll('{quality}', '${s.compressQuality}'),
            ),
            value: s.autoCompressImage,
            onChanged: (v) async {
              await widget.onSettingsChanged(s.copyWith(autoCompressImage: v));
            },
          ),
        ]),

        const SizedBox(height: 20),
        // ── AI 中转站 ──
        _section('ai_relay', l10n.translate('settings_ai_relay'), [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.smart_toy_outlined),
            title: Text(
              s.activeAiProfile?.displayLabel ??
                  l10n.translate('ai_not_configured'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              s.aiProfiles.isEmpty
                  ? l10n.translate('ai_profile_empty_hint')
                  : l10n
                        .translate('ai_profile_count')
                        .replaceAll('{count}', '${s.aiProfiles.length}'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onShowAiManager,
          ),
          if (s.aiProfiles.isNotEmpty)
            DropdownButtonFormField<String>(
              value: s.activeAiProfile?.id,
              decoration: InputDecoration(
                labelText: l10n.translate('current_ai_profile'),
                prefixIcon: const Icon(Icons.swap_horiz),
              ),
              items: s.aiProfiles
                  .map(
                    (p) => DropdownMenuItem(
                      value: p.id,
                      child: Text(
                        p.displayLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) async {
                if (v == null) return;
                final p = s.aiProfiles.firstWhere((e) => e.id == v);
                final ns = s.copyWith(
                  ai: s.ai.copyWith(
                    activeAiProfileId: p.id,
                    aiBaseUrl: p.baseUrl,
                    aiApiKey: p.apiKey,
                    aiModel: p.model,
                    aiProvider: p.name,
                  ),
                );
                await widget.onSettingsChanged(ns);
                widget.onShowToast(
                  '${l10n.translate('switched_to')} ${p.displayLabel}',
                );
              },
            ),
          const SizedBox(height: 8),
          Text(
            l10n.translate('ai_relay_desc'),
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ]),

        const SizedBox(height: 20),
        // ── AI 调度器 ──
        _section('ai_scheduler', l10n.translate('settings_ai_scheduler'), [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.translate('auto_best_mode')),
            subtitle: Text(l10n.translate('auto_best_mode_hint')),
            value: s.ai.aiAutoOptimalModel,
            onChanged: (v) async {
              await widget.onSettingsChanged(
                s.copyWith(ai: s.ai.copyWith(aiAutoOptimalModel: v)),
              );
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.translate('allow_ai_save_tool')),
            subtitle: Text(l10n.translate('allow_ai_save_tool_hint')),
            value: s.ai.aiAllowAutoSaveTools,
            onChanged: (v) async {
              await widget.onSettingsChanged(
                s.copyWith(ai: s.ai.copyWith(aiAllowAutoSaveTools: v)),
              );
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.translate('confirm_high_risk_tools')),
            subtitle: Text(l10n.translate('confirm_high_risk_tools_hint')),
            value: s.ai.aiConfirmHighRiskTools,
            onChanged: (v) async {
              await widget.onSettingsChanged(
                s.copyWith(ai: s.ai.copyWith(aiConfirmHighRiskTools: v)),
              );
            },
          ),
          _field(
            label: l10n.translate('ai_request_timeout'),
            value: s.ai.aiRequestTimeoutSec.toString(),
            onChanged: (v) async {
              final n = int.tryParse(v);
              if (n == null || n <= 0) return;
              await widget.onSettingsChanged(
                s.copyWith(ai: s.ai.copyWith(aiRequestTimeoutSec: n)),
              );
            },
          ),
          _field(
            label: l10n.translate('ai_max_switch'),
            value: s.ai.aiMaxSwitchCount.toString(),
            onChanged: (v) async {
              final n = int.tryParse(v);
              if (n == null || n < 0) return;
              await widget.onSettingsChanged(
                s.copyWith(ai: s.ai.copyWith(aiMaxSwitchCount: n)),
              );
            },
          ),
        ]),

        const SizedBox(height: 20),
        // ── 速记与快捷入口 ──
        _section('quick_note', '速记与快捷入口', [
          // 桌面小部件 / 通知栏磁贴引导
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.widgets_outlined,
              color: Color(0xFF0EA5E9),
            ),
            title: const Text('桌面小部件 / 通知栏磁贴'),
            subtitle: const Text(
              '长按桌面 → 添加小部件「速记」；下拉通知栏 → 编辑磁贴 → 拖入「速记」',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
          const Divider(height: 20),
          // 速记锚点
          TextField(
            controller: _quickNoteAnchorCtrl,
            decoration: const InputDecoration(
              labelText: '速记锚点（可选，写在开头）',
              hintText: '例如 # 灵感速记',
              prefixIcon: Icon(Icons.anchor_outlined, size: 20),
            ),
            onSubmitted: (v) async {
              await widget.onSettingsChanged(
                s.copyWith(ui: s.ui.copyWith(quickNoteAnchor: v.trim())),
              );
              widget.onShowToast('速记锚点已保存');
            },
          ),
          const SizedBox(height: 12),
          // 速记时间戳
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('速记自动插入时间戳'),
            value: s.ui.quickNoteTimestamp,
            onChanged: (v) async {
              await widget.onSettingsChanged(
                s.copyWith(ui: s.ui.copyWith(quickNoteTimestamp: v)),
              );
            },
          ),
          if (s.ui.quickNoteTimestamp) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: s.ui.timestampFormat,
              decoration: const InputDecoration(
                labelText: '时间戳格式',
                prefixIcon: Icon(Icons.schedule, size: 20),
              ),
              items: const [
                DropdownMenuItem(value: 'date', child: Text('日期')),
                DropdownMenuItem(value: 'time', child: Text('时间')),
                DropdownMenuItem(value: 'datetime', child: Text('日期+时间')),
                DropdownMenuItem(value: 'iso', child: Text('ISO 完整')),
                DropdownMenuItem(value: 'slash', child: Text('斜杠日期')),
                DropdownMenuItem(value: 'cn', child: Text('中文格式')),
                DropdownMenuItem(value: 'compact', child: Text('紧凑格式')),
              ],
              onChanged: (v) async {
                if (v == null) return;
                await widget.onSettingsChanged(
                  s.copyWith(ui: s.ui.copyWith(timestampFormat: v)),
                );
              },
            ),
          ],
        ]),

        const SizedBox(height: 20),
        // ── 隐私与加密 ──
        _section('privacy_encryption', '隐私与加密', [_buildDraftEncryptionTile()]),

        const SizedBox(height: 20),
        // ── 站点与 PWA ──
        if (sectionVisible('site_pwa')) ...[
          _section('site_pwa', l10n.translate('settings_site_pwa'), [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.language),
              title: Text(l10n.translate('blog_address')),
              subtitle: Text(
                activeRepo?.siteUrl.isNotEmpty == true
                    ? activeRepo!.siteUrl
                    : (s.sitePreviewUrl.isNotEmpty
                          ? s.sitePreviewUrl
                          : l10n.translate('site_url_not_set')),
              ),
              trailing: const Icon(Icons.copy),
              onTap: () {
                final u = activeRepo?.siteUrl.isNotEmpty == true
                    ? activeRepo!.siteUrl
                    : (s.sitePreviewUrl.isNotEmpty ? s.sitePreviewUrl : '');
                if (u.isEmpty) {
                  widget.onShowToast(l10n.translate('site_url_not_set'));
                  return;
                }
                Clipboard.setData(ClipboardData(text: u));
                widget.onShowToast(l10n.translate('site_url_copied'));
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.install_mobile),
              title: Text(l10n.translate('pwa_guide')),
              subtitle: Text(l10n.translate('pwa_guide_hint')),
              onTap: widget.onShowPwaGuide,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cloud_upload),
              title: Text(l10n.translate('cloudflare_hook')),
              subtitle: Text(
                s.deployHooks.isNotEmpty
                    ? l10n.translate(
                        'deploy_hook_configured',
                        params: {'count': '${s.deployHooks.length}'},
                      )
                    : l10n.translate('deploy_hook_not_configured'),
              ),
              trailing: const Icon(Icons.edit, size: 18),
              onTap: () async {
                final ctrl = TextEditingController(
                  text: s.deployHooks.join('\n'),
                );
                try {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(l10n.translate('deploy_hook_title')),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.translate('deploy_hook_desc'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: ctrl,
                            maxLines: 5,
                            minLines: 2,
                            decoration: InputDecoration(
                              labelText: l10n.translate('deploy_hook_label'),
                              hintText: l10n.translate('deploy_hook_hint'),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(l10n.translate('cancel')),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(l10n.translate('save')),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    final hooks = ctrl.text
                        .split('\n')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList();
                    await widget.onSettingsChanged(
                      widget.settings.copyWith(deployHooks: hooks),
                    );
                    widget.onShowToast(l10n.translate('cloudflare_hook_saved'));
                  }
                } finally {
                  ctrl.dispose();
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.web),
              title: Text(l10n.translate('website_pages')),
              subtitle: Text(l10n.translate('site_editor_pages')),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.onShowSiteEditor,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.palette),
              title: Text(l10n.translate('theme_color')),
              subtitle: Text(l10n.translate('theme_color_hint')),
              trailing: CircleAvatar(
                backgroundColor: Color(s.themeColor),
                radius: 14,
              ),
              onTap: widget.onShowThemeColorPicker,
            ),
          ]),
        ],

        const SizedBox(height: 20),
        // ── 关于 ──
        _section('about', l10n.translate('settings_about'), [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              l10n.translate('hexo_writing_system'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(l10n.translate('local_drafts')),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.translate('about_version')),
            subtitle: Text(_cachedVersion),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.system_update_alt_outlined),
            title: Text(l10n.checkForUpdates),
            subtitle: const Text('从 GitHub 读取最新版本清单'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _checkForUpdates,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.translate('about_author')),
            subtitle: const Text('小子'),
            trailing: const Icon(Icons.person_outline),
            onTap: () => _openUrl('https://www.coolapk.com/u/400522'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('QQ 技术交流群'),
            subtitle: const Text('97126959 · 点击加入'),
            trailing: const Icon(Icons.forum_outlined),
            onTap: () => _openUrl('https://qm.qq.com/q/D8qN5eUDh6'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.favorite_outline),
            title: const Text('鸣谢'),
            subtitle: const Text('QuickDaily · MonkeyCode · MarkText 等开源项目'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showCreditsDialog,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.translate('about_email')),
            subtitle: const Text('1995@139.com'),
            trailing: const Icon(Icons.copy),
            onTap: () {
              Clipboard.setData(const ClipboardData(text: '1995@139.com'));
              widget.onShowToast(l10n.translate('email_copied'));
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.language),
            title: const Text('官网'),
            subtitle: const Text('app.caogenfunan.me'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _openUrl('https://app.caogenfunan.me'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.translate('repository')),
            subtitle: const Text('github.com/caogenfunan123/hexo'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _openUrl('https://github.com/caogenfunan123/hexo'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.help_outline),
            title: Text(l10n.translate('about_help')),
            subtitle: Text(l10n.translate('about_help_hint')),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showHelpDialog,
          ),
          if (kIsWeb || !Platform.isAndroid)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_open_outlined),
              title: Text(l10n.translate('export_dir')),
              subtitle: Text(l10n.translate('export_dir_hint')),
              onTap: () async {
                final dir = await widget.storage.draftsDir();
                Clipboard.setData(ClipboardData(text: dir.path));
                widget.onShowToast(
                  l10n.translate(
                    'export_dir_copied',
                    params: {'path': dir.path},
                  ),
                );
              },
            ),
        ]),
        const SizedBox(height: 24),
      ],
    );
  }

  void _openUrl(String url) async {
    final l10n = AppLocalizations.ofContext(context);
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      Clipboard.setData(ClipboardData(text: url));
      widget.onShowToast(l10n.translate('repo_copied'));
    }
  }

  void _showHelpDialog() {
    final l10n = AppLocalizations.ofContext(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('help_title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _helpSection('help_quick_start', 'help_quick_start_body', l10n),
              const SizedBox(height: 16),
              _helpSection('help_ai', 'help_ai_body', l10n),
              const SizedBox(height: 16),
              _helpSection('help_publish', 'help_publish_body', l10n),
              const SizedBox(height: 16),
              _helpSection('help_issue', 'help_issue_body', l10n),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.translate('confirm')),
          ),
        ],
      ),
    );
  }

  Widget _helpSection(String titleKey, String bodyKey, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate(titleKey),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.translate(bodyKey),
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: Color(0xFF475569),
          ),
        ),
      ],
    );
  }

  /// 鸣谢弹窗：列出本项目深度参考的开源项目（含仓库地址，点击可跳转）
  void _showCreditsDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('鸣谢'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '本项目的架构设计与功能实现深度参考了以下开源项目，在此向各位原作者致敬：',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 12),
                _creditGroup('直接复刻 / 深度参考', [
                  (
                    'QuickDaily',
                    '悬浮速记窗、任务小部件、阅读小部件',
                    'MIT',
                    'https://github.com/agarcabin/QuickDaily',
                  ),
                  (
                    'MonkeyCode',
                    'AI 工具/模型编排、MCP 服务器管理',
                    'AGPL-3.0',
                    'https://github.com/chaitin/MonkeyCode',
                  ),
                  (
                    'MarkText',
                    '沉浸式写作布局、专注模式、打字机滚动',
                    'MIT',
                    'https://github.com/marktext/marktext',
                  ),
                  (
                    'VS Code',
                    'MVVM 架构、命令面板、Markdown 语法着色',
                    'MIT',
                    'https://github.com/microsoft/vscode',
                  ),
                  (
                    'super_editor',
                    'Document / Composer 编辑器架构',
                    'MIT',
                    'https://github.com/superlistapp/super_editor',
                  ),
                  (
                    'Zettlr',
                    'FrontMatter 解析、FSAL 全文搜索架构',
                    'GPL-3.0',
                    'https://github.com/Zettlr/Zettlr',
                  ),
                  (
                    'Markora',
                    'Mermaid + KaTeX 离线渲染架构（仅参考思路，未复制代码）',
                    'GPL-3.0',
                    'https://github.com/AgentBase/Markora',
                  ),
                ]),
                const SizedBox(height: 12),
                _creditGroup('布局与交互参考', [
                  (
                    'PureWriter',
                    '左栏源码 + 右栏实时预览',
                    '资源仓库',
                    'https://github.com/PureWriter/PureWriter',
                  ),
                  ('Notion', '左栏文章平铺内嵌、可折叠列表', '闭源产品', 'https://www.notion.so'),
                  (
                    'Obsidian',
                    'Vault 工作区隔离思想',
                    '闭源产品',
                    'https://github.com/obsidianmd/obsidian-releases',
                  ),
                  (
                    'Cursor',
                    'AI inline edit + 编辑器 diff 交互',
                    '闭源产品',
                    'https://github.com/getcursor/cursor',
                  ),
                ]),
                const SizedBox(height: 12),
                _creditGroup('能力依赖参考', [
                  (
                    'hexo-mobile',
                    'FrontMatter 处理思路（源自 Hexo 生态，仓库已归档）',
                    'MIT',
                    'https://github.com/hexojs/hexo',
                  ),
                  (
                    'flutter_udp_broadcast',
                    'P2P 局域网同步广播（UDP 广播思路参考）',
                    '思路参考',
                    'https://pub.dev/packages?q=udp+broadcast',
                  ),
                  (
                    'ripgrep',
                    '全文检索二进制预编译方案',
                    'Unlicense',
                    'https://github.com/BurntSushi/ripgrep',
                  ),
                  (
                    'GitHub REST API',
                    'Contents API / Git Data API 批量上传',
                    '服务条款',
                    'https://docs.github.com/rest',
                  ),
                  (
                    'flutter_smooth_markdown',
                    '纯原生 Markdown 渲染引擎（Mermaid + KaTeX 支持）',
                    'MIT',
                    'https://github.com/JackCaow/flutter-smooth-markdown',
                  ),
                ]),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _creditGroup(
    String title,
    List<(String, String, String, String)> items,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 6),
        for (final (name, desc, license, url) in items)
          InkWell(
            onTap: () => _openUrl(url),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '• ',
                    style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
                  ),
                  Expanded(
                    child: Text(
                      '$name — $desc\n$url  [$license]',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 设置页所有可折叠分区的 key（默认全折叠）
  static const List<String> _settingsSectionKeys = [
    'basic_info',
    'app_mode',
    'github_token',
    'webdav',
    'draft_backup',
    'global_storage',
    'publish_status',
    'network',
    'editor_theme',
    'image_host',
    'ai_relay',
    'ai_scheduler',
    'quick_note',
    'privacy_encryption',
    'site_pwa',
    'about',
  ];

  /// 草稿加密设置项
  Widget _buildDraftEncryptionTile() {
    return StatefulBuilder(
      builder: (context, setState) {
        final encEnabled = DraftEncryptionService.enabled;
        final unlocked = DraftEncryptionService.unlocked;
        return Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline),
              title: const Text('草稿内容加密'),
              subtitle: Text(
                encEnabled
                    ? (unlocked ? '草稿已加密保存，解锁密码在本机' : '加密已开启，需输入密码解锁')
                    : '对本地草稿内容 AES-256 加密',
              ),
              trailing: Switch(
                value: encEnabled,
                onChanged: (v) => _toggleDraftEncryption(v),
              ),
            ),
            if (encEnabled && unlocked) ...[
              Padding(
                padding: const EdgeInsets.only(left: 40),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.password, size: 18),
                    label: const Text('修改密码'),
                    onPressed: _showChangePasswordDialog,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// 切换草稿加密开关
  Future<void> _toggleDraftEncryption(bool enable) async {
    if (enable) {
      // 开启：首次需设置密码
      await _showSetPasswordDialog();
    } else {
      // 关闭：需验证当前密码
      await _showDisableEncryptionDialog();
    }
    if (mounted) setState(() {});
  }

  /// 设置加密密码对话框
  Future<void> _showSetPasswordDialog() async {
    final pwdCtrl = TextEditingController();
    final confCtrl = TextEditingController();
    final errCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('开启草稿加密'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('开启后草稿内容将加密保存。请设置至少 8 位密码。'),
              const SizedBox(height: 12),
              TextField(
                controller: pwdCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '确认密码'),
              ),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: errCtrl,
                builder: (context, _) => Text(
                  errCtrl.text,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final storage = widget.storage;
                final err = await DraftEncryptionService.setPassword(
                  pwdCtrl.text,
                  confCtrl.text,
                  storage,
                );
                if (err != null) {
                  errCtrl.text = err;
                  if (ctx.mounted) setState(() {});
                  return;
                }
                // 加密现有草稿
                await DraftEncryptionService.encryptExistingDrafts(storage);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('开启'),
            ),
          ],
        ),
      );
      if (ok == true && mounted) {
        widget.onShowToast('草稿加密已开启');
        setState(() {});
      }
    } finally {
      pwdCtrl.dispose();
      confCtrl.dispose();
      errCtrl.dispose();
    }
  }

  /// 解锁 / 输入密码对话框
  Future<bool> _showUnlockDialog() async {
    final pwdCtrl = TextEditingController();
    final errCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('输入密码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pwdCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码'),
              ),
              ListenableBuilder(
                listenable: errCtrl,
                builder: (context, _) => Text(
                  errCtrl.text,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final storage = widget.storage;
                final err = await DraftEncryptionService.verifyPassword(
                  pwdCtrl.text,
                  storage,
                );
                if (err != null) {
                  errCtrl.text = err;
                  if (ctx.mounted) setState(() {});
                  return;
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('确认'),
            ),
          ],
        ),
      );
      return ok == true;
    } finally {
      pwdCtrl.dispose();
      errCtrl.dispose();
    }
  }

  /// 关闭加密对话框
  Future<void> _showDisableEncryptionDialog() async {
    final unlockedBefore = DraftEncryptionService.unlocked;
    // 未解锁先解锁
    if (!unlockedBefore) {
      final ok = await _showUnlockDialog();
      if (!ok) return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关闭草稿加密'),
        content: const Text('关闭后草稿将保存为明文。确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final err = await DraftEncryptionService.disable(widget.storage);
      if (err != null) {
        widget.onShowToast(err);
      } else {
        widget.onShowToast('草稿加密已关闭');
      }
      setState(() {});
    }
  }

  /// 修改密码对话框
  Future<void> _showChangePasswordDialog() async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confCtrl = TextEditingController();
    final errCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('修改密码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '当前密码'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: newCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '新密码'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '确认新密码'),
              ),
              ListenableBuilder(
                listenable: errCtrl,
                builder: (context, _) => Text(
                  errCtrl.text,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final storage = widget.storage;
                final err = await DraftEncryptionService.changePassword(
                  oldCtrl.text,
                  newCtrl.text,
                  confCtrl.text,
                  storage,
                );
                if (err != null) {
                  errCtrl.text = err;
                  if (ctx.mounted) setState(() {});
                  return;
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('确认'),
            ),
          ],
        ),
      );
      if (ok == true && mounted) {
        widget.onShowToast('密码已修改');
      }
    } finally {
      oldCtrl.dispose();
      newCtrl.dispose();
      confCtrl.dispose();
      errCtrl.dispose();
    }
  }

  /// 切换设置分区折叠状态并持久化
  void _toggleSettingsSection(String key) {
    setState(() {
      if (_collapsedSettingsSections.contains(key)) {
        _collapsedSettingsSections.remove(key);
      } else {
        _collapsedSettingsSections.add(key);
      }
    });
    final ns = widget.settings.copyWith(
      ui: widget.settings.ui.copyWith(
        collapsedSettingsSections: _collapsedSettingsSections.toList()..sort(),
      ),
    );
    widget.onSettingsChanged(ns);
  }

  /// 可折叠分区：标题行（点击展开/折叠）+ 内容卡片
  Widget _section(String key, String title, List<Widget> children) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final collapsed = _collapsedSettingsSections.contains(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => _toggleSettingsSection(key),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Icon(
                  collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 18,
                  color: isDark
                      ? Colors.white.withOpacity(0.5)
                      : const Color(0xFF64748B),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: isDark
                          ? Colors.white.withOpacity(0.9)
                          : const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!collapsed) _settingsCard(children),
      ],
    );
  }

  /// 简易模式可加回入口清单（optIn 条目 → 中文名称）
  static const Map<String, String> _optInLabels = {
    'ai_prompt_templates': 'AI 提示词模板',
    'ai_template_chat': 'AI 模板创作',
    'preview': '网站预览',
    'rss': 'RSS 订阅',
    'recycle_bin': '回收站',
    'snippets': '片段素材库',
  };

  /// 简易模式额外入口开关列表
  List<Widget> _buildOptInTiles(AppSettings s) {
    final extras = s.ui.simpleModeExtras.toSet();
    return _optInLabels.entries.map((e) {
      final enabled = extras.contains(e.key);
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: enabled,
        title: Text(e.value, style: const TextStyle(fontSize: 13.5)),
        onChanged: (v) async {
          final next = v ? extras.union({e.key}) : extras.difference({e.key});
          final ns = s.copyWith(
            ui: s.ui.copyWith(simpleModeExtras: next.toList()..sort()),
          );
          await widget.onSettingsChanged(ns);
        },
      );
    }).toList();
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
            ],
          ],
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required String value,
    ValueChanged<String>? onChanged,
    bool obscure = false,
    bool readOnly = false,
    VoidCallback? onTap,
    String? hint,
  }) {
    return TextFormField(
      initialValue: value,
      obscureText: obscure,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onChanged: onChanged,
      onTap: onTap,
    );
  }

  Widget _statusPresetManager(AppSettings s) {
    final l10n = AppLocalizations.ofContext(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...s.statusPresets.asMap().entries.map((entry) {
          final idx = entry.key;
          final status = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: status,
                    decoration: InputDecoration(
                      labelText: l10n
                          .translate('status_label')
                          .replaceAll('{index}', '${idx + 1}'),
                      prefixIcon: const Icon(Icons.label_outline, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (v) async {
                      final updated = List<String>.from(s.statusPresets);
                      updated[idx] = v.trim();
                      await widget.onSettingsChanged(
                        s.copyWith(ui: s.ui.copyWith(statusPresets: updated)),
                      );
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.red),
                  onPressed: s.statusPresets.length > 1
                      ? () async {
                          final updated = List<String>.from(s.statusPresets);
                          updated.removeAt(idx);
                          await widget.onSettingsChanged(
                            s.copyWith(
                              ui: s.ui.copyWith(statusPresets: updated),
                            ),
                          );
                        }
                      : null,
                ),
              ],
            ),
          );
        }),
        TextButton.icon(
          onPressed: () async {
            final updated = List<String>.from(s.statusPresets)..add('');
            await widget.onSettingsChanged(
              s.copyWith(ui: s.ui.copyWith(statusPresets: updated)),
            );
          },
          icon: const Icon(Icons.add, size: 18),
          label: Text(l10n.translate('add_status')),
        ),
      ],
    );
  }
}
