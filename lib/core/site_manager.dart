import '../models/app_settings.dart';
import '../models/blog_site_config.dart';
import '../models/repo_config.dart';
import 'repository/blog_repository.dart';
import 'repository/ghost_adapter.dart';
import 'repository/typecho_adapter.dart';
import 'repository/wordpress_adapter.dart';

/// 站点类型枚举（用于统一的站点标识）
enum SiteType {
  /// 静态博客站点（基于本地文件 + Git 仓库）
  staticBlog,

  /// 动态 CMS 站点（基于远程 REST API）
  dynamicCms,
}

/// 统一的站点标识
/// 可能是静态仓库（RepoConfig）或动态 CMS（BlogSiteConfig）
class SiteIdentity {
  /// 站点唯一 ID（RepoConfig.id 或 BlogSiteConfig.id）
  final String id;

  /// 站点显示名称
  final String name;

  /// 站点类型
  final SiteType type;

  /// 博客平台类型（Hexo / WordPress / Ghost / Typecho 等）
  final BlogType blogType;

  /// 站点 URL
  final String siteUrl;

  const SiteIdentity({
    required this.id,
    required this.name,
    required this.type,
    required this.blogType,
    required this.siteUrl,
  });

  /// 是否为静态博客站点
  bool get isStatic => type == SiteType.staticBlog;

  /// 是否为动态 CMS 站点
  bool get isDynamic => type == SiteType.dynamicCms;

  /// 从 RepoConfig 创建
  factory SiteIdentity.fromRepo(RepoConfig repo) {
    final blogType = BlogType.fromString(repo.frameworkId);
    return SiteIdentity(
      id: repo.id,
      name: repo.name,
      type: SiteType.staticBlog,
      blogType: blogType,
      siteUrl: repo.siteUrl,
    );
  }

  /// 从 BlogSiteConfig 创建
  factory SiteIdentity.fromBlogSite(BlogSiteConfig config) {
    return SiteIdentity(
      id: config.id,
      name: config.name,
      type: SiteType.dynamicCms,
      blogType: config.type,
      siteUrl: config.siteUrl,
    );
  }

  @override
  String toString() => 'SiteIdentity($id, $name, $type)';
}

/// 站点管理器
///
/// 统一管理静态仓库（RepoConfig）和动态 CMS 站点（BlogSiteConfig），
/// 负责：
/// 1. 站点列表的增删改查
/// 2. 当前活跃站点切换
/// 3. 根据站点类型返回对应的 BlogRepository 适配器
/// 4. 站点类型路由（静态 vs 动态的功能隔离）
class SiteManager {
  /// 静态仓库列表（由外部管理，如 main.dart 中的 repoConfigs）
  List<RepoConfig> staticRepos;

  /// 动态 CMS 站点配置列表
  List<BlogSiteConfig> dynamicSites;

  /// 全局应用设置（用于网络超时、SSL 等全局配置）
  AppSettings appSettings;

  /// 当前活跃站点 ID
  /// 可能是 RepoConfig.id 或 BlogSiteConfig.id
  String _activeSiteId;

  /// 缓存已创建的适配器，避免重复创建 HTTP 客户端
  final Map<String, BlogRepository> _adapterCache = {};

  SiteManager({
    required this.staticRepos,
    required this.dynamicSites,
    required this.appSettings,
    required String activeSiteId,
  }) : _activeSiteId = activeSiteId;

  // ── 活跃站点管理 ──

  /// 当前活跃站点 ID
  String get activeSiteId => _activeSiteId;

  /// 设置活跃站点
  /// 切换站点时自动清理旧适配器缓存
  void setActiveSite(String siteId) {
    if (_activeSiteId == siteId) return;
    // 清理旧适配器
    _disposeAdapter(_activeSiteId);
    _adapterCache.remove(_activeSiteId);
    _activeSiteId = siteId;
  }

