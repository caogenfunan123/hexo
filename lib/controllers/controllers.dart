/// 控制器模块导出
///
/// 架构分层（参考 VS Code MVVM + super_editor Document/Composer）：
///   DocumentController — 纯数据层（对标 TextModel / Document）
///   EditorController   — 视图状态层（对标 ViewModel / Composer）
///   FrontMatterController — FrontMatter 元数据管理
///   LayoutController   — 布局状态
///   SyncController     — 同步状态
///   SiteController     — 站点管理
///   UiStateController  — 全局 UI 状态
library;

export 'document_controller.dart';
export 'editor_controller.dart';
export 'layout_controller.dart';
export 'sync_controller.dart';
export 'site_controller.dart';
export 'frontmatter_controller.dart';
export 'ui_state_controller.dart';