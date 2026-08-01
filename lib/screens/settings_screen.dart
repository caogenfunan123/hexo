import 'package:flutter/material.dart';
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

  const SettingsScreen({super.key, required this.settings, required this.repos, required this.github, required this.storage, required this.webdavService, required this.onSettingsChanged, required this.onReposChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _siteNameCtrl;
  late TextEditingController _siteBioCtrl;
  late TextEditingController _tokenCtrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _siteNameCtrl = TextEditingController(text: widget.settings.siteName);
    _siteBioCtrl = TextEditingController(text: widget.settings.siteBio);
    _tokenCtrl = TextEditingController(text: widget.settings.effectiveGithubToken);
  }

  @override
  void dispose() {
    _siteNameCtrl.dispose();
    _siteBioCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final s = widget.settings.copyWith(
      siteName: _siteNameCtrl.text.trim(),
      siteBio: _siteBioCtrl.text.trim(),
      defaultToken: _tokenCtrl.text.trim(),
    );
    await widget.onSettingsChanged(s);
    _showToast('设置已保存');
  }

  Future<void> _verifyToken() async {
    setState(() => _busy = true);
    try {
      final ok = await widget.github.verifyToken(_tokenCtrl.text.trim());
      _showToast(ok ? 'Token 验证成功' : 'Token 验证失败');
    } catch (e) {
      _showToast('验证失败: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('基本信息'),
        const SizedBox(height: 8),
        Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          child: Column(children: [
            _settingField('网站名称', _siteNameCtrl, Icons.language),
            const Divider(height: 1, indent: 14, endIndent: 14),
            _settingField('网站简介', _siteBioCtrl, Icons.info_outline),
          ]),
        ),
        const SizedBox(height: 20),
        _sectionTitle('GitHub Token'),
        const SizedBox(height: 8),
        Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(children: [
                const Icon(Icons.vpn_key_outlined, size: 20, color: Color(0xFF64748B)),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _tokenCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(border: InputBorder.none, enabledBorder: InputBorder.none, hintText: '输入 GitHub Token', isDense: true),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                TextButton(onPressed: _busy ? null : _verifyToken, child: const Text('验证', style: TextStyle(fontSize: 13))),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        _sectionTitle('仓库列表'),
        const SizedBox(height: 8),
        ...widget.repos.map((r) => Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: const Color(0xFF0EA5E9).withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.storage_outlined, size: 20, color: Color(0xFF0EA5E9)),
            ),
            title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text(r.fullName, style: const TextStyle(fontSize: 12)),
            trailing: r.isDefault ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFF0EA5E9).withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
              child: const Text('默认', style: TextStyle(fontSize: 11, color: Color(0xFF0EA5E9))),
            ) : null,
          ),
        )),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saveSettings,
          icon: const Icon(Icons.save_outlined, size: 18),
          label: const Text('保存设置'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)));
  }

  Widget _settingField(String label, TextEditingController ctrl, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Row(children: [
        Icon(icon, size: 20, color: const Color(0xFF64748B)),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: ctrl,
            decoration: InputDecoration(border: InputBorder.none, enabledBorder: InputBorder.none, labelText: label, isDense: true),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ]),
    );
  }
}