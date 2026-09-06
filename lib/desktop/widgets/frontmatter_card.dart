/// Front-matter 结构化编辑面板
/// 对标 MarkText + VS Code Front Matter 插件
/// 在编辑器顶部渲染卡片式 YAML 元数据编辑区
library;

import 'package:flutter/material.dart';
import '../../../theme/app_color.dart';

/// 解析后的 Front-matter 字段
class FrontMatterData {
  final String rawYaml;
  final Map<String, String> fields;
  final int startOffset; // YAML 块在全文中的起始位置
  final int endOffset;   // YAML 块在全文中的结束位置

  const FrontMatterData({
    required this.rawYaml,
    required this.fields,
    required this.startOffset,
    required this.endOffset,
  });

  bool get hasData => fields.isNotEmpty;

  static FrontMatterData empty() => const FrontMatterData(
        rawYaml: '',
        fields: {},
        startOffset: 0,
        endOffset: 0,
      );

  /// 从全文解析 YAML Front-matter
  static FrontMatterData parse(String fullText) {
    if (fullText.isEmpty) return empty();

    // 检测 YAML front matter: 以 --- 开头
    if (!fullText.trimLeft().startsWith('---')) return empty();

    final startIdx = fullText.indexOf('---');
    final afterStart = fullText.substring(startIdx + 3);
    final endIdx = afterStart.indexOf('---');
    if (endIdx < 0) return empty();

    final yamlContent = afterStart.substring(0, endIdx).trim();
    final fields = <String, String>{};

    // 简单 YAML 解析（不依赖 yaml 包，避免引入新依赖）
    String? currentKey;
    StringBuffer currentValue = StringBuffer();

    for (final line in yamlContent.split('\n')) {
      if (line.trim().isEmpty) {
        if (currentKey != null) {
          currentValue.writeln();
        }
        continue;
      }

      // 检测新字段（不以空格开头，包含冒号）
      final colonIdx = line.indexOf(':');
      if (colonIdx > 0 && !line.startsWith(' ') && !line.startsWith('\t')) {
        // 保存上一个字段
        if (currentKey != null) {
          fields[currentKey] = currentValue.toString().trim();
        }
        currentKey = line.substring(0, colonIdx).trim();
        currentValue = StringBuffer(line.substring(colonIdx + 1).trim());
      } else if (currentKey != null) {
        // 多行值续行
        currentValue.writeln(line.trim());
      }
    }

    // 保存最后一个字段
    if (currentKey != null) {
      fields[currentKey] = currentValue.toString().trim();
    }

    return FrontMatterData(
      rawYaml: yamlContent,
      fields: fields,
      startOffset: startIdx,
      endOffset: startIdx + 3 + endIdx + 3,
    );
  }

  /// 将字段映射回 YAML 字符串
  String toYamlBlock() {
    if (fields.isEmpty) return '';
    final buf = StringBuffer('---\n');
    for (final entry in fields.entries) {
      buf.writeln('${entry.key}: ${entry.value}');
    }
    buf.write('---');
    return buf.toString();
  }
}

/// Front-matter 结构化编辑卡片
class FrontMatterCard extends StatefulWidget {
  final TextEditingController contentController;
  final VoidCallback? onChanged;
  final bool isDark;
  final Color? background;

  const FrontMatterCard({
    super.key,
    required this.contentController,
    this.onChanged,
    this.isDark = false,
    this.background,
  });

  @override
  State<FrontMatterCard> createState() => _FrontMatterCardState();
}

class _FrontMatterCardState extends State<FrontMatterCard> {
  bool _expanded = false;
  final _titleCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  final _categoriesCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  bool _isUpdating = false; // 防止循环更新

  FrontMatterData get _data => FrontMatterData.parse(widget.contentController.text);

  /// 卡片整体明暗：优先按传入 background 亮度判定，避免自定义底色与主题语义冲突
  bool get _cardIsDark {
    final bg = widget.background ?? AppColor.surfaceBase(context);
    return bg.computeLuminance() < 0.5;
  }

