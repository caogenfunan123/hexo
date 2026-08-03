/// 桌面版主入口
/// 负责：窗口管理、系统托盘、全局快捷键、拖拽文件导入、布局记忆
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:system_tray/system_tray.dart';
import 'package:file_picker/file_picker.dart';

import '../theme/app_theme.dart';
import 'desktop_shell.dart';

/// 桌面版启动入口（由 lib/main.dart 根据平台自动调用，或通过 --target 直接使用）
Future<void> runDesktopApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  try {
    // await hotKeyManager.unregisterAll();
  } catch (_) {}
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
  static const _layoutKey = 'desktop_layout';
  Offset _windowPosition = const Offset(100, 80);
  Size _windowSize = const Size(1280, 800);
  bool _isMaximized = false;

  // ── 主题 ──
  ThemeMode _themeMode = ThemeMode.system;

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
    super.dispose();
  }

  Future<void> _initAll() async {
    await _restoreLayout();
    await _initWindow();
    _initSystemTray();
    // _registerHotkeys();
  }

  // ============================================================
  // 窗口布局记忆
  // ============================================================

  Future<void> _restoreLayout() async {
    try {
      final file = File('${Directory.systemTemp.path}/hexo_desktop_layout.json');
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
    } catch (_) {}
  }

  Future<void> _saveLayout() async {
    try {
      final file = File('${Directory.systemTemp.path}/hexo_desktop_layout.json');
      await file.writeAsString(jsonEncode({
        'x': _windowPosition.dx,
        'y': _windowPosition.dy,
        'w': _windowSize.width,
        'h': _windowSize.height,
        'maximized': _isMaximized,
      }));
    } catch (_) {}
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
          await _systemTray.destroy();
          await windowManager.destroy();
        }),
      ]);
      await _systemTray.setContextMenu(menu);
      _isTrayReady = true;
    } catch (_) {
      _isTrayReady = false;
    }
  }

  // ============================================================
  // 全局快捷键
  // ============================================================

  void _registerHotkeys() async {
    // TODO: fix hotkey_manager compatibility with Flutter 3.24
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
    return DropTarget(
      onDragDone: (details) {
        for (final file in details.files) {
          if (file.path.endsWith('.md') || file.path.endsWith('.markdown')) {
            _loadMdFile(file.path);
          }
        }
      },
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'AI 博客编辑器',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: _themeMode,
        home: DesktopShell(
          key: DesktopApp.shellKey,
          onToggleAppTheme: _toggleAppTheme,
        ),
      ),
    );
  }
}