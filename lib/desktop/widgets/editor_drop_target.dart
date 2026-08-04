/// 拖拽文件处理组件
/// 支持拖拽图片到编辑器自动上传并插入 Markdown
/// 支持拖拽 Markdown 文件到编辑器自动打开
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';

/// 拖拽目标区域包装器
/// 包裹编辑器内容区域，使整个编辑器支持拖拽文件
class EditorDropTarget extends StatefulWidget {
  final Widget child;
  final Future<String?> Function(File file)? onImageDropped;
  final Future<void> Function(String markdown)? onMarkdownInserted;
  final VoidCallback? onFileDropped;
  final bool isDark;

  const EditorDropTarget({
    super.key,
    required this.child,
    this.onImageDropped,
    this.onMarkdownInserted,
    this.onFileDropped,
    this.isDark = false,
  });

  @override
  State<EditorDropTarget> createState() => _EditorDropTargetState();
}

class _EditorDropTargetState extends State<EditorDropTarget> {
  bool _dragging = false;
  String _dragMessage = '';

  bool get _isImageFile(String path) {
    final ext = path.toLowerCase();
    return ext.endsWith('.png') ||
        ext.endsWith('.jpg') ||
        ext.endsWith('.jpeg') ||
        ext.endsWith('.gif') ||
        ext.endsWith('.webp') ||
        ext.endsWith('.bmp') ||
        ext.endsWith('.svg') ||
        ext.endsWith('.ico') ||
        ext.endsWith('.heic') ||
        ext.endsWith('.heif');
  }

  bool get _isMarkdownFile(String path) {
    final ext = path.toLowerCase();
    return ext.endsWith('.md') ||
        ext.endsWith('.markdown') ||
        ext.endsWith('.mdown') ||
        ext.endsWith('.mkd');
  }

  bool get _isTextFile(String path) {
    final ext = path.toLowerCase();
    return ext.endsWith('.txt') ||
        ext.endsWith('.csv') ||
        ext.endsWith('.json') ||
        ext.endsWith('.xml') ||
        ext.endsWith('.yaml') ||
        ext.endsWith('.yml') ||
        ext.endsWith('.html') ||
        ext.endsWith('.htm') ||
        ext.endsWith('.css') ||
        ext.endsWith('.js') ||
        ext.endsWith('.ts') ||
        ext.endsWith('.dart') ||
        ext.endsWith('.py') ||
        ext.endsWith('.java') ||
        ext.endsWith('.c') ||
        ext.endsWith('.cpp') ||
        ext.endsWith('.h') ||
        ext.endsWith('.rs') ||
        ext.endsWith('.go') ||
        ext.endsWith('.rb') ||
        ext.endsWith('.php') ||
        ext.endsWith('.sh') ||
        ext.endsWith('.bash') ||
        ext.endsWith('.zsh') ||
        ext.endsWith('.toml') ||
        ext.endsWith('.ini') ||
        ext.endsWith('.cfg') ||
        ext.endsWith('.conf');
  }

  Future<void> _handleDroppedFiles(List<DropFile> files) async {
    setState(() => _dragging = false);

    if (files.isEmpty) return;

    for (final dropFile in files) {
      final file = File(dropFile.path);
      if (!await file.exists()) continue;

      if (_isImageFile(dropFile.path)) {
        if (widget.onImageDropped != null) {
          final result = await widget.onImageDropped!(file);
          if (result != null) {
            widget.onMarkdownInserted?.call(result);
          }
        }
      } else if (_isMarkdownFile(dropFile.path)) {
        final content = await file.readAsString();
        widget.onMarkdownInserted?.call(content);
      } else if (_isTextFile(dropFile.path)) {
        final content = await file.readAsString();
        // 文本文件默认作为代码块插入
        final ext = dropFile.path.split('.').last;
        final codeBlock = '\n```$ext\n$content\n```\n';
        widget.onMarkdownInserted?.call(codeBlock);
      }
    }

    widget.onFileDropped?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return DropTarget(
      onDragDone: (detail) => _handleDroppedFiles(detail.files),
      onDragEntered: (detail) {
        setState(() {
          _dragging = true;
          if (detail.files.length == 1) {
            final path = detail.files.first.path;
            final name = path.split('/').last;
            if (_isImageFile(path)) {
              _dragMessage = '释放以插入图片: $name';
            } else if (_isMarkdownFile(path)) {
              _dragMessage = '释放以打开文件: $name';
            } else {
              _dragMessage = '释放以添加文件: $name';
            }
          } else {
            _dragMessage = '释放以添加 ${detail.files.length} 个文件';
          }
        });
      },
      onDragExited: (detail) {
        setState(() {
          _dragging = false;
          _dragMessage = '';
        });
      },
      child: Stack(
        children: [
          widget.child,
          if (_dragging)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.5),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_upload_outlined,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _dragMessage,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : const Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '支持图片、Markdown 和文本文件',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white.withOpacity(0.4) : const Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}