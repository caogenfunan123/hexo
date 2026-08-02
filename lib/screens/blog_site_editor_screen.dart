import 'package:flutter/material.dart';

import '../core/repository/blog_repository.dart';
import '../core/repository/ghost_adapter.dart';
import '../core/repository/typecho_adapter.dart';
import '../core/repository/wordpress_adapter.dart';
import '../models/app_settings.dart';
import '../models/blog_site_config.dart';

/// 动态 CMS 站点配置编辑器
///
/// 支持添加/编辑 WordPress、Ghost、Typecho 站点配置，
/// 包含连通性测试和表单校验。
class BlogSiteEditorScreen extends StatefulWidget {
  /// 编辑已有站点时传入，新建站点时为 null
  final BlogSiteConfig? existingConfig;

  /// 全局应用设置（用于网络超时、SSL 等）
  final AppSettings appSettings;

  /// 保存回调：返回编辑后的 BlogSiteConfig
  final Future<void> Function(BlogSiteConfig) onSaved;

  const BlogSiteEditorScreen({
    super.key,
    this.existingConfig,
    required this.appSettings,
    required this.onSaved,
  });

  @override
  State<BlogSiteEditorScreen> createState() => _BlogSiteEditorScreenState();
}

class _BlogSiteEditorScreenState extends State<BlogSiteEditorScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _urlCtrl;
  late TextEditingController _wpUsernameCtrl;
  late TextEditingController _wpPasswordCtrl;
  late TextEditingController _ghostApiKeyCtrl;
  late TextEditingController _typechoEndpointCtrl;
  late TextEditingController _typechoTokenCtrl;

  BlogType _selectedType = BlogType.wordpress;
  bool _ignoreSsl = false;
  bool _testing = false;
  bool _saving = false;
  String? _testResult;
  bool _testSuccess = false;

  bool get isEditing => widget.existingConfig != null;

  @override
  void initState() {
    super.initState();
    final cfg = widget.existingConfig;
    _nameCtrl = TextEditingController(text: cfg?.name ?? '');
    _urlCtrl = TextEditingController(text: cfg?.siteUrl ?? '');
    _wpUsernameCtrl = TextEditingController(text: cfg?.wpUsername ?? '');
    _wpPasswordCtrl = TextEditingController(text: cfg?.wpAppPassword ?? '');
    _ghostApiKeyCtrl = TextEditingController(text: cfg?.ghostAdminApiKey ?? '');
    _typechoEndpointCtrl = TextEditingController(text: cfg?.typechoApiEndpoint ?? '');
    _typechoTokenCtrl = TextEditingController(text: cfg?.typechoToken ?? '');

    if (cfg != null) {
      _selectedType = cfg.type;
      _ignoreSsl = cfg.ignoreSsl;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _wpUsernameCtrl.dispose();
    _wpPasswordCtrl.dispose();
    _ghostApiKeyCtrl.dispose();
    _typechoEndpointCtrl.dispose();
    _typechoTokenCtrl.dispose();
    super.dispose();
  }

  bool get _isFormValid {
    final urlOk = _urlCtrl.text.trim().isNotEmpty;
    if (!urlOk) return false;
    return switch (_selectedType) {
      BlogType.wordpress =>
        _wpUsernameCtrl.text.trim().isNotEmpty &&
            _wpPasswordCtrl.text.trim().isNotEmpty,
      BlogType.ghost =>
        _ghostApiKeyCtrl.text.trim().isNotEmpty &&
            _ghostApiKeyCtrl.text.trim().contains(':'),
      BlogType.typecho =>
        _typechoTokenCtrl.text.trim().isNotEmpty,
      _ => false,
    };
  }

  BlogSiteConfig _buildConfig() {
    final id = widget.existingConfig?.id ??
        'blog_${DateTime.now().millisecondsSinceEpoch}';
    return BlogSiteConfig(
      id: id,
      name: _nameCtrl.text.trim(),
      type: _selectedType,
      siteUrl: _urlCtrl.text.trim(),
      ignoreSsl: _ignoreSsl,
      wpUsername: _selectedType == BlogType.wordpress
          ? _wpUsernameCtrl.text.trim()
          : null,
      wpAppPassword: _selectedType == BlogType.wordpress
          ? _wpPasswordCtrl.text.trim()
          : null,
      ghostAdminApiKey: _selectedType == BlogType.ghost
          ? _ghostApiKeyCtrl.text.trim()
          : null,
      typechoApiEndpoint: _selectedType == BlogType.typecho
          ? (_typechoEndpointCtrl.text.trim().isNotEmpty
              ? _typechoEndpointCtrl.text.trim()
              : null)
          : null,
      typechoToken: _selectedType == BlogType.typecho
          ? _typechoTokenCtrl.text.trim()
          : null,
      isDefault: widget.existingConfig?.isDefault ?? false,
    );
  }

  Future<void> _testConnection() async {
    if (!_isFormValid) {
      setState(() {
        _testResult = '请先填写完整的站点信息';
        _testSuccess = false;
      });
      return;
    }

    setState(() {
      _testing = true;
      _testResult = null;
    });

    try {
      final config = _buildConfig();
      BlogRepository adapter;
      switch (_selectedType) {
        case BlogType.wordpress:
          adapter = WordPressAdapter(config, widget.appSettings);
        case BlogType.ghost:
          adapter = GhostAdapter(config, widget.appSettings);
        case BlogType.typecho:
          adapter = TypechoAdapter(config, widget.appSettings);
        default:
          setState(() {
            _testing = false;
            _testResult = '不支持的站点类型';
            _testSuccess = false;
          });
          return;
      }

      final result = await adapter.testConnection();
      adapter.dispose();

      if (mounted) {
        setState(() {
          _testing = false;
          _testResult = result.message;
          _testSuccess = result.success;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testing = false;
          _testResult = '连接测试异常: $e';
          _testSuccess = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isFormValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写完整的站点信息')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.onSaved(_buildConfig());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isEditing ? '站点已更新' : '站点已添加')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? '编辑 CMS 站点' : '添加 CMS 站点'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 站点类型选择
            _buildSectionTitle('站点类型'),
            const SizedBox(height: 8),
            SegmentedButton<BlogType>(
              segments: const [
                ButtonSegment(
                  value: BlogType.wordpress,
                  label: Text('WordPress'),
                  icon: Icon(Icons.wordpress),
                ),
                ButtonSegment(
                  value: BlogType.ghost,
                  label: Text('Ghost'),
                  icon: Icon(Icons.auto_awesome),
                ),
                ButtonSegment(
                  value: BlogType.typecho,
                  label: Text('Typecho'),
                  icon: Icon(Icons.web),
                ),
              ],
              selected: {_selectedType},
              onSelectionChanged: (v) {
                setState(() {
                  _selectedType = v.first;
                  _testResult = null;
                });
              },
            ),
            const SizedBox(height: 24),

            // 通用字段
            _buildSectionTitle('基本信息'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '站点名称',
                hintText: '如：我的 WordPress 博客',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请输入站点名称' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: '站点 URL',
                hintText: 'https://example.com',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
              keyboardType: TextInputType.url,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '请输入站点 URL';
                final uri = Uri.tryParse(v.trim());
                if (uri == null || !uri.hasScheme) return '请输入有效的 URL';
                return null;
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('忽略 SSL 证书错误'),
              subtitle: const Text('自签名证书或内网环境请开启'),
              value: _ignoreSsl,
              onChanged: (v) => setState(() => _ignoreSsl = v),
              dense: true,
            ),
            const SizedBox(height: 24),

            // 平台专属字段
            _buildSectionTitle(_platformSectionTitle),
            const SizedBox(height: 8),
            ..._buildPlatformFields(),
            const SizedBox(height: 16),

            // 鉴权说明
            _buildAuthHint(),
            const SizedBox(height: 24),

            // 测试连接按钮
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: Text(_testing ? '测试中...' : '测试连接'),
              ),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testSuccess
                      ? Colors.green.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _testSuccess ? Colors.green : Colors.red,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _testSuccess ? Icons.check_circle : Icons.error,
                      color: _testSuccess ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _testResult!,
                        style: TextStyle(
                          color: _testSuccess ? Colors.green.shade800 : Colors.red.shade800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  String get _platformSectionTitle => switch (_selectedType) {
        BlogType.wordpress => 'WordPress 鉴权',
        BlogType.ghost => 'Ghost 鉴权',
        BlogType.typecho => 'Typecho 鉴权',
        _ => '鉴权信息',
      };

  List<Widget> _buildPlatformFields() {
    switch (_selectedType) {
      case BlogType.wordpress:
        return [
          TextFormField(
            controller: _wpUsernameCtrl,
            decoration: const InputDecoration(
              labelText: '用户名',
              hintText: 'WordPress 后台登录用户名',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? '请输入 WordPress 用户名'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _wpPasswordCtrl,
            decoration: const InputDecoration(
              labelText: 'Application Password',
              hintText: 'WP 后台 → 个人资料 → 应用程序密码',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.key),
            ),
            obscureText: true,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? '请输入 Application Password（非登录密码）'
                : null,
          ),
        ];

      case BlogType.ghost:
        return [
          TextFormField(
            controller: _ghostApiKeyCtrl,
            decoration: const InputDecoration(
              labelText: 'Admin API Key',
              hintText: '格式: id:secret（如 64f1a2b3c4:1a2b3c4d5e...）',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.vpn_key),
            ),
            obscureText: true,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return '请输入 Admin API Key';
              if (!v.trim().contains(':')) return '格式错误：应为 id:secret';
              return null;
            },
          ),
        ];

      case BlogType.typecho:
        return [
          TextFormField(
            controller: _typechoEndpointCtrl,
            decoration: const InputDecoration(
              labelText: 'API 端点（可选）',
              hintText: '留空自动探测，如 /api/posts',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.api),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _typechoTokenCtrl,
            decoration: const InputDecoration(
              labelText: 'Token',
              hintText: 'Typecho 插件设置页生成的 Token',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.token),
            ),
            obscureText: true,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? '请输入 Token'
                : null,
          ),
        ];

      default:
        return [const Text('未知平台类型')];
    }
  }

  Widget _buildAuthHint() {
    final (String title, String content) = switch (_selectedType) {
      BlogType.wordpress => (
            '如何获取 WordPress Application Password？',
            '1. 登录 WordPress 后台\n'
                '2. 进入「用户」→「个人资料」\n'
                '3. 滚动到底部「应用程序密码」\n'
                '4. 输入名称（如 "HexoManager"）→ 点击「添加新的应用程序密码」\n'
                '5. 复制生成的密码（注意：只显示一次）\n\n'
                '要求：WordPress 5.6+，REST API 未被禁用',
          ),
      BlogType.ghost => (
            '如何获取 Ghost Admin API Key？',
            '1. 登录 Ghost 后台\n'
                '2. 进入 Settings → Integrations\n'
                '3. 点击「Add custom integration」\n'
                '4. 输入名称（如 "HexoManager"）\n'
                '5. 复制 Admin API Key（格式为 id:secret）\n\n'
                '要求：Ghost 3.0+，请使用 Admin API Key 而非 Content API Key',
          ),
      BlogType.typecho => (
            '如何获取 Typecho Token？',
            '1. 安装 REST API 插件（推荐 Typecho-Plugin-Restful）\n'
                '2. 进入插件设置页\n'
                '3. 生成 API Token\n'
                '4. 粘贴到此处\n\n'
                '注意：不同插件的 JSON 结构存在差异，\n'
                '如连接失败请尝试切换 API 端点路径',
          ),
      _ => ('', ''),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            content,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}