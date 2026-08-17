# 需求实施计划

- [ ] 1. 创建 NavCustomConfig 数据模型与 UiSettings 持久化
  - 新建 `lib/models/nav_custom_config.dart`：`customized`、`visible`（Map<String,bool>）、`pinnedOrder`（List<String>），含 copyWith/toJson/fromJson，缺省回退默认值
  - 在 `lib/models/ui_settings.dart` 增加 `NavCustomConfig navCustom` 字段（默认 `const NavCustomConfig()`），`copyWith`、`toJson`、`fromJson` 处理嵌套序列化与旧配置缺省回退
  - 实现 Requirement 3-AC2/AC6 与 Requirement 5 数据持久化基础

- [ ] 2. 实现 navVisibleFor 组合过滤器与入口去重映射
  - 在 `lib/desktop/feature_entries.dart` 新增 `navVisibleFor(id, mode, extras, navCustom, registry)` 纯函数：customized=true 时按 visible 偏好，否则回落 ModeVisibilityFilter 逻辑；未知 id 忽略
  - 目录去重：`site_manager` 保留、`add_site`/`blog_site_manager` 标记 hidden；`cloud_sync` 为同步中心保留，`remote_posts`/`sync_status`/`history` 标记 hidden；确认 `dashboard` hidden
  - 实现 Requirement 1 全部 4 条、Requirement 3-AC6、Requirement 4-AC1/AC2/AC3
  - [ ]* 2.1 为 navVisibleFor 编写单元测试：未自定义回落/自定义显示/自定义隐藏/未知 id/部分未配置项回落

- [ ] 3. 侧边栏结构改造（left_panel.dart）
  - 顶部固定区：首页/新建文章/草稿箱/站点列表 + 按 `pinnedOrder` 渲染的固定项，均经 `navVisibleFor` 过滤
  - 分组区：保留 7 分组折叠，分组内各项渲染前改用 `navVisibleFor` 判定（替换 `NavEntries.visibleEntry` 调用点）
  - 底部入口："全部功能"、"自定义侧边栏"按钮，不随折叠消失
  - 全部入口可自定义显隐；侧边栏为空时显示兜底提示与"恢复默认"按钮
  - 传参：`DesktopLeftPanel` 增加 `NavCustomConfig navCustom` 传入，`desktop_shell.dart` 接线
  - 实现 Requirement 2-AC1/AC2、Requirement 3 全部、Requirement 4-AC4/AC5
  - [ ]* 3.1 验证侧边栏折叠状态持久化不受改造影响

- [ ] 4. 全部功能 Hub 页（all_features_screen.dart）
  - 新建 `lib/screens/all_features_screen.dart`：按分组分区渲染入口网格（图标+名称），每格有显隐开关与置顶按钮，隐藏项显示"已隐藏"角标且始终可访问
  - 顶部搜索框按名称过滤；无匹配显示空态
  - 经 ShellActionBus 打开（`onOpenAllFeatures`），桌面与移动端复用同一页面
  - 实现 Requirement 2-AC3/AC4/AC5/AC6、Requirement 4-AC3

- [ ] 5. 自定义侧边栏对话框（sidebar_customize_dialog.dart）
  - 新建 `lib/desktop/widgets/sidebar_customize_dialog.dart`：分组分区列出全部入口，每项图标+名称+显隐开关+置顶按钮
  - 实时生效：改动即写回 UiSettings 并通过 LayoutController.notifyListeners 触发重建
  - "恢复默认"按钮：重置 customized=false、空 visible、空 pinnedOrder
  - 实现 Requirement 3-AC1 至 AC5
  - [ ]* 5.1 验证对话框改动与侧边栏/移动端导航实时联动

- [ ] 6. 移动端导航接线（main.dart）
  - MobilePage 抽屉入口渲染改用 `navVisibleFor` 过滤
  - `_navigateTo` 简易模式重定向逻辑判据替换为 `navVisibleFor`（原 `NavEntries.visibleEntry` 调用点）
  - 抽屉尾部增加"全部功能"与"自定义侧边栏"入口
  - 实现 Requirement 5 全部 3 条与 Requirement 2-AC3 移动端部分
  - [ ]* 6.1 验证移动端抽屉与桌面侧边栏入口集合一致

- [ ] 7. 全部博客管理快照缓存
  - 在 `lib/core/repository/static_blog_repository.dart` 增加快照模型与缓存读写：`reloadIfChanged()` 基于仓库文件指纹（lastModified 最大值 + 文件数量 + 各文件 sha）判断是否有更新，无更新直接返回缓存；有更新只重拉该仓库并更新缓存
  - 在 `lib/screens/all_static_blogs_screen.dart` 改造加载流程：initState 先读缓存立即渲染，再按仓库逐个比对基线，仅对变化的仓库发起网络请求；页面增加"刷新"按钮强制全量重拉并重置缓存
  - 缓存文件缺省/损坏时回退全量加载，不阻断页面展示
  - 实现 Requirement 6 全部 7 条
  - [ ]* 7.1 单元测试：无更新仓库跳过网络请求、有更新仓库部分重拉、缓存损坏回退全量

- [ ] 8. 检查点 - 纯 Dart 静态校验
  - 用 `/tmp/opencode/dart/dart-sdk/bin/dart analyze` 校验全部改动文件无错误（flutter_lints/包解析噪音除外）
  - 校验前只用 Anacron 排查问题，确信无残留错误

- [ ] 9. 一次性代码审查与错误复盘
  - 全量 review 本次改动 diff：入口 id 稳定性、序列化兼容性、双端过滤一致性、空态兜底、缓存一致性
  - 修复发现的全部问题后再提交