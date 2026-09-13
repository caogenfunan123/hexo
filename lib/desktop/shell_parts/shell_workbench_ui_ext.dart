// 工作台编辑区 UI扩展（desktop_shell.dart 的 part，与主类同 library，可访问私有成员）。
// 由 desktop_shell.dart 拆分而来（修复1），方法体保持零变更；
// setState 经宿主 _applyState 包装调用。
part of '../desktop_shell.dart';

extension DesktopShellWorkbenchUiExt on DesktopShellState {
  Widget _buildEmbeddedEditor() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 预览排版：行高 1.6，段落间距收紧（MarkText 式紧凑阅读）
    final previewStyle = createUnifiedMarkdownStyle(
      context: context,
      baseFontSize: 16,
      lineHeight: 1.6,
    ).copyWith(pPadding: const EdgeInsets.symmetric(vertical: 2));

    // 背景层：自定义壁纸 / 纯色（写作界面全屏背景）
    final Widget bgLayer;
    if (_deskUseWallpaper) {
      bgLayer = Image.file(
        File(_deskEditorTheme.wallpaperPath),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => ColoredBox(color: _deskBgColor),
      );
    } else {
      bgLayer = ColoredBox(color: _deskBgColor);
    }

    return Stack(
      children: [
        Positioned.fill(child: bgLayer),
        Column(
          children: [
            // ── 顶栏（固定：标题 + 元数据开关 + 工具栏） ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 标题（预览态隐藏：标题改到右侧属性抽屉编辑） ──
                  if (_splitEditorMode != SplitEditorMode.previewOnly)
                    _editorCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: TextField(
                        controller: _doc.titleCtrl,
                        decoration: const InputDecoration(
                          labelText: '文章标题',
                          prefixIcon: Icon(Icons.title, size: 19),
                          prefixIconConstraints: BoxConstraints(
                            minWidth: 30,
                            minHeight: 30,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 6),
                        ),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                        onChanged: (_) {
                          _onContentChanged();
                          _doc.refreshUi();
                          // 更新打字机光标位置
                          final text = _doc.contentCtrl.text;
                          final cursorPos =
                              _doc.contentCtrl.selection.baseOffset;
                          final textBefore = text.substring(
                            0,
                            cursorPos.clamp(0, text.length),
                          );
                          final currentLine = '\n'
                              .allMatches(textBefore)
                              .length;
                          final totalLines = '\n'.allMatches(text).length + 1;
                          _typewriterCtrl.updateCursorPosition(
                            currentLine,
                            totalLines,
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  // 元数据折叠开关
                  Align(
                    alignment: Alignment.centerLeft,
                    // canRequestFocus=false：点击展开/收起不抢编辑器键盘焦点，
                    // 抽屉输入过程中编辑器光标与选区保持不变
                    child: Focus(
                      canRequestFocus: false,
                      child: TextButton.icon(
                        onPressed: () => _applyState(
                          () => _showEditorMeta = !_showEditorMeta,
                        ),
                        icon: Icon(
                          _showEditorMeta
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 16,
                        ),
                        label: Text(_showEditorMeta ? '收起文章属性' : '展开文章属性'),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            // ── 工具栏（预览/所见即所得态隐藏：WYSIWYG 有自己的行内操作，
            //    且源码选区操作对富文本光标无意义） ──
            if (_splitEditorMode != SplitEditorMode.previewOnly &&
                _splitEditorMode != SplitEditorMode.wysiwyg)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListenableBuilder(
                  listenable: _editor,
                  builder: (context, child) => _editorCard(
                    padding: const EdgeInsets.all(8),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 8,
                      children: [..._buildToolChips()],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),

            // ── 元数据面板（折叠收纳，220ms 缓动展开，不挤占编辑器区域） ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: _showEditorMeta
                    ? ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: _metaPanelMaxHeight(context),
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── 仓库选择器 ──
                              if (repos.isNotEmpty)
                                _editorCard(
                                  child: DropdownButtonFormField<String>(
                                    value: _editorRepo?.id,
                                    decoration: const InputDecoration(
                                      labelText: '目标仓库',
                                      prefixIcon: Icon(
                                        Icons.storage_outlined,
                                        size: 19,
                                      ),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      isDense: true,
                                      filled: false,
                                    ),
                                    items: repos
                                        .map(
                                          (r) => DropdownMenuItem(
                                            value: r.id,
                                            child: Text(
                                              '${r.name} (${r.fullName})',
                                              style: const TextStyle(
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) => _applyState(() {
                                      final match = repos
                                          .where((e) => e.id == v)
                                          .firstOrNull;
                                      if (match != null) _editorRepo = match;
                                    }),
                                  ),
                                ),
                              const SizedBox(height: 16),
                              // ── 文章属性（front matter，可折叠） ──
                              _buildFrontMatterPanel(templates),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            // ── 正文编辑区（双栏 Markdown 编辑器，占满剩余高度） ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DesktopSplitEditor(
                  contentController: _doc.contentCtrl,
                  focusNode: _doc.contentFocus,
                  onChanged: () {
                    _onContentChanged();
                    // 更新打字机光标位置
                    final text = _doc.contentCtrl.text;
                    final cursorPos = _doc.contentCtrl.selection.baseOffset;
                    final textBefore = text.substring(
                      0,
                      cursorPos.clamp(0, text.length),
                    );
                    final currentLine = '\n'.allMatches(textBefore).length;
                    final totalLines = '\n'.allMatches(text).length + 1;
                    _typewriterCtrl.updateCursorPosition(
                      currentLine,
                      totalLines,
                    );
                  },
                  fontSize: _editor.editorFontSize,
                  lineHeight: _editor.editorLineHeight,
                  fontFamily: 'monospace',
                  isDark: isDark,
                  colorScheme: cs,
                  editorTextColor: _deskCustomBg ? _deskTextColor : null,
                  backgroundColor: _deskCustomBg
                      ? _deskCardBg
                      : AppColor.surfaceRaised(context),
                  initialSplitRatio: _splitEditorRatio,
                  // 分栏拖拽是连续回调：只记值供下次恢复，绝不能整壳 setState
                  // （曾导致拖拽期间每像素一次全壳重建 = 卡顿主因之一）
                  onSplitRatioChanged: (r) => _splitEditorRatio = r,
                  styleSheet: previewStyle,
                  initialMode: _splitEditorMode,
                  // 模式切换保留整壳刷新：工具栏显隐依赖该状态（单击一次，可接受）
                  onModeChanged: (mode) {
                    _applyState(() => _splitEditorMode = mode);
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListenableBuilder(
                listenable: _editor,
                builder: (context, child) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_editor.editorStatus != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            if (_editor.editorBusy)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: cs.primary,
                                  ),
                                ),
                              ),
                            Text(
                              _editor.editorStatus!,
                              style: TextStyle(
                                color: _editor.editorBusy
                                    ? cs.primary
                                    : cs.outline,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    // ── 底部操作栏 ──
                    Row(
                      children: [
                        // 导出下拉菜单
                        PopupMenuButton<String>(
                          tooltip: '导出',
                          offset: const Offset(0, -8),
                          enabled: !_editor.editorBusy,
                          icon: const Icon(
                            Icons.file_download_outlined,
                            size: 18,
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: 13,
                              horizontal: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'html',
                              child: ListTile(
                                leading: Icon(Icons.html),
                                title: Text('导出 HTML'),
                                dense: true,
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'pdf',
                              child: ListTile(
                                leading: Icon(Icons.picture_as_pdf),
                                title: Text('导出 PDF'),
                                dense: true,
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'md',
                              child: ListTile(
                                leading: Icon(Icons.description),
                                title: Text('导出 Markdown'),
                                dense: true,
                              ),
                            ),
                          ],
                          onSelected: (v) {
                            switch (v) {
                              case 'html':
                                _exportHtml();
                                break;
                              case 'pdf':
                                _exportPdf();
                                break;
                              case 'md':
                                _saveMdBackup();
                                break;
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        if (_editor.failedImageBytes != null) ...[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _editor.editorBusy
                                  ? null
                                  : _retryUploadImage,
                              icon: const Icon(
                                Icons.refresh,
                                size: 18,
                                color: Colors.orange,
                              ),
                              label: const Text(
                                '重试上传',
                                style: TextStyle(color: Colors.orange),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                side: const BorderSide(color: Colors.orange),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _editor.editorBusy ? null : _saveLocal,
                            icon: const Icon(Icons.save_outlined, size: 18),
                            label: const Text('存草稿'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: _editor.editorBusy
                                ? null
                                : _handlePublish,
                            icon: const Icon(
                              Icons.cloud_upload_outlined,
                              size: 18,
                            ),
                            label: const Text('发布'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  double _metaPanelMaxHeight(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final upper = h * 0.6;
    if (upper <= 120) return upper;
    return math.max(120.0, math.min(upper, h - 320));
  }

  Widget _editorCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
    bool transparent = false,
  }) {
    final cardColor = transparent
        ? Colors.transparent
        : (_deskCustomBg ? _deskCardBg : AppColor.surfaceRaised(context));
    return Card(
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColor.border(context)),
      ),
      color: cardColor,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(12),
        child: child,
      ),
    );
  }

  String _frontMatterSummary() {
    final parts = <String>[];
    final t = _doc.titleCtrl.text.trim();
    if (t.isNotEmpty) parts.add('title: $t');
    final tags = _doc.tagsCtrl.text.trim();
    if (tags.isNotEmpty) {
      final ts = tags
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(', ');
      parts.add('tags: [$ts]');
    }
    final cats = _doc.categoriesCtrl.text.trim();
    if (cats.isNotEmpty) {
      final cs2 = cats
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(', ');
      parts.add('categories: [$cs2]');
    }
    final cover = _doc.coverCtrl.text.trim();
    if (cover.isNotEmpty) parts.add('cover: $cover');
    final tmpl = _doc.selectedTemplateId;
    if (tmpl != null && tmpl.isNotEmpty) parts.add('template: $tmpl');
    return parts.isEmpty ? '未设置元数据' : parts.join('  ');
  }

  Widget _buildFrontMatterPanel(List<TemplateItem> templates) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: _doc,
      builder: (context, _) => _editorCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => _applyState(
                () => _frontMatterExpanded = !_frontMatterExpanded,
              ),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.data_object, size: 15, color: cs.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Front Matter',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColor.textSecondary(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _frontMatterSummary(),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                          color: AppColor.textSecondary(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _frontMatterExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: AppColor.textSecondary(context),
                    ),
                  ],
                ),
              ),
            ),
            if (_frontMatterExpanded) ...[
              const Divider(height: 8),
              const SizedBox(height: 12),
              // ── 模板（最高频：置顶） ──
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      // 值必须是当前类型过滤后的可选项，否则触发断言：
                      // 切换文章类型后 _autoSelectTemplate 提前返回会留下失效模板 id
                      value:
                          templates
                              .where(
                                (t) =>
                                    t.isPost ==
                                    (_doc.articleType == ArticleType.post),
                              )
                              .any((t) => t.id == _doc.selectedTemplateId)
                          ? _doc.selectedTemplateId
                          : null,
                      decoration: const InputDecoration(
                        labelText: '模板',
                        prefixIcon: Icon(Icons.view_quilt_outlined, size: 19),
                        prefixIconConstraints: BoxConstraints(
                          minWidth: 30,
                          minHeight: 30,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        isDense: true,
                        filled: false,
                        contentPadding: EdgeInsets.symmetric(vertical: 6),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('无模板', style: TextStyle(fontSize: 13)),
                        ),
                        ...templates
                            .where(
                              (t) =>
                                  t.isPost ==
                                  (_doc.articleType == ArticleType.post),
                            )
                            .map(
                              (t) => DropdownMenuItem<String>(
                                value: t.id,
                                child: Text(
                                  '${t.isBuiltin ? "[内置] " : ""}${t.name}',
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                      ],
                      onChanged: (v) => _doc.setSelectedTemplateId(v),
                    ),
                  ),
                  IconButton(
                    tooltip: '设为本仓库默认模板',
                    onPressed:
                        _editorRepo != null && _doc.selectedTemplateId != null
                        ? () => _setAsRepoDefault(_doc.selectedTemplateId!)
                        : null,
                    icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(2),
                  ),
                  IconButton(
                    tooltip: '管理模板',
                    onPressed: () => _showTemplateManager(),
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(2),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // ── 类型 ──
              Row(
                children: [
                  _fmTypePill('博文', ArticleType.post, Icons.article_outlined),
                  const SizedBox(width: 6),
                  _fmTypePill('页面', ArticleType.page, Icons.web_outlined),
                ],
              ),
              // 预览态标题改由右侧属性抽屉编辑，属性面板内不再重复
              if (_splitEditorMode != SplitEditorMode.previewOnly) ...[
                const SizedBox(height: 16),
                _fmField(label: '标题', icon: Icons.title, ctrl: _doc.titleCtrl),
              ],
              const SizedBox(height: 16),
              _fmField(
                label: '分类',
                icon: Icons.folder_outlined,
                ctrl: _doc.categoriesCtrl,
                hint: '逗号分隔',
              ),
              const SizedBox(height: 16),
              _fmField(
                label: '标签',
                icon: Icons.tag,
                ctrl: _doc.tagsCtrl,
                hint: '逗号分隔',
              ),
              if (_editorRepo != null) ...[
                const SizedBox(height: 16),
                Text(
                  '框架: ${BlogFramework.byId(_editorRepo!.frameworkId)?.name ?? _editorRepo!.frameworkId} | '
                  '文件名: ${_doc.articleType == ArticleType.page ? '无日期前缀' : (_editorRepo!.fileNameRule.postDatePrefix ? '自动加日期' : '纯标题')}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColor.textSecondary(context),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _fmTypePill(String label, ArticleType type, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    final active = _doc.articleType == type;
    return GestureDetector(
      onTap: () {
        _doc.setArticleType(type);
        _autoSelectTemplate();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? cs.primary.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? cs.primary : AppColor.border(context),
            width: active ? 1.2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: active ? cs.primary : AppColor.textSecondary(context),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: active ? cs.primary : AppColor.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fmField({
    required String label,
    required IconData icon,
    required TextEditingController ctrl,
    String? hint,
  }) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: ctrl,
      style: const TextStyle(fontSize: 13.5),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 30,
          minHeight: 30,
        ),
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: cs.primary, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
      onChanged: (_) {
        _onContentChanged();
        _doc.refreshUi();
      },
    );
  }

  List<Widget> _buildToolChips() {
    return [
      _toolChip(Icons.format_bold, '粗体', () => _wrap('**', '**', p: '粗体')),
      _toolChip(Icons.format_italic, '斜体', () => _wrap('*', '*', p: '斜体')),
      _toolChip(Icons.code, '行内码', () => _wrap('`', '`', p: 'code')),
      _toolChip(Icons.code_off, '代码块', _insertCodeBlock),
      _toolChip(Icons.title, 'H1', () => _insertHeading(1)),
      _toolChip(Icons.title, 'H2', () => _insertHeading(2)),
      _toolChip(Icons.format_list_bulleted, '列表', () => _insertList('- ')),
      _toolChip(Icons.format_quote, '引用', () => _insertList('> ')),
      _toolChip(Icons.link, '链接', () => _wrap('[', '](https://)', p: '链接文字')),
      _toolChip(
        Icons.grid_on,
        '表格',
        () => _insertText('\n| 列1 | 列2 |\n| --- | --- |\n| 值1 | 值2 |\n'),
      ),
      _toolChip(Icons.horizontal_rule, '分割线', () => _insertText('\n---\n')),
      _toolChip(
        Icons.format_strikethrough,
        '删除线',
        () => _wrap('~~', '~~', p: '删除文字'),
      ),
      _toolChip(Icons.checklist, '任务', () => _insertList('- [ ] ')),
      _toolChip(Icons.more_horiz, 'more', () => _insertText('\n<!--more-->\n')),
      _toolChip(
        Icons.image_outlined,
        '图床',
        _editor.editorBusy ? null : _insertImage,
      ),
      _moreToolsChip(),
    ];
  }

  Widget _moreToolsChip() {
    final busy = _editor.editorBusy;
    return PopupMenuButton<String>(
      tooltip: '更多工具',
      enabled: !busy,
      onSelected: (value) {
        switch (value) {
          case 'batch_images':
            _batchInsertImages();
          case 'ai_polish':
            _aiAction('polish');
          case 'ai_continue':
            _aiAction('continue');
          case 'ai_summary':
            _aiAction('summary');
          case 'ai_code':
            _aiAction('code');
          case 'ai_rewrite':
            _aiAction('rewrite');
          case 'ai_format':
            _aiAction('format');
          case 'ai_chat':
            _showAgentWorkbench();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'batch_images',
          child: Row(
            children: [
              Icon(Icons.collections_outlined, size: 16),
              SizedBox(width: 8),
              Text('批量图床'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'ai_polish',
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: Colors.purple),
              SizedBox(width: 8),
              Text('AI 润色'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'ai_continue',
          child: Row(
            children: [
              Icon(Icons.edit_note, size: 16, color: Colors.purple),
              SizedBox(width: 8),
              Text('AI 续写'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'ai_summary',
          child: Row(
            children: [
              Icon(Icons.summarize_outlined, size: 16, color: Colors.purple),
              SizedBox(width: 8),
              Text('AI 摘要'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'ai_code',
          child: Row(
            children: [
              Icon(Icons.developer_mode, size: 16, color: Colors.purple),
              SizedBox(width: 8),
              Text('AI 代码'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'ai_rewrite',
          child: Row(
            children: [
              Icon(Icons.sync_alt, size: 16, color: Colors.purple),
              SizedBox(width: 8),
              Text('AI 改写'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'ai_format',
          child: Row(
            children: [
              Icon(Icons.auto_fix_high, size: 16, color: Colors.deepPurple),
              SizedBox(width: 8),
              Text('AI 排版'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'ai_chat',
          child: Row(
            children: [
              Icon(Icons.chat, size: 16, color: Colors.deepPurple),
              SizedBox(width: 8),
              Text('AI 对话'),
            ],
          ),
        ),
      ],
      child: Builder(
        builder: (context) {
          final cs = Theme.of(context).colorScheme;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_circle_outline,
                  size: 16,
                  color: cs.onSurface.withOpacity(0.7),
                ),
                const SizedBox(width: 4),
                Text(
                  '更多',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _toolChip(
    IconData icon,
    String label,
    VoidCallback? onTap, {
    Color? color,
  }) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.onSurface;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: c.withOpacity(onTap == null ? 0.3 : 0.7),
              ),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: c.withOpacity(onTap == null ? 0.3 : 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
