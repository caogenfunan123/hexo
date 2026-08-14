/// 文章长按管理菜单（桌面端 PopupMenu / 移动端底部弹层共用）
///
/// 提供统一的文章管理操作入口：重命名 / 移动到卷宗 / 导出 / 删除。
/// 桌面端弹出 PopupMenu，移动端弹出 ModalBottomSheet。
library;

import 'package:flutter/material.dart';
import '../models/article.dart';

/// 弹出文章管理菜单
///
/// [anchor] 为桌面端菜单弹出的屏幕坐标（长按点）。
/// [onRename] / [onMoveVolume] / [onExport] / [onDelete] 任一为空时对应项隐藏。
Future<void> showArticleActionMenu({
  required BuildContext context,
  required Offset anchor,
  required Article article,
  ValueChanged<Article>? onRename,
  ValueChanged<Article>? onMoveVolume,
  ValueChanged<Article>? onExport,
  ValueChanged<Article>? onDelete,
}) async {
  final isDesktop = MediaQuery.of(context).size.width >= 600;

  if (isDesktop) {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(anchor.dx, anchor.dy, anchor.dx, anchor.dy),
      items: _buildItems(article),
    );
    _dispatch(context, result, article, onRename: onRename, onMoveVolume: onMoveVolume, onExport: onExport, onDelete: onDelete);
    return;
  }

  final result = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                article.title.isEmpty ? '(无标题)' : article.title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          ..._sheetItems(ctx, article, onRename: onRename, onMoveVolume: onMoveVolume, onExport: onExport, onDelete: onDelete),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  _dispatch(context, result, article, onRename: onRename, onMoveVolume: onMoveVolume, onExport: onExport, onDelete: onDelete);
}

List<PopupMenuEntry<String>> _buildItems(Article article) {
  return [
    const PopupMenuItem(
      value: 'rename',
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.drive_file_rename_outline, size: 18),
        title: Text('重命名'),
      ),
    ),
    const PopupMenuItem(
      value: 'move',
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.drive_file_move_outline, size: 18),
        title: Text('移动到卷宗'),
      ),
    ),
    const PopupMenuItem(
      value: 'export',
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.ios_share_outlined, size: 18),
        title: Text('导出'),
      ),
    ),
    const PopupMenuItem(
      value: 'delete',
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
        title: Text('删除', style: TextStyle(color: Colors.redAccent)),
      ),
    ),
  ];
}

List<Widget> _sheetItems(
  BuildContext context,
  Article article, {
  ValueChanged<Article>? onRename,
  ValueChanged<Article>? onMoveVolume,
  ValueChanged<Article>? onExport,
  ValueChanged<Article>? onDelete,
}) {
  final items = <Widget>[];
  void add(String value, IconData icon, String label, {Color? color}) {
    items.add(ListTile(
      leading: Icon(icon, size: 20, color: color),
      title: Text(label, style: TextStyle(color: color)),
      onTap: () => Navigator.of(context).pop(value),
    ));
  }

  if (onRename != null) add('rename', Icons.drive_file_rename_outline, '重命名');
  if (onMoveVolume != null) add('move', Icons.drive_file_move_outline, '移动到卷宗');
  if (onExport != null) add('export', Icons.ios_share_outlined, '导出');
  if (onDelete != null) add('delete', Icons.delete_outline, '删除', color: Colors.redAccent);
  return items;
}

void _dispatch(
  BuildContext context,
  String? result,
  Article article, {
  ValueChanged<Article>? onRename,
  ValueChanged<Article>? onMoveVolume,
  ValueChanged<Article>? onExport,
  ValueChanged<Article>? onDelete,
}) {
  switch (result) {
    case 'rename':
      onRename?.call(article);
      break;
    case 'move':
      onMoveVolume?.call(article);
      break;
    case 'export':
      onExport?.call(article);
      break;
    case 'delete':
      onDelete?.call(article);
      break;
  }
}
