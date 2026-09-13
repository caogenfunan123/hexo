// 外观定制 / 帮助扩展（desktop_shell.dart 的 part，与主类同 library，可访问私有成员）。
// 由 desktop_shell.dart 拆分而来（修复1），方法体保持零变更；
// setState 经宿主 _applyState 包装调用。
part of '../desktop_shell.dart';

extension DesktopShellStyleExt on DesktopShellState {
  Future<void> _showThemeColorPicker() async {
    const colors = [
      Color(0xFF0D9488),
      Color(0xFF0EA5E9),
      Color(0xFF6366F1),
      Color(0xFF8B5CF6),
      Color(0xFFEC4899),
      Color(0xFFF43F5E),
      Color(0xFF10B981),
      Color(0xFF14B8A6),
      Color(0xFFF59E0B),
      Color(0xFF64748B),
      Color(0xFF1E293B),
    ];
    const names = [
      '青绿',
      '天蓝',
      '靛蓝',
      '紫色',
      '粉色',
      '玫瑰红',
      '翡翠绿',
      '青色',
      '琥珀',
      '石板灰',
      '深灰',
    ];
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择主题颜色'),
        content: SizedBox(
          width: 300,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(colors.length, (i) {
              return GestureDetector(
                onTap: () async {
                  settings = settings.copyWith(themeColor: colors[i].value);
                  await _persistSettings();
                  if (mounted) _applyState(() {});
                  _showToast('主题色已切换为${names[i]}');
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors[i],
                        borderRadius: BorderRadius.circular(8),
                        border: settings.themeColor == colors[i].value
                            ? Border.all(color: Colors.black, width: 2.5)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(names[i], style: const TextStyle(fontSize: 11)),
                  ],
                ),
              );
            }),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showFontSettings() {
    double localFontSize = _editor.editorFontSize;
    double localLineHeight = _editor.editorLineHeight;
    String localFontFamily = _editor.editorFontFamily;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.text_fields, size: 20),
              SizedBox(width: 8),
              Text('字体设置', style: TextStyle(fontSize: 17)),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 字体大小
                Row(
                  children: [
                    const Icon(Icons.format_size, size: 16),
                    const SizedBox(width: 8),
                    const Text(
                      '字体大小',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${localFontSize.toInt()}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: localFontSize,
                  min: 12,
                  max: 28,
                  divisions: 16,
                  label: '${localFontSize.toInt()}',
                  onChanged: (v) => setDialogState(() => localFontSize = v),
                ),
                const SizedBox(height: 12),
                // 行高
                Row(
                  children: [
                    const Icon(Icons.format_line_spacing, size: 16),
                    const SizedBox(width: 8),
                    const Text(
                      '行高',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      localLineHeight.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: localLineHeight,
                  min: 1.2,
                  max: 2.5,
                  divisions: 13,
                  label: localLineHeight.toStringAsFixed(1),
                  onChanged: (v) => setDialogState(() => localLineHeight = v),
                ),
                const SizedBox(height: 12),
                // 字体族
                Row(
                  children: [
                    const Icon(Icons.font_download_outlined, size: 16),
                    const SizedBox(width: 8),
                    const Text(
                      '字体族',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: localFontFamily,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'System',
                      child: Text('System（系统默认）'),
                    ),
                    DropdownMenuItem(
                      value: 'monospace',
                      child: Text('monospace（等宽）'),
                    ),
                    DropdownMenuItem(value: 'serif', child: Text('serif（衬线）')),
                    DropdownMenuItem(
                      value: 'sans-serif',
                      child: Text('sans-serif（无衬线）'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => localFontFamily = v);
                  },
                ),
                const SizedBox(height: 16),
                // 预览
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'AaBbCc 中文预览 123',
                    style: TextStyle(
                      fontSize: localFontSize,
                      height: localLineHeight,
                      fontFamily: _resolveFontFamily(localFontFamily),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (mounted) {
                  _applyState(() {
                    _editor.setEditorFontSize(localFontSize);
                    _editor.setEditorLineHeight(localLineHeight);
                    _editor.setEditorFontFamily(localFontFamily);
                  });
                }
                await _saveEditorSettings();
                _showToast('字体设置已保存');
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
  }

  void _showThemePicker() {
    final themeKeys = editorThemes.keys.toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          String selectedTheme = _editor.editorTheme;
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.palette_outlined, size: 20),
                SizedBox(width: 8),
                Text('编辑器主题', style: TextStyle(fontSize: 17)),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 当前主题预览
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: getEditorTheme(selectedTheme).backgroundColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '标题预览',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: getEditorTheme(selectedTheme).headingColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '这是正文预览文本，展示当前主题的文字颜色效果。',
                          style: TextStyle(
                            fontSize: 13,
                            color: getEditorTheme(selectedTheme).textColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: getEditorTheme(
                              selectedTheme,
                            ).codeBlockBackground,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'code block preview',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: getEditorTheme(
                                selectedTheme,
                              ).codeBlockTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 主题网格
                  SizedBox(
                    height: 200,
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 1.3,
                          ),
                      itemCount: themeKeys.length,
                      itemBuilder: (_, i) {
                        final key = themeKeys[i];
                        final theme = editorThemes[key]!;
                        final isSelected = selectedTheme == key;
                        return GestureDetector(
                          onTap: () =>
                              setDialogState(() => selectedTheme = key),
                          child: Container(
                            decoration: BoxDecoration(
                              color: theme.backgroundColor,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? Theme.of(ctx).colorScheme.primary
                                    : Colors.grey.shade300,
                                width: isSelected ? 2.5 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  theme.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: theme.textColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  width: 30,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: theme.headingColor,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  width: 40,
                                  height: 2,
                                  decoration: BoxDecoration(
                                    color: theme.textColor.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  if (mounted) {
                    _editor.setEditorTheme(selectedTheme);
                  }
                  await _saveEditorSettings();
                  _showToast('主题已切换为: ${getEditorTheme(selectedTheme).name}');
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('应用'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showCustomCssEditor() async {
    final cssCtrl = TextEditingController(text: _editor.customCss);

    try {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.css, size: 20),
              SizedBox(width: 8),
              Text('自定义 CSS', style: TextStyle(fontSize: 17)),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '支持简化的 CSS 属性映射，如：\n'
                  'h1-size: 28; h2-size: 22; h3-size: 18;\n'
                  'code-bg: #f5f5f5; code-color: #333;\n'
                  'link-color: #0366d6;',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cssCtrl,
                  maxLines: 10,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: '在此输入自定义 CSS 规则...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                cssCtrl.text = '';
                if (mounted) {
                  _editor.setCustomCss('');
                }
                _saveEditorSettings();
                _showToast('CSS 已重置');
                Navigator.pop(ctx);
              },
              child: const Text('重置'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (mounted) {
                  _editor.setCustomCss(cssCtrl.text);
                }
                await _saveEditorSettings();
                _showToast('自定义 CSS 已应用');
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('应用'),
            ),
          ],
        ),
      );
    } finally {
      cssCtrl.dispose();
    }
  }

  Future<void> _showShortcutEditor() async {
    // 合并默认快捷键和自定义快捷键
    final shortcuts = Map<String, String>.from(DesktopShellState._defaultShortcuts);
    shortcuts.addAll(_editor.customShortcuts);

    // 预创建控制器并在对话框关闭后统一 dispose，避免 itemBuilder 内泄漏
    final ctrls = <String, TextEditingController>{};
    for (final entry in shortcuts.entries) {
      ctrls[entry.key] = TextEditingController(text: entry.value);
    }

    try {
      await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.keyboard, size: 20),
                SizedBox(width: 8),
                Text('快捷键设置', style: TextStyle(fontSize: 17)),
              ],
            ),
            content: SizedBox(
              width: 500,
              height: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '提示: 点击快捷键值可编辑，修改后点击空白处保存。\n'
                      '格式: Ctrl+X / Ctrl+Shift+X / Alt+X',
                      style: TextStyle(fontSize: 11, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: shortcuts.entries.map((entry) {
                        final action = entry.key;
                        final label = DesktopShellState._actionLabels[action] ?? action;
                        final ctrl = ctrls[action]!;

                        return ListTile(
                          dense: true,
                          title: Text(
                            label,
                            style: const TextStyle(fontSize: 13),
                          ),
                          trailing: SizedBox(
                            width: 140,
                            child: TextField(
                              controller: ctrl,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: ctrl.text.isEmpty ? Colors.grey : null,
                              ),
                              decoration: InputDecoration(
                                hintText: '未设置',
                                hintStyle: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onSubmitted: (value) {
                                _editor.setCustomShortcut(action, value.trim());
                                _saveEditorSettings();
                                widget.onShortcutsChanged?.call();
                                setDialogState(() {});
                              },
                              onTapOutside: (_) {
                                _editor.setCustomShortcut(
                                  action,
                                  ctrl.text.trim(),
                                );
                                _saveEditorSettings();
                                widget.onShortcutsChanged?.call();
                                setDialogState(() {});
                              },
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _editor.setCustomShortcuts({});
                  _saveEditorSettings();
                  widget.onShortcutsChanged?.call();
                  _showToast('快捷键已重置为默认值');
                  Navigator.pop(ctx);
                },
                child: const Text('恢复默认'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
    } finally {
      for (final c in ctrls.values) {
        c.dispose();
      }
    }
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline, size: 22),
            SizedBox(width: 8),
            Text(
              '帮助 · 快捷键速查',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        content: SizedBox(
          width: 700,
          height: 520,
          child: DefaultTabController(
            length: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TabBar(
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: TextStyle(fontSize: 13),
                  tabs: [
                    Tab(text: '快捷键'),
                    Tab(text: '功能概览'),
                    Tab(text: '模式与布局'),
                    Tab(text: '使用技巧'),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 420,
                  child: TabBarView(
                    children: [
                      // ── 快捷键 ──
                      _buildHelpShortcuts(),
                      // ── 功能概览 ──
                      _buildHelpFeatures(),
                      // ── 模式与布局 ──
                      _buildHelpLayout(),
                      // ── 使用技巧 ──
                      _buildHelpTips(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpShortcuts() {
    final shortcuts = <(String, String)>[
      ('Ctrl+S', '保存草稿'),
      ('Ctrl+P', '一键发布'),
      ('Ctrl+N', '新建文章'),
      ('Ctrl+O', '打开 .md 文件'),
      ('Ctrl+Shift+S', '另存为到本地'),
      ('Ctrl+Shift+P', '命令面板'),
      ('F1', '打开帮助'),
      ('Ctrl+B', '加粗'),
      ('Ctrl+I', '斜体'),
      ('Ctrl+D', '删除线'),
      ('Ctrl+K', '插入链接'),
      ('Ctrl+1', '一级标题'),
      ('Ctrl+2', '二级标题'),
      ('Ctrl+3', '三级标题'),
      ('Ctrl+Shift+V', '粘贴剪贴板图片'),
      ('Ctrl+F', '专注模式'),
      ('Ctrl+L', '切换左侧面板'),
      ('Ctrl+E', '打开大纲'),
    ];
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: shortcuts
          .map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 130,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      e.$1,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(e.$2, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildHelpFeatures() {
    final features = [
      (
        '写作编辑',
        [
          'Markdown 实时预览',
          '代码语法高亮（flutter_highlight）',
          'LaTeX 数学公式（块级+内联）',
          'Mermaid 图表渲染',
          '查找替换（支持正则）',
          'TOC 自动生成',
          '可视化表格编辑',
          '全文格式化',
          '打字机模式（光标居中）',
        ],
      ),
      (
        '图片处理',
        [
          '剪贴板截图粘贴上传',
          '本地图片选择上传',
          '批量插图+预处理压缩',
          '图片尺寸快捷设置',
          '图片路径相对/绝对切换',
          '发布前路径自动修复',
          '图床管理面板',
          '图片死链检测',
        ],
      ),
      (
        '多格式导出',
        ['HTML（完整模板）', 'PDF（printing 包）', 'DOCX（OOXML）', 'EPUB（电子书）', '另存为到本地'],
      ),
      (
        'AI 能力',
        [
          'AI 润色/续写',
          'AI 博文/页面创作',
          'AI 主题迁移',
          'AI 站点巡检',
          'AI 应用 UI 设计',
          'AI 选区改写',
          'AI 全文润色',
          'AI 输出对比（diff 预览）',
          'AI 提示词模板库',
          'AI 自主创建/管理技能',
        ],
      ),
      ('编辑器自定义', ['7 种编辑器主题', '自定义字体/字号/行高', '自定义 CSS', '自定义快捷键', '夜间护眼滤镜']),
      (
        '文件管理',
        [
          '最近打开文件（10条）',
          '文件夹工作区',
          '文件重命名/移动',
          '拖拽 .md 文件导入',
          '回收站（防误删）',
          '版本历史快照',
          '编码修复工具',
        ],
      ),
      (
        '同步与发布',
        [
          'GitHub / WebDAV 云同步',
          '同步冲突可视化对比',
          '冲突策略（本地/云端优先）',
          '一键发布到 GitHub/CMS',
          '发布前预检测',
          '定时发布',
          '发布变更日志',
        ],
      ),
      ('导入', ['HTML 转 Markdown', 'DOCX 转 Markdown', '.md / .txt 打开']),
      ('搜索', ['全局工作区搜索', '草稿/已发布筛选', '编辑器内查找替换']),
      ('系统', ['网络代理设置', '离线模式', '缓存清理', '日志导出', '命令面板（Ctrl+Shift+P）']),
    ];
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: features
          .map(
            (group) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.$1,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...group.$2.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(left: 12, top: 2),
                      child: Row(
                        children: [
                          const Text(
                            '  •  ',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          Expanded(
                            child: Text(
                              item,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildHelpLayout() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: const [
        Text(
          '🎯 三种工作模式',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 8),
        _HelpModeCard('工作台', '完整三栏布局：左侧导航 + 中央编辑器 + 右侧抽屉', '适合日常写作、管理文章'),
        _HelpModeCard('专注模式', '极简顶栏，隐藏面板，全宽编辑器 + 实时预览', '适合沉浸式写作，打字机滚动'),
        _HelpModeCard('写作画布', '标题+正文一张连续画布，所见即所得，支持自定义壁纸', '对标手机端的沉浸排版写作'),
        SizedBox(height: 16),
        Text(
          '📐 布局说明',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 8),
        _HelpLayoutItem('顶栏', '站点切换下拉框 + 功能按钮（同步/发布/AI/主题/文件/新建）'),
        _HelpLayoutItem('左侧面板', '可折叠、可拖拽宽度。包含全部导航入口'),
        _HelpLayoutItem('中央编辑器', '多标签页，支持切换和关闭'),
        _HelpLayoutItem('右侧抽屉', '悬浮式，4 个标签：大纲 | 属性 | AI 聊天 | 同步日志'),
        _HelpLayoutItem('底部状态栏', '工作模式切换 | 编辑器状态 | 行列位置 | 字数统计'),
        SizedBox(height: 16),
        Text(
          '⌨️ 命令面板',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 4),
        Text(
          '  Ctrl+Shift+P 打开命令面板，搜索 48 条命令，覆盖全部功能。\n  无需记忆快捷键，输入关键词即可快速执行。',
          style: TextStyle(fontSize: 12.5, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildHelpTips() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        _HelpTipCard(
          '💡 快速发布',
          '写完文章后，按 Ctrl+P 直接发布。\n发布前会自动检查图片路径，可在确认框中勾选"同时保存 MD 备份"。',
        ),
        _HelpTipCard(
          '🖼️ 截图粘贴',
          '截屏后按 Ctrl+Shift+V，图片自动上传到 GitHub 图床并插入 Markdown。\n也可以在编辑器中右键粘贴。',
        ),
        _HelpTipCard(
          '📝 自动保存',
          '开启自动保存后，每隔 N 秒自动保存草稿到本地。\n切后台/关闭窗口前也会自动保存，不用担心丢失。',
        ),
        _HelpTipCard(
          '☁️ 云同步',
          '配置 WebDAV 后，启动时自动拉取，定时推送，切后台推送，切前台拉取。\n多设备间无缝同步草稿。',
        ),
        _HelpTipCard('🔍 查找替换', '支持正则表达式和区分大小写。\n全部替换会一次性替换所有匹配项。'),
        _HelpTipCard('📊 表格编辑', '插入表格后，光标放在表格内可使用"添加行/列"功能。\n支持动态扩展表格。'),
        _HelpTipCard(
          '🎨 主题切换',
          '7 种编辑器主题可随时切换，预览区同步生效。\nGitHub 主题适合亮色环境，Monokai/Dracula/Nord 适合暗色。',
        ),
        _HelpTipCard('📦 批量操作', '在草稿箱中可多选草稿，批量导出、格式化或发布。\n适合需要一次性处理多篇文章的场景。'),
        _HelpTipCard(
          '🔄 图片路径',
          '使用相对路径写作，发布前用"修复发布路径"一键转为绝对路径。\n切换图片路径模式可批量转换。',
        ),
        _HelpTipCard(
          '📂 文件管理',
          '打开文件夹工作区可浏览整个目录的 .md 文件。\n最近打开文件列表记录最近 10 个文件，方便快速切换。',
        ),
        _HelpTipCard(
          '⚠️ 冲突处理',
          '多设备同步时若出现冲突，会自动弹出双栏对比界面。\n可选择保留本地版本、云端版本，或全部本地/云端优先。',
        ),
        _HelpTipCard(
          '🤖 AI 选区',
          '选中一段文字后按 Ctrl+Shift+I，只将选中文字发送给 AI 改写。\nAI 修改完成后会显示 diff 对比，可选择接受或拒绝。',
        ),
        _HelpTipCard(
          '⏰ 定时发布',
          '在命令面板中搜索"定时发布"，设置时间后自动发布。\n适合在节假日或特定时间点自动推送文章。',
        ),
        _HelpTipCard(
          '🔍 全局搜索',
          'Ctrl+Shift+F 搜索所有文章的标题和正文。\n可筛选草稿/已发布状态，快速定位目标文章。',
        ),
        _HelpTipCard('🛡️ 发布预检', '发布前自动检查空标题、空内容、图片链接等。\n确保发布质量，避免推送不完整文章。'),
      ],
    );
  }
}
