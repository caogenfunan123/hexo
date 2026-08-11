import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../models/app_settings.dart';
import '../models/repo_config.dart';
import '../services/github_service.dart';
import '../services/storage_service.dart';
import '../services/webdav_service.dart';
import '../l10n/app_localizations.dart';

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

  /// 选择全局存储根目录
  ///
  /// Android 使用原生 SAF 目录选择；SAF 返回的 content:// tree URI 无法被
  /// dart:io 直接读写，此时回退到应用外部专属存储目录（真实可写路径）。
  Future<void> _pickStorageRoot() async {
    final l10n = AppLocalizations.ofContext(context);
    var path = '';
    try {
      const channel = MethodChannel('hexo/native');
      final picked = await channel.invokeMethod<String>('pickDirectory');
      if (picked != null && picked.isNotEmpty) {
        if (picked.startsWith('/')) {
          path = picked;
        } else if (picked.startsWith('content://') ||
            picked.startsWith('tree://')) {
          // SAF tree URI 不可直接用于 dart:io，回退应用外部存储目录
          final external = await channel.invokeMethod<String>(
            'getExternalFilesDir',
          );
          if (external != null && external.isNotEmpty) path = external;
        }
      }
    } catch (_) {
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

  /// 重置为默认存储根目录
  Future<void> _resetStorageRoot() async {
    final l10n = AppLocalizations.ofContext(context);
    final ns = widget.settings.copyWith(storageRootDir: '');
    await widget.onSettingsChanged(ns);
    widget.onShowToast(l10n.translate('global_storage_reset'));
  }

  /// 一键迁移旧目录全部历史文件到当前全局根目录
  Future<void> _migrateStorageRoot(String oldRoot) async {
    final l10n = AppLocalizations.ofContext(context);
    final count = await widget.storage.migrateFrom(oldRoot);
    widget.onShowToast(
      l10n.translate('global_storage_migrated', params: {'count': '$count'}),
    );
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
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
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
        _sectionTitle(l10n.translate('settings_basic_info')),
        const SizedBox(height: 8),
        _settingsCard([
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
        // ── GitHub 登录令牌 ──
        _sectionTitle(l10n.translate('settings_github_token')),
        const SizedBox(height: 8),
        _settingsCard([
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
        _sectionTitle(l10n.translate('settings_webdav')),
        const SizedBox(height: 8),
        _settingsCard([
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
        _sectionTitle(l10n.translate('settings_draft_backup')),
        const SizedBox(height: 8),
        _settingsCard([
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
        // ── 全局文件存储目录 ──
        _sectionTitle(l10n.translate('settings_global_storage')),
        const SizedBox(height: 8),
        _settingsCard([
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

        const SizedBox(height: 20),
        // ── 发布状态预设 ──
        _sectionTitle(l10n.translate('settings_publish_status')),
        const SizedBox(height: 8),
        _settingsCard([
          _statusPresetManager(s),
          const Divider(height: 24),
          Text(
            l10n.translate('status_preset_hint'),
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ]),

        const SizedBox(height: 20),
        // ── 网络超时设置 ──
        _sectionTitle(l10n.translate('settings_network')),
        const SizedBox(height: 8),
        _settingsCard([
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
        _sectionTitle('写作界面主题'),
        const SizedBox(height: 8),
        _settingsCard([
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
        _sectionTitle(l10n.translate('settings_image_host')),
        const SizedBox(height: 8),
        _settingsCard([
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
        _sectionTitle(l10n.translate('settings_ai_relay')),
        const SizedBox(height: 8),
        _settingsCard([
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
        _sectionTitle(l10n.translate('settings_ai_scheduler')),
        const SizedBox(height: 8),
        _settingsCard([
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
        // ── 站点与 PWA ──
        _sectionTitle(l10n.translate('settings_site_pwa')),
        const SizedBox(height: 8),
        _settingsCard([
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
              s.cloudflareDeployHook.isNotEmpty
                  ? l10n.translate('deploy_hook_configured')
                  : l10n.translate('deploy_hook_not_configured'),
            ),
            trailing: const Icon(Icons.edit, size: 18),
            onTap: () async {
              final ctrl = TextEditingController(text: s.cloudflareDeployHook);
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
                await widget.onSettingsChanged(
                  widget.settings.copyWith(
                    cloudflareDeployHook: ctrl.text.trim(),
                  ),
                );
                widget.onShowToast(l10n.translate('cloudflare_hook_saved'));
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

        const SizedBox(height: 20),
        // ── 关于 ──
        _sectionTitle(l10n.translate('settings_about')),
        const SizedBox(height: 8),
        _settingsCard([
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.translate('hexo_writing_system')),
            subtitle: Text(l10n.translate('local_drafts')),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.translate('about_author')),
            subtitle: Text(l10n.translate('about_developer')),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.translate('about_version')),
            subtitle: const Text('1.0.1'),
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
            title: Text(l10n.translate('repository')),
            subtitle: const Text('github.com/caogenfunan123/xiamend'),
            trailing: const Icon(Icons.copy),
            onTap: () {
              Clipboard.setData(
                const ClipboardData(
                  text: 'https://github.com/caogenfunan123/xiamend',
                ),
              );
              widget.onShowToast(l10n.translate('repo_copied'));
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_open_outlined),
            title: Text(l10n.translate('export_dir')),
            subtitle: Text(l10n.translate('export_dir_hint')),
            onTap: () async {
              final dir = await widget.storage.draftsDir();
              Clipboard.setData(ClipboardData(text: dir.path));
              widget.onShowToast(
                l10n.translate('export_dir_copied', params: {'path': dir.path}),
              );
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
