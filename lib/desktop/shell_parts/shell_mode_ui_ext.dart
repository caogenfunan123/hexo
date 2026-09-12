// 三种工作模式布局 UI扩展（desktop_shell.dart 的 part，与主类同 library，可访问私有成员）。
// 由 desktop_shell.dart 拆分而来（修复1），方法体保持零变更；
// setState 经宿主 _applyState 包装调用。
part of '../desktop_shell.dart';

extension DesktopShellModeUiExt on DesktopShellState {
  Future<void> _refreshWallpaperBrightness() async {
    if (!_deskUseWallpaper) {
      _wallpaperBrightness = 1.0;
      return;
    }
    try {
      final bytes = await File(_deskEditorTheme.wallpaperPath).readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 32,
        targetHeight: 32,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      frame.image.dispose();
      codec.dispose();
      if (data != null) {
        final bytesData = data.buffer.asUint8List();
        var sum = 0.0;
        final step = bytesData.length ~/ 4;
        for (
          var i = 0;
          i + 2 < bytesData.length;
          i += 4 * (step > 400 ? step ~/ 400 : 1)
        ) {
          final r = bytesData[i] / 255;
          final g = bytesData[i + 1] / 255;
          final b = bytesData[i + 2] / 255;
          sum += 0.2126 * r + 0.7152 * g + 0.0722 * b;
        }
        final count =
            (bytesData.length / (4 * (step > 400 ? step ~/ 400 : 1))).ceil();
        if (count > 0) sum /= count;
        _wallpaperBrightness = sum.clamp(0.0, 1.0);
      }
    } catch (_) {
      // 读取失败保持默认
    }
  }

  Widget _buildTopBar(LayoutController layout) {
    if (layout.workMode == WorkMode.focus) return _focusModeTitleBar();
    return DesktopTitleBar(
      onAi: () => _openRightDrawer(RightDrawerTab.aiChat),
      bus: _bus,
      siteName: activeRepo?.name ?? settings.siteName,
      repos: repos,
    );
  }

  Widget _buildMainArea(LayoutController layout) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mainContent = switch (layout.workMode) {
      WorkMode.focus => _buildFocusEditor(),
      WorkMode.source => _buildSourceEditor(),
      _ => _buildWorkspaceLayout(layout),
    };

