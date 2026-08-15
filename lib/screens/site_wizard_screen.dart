import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../models/git_provider.dart';
import '../models/repo_config.dart';
import '../models/wizard_models.dart';
import '../services/git_providers.dart';
import '../services/site_wizard_service.dart';
import '../services/storage_service.dart';
import '../services/framework_build_map.dart';
import '../services/rollback_manager.dart';

/// 一键建站降级表单向导（AI 对话为主模式，此表单为显式降级路径）
///
/// 分步：模式选择 → 账号连接 → 站点信息 → 确认/执行 → 完成
class SiteWizardScreen extends StatefulWidget {
  final AppSettings settings;
  final List<RepoConfig> repos;
  final Future<void> Function(AppSettings) onSettingsChanged;
  final Future<void> Function(List<RepoConfig>) onReposChanged;

  const SiteWizardScreen({
    super.key,
    required this.settings,
    required this.repos,
    required this.onSettingsChanged,
    required this.onReposChanged,
  });

  @override
  State<SiteWizardScreen> createState() => _SiteWizardScreenState();
}

class _SiteWizardScreenState extends State<SiteWizardScreen> {
  int _step = 0;
  bool _running = false;
  bool _isCancelConfirmed = false;
  WizardResult? _result;
  String? _error;
  String? _cancelHint;

  // 模式
  WizardMode _mode = WizardMode.one;
  GitProviderType _gitProvider = GitProviderType.github;

  // 账号连接
  final _gitTokenCtrl = TextEditingController();
  final _cfTokenCtrl = TextEditingController();
  final _cfAccountCtrl = TextEditingController();
  bool _tokenVerified = false;

  // 站点信息
  final _repoNameCtrl = TextEditingController();
  final _siteTitleCtrl = TextEditingController();
  bool _repoPrivate = true;
  bool _skipWelcomePost = false;
  String _frameworkId = 'hexo';

  final SiteWizardService _service = SiteWizardService();

  bool get _isModeTwo => _mode == WizardMode.two;

  @override
  void dispose() {
    _gitTokenCtrl.dispose();
    _cfTokenCtrl.dispose();
    _cfAccountCtrl.dispose();
    _repoNameCtrl.dispose();
    _siteTitleCtrl.dispose();
    super.dispose();
  }

