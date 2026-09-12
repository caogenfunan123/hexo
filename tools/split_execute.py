#!/usr/bin/env python3
"""desktop_shell.dart 拆分执行脚本（修复1）
按业务域把 DesktopShellState 的方法抽取为 extension part 文件，行为零变更。
用法: python tools/split_execute.py
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from split_helper import mask_document, mask_lines, collect_methods, SRC

# ── 业务域 → 方法名映射（基于 2026-09-12 清单；未列出的方法一律保留在主类） ──
DOMAINS = {
    'shell_publish_ext': ('发布 / 保存 / 定时发布', [
        '_collect', '_generateSlug', '_saveDraft', '_saveLocal', '_saveMdBackup',
        '_handlePublish', '_publishToCms', '_publishToAllCmsSites',
        '_showPublishChangeLog', '_schedulePublish', '_executePublish',
        '_repairPublishPaths', '_batchPublish', '_saveAsToLocal',
    ]),
    'shell_sync_ext': ('云同步 / WebDAV / 冲突解决', [
        '_startAutoSync', '_stopAutoSync', '_autoSyncToCloud', '_autoPullFromCloud',
        '_pushAllToCloud', '_pullAllFromCloud', '_handleSync', '_openSyncStatus',
        '_showWebDavDialog', '_syncWebDavToLocal', '_syncDraftsToWebDav',
        '_showConflictResolution', '_applyConflictResolutions',
        '_checkAndResolveConflicts', '_computeDiff', '_lcsMatrix',
    ]),
    'shell_autosave_ext': ('自动保存 / 内容变更跟踪', [
        '_startAutoSave', '_stopAutoSave', '_flushAllPendingSaves', '_onTitleChanged',
        '_onContentChanged', '_trackStats', '_onCursorSelectionChanged',
        '_centerCursorInFocusMode', '_autoSaveSnapshot',
    ]),
    'shell_drafts_ext': ('文章 / 草稿 / 标签页 / 会话', [
        '_restoreSession', '_openExistingArticle', '_saveSessionFromDoc',
        '_loadSessionIntoDoc', '_switchEditorTab', '_deleteDraft', '_renameArticle',
        '_moveArticleVolume', '_exportArticle', '_refreshDraftsFromStorage',
        '_newArticle', '_addEditorTab', '_openTab', '_closeTab',
    ]),
    'shell_remote_ext': ('远程内容 / 回滚', [
        '_refreshRemote', '_refreshRss', '_refreshCommits', '_openRemote',
        '_batchDeleteRemoteFiles', '_rollbackRemoteFile',
    ]),
    'shell_ai_ext': ('AI 功能', [
        '_aiAction', '_sendSelectionToAi', '_sendFullToAi', '_sendToAiChatWhenReady',
        '_showAiDiffPreview', '_buildDiffLegend', '_showAgentWorkbench',
        '_showAiTemplateChat', '_startAiSiteWizard', '_showAiModelManager',
        '_showToolLibrary', '_showAiManager', '_openAiPromptTemplates', '_showThemeStore',
    ]),
    'shell_import_export_ext': ('导入 / 导出', [
        '_importHtmlFile', '_importDocxFile', '_extractDocxText', '_exportHtml',
        '_exportPdf', '_exportDocx', '_buildDocxZip', '_exportEpub', '_buildEpubZip',
        '_escapeXml', '_escapeXmlBody', '_createZip', '_safeTitle', '_mdToHtml',
        '_sanitizeHtml', '_escapeHtml',
    ]),
    'shell_dialogs_ext': ('设置 / 站点 / 管理弹窗', [
        '_updateSettings', '_updateRepos', '_loadEditorSettings', '_saveEditorSettings',
        '_showTemplateManager', '_showSnippetManager', '_showConfigEditor',
        '_showSiteEditor', '_showBlogSiteManager', '_handleBlogSiteSaved',
        '_showGithubTokenManager', '_showRepoManager', '_showSiteOperations',
        '_showModeGuideDialog', '_showPwaGuide',
    ]),
    'shell_style_ext': ('外观定制 / 帮助', [
        '_showThemeColorPicker', '_showFontSettings', '_showThemePicker',
        '_showCustomCssEditor', '_showShortcutEditor', '_showHelpDialog',
        '_buildHelpShortcuts', '_buildHelpFeatures', '_buildHelpLayout', '_buildHelpTips',
    ]),
    'shell_search_ext': ('查找替换 / 全局搜索', [
        '_openGlobalSearch', '_showFindReplace', '_findNext', '_replaceCurrent', '_replaceAll',
    ]),
    'shell_tools_ext': ('运维工具 / 批量操作', [
        '_openProxySettings', '_openCacheCleanup', '_exportLogs', '_fixEncoding',
        '_toggleOfflineMode', '_toggleNightEyeProtection', '_openLinkChecker',
        '_openBatchTools', '_openContentStats', '_openBackupRestore',
        '_openImageBedManager', '_openRecycleBin', '_openP2PSync',
        '_openThemeMigration', '_showSpellCheck', '_showBatchOperations',
        '_batchExportMd', '_batchFormat', '_openVersionHistory',
    ]),
    'shell_text_ext': ('文本编辑 / 插入', [
        '_insertText', '_insertCodeBlock', '_insertImage', '_handleDroppedImage',
        '_batchInsertImages', '_retryUploadImage', '_pasteImageFromClipboard',
        '_wrap', '_insertHeading', '_insertList', '_wrapSelection', '_prefixLine',
        '_insertLink', '_insertTable', '_addTableRow', '_addTableCol',
        '_toggleImagePathMode', '_insertToc', '_formatDocument', '_autoSelectTemplate',
    ]),
    'shell_nav_ext': ('导航 / 文件打开 / 布局开关', [
        '_openHome', '_openDrafts', '_openSettings', '_openSyncSettings', '_openDashboard',
        '_openHistory', '_openRss', '_openBatchUpload', '_openPreview',
        '_openPreviewExternal', '_openAllFeatures', '_openSidebarCustomize',
        '_openLocalFileZone', '_openFileDialog', '_addRecentFile', '_persistRecentFiles',
        '_loadRecentFiles', '_switchSite', '_toggleLeftPanel', '_toggleRightDrawer',
        '_openRightDrawer', '_toggleTheme', '_switchWorkMode', '_openLogs',
        '_setAsRepoDefault',
    ]),
    'shell_workbench_ui_ext': ('工作台编辑区 UI', [
        '_buildEmbeddedEditor', '_metaPanelMaxHeight', '_editorCard', '_frontMatterSummary',
        '_buildFrontMatterPanel', '_fmTypePill', '_fmField', '_buildToolChips',
        '_moreToolsChip', '_toolChip',
    ]),
    'shell_mode_ui_ext': ('三种工作模式布局 UI', [
        '_buildTopBar', '_buildMainArea', '_buildWorkspaceLayout', '_buildRightDrawer',
        '_buildBottomBar', '_focusModeTitleBar', '_onFocusMoreSelected',
        '_toggleFocusPreview', '_focusContextMenu', '_miniToolbarChip', '_minimalBarButton',
        '_focusMoreItem', '_buildFocusEditor', '_buildSourceEditor', '_sourceToolbarButton',
        '_collapseToggle', '_refreshWallpaperBrightness',
    ]),
    'shell_misc_ext': ('杂项 / 命令面板', [
        '_showToast', '_openCommandPalette', '_closeCommandPalette', '_buildCommandItems',
    ]),
}

EXT_NAMES = {
    'shell_publish_ext': 'DesktopShellPublishExt',
    'shell_sync_ext': 'DesktopShellSyncExt',
    'shell_autosave_ext': 'DesktopShellAutosaveExt',
    'shell_drafts_ext': 'DesktopShellDraftsExt',
    'shell_remote_ext': 'DesktopShellRemoteExt',
    'shell_ai_ext': 'DesktopShellAiExt',
    'shell_import_export_ext': 'DesktopShellImportExportExt',
    'shell_dialogs_ext': 'DesktopShellDialogsExt',
    'shell_style_ext': 'DesktopShellStyleExt',
    'shell_search_ext': 'DesktopShellSearchExt',
    'shell_tools_ext': 'DesktopShellToolsExt',
    'shell_text_ext': 'DesktopShellTextExt',
    'shell_nav_ext': 'DesktopShellNavExt',
    'shell_workbench_ui_ext': 'DesktopShellWorkbenchUiExt',
    'shell_mode_ui_ext': 'DesktopShellModeUiExt',
    'shell_misc_ext': 'DesktopShellMiscExt',
}

def main():
    with open(SRC, encoding='utf-8') as f:
        lines = f.readlines()
    masked = mask_lines(lines)

    # 定位类范围并提取方法
    cls_start = cls_end = None
    for idx, l in enumerate(masked):
        if l.startswith('class DesktopShellState'):
            cls_start = idx; break
    assert cls_start is not None, 'DesktopShellState not found'
    for idx in range(cls_start + 1, len(lines)):
        if re.match(r'^(class |enum |mixin |abstract class )', masked[idx]):
            cls_end = idx - 1; break
    methods = {name: (cs, ds, e) for name, cs, ds, e in collect_methods(masked, cls_start, cls_end)}

    # 校验映射完整性
    missing = []
    for dom, (_, names) in DOMAINS.items():
        for n in names:
            if n not in methods:
                missing.append(f'{dom}: {n}')
    if missing:
        print('MAPPED METHOD NOT FOUND:'); [print(' ', m) for m in missing]; sys.exit(1)

    # 收集提取区间 (0-based inclusive: cstart-1 .. end-1)
    blocks = []  # (cstart1, end1, name, domain)
    seen = set()
    for dom, (_, names) in DOMAINS.items():
        for n in names:
            cs, ds, e = methods[n]
            assert n not in seen, f'duplicate mapping {n}'
            seen.add(n)
            blocks.append((cs, e, n, dom))

    # 区间不重叠校验
    ordered = sorted(blocks)
    for a, b in zip(ordered, ordered[1:]):
        assert a[1] < b[0], f'overlap: {a[2]}({a[0]}-{a[1]}) vs {b[2]}({b[0]}-{b[1]})'

    # 按域生成 part 文件
    outdir = 'lib/desktop/shell_parts'
    os.makedirs(outdir, exist_ok=True)
    moved_lines = 0
    for dom, (title, names) in DOMAINS.items():
        dom_blocks = sorted(b for b in blocks if b[3] == dom)
        parts = []
        for cs, e, n, _ in dom_blocks:
            # cs/e 均为 0 基闭区间索引：切片 [cs:e+1] 才是完整方法块
            text = ''.join(lines[cs:e+1])
            m = mask_document(text)
            assert m.count('{') == m.count('}'), f'{n}: brace imbalance in extracted block'
            text = re.sub(r'\bsetState\(', '_applyState(', text)
            parts.append(text.rstrip('\n'))
            moved_lines += e - cs + 1
        body = '\n\n'.join(parts)
        content = (
            f'// {title}扩展（desktop_shell.dart 的 part，与主类同 library，可访问私有成员）。\n'
            f'// 由 desktop_shell.dart 拆分而来（修复1），方法体保持零变更；\n'
            f'// setState 经宿主 _applyState 包装调用。\n'
            f"part of '../desktop_shell.dart';\n\n"
            f"extension {EXT_NAMES[dom]} on DesktopShellState {{\n"
            f"{body}\n"
            f"}}\n"
        )
        with open(os.path.join(outdir, f'{dom}.dart'), 'w', encoding='utf-8', newline='') as f:
            f.write(content)
        print(f'{dom}.dart: {len(dom_blocks)} methods')

    # extension 内访问宿主静态成员需要类名限定（Dart 规则）
    QUALIFY = [
        ('lib/desktop/shell_parts/shell_autosave_ext.dart',
         '        _focusHeaderOffset + (line - 1) * lineHeight - viewportHeight / 2 + lineHeight;',
         '        DesktopShellState._focusHeaderOffset + (line - 1) * lineHeight - viewportHeight / 2 + lineHeight;'),
        ('lib/desktop/shell_parts/shell_nav_ext.dart',
         '    if (_recentFiles.length > _maxRecentFiles) {\n      _recentFiles.removeRange(_maxRecentFiles, _recentFiles.length);',
         '    if (_recentFiles.length > DesktopShellState._maxRecentFiles) {\n      _recentFiles.removeRange(DesktopShellState._maxRecentFiles, _recentFiles.length);'),
        ('lib/desktop/shell_parts/shell_style_ext.dart',
         '    final shortcuts = Map<String, String>.from(_defaultShortcuts);',
         '    final shortcuts = Map<String, String>.from(DesktopShellState._defaultShortcuts);'),
        ('lib/desktop/shell_parts/shell_style_ext.dart',
         '                        final label = _actionLabels[action] ?? action;',
         '                        final label = DesktopShellState._actionLabels[action] ?? action;'),
    ]
    for path, old, new in QUALIFY:
        p = os.path.join(*path.split('/'))
        s = open(p, encoding='utf-8').read()
        assert old in s, f'QUALIFY target not found in {path}'
        open(p, 'w', encoding='utf-8', newline='').write(s.replace(old, new))
    print('static qualifications applied')

    # 从主文件删除已提取区间（降序）
    keep = [True] * len(lines)
    for cs, e, n, _ in blocks:
        for i in range(cs, e+1):
            keep[i] = False
    new_lines = [l for i, l in enumerate(lines) if keep[i]]

    # 收缩连续空行（删除方法后留下的 ≥3 连续空行 → 1 空行）
    collapsed = []
    blank = 0
    for l in new_lines:
        if l.strip() == '':
            blank += 1
            if blank > 1:
                continue
        else:
            blank = 0
        collapsed.append(l)
    new_lines = collapsed

    # 在最后一个 import 后插入 part 声明
    last_import = max(i for i, l in enumerate(new_lines) if l.startswith('import '))
    decls = ["part 'shell_parts/%s.dart';" % d for d in DOMAINS]
    new_lines[last_import+1:last_import+1] = [d + '\n' for d in decls] + ['\n']

    # 在 initState 前插入 _applyState 包装
    for i, l in enumerate(new_lines):
        if l.strip() == 'void initState() {':
            # 向上找 @override
            j = i - 1
            while j > 0 and new_lines[j].strip() in ('', '@override'):
                j -= 1
            insert_at = j + 1
            wrapper = [
                '  /// 供 part 扩展调用的 setState 包装（extension 无法直接访问 protected 成员）\n',
                '  void _applyState(VoidCallback fn) => setState(fn);\n\n',
            ]
            # 若上面是 @override 行，插到它前面
            new_lines[insert_at:insert_at] = wrapper
            break

    with open(SRC, 'w', encoding='utf-8', newline='') as f:
        f.writelines(new_lines)
    print(f'moved {moved_lines} lines into {len(DOMAINS)} part files')
    print(f'desktop_shell.dart now: {len(new_lines)} lines')

if __name__ == '__main__':
    main()
