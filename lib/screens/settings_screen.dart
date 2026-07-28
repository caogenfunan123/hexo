import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/ai_profile.dart';
import '../models/app_settings.dart';
import '../models/article_template.dart';
import '../models/github_token_profile.dart';
import '../models/repo_config.dart';
import '../services/github_service.dart';
import '../services/storage_service.dart';
import '../services/webdav_service.dart';
import '../widgets/common_widgets.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final List<RepoConfig> repos;
  final List<ArticleTemplate> templates;
  final GitHubService github;
  final StorageService storage;
  final WebDavService webdavService;
  final Future<void> Function(AppSettings) onSettingsChanged;
  final Future<void> Function(List<RepoConfig>) onReposChanged;
  final Future<void> Function(List<ArticleTemplate>) onTemplatesChanged;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.repos,
    required this.templates,
    required this.github,
    required this.storage,
    required this.webdavService,
    required this.onSettingsChanged,
    required this.onReposChanged,
    required this.onTemplatesChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _section = 0; // 0=令牌, 1=仓库, 2=图床, 3=AI, 4=WebDAV, 5=站点, 6=模板

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      // 左侧分类
      SizedBox(
        width: 150,
        child: ListView(
          children: [
            _catTile(0, Icons.key, 'GitHub 令牌'),
            _catTile(1, Icons.storage, '仓库管理'),
            _catTile(2, Icons.image, '图床设置'),
            _catTile(3, Icons.psychology, 'AI 配置'),
            _catTile(4, Icons.cloud, 'WebDAV'),
            _catTile(5, Icons.language, '站点信息'),
            _catTile(6, Icons.file_copy, '写作模板'),
          ],
        ),
      ),
      const VerticalDivider(width: 1),
      Expanded(child: _buildSection()),
    ]);
  }

  Widget _catTile(int idx, IconData icon, String label) {
    return ListTile(
      leading: Icon(icon, size: 20, color: _section == idx ? Theme.of(context).colorScheme.primary : Colors.grey),
      title: Text(label, style: TextStyle(fontSize: 13, fontWeight: _section == idx ? FontWeight.w600 : FontWeight.normal)),
      selected: _section == idx,
      onTap: () => setState(() => _section = idx),
    );
  }

  Widget _buildSection() {
    switch (_section) {
      case 0: return _buildTokenSection();
      case 1: return _buildRepoSection();
      case 2: return _buildImageBedSection();
      case 3: return _buildAiSection();
      case 4: return _buildWebdavSection();
      case 5: return _buildSiteSection();
      case 6: return _buildTemplateSection();
      default: return const SizedBox();
    }
  }

  // ===== Token 管理 =====
  Widget _buildTokenSection() {
    final tokens = widget.settings.githubTokens;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionTitle(title: 'GitHub 登录令牌'),
        const SizedBox(height: 8),
        if (tokens.isEmpty)
          EmptyState(icon: Icons.key_outlined, title: '还没有保存的 Token', subtitle: '添加 Token 后可复用到多个仓库'),
        ...tokens.map((t) => Card(
          child: ListTile(
            leading: const Icon(Icons.vpn_key_outlined),
            title: Text(t.displayLabel),
            subtitle: Text(t.maskedToken, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'active') await _activateToken(t.id);
                else if (v == 'verify') await _verifyToken(t);
                else if (v == 'delete') await _deleteToken(t);
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'active', child: Text(t.id == widget.settings.activeGithubTokenId ? '✓ 当前登录' : '设为当前登录')),
                PopupMenuItem(value: 'verify', child: const Text('验证有效性')),
                PopupMenuItem(value: 'delete', child: const Text('删除', style: TextStyle(color: Colors.red))),
              ],
            ),
          ),
        )),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _addToken, icon: const Icon(Icons.add), label: const Text('添加 Token')),
      ],
    );
  }

  Future<void> _addToken() async {
    final tokenCtrl = TextEditingController();
    final nameCtrl = TextEditingController(text: 'GitHub Token');
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('添加 GitHub Token'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '名称')),
        const SizedBox(height: 8),
        TextField(controller: tokenCtrl, decoration: const InputDecoration(labelText: 'Token', hintText: 'ghp_... 或 github_pat_...'), obscureText: true),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
      ],
    ));
    if (ok != true || tokenCtrl.text.trim().isEmpty) return;
    final t = GithubTokenProfile(id: 'gh_${DateTime.now().millisecondsSinceEpoch}', name: nameCtrl.text.trim(), token: tokenCtrl.text.trim());
    await widget.onSettingsChanged(widget.settings.copyWith(
      githubTokens: [...widget.settings.githubTokens, t],
      activeGithubTokenId: t.id,
    ));
    showToast(context, '已添加');
  }

  Future<void> _activateToken(String id) async {
    await widget.onSettingsChanged(widget.settings.copyWith(activeGithubTokenId: id));
    showToast(context, '已切换');
  }

  Future<void> _verifyToken(GithubTokenProfile t) async {
    try {
      final user = await widget.github.getUser(t.token);
      final login = user['login']?.toString() ?? '';
      showToast(context, login.isEmpty ? 'Token 有效' : '✅ 有效 · @$login');
    } catch (e) {
      showToast(context, '❌ 校验失败');
    }
  }

  Future<void> _deleteToken(GithubTokenProfile t) async {
    final ok = await showConfirm(context, title: '删除 Token', message: '确认删除「${t.displayLabel}」？', confirmColor: Colors.red);
    if (!ok) return;
    final tokens = widget.settings.githubTokens.where((e) => e.id != t.id).toList();
    await widget.onSettingsChanged(widget.settings.copyWith(
      githubTokens: tokens,
      activeGithubTokenId: tokens.isNotEmpty ? tokens.first.id : '',
    ));
  }

  // ===== 仓库管理 =====
  Widget _buildRepoSection() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionTitle(title: '仓库管理'),
        const SizedBox(height: 8),
        if (widget.repos.isEmpty)
          EmptyState(icon: Icons.storage_outlined, title: '还没有仓库', subtitle: '添加 GitHub 仓库即可发布文章'),
        ...widget.repos.map((r) => Card(
          child: ListTile(
            leading: Icon(r.isDefault ? Icons.star : Icons.storage_outlined, color: r.isDefault ? Colors.amber : null),
            title: Text(r.name),
            subtitle: Text('${r.fullName} · ${r.postsPath}'),
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'edit') await _editRepo(r);
                else if (v == 'default') {
                  final updated = widget.repos.map((e) => e.copyWith(isDefault: e.id == r.id)).toList();
                  await widget.onReposChanged(updated);
                }
                else if (v == 'delete') await _deleteRepo(r);
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: const Text('编辑')),
                PopupMenuItem(value: 'default', child: Text(r.isDefault ? '✓ 默认仓库' : '设为默认')),
                PopupMenuItem(value: 'delete', child: const Text('删除', style: TextStyle(color: Colors.red))),
              ],
            ),
          ),
        )),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _addRepo, icon: const Icon(Icons.add), label: const Text('添加仓库')),
      ],
    );
  }

  Future<void> _addRepo() async {
    final ctrls = {
      'name': TextEditingController(),
      'owner': TextEditingController(),
      'repo': TextEditingController(),
      'branch': TextEditingController(text: 'main'),
      'postsPath': TextEditingController(text: 'source/_posts'),
      'siteUrl': TextEditingController(),
    };
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('添加仓库'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: ctrls['name'], decoration: const InputDecoration(labelText: '名称')),
        TextField(controller: ctrls['owner'], decoration: const InputDecoration(labelText: 'Owner')),
        TextField(controller: ctrls['repo'], decoration: const InputDecoration(labelText: '仓库名')),
        TextField(controller: ctrls['branch'], decoration: const InputDecoration(labelText: '分支')),
        TextField(controller: ctrls['postsPath'], decoration: const InputDecoration(labelText: '文章路径')),
        TextField(controller: ctrls['siteUrl'], decoration: const InputDecoration(labelText: '站点 URL')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('添加')),
      ],
    ));
    if (ok != true) return;
    final r = RepoConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: ctrls['name']!.text,
      owner: ctrls['owner']!.text,
      repo: ctrls['repo']!.text,
      branch: ctrls['branch']!.text,
      postsPath: ctrls['postsPath']!.text,
      siteUrl: ctrls['siteUrl']!.text,
      token: widget.settings.effectiveGithubToken,
      isDefault: widget.repos.isEmpty,
    );
    final updated = [...widget.repos, r];
    await widget.onReposChanged(updated);
    await widget.onSettingsChanged(widget.settings.copyWith(activeRepoId: r.id));
    showToast(context, '已添加');
  }

  Future<void> _editRepo(RepoConfig r) async {
    final ctrls = {
      'name': TextEditingController(text: r.name),
      'owner': TextEditingController(text: r.owner),
      'repo': TextEditingController(text: r.repo),
      'branch': TextEditingController(text: r.branch),
      'postsPath': TextEditingController(text: r.postsPath),
      'siteUrl': TextEditingController(text: r.siteUrl),
    };
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('编辑仓库'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: ctrls['name'], decoration: const InputDecoration(labelText: '名称')),
        TextField(controller: ctrls['owner'], decoration: const InputDecoration(labelText: 'Owner')),
        TextField(controller: ctrls['repo'], decoration: const InputDecoration(labelText: '仓库名')),
        TextField(controller: ctrls['branch'], decoration: const InputDecoration(labelText: '分支')),
        TextField(controller: ctrls['postsPath'], decoration: const InputDecoration(labelText: '文章路径')),
        TextField(controller: ctrls['siteUrl'], decoration: const InputDecoration(labelText: '站点 URL')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
      ],
    ));
    if (ok != true) return;
    final updated = widget.repos.map((e) => e.id == r.id ? e.copyWith(
      name: ctrls['name']!.text, owner: ctrls['owner']!.text, repo: ctrls['repo']!.text,
      branch: ctrls['branch']!.text, postsPath: ctrls['postsPath']!.text, siteUrl: ctrls['siteUrl']!.text,
    ) : e).toList();
    await widget.onReposChanged(updated);
  }

  Future<void> _deleteRepo(RepoConfig r) async {
    final ok = await showConfirm(context, title: '删除仓库', message: '确认删除「${r.name}」？', confirmColor: Colors.red);
    if (!ok) return;
    final updated = widget.repos.where((e) => e.id != r.id).toList();
    await widget.onReposChanged(updated);
  }

  // ===== 其他设置页简化版 =====
  Widget _buildImageBedSection() => _simpleTextFieldSection(
    title: '图床设置',
    fields: { 'Owner': widget.settings.imageBedOwner, 'Repo': widget.settings.imageBedRepo, '分支': widget.settings.imageBedBranch, '路径': widget.settings.imageBedPath, 'CDN': widget.settings.imageBedCdn },
    onSave: (vals) => widget.onSettingsChanged(widget.settings.copyWith(imageBedOwner: vals[0], imageBedRepo: vals[1], imageBedBranch: vals[2], imageBedPath: vals[3], imageBedCdn: vals[4])),
  );

  Widget _buildAiSection() => _simpleTextFieldSection(
    title: 'AI 配置',
    fields: { 'API Key': widget.settings.aiApiKey, 'Base URL': widget.settings.aiBaseUrl, 'Model': widget.settings.aiModel },
    onSave: (vals) => widget.onSettingsChanged(widget.settings.copyWith(aiApiKey: vals[0], aiBaseUrl: vals[1], aiModel: vals[2])),
  );

  Widget _buildWebdavSection() => _simpleTextFieldSection(
    title: 'WebDAV 设置',
    fields: { 'URL': widget.settings.webdavUrl, '用户名': widget.settings.webdavUsername, '密码': widget.settings.webdavPassword, '文件夹': widget.settings.webdavFolder },
    onSave: (vals) => widget.onSettingsChanged(widget.settings.copyWith(webdavUrl: vals[0], webdavUsername: vals[1], webdavPassword: vals[2], webdavFolder: vals[3])),
  );

  Widget _buildSiteSection() => _simpleTextFieldSection(
    title: '站点信息',
    fields: { '站点名': widget.settings.siteName, '简介': widget.settings.siteBio, '首页': widget.settings.siteHome, '友链': widget.settings.siteGuestbook, '作品': widget.settings.siteWorks, 'Cloudflare Hook': widget.settings.cloudflareDeployHook },
    onSave: (vals) => widget.onSettingsChanged(widget.settings.copyWith(siteName: vals[0], siteBio: vals[1], siteHome: vals[2], siteGuestbook: vals[3], siteWorks: vals[4], cloudflareDeployHook: vals[5])),
  );

  Widget _buildTemplateSection() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionTitle(title: '写作模板'),
        const SizedBox(height: 8),
        ...widget.templates.map((t) => Card(
          child: ListTile(
            leading: const Icon(Icons.article_outlined),
            title: Text(t.name),
            subtitle: Text(t.description, maxLines: 1),
            trailing: IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: () async {
              final updated = widget.templates.where((e) => e.id != t.id).toList();
              await widget.onTemplatesChanged(updated);
            }),
          ),
        )),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _addTemplate, icon: const Icon(Icons.add), label: const Text('新建模板')),
      ],
    );
  }

  Future<void> _addTemplate() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('新建模板'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '模板名称')),
        TextField(controller: descCtrl, decoration: const InputDecoration(labelText: '描述')),
        TextField(controller: contentCtrl, maxLines: 5, decoration: const InputDecoration(labelText: 'Markdown 内容')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
      ],
    ));
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    final t = ArticleTemplate(id: DateTime.now().millisecondsSinceEpoch.toString(), name: nameCtrl.text.trim(), description: descCtrl.text.trim(), content: contentCtrl.text, createdAt: DateTime.now());
    await widget.onTemplatesChanged([...widget.templates, t]);
    showToast(context, '模板已创建');
  }

  Widget _simpleTextFieldSection({
    required String title,
    required Map<String, String> fields,
    required void Function(List<String>) onSave,
  }) {
    final ctrls = fields.keys.map((k) => TextEditingController(text: fields[k] ?? '')).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionTitle(title: title),
        const SizedBox(height: 8),
        ...List.generate(fields.length, (i) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(controller: ctrls[i], decoration: InputDecoration(labelText: fields.keys.elementAt(i))),
        )),
        const SizedBox(height: 12),
        FilledButton(onPressed: () => onSave(ctrls.map((c) => c.text).toList()), child: const Text('保存')),
      ],
    );
  }
}
