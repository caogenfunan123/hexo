// 编辑器 UI 构建扩展（由 main.dart part 引入，与原类同 library，可访问私有成员）
part of '../main.dart';

extension EditorUiExt on _RootShellState {
  /// 全屏专注模式：隐藏所有 UI 元素，只保留编辑器
  Widget _buildFocusMode() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0D1117)
          : const Color(0xFFF8F6F0),
      body: SafeArea(
        child: Stack(
          children: [
            // 主编辑区 — 居中、干净
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 60),
              child: TextField(
                controller: _doc.contentCtrl,
                focusNode: _doc.contentFocus,
                minLines: null,
                maxLines: null,
                expands: true,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                onChanged: (_) {
                  _onContentChanged();
                  final text = _doc.contentCtrl.text;
                  final cursorPos = _doc.contentCtrl.selection.baseOffset;
                  final textBefore = text.substring(
                    0,
                    cursorPos.clamp(0, text.length),
                  );
                  final currentLine = '\n'.allMatches(textBefore).length;
                  final totalLines = '\n'.allMatches(text).length + 1;
                  _typewriterCtrl.updateCursorPosition(currentLine, totalLines);
                },
                decoration: InputDecoration(
                  hintText: '专注写作...',
                  hintStyle: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white24 : Colors.black26,
                    fontWeight: FontWeight.w300,
                  ),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                style: TextStyle(
                  fontSize: 17,
                  height: 1.8,
                  fontFamily: 'monospace',
                  color: isDark
                      ? const Color(0xFFE6EDF3)
                      : const Color(0xFF1A1A2E),
                  fontWeight: FontWeight.w400,
                ),
                cursorColor: isDark
                    ? const Color(0xFF58A6FF)
                    : const Color(0xFF1A6DB5),
                cursorWidth: 2.5,
              ),
            ),

            // 底部状态栏：字数
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  '${_editor.wordCount} 字',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white24 : Colors.black26,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),
            ),

            // 顶部退出按钮
            Positioned(
              top: 4,
              right: 8,
              child: Material(
                color: Colors.transparent,
                child: IconButton(
                  icon: Icon(
                    Icons.fullscreen_exit,
                    color: isDark ? Colors.white38 : Colors.black38,
                    size: 22,
                  ),
                  tooltip: '退出专注模式',
                  onPressed: () => _applyState(() => _focusModeEnabled = false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _appBarAction({
    required IconData icon,
    required String tooltip,
    Color? color,
    VoidCallback? onTap,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, color: color ?? AppTheme.muted, size: 21),
      onPressed: onTap,
      style: IconButton.styleFrom(foregroundColor: color ?? AppTheme.muted),
    );
  }

  /// 极简顶部标识：仅保留当前站点小圆点，不显示「写文章」文字
  Widget _buildEditorAppBarTitle(ColorScheme cs) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: globalTextColor,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }

  /// 工具箱抽屉：静态博客类型 / 目标仓库 / 博文页面设置 / 模板配置 / 标签分类 / 封面 URL
  void _showEditorToolbox() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDynamic = siteManager.isDynamicSite;
          final siteName = settings.siteName.isNotEmpty
              ? settings.siteName
              : '未命名站点';
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 头部 ──
                  Row(
                    children: [
                      Icon(
                        Icons.handyman_outlined,
                        color: cs.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '工具箱',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '当前站点: $siteName',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  if (_failedImageBytes != null) ...[
                    const SizedBox(height: 10),
                    Material(
                      color: Colors.orange.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          Navigator.pop(ctx);
                          _retryUploadImage();
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.refresh,
                                size: 18,
                                color: Colors.orange,
                              ),
                              SizedBox(width: 8),
                              Text(
                                '重试上传失败的图片',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // ── 1. 静态博客类型切换 ──
                  _toolboxSectionTitle('静态博客类型'),
                  _toolboxSectionBody(
                    child: Row(
                      children: [
                        Expanded(
                          child: _toolboxTypeChip(
                            icon: Icons.article_outlined,
                            label: '博文',
                            active:
                                !isDynamic &&
                                _doc.articleType == ArticleType.post,
                            onTap: () => setSheetState(() {
                              _doc.setArticleType(ArticleType.post);
                              _autoSelectTemplate();
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _toolboxTypeChip(
                            icon: Icons.web_outlined,
                            label: '页面',
                            active:
                                !isDynamic &&
                                _doc.articleType == ArticleType.page,
                            onTap: () => setSheetState(() {
                              _doc.setArticleType(ArticleType.page);
                              _autoSelectTemplate();
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── 2. 目标仓库配置 ──
                  _toolboxSectionTitle('目标仓库配置'),
                  _toolboxSectionBody(
                    child: DropdownButtonFormField<String>(
                      value: _editorRepo?.id,
                      decoration: const InputDecoration(
                        labelText: '目标仓库',
                        prefixIcon: Icon(Icons.storage_outlined, size: 18),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      items: repos
                          .map(
                            (r) => DropdownMenuItem(
                              value: r.id,
                              child: Text(
                                '${r.name} (${r.fullName})',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => _applyState(() {
                        _editorRepo = repos.firstWhere((e) => e.id == v);
                        _doc.setEditorRepoId(v);
                      }),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── 3. 博文页面设置（站点切换） ──
                  _toolboxSectionTitle('博文页面设置'),
                  _toolboxSectionBody(
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: siteManager.activeSiteId,
                            decoration: InputDecoration(
                              labelText: '当前站点',
                              prefixIcon: Icon(
                                isDynamic
                                    ? Icons.dns_outlined
                                    : Icons.storage_outlined,
                                size: 18,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            isExpanded: true,
                            style: TextStyle(fontSize: 13, color: cs.onSurface),
                            items: siteManager.allSites.map((site) {
                              final typeLabel = site.isDynamic ? 'CMS' : '静态';
                              return DropdownMenuItem<String>(
                                value: site.id,
                                child: Text(
                                  '${site.name}  [$typeLabel]',
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: _editorBusy ? null : _onSiteChanged,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.settings_outlined,
                            size: 20,
                            color: cs.outline,
                          ),
                          onPressed: _editorBusy
                              ? null
                              : () {
                                  Navigator.pop(ctx);
                                  _openSiteManagement();
                                },
                          tooltip: '管理站点',
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── 4. 模板博文配置 ──
                  _toolboxSectionTitle('模板博文配置'),
                  _toolboxSectionBody(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _doc.selectedTemplateId,
                                decoration: InputDecoration(
                                  labelText:
                                      '模板 (${_doc.articleType == ArticleType.post ? '博文' : '页面'})',
                                  prefixIcon: const Icon(
                                    Icons.view_quilt_outlined,
                                    size: 18,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                items: [
                                  const DropdownMenuItem<String>(
                                    value: null,
                                    child: Text(
                                      '无模板',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  ...templates
                                      .where(
                                        (t) =>
                                            t.isPost ==
                                            (_doc.articleType ==
                                                ArticleType.post),
                                      )
                                      .map(
                                        (t) => DropdownMenuItem<String>(
                                          value: t.id,
                                          child: Text(
                                            '${t.isBuiltin ? "[内置] " : ""}${t.name}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                ],
                                onChanged: (v) => _applyState(
                                  () => _doc.setSelectedTemplateId(v),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '设为本仓库默认模板',
                              onPressed:
                                  _editorRepo != null &&
                                      _doc.selectedTemplateId != null
                                  ? () => _setAsRepoDefault(
                                      _doc.selectedTemplateId!,
                                    )
                                  : null,
                              icon: const Icon(
                                Icons.bookmark_add_outlined,
                                size: 18,
                              ),
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(4),
                            ),
                            IconButton(
                              tooltip: '管理模板',
                              onPressed: () => _showTemplateManager(),
                              icon: const Icon(
                                Icons.settings_outlined,
                                size: 18,
                              ),
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(4),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '小字提示：默认模板可在「博文」或「页面」下分别设置，发布时自动套用所选模板生成 front-matter。',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── 5. 标签、分类管理 ──
                  _toolboxSectionTitle('标签、分类管理'),
                  _toolboxSectionBody(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _doc.tagsCtrl,
                            decoration: const InputDecoration(
                              labelText: '标签',
                              prefixIcon: Icon(Icons.tag, size: 18),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _doc.categoriesCtrl,
                            decoration: const InputDecoration(
                              labelText: '分类',
                              prefixIcon: Icon(Icons.folder_outlined, size: 18),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── 6. 封面 URL ──
                  _toolboxSectionTitle('封面图 URL'),
                  _toolboxSectionBody(
                    child: TextField(
                      controller: _doc.coverCtrl,
                      decoration: const InputDecoration(
                        labelText: '封面图 URL（可选）',
                        prefixIcon: Icon(Icons.image_outlined, size: 19),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _toolboxSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF64748B),
        ),
      ),
    );
  }

  Widget _toolboxSectionBody({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }

  Widget _toolboxTypeChip({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? cs.primary.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? cs.primary : const Color(0xFFE2E8F0),
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17,
              color: active ? cs.primary : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: active ? cs.primary : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 三点菜单：分层承载文档操作 / 发布渠道 / AI 全功能 / 分享 / 页面操作
  void _showEditorMoreMenu() {
    final cs = Theme.of(context).colorScheme;
    final isDynamic = siteManager.isDynamicSite;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 文档操作 ──
              _menuGroupTitle('文档操作'),
              _menuRow(
                icon: Icons.widgets_outlined,
                label: '工具箱',
                color: cs.primary,
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditorToolbox();
                },
              ),
              _menuRow(
                icon: Icons.save_alt,
                label: '保存为 .md 文件',
                color: cs.primary,
                onTap: () {
                  Navigator.pop(ctx);
                  _saveMdBackup();
                },
              ),
              _menuRow(
                icon: Icons.image_outlined,
                label: '导出 PNG 长图',
                color: const Color(0xFF0EA5E9),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportPngLongImage();
                },
              ),
              _menuRow(
                icon: Icons.folder_open_outlined,
                label: '打开存储文件夹',
                color: const Color(0xFF6366F1),
                onTap: () {
                  Navigator.pop(ctx);
                  _openStorageFolder();
                },
              ),
              const Divider(height: 18),
              // ── 发布渠道 ──
              _menuGroupTitle('发布渠道'),
              _menuRow(
                icon: isDynamic
                    ? Icons.cloud_outlined
                    : Icons.cloud_queue_outlined,
                label: isDynamic
                    ? '发布到站点 (${siteManager.currentBlogType.displayName})'
                    : '发布到站点',
                color: const Color(0xFF10B981),
                onTap: () {
                  Navigator.pop(ctx);
                  _publish();
                },
              ),
              _menuRow(
                icon: Icons.upload_file_outlined,
                label: '发布 Git 仓库',
                color: const Color(0xFF6366F1),
                onTap: () {
                  Navigator.pop(ctx);
                  if (siteManager.isDynamicSite) {
                    _showToast('当前为动态站点，发布走「发布到站点」');
                  } else {
                    _publish();
                  }
                },
              ),
              const Divider(height: 18),
              // ── AI 全功能 ──
              _menuGroupTitle('AI 全功能'),
              _menuRow(
                icon: Icons.auto_awesome,
                label: 'AI 全功能入口',
                color: const Color(0xFF8B5CF6),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAiFullMenu();
                },
              ),
              const Divider(height: 18),
              // ── 分享 ──
              _menuGroupTitle('分享'),
              _menuRow(
                icon: Icons.description_outlined,
                label: '分享 MD 文件',
                color: const Color(0xFF0EA5E9),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareMdFile();
                },
              ),
              _menuRow(
                icon: Icons.share_outlined,
                label: '分享本文（纯文本）',
                color: const Color(0xFFF59E0B),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareArticle();
                },
              ),
              const Divider(height: 18),
              // ── 写作主题 ──
              _menuGroupTitle('写作主题'),
              _menuRow(
                icon: Icons.brightness_high_outlined,
                label: '纯白背景',
                color: const Color(0xFF64748B),
                onTap: () {
                  Navigator.pop(ctx);
                  _setEditorTheme(_editorTheme.copyWith(bgMode: 0));
                },
              ),
              _menuRow(
                icon: Icons.dark_mode_outlined,
                label: '纯黑背景',
                color: const Color(0xFF0F172A),
                onTap: () {
                  Navigator.pop(ctx);
                  _setEditorTheme(_editorTheme.copyWith(bgMode: 1));
                },
              ),
              _menuRow(
                icon: Icons.text_fields,
                label: '强制黑色字体',
                color: const Color(0xFF0F172A),
                onTap: () {
                  Navigator.pop(ctx);
                  _setEditorTheme(_editorTheme.copyWith(forceTextMode: 1));
                },
              ),
              _menuRow(
                icon: Icons.format_color_fill,
                label: '强制白色字体',
                color: const Color(0xFF94A3B8),
                onTap: () {
                  Navigator.pop(ctx);
                  _setEditorTheme(_editorTheme.copyWith(forceTextMode: 2));
                },
              ),
              const Divider(height: 18),
              // ── 页面操作 ──
              _menuGroupTitle('页面操作'),
              _menuRow(
                icon: Icons.visibility_outlined,
                label: '预览文章',
                color: cs.primary,
                onTap: () {
                  Navigator.pop(ctx);
                  _openArticlePreview();
                },
              ),
              _menuRow(
                icon: Icons.exit_to_app,
                label: '退出编辑',
                color: const Color(0xFFEF4444),
                onTap: () {
                  Navigator.pop(ctx);
                  _onCloseEditor();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuGroupTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: Color(0xFF94A3B8),
        ),
      ),
    );
  }

  Widget _menuRow({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFCBD5E1)),
          ],
        ),
      ),
    );
  }

  /// AI 全功能入口：列出全部 AI 功能
  void _showAiFullMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    color: const Color(0xFF8B5CF6),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'AI 全功能',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _aiMenuChip('润色', Icons.edit_note, () {
                    Navigator.pop(ctx);
                    _aiAction('polish');
                  }),
                  _aiMenuChip('续写', Icons.auto_awesome, () {
                    Navigator.pop(ctx);
                    _aiAction('continue');
                  }),
                  _aiMenuChip('摘要', Icons.summarize_outlined, () {
                    Navigator.pop(ctx);
                    _aiAction('summary');
                  }),
                  _aiMenuChip('代码', Icons.developer_mode, () {
                    Navigator.pop(ctx);
                    _aiAction('code');
                  }),
                  _aiMenuChip('改写', Icons.sync_alt, () {
                    Navigator.pop(ctx);
                    _aiAction('rewrite');
                  }),
                  _aiMenuChip('排版', Icons.auto_fix_high, () {
                    Navigator.pop(ctx);
                    _aiAction('format');
                  }),
                  _aiMenuChip('对话', Icons.chat, () {
                    Navigator.pop(ctx);
                    _showAiArticleChat();
                  }),
                  _aiMenuChip('选区', Icons.touch_app, () {
                    Navigator.pop(ctx);
                    _showAiSelectionEdit();
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aiMenuChip(String label, IconData icon, VoidCallback onTap) {
    final color = const Color(0xFF8B5CF6);
    return Material(
      color: color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.ofContext(context);
    final repoName = activeRepo?.name ?? '未配置';
    final repoFullName = activeRepo?.fullName ?? '';
    final siteName = settings.siteName.isNotEmpty
        ? settings.siteName
        : '拓墨 写作';

    return Drawer(
      backgroundColor: Colors.white,
      width: 280,
      child: SafeArea(
        child: Column(
          children: [
            // ── 渐变色头部 ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cs.primary,
                    Color.lerp(cs.primary, Colors.indigo, 0.4)!,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo 文字标志
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        '拓墨',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          'AI 写作',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.75),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    siteName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    repoFullName,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // ── 菜单项 ──
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  _drawerSection(l10n.translate('drawer_section_create')),
                  _drawerItem(
                    0,
                    Icons.edit_square,
                    l10n.translate('nav_write'),
                    isPrimary: true,
                  ),
                  _drawerItem(
                    1,
                    Icons.drafts_outlined,
                    l10n.translate('nav_drafts'),
                    badge: drafts.where((d) => !d.published).length,
                  ),
                  const SizedBox(height: 8),
                  _drawerSection(l10n.translate('drawer_section_manage')),
                  _drawerItem(
                    2,
                    Icons.cloud_outlined,
                    l10n.translate('nav_remote'),
                  ),
                  _drawerAction(
                    Icons.article_outlined,
                    l10n.translate('static_blog_posts'),
                    _showStaticBlogPosts,
                  ),
                  _drawerAction(
                    Icons.library_books_outlined,
                    l10n.translate('all_blog_manage'),
                    _showAllStaticBlogs,
                  ),
                  _drawerItem(
                    12,
                    Icons.sync,
                    l10n.translate('nav_sync_status'),
                  ),
                  _drawerAction(
                    Icons.wifi,
                    l10n.translate('p2p_sync'),
                    _openP2PSync,
                  ),
                  _drawerItem(
                    3,
                    Icons.dashboard_outlined,
                    l10n.translate('nav_dashboard'),
                  ),
                  _drawerItem(
                    5,
                    Icons.history_outlined,
                    l10n.translate('nav_history'),
                  ),
                  const SizedBox(height: 8),
                  _drawerSection(l10n.translate('drawer_section_tools')),
                  _drawerItem(
                    6,
                    Icons.drive_folder_upload,
                    l10n.translate('nav_upload'),
                  ),
                  _drawerItem(7, Icons.language, l10n.translate('nav_preview')),
                  _drawerItem(
                    4,
                    Icons.rss_feed_outlined,
                    l10n.translate('nav_rss'),
                  ),
                  _drawerAction(
                    Icons.view_quilt_outlined,
                    l10n.translate('template_manager'),
                    _showTemplateManager,
                  ),
                  _drawerAction(
                    Icons.content_paste,
                    l10n.translate('snippet_library'),
                    _showSnippetManager,
                  ),
                  _drawerAction(
                    Icons.settings_applications,
                    l10n.translate('config_editor'),
                    _showSiteConfigEditor,
                  ),
                  _drawerAction(
                    Icons.swap_horiz,
                    l10n.translate('ai_batch_migrate'),
                    _showMigrationTool,
                  ),
                  const SizedBox(height: 8),
                  _drawerSection(l10n.translate('drawer_section_ai')),
                  _drawerAction(
                    Icons.assignment_outlined,
                    l10n.translate('agent_workbench'),
                    _showAgentWorkbench,
                  ),
                  _drawerAction(
                    Icons.article_outlined,
                    l10n.translate('ai_post_create'),
                    _showAiArticleChat,
                  ),
                  _drawerAction(
                    Icons.web_outlined,
                    l10n.translate('ai_page_create'),
                    _showAiPageChat,
                  ),
                  _drawerAction(
                    Icons.palette_outlined,
                    l10n.translate('ai_theme_dev'),
                    _showAiThemeChat,
                  ),
                  _drawerItem(
                    10,
                    Icons.auto_fix_high,
                    l10n.translate('nav_ai_theme_migrate'),
                  ),
                  _drawerAction(
                    Icons.fact_check_outlined,
                    l10n.translate('ai_site_audit'),
                    _showAiAudit,
                  ),
                  _drawerAction(
                    Icons.view_quilt_outlined,
                    l10n.translate('ai_templates'),
                    _showAiTemplateChat,
                  ),
                  _drawerAction(
                    Icons.psychology_outlined,
                    l10n.translate('ai_models'),
                    _showAiModelManager,
                  ),
                  _drawerAction(
                    Icons.build_outlined,
                    l10n.translate('tool_library'),
                    _showToolLibrary,
                  ),
                  const SizedBox(height: 8),
                  _drawerSection(l10n.translate('drawer_section_system')),
                  _drawerItem(
                    13,
                    Icons.cloud_sync,
                    l10n.translate('nav_cloud_sync'),
                  ),
                  _drawerItem(
                    8,
                    Icons.settings_outlined,
                    l10n.translate('nav_settings'),
                  ),
                  _drawerItem(11, Icons.history, l10n.translate('nav_log')),
                ],
              ),
            ),

            // ── 底部信息 ──
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.shade100, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.storage_outlined,
                      size: 18,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          repoName,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          repoFullName,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage() {
    switch (_currentPage) {
      case 0:
        return _buildEditorPage();
      case 1:
        return DraftsScreen(
          drafts: drafts,
          repos: repos,
          blogSiteConfigs: settings.blogSiteConfigs,
          onOpen: (a) {
            _openExistingArticle(a);
          },
          onDelete: _deleteDraft,
        );
      case 2:
        // 远程文章：支持多站点统一聚合（静态博客 + 动态 CMS）
        final allSiteAdapters = _allSiteAdapters;
        final currentAdapter = siteManager.currentAdapter;
        final activeSiteId = siteManager.activeSiteId;
        if (allSiteAdapters.length > 1) {
          // 多站点聚合模式：静态 + 动态统一浏览
          final primary =
              allSiteAdapters
                  .where((a) => a.config.id == activeSiteId)
                  .firstOrNull ??
              currentAdapter ??
              allSiteAdapters.first;
          return RemotePostsScreen(
            adapter: primary,
            allAdapters: allSiteAdapters,
            siteManager: siteManager,
            logService: logService,
            onOpenInEditor: (post) => _openRemotePostInEditor(post),
            onDeletePost: (post) => _deleteRemoteCmsPost(post),
          );
        }
        if (siteManager.isDynamicSite) {
          final adapter = siteManager.currentAdapter;
          if (adapter == null) {
            return const Center(child: Text('未配置 CMS 站点'));
          }
          return RemotePostsScreen(
            adapter: adapter,
            allAdapters: _allCmsAdapters,
            siteManager: siteManager,
            logService: logService,
            onOpenInEditor: (post) => _openRemotePostInEditor(post),
            onDeletePost: (post) => _deleteRemoteCmsPost(post),
          );
        }
        return RemoteScreen(
          posts: remotePosts,
          activeRepo: activeRepo,
          effectiveRepo: effectiveRepo,
          github: github,
          onRefresh: _refreshRemote,
          onOpen: (item) async {
            final repo = effectiveRepo;
            if (repo == null) return;
            try {
              final a = await github.getArticle(repo, item);
              _openExistingArticle(a);
            } catch (e) {
              _showToast('打开失败: $e');
            }
          },
          onDelete: _deleteRemotePost,
          onBatchDelete: _batchDeleteRemote,
          onRollback: _rollbackFile,
        );
      case 3:
        return DashboardScreen(
          drafts: drafts,
          remotePosts: remotePosts,
          commits: commits,
          settings: settings,
          activeRepo: activeRepo,
          onNewPost: () => _navigateTo(0),
          onNavigateToRemote: () => _navigateTo(2),
          onNavigateToHistory: () => _navigateTo(5),
          onNavigateToSettings: () => _navigateTo(8),
          onNavigateToPreview: () => _navigateTo(7),
          onNavigateToDrafts: () => _navigateTo(1),
        );
      case 4:
        return RssScreen(
          items: rssItems,
          activeRepo: activeRepo,
          onRefresh: _refreshRss,
        );
      case 5:
        return HistoryScreen(
          commits: commits,
          github: github,
          effectiveRepo: effectiveRepo,
          onRefresh: _refreshCommits,
          onCommitTap: _showCommitActions,
        );
      case 6:
        return FolderUploadScreen(
          repos: repos,
          github: github,
          activeRepo: effectiveRepo,
        );
      case 7:
        return PreviewScreen(
          activeRepo: activeRepo,
          sitePreviewUrl: settings.sitePreviewUrl,
        );
      case 8:
        return SettingsScreen(
          settings: settings,
          repos: repos,
          github: github,
          storage: storage,
          webdavService: webdavService,
          onSettingsChanged: _updateSettings,
          onReposChanged: _updateRepos,
          onShowWebDavDialog: _showWebDavDialog,
          onSyncWebDavToLocal: _syncWebDavToLocal,
          onSyncDraftsToWebDav: _syncDraftsToWebDav,
          onShowAiManager: _showAiManager,
          onShowGithubTokenManager: _showGithubTokenManager,
          onShowRepoManager: _showRepoManager,
          onShowSiteEditor: _showSiteEditor,
          onShowThemeColorPicker: _showThemeColorPicker,
          onShowPwaGuide: _showPwaGuide,
          onPersistSettings: _persistSettings,
          onShowToast: _showToast,
          onShowBlogSiteManager: _showBlogSiteManager,
        );
      case 9:
        return ArticleReaderScreen(
          article: _doc.currentArticle,
          onEnterEdit: () => _enterEditorFromReader(_doc.currentArticle),
          onClose: () => _onCloseReader(),
        );
      case 10:
        return ThemeMigrationScreen(
          settings: settings,
          activeRepo: effectiveRepo,
          repos: repos,
          aiService: aiService,
          githubService: github,
          modelManager: aiModelManager,
          dispatcher: aiDispatcher,
          migrationService: themeMigrationService,
          selfChecker: aiSelfChecker,
          onSettingsChanged: _updateSettings,
          storageService: storage,
        );
      case 11:
        return LogScreen(logService: logService);
      case 12:
        if (siteManager.isDynamicSite) {
          final adapter = siteManager.currentAdapter;
          final config = siteManager.currentDynamicConfig;
          if (adapter == null || config == null) {
            return const Center(child: Text('未配置 CMS 站点'));
          }
          return SyncScreen(
            adapter: adapter,
            siteConfig: config,
            syncService: syncService,
            logService: logService,
            localArticles: drafts,
            onOpenArticle: _openExistingArticle,
            onOpenRemotePost: _openRemotePostInEditor,
          );
        }
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sync_disabled, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                '双向同步仅支持动态 CMS 站点',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              SizedBox(height: 4),
              Text(
                '请先在设置中添加 WordPress / Ghost / Typecho 站点',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        );
      case 13:
        return SyncSettingsScreen(
          cloudSyncService: cloudSyncService,
          logService: logService,
          settings: settings,
          repos: repos,
          onSettingsChanged: _updateSettings,
          onPushAll: _pushAllToCloud,
          onPullAll: _pullAllFromCloud,
        );
      default:
        return const SizedBox();
    }
  }

  /// 切换编辑器主题并同步系统栏
  Future<void> _setEditorTheme(EditorTheme theme) async {
    _updateSystemBarStyle();
    await _updateSettings(
      settings.copyWith(ui: settings.ui.copyWith(editorTheme: theme)),
    );
  }

  /// 编辑页全屏背景层：纯白/纯黑/自定义壁纸铺满整机（含状态栏与顶栏）
  Widget _buildEditorBackground() {
    final wallpaper = _editorTheme.bgMode == 2 && _wallpaperPath.isNotEmpty
        ? File(_wallpaperPath)
        : null;
    return Container(
      decoration: BoxDecoration(
        color: _editorBgColor,
        image: wallpaper != null && wallpaper.existsSync()
            ? DecorationImage(image: FileImage(wallpaper), fit: BoxFit.cover)
            : null,
      ),
    );
  }

  Widget _buildEditorPage() {
    final cs = Theme.of(context).colorScheme;
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    return Container(
      // 背景交给外层全屏背景层，这里保持透明
      color: Colors.transparent,
      child: Stack(
        children: [
          Column(
            children: [
              if (_editorBusy) const LinearProgressIndicator(minHeight: 2),
              if (_editorBusy)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _editorStatus ?? '处理中...',
                        style: TextStyle(fontSize: 12, color: cs.primary),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          _publishCancelToken.cancel();
                          _applyState(() {
                            _editorBusy = false;
                            _editorStatus = '已取消';
                          });
                        },
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('取消', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView(
                  controller: _editorScrollCtrl,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
                  children: [
                    // ── 标题：无边框、无常驻 label、淡提示 ──
                    TextField(
                      controller: _doc.titleCtrl,
                      decoration: InputDecoration(
                        hintText: '输入标题',
                        hintStyle: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: globalTextColor.withValues(alpha: 0.35),
                        ),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      cursorColor: globalTextColor,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: globalTextColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // ── 正文：无边框、无常驻 label，首次进入显示淡提示，输入后永久隐藏 ──
                    OrientationGuard(
                      enabled: true,
                      child: TextField(
                        controller: _doc.contentCtrl,
                        focusNode: _doc.contentFocus,
                        minLines: 20,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textAlignVertical: TextAlignVertical.top,
                        enabled: !_editorBusy,
                        onChanged: (_) {
                          _onContentChanged();
                          if (!_contentHintDismissed &&
                              _doc.contentCtrl.text.isNotEmpty) {
                            _applyState(() => _contentHintDismissed = true);
                          }
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
                        decoration: InputDecoration(
                          hintText: _contentHintDismissed
                              ? null
                              : '开始写作，支持 Markdown 语法...',
                          hintStyle: TextStyle(
                            fontSize: 15,
                            color: globalTextColor.withValues(alpha: 0.35),
                          ),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                        cursorColor: globalTextColor,
                        style: createUnifiedMarkdownStyle(
                          context: context,
                          config: const UnifiedMarkdownStyleConfig(
                            baseFontSize: 15,
                            lineHeight: 1.7,
                            fontFamily: 'monospace',
                          ),
                        ).p!.copyWith(color: globalTextColor),
                      ),
                    ),
                  ],
                ),
              ),
              // ── 左下角常驻状态文字：当前站点标识 ──
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '已切换到: ${_currentSiteLabel}',
                    style: TextStyle(
                      color: globalTextColor.withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              // ── 底部 MD 语法工具栏：键盘弹出时紧贴输入法，平时不占编辑区 ──
              if (keyboardVisible && !_editorBusy) _buildMdToolbar(cs),
            ],
          ),
          // ── 右下角悬浮快捷按钮：MD 导出 + 新建空白文章 ──
          Positioned(
            right: 18,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton(
                  heroTag: 'editor_export_md',
                  mini: true,
                  backgroundColor: globalTextColor.withValues(alpha: 0.12),
                  foregroundColor: globalTextColor,
                  elevation: 2,
                  tooltip: 'MD 导出',
                  onPressed: _saveMdBackup,
                  child: Text(
                    'M↓',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: globalTextColor,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'editor_new_blank',
                  mini: true,
                  backgroundColor: _editorBgColor.computeLuminance() > 0.5
                      ? cs.primary
                      : Colors.white24,
                  foregroundColor: Colors.white,
                  elevation: 3,
                  tooltip: '新建空白文章',
                  onPressed: _newBlankArticle,
                  child: const Icon(Icons.add, size: 22),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 底部 MD 语法工具栏：紧贴输入法顶部的横向滚动工具条
  Widget _buildMdToolbar(ColorScheme cs) {
    return Container(
      height: 46,
      color: Colors.transparent,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _toolChip(Icons.format_bold, '粗体', () => _wrap('**', '**', p: '粗体')),
          _toolChip(Icons.format_italic, '斜体', () => _wrap('*', '*', p: '斜体')),
          _toolChip(Icons.code, '行内码', () => _wrap('`', '`', p: 'code')),
          _toolChip(Icons.code_off, '代码块', _insertCodeBlock),
          _toolChip(Icons.title, 'H1', () => _insertHeading(1)),
          _toolChip(Icons.title, 'H2', () => _insertHeading(2)),
          _toolChip(Icons.format_list_bulleted, '列表', () => _insertList('- ')),
          _toolChip(Icons.format_quote, '引用', () => _insertList('> ')),
          _toolChip(
            Icons.link,
            '链接',
            () => _wrap('[', '](https://)', p: '链接文字'),
          ),
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
          _toolChip(
            Icons.more_horiz,
            'more',
            () => _insertText('\n<!--more-->\n'),
          ),
          _toolChip(
            Icons.image_outlined,
            '图床',
            _editorBusy ? null : _insertImage,
          ),
          _toolChip(
            Icons.collections_outlined,
            '批量图床',
            _editorBusy ? null : _batchInsertImages,
          ),
          _toolChip(
            Icons.auto_awesome,
            'AI润色',
            _editorBusy ? null : () => _aiAction('polish'),
            color: Colors.purple,
          ),
          _toolChip(
            Icons.edit_note,
            'AI续写',
            _editorBusy ? null : () => _aiAction('continue'),
            color: Colors.purple,
          ),
          _toolChip(
            Icons.summarize_outlined,
            'AI摘要',
            _editorBusy ? null : () => _aiAction('summary'),
            color: Colors.purple,
          ),
          _toolChip(
            Icons.developer_mode,
            'AI代码',
            _editorBusy ? null : () => _aiAction('code'),
            color: Colors.purple,
          ),
          _toolChip(
            Icons.sync_alt,
            'AI改写',
            _editorBusy ? null : () => _aiAction('rewrite'),
            color: Colors.purple,
          ),
          _toolChip(
            Icons.auto_fix_high,
            'AI排版',
            _editorBusy ? null : () => _aiAction('format'),
            color: Colors.deepPurple,
          ),
          _toolChip(
            Icons.chat,
            'AI对话',
            () => _showAiArticleChat(),
            color: Colors.deepPurple,
          ),
          _toolChip(
            Icons.touch_app,
            'AI选区',
            _editorBusy ? null : _showAiSelectionEdit,
            color: Colors.deepPurple,
          ),
        ],
      ),
    );
  }

}