  @override
  void initState() {
    super.initState();
    _syncFromContent();
    widget.contentController.addListener(_onContentChanged);
  }

  @override
  void dispose() {
    widget.contentController.removeListener(_onContentChanged);
    _titleCtrl.dispose();
    _dateCtrl.dispose();
    _tagsCtrl.dispose();
    _categoriesCtrl.dispose();
    _slugCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  void _onContentChanged() {
    if (_isUpdating) return;
    _syncFromContent();
  }

  void _syncFromContent() {
    final data = _data;
    _titleCtrl.text = data.fields['title'] ?? '';
    _dateCtrl.text = data.fields['date'] ?? '';
    _tagsCtrl.text = data.fields['tags'] ?? '';
    _categoriesCtrl.text = data.fields['categories'] ?? '';
    _slugCtrl.text = data.fields['slug'] ?? '';
    _descriptionCtrl.text = data.fields['description'] ?? '';
  }

  /// 更新 YAML 块
  void _updateYamlField(String key, String value) {
    _isUpdating = true;
    final fullText = widget.contentController.text;
    final data = _data;

    if (data.hasData) {
      // 原位行级替换，保留未编辑字段的原始格式（列表/注释/多行）
      final prefix = fullText.substring(0, data.startOffset);
      final rest = fullText.substring(data.endOffset);
      final newBlock = _rewriteYamlBlock(
        data.rawYaml,
        key,
        value,
        remove: value.isEmpty,
      );
      if (newBlock.trim().isEmpty) {
        // 所有字段都被删除：移除整个 YAML 块
        widget.contentController.text = prefix + rest;
        widget.contentController.selection = TextSelection.collapsed(
          offset: prefix.length.clamp(0, fullText.length),
        );
      } else {
        final newText = '$prefix---\n$newBlock\n---\n$rest';
        widget.contentController.text = newText;
        widget.contentController.selection = TextSelection.collapsed(
          offset: (prefix.length + newBlock.length + 8).clamp(0, newText.length),
        );
      }
    } else if (value.isNotEmpty) {
      // 创建新的 YAML 块
      final newYaml = '---\n$key: $value\n---\n';
      widget.contentController.text = newYaml + fullText;
      widget.contentController.selection = TextSelection.collapsed(
        offset: newYaml.length.clamp(0, newYaml.length + fullText.length),
      );
    }

    _isUpdating = false;
    widget.onChanged?.call();
  }

  /// 在原 YAML 块内替换单个顶级字段，其余行原样保留。
  /// 支持列表值（多行 value 拆分写入，续行带缩进）。
  String _rewriteYamlBlock(
    String yamlBlock,
    String key,
    String newValue, {
    required bool remove,
  }) {
    final lines = yamlBlock.split('\n');
    final keyPattern = RegExp('^$key:');
    int? keyIdx;
    for (var i = 0; i < lines.length; i++) {
      if (keyPattern.hasMatch(lines[i])) {
        keyIdx = i;
        break;
      }
    }

    // 该 key 占用行区间：本身 + 后续缩进续行（列表项/多行值）
    int startIdx = keyIdx ?? lines.length;
    int endIdx;
    if (keyIdx != null) {
      endIdx = keyIdx + 1;
      while (endIdx < lines.length &&
          (lines[endIdx].startsWith(' ') || lines[endIdx].startsWith('\t'))) {
        endIdx++;
      }
    } else {
      endIdx = lines.length;
    }

    final before = lines.sublist(0, startIdx);
    final after = lines.sublist(endIdx);
    if (remove) return [...before, ...after].join('\n');

    final valueLines = newValue.split('\n');
    final newLines = <String>[];
    for (var i = 0; i < valueLines.length; i++) {
      final v = valueLines[i];
      if (i == 0) {
        newLines.add('$key: $v');
      } else {
        newLines.add(
          v.startsWith(' ') || v.startsWith('\t') ? v : '  $v',
        );
      }
    }
    return [...before, ...newLines, ...after].join('\n');
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final timePicked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(now),
      );
      if (timePicked != null) {
        final dt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          timePicked.hour,
          timePicked.minute,
        );
        _dateCtrl.text = _formatDate(dt);
        _updateYamlField('date', _dateCtrl.text);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = _cardIsDark;
    final data = _data;

    // 如果没有 frontmatter 且未展开，显示一个小提示
    if (!data.hasData && !_expanded) {
      return GestureDetector(
        onTap: () => setState(() => _expanded = true),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColor.surfaceHover(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColor.border(context),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.article_outlined, size: 14, color: cs.primary.withOpacity(0.6)),
              const SizedBox(width: 8),
              Text(
                '添加 Front-matter（标题、标签、分类等）',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.primary.withOpacity(0.6),
                ),
              ),
              const Spacer(),
              Icon(Icons.add, size: 14, color: cs.primary.withOpacity(0.6)),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: widget.background ?? AppColor.surfaceBase(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? cs.primary.withOpacity(0.15)
              : cs.primary.withOpacity(0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                border: _expanded
                    ? Border(
                        bottom: BorderSide(
                          color: AppColor.border(context),
                        ),
                      )
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.code, size: 12, color: cs.primary),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Front-matter',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColor.textSecondary(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'YAML 元数据',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColor.textMuted(context),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: AppColor.textMuted(context),
                  ),
                ],
              ),
            ),
          ),
          // 展开的字段
          if (_expanded)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _buildField(
                    controller: _titleCtrl,
                    label: '标题',
                    icon: Icons.title,
                    hint: '文章标题',
                    onChanged: (v) => _updateYamlField('title', v),
                    isDark: isDark,
                    cs: cs,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildField(
                          controller: _dateCtrl,
                          label: '日期',
                          icon: Icons.calendar_today,
                          hint: '2024-01-01 12:00:00',
                          onChanged: (v) => _updateYamlField('date', v),
                          isDark: isDark,
                          cs: cs,
                          suffix: GestureDetector(
                            onTap: _pickDate,
                            child: Icon(Icons.edit_calendar, size: 16, color: cs.primary.withOpacity(0.6)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 1,
                        child: _buildField(
                          controller: _slugCtrl,
                          label: 'Slug',
                          icon: Icons.link,
                          hint: 'my-post',
                          onChanged: (v) => _updateYamlField('slug', v),
                          isDark: isDark,
                          cs: cs,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildField(
                    controller: _tagsCtrl,
                    label: '标签',
                    icon: Icons.label_outline,
                    hint: 'flutter, hexo, blog（逗号分隔）',
                    onChanged: (v) => _updateYamlField('tags', v),
                    isDark: isDark,
                    cs: cs,
                  ),
                  const SizedBox(height: 10),
                  _buildField(
                    controller: _categoriesCtrl,
                    label: '分类',
                    icon: Icons.folder_outlined,
                    hint: '技术, 前端（逗号分隔）',
                    onChanged: (v) => _updateYamlField('categories', v),
                    isDark: isDark,
                    cs: cs,
                  ),
                  const SizedBox(height: 10),
                  _buildField(
                    controller: _descriptionCtrl,
                    label: '摘要',
                    icon: Icons.description_outlined,
                    hint: '文章简短描述',
                    onChanged: (v) => _updateYamlField('description', v),
                    isDark: isDark,
                    cs: cs,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
    required ValueChanged<String> onChanged,
    required bool isDark,
    required ColorScheme cs,
    Widget? suffix,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 11, color: AppColor.iconMuted(context)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: AppColor.iconMuted(context),
              ),
            ),
            if (suffix != null) ...[const Spacer(), suffix],
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: maxLines,
          onChanged: onChanged,
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: isDark ? Colors.white.withOpacity(0.85) : const Color(0xFF1F2937),
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 12,
              color: AppColor.borderStrong(context),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            filled: true,
            fillColor: isDark ? Colors.white.withOpacity(0.03) : const Color(0xFFF3F4F6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: AppColor.border(context),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: AppColor.border(context),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: cs.primary.withOpacity(0.3)),
            ),
          ),
        ),
      ],
    );
  }
}