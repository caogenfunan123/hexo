import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/backup_restore_service.dart';

/// 数据备份与恢复面板
///
/// 将全部本地数据（设置/仓库/草稿/模板/片段/站点/写作统计）导出为单个存档文件，
/// 或从存档恢复。支持本地文件系统与（可选）WebDAV 目录。
class BackupRestoreScreen extends StatefulWidget {
  final Future<Directory> Function() rootProvider;
  final void Function(String message)? onToast;

  const BackupRestoreScreen({
    super.key,
    required this.rootProvider,
    this.onToast,
  });

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  bool _busy = false;
  String _lastExportPath = '';
  int _lastFileCount = 0;
  int _lastBytes = 0;

  BackupRestoreService? _service;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    try {
      final root = await widget.rootProvider();
      if (mounted) setState(() => _service = BackupRestoreService(root));
    } catch (e) {
      _toast('初始化备份服务失败: $e');
    }
  }

  Future<void> _export() async {
    final svc = _service;
    if (svc == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await svc.exportAll();

      // 默认保存目录：文档目录
      Directory? docs;
      try {
        docs = await getApplicationDocumentsDirectory();
      } catch (_) {
        docs = null;
      }
      final defaultName =
          'hexo_blog_backup_${_stamp(DateTime.now())}.json';

      final String? savePath;
      try {
        savePath = await FilePicker.platform.saveFile(
          dialogTitle: '导出数据备份',
          fileName: defaultName,
          initialDirectory: docs?.path,
          bytes: bytes,
        );
      } catch (e) {
        _toast('导出保存失败: $e');
        return;
      }

      if (savePath == null || savePath.isEmpty) {
        _toast('已取消导出');
        return;
      }
      final path = savePath;
      final f = File(path);
      await f.writeAsBytes(bytes, flush: true);
      if (mounted) {
        setState(() {
          _lastExportPath = path;
          _lastBytes = bytes.length;
        });
      }
      _toast('备份已导出到 $path');
    } catch (e) {
      _toast('导出失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final svc = _service;
    if (svc == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认恢复'),
        content: const Text(
            '恢复将覆盖当前全部本地数据（设置/仓库/草稿/模板/片段/站点）。建议先执行一次导出备份。确定继续？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('恢复')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final bytes = await File(path).readAsBytes();
      final res = await svc.restore(bytes);
      final msg = res.hasErrors
          ? '恢复完成：成功 ${res.restored} 项，失败 ${res.errors.length} 项\n${res.errors.take(3).join('\n')}'
          : '恢复完成：共恢复 ${res.restored} 项数据';
      if (mounted) {
        setState(() => _lastFileCount = res.restored);
      }
      _toast(msg);
    } catch (e) {
      _toast('恢复失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _stamp(DateTime dt) =>
      '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}_'
      '${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}';

  void _toast(String message) {
    if (!mounted) return;
    widget.onToast?.call(message);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('数据备份与恢复',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface)),
            const Spacer(),
            if (_busy)
              const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
        const SizedBox(height: 4),
        Text('导出全部本地数据为单个存档，或从存档恢复。包含设置、仓库、草稿、模板、片段、站点任务与写作统计。',
            style: TextStyle(fontSize: 12.5, color: cs.outline)),
        const SizedBox(height: 20),
        // ── 导出 ──
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.save_alt, size: 20, color: cs.primary),
                  const SizedBox(width: 10),
                  Text('导出备份',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface)),
                ]),
                const SizedBox(height: 8),
                Text('将全部数据打包为一个 JSON 存档文件，可保存到本地或迁移到新设备。',
                    style: TextStyle(fontSize: 12.5, color: cs.outline)),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: Text(_busy ? '正在导出...' : '导出到本地文件'),
                    onPressed: _busy ? null : _export,
                  ),
                ),
                if (_lastExportPath.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('上次导出：$_lastExportPath',
                            style: TextStyle(fontSize: 11.5, color: cs.outline)),
                        Text('大小：${(_lastBytes / 1024).toStringAsFixed(1)} KB',
                            style: TextStyle(fontSize: 11.5, color: cs.outline)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        // ── 恢复 ──
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.restore, size: 20, color: const Color(0xFFF59E0B)),
                  const SizedBox(width: 10),
                  Text('从备份恢复',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface)),
                ]),
                const SizedBox(height: 8),
                Text('选择一个之前导出的存档文件，恢复全部数据。恢复会覆盖当前本地数据。',
                    style: TextStyle(fontSize: 12.5, color: cs.outline)),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: Text(_busy ? '正在恢复...' : '从文件恢复'),
                    onPressed: _busy ? null : _restore,
                  ),
                ),
                if (_lastFileCount > 0) ...[
                  const SizedBox(height: 10),
                  Text('上次恢复：$_lastFileCount 项数据',
                      style: TextStyle(fontSize: 11.5, color: cs.outline)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        // ── 备份范围说明 ──
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('备份范围',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
                const SizedBox(height: 10),
                _includeRow(context, Icons.settings_outlined, '应用设置'),
                _includeRow(context, Icons.storage_outlined, '站点仓库配置'),
                _includeRow(context, Icons.drafts_outlined, '全部草稿'),
                _includeRow(context, Icons.view_quilt_outlined, '文章模板'),
                _includeRow(context, Icons.content_paste, '片段素材库'),
                _includeRow(context, Icons.dns_outlined, '站点任务与附件'),
                _includeRow(context, Icons.insights_outlined, '写作统计记录'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _includeRow(BuildContext context, IconData icon, String label) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icon, size: 16, color: cs.outline),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 12.5, color: cs.onSurface)),
        const Spacer(),
        Icon(Icons.check_circle, size: 15, color: Colors.green.shade400),
      ]),
    );
  }
}
