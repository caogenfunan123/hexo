/// 功能入口注册表与界面模式可见性过滤
///
/// 桌面侧边栏（left_panel）与移动端导航共用同一份入口 id 集合，
/// 简易普通用户模式（AppMode.simple）按可见性规则过滤入口：
/// - shown  默认可见
/// - hidden 始终隐藏（专业开发/运维/诊断）
/// - optIn  默认隐藏，用户可在设置中手动加回（写入 UiSettings.simpleModeExtras）
library;

import '../../models/ui_settings.dart';

/// 简易模式下的入口可见性
enum FeatureVisibility {
  /// 默认可见
  shown,

  /// 始终隐藏（专业入口）
  hidden,

  /// 默认隐藏，可在设置中手动加回
  optIn,
}

/// 功能入口定义（id 一经定义不可变更，用于持久化白名单）
class FeatureEntry {
  final String id;
  final FeatureVisibility simpleVisibility;

  const FeatureEntry(this.id, this.simpleVisibility);
}

/// 简易模式可见性过滤
class ModeVisibilityFilter {
  const ModeVisibilityFilter._();

  /// 简易模式下可见的入口 id 集合
  static Set<String> visibleIds(
    AppMode mode,
    List<String> extras,
    Map<String, FeatureVisibility> registry,
  ) {
    if (mode == AppMode.standard) {
      return registry.keys.toSet();
    }
    final extrasSet = extras.toSet();
    final result = <String>{};
    registry.forEach((id, vis) {
      if (vis == FeatureVisibility.shown) {
        result.add(id);
      } else if (vis == FeatureVisibility.optIn && extrasSet.contains(id)) {
        result.add(id);
      }
    });
    return result;
  }

  /// 判断入口 id 是否在可见集合内
  static bool isVisible(
    String id,
    AppMode mode,
    List<String> extras,
    Map<String, FeatureVisibility> registry,
  ) {
    return visibleIds(mode, extras, registry).contains(id);
  }
}

/// 侧边栏导航入口注册表（桌面 + 移动端共用）
abstract final class NavEntries {
  static const Map<String, FeatureVisibility> registry = {
    // 首页 / 创作
    'home': FeatureVisibility.shown,
    'new_article': FeatureVisibility.shown,
    'drafts': FeatureVisibility.shown,
    // 同步与站点（全部同步功能保留可见）
    'remote_posts': FeatureVisibility.shown,
    'sync_status': FeatureVisibility.shown,
    'history': FeatureVisibility.shown,
    'cloud_sync': FeatureVisibility.shown,
    'p2p_sync': FeatureVisibility.shown,
    'add_site': FeatureVisibility.shown,
    'site_manager': FeatureVisibility.shown,
    'create_site': FeatureVisibility.shown, // 一键建站（AI 对话主模式）
    // 仪表盘由首页替代
    'dashboard': FeatureVisibility.hidden,
    // AI 工作台与模型配置（唯一 AI 对话入口）
    'agent_workbench': FeatureVisibility.shown,
    'ai_model_manager': FeatureVisibility.shown,
    'ai_prompt_templates': FeatureVisibility.optIn,
    'theme_migration': FeatureVisibility.hidden,
    'ai_template_chat': FeatureVisibility.optIn,
    'tool_library': FeatureVisibility.hidden,
    // 图床（基础保留，高级批量隐藏）
    'image_bed': FeatureVisibility.shown,
    'proxy_settings': FeatureVisibility.shown,
    // 边界模糊入口（默认隐藏，可手动加回）
    'preview': FeatureVisibility.optIn,
    'rss': FeatureVisibility.optIn,
    'recycle_bin': FeatureVisibility.optIn,
    'snippets': FeatureVisibility.optIn,
    // 批量运维 / 专业工具（隐藏）
    'batch_upload': FeatureVisibility.hidden,
    'link_checker': FeatureVisibility.hidden,
    'batch_tools': FeatureVisibility.hidden,
    'template_manager': FeatureVisibility.hidden,
    'config_editor': FeatureVisibility.hidden,
    // 系统 / 诊断（隐藏）
    'logs': FeatureVisibility.hidden,
    'export_logs': FeatureVisibility.hidden,
    'cache_cleanup': FeatureVisibility.hidden,
    'blog_site_manager': FeatureVisibility.hidden,
    'settings': FeatureVisibility.shown,
    'help': FeatureVisibility.shown,
  };

  /// 简易模式下可见入口
  static Set<String> visible(AppMode mode, List<String> extras) =>
      ModeVisibilityFilter.visibleIds(mode, extras, registry);

  static bool visibleEntry(String id, AppMode mode, List<String> extras) =>
      ModeVisibilityFilter.isVisible(id, mode, extras, registry);
}

/// 设置界面分区注册表
abstract final class SettingsEntries {
  static const Map<String, FeatureVisibility> registry = {
    'basic_info': FeatureVisibility.shown,
    'app_mode': FeatureVisibility.shown, // 模式开关
    'github_token': FeatureVisibility.shown,
    'webdav': FeatureVisibility.shown,
    'draft_backup': FeatureVisibility.shown,
    'global_storage': FeatureVisibility.shown,
    'publish_status': FeatureVisibility.shown,
    'network': FeatureVisibility.shown,
    'writing_theme': FeatureVisibility.shown,
    'image_host': FeatureVisibility.shown,
    'ai_relay': FeatureVisibility.shown,
    'ai_scheduler': FeatureVisibility.shown,
    'simple_extras': FeatureVisibility.shown, // 简易模式额外入口管理
    'about': FeatureVisibility.shown,
    'create_site': FeatureVisibility.shown, // 一键建站（设置页入口）
    // 开发配置（隐藏）
    'site_pwa': FeatureVisibility.hidden, // 含 Cloudflare/部署钩子
  };

  static bool visibleEntry(String id, AppMode mode, List<String> extras) =>
      ModeVisibilityFilter.isVisible(id, mode, extras, registry);
}

/// 系统诊断日志文件前缀（简易模式首页列表自动过滤）
abstract final class SystemLogFiles {
  static const List<String> prefixes = ['llama_diag_log'];

  /// 判断文件名是否为系统诊断日志
  static bool isSystemLogFileName(String name) {
    for (final p in prefixes) {
      if (name.startsWith(p)) return true;
    }
    return false;
  }
}
