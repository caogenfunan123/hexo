/// 桌面版主入口
/// 负责：窗口管理、系统托盘、全局快捷键、拖拽文件导入、布局记忆、Provider 状态注入
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:system_tray/system_tray.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../theme/app_theme.dart';
import '../models/design_config.dart';
import '../controllers/controllers.dart';
import 'desktop_shell.dart';

/// 桌面版启动入口（由 lib/main.dart 根据平台自动调用，或通过 --target 直接使用）
Future<void> runDesktopApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面端必须初始化 sqflite FFI，否则 SQLite 操作会抛 MissingPluginException
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await windowManager.ensureInitialized();
  try {
    // await hotKeyManager.unregisterAll();
  } catch (e) {
    debugPrint('HotKey unregister error: $e');
  }
  runApp(const DesktopApp());
}

/// 命令行入口：flutter build windows --target=lib/desktop/desktop_main.dart
void main() async {
  await runDesktopApp();
}

class DesktopApp extends StatefulWidget {
  const DesktopApp({super.key});

  static final GlobalKey<DesktopShellState> shellKey = GlobalKey<DesktopShellState>();

  @override
  State<DesktopApp> createState() => _DesktopAppState();
}

class _DesktopAppState extends State<DesktopApp> with WindowListener {
  final SystemTray _systemTray = SystemTray();
  bool _isTrayReady = false;

  // ── 布局记忆 ──
  Offset _windowPosition = const Offset(100, 80);
  Size _windowSize = const Size(1280, 800);
  bool _isMaximized = false;

  // ── 主题 ──
  ThemeMode _themeMode = ThemeMode.system;
  DesignConfig _designConfig = const DesignConfig();