  Future<void> _verifyToken() async {
    final token = _gitTokenCtrl.text.trim();
    if (token.isEmpty) {
      _showError('请输入 Git 访问令牌');
      return;
    }
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final missing = _gitProvider == GitProviderType.gitlab
          ? (await GitLabProvider().verifyScopes(token))['missing'] as List
          : (await GitHubProvider().verifyScopes(token))['missing'] as List;
      setState(() {
        _tokenVerified = missing.isEmpty;
        _error = missing.isEmpty
            ? null
            : '令牌缺少必要权限：${missing.join('、')}，请重新生成后重试';
      });
      if (missing.isNotEmpty) return;
      if (_isModeTwo) {
        final cf = _cfTokenCtrl.text.trim();
        final acc = _cfAccountCtrl.text.trim();
        if (cf.isEmpty || acc.isEmpty) {
          setState(() => _error = '模式二还需填写 Cloudflare API Token 与账号 ID');
          return;
        }
      }
      setState(() {
        _step = 2;
        _running = false;
      });
    } catch (e) {
      setState(() {
        _running = false;
        _error = '令牌校验失败：$e';
      });
    }
  }

  static final RegExp _repoNameRe =
      RegExp(r'^[a-z0-9][a-z0-9-_]{0,98}[a-z0-9]$|^[a-z0-9]$');

  /// 仓库名校验：小写字母/数字/连字符/下划线，不以连字符首尾，1-100 字符
  bool _validateRepoName(String name) {
    if (name.isEmpty || name.length > 100) return false;
    return _repoNameRe.hasMatch(name);
  }

  bool get _formValid =>
      _validateRepoName(_repoNameCtrl.text.trim()) &&
      _siteTitleCtrl.text.trim().isNotEmpty;

  Future<void> _run() async {
    if (!_validateRepoName(_repoNameCtrl.text.trim())) {
      _showError('仓库名仅支持小写字母/数字/连字符/下划线，不以连字符首尾，长度 1-100');
      return;
    }
    if (_siteTitleCtrl.text.trim().isEmpty) {
      _showError('请填写站点标题');
      return;
    }
    setState(() {
      _running = true;
      _error = null;
    });
    final req = WizardRequest(
      mode: _mode,
      gitProvider: _gitProvider,
      gitToken: _gitTokenCtrl.text.trim(),
      cfApiToken: _cfTokenCtrl.text.trim(),
      cfAccountId: _cfAccountCtrl.text.trim(),
      repoName: _repoNameCtrl.text.trim(),
      repoPrivate: _repoPrivate,
      frameworkId: _frameworkId,
      siteTitle: _siteTitleCtrl.text.trim(),
      skipWelcomePost: _skipWelcomePost,
    );
    try {
      final result = await _service.run(req);
      if (!mounted) return;
      // 持久化：模式二保存 CF 凭据 + 站点注册到 repos
      if (_isModeTwo && req.cfApiToken.isNotEmpty) {
        final updated = widget.settings.copyWith(
          cfApiToken: req.cfApiToken,
          cfAccountId: req.cfAccountId,
        );
        await widget.onSettingsChanged(updated);
      }
      final repos = List<RepoConfig>.from(widget.repos);
      final exists = repos.any((r) => r.fullName == result.repoConfig.fullName);
      if (!exists) {
        repos.add(result.repoConfig);
        await widget.onReposChanged(repos);
      }
      setState(() {
        _result = result;
        _running = false;
        _step = 4;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = '建站失败：$e';
      });
    }
  }

  void _showError(String msg) {
    setState(() => _error = msg);
  }

  Future<void> _handleCancel() async {
    // 未创建任何资源时直接退出
    if (_step < 3) {
      Navigator.of(context).pop();
      return;
    }
    // 模式二：提示保留仓库，返回站点管理，不触发回滚
    if (_isModeTwo) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('退出向导'),
          content: const Text('仓库将保留，可稍后在站点管理中继续。确定退出吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('继续'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('退出'),
            ),
          ],
        ),
      );
      if (ok == true && mounted) Navigator.of(context).pop();
      return;
    }
    // 模式一：确认是否清理已创建资源
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认取消'),
        content: const Text('将清理本次已创建的资源（仓库、Pages 设置）。是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('留在向导'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清理并退出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _isCancelConfirmed = true;
      _running = true;
      _error = null;
    });
    // 组装回滚计划（本表单不持有执行中的 RollbackPlan，提示资源保留交给站点管理）
    // 简化：表单场景尚未投入网页操作，触发 RollbackManager 逆序清理
    try {
      final plan = RollbackPlan(
        repoOwner: '',
        repoName: _repoNameCtrl.text.trim(),
        gitProvider: _gitProvider,
        gitToken: _gitTokenCtrl.text.trim(),
        cfApiToken: _cfTokenCtrl.text.trim(),
        cfAccountId: _cfAccountCtrl.text.trim(),
        gitRepoCreated: _step >= 3,
        userInvestedInWeb: false,
      );
      final failures = await RollbackManager().rollback(plan);
      if (!mounted) return;
      setState(() {
        _running = false;
        _isCancelConfirmed = true;
        _cancelHint = failures.isEmpty ? null : '部分资源清理失败：${failures.join('、')}';
      });
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _cancelHint = '清理失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _isCancelConfirmed,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleCancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('一键建站'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _running ? null : _handleCancel,
          ),
        ),
        body: _result != null ? _buildResult() : _buildStepper(),
      ),
    );
  }

  Widget _buildStepper() {
    final steps = <Widget>[
      _buildModeStep(),
      _buildAccountStep(),
      _buildInfoStep(),
      _buildConfirmStep(),
    ];
    return Stepper(
      currentStep: _step.clamp(0, 3),
      onStepContinue: _step == 0
          ? () => setState(() => _step = 1)
          : _step == 1
              ? _verifyToken
              : _step == 2
                  ? () => setState(() => _step = 3)
                  : _run,
      onStepCancel: _handleCancel,
      controlsBuilder: (context, details) {
        return Row(
          children: [
            FilledButton(
              onPressed: _running ? null : details.onStepContinue,
              child: Text(_step == 3 ? '开始建站' : '下一步'),
            ),
            const SizedBox(width: 12),
            if (_step > 0)
              TextButton(
                onPressed: _running ? null : details.onStepCancel,
                child: const Text('上一步'),
              ),
          ],
        );
      },
      steps: [
        Step(
          title: const Text('选择模式'),
          isActive: _step >= 0,
          state: _step == 0 ? StepState.editing : StepState.indexed,
          content: steps[0],
        ),
        Step(
          title: const Text('账号连接'),
          isActive: _step >= 1,
          state: _step == 1 ? StepState.editing : StepState.indexed,
          content: steps[1],
        ),
        Step(
          title: const Text('站点信息'),
          isActive: _step >= 2,
          state: _step == 2 ? StepState.editing : StepState.indexed,
          content: steps[2],
        ),
        Step(
          title: const Text('确认并建站'),
          isActive: _step >= 3,
          state: _step == 3 ? StepState.editing : StepState.indexed,
          content: steps[3],
        ),
      ],
    );
  }

  Widget _buildModeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RadioListTile<WizardMode>(
          title: const Text('模式一：平台 Pages（GitHub / GitLab）'),
          subtitle: const Text('仓库内 CI 自动构建，构建消耗平台分钟数'),
          value: WizardMode.one,
          groupValue: _mode,
          onChanged: (v) => setState(() => _mode = v!),
        ),
        RadioListTile<WizardMode>(
          title: const Text('模式二：Cloudflare Pages'),
          subtitle: const Text('需在 Cloudflare 控制台连接 Git 并创建 Pages 项目'),
          value: WizardMode.two,
          groupValue: _mode,
          onChanged: (v) => setState(() => _mode = v!),
        ),
        if (_isModeTwo) ...[
          const Divider(height: 24),
          const Text('模式二引导：', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            '1. 在 Cloudflare 控制台 → Pages → Projects → Create project\n'
            '2. 选择 Connect to Git，授权访问你的仓库\n'
            '3. 按框架要求选择构建命令与输出目录，点击 Save 开始首次构建\n'
            '4. 回到本向导继续填写下方信息，App 会自动检测并衔接部署',
            style: TextStyle(color: Colors.black54, height: 1.6),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<GitProviderType>(
            initialValue: _gitProvider,
            decoration: const InputDecoration(labelText: 'Git 托管平台'),
            items: const [
              DropdownMenuItem(value: GitProviderType.github, child: Text('GitHub')),
              DropdownMenuItem(value: GitProviderType.gitlab, child: Text('GitLab')),
            ],
            onChanged: (v) => setState(() => _gitProvider = v ?? _gitProvider),
          ),
        ] else
          DropdownButtonFormField<GitProviderType>(
            initialValue: _gitProvider,
            decoration: const InputDecoration(labelText: 'Git 托管平台'),
            items: const [
              DropdownMenuItem(value: GitProviderType.github, child: Text('GitHub')),
              DropdownMenuItem(value: GitProviderType.gitlab, child: Text('GitLab')),
            ],
            onChanged: (v) => setState(() => _gitProvider = v ?? _gitProvider),
          ),
      ],
    );
  }

  Widget _buildAccountStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _gitTokenCtrl,
          obscureText: true,
          decoration: InputDecoration(
            labelText: _gitProvider == GitProviderType.github
                ? 'GitHub Personal Access Token'
                : 'GitLab Personal Access Token',
            hintText: _gitProvider == GitProviderType.github
                ? '需含 repo + workflow scope'
                : '需含 api scope',
            prefixIcon: const Icon(Icons.key_outlined),
          ),
        ),
        const SizedBox(height: 8),
        if (_tokenVerified)
          const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 18),
              SizedBox(width: 6),
              Text('令牌已通过 scope 校验', style: TextStyle(color: Colors.green)),
            ],
          ),
        if (_isModeTwo) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _cfTokenCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Cloudflare API Token',
              hintText: '需 pages:edit 权限',
              prefixIcon: Icon(Icons.cloud_outlined),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _cfAccountCtrl,
            decoration: const InputDecoration(
              labelText: 'Cloudflare Account ID',
              prefixIcon: Icon(Icons.numbers),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
        ],
      ],
    );
  }

  Widget _buildInfoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _repoNameCtrl,
          onChanged: (_) => setState(() {}),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp('[a-z0-9-_]'),
            ),
            LengthLimitingTextInputFormatter(100),
          ],
          decoration: InputDecoration(
            labelText: '仓库名（同时作为站点项目名）',
            hintText: 'my-blog',
            prefixIcon: const Icon(Icons.folder_outlined),
            errorText: _repoNameCtrl.text.isEmpty
                ? null
                : (_validateRepoName(_repoNameCtrl.text.trim())
                    ? null
                    : '小写字母/数字/连字符/下划线，不以连字符首尾'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _siteTitleCtrl,
          decoration: const InputDecoration(
            labelText: '站点标题',
            hintText: '我的博客',
            prefixIcon: Icon(Icons.title),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _frameworkId,
          decoration: const InputDecoration(labelText: '博客框架'),
          items: [
            for (final id in FrameworkBuildMap.knownFrameworkIds)
              DropdownMenuItem(value: id, child: Text(id)),
          ],
          onChanged: (v) => setState(() => _frameworkId = v ?? _frameworkId),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('仓库设为私有'),
          subtitle: _gitProvider == GitProviderType.github
              ? const Text('注意：GitHub 免费账号私有仓库无法启用 Pages')
              : null,
          value: _repoPrivate,
          onChanged: (v) => setState(() => _repoPrivate = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('生成欢迎文章'),
          value: !_skipWelcomePost,
          onChanged: (v) => setState(() => _skipWelcomePost = !v),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
        ],
      ],
    );
  }

  Widget _buildConfirmStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('请确认以下信息：', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _kv('模式', _isModeTwo ? 'Cloudflare Pages' : '平台 Pages'),
        _kv('平台', _gitProvider.name),
        _kv('仓库名', _repoNameCtrl.text.trim()),
        _kv('站点标题', _siteTitleCtrl.text.trim()),
        _kv('框架', _frameworkId),
        _kv('可见性', _repoPrivate ? '私有' : '公开'),
        _kv('欢迎文章', _skipWelcomePost ? '跳过' : '生成'),
        if (_isModeTwo) ...[
          const SizedBox(height: 8),
          const Divider(),
          const Text(
            '模式二提醒：请在 Cloudflare 控制台完成「连接 Git → 创建 Pages 项目」后，'
            '再点击下方「开始建站」。App 会自动检测项目并衔接部署。',
            style: TextStyle(color: Colors.orange, fontSize: 13),
          ),
        ],
        if (_running) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 8),
          const Center(
            child: Text('正在建站，首次构建最长等待 10 分钟…',
                style: TextStyle(fontSize: 13)),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
        ],
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(k, style: const TextStyle(color: Colors.black54)),
          ),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final r = _result!;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 64),
        const SizedBox(height: 16),
        const Center(
          child: Text('建站完成', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 24),
        _kv('仓库', r.repoConfig.repo),
        _kv('站点项目', r.siteProjectName),
        _kv('站点地址', r.siteUrl.isEmpty ? '构建中（稍后回填）' : r.siteUrl),
        if (r.welcomePostPath.isNotEmpty) _kv('欢迎文章', r.welcomePostPath),
        if (_isModeTwo) ...[
          const SizedBox(height: 16),
          const Text(
            '模式二：若本次部署通过 Deploy Hook 触发成功，站点已可访问；'
            'Cloudflare 控制台首次通过 Git 构建的版本可能仍显示为旧状态，无需担心。',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ],
        if (_isModeOne && _gitProvider == GitProviderType.github) ...[
          const SizedBox(height: 16),
          const Text(
            '首次构建消耗 GitHub Actions 分钟数（免费账号 2000 分钟/月）',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
        ],
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('完成'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('返回 AI 对话'),
        ),
      ],
    );
  }

  bool get _isModeOne => !_isModeTwo;
}
