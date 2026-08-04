/// 冲突 Diff 对比 UI 组件
/// 桌面端：左右双栏对比 | 移动端：上下分栏
/// 对标：Yank Note 版本对比 UI
library;

import 'package:flutter/material.dart';
import '../../services/conflict_diff_service.dart';

/// 冲突解决方式
enum ConflictResolution {
  keepLocal,
  keepRemote,
  manualMerge,
}

/// 冲突 Diff 对比组件
class ConflictDiffView extends StatefulWidget {
  final String filePath;
  final String localContent;
  final String remoteContent;
  final String? localLabel;
  final String? remoteLabel;
  final bool isDesktop;
  final Function(ConflictResolution resolution, String? mergedContent)? onResolve;

  const ConflictDiffView({
    super.key,
    required this.filePath,
    required this.localContent,
    required this.remoteContent,
    this.localLabel,
    this.remoteLabel,
    this.isDesktop = true,
    this.onResolve,
  });

  @override
  State<ConflictDiffView> createState() => _ConflictDiffViewState();
}

class _ConflictDiffViewState extends State<ConflictDiffView> {
  late List<DiffLine> _diffLines;
  final ScrollController _localScroll = ScrollController();
  final ScrollController _remoteScroll = ScrollController();
  bool _syncScroll = true;

  @override
  void initState() {
    super.initState();
    _diffLines = ConflictDiffService.computeDiff(
      widget.localContent,
      widget.remoteContent,
    );
    // 同步滚动
    _localScroll.addListener(_onLocalScroll);
    _remoteScroll.addListener(_onRemoteScroll);
  }

  void _onLocalScroll() {
    if (_syncScroll && _remoteScroll.hasClients) {
      _remoteScroll.jumpTo(_localScroll.offset);
    }
  }

  void _onRemoteScroll() {
    if (_syncScroll && _localScroll.hasClients) {
      _localScroll.jumpTo(_remoteScroll.offset);
    }
  }