  // ── 控制器（全局单例，注入到 Provider 树） ──
  final DocumentController _docCtrl = DocumentController();
  final LayoutController _layoutCtrl = LayoutController();
  final EditorController _editorCtrl = EditorController();
  final SyncController _syncCtrl = SyncController();
  final SiteController _siteCtrl = SiteController();
  final FrontMatterController _frontMatterCtrl = FrontMatterController();
  final UiStateController _uiStateCtrl = UiStateController();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initAll();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    // hotKeyManager.unregisterAll();
    _docCtrl.dispose();
    _layoutCtrl.dispose();
    _editorCtrl.dispose();
    _syncCtrl.dispose();
    _siteCtrl.dispose();
    _frontMatterCtrl.dispose();
    _uiStateCtrl.dispose();
    super.dispose();
  }

  Future<void> _initAll() async {
    await _restoreLayout();
    await _initWindow();
    _initSystemTray();
    _initShortcuts();
  }

  // ============================================================
  // 窗口布局记忆
  // ============================================================

  /// 获取布局文件路径（迁移到应用私有目录，避免系统清理丢失）
  Future<File> _layoutFile() async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory('${appDir.path}/.hexo');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    // 兼容旧路径迁移
    final oldFile = File('${Directory.systemTemp.path}/hexo_desktop_layout.json');
    final newFile = File('${dir.path}/desktop_layout.json');
    if (await oldFile.exists() && !await newFile.exists()) {
      try {
        await oldFile.copy(newFile.path);
      } catch (e) {
        debugPrint('Layout file migration error: $e');
      }
    }
    return newFile;
  }

  Future<void> _restoreLayout() async {
    try {
      final file = await _layoutFile();
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _windowPosition = Offset(
          (json['x'] as num?)?.toDouble() ?? 100,
          (json['y'] as num?)?.toDouble() ?? 80,
        );
        _windowSize = Size(
          (json['w'] as num?)?.toDouble() ?? 1280,
          (json['h'] as num?)?.toDouble() ?? 800,
        );
        _isMaximized = json['maximized'] == true;
      }
    } catch (e) {
      debugPrint('Restore layout error: $e');
    }
  }

  Future<void> _saveLayout() async {
    try {
      final file = await _layoutFile();
      await file.writeAsString(jsonEncode({
        'x': _windowPosition.dx,
        'y': _windowPosition.dy,
        'w': _windowSize.width,
        'h': _windowSize.height,
        'maximized': _isMaximized,
      }));
    } catch (e) {
      debugPrint('Save layout error: $e');
    }
  }

  Future<void> _initWindow() async {
    final windowOptions = WindowOptions(
      size: _windowSize,
      minimumSize: const Size(900, 600),
      center: _windowPosition == const Offset(100, 80),
      title: 'AI 博客编辑器',
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Colors.white,
      skipTaskbar: false,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      if (!(_windowPosition == const Offset(100, 80))) {
        await windowManager.setPosition(_windowPosition);
      }
      if (_isMaximized) {
        await windowManager.maximize();
      }
    });
  }

  // ── 窗口事件监听 ──

  @override
  void onWindowResize() async {
    if (_isMaximized) return;
    final size = await windowManager.getSize();
    _windowSize = size;
    _saveLayout();
  }

  @override
  void onWindowMove() async {
    if (_isMaximized) return;
    final pos = await windowManager.getPosition();
    _windowPosition = pos;
    _saveLayout();
  }

  @override
  void onWindowMaximize() {
    _isMaximized = true;
    _saveLayout();
  }

  @override
  void onWindowUnmaximize() {
    _isMaximized = false;
  }

  @override
  void onWindowClose() async {
    await _saveLayout();
    // 关闭前强制落盘所有未保存内容
    await _editorCtrl.onBeforeClose();
    // 最小化到托盘而不是关闭
    if (_isTrayReady) {
      await windowManager.hide();
    } else {
      await windowManager.destroy();
    }
  }

  // ============================================================
  // 系统托盘
  // ============================================================

  Future<void> _initSystemTray() async {
    try {
      await _systemTray.initSystemTray(
        title: 'AI 博客编辑器',
        iconPath: '', // 使用默认图标
        toolTip: 'AI 博客编辑器 - 桌面版',
      );

      final menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(label: '显示窗口', onClicked: (_) => windowManager.show()),
        MenuItemLabel(label: '新建文章', onClicked: (_) {
          windowManager.show();
          _invokeShell('new');
        }),
        MenuSeparator(),
        MenuItemLabel(label: '退出', onClicked: (_) async {
          await _editorCtrl.onBeforeClose();
          await _systemTray.destroy();
          await windowManager.destroy();
        }),
      ]);
      await _systemTray.setContextMenu(menu);
      _isTrayReady = true;
    } catch (e) {
      debugPrint('System tray init error: $e');
      _isTrayReady = false;
    }
  }

  // ============================================================
  // 全局快捷键
  // ============================================================

  /// 使用 Flutter 内置 Shortcuts 系统替代 hotkey_manager
  /// 快捷键仅在应用窗口获得焦点时生效
  Map<ShortcutActivator, VoidCallback> _shortcuts = {};

  void _initShortcuts() {
    _rebuildShortcuts();
  }

  /// 重建快捷键绑定（合并默认 + 自定义）
  void _rebuildShortcuts() {
    final newShortcuts = <ShortcutActivator, VoidCallback>{};

    // 1. 添加硬编码默认绑定
    _addDefaultBindings(newShortcuts);

    // 2. 用自定义快捷键覆盖
    final customShortcuts = _editorCtrl.customShortcuts;
    for (final entry in customShortcuts.entries) {
      final action = entry.key;
      final shortcutStr = entry.value;
      if (shortcutStr.isEmpty) continue;

      final activator = _parseShortcut(shortcutStr);
      if (activator == null) continue;

      // 移除冲突的默认绑定
      newShortcuts.remove(activator);
      // 添加自定义绑定
      newShortcuts[activator] = () => _invokeShell(action);
    }

    _shortcuts = newShortcuts;
    if (mounted) setState(() {});
  }

  /// 默认快捷键绑定（不可被覆盖的硬编码映射）
  void _addDefaultBindings(Map<ShortcutActivator, VoidCallback> bindings) {
    bindings.addAll({
      // 文件操作
      const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => _invokeShell('newArticle'),
      const SingleActivator(LogicalKeyboardKey.keyO, control: true): () => openMarkdownFile(),
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _invokeShell('saveLocal'),
      const SingleActivator(LogicalKeyboardKey.keyP, control: true): () => _invokeShell('publish'),
      const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): () => _invokeShell('saveAs'),
      // 面板切换
      const SingleActivator(LogicalKeyboardKey.keyL, control: true): () => _invokeShell('toggleLeftPanel'),
      const SingleActivator(LogicalKeyboardKey.keyE, control: true): () => _invokeShell('toggleRightDrawer'),
      // 工作模式
      const SingleActivator(LogicalKeyboardKey.keyF, control: true, shift: true): () => _invokeShell('focusMode'),
      const SingleActivator(LogicalKeyboardKey.keyE, control: true, shift: true): () => _invokeShell('sourceMode'),
      const SingleActivator(LogicalKeyboardKey.keyW, control: true, shift: true): () => _invokeShell('workspaceMode'),
      // 编辑操作 — Ctrl+B/I 由 Flutter TextField 原生处理，不在全局注册
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _invokeShell('find'),
      const SingleActivator(LogicalKeyboardKey.keyH, control: true): () => _invokeShell('replace'),
      // 命令面板
      const SingleActivator(LogicalKeyboardKey.keyP, control: true, shift: true): () => _invokeShell('commandPalette'),
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => _invokeShell('commandPalette'),
      // 窗口
      const SingleActivator(LogicalKeyboardKey.escape): () => _invokeShell('escape'),
    });
  }

  /// 解析快捷键字符串 → SingleActivator
  /// 支持格式: "Ctrl+X", "Ctrl+Shift+X", "Alt+X", "Ctrl+Alt+Shift+X", "F1", "Escape"
  static SingleActivator? _parseShortcut(String shortcut) {
    if (shortcut.isEmpty) return null;
    final parts = shortcut.split('+').map((s) => s.trim()).toList();
    if (parts.isEmpty) return null;

    bool control = false, shift = false, alt = false, meta = false;
    String? keyName;

    for (final part in parts) {
      switch (part.toLowerCase()) {
        case 'ctrl':
        case 'control':
          control = true;
          break;
        case 'shift':
          shift = true;
          break;
        case 'alt':
          alt = true;
          break;
        case 'meta':
        case 'cmd':
        case 'win':
          meta = true;
          break;
        default:
          keyName = part;
      }
    }

    if (keyName == null) return null;
    final key = _keyFromName(keyName);
    if (key == null) return null;

    return SingleActivator(key, control: control, shift: shift, alt: alt, meta: meta);
  }

  /// 键名 → LogicalKeyboardKey
  static LogicalKeyboardKey? _keyFromName(String name) {
    final upper = name.toUpperCase();

    // 单字母 A-Z
    if (upper.length == 1 && upper.codeUnitAt(0) >= 65 && upper.codeUnitAt(0) <= 90) {
      return LogicalKeyboardKey(0x60 + upper.codeUnitAt(0) - 64); // 'a'=0x61
    }

    // 数字 0-9
    if (name.length == 1 && name.codeUnitAt(0) >= 48 && name.codeUnitAt(0) <= 57) {
      return LogicalKeyboardKey(name.codeUnitAt(0));
    }

    // F1-F24
    if (upper.startsWith('F')) {
      final num = int.tryParse(name.substring(1));
      if (num != null && num >= 1 && num <= 24) {
        return LogicalKeyboardKey(0x80000000 + 0x70000 + num - 1);
      }
    }

    // 特殊键
    switch (upper) {
      case 'ESCAPE': case 'ESC': return LogicalKeyboardKey.escape;
      case 'SPACE': return LogicalKeyboardKey.space;
      case 'ENTER': case 'RETURN': return LogicalKeyboardKey.enter;
      case 'TAB': return LogicalKeyboardKey.tab;
      case 'BACKSPACE': return LogicalKeyboardKey.backspace;
      case 'DELETE': case 'DEL': return LogicalKeyboardKey.delete;
      case 'HOME': return LogicalKeyboardKey.home;
      case 'END': return LogicalKeyboardKey.end;
      case 'PAGEUP': case 'PGUP': return LogicalKeyboardKey.pageUp;
      case 'PAGEDOWN': case 'PGDN': return LogicalKeyboardKey.pageDown;
      case 'UP': return LogicalKeyboardKey.arrowUp;
      case 'DOWN': return LogicalKeyboardKey.arrowDown;
      case 'LEFT': return LogicalKeyboardKey.arrowLeft;
      case 'RIGHT': return LogicalKeyboardKey.arrowRight;
      case 'INSERT': case 'INS': return LogicalKeyboardKey.insert;
      case 'COMMA': case ',': return LogicalKeyboardKey.comma;
      case 'PERIOD': case '.': return LogicalKeyboardKey.period;
      case 'SLASH': case '/': return LogicalKeyboardKey.slash;
      case 'BACKSLASH': case '\\': return LogicalKeyboardKey.backslash;
      case 'SEMICOLON': case ';': return LogicalKeyboardKey.semicolon;
      case 'QUOTE': case "'": return LogicalKeyboardKey.quote;
      case 'MINUS': case '-': return LogicalKeyboardKey.minus;
      case 'EQUAL': case '=': return LogicalKeyboardKey.equal;
      default: return null;
    }
  }

  void _invokeShell(String action) {
    final state = DesktopApp.shellKey.currentState;
    if (state == null) return;
    state.handleGlobalAction(action);
  }

  // ============================================================
  // 文件打开对话框
  // ============================================================

  void openMarkdownFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md', 'markdown', 'txt'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    _loadMdFile(path);
  }

  void _loadMdFile(String path) async {
    try {
      final file = File(path);
      final content = await file.readAsString();
      final fileName = path.split('/').last.replaceAll(RegExp(r'\.(md|markdown|txt)$'), '');
      final state = DesktopApp.shellKey.currentState;
      if (state != null) {
        state.openExternalFile(fileName, content, path);
      }
    } catch (e) {
      debugPrint('打开文件失败: $e');
    }
  }

  void _toggleAppTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light
          ? ThemeMode.dark
          : _themeMode == ThemeMode.dark
              ? ThemeMode.system
              : ThemeMode.light;
    });
  }

  // ============================================================
  // 构建
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: _shortcuts,
      child: DropTarget(
        onDragDone: (details) {
          for (final file in details.files) {
            if (file.path.endsWith('.md') || file.path.endsWith('.markdown')) {
              _loadMdFile(file.path);
            }
          }
        },
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: _docCtrl),
            ChangeNotifierProvider.value(value: _layoutCtrl),
            ChangeNotifierProvider.value(value: _editorCtrl),
            ChangeNotifierProvider.value(value: _syncCtrl),
            ChangeNotifierProvider.value(value: _siteCtrl),
            ChangeNotifierProvider.value(value: _frontMatterCtrl),
            ChangeNotifierProvider.value(value: _uiStateCtrl),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'AI 博客编辑器',
            theme: AppTheme.lightFromConfig(_designConfig),
            darkTheme: AppTheme.darkFromConfig(_designConfig),
            themeMode: _themeMode,
            home: DesktopShell(
              key: DesktopApp.shellKey,
              onToggleAppTheme: _toggleAppTheme,
              onShortcutsChanged: _rebuildShortcuts,
              onDesignConfigChanged: (dc) {
                setState(() => _designConfig = dc);
              },
            ),
          ),
        ),
      ),
    );
  }
}