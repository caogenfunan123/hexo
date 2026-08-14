# 原生悬浮速记窗 + 任务/阅读小部件 实施计划

## 阶段 1：原生悬浮速记窗核心

- [x] 1. 实现原生速记数据层 NativeQuickNoteStore
  - [x] 1.1 SharedPreferences 草稿读写（loadDraft / persistDraft / clearDraft）
  - [x] 1.2 md 落盘 saveToMd：构造锚点+时间戳+内容 → `<filesDir>/MD文章/<epoch>_<title>.md`
  - [x] 1.3 时间戳格式化（对齐 Flutter TimestampFormat 各 key）

- [x] 2. 实现悬浮窗 UI 布局
  - [x] 2.1 布局文件 `floating_note_view.xml`：标题栏(标题/保存/关闭) + 多行 EditText + 工具栏(时间戳/加粗/列表/保存)
  - [x] 2.2 主题 `styles.xml` 新增透明悬浮样式（`windowDisablePreview`、透明背景）

- [x] 3. 实现 FloatingNoteService
  - [x] 3.1 `TYPE_APPLICATION_OVERLAY` WindowManager 悬浮窗：0.88x0.35 尺寸、居中偏上、可拖拽、位置记忆
  - [x] 3.2 自动聚焦弹键盘（`SOFT_INPUT_ADJUST_RESIZE or SOFT_INPUT_STATE_ALWAYS_VISIBLE`）
  - [x] 3.3 外部点击/返回键/× 关闭；关闭策略（save_on_close / 保留草稿）
  - [x] 3.4 前台服务保活 + 常驻通知（specialUse 类型）
  - [x] 3.5 ACTION_SHOW / ACTION_HIDE / ACTION_REFRESH 动作 + showIntent/hideIntent 构造

- [x] 4. 入口改造：小部件与磁贴改为拉起悬浮窗
  - [x] 4.1 QuickNoteWidgetProvider 点击 → FloatingNoteService.showIntent（不再启动 MainActivity）
  - [x] 4.2 QuickNoteTileService 点击 → 启动 FloatingNoteService
  - [x] 4.3 AndroidManifest：SYSTEM_ALERT_WINDOW / FOREGROUND_SERVICE(+SPECIAL_USE) 权限 + service 声明
  - [x] 4.4 悬浮窗权限未授权时引导打开系统设置页（桌面图标维持打开主应用，不做悬浮窗路由）

- [x] 5. 检查点 - 入口不再打开 MainActivity，悬浮窗可弹出并可保存 md（Java 侧依赖 CI 编译验证）

## 阶段 2：Flutter 侧草稿同步

- [x] 6. Flutter 侧 md 扫描导入
  - [x] 6.1 storage_service.dart 新增 `importNativeQuickNotes()`：扫描 `MD文章/` 未导入 md → Article 草稿，写 `.imported` 标记
  - [x] 6.2 `_RootShellState` 初始化时调用导入并并入草稿列表（main.dart _bootstrap）
  - [x] 6.3 遵循 code-splitting-guide：导入逻辑放 StorageService，不堆 main.dart

- [x] 7. 检查点 - `flutter analyze --no-pub` 0 error/warning；原生 md 文件能在 App 草稿箱看到

## 阶段 3：任务小部件

- [x] 8. 实现任务小部件
  - [x] 8.1 布局 `widget_tasks.xml`（标题 + 任务列表 + 刷新按钮）
  - [x] 8.2 TaskWidgetProvider：读最新草稿 md，解析 `- [ ]` / `- [x]` 行展示（RemoteViewsService 渲染）
  - [x] 8.3 点击行勾选切换（ACTION_TOGGLE_TASK）：读文件改行写回 + 刷新
  - [x] 8.4 空态文案「暂无待办事项」+ 刷新动作
  - [x] 8.5 AndroidManifest receiver 声明 + `task_widget_info.xml`

## 阶段 4：阅读小部件

- [x] 9. 实现阅读小部件
  - [x] 9.1 布局 `widget_diary_read.xml`（标题 + 内容预览 + 眼睛开关 + 主页按钮）
  - [x] 9.2 ReadWidgetProvider：读最新速记草稿 md 内容预览
  - [x] 9.3 眼睛开关切换 原文/任务 视图（SharedPreferences `read_widget` 记忆）
  - [x] 9.4 主页按钮→MainActivity；任务视图点击行可勾选
  - [x] 9.5 AndroidManifest receiver 声明 + `read_widget_info.xml`

## 阶段 5：收尾

- [x] 10. 收尾
  - [x] 10.1 旧入口逻辑：QuickNoteIntent 保留（MainActivity 冷启动投递仍用），小部件/磁贴已不再走它
  - [x] 10.2 `flutter analyze --no-pub` 0 error/warning
  - [x] 10.3 提交推送触发 CI 构建验证
