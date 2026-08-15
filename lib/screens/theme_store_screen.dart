import 'package:flutter/material.dart';

import '../models/repo_config.dart';
import '../models/theme_store_item.dart';
import '../services/theme_store_service.dart';

/// 主题商店：浏览内置精选主题并一键安装到建站仓库
///
/// 机械安装流程统一（下载 → 解压 → writeBatch → 改 config → 触发 CI），
/// 深度定制请使用「AI 主题开发」对话。
class ThemeStoreScreen extends StatefulWidget {
  final List<RepoConfig> repos;
  final ThemeStoreService service;
  final void Function(String message)? onToast;

  const ThemeStoreScreen({
    super.key,
    this.repos = const [],
    this.service = const ThemeStoreService(),
    this.onToast,
  });

  @override
  State<ThemeStoreScreen> createState() => _ThemeStoreScreenState();
}

class _ThemeStoreScreenState extends State<ThemeStoreScreen> {
  String? _repoId;
  String? _frameworkFilter;
  String? _installingThemeId;
  double _installProgress = 0.0;
  final Map<String, ThemeInstallResult> _results = {};

  @override
  void initState() {
    super.initState();
    if (widget.repos.isNotEmpty) {
      _repoId = widget.repos.first.id;
      _frameworkFilter = widget.repos.first.frameworkId;
    }
  }

  List<ThemeStoreItem> get _filteredThemes =>
      ThemeStoreService.themesForFramework(_frameworkFilter);

  RepoConfig? get _selectedRepo =>
      widget.repos.where((r) => r.id == _repoId).firstOrNull;

  Future<void> _install(ThemeStoreItem item) async {
    final repo = _selectedRepo;
    if (repo == null) {
      _toast('请先选择目标站点仓库');
      return;
    }
    setState(() {
      _installingThemeId = item.id;
      _installProgress = 0.2;
    });
    try {
      final result = await widget.service.installTheme(
        repo,
        item,
        onProgress: (d, t) {
          if (mounted) {
            setState(() => _installProgress = d / t);
          }
        },
      );
      if (mounted) {
        setState(() {
          _results[item.id] = result;
          _installingThemeId = null;
          _installProgress = 1.0;
        });
      }
      _toast('主题 ${item.name} 安装完成，共写入 ${result.fileCount} 个文件，CI 构建中');
    } catch (e) {
      if (mounted) {
        setState(() => _installingThemeId = null);
      }
      _toast('安装失败: $e');
    }
  }

  void _toast(String message) {
    if (widget.onToast != null) {
      widget.onToast!(message);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themes = _filteredThemes;
    final frameworkNames = {
      'hexo': 'Hexo',
      'hugo': 'Hugo',
      'jekyll': 'Jekyll',
      'astro': 'Astro',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('主题商店'),
        actions: [
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: '需要深度定制？用 AI 主题开发',
            onPressed: _toast != null
                ? () => _toast('深度定制请使用「AI 主题开发」对话')
                : null,
          ),
        ],
      ),
      body: Column(
        children: [
          // 仓库选择 + 框架筛选
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.repos.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: _repoId,
                    decoration: const InputDecoration(
                      labelText: '目标站点仓库',
                      prefixIcon: Icon(Icons.storage_outlined),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: widget.repos
                        .map((r) => DropdownMenuItem(
                              value: r.id,
                              child: Text('${r.name} (${r.fullName})'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _repoId = v;
                      final r = widget.repos.where((x) => x.id == v).firstOrNull;
                      _frameworkFilter = r?.frameworkId ?? _frameworkFilter;
                    }),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.errorContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '尚未配置站点仓库，请先到「站点管理」创建并同步仓库',
                      style: TextStyle(color: cs.onErrorContainer),
                    ),
                  ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('全部'),
                        selected: _frameworkFilter == null,
                        onSelected: (_) =>
                            setState(() => _frameworkFilter = null),
                      ),
                      for (final fw in ['hexo', 'hugo', 'jekyll', 'astro'])
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ChoiceChip(
                            label: Text(frameworkNames[fw] ?? fw),
                            selected: _frameworkFilter == fw,
                            onSelected: (_) =>
                                setState(() => _frameworkFilter = fw),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1),
          // 主题列表
          Expanded(
            child: themes.isEmpty
                ? Center(
                    child: Text('暂无可安装的主题',
                        style: TextStyle(color: cs.onSurface.withOpacity(0.6))),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: themes.length,
                    itemBuilder: (context, i) =>
                        _buildThemeCard(cs, themes[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeCard(ColorScheme cs, ThemeStoreItem item) {
    final result = _results[item.id];
    final installing = _installingThemeId == item.id;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 截图缩略占位
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: item.screenshotUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        item.screenshotUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.palette_outlined,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    )
                  : Icon(Icons.palette_outlined, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.frameworkId,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${item.author} · ${item.fullName}',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withOpacity(0.4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (installing)
                    Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '安装中 ${(_installProgress * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                              fontSize: 12, color: cs.primary),
                        ),
                      ],
                    )
                  else if (result != null)
                    Text(
                      '已安装 · 写入 ${result.fileCount} 文件'
                      '${result.configChanged ? ' · config 已切换' : ''}',
                      style: TextStyle(fontSize: 12, color: cs.primary),
                    )
                  else
                    Row(
                      children: [
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text('安装'),
                          onPressed: _installingThemeId != null
                              ? null
                              : () => _install(item),
                        ),
                        const SizedBox(width: 8),
                        if (_selectedRepo != null)
                          Text(
                            _selectedRepo!.frameworkId == item.frameworkId
                                ? ''
                                : '与当前站点框架 ${_selectedRepo!.frameworkId} 不匹配',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withOpacity(0.5),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
