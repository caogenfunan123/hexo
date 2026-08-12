# 需求实施计划

Feature: simple-user-mode

- [ ] 1. 模式状态与数据模型扩展
  - [ ] 1.1 在 `lib/models/ui_settings.dart` 新增 `AppMode` 枚举（simple/standard）与字段 `appMode`、`simpleModeExtras`（List<String>），扩展 `toJson`/`fromJson`/`copyWith`；`appMode` 序列化缺失按引导策略处理（新装默认 simple），`simpleModeExtras` 默认 `const []`
  - [ ] 1.2 在 `lib/models/app_settings.dart` 增加 `appMode` 与 `simpleModeExtras` 的 getter/copyWith 透传（参考现有 deployHooks 透传模式）
  - [ ] 1.3 在 `lib/models/article.dart` 新增可空 `volume` 字段，扩展 `toJson`/`fromJson`/`copyWith`（旧数据回退 null）
  - [ ]* 1.4 为 UiSettings/Article 序列化写单元测试：往返一致、缺失字段回退

- [ ] 2. 入口注册表与可见性过滤
  - [ ] 2.1 新建 `lib/desktop/feature_entries.dart`：定义 `FeatureVisibility`（shown/hidden/optIn）、`FeatureEntry`（id/icon/label/group/action/defaultInSimple）与全量入口注册表，覆盖 left_panel 现有 6 分组全部入口并新增 home 首页入口；id 稳定不可变
  - [ ] 2.2 新建 `ModeVisibilityFilter.visibleFor(AppMode, List<String> extras)`：标准全显；简易模式 shown 显、optIn 依 extras、hidden 不显；纯函数
  - [ ] 2.3 新建设置分区可见性清单（沿用 FeatureEntry/Visibility 语义），定义简易模式隐藏分区：部署钩子/站点 PWA、诊断日志导出 等，保留：基本信息、Git Token、同步定时、存储目录、AI 模型/密钥、代理、图床
  - [ ]* 2.4 为 ModeVisibilityFilter 写单元测试：标准全显 / 简易三态过滤 / extras 白名单 / 未知 id 忽略

- [ ] 3. 桌面侧边栏注册表化与模式过滤（R2/R3）
  - [ ] 3.1 重构 `lib/desktop/widgets/left_panel.dart`：由硬编码 `_navItem` 列表改为消费 `feature_entries.dart` 注册表经 `ModeVisibilityFilter` 过滤后的可见清单渲染分组
  - [ ] 3.2 简易模式下分组重组：展示 首页、编辑器、AI 写作对话、同步与站点（Git/WebDAV/P2P/快照/冲突全部可见）、图床、草稿箱、设置；隐藏 R3 清单入口（AI 专业会话、批量运维、诊断）
  - [ ] 3.3 顶部工具栏精简（R7）：`title_bar` 简易模式隐藏「导出诊断日志、批量站点检测、模型连通性批量测试」，保留搜索/排序/新建文稿

- [ ] 4. 移动端导航过滤（R1/R2）
  - [ ] 4.1 `lib/controllers/layout_controller.dart` 的 `MobilePage` 新增 `home` 枚举，`navigateTo` 边界随枚举更新
  - [ ] 4.2 `lib/mixins/editor_ui_ext.dart` 的 `_buildDrawer` 按 `ModeVisibilityFilter` 过滤移动端导航项（hidden 不渲染，optIn 依 extras）
  - [ ] 4.3 简易模式下当前页不可见时导航重定向到 `home`（R1-6）

- [ ] 5. 首页-卷宗文章列表（R2/R6）
  - [ ] 5.1 新建 `lib/screens/home_screen.dart`：当前卷宗文章列表，按 `Article.volume` 分组（卷1/卷2…，空值归「未分类」），复用草稿列表交互（点击打开文章/新建）
  - [ ] 5.2 实现系统日志过滤：文件名以系统前缀（`llama_diag_log`）开头的条目不展示（R6）
  - [ ] 5.3 桌面 `desktop_shell.dart` 与移动端接载 home tab/页面；编辑器「新建文章/随笔/博客文稿」入口指向编辑器并支持卷宗预填
  - [ ]* 5.4 为系统日志过滤规则写单元测试：`llama_diag_log` 前缀命中、普通文章不误伤

- [ ] 6. 设置界面精简与模式开关（R1/R2）
  - [ ] 6.1 `lib/screens/settings_screen.dart` 分区按可见性清单过滤：简易模式隐藏 部署钩子/PWA、诊断导出 等开发分区，保留 AI 模型/密钥、Token、同步、存储、代理、图床、基本信息
  - [ ] 6.2 设置页新增「简易普通用户模式」开关（Switch，读写 `appMode`），切换后实时通知重建并持久化
  - [ ] 6.3 简易模式下设置页提供「简易模式额外入口」管理（R9）：对 optIn 入口勾选写入 `simpleModeExtras`

- [ ] 7. 模式引导与切换接线（R1）
  - [ ] 7.1 首启引导：新装（无设置文件）默认 simple；存量无 `appMode` 记录时弹出模式选择引导弹窗（简易/标准），选择后持久化
  - [ ] 7.2 桌面 `desktop_shell.dart` 与 `main.dart` 接线模式状态：切换模式触发布局重建（`LayoutController.notifyListeners`），配置不重置
  - [ ] 7.3 `flutter analyze` 全量通过（0 error / 0 warning）

- [ ] 8. 检查点 - 确保模式切换与隐藏逻辑正确
  - 简易模式：首页/AI 对话/同步全部入口可见，专业入口不渲染，设置精简生效
  - 标准模式：全部入口恢复；切换后密钥与仓库配置不丢失
  - 如有疑问请询问用户

- [ ] 9. 提交与 CI 验证
  - [ ] 9.1 提交改动并推送，等待 GitHub Actions 构建通过（APK 产物就绪）