  @override
  void dispose() {
    _localScroll.removeListener(_onLocalScroll);
    _remoteScroll.removeListener(_onRemoteScroll);
    _localScroll.dispose();
    _remoteScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // 头部
        _buildHeader(isDark),
        // 对比区域
        Expanded(
          child: widget.isDesktop
              ? _buildDesktopLayout(isDark)
              : _buildMobileLayout(isDark),
        ),
        // 底部操作栏
        _buildFooter(isDark),
      ],
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252526) : const Color(0xFFF3F3F3),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF3E3E42) : const Color(0xFFE0E0E0),
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.merge_type, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '冲突对比: ${widget.filePath.split('/').last}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 同步滚动开关
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '同步滚动',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              const SizedBox(width: 4),
              SizedBox(
                height: 20,
                child: Switch(
                  value: _syncScroll,
                  onChanged: (v) => setState(() => _syncScroll = v),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(bool isDark) {
    return Row(
      children: [
        // 本地版本
        Expanded(
          child: _buildDiffPanel(
            label: widget.localLabel ?? '本地版本',
            isLocal: true,
            isDark: isDark,
            scrollController: _localScroll,
          ),
        ),
        // 分隔线
        Container(
          width: 1,
          color: isDark ? const Color(0xFF3E3E42) : const Color(0xFFE0E0E0),
        ),
        // 远程版本
        Expanded(
          child: _buildDiffPanel(
            label: widget.remoteLabel ?? '远程版本',
            isLocal: false,
            isDark: isDark,
            scrollController: _remoteScroll,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(bool isDark) {
    return Column(
      children: [
        Expanded(
          child: _buildDiffPanel(
            label: widget.localLabel ?? '本地版本',
            isLocal: true,
            isDark: isDark,
            scrollController: _localScroll,
          ),
        ),
        Container(
          height: 1,
          color: isDark ? const Color(0xFF3E3E42) : const Color(0xFFE0E0E0),
        ),
        Expanded(
          child: _buildDiffPanel(
            label: widget.remoteLabel ?? '远程版本',
            isLocal: false,
            isDark: isDark,
            scrollController: _remoteScroll,
          ),
        ),
      ],
    );
  }

  Widget _buildDiffPanel({
    required String label,
    required bool isLocal,
    required bool isDark,
    required ScrollController scrollController,
  }) {
    return Column(
      children: [
        // 面板标签
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: isLocal
              ? (isDark ? const Color(0xFF1A3A2A) : const Color(0xFFE8F5E9))
              : (isDark ? const Color(0xFF2A1A3A) : const Color(0xFFE3F2FD)),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isLocal
                  ? (isDark ? const Color(0xFF4CAF50) : const Color(0xFF2E7D32))
                  : (isDark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0)),
            ),
          ),
        ),
        // Diff 行
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            itemCount: _diffLines.length,
            itemBuilder: (context, index) {
              final line = _diffLines[index];
              if (isLocal && line.operation == DiffOperation.insert) {
                return const SizedBox(height: 20); // 占位
              }
              if (!isLocal && line.operation == DiffOperation.delete) {
                return const SizedBox(height: 20); // 占位
              }
              return _buildDiffLine(line, isDark);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDiffLine(DiffLine line, bool isDark) {
    Color bgColor;
    Color? borderColor;
    String prefix;

    switch (line.operation) {
      case DiffOperation.insert:
        bgColor = isDark ? const Color(0xFF1A3A2A) : const Color(0xFFE8F5E9);
        borderColor = isDark ? const Color(0xFF4CAF50) : const Color(0xFF66BB6A);
        prefix = '+ ';
        break;
      case DiffOperation.delete:
        bgColor = isDark ? const Color(0xFF3A1A1A) : const Color(0xFFFFEBEE);
        borderColor = isDark ? const Color(0xFFEF5350) : const Color(0xFFEF9A9A);
        prefix = '- ';
        break;
      case DiffOperation.replace:
        bgColor = isDark ? const Color(0xFF2A2A1A) : const Color(0xFFFFF8E1);
        borderColor = isDark ? const Color(0xFFFFCA28) : const Color(0xFFFFE082);
        prefix = '~ ';
        break;
      case DiffOperation.equal:
        bgColor = Colors.transparent;
        prefix = '  ';
        break;
      default:
        bgColor = Colors.transparent;
        prefix = '  ';
    }

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 行号
          SizedBox(
            width: 40,
            child: Text(
              '${line.lineNumber}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: isDark ? Colors.white.withOpacity(0.3) : Colors.grey.shade500,
                height: 1.5,
              ),
            ),
          ),
          // 变更指示器
          if (borderColor != null)
            Container(
              width: 3,
              margin: const EdgeInsets.only(right: 4),
              color: borderColor,
            )
          else
            const SizedBox(width: 7),
          // 内容
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: isDark ? Colors.white : Colors.black87,
                  height: 1.5,
                ),
                children: [
                  TextSpan(
                    text: prefix,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: line.operation == DiffOperation.insert
                          ? const Color(0xFF4CAF50)
                          : line.operation == DiffOperation.delete
                              ? const Color(0xFFEF5350)
                              : null,
                    ),
                  ),
                  TextSpan(text: line.content),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252526) : const Color(0xFFF3F3F3),
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF3E3E42) : const Color(0xFFE0E0E0),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton.icon(
            onPressed: () => widget.onResolve?.call(ConflictResolution.keepRemote, null),
            icon: const Icon(Icons.cloud_download, size: 16),
            label: const Text('保留远程'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => widget.onResolve?.call(ConflictResolution.manualMerge, null),
            icon: const Icon(Icons.merge, size: 16),
            label: const Text('手动合并'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => widget.onResolve?.call(ConflictResolution.keepLocal, null),
            icon: const Icon(Icons.laptop, size: 16),
            label: const Text('保留本地'),
          ),
        ],
      ),
    );
  }
}