// 编辑器抽屉组件扩展（由 main.dart part 引入，与原类同 library，可访问私有成员）
part of '../main.dart';

extension EditorDrawerExt on _RootShellState {
  /// 可折叠功能分区（仿桌面左栏 _buildSection：箭头 + 图标 + 标题 + 内容）
  Widget _drawerSectionGroup(
    String key,
    String title,
    IconData icon, {
    required List<Widget> children,
  }) {
    if (children.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white.withOpacity(0.35) : const Color(0xFF9CA3AF);
    final collapsed = _drawerCollapsed.contains(key);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _applyState(() {
            if (collapsed) {
              _drawerCollapsed.remove(key);
            } else {
              _drawerCollapsed.add(key);
            }
          }),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Icon(
                  collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 16,
                  color: muted,
                ),
                const SizedBox(width: 4),
                Icon(icon, size: 14, color: muted),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: muted,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!collapsed) ...children,
      ],
    );
  }

  /// 抽屉文章分区内容（平铺全部文章，仿桌面左栏 _buildArticleItems）
  List<Widget> _buildDrawerArticleItems() {
    final articles = drafts
        .where((d) =>
            !SystemLogFiles.isSystemLogFileName(d.title) &&
            !SystemLogFiles.isSystemLogFileName(d.fileName()))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (articles.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.fromLTRB(24, 2, 20, 8),
          child: Text(
            '暂无文章',
            style: TextStyle(fontSize: 12, color: AppTheme.muted),
          ),
        ),
      ];
    }
    return articles.map(_drawerArticleItem).toList();
  }

  /// 最近文章列表项（抽屉平铺）
  Widget _drawerArticleItem(Article a) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _openExistingArticle(a),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 16,
                  color: AppTheme.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    a.title.isEmpty ? '(无标题)' : a.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppTheme.text),
                  ),
                ),
                if (!a.published)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '草稿',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _drawerItem(
    int page,
    IconData icon,
    String label, {
    int badge = 0,
    bool isPrimary = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final sel = _currentPage == page;
    final bgColor = sel ? cs.primary.withOpacity(0.07) : Colors.transparent;
    final fgColor = sel ? cs.primary : AppTheme.text;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _navigateTo(page),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 20, color: fgColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                      color: fgColor,
                    ),
                  ),
                ),
                if (badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? cs.primary : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '$badge',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: sel ? Colors.white : AppTheme.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _drawerAction(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppTheme.text),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppTheme.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolChip(
    IconData icon,
    String label,
    VoidCallback? onTap, {
    Color? color,
  }) {
    final c = color ?? globalTextColor;
    return Material(
      color: c.withOpacity(0.05),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: c),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: c,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}
