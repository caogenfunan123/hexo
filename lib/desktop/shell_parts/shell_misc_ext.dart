// 杂项 / 命令面板扩展（desktop_shell.dart 的 part，与主类同 library，可访问私有成员）。
// 由 desktop_shell.dart 拆分而来（修复1），方法体保持零变更；
// setState 经宿主 _applyState 包装调用。
part of '../desktop_shell.dart';

extension DesktopShellMiscExt on DesktopShellState {
  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openCommandPalette() {
    _applyState(() => _showCommandPalette = true);
  }

  void _closeCommandPalette() {
    _applyState(() => _showCommandPalette = false);
  }

  /// 阶段2 Spike：super_editor 所见即所得编辑（实验入口，经命令面板触发）
  Future<void> _openWysiwygPoc() async {
    final initial = _doc.contentCtrl.text;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => WysiwygPocDialog(initialMarkdown: initial),
    );
    if (result == null) return;
    if (result != initial) {
      _doc.contentCtrl.text = result;
      _onContentChanged();
      _showToast('所见即所得内容已应用');
    }
  }

  List<CommandItem> _buildCommandItems() {
    return [
      CommandItem(
        label: '所见即所得编辑（实验）',
        category: '编辑',
        shortcut: '',
        icon: Icons.auto_fix_high_outlined,
        onExecute: _openWysiwygPoc,
      ),
      CommandItem(
        label: '保存草稿',
        category: '文件',
        shortcut: 'Ctrl+S',
        icon: Icons.save,
        onExecute: () => _saveLocal(),
      ),
      CommandItem(
        label: '一键发布',
        category: '文件',
        shortcut: 'Ctrl+P',
        icon: Icons.send,
        onExecute: () => _handlePublish(),
      ),
      CommandItem(
        label: '新建文章',
        category: '文件',
        shortcut: 'Ctrl+N',
        icon: Icons.add,
        onExecute: () => _newArticle(),
      ),
      CommandItem(
        label: '打开文件',
        category: '文件',
        shortcut: 'Ctrl+O',
        icon: Icons.folder_open,
        onExecute: () => _openFileDialog(),
      ),
      CommandItem(
        label: '另存为...',
        category: '文件',
        shortcut: 'Ctrl+Shift+S',
        icon: Icons.save_as,
        onExecute: () => _saveAsToLocal(),
      ),
      CommandItem(
        label: '导出 HTML',
        category: '导出',
        shortcut: '',
        icon: Icons.html,
        onExecute: () => _exportHtml(),
      ),
      CommandItem(
        label: '导出 PDF',
        category: '导出',
        shortcut: '',
        icon: Icons.picture_as_pdf,
        onExecute: () => _exportPdf(),
      ),
      CommandItem(
        label: '导出 DOCX',
        category: '导出',
        shortcut: '',
        icon: Icons.description,
        onExecute: () => _exportDocx(),
      ),
      CommandItem(
        label: '导出 EPUB',
        category: '导出',
        shortcut: '',
        icon: Icons.book,
        onExecute: () => _exportEpub(),
      ),
      CommandItem(
        label: '专注模式',
        category: '视图',
        shortcut: 'Ctrl+Shift+F',
        icon: Icons.auto_awesome,
        onExecute: () => _switchWorkMode(WorkMode.focus),
      ),
      CommandItem(
        label: '工作台模式',
        category: '视图',
        shortcut: '',
        icon: Icons.dashboard,
        onExecute: () => _switchWorkMode(WorkMode.workspace),
      ),
      CommandItem(
        label: '源码模式',
        category: '视图',
        shortcut: '',
        icon: Icons.code,
        onExecute: () => _switchWorkMode(WorkMode.source),
      ),
      CommandItem(
        label: '切换左侧面板',
        category: '视图',
        shortcut: 'Ctrl+L',
        icon: Icons.menu_open,
        onExecute: () => _toggleLeftPanel(),
      ),
      CommandItem(
        label: '打开大纲',
        category: '视图',
        shortcut: 'Ctrl+E',
        icon: Icons.list_alt,
        onExecute: () => _openRightDrawer(RightDrawerTab.outline),
      ),
      CommandItem(
        label: '查找替换',
        category: '编辑',
        shortcut: 'Ctrl+F',
        icon: Icons.find_replace,
        onExecute: () => _showFindReplace(),
      ),
      CommandItem(
        label: '插入目录',
        category: '编辑',
        shortcut: '',
        icon: Icons.toc,
        onExecute: () => _insertToc(),
      ),
      CommandItem(
        label: '插入表格',
        category: '编辑',
        shortcut: '',
        icon: Icons.table_chart,
        onExecute: () => _insertTable(),
      ),
      CommandItem(
        label: '文档格式化',
        category: '编辑',
        shortcut: '',
        icon: Icons.cleaning_services,
        onExecute: () => _formatDocument(),
      ),
      CommandItem(
        label: '粘贴图片',
        category: '编辑',
        shortcut: 'Ctrl+Shift+V',
        icon: Icons.image,
        onExecute: () => _pasteImageFromClipboard(),
      ),
      CommandItem(
        label: 'Agent 任务工作台',
        category: 'AI',
        shortcut: '',
        icon: Icons.assignment_outlined,
        onExecute: () => _showAgentWorkbench(),
      ),
      CommandItem(
        label: 'AI 模板与博客框架',
        category: 'AI',
        shortcut: '',
        icon: Icons.view_quilt_outlined,
        onExecute: () => _showAiTemplateChat(),
      ),
      CommandItem(
        label: 'AI 选区改写',
        category: 'AI',
        shortcut: '',
        icon: Icons.short_text,
        onExecute: () => _sendSelectionToAi(),
      ),
      CommandItem(
        label: 'AI 全文润色',
        category: 'AI',
        shortcut: '',
        icon: Icons.auto_awesome,
        onExecute: () => _sendFullToAi(),
      ),
      CommandItem(
        label: '草稿箱',
        category: '导航',
        shortcut: '',
        icon: Icons.drafts_outlined,
        onExecute: () => _openDrafts(),
      ),
      CommandItem(
        label: '远程文章',
        category: '导航',
        shortcut: '',
        icon: Icons.cloud_outlined,
        onExecute: () => _openRemote(),
      ),
      CommandItem(
        label: '仪表盘',
        category: '导航',
        shortcut: '',
        icon: Icons.dashboard_outlined,
        onExecute: () => _openDashboard(),
      ),
      CommandItem(
        label: '回收站',
        category: '导航',
        shortcut: '',
        icon: Icons.delete_outline,
        onExecute: () => _openRecycleBin(),
      ),
      CommandItem(
        label: '模板管理',
        category: '工具',
        shortcut: '',
        icon: Icons.view_quilt_outlined,
        onExecute: () => _showTemplateManager(),
      ),
      CommandItem(
        label: '图床管理',
        category: '工具',
        shortcut: '',
        icon: Icons.photo_library_outlined,
        onExecute: () => _openImageBedManager(),
      ),
      CommandItem(
        label: '版本历史',
        category: '工具',
        shortcut: '',
        icon: Icons.history,
        onExecute: () => _openVersionHistory(),
      ),
      CommandItem(
        label: '链接检测',
        category: '工具',
        shortcut: '',
        icon: Icons.link_off,
        onExecute: () => _openLinkChecker(),
      ),
      CommandItem(
        label: '设置',
        category: '工具',
        shortcut: '',
        icon: Icons.settings_outlined,
        onExecute: () => _openSettings(),
      ),
      CommandItem(
        label: '快捷键设置',
        category: '工具',
        shortcut: '',
        icon: Icons.keyboard,
        onExecute: () => _showShortcutEditor(),
      ),
      CommandItem(
        label: '帮助 / 快捷键速查',
        category: '帮助',
        shortcut: 'F1',
        icon: Icons.help_outline,
        onExecute: () => _showHelpDialog(),
      ),
    ];
  }
}