    return Expanded(
      child: EditorDropTarget(
        isDark: isDark,
        onImageDropped: (file) async {
          return await _handleDroppedImage(file);
        },
        onMarkdownInserted: (content) async {
          _insertText(content);
        },
        child: mainContent,
      ),
    );
  }

  Widget _buildWorkspaceLayout(LayoutController layout) {
    return Row(
      children: [
        if (layout.leftPanelExpanded)
          DesktopLeftPanel(
            width: layout.leftPanelWidth,
            onResize: (w) => _layout.setLeftPanelWidth(w),
            onCollapse: _toggleLeftPanel,
            bus: _bus,
            repos: repos,
            drafts: drafts,
            siteManager: siteManager,
            mode: settings.ui.appMode,
            simpleModeExtras: settings.ui.simpleModeExtras,
            navCustom: settings.ui.navCustom,
            collapsedSections: settings.ui.collapsedLeftSections,
            collapsedLeftSectionsSet: settings.ui.collapsedLeftSectionsSet,
            onCollapsedSectionsChanged: (keys) {
              _updateSettings(
                settings.copyWith(
                  ui: settings.ui.copyWith(
                    collapsedLeftSections: keys,
                    collapsedLeftSectionsSet: true,
                  ),
                ),
              );
            },
          ),

        if (!layout.leftPanelExpanded) _collapseToggle(),

        Expanded(
          child: ListenableBuilder(
            listenable: _editor,
            builder: (context, child) => DesktopEditorArea(
              tabs: _editor.openTabs,
              activeIndex: _editor.activeTabIndex,
              onTabChange: _switchEditorTab,
              onTabClose: _closeTab,
              onNewArticle: _newArticle,
              onSync: _handleSync,
              onSettings: _openSettings,
            ),
          ),
        ),

        if (layout.rightDrawerOpen) _buildRightDrawer(layout),
      ],
    );
  }

  Widget _buildRightDrawer(LayoutController layout) {
    return DesktopRightDrawer(
      activeTab: layout.activeDrawerTab,
      onTabChange: (t) => _layout.setDrawerTab(t),
      onClose: () => _layout.closeRightDrawer(),
      outlineItems: parseOutline(_doc.contentCtrl.text),
      titleCtrl: _doc.titleCtrl,
      tagsCtrl: _doc.tagsCtrl,
      categoriesCtrl: _doc.categoriesCtrl,
      coverCtrl: _doc.coverCtrl,
      syncLogs: _sync.logs
          .map(
            (e) =>
                '${e.timestamp.hour}:${e.timestamp.minute.toString().padLeft(2, '0')}:${e.timestamp.second.toString().padLeft(2, '0')} ${e.message}',
          )
          .toList(),
      snippets: snippets,
      onSnippetInsert: (content) => _insertText(content),
      onSnippetDelete: (snippet) async {
        snippets.removeWhere((s) => s.id == snippet.id);
        await storage.saveSnippets(snippets);
        if (mounted) _applyState(() => snippets = List.from(snippets));
      },
      onSnippetAdd: _showSnippetManager,
      aiChatPanel: AiChatPanel(
        key: _aiChatKey,
        settings: settings,
        aiService: aiService,
        modelManager: aiModelManager,
        dispatcher: aiDispatcher,
        selfChecker: aiSelfChecker,
        sessionType: AiSessionType.article,
        // 按文章隔离 AI 会话历史，避免切文章后旧上下文串入新文章
        historyKey: 'article_${_doc.currentArticle.id}',
        blogFramework: effectiveRepo?.frameworkId,
        postsPath: effectiveRepo?.postsPath,
        pagesPath: effectiveRepo?.pagesPath,
        onSettingsChanged: _updateSettings,
        gitHubService: github,
        activeRepo: effectiveRepo,
        storageService: storage,
      ),
    );
  }

  Widget _buildBottomBar(LayoutController layout) {
    if (layout.workMode == WorkMode.focus) return const SizedBox.shrink();
    // 状态栏仅订阅 _editor/_doc 变化，独立重建，不再依赖整壳 setState
    return ListenableBuilder(
      listenable: Listenable.merge([_editor, _doc]),
      builder: (context, child) {
        // 计算阅读时间
        final charCount = _editor.charCount;
        final readMin = charCount > 0 ? (charCount / 400).ceil().clamp(1, 120) : 0;
        return DesktopStatusBar(
          workMode: layout.workMode,
          onModeChange: _switchWorkMode,
          editorStatus: _editor.editorStatus,
          cursorPosition: (_editor.cursorPos.line, _editor.cursorPos.column),
          wordCount: _editor.wordCount,
          charCount: charCount,
          siteName: activeRepo?.name ?? settings.siteName,
          isSyncing: false,
          isSaved: !_doc.hasUnsavedChanges,
          lineCount: _editor.cursorPos.totalLines,
          readTime: readMin > 0 ? '约$readMin分钟' : '',
        );
      },
    );
  }

  Widget _focusModeTitleBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final siteName = activeRepo?.name ?? settings.siteName;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColor.surfaceRaised(context),
        border: Border(
          bottom: BorderSide(
            color: AppColor.border(context),
          ),
        ),
      ),
      child: GestureDetector(
        onPanStart: (_) => windowManager.startDragging(),
        child: Row(
          children: [
            const SizedBox(width: 4),
            _minimalBarButton(
              Icons.menu,
              '菜单',
              () => _toggleLeftPanel(),
              isDark,
            ),
            const SizedBox(width: 8),
            Text(
              '拓墨',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColor.textSecondary(context),
                letterSpacing: 0.3,
              ),
            ),
            if (siteName.isNotEmpty) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  siteName,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColor.iconMuted(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const Spacer(),
            _minimalBarButton(Icons.check, '保存', _saveLocal, isDark),
            _minimalBarButton(
              Icons.visibility_outlined,
              '预览',
              _toggleFocusPreview,
              isDark,
              active: _focusPreviewOpen,
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              offset: const Offset(0, 44),
              color: AppColor.surfaceOverlay(context),
              icon: Icon(
                Icons.more_vert,
                size: 18,
                color: AppColor.icon(context),
              ),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'meta',
                  child: _focusMoreItem(
                    Icons.article_outlined,
                    '文章元数据',
                    isDark,
                  ),
                ),
                PopupMenuItem(
                  value: 'toolbar',
                  child: _focusMoreItem(
                    Icons.format_bold,
                    '格式化工具栏',
                    isDark,
                    trailing: _focusShowToolbar
                        ? Icon(Icons.check, size: 16, color: cs.primary)
                        : null,
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'ai',
                  child: _focusMoreItem(
                    Icons.auto_awesome,
                    'AI 对话',
                    isDark,
                  ),
                ),
                PopupMenuItem(
                  value: 'publish',
                  child: _focusMoreItem(
                    Icons.send_outlined,
                    '一键发布',
                    isDark,
                  ),
                ),
                PopupMenuItem(
                  value: 'sync',
                  child: _focusMoreItem(Icons.sync, '同步', isDark),
                ),
                PopupMenuItem(
                  value: 'theme',
                  child: _focusMoreItem(
                    isDark ? Icons.light_mode : Icons.dark_mode_outlined,
                    '切换主题',
                    isDark,
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'full',
                  child: _focusMoreItem(
                    Icons.space_dashboard_outlined,
                    '切换到完整编辑模式',
                    isDark,
                  ),
                ),
              ],
              onSelected: _onFocusMoreSelected,
            ),
            const SizedBox(width: 4),
            Container(
              width: 1,
              height: 20,
              color: AppColor.border(context),
            ),
            const SizedBox(width: 2),
            _minimalBarButton(
              Icons.minimize,
              '最小化',
              () => windowManager.minimize(),
              isDark,
            ),
            _minimalBarButton(
              Icons.crop_square,
              '最大化',
              () => windowManager.maximize(),
              isDark,
            ),
            _minimalBarButton(
              Icons.close,
              '关闭',
              () => windowManager.close(),
              isDark,
              isClose: true,
            ),
          ],
        ),
      ),
    );
  }

  void _onFocusMoreSelected(String value) {
    switch (value) {
      case 'meta':
        if (_focusPreviewOpen) _applyState(() => _focusPreviewOpen = false);
        _openRightDrawer(RightDrawerTab.frontMatter);
        break;
      case 'toolbar':
        _applyState(() => _focusShowToolbar = !_focusShowToolbar);
        break;
      case 'ai':
        if (_focusPreviewOpen) _applyState(() => _focusPreviewOpen = false);
        _openRightDrawer(RightDrawerTab.aiChat);
        break;
      case 'publish':
        _handlePublish();
        break;
      case 'sync':
        _handleSync();
        break;
      case 'theme':
        _toggleTheme();
        break;
      case 'full':
        _switchWorkMode(WorkMode.workspace);
        break;
    }
  }

  void _toggleFocusPreview() {
    _applyState(() {
      _focusPreviewOpen = !_focusPreviewOpen;
      if (_focusPreviewOpen) _layout.closeRightDrawer();
    });
  }

  Widget _focusContextMenu(BuildContext context, EditableTextState state) {
    final sel = state.textEditingValue.selection;
    final hasSelection = sel.isValid && !sel.isCollapsed;
    final chips = <Widget>[
      if (hasSelection) ...[
        _miniToolbarChip(
          Icons.format_bold,
          '粗体',
          () => _wrap('**', '**', p: '粗体'),
        ),
        _miniToolbarChip(
          Icons.format_italic,
          '斜体',
          () => _wrap('*', '*', p: '斜体'),
        ),
        _miniToolbarChip(
          Icons.link,
          '链接',
          () => _wrap('[', '](https://)', p: '链接文字'),
        ),
        _miniToolbarChip(
          Icons.format_quote,
          '引用',
          () => _wrap('\n> ', '\n', p: '引用'),
        ),
      ],
      if (!hasSelection) ...[
        _miniToolbarChip(
          Icons.content_paste,
          '粘贴',
          () async {
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            final text = data?.text;
            if (text != null && text.isNotEmpty) _insertText(text);
          },
        ),
        _miniToolbarChip(
          Icons.select_all,
          '全选',
          () => state.selectAll(SelectionChangedCause.toolbar),
        ),
      ],
    ];
    return AdaptiveTextSelectionToolbar(
      anchors: state.contextMenuAnchors,
      children: chips,
    );
  }

  Widget _miniToolbarChip(
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              icon,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _minimalBarButton(
    IconData icon,
    String tooltip,
    VoidCallback onTap,
    bool isDark, {
    bool active = false,
    bool isClose = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 18,
              color: isClose
                  ? Colors.redAccent
                  : (active
                        ? Theme.of(context).colorScheme.primary
                        : AppColor.icon(context)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _focusMoreItem(
    IconData icon,
    String label,
    bool isDark, {
    Widget? trailing,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: AppColor.icon(context),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AppColor.textSecondary(context),
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildFocusEditor() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 背景层：自定义壁纸 / 纯色（写作界面全屏背景，对标手机端 _buildEditorBackground）
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

    final textColor = _deskCustomBg
        ? _deskTextColor
        : (isDark ? Colors.white : const Color(0xFF1F2937));
    final mutedColor = textColor.withOpacity(0.35);

    return Stack(
      children: [
        Positioned.fill(child: bgLayer),
        // ── 主编辑区：只有「标题输入 + 正文」，大留白 ──
        SingleChildScrollView(
          controller: _focusScrollCtrl,
          padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 标题输入
                  TextField(
                    controller: _doc.titleCtrl,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: textColor,
                      fontFamily: _resolveFontFamily(
                        _editor.editorFontFamily,
                      ),
                    ),
                    cursorColor: cs.primary,
                    decoration: InputDecoration(
                      hintText: '在此输入标题...',
                      hintStyle: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: mutedColor,
                      ),
                      border: InputBorder.none,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          enabledBorder: InputBorder.none,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          focusedBorder: InputBorder.none,
                    ),
                    onChanged: (_) => _onContentChanged(),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 1,
                    color: mutedColor.withOpacity(0.6),
                  ),
                  const SizedBox(height: 16),
                  // 正文编辑区（带当前行高亮）
                  Stack(
                    children: [
                      ValueListenableBuilder<int>(
                        valueListenable: _focusCursorLine,
                        builder: (context, cursorLine, _) => Positioned(
                          top: cursorLine > 0
                              ? (cursorLine - 1) *
                                  (_editor.editorFontSize *
                                      _editor.editorLineHeight)
                              : -100,
                          left: 0,
                          right: 0,
                          height: _editor.editorFontSize *
                              _editor.editorLineHeight,
                          child: Container(
                            color: AppColor.surfaceHover(context),
                          ),
                        ),
                      ),
                      SizedBox(
                        height:
                            _doc.contentCtrl.text.split('\n').length *
                                (_editor.editorFontSize *
                                    _editor.editorLineHeight) +
                            600,
                        child: TextField(
                          controller: _doc.contentCtrl,
                          maxLines: null,
                          expands: true,
                          focusNode: _doc.contentFocus,
                          cursorColor: cs.primary,
                          style: TextStyle(
                            fontSize: _editor.editorFontSize,
                            height: _editor.editorLineHeight,
                            color: textColor,
                            fontFamily: _resolveFontFamily(
                              _editor.editorFontFamily,
                            ),
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     enabledBorder: InputBorder.none,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     focusedBorder: InputBorder.none,
                            hintText: '开始写作...',
                            hintStyle: TextStyle(
                              fontSize: _editor.editorFontSize,
                              color: mutedColor,
                            ),
                          ),
                          contextMenuBuilder: _focusContextMenu,
                          onChanged: (_) => _onContentChanged(),
                        ),
                      ),
                    ],
                  ),
                  // ── 格式化工具栏（更多菜单展开） ──
                  if (_focusShowToolbar) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (_deskCustomBg
                                ? _deskCardBg
                                : AppColor.surfaceBase(context))
                            .withOpacity(0.92),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColor.border(context),
                        ),
                      ),
                      child: Wrap(
                        spacing: 2,
                        runSpacing: 2,
                        children: [..._buildToolChips()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // ── 右侧预览面板（极简标题栏「预览」打开） ──
        if (_focusPreviewOpen)
          Positioned(
            right: 8,
            top: 8,
            bottom: 8,
            child: Container(
              width: 400,
              decoration: BoxDecoration(
                color: AppColor.surfaceRaised(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColor.borderStrong(context),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.28 : 0.06),
                    blurRadius: 16,
                    offset: const Offset(-2, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: AppColor.border(context),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.visibility, size: 14, color: mutedColor),
                        const SizedBox(width: 6),
                        Text(
                          '实时预览',
                          style: TextStyle(fontSize: 11, color: mutedColor),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: _toggleFocusPreview,
                          child: Icon(Icons.close, size: 14, color: mutedColor),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListenableBuilder(
                      listenable: Listenable.merge([
                        _doc.contentCtrl,
                        _doc.titleCtrl,
                      ]),
                      builder: (context, _) {
                        final t = _doc.titleCtrl.text.trim();
                        final body = _doc.contentCtrl.text;
                        return MarkdownPreviewSmooth(
                          markdown: t.isEmpty
                              ? body
                              : '# $t\n\n$body',
                          darkTheme: isDark,
                          baseFontSize: 16,
                          lineHeight: 1.6,
                          onOpenLink: (url) async {
                            final uri = Uri.tryParse(url);
                            if (uri != null &&
                                (uri.scheme == 'http' ||
                                    uri.scheme == 'https')) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        // ── 右侧抽屉（元数据 / AI，与预览互斥） ──
        if (!_focusPreviewOpen &&
            context.watch<LayoutController>().rightDrawerOpen)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: _buildRightDrawer(_layout),
          ),
      ],
    );
  }

  Widget _buildSourceEditor() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    // 初始化或重建语法高亮桥接控制器
    final syntaxColors = isDark
        ? MarkdownSyntaxColors.dark
        : MarkdownSyntaxColors.light;
    if (_sourceSyntaxCtrl == null) {
      _sourceSyntaxCtrl = BridgedSyntaxController(
        delegate: _doc.contentCtrl,
        colors: syntaxColors,
        fontSize: 14,
        fontFamily: 'monospace',
      );
    } else {
      _sourceSyntaxCtrl!.updateColors(syntaxColors);
    }

    return Container(
      color: AppColor.surfaceBase(context),
      child: Column(
        children: [
          // 源码模式标题栏
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColor.surfaceRaised(context),
              border: Border(
                bottom: BorderSide(
                  color: AppColor.border(context),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.code, size: 14, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  '源码模式',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _doc.titleCtrl.text.isNotEmpty
                      ? _doc.titleCtrl.text
                      : '未命名文章',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColor.iconMuted(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                // 快捷操作
                _sourceToolbarButton(
                  Icons.save_outlined,
                  '保存',
                  _saveLocal,
                  isDark,
                ),
                _sourceToolbarButton(
                  Icons.send_outlined,
                  '发布',
                  _handlePublish,
                  isDark,
                ),
                _sourceToolbarButton(Icons.content_copy, '复制全文', () {
                  Clipboard.setData(ClipboardData(text: _doc.contentCtrl.text));
                  _showToast('已复制到剪贴板');
                }, isDark),
                _sourceToolbarButton(
                  Icons.spellcheck,
                  '拼写检查',
                  () => _showSpellCheck(),
                  isDark,
                ),
                Container(
                  width: 1,
                  height: 18,
                  color: AppColor.border(context),
                ),
                _sourceToolbarButton(
                  Icons.close_fullscreen,
                  '退出源码模式',
                  () => _switchWorkMode(WorkMode.workspace),
                  isDark,
                ),
              ],
            ),
          ),
          // 源码编辑区（带语法高亮）
          Expanded(
            child: ColoredBox(
              color: isDark ? const Color(0xFF18181B) : Colors.white,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: TextField(
                  controller: _sourceSyntaxCtrl,
                  maxLines: null,
                  focusNode: _doc.contentFocus,
                  cursorColor: cs.primary,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             enabledBorder: InputBorder.none,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             focusedBorder: InputBorder.none,
                    hintText: '在此编辑 Markdown 源码...',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      fontFamily: 'monospace',
                      color: isDark
                          ? Colors.white.withOpacity(0.1)
                          : const Color(0xFFB0B0B0),
                    ),
                  ),
                  onChanged: (_) => _onContentChanged(),
                ),
              ),
            ),
          ),
          // 底部状态条（白底 + 顶部细线，轻量化）
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColor.surfaceRaised(context),
              border: Border(
                top: BorderSide(
                  color: AppColor.border(context),
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'Markdown',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColor.textSubtle(context),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '行 ${_editor.cursorPos.line} 列 ${_editor.cursorPos.column}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColor.textSubtle(context),
                  ),
                ),
                const Spacer(),
                Text(
                  '$_editor.wordCount 词  $_editor.charCount 字',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColor.textSubtle(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sourceToolbarButton(
    IconData icon,
    String tooltip,
    VoidCallback onTap,
    bool isDark,
  ) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(
              icon,
              size: 15,
              color: AppColor.icon(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _collapseToggle() {
    return GestureDetector(
      onTap: _toggleLeftPanel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 28,
          decoration: BoxDecoration(
            color: AppColor.surfaceBase(context),
            border: Border(
              right: BorderSide(
                color: AppColor.border(context),
              ),
            ),
          ),
          child: Center(
            child: Icon(
              Icons.chevron_right,
              size: 14,
              color: AppColor.iconMuted(context),
            ),
          ),
        ),
      ),
    );
  }
}
