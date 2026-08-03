/// 右侧悬浮抽屉面板
/// 包含：大纲、FrontMatter、AI 聊天、同步日志
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// 右侧抽屉标签
enum RightDrawerTab {
  outline,
  frontMatter,
  aiChat,
  syncLog,
}

class DesktopRightDrawer extends StatelessWidget {
  final RightDrawerTab activeTab;
  final ValueChanged<RightDrawerTab> onTabChange;
  final VoidCallback onClose;

  /// 大纲数据（Markdown标题列表）
  final List<OutlineItem> outlineItems;

  /// FrontMatter 控制器
  final TextEditingController? titleCtrl;
  final TextEditingController? tagsCtrl;
  final TextEditingController? categoriesCtrl;
  final TextEditingController? coverCtrl;
  final TextEditingController? dateCtrl;

  /// AI 聊天面板
  final Widget? aiChatPanel;

  /// 同步日志
  final List<String> syncLogs;

  const DesktopRightDrawer({
    super.key,
    required this.activeTab,
    required this.onTabChange,
    required this.onClose,
    this.outlineItems = const [],
    this.titleCtrl,
    this.tagsCtrl,
    this.categoriesCtrl,
    this.coverCtrl,
    this.dateCtrl,
    this.aiChatPanel,
    this.syncLogs = const [],
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          left: BorderSide(color: cs.outlineVariant.withOpacity(0.2)),
        ),
      ),
      child: Column(
        children: [
          // ── 顶部标签切换 ──
          Container(
            height: 40,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.2)),
              ),
            ),
            child: Row(
              children: [
                _tabButton(RightDrawerTab.outline, Icons.list_alt, '大纲'),
                _tabButton(RightDrawerTab.frontMatter, Icons.tune, '属性'),
                _tabButton(RightDrawerTab.aiChat, Icons.auto_awesome, 'AI'),
                _tabButton(RightDrawerTab.syncLog, Icons.sync, '日志'),
                const Spacer(),
                GestureDetector(
                  onTap: onClose,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(Icons.close, size: 16, color: cs.onSurface.withOpacity(0.5)),
                  ),
                ),
              ],
            ),
          ),

          // ── 内容区 ──
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(RightDrawerTab tab, IconData icon, String label) {
    final isActive = activeTab == tab;
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => onTabChange(tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isActive ? cs.primary : cs.onSurface.withOpacity(0.5)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? cs.primary : cs.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (activeTab) {
      case RightDrawerTab.outline:
        return _buildOutline();
      case RightDrawerTab.frontMatter:
        return _buildFrontMatter();
      case RightDrawerTab.aiChat:
        return _buildAiChat();
      case RightDrawerTab.syncLog:
        return _buildSyncLog();
    }
  }

  // ── 大纲视图 ──
  Widget _buildOutline() {
    final cs = Theme.of(context).colorScheme;
    if (outlineItems.isEmpty) {
      return Center(
        child: Text('暂无大纲', style: TextStyle(color: cs.onSurface.withOpacity(0.3), fontSize: 13)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: outlineItems.length,
      itemBuilder: (_, i) {
        final item = outlineItems[i];
        return Padding(
          padding: EdgeInsets.only(left: (item.level - 1) * 16.0),
          child: ListTile(
            dense: true,
            leading: Icon(
              item.level == 1 ? Icons.title : Icons.subdirectory_arrow_right,
              size: 14,
              color: cs.primary.withOpacity(0.6),
            ),
            title: Text(
              item.title,
              style: TextStyle(
                fontSize: 12 + (3 - item.level).clamp(0, 2).toDouble(),
                fontWeight: item.level == 1 ? FontWeight.w600 : FontWeight.w400,
                color: cs.onSurface,
              ),
            ),
            onTap: item.onTap,
          ),
        );
      },
    );
  }

  // ── FrontMatter 编辑 ──
  Widget _buildFrontMatter() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fmField('标题', titleCtrl),
          const SizedBox(height: 10),
          _fmField('标签', tagsCtrl, hint: '逗号分隔'),
          const SizedBox(height: 10),
          _fmField('分类', categoriesCtrl, hint: '逗号分隔'),
          const SizedBox(height: 10),
          _fmField('封面图', coverCtrl, hint: '图片 URL'),
          const SizedBox(height: 10),
          _fmField('日期', dateCtrl, hint: 'YYYY-MM-DD'),
        ],
      ),
    );
  }

  Widget _fmField(String label, TextEditingController? ctrl, {String? hint}) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.5))),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.3)),
            ),
          ),
        ),
      ],
    );
  }

  // ── AI 聊天面板 ──
  Widget _buildAiChat() {
    if (aiChatPanel != null) return aiChatPanel!;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 48, color: cs.primary.withOpacity(0.3)),
          const SizedBox(height: 12),
          Text('AI 助手', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.5))),
          const SizedBox(height: 4),
          Text('选择文章后可使用 AI 辅助写作', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.3))),
        ],
      ),
    );
  }

  // ── 同步日志 ──
  Widget _buildSyncLog() {
    final cs = Theme.of(context).colorScheme;
    if (syncLogs.isEmpty) {
      return Center(
        child: Text('暂无同步日志', style: TextStyle(color: cs.onSurface.withOpacity(0.3), fontSize: 13)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: syncLogs.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          syncLogs[i],
          style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: cs.onSurface.withOpacity(0.7)),
        ),
      ),
    );
  }
}

/// 大纲条目
class OutlineItem {
  final int level;
  final String title;
  final VoidCallback? onTap;

  const OutlineItem({
    required this.level,
    required this.title,
    this.onTap,
  });
}

/// 从 Markdown 内容解析大纲
List<OutlineItem> parseOutline(String markdown) {
  final items = <OutlineItem>[];
  final lines = markdown.split('\n');
  for (final line in lines) {
    final match = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line.trim());
    if (match != null) {
      items.add(OutlineItem(
        level: match.group(1)!.length,
        title: match.group(2)!.trim(),
      ));
    }
  }
  return items;
}