  /// 获取当前活跃站点的身份标识
  SiteIdentity? get currentSiteIdentity {
    return getSiteIdentity(_activeSiteId);
  }

  /// 获取指定站点 ID 的身份标识
  SiteIdentity? getSiteIdentity(String siteId) {
    // 先查静态仓库
    for (final repo in staticRepos) {
      if (repo.id == siteId) {
        return SiteIdentity.fromRepo(repo);
      }
    }
    // 再查动态 CMS
    for (final site in dynamicSites) {
      if (site.id == siteId) {
        return SiteIdentity.fromBlogSite(site);
      }
    }
    return null;
  }

  /// 当前活跃站点是否为静态博客
  bool get isStaticSite {
    final identity = currentSiteIdentity;
    return identity?.isStatic ?? true; // 默认按静态站点处理
  }

  /// 当前活跃站点是否为动态 CMS
  bool get isDynamicSite {
    final identity = currentSiteIdentity;
    return identity?.isDynamic ?? false;
  }

  /// 获取当前活跃站点的 BlogType
  BlogType get currentBlogType {
    final identity = currentSiteIdentity;
    return identity?.blogType ?? BlogType.hexo;
  }

  // ── 站点列表查询 ──

  /// 获取所有站点（静态 + 动态）的身份标识列表
  List<SiteIdentity> get allSites {
    final sites = <SiteIdentity>[];
    for (final repo in staticRepos) {
      sites.add(SiteIdentity.fromRepo(repo));
    }
    for (final site in dynamicSites) {
      sites.add(SiteIdentity.fromBlogSite(site));
    }
    return sites;
  }

  /// 获取所有静态站点列表
  List<SiteIdentity> get staticSites {
    return staticRepos.map((r) => SiteIdentity.fromRepo(r)).toList();
  }

  /// 获取所有动态 CMS 站点列表
  List<SiteIdentity> get dynamicSitesList {
    return dynamicSites.map((s) => SiteIdentity.fromBlogSite(s)).toList();
  }

  /// 获取当前活跃的静态仓库配置（静态站点时）
  RepoConfig? get currentStaticRepo {
    if (!isStaticSite) return null;
    for (final repo in staticRepos) {
      if (repo.id == _activeSiteId) return repo;
    }
    return null;
  }

  /// 获取当前活跃的动态 CMS 站点配置（动态站点时）
  BlogSiteConfig? get currentDynamicConfig {
    if (!isDynamicSite) return null;
    for (final site in dynamicSites) {
      if (site.id == _activeSiteId) return site;
    }
    return null;
  }

  // ── 动态站点 CRUD ──

  /// 添加动态 CMS 站点
  void addDynamicSite(BlogSiteConfig config) {
    // 检查是否重复
    final existing = dynamicSites.where((s) => s.id == config.id).toList();
    for (final s in existing) {
      dynamicSites.remove(s);
    }
    dynamicSites.add(config);
  }

  /// 删除动态 CMS 站点
  void removeDynamicSite(String siteId) {
    dynamicSites.removeWhere((s) => s.id == siteId);
    _disposeAdapter(siteId);
    _adapterCache.remove(siteId);

    // 如果删除的是当前活跃站点，自动切换到第一个可用站点
    if (_activeSiteId == siteId) {
      final first = allSites.firstOrNull;
      _activeSiteId = first?.id ?? '';
    }
  }

  /// 更新动态 CMS 站点配置
  void updateDynamicSite(BlogSiteConfig config) {
    final index = dynamicSites.indexWhere((s) => s.id == config.id);
    if (index >= 0) {
      dynamicSites[index] = config;
      // 更新后清理旧的适配器缓存
      _disposeAdapter(config.id);
      _adapterCache.remove(config.id);
    }
  }

  // ── 适配器管理 ──

  /// 获取当前活跃站点对应的 BlogRepository 适配器
  ///
  /// 静态站点返回 null（因为静态站点不使用 BlogRepository 接口），
  /// 动态站点根据 BlogType 返回对应的适配器实例。
  BlogRepository? get currentAdapter {
    if (!isDynamicSite) return null;
    return getAdapter(_activeSiteId);
  }

  /// 获取指定站点 ID 对应的适配器
  BlogRepository? getAdapter(String siteId) {
    final config = _getDynamicConfig(siteId);
    if (config == null) return null;

    // 检查缓存
    if (_adapterCache.containsKey(siteId)) {
      return _adapterCache[siteId];
    }

    // 根据站点类型创建适配器
    BlogRepository? adapter;
    switch (config.type) {
      case BlogType.wordpress:
        adapter = WordPressAdapter(config, appSettings);
        break;
      case BlogType.ghost:
        adapter = GhostAdapter(config, appSettings);
        break;
      case BlogType.typecho:
        adapter = TypechoAdapter(config, appSettings);
        break;
      default:
        return null;
    }

    _adapterCache[siteId] = adapter;
    return adapter;
  }

  /// 获取动态站点配置
  BlogSiteConfig? _getDynamicConfig(String siteId) {
    for (final site in dynamicSites) {
      if (site.id == siteId) return site;
    }
    return null;
  }

  /// 释放指定站点适配器资源
  void _disposeAdapter(String siteId) {
    final adapter = _adapterCache[siteId];
    if (adapter != null) {
      adapter.dispose();
    }
  }

  // ── 功能路由（工具调用的双层防护） ──

  /// 检查当前站点是否允许执行某个操作
  ///
  /// 第一层防护：AI 提示词中告知当前站点类型
  /// 第二层防护：代码层硬拦截
  bool canExecuteOperation(SiteOperation operation) {
    final identity = currentSiteIdentity;
    if (identity == null) return false;

    switch (operation) {
      // 静态站点专属操作
      case SiteOperation.fileRead:
      case SiteOperation.fileWrite:
      case SiteOperation.gitCommit:
      case SiteOperation.gitPush:
      case SiteOperation.directoryTraversal:
      case SiteOperation.themeMigration:
        return identity.isStatic;

      // 动态 CMS 专属操作
      case SiteOperation.remotePostCreate:
      case SiteOperation.remotePostUpdate:
      case SiteOperation.remotePostDelete:
      case SiteOperation.remotePostList:
      case SiteOperation.remoteMediaUpload:
      case SiteOperation.remoteConnectionTest:
        return identity.isDynamic;

      // 通用操作（两种站点类型都支持）
      case SiteOperation.markdownEdit:
      case SiteOperation.aiChat:
      case SiteOperation.selfCheck:
      case SiteOperation.autoSave:
        return true;
    }
  }

  // ── 资源清理 ──

  /// 释放所有适配器资源
  void disposeAll() {
    for (final adapter in _adapterCache.values) {
      adapter.dispose();
    }
    _adapterCache.clear();
  }
}

/// 站点操作枚举
/// 用于功能路由，区分静态站点和动态 CMS 各自支持的操作
enum SiteOperation {
  // ── 静态站点专属 ──
  /// 文件读取
  fileRead,
  /// 文件写入
  fileWrite,
  /// Git 提交
  gitCommit,
  /// Git 推送
  gitPush,
  /// 目录遍历
  directoryTraversal,
  /// 主题迁移
  themeMigration,

  // ── 动态 CMS 专属 ──
  /// 远程文章创建
  remotePostCreate,
  /// 远程文章更新
  remotePostUpdate,
  /// 远程文章删除
  remotePostDelete,
  /// 远程文章列表
  remotePostList,
  /// 远程媒体上传
  remoteMediaUpload,
  /// 远程连接测试
  remoteConnectionTest,

  // ── 通用操作 ──
  /// Markdown 编辑
  markdownEdit,
  /// AI 对话
  aiChat,
  /// 自检
  selfCheck,
  /// 自动保存
  autoSave,
}