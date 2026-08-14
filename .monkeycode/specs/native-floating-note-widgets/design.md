# 原生悬浮速记窗 + 任务/阅读小部件 技术设计

> 参考：QuickDaily 源码 `/tmp/opencode/QuickDaily/app/src/main/java/com/quickdaily/`
> 对应文件：`FloatingNoteService.kt` / `NoteEditActivity.kt` / `QuickNoteWidget.kt` / `TaskWidget.kt` / `QuickDailyReadWidget.kt` / `FloatingNoteModels.kt` / `FloatingNoteSaveUseCase.kt`

## 一、总体架构

```
┌─ 桌面小部件(速记/任务/阅读) ─┐   ┌─ 磁贴 ─┐
└────────────┬───────────────┘   └───┬───┘
             ▼                        ▼
      QuickNoteWidgetProvider   QuickNoteTileService
             │                        │
             └────────────┬───────────┘
                          ▼
                 FloatingNoteService
                  (TYPE_APPLICATION_OVERLAY 系统悬浮窗)
                          │
              ┌───────────┴────────────┐
              ▼                        ▼
    原生 md 写入                 前台服务通知(保活)
  <filesDir>/MD文章/xxx.md
              │
              ▼ (Flutter 启动时)
      StorageService 扫描导入 → drafts.json 草稿箱
```

### 关键决策

1. **悬浮窗承载**：用 `FloatingNoteService`（`LifecycleService` + `WindowManager.addView`）实现系统级悬浮窗，完全独立于 Flutter 引擎。需要 `SYSTEM_ALERT_WINDOW` 权限 + 前台服务。
2. **数据协同**：原生只写 md 文件到 `<filesDir>/MD文章/`；Flutter 侧扫描导入，不碰 `drafts.json`（可能加密）。
3. **入口改造**：小部件/磁贴从"拉起 MainActivity"改为"启动 FloatingNoteService"。

## 二、原生侧组件

### 2.1 FloatingNoteService（核心，对应 QuickDaily FloatingNoteService.kt）

| 项 | 设计 |
|---|---|
| 类型 | `Service`（前台服务，`foregroundServiceType="specialUse"`） |
| 悬浮层 | `WindowManager` + `TYPE_APPLICATION_OVERLAY`，宽 `0.88*屏宽`、高 `0.35*屏高`（min 280dp x 220dp） |
| 位置 | 居中偏上 `(w/2, 0.25*屏高)`，可拖拽，SharedPreferences 记忆 `x/y` |
| 焦点 | `SOFT_INPUT_ADJUST_RESIZE or SOFT_INPUT_STATE_ALWAYS_VISIBLE` 自动弹键盘 |
| 关闭 | 外部点击（`FLAG_WATCH_OUTSIDE_TOUCH` + `ACTION_OUTSIDE`）、返回键、右上角 × |
| 保活 | `startForeground` + 常驻通知（"速记悬浮窗正在运行"） |
| 动作 | `ACTION_SHOW`（带 source/prefill/target）、`ACTION_HIDE`、`ACTION_REFRESH` |

**UI 结构**（原生 LinearLayout，避免引入 Compose 依赖）：

```
root (圆角卡片背景)
├─ titleBar (可拖拽 GestureDetector，长按拖动)
│  ├─ 标题 TextView（"速记"）
│  ├─ 保存按钮
│  └─ 关闭按钮
├─ EditText (多行, 自动聚焦, hint "写点什么...")
└─ toolbarRow
   ├─ 时间戳按钮
   ├─ 加粗按钮 (包裹 **)
   ├─ 列表按钮 (- 前缀)
   └─ 保存 FilledButton
```

### 2.2 NativeQuickNoteStore（原生数据层）

负责速记文本持久化与落盘，对应 QuickDaily `FloatingNoteDraftStore` + `FloatingNoteSaveUseCase` 合并：

| 方法 | 职责 |
|---|---|
| `loadDraft(context, targetKey)` | SharedPreferences 读取草稿（文本 + 光标 + target） |
| `persistDraft(context, text, ...)` | SharedPreferences 写草稿（防进程杀丢失） |
| `clearDraft(context, targetKey)` | 清除草稿 |
| `saveToMd(context, text, targetPath)` | 构造 md：锚点 + 时间戳 + 内容 → 写入 `<filesDir>/MD文章/<ts>_<firstLine>.md` |
| `listMdFiles(context)` | 列出 `MD文章/` 下待导入文件 |
| `markImported(context, file)` | 写 `.imported` 标记文件（避免重复导入） |

**md 文件命名**：`<epochMillis>_<标题截断>.md`，标题取首行去 markdown 前缀，空则 `速记`。

**md 内容**（对齐 Flutter `QuickNoteTemplate.compose` + 现有草稿导出格式）：
```markdown
<anchor if set>
<timestamp if enabled>
<user text>
```
时间戳格式复用 Flutter `TimestampFormat` 各 key（date/time/datetime/iso/slash/cn/compact）。

### 2.3 入口改造

**QuickNoteWidgetProvider**：`onUpdate` 中点击 PendingIntent 改为 → `FloatingNoteService.showIntent(context, source=WIDGET)`。
**QuickNoteTileService**：`onClick` 改为启动 `FloatingNoteService`（不再拉起 MainActivity）。
桌面图标保持启动 MainActivity（主应用），不做悬浮窗路由。

### 2.4 任务小部件 TaskWidgetProvider（对应 TaskWidget.kt）

- `AppWidgetProvider`，布局 `widget_tasks.xml`（标题 + 任务列表 + 刷新按钮）。
- 数据源：读取 `MD文章/` 最新一篇草稿的 md 内容，解析 `- [ ]` / `- [x]` 行。
- 点击行 → `onReceive` 中 `ACTION_TOGGLE_TASK` → 读文件改行写回 → `notifyAppWidgetViewDataChanged` 刷新。
- RemoteViews + `RemoteViewsService` 支持列表；Android 12+ 用 collection。
- 空态：「暂无待办事项」。

### 2.5 阅读小部件 ReadWidgetProvider（对应 QuickDailyReadWidget.kt）

- 布局 `widget_diary_read.xml`（标题 + 内容列表 + 眼睛开关 + 加号 + 主页按钮）。
- 数据源：读取指定草稿 md 内容，预览渲染。
- markdown 渲染开关（`render_markdown` SharedPreferences）+ 任务行勾选。
- 「加号」→ 速记悬浮窗；「主页」→ 打开 MainActivity 对应草稿。

### 2.6 AndroidManifest 新增

```xml
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>
<service android:name=".FloatingNoteService" android:foregroundServiceType="specialUse" ...>
    <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" android:value="quick note overlay editor"/>
</service>
<activity android:name=".MainActivity" ...>（桌面图标/主应用，维持现状）</activity>
<receiver android:name=".TaskWidgetProvider" ...>
<receiver android:name=".ReadWidgetProvider" ...>
```

## 三、Flutter 侧改动

### 3.1 md 扫描导入（storage_service.dart 新增）

```dart
/// 扫描 MD文章 目录中未导入的 md，转成草稿 Article
Future<List<Article>> importNativeQuickNotes() async {
  final dir = await mdArticlesDir();
  // 遍历 *.md，跳过已被标记导入的（存在 .imported 标记文件）
  // 解析：首行 -> 标题，正文 -> content，取文件名时间戳 -> createdAt
  // 生成 Article(id, title, content, isDraft: true, ...)
  // 写入 .imported 标记，避免重复导入
}
```

### 3.2 启动时调用导入

`_RootShellState` 初始化草稿加载后调用 `importNativeQuickNotes()`，把导入结果并入 `drafts` 列表。

### 3.3 遵循 code-splitting-guide

- 新方法放入 `lib/mixins/editor_xxx_ext.dart`（导入逻辑属草稿域 → `editor_draft_ext.dart` 或 storage 服务）。
- Flutter 侧无新增巨型文件。

## 四、数据格式约定

### md 文件（原生写入 / Flutter 导入）
- 文件名：`<epochMillis>_<title>.md`
- 内容：锚点（可选）+ 时间戳（可选）+ 用户文本，UTF-8。
- 无 frontmatter（速记草稿）。

### 导入标记
- 每个 md 文件旁生成 `<basename>.md.imported` 标记文件；Flutter 扫描时跳过已标记文件。

### 任务行格式
- 遵循 markdown 任务列表：`- [ ] 任务描述`、`- [x] 任务描述`。

## 五、权限

### 5.1 现行方案（第三轮迭代后）：透明 Activity 悬浮窗

| 权限 | 用途 | 申请时机 |
|---|---|---|
| （无需悬浮窗权限） | 悬浮速记窗改为透明 Activity（`QuickNoteLauncherActivity` + `note_edit_view.xml`）直接弹出编辑卡片，不经过 WindowManager，不依赖前台服务 | 点击小部件时系统直接拉起 Activity |
| FOREGROUND_SERVICE(+SPECIAL_USE) | 仅作兜底保留（FloatingNoteService），当前入口不再启动 | 无 |

> 变更原因：用户实测 `Settings.canDrawOverlays()` 返回 true 但 `addView(TYPE_APPLICATION_OVERLAY)` 被国产 ROM（MIUI/HyperOS/ColorOS/EMUI）拒绝，出现"无法显示悬浮窗"。改用 QuickDaily `NoteEditActivity` 同款透明 Activity 方案绕开 SYSTEM_ALERT_WINDOW 权限，兼容所有 ROM。
>
> 变更实现：`QuickNoteLauncherActivity` 由"权限检查中转"升级为"悬浮编辑窗本体"——加载 `note_edit_view` 布局（全屏半透明遮罩 + 居中偏上 88%×35% 输入卡片），点击遮罩/关闭键关闭，恢复/持久化草稿，插入时间戳/加粗/列表工具，保存写入 `<filesDir>/MD文章/` 并刷新三个小部件。`windowSoftInputMode="adjustResize"` 保证键盘弹出不遮挡输入区。

### 5.2 历史方案（已废弃）：Overlay 悬浮窗 + 前台服务

| 权限 | 用途 | 申请时机 |
|---|---|---|
| SYSTEM_ALERT_WINDOW | 系统悬浮窗 | 首次点小部件/磁贴未授权时引导去设置页 |
| FOREGROUND_SERVICE(+SPECIAL_USE) | 悬浮窗前台服务保活 | 启动服务时自动 |
| POST_NOTIFICATIONS | 前台服务通知 | Android 13+ 运行时 |

> 该方案在第一、二轮迭代中实现，第三轮起被透明 Activity 方案取代。FloatingNoteService 代码与清单声明保留作兜底，但小部件/磁贴入口不再启动它。

## 六、风险与权衡

1. **原生 UI 与 Flutter 主题不一致**：原生用 Material 风格，悬浮窗配色取系统深/浅色，接受差异。
2. **Compose 依赖**：为避免引入 Compose（gradle 依赖大增 + 本地无 SDK 编译风险），原生 UI 用经典 View 体系实现，不引入 Jetpack Compose。
3. **本地无法编译验证**：无 Android SDK，Java 代码编译依赖 CI；需严格对照 QuickDaily 语法与 Android API 编写，Flutter 侧可本地 analyze。
4. **导入去重**：靠 `.imported` 标记文件，若 Flutter 侧删除草稿需同时清理标记，否则草稿删除后重开会重新导入 —— 按"标记文件与 md 同生命周期"处理。
