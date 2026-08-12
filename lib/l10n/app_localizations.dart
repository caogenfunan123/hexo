/// 应用语言支持
import 'package:flutter/widgets.dart';

enum AppLanguage {
  chinese('简体中文', 'zh-CN', 'zh'),
  english('English', 'en', 'en'),
  japanese('日本語', 'ja', 'ja'),
  korean('한국어', 'ko', 'ko'),
  ;

  final String displayName;
  final String locale;
  final String code;

  const AppLanguage(this.displayName, this.locale, this.code);

  /// 从代码获取语言
  static AppLanguage fromCode(String? code) {
    if (code == null) return chinese;
    return AppLanguage.values.firstWhere(
      (lang) => lang.code == code || lang.locale == code,
      orElse: () => chinese,
    );
  }

  /// 转换为 Flutter Locale
  Locale toLocale() => Locale(code);

  /// 获取系统支持的语言列表
  static List<AppLanguage> get supportedLanguages => [
        chinese,
        english,
        japanese,
        korean,
      ];

  /// Flutter Locale 列表
  static List<Locale> get supportedLocales =>
      supportedLanguages.map((l) => Locale(l.code)).toList();
}

/// 语言资源管理
class AppLocalizations {
  static const _translations = {
    // 中文（默认）
    'zh-CN': {
      'app_title': 'Hexo 博客管理',
      'home': '首页',
      'posts': '文章',
      'drafts': '草稿',
      'categories': '分类',
      'tags': '标签',
      'settings': '设置',
      'add_site': '添加站点',
      'edit_site': '编辑站点',
      'delete_site': '删除站点',
      'site_name': '站点名称',
      'site_url': '站点 URL',
      'preview_url': '预览 URL',
      'test_connection': '测试连接',
      'save': '保存',
      'cancel': '取消',
      'loading': '加载中...',
      'error': '错误',
      'success': '成功',
      'warning': '警告',
      'info': '信息',
      'confirm': '确认',
      'delete': '删除',
      'edit': '编辑',
      'view': '查看',
      'publish': '发布',
      'unpublish': '取消发布',
      'create_post': '创建文章',
      'edit_post': '编辑文章',
      'delete_post': '删除文章',
      'post_title': '文章标题',
      'post_content': '文章内容',
      'post_tags': '文章标签',
      'post_categories': '文章分类',
      'post_status': '文章状态',
      'post_slug': '文章别名',
      'published': '已发布',
      'draft': '草稿',
      'static_blog': '静态博客',
      'dynamic_cms': '动态 CMS',
      'wordpress': 'WordPress',
      'ghost': 'Ghost',
      'typecho': 'Typecho',
      'all_sites': '所有站点',
      'current_site': '当前站点',
      'selected_sites': '选择站点',
      'batch_publish': '批量发布',
      'batch_publish_to_all': '批量发布到所有站点',
      'batch_publish_selected': '批量发布到选定站点',
      'preview': '预览',
      'language': '语言',
      'theme': '主题',
      'about': '关于',
      'version': '版本',
      'check_for_updates': '检查更新',
      'export_data': '导出数据',
      'import_data': '导入数据',
      'reset_settings': '重置设置',
      'logout': '退出登录',
      'language_updated': '语言已更新',
      'select_language': '选择语言',
      'site_preview_url': '站点预览 URL',
      'website_name': '网站名称',
      'website_bio': '网站简介',
      'basic_info': '基本信息',
      'github_token': 'GitHub 登录令牌',
      'author': '作者',
      'contact_email': '联系邮箱',
      'repository': '仓库',
      'export_dir': '导出目录',
      'website_pages': '网站页面编辑',
      'theme_color': '主题颜色',
      'local_drafts': '本地草稿 · 离线编辑 · GitHub 发布 · 图床 · AI · RSS · 搜索 · 提交回滚',
      'not_logged_in': '尚未登录 Token',
      'token_configured': '已配置 Token',
      'saved_tokens_reuse': '保存过的 Token 可复用到多个仓库',
      'saved_tokens_count': '已保存 {count} 个 · 点此管理',
      'current_token': '当前登录令牌',
      'switched_to': '已切换到',
      'language_selector_hint': '选择应用界面显示语言',

      // ── 导航抽屉 ──
      'drawer_section_create': '创作',
      'drawer_section_manage': '管理',
      'drawer_section_tools': '工具',
      'drawer_section_ai': 'AI 工具',
      'drawer_section_system': '系统',
      'nav_write': '写文章',
      'nav_drafts': '草稿箱',
      'nav_remote': '远程文章',
      'nav_remote_single': '远程',
      'nav_dashboard': '仪表盘',
      'nav_rss': 'RSS 订阅',
      'nav_history': '提交历史',
      'nav_upload': '批量上传',
      'nav_preview': '网站预览',
      'nav_settings': '设置',
      'nav_ai_theme_migrate': 'AI 主题迁移',
      'nav_log': '操作日志',
      'nav_sync_status': '同步状态',
      'nav_cloud_sync': '云同步',
      'page_read': '阅读',
      'static_blog_posts': '静态博客文章',
      'all_blog_manage': '全部博客管理',
      'p2p_sync': 'P2P 同步',
      'template_manager': '模板管理',
      'snippet_library': '片段素材库',
      'config_editor': '配置编辑器',
      'ai_batch_migrate': 'AI批量迁移',
      'agent_workbench': 'Agent 任务工作台',
      'ai_post_create': 'AI 博文创作',
      'ai_page_create': 'AI 页面创作',
      'ai_theme_dev': 'AI 主题开发',
      'ai_site_audit': 'AI 站点巡检',
      'ai_templates': 'AI 模板与框架',
      'ai_models': 'AI 模型管理',
      'tool_library': '工具库',

      // ── 通用操作 ──
      'batch_select': '批量选择',
      'refresh': '刷新',
      'retry': '重试',
      'no_title': '（无标题）',
      'just_now': '刚刚',
      'minutes_ago': '{count}分钟前',
      'hours_ago': '{count}小时前',
      'days_ago': '{count}天前',
      'confirm_delete_title': '确认删除',

      // ── 远程文章 ──
      'posts_count': '{count} 篇',
      'static_blog_posts_count': '静态博客文章 ({count} 篇)',
      'no_remote_posts': '暂无远程文章',
      'no_static_posts': '暂无静态博客文章',
      'check_repo_config': '请检查仓库配置',
      'rollback_history': '回滚历史',
      'delete_remote': '删除远程',
      'delete_remote_post': '删除远程文章',
      'static_blog_prefix': '静态博客 · {name}',
      'cms_remote_posts': '{type} 远程文章',
      'current_site_name': '当前站点 · {name}',
      'all_site_posts': '全部站点文章',
      'selected_site_posts': '自选站点文章',
      'select_site_hint': '仅展示已勾选站点的文章；默认勾选已登录（已配置密钥）的站点。',
      'tap_refresh': '点击刷新按钮重新加载',
      'select_at_least_one_site': '请至少选择一个站点',
      'site_static': '静态',
      'site_cms': 'CMS',
      'confirm_delete_remote': '确定要删除远程文章「{title}」{site} 吗？\n此操作不可撤销。',
      'deleted_prefix': '已删除: {title}',
      'delete_failed': '删除失败: {error}',
      'log_delete_remote': '删除远程文章',
      'log_delete_remote_failed': '删除远程文章失败',

      // ── 仪表盘 ──
      'dashboard_local_drafts': '本地草稿',
      'dashboard_remote_posts': '远程文章',
      'commits_count': '提交次数',
      'quick_actions': '快捷操作',
      'new_post': '新建文章',
      'new_post_sub': '开始写一篇新文章',
      'manage_drafts': '管理草稿',
      'manage_drafts_sub': '查看和编辑本地草稿',
      'remote_posts_sub': '查看和管理 GitHub 上的文章',
      'commit_history': '提交历史',
      'commit_history_sub': '查看提交记录并回滚文件',
      'preview_site': '预览网站',
      'no_url_configured': '未配置网址',
      'settings_sub': '配置 Token、仓库、AI、备份等',
      'recent_commits': '最近提交',

      // ── 草稿箱 ──
      'unknown_site': '未知站点',
      'all_sites_short': '全部站点',
      'site_filter': '站点筛选：',
      'no_drafts': '暂无草稿',
      'site_no_drafts': '该站点暂无草稿',
      'untitled': '未命名',
      'delete_draft': '删除草稿',
      'confirm_delete_draft': '确认删除「{title}」？',
      'word_count': '{count} 字',

      // ── 设置页（分区标题与主要条目） ──
      'settings_basic_info': '基本信息',
      'settings_github_token': 'GitHub 登录令牌',
      'settings_webdav': 'WebDAV 云端备份',
      'settings_draft_backup': '草稿备份设置',
      'settings_publish_status': '发布状态预设',
      'settings_network': '网络设置',
      'settings_image_host': '图床（GitHub + CDN）',
      'settings_ai_relay': 'AI 中转站（可多套切换）',
      'settings_ai_scheduler': 'AI 调度器',
      'settings_site_pwa': '站点与 PWA',
      'settings_about': '关于',
      'manage_tokens': '管理已登录令牌',
      'dynamic_blog_login': '动态博客登录',
      'multi_repo_manage': '多仓库管理',
      'repos_count': '当前 {count} 个仓库',
      'config_nutstore': '配置坚果云 / WebDAV 网盘',
      'upload_drafts_webdav': '上传草稿到 WebDAV',
      'sync_webdav_local': '从 WebDAV 同步到本地',
      'local_auto_save': '本地自动保存',
      'auto_save_interval': '自动保存间隔',
      'netdisk_auto_sync': '网盘自动同步',
      'netdisk_sync_interval': '网盘同步间隔',
      'only_wifi_sync': '仅 WiFi 同步',
      'only_wifi_sync_hint': '开启后仅在 WiFi 网络下自动同步',
      'restore_last_session': '启动时恢复上次会话',
      'restore_last_session_hint': 'APP 被杀后台后重新打开，自动恢复到上次停留的页面',
      'http_timeout': 'HTTP 请求超时',
      'allow_insecure_https': '允许不安全的 HTTPS 证书',
      'allow_insecure_https_hint': '开启后忽略 SSL 证书校验（适用于自签名证书站点）',
      'image_host_sync': '一键同步当前仓库为图床',
      'image_host_synced': '已同步图床仓库为 {name}',
      'auto_compress_image': '自动压缩图片',
      'current_ai_profile': '当前使用的 AI 配置',
      'auto_best_mode': '自动择优模式',
      'auto_best_mode_hint': '后台探测各模型延迟，优先调用当前最快模型',
      'allow_ai_save_tool': '允许 AI 自动保存工具',
      'allow_ai_save_tool_hint': 'AI 生成的 MCP/Skill 校验通过后自动存入工具箱',
      'confirm_high_risk_tools': '高风险工具执行需确认',
      'confirm_high_risk_tools_hint': '删除/回滚/克隆等操作前弹确认框；关闭则 AI 拥有全部权限直接执行',
      'blog_address': '博客地址',
      'pwa_guide': 'PWA 说明',
      'pwa_guide_hint': '站点已部署为静态网站，可在浏览器"添加到主屏幕"',
      'cloudflare_hook': '部署钩子',
      'theme_color_hint': '点击切换主题色',
      'about_author': '作者',
      'about_developer': '开发者',
      'about_version': '版本',
      'about_email': '联系邮箱',
      'ai_request_timeout': '请求超时阈值（秒）',
      'ai_max_switch': '最大自动切换次数',
      'site_url_not_set': '未设置站点地址',
      'site_url_copied': '已复制站点地址',
      'cloudflare_hook_saved': '部署钩子已保存',
      'deploy_hook_configured': '已配置 {count} 个（发布后自动触发重新部署）',
      'deploy_hook_not_configured': '未配置（发布后需手动触发部署）',
      'deploy_hook_title': '部署钩子',
      'deploy_hook_desc': '支持 Cloudflare Pages / Vercel / Netlify 等平台的 Deploy Hook（Build Hook）。每行填一个钩子 URL，发布文章后将自动触发全部重新部署。',
      'deploy_hook_label': 'Deploy Hook URL',
      'deploy_hook_hint': 'https://api.cloudflare.com/...（每行一个）',
      'site_editor_pages': '头像 · 名称 · 首页 · 关于 · 留言 · Now · 作品',
      'email_copied': '已复制邮箱地址',
      'repo_copied': '已复制仓库地址',
      'open_repo': '打开开源仓库',
      'open_repo_hint': '查看源码、提 Issue 或给个 Star',
      'about_help': '帮助',
      'about_help_hint': '使用说明与常见问题',
      'help_title': '拓墨 · 使用帮助',
      'help_quick_start': '快速开始',
      'help_quick_start_body': '1. 在「设置」中配置 GitHub Token 或 WebDAV\n2. 在「仓库」中添加你的博客仓库\n3. 进入「写文章」开始创作，支持 AI 辅助写作\n4. 写完后一键发布到站点',
      'help_ai': 'AI 写作',
      'help_ai_body': '设置页可配置云端模型（OpenAI/Anthropic/火山引擎等）。在写作界面可让 AI 生成大纲、续写、润色、取标题，也可用 Agent 工作台执行多步骤写作任务。',
      'help_publish': '静态博客发布',
      'help_publish_body': '支持 GitHub Pages / 静态博客 / CMS 多站点一键发布。可配置多个部署钩子（Cloudflare / Vercel / Netlify），发布后自动触发重新部署。',
      'help_issue': '遇到问题？',
      'help_issue_body': '在 GitHub 仓库提 Issue，附上日志面板中的错误信息，我们会尽快回复。',
      'version_label': '版本号',
      'export_dir_copied': '导出目录已复制: {path}',
      'export_dir_hint': '查看本地 drafts_md 导出路径',
      'settings_global_storage': '全局文件存储目录',
      'global_storage_root': '全局存储根目录',
      'global_storage_default': '默认目录（应用私有目录）',
      'global_storage_hint': '本地导出 MD/图片、云同步、Git 拉取推送、分享临时缓存统一存放于此目录，根目录下自动生成 MD文章/文章长图/同步缓存/Git博文/临时分享文件 分类子文件夹。',
      'pick_global_storage_root': '选择全局存储根目录',
      'global_storage_set': '已设置全局存储目录: {path}',
      'global_storage_reset': '已重置为默认存储目录',
      'global_storage_migrated': '已迁移 {count} 个文件到新目录',
      'copy_path': '复制路径',
      'reset_storage_root': '重置目录',
      'migrate_storage_root': '迁移历史文件',
      'pick_dir_failed': '选择目录失败',
      'hexo_writing_system': '拓墨 · AI 写作与静态博客发布',
      'sites_configured': '已配置 {count} 个站点',
      'token_hint': '登录过的 Token 会本地保存，可随时切换；新建/编辑仓库时可一键选用已登录令牌。',
      'webdav_placeholder': '填写 WebDAV 地址、账号和密码',
      'webdav_configured': '已配置: {url}',
      'webdav_not_configured': '请先配置 WebDAV',
      'upload_drafts_hint': '同步本地草稿到云端',
      'download_drafts_hint': '下载云端草稿到本地',
      'auto_save_interval_hint': '间隔 {count} 秒自动保存草稿快照',
      'auto_save_dir': '保存目录（默认 ~/.hexo_app/auto_save）',
      'backup_dir': '备份目录（默认 ~/.hexo_app/backup）',
      'auto_save_hint': '打字时防抖延时保存，到达定时周期强制快照，切后台/退出时立刻保存。',
      'webdav_auto_sync_enabled': '每 {count} 分钟同步到云端',
      'webdav_auto_sync_disabled': '关闭后仅手动同步',
      'status_preset_hint': '自定义 CMS 发布时的可选状态。默认提供 publish（发布）、draft（草稿）、pending（待审核）、private（私有）四种状态。',
      'http_timeout_hint': '超时设置影响所有动态 CMS 站点（WordPress / Ghost / Typecho）的 HTTP 请求。网络环境较差时可适当增大超时。',
      'image_host_no_repo': '请先添加仓库',
      'image_host_repo_hint': '使用 {name} / {branch}，Token 回退已登录令牌',
      'image_bed_token': '图床 Token（可留空用已登录令牌）',
      'dir_path': '目录路径',
      'cdn_prefix': '自定义 CDN 前缀（可选）',
      'compress_hint': '最大宽 {width}px / 质量 {quality}',
      'ai_not_configured': '尚未配置 AI',
      'ai_profile_empty_hint': '填写密钥和 URL，获取模型后保存；可添加多套任意切换',
      'ai_profile_count': '已保存 {count} 套配置 · 点此管理',
      'ai_relay_desc': '兼容各类 OpenAI 中转站：填 Base URL + API Key → 点击获取模型 → 选择模型保存。',
      'status_label': '状态 {index}',
      'add_status': '添加状态',
    },
    // English
    'en': {
      'app_title': 'Hexo Blog Manager',
      'home': 'Home',
      'posts': 'Posts',
      'drafts': 'Drafts',
      'categories': 'Categories',
      'tags': 'Tags',
      'settings': 'Settings',
      'add_site': 'Add Site',
      'edit_site': 'Edit Site',
      'delete_site': 'Delete Site',
      'site_name': 'Site Name',
      'site_url': 'Site URL',
      'preview_url': 'Preview URL',
      'test_connection': 'Test Connection',
      'save': 'Save',
      'cancel': 'Cancel',
      'loading': 'Loading...',
      'error': 'Error',
      'success': 'Success',
      'warning': 'Warning',
      'info': 'Info',
      'confirm': 'Confirm',
      'delete': 'Delete',
      'edit': 'Edit',
      'view': 'View',
      'publish': 'Publish',
      'unpublish': 'Unpublish',
      'create_post': 'Create Post',
      'edit_post': 'Edit Post',
      'delete_post': 'Delete Post',
      'post_title': 'Post Title',
      'post_content': 'Post Content',
      'post_tags': 'Post Tags',
      'post_categories': 'Post Categories',
      'post_status': 'Post Status',
      'post_slug': 'Post Slug',
      'published': 'Published',
      'draft': 'Draft',
      'static_blog': 'Static Blog',
      'dynamic_cms': 'Dynamic CMS',
      'wordpress': 'WordPress',
      'ghost': 'Ghost',
      'typecho': 'Typecho',
      'all_sites': 'All Sites',
      'current_site': 'Current Site',
      'selected_sites': 'Selected Sites',
      'batch_publish': 'Batch Publish',
      'batch_publish_to_all': 'Batch Publish to All Sites',
      'batch_publish_selected': 'Batch Publish to Selected Sites',
      'preview': 'Preview',
      'language': 'Language',
      'theme': 'Theme',
      'about': 'About',
      'version': 'Version',
      'check_for_updates': 'Check for Updates',
      'export_data': 'Export Data',
      'import_data': 'Import Data',
      'reset_settings': 'Reset Settings',
      'logout': 'Logout',
      'language_updated': 'Language updated',
      'select_language': 'Select Language',
      'site_preview_url': 'Site Preview URL',
      'website_name': 'Site Name',
      'website_bio': 'Site Bio',
      'basic_info': 'Basic Info',
      'github_token': 'GitHub Login Token',
      'author': 'Author',
      'contact_email': 'Contact Email',
      'repository': 'Repository',
      'export_dir': 'Export Directory',
      'website_pages': 'Site Pages Editor',
      'theme_color': 'Theme Color',
      'local_drafts': 'Local drafts · Offline editing · GitHub publish · Image host · AI · RSS · Search · Commit rollback',
      'not_logged_in': 'No token yet',
      'token_configured': 'Token configured',
      'saved_tokens_reuse': 'Saved tokens can be reused across repos',
      'saved_tokens_count': '{count} saved · Tap to manage',
      'current_token': 'Current Login Token',
      'switched_to': 'Switched to',
      'language_selector_hint': 'Select app interface language',

      // ── Navigation drawer ──
      'drawer_section_create': 'Create',
      'drawer_section_manage': 'Manage',
      'drawer_section_tools': 'Tools',
      'drawer_section_ai': 'AI Tools',
      'drawer_section_system': 'System',
      'nav_write': 'Write',
      'nav_drafts': 'Drafts',
      'nav_remote': 'Remote Posts',
      'nav_remote_single': 'Remote',
      'nav_dashboard': 'Dashboard',
      'nav_rss': 'RSS',
      'nav_history': 'History',
      'nav_upload': 'Batch Upload',
      'nav_preview': 'Preview',
      'nav_settings': 'Settings',
      'nav_ai_theme_migrate': 'AI Theme Migration',
      'nav_log': 'Activity Log',
      'nav_sync_status': 'Sync Status',
      'nav_cloud_sync': 'Cloud Sync',
      'page_read': 'Read',
      'static_blog_posts': 'Static Blog Posts',
      'all_blog_manage': 'All Blog Management',
      'p2p_sync': 'P2P Sync',
      'template_manager': 'Templates',
      'snippet_library': 'Snippets',
      'config_editor': 'Config Editor',
      'ai_batch_migrate': 'AI Batch Migration',
      'agent_workbench': 'Agent Workbench',
      'ai_post_create': 'AI Post Creation',
      'ai_page_create': 'AI Page Creation',
      'ai_theme_dev': 'AI Theme Development',
      'ai_site_audit': 'AI Site Audit',
      'ai_templates': 'AI Templates',
      'ai_models': 'AI Models',
      'tool_library': 'Tool Library',

      // ── Common actions ──
      'batch_select': 'Batch Select',
      'refresh': 'Refresh',
      'retry': 'Retry',
      'no_title': '(Untitled)',
      'just_now': 'Just now',
      'minutes_ago': '{count} min ago',
      'hours_ago': '{count} hr ago',
      'days_ago': '{count} days ago',
      'confirm_delete_title': 'Confirm Delete',

      // ── Remote posts ──
      'posts_count': '{count} posts',
      'static_blog_posts_count': 'Static blog posts ({count})',
      'no_remote_posts': 'No remote posts',
      'no_static_posts': 'No static blog posts',
      'check_repo_config': 'Please check the repo config',
      'rollback_history': 'Rollback History',
      'delete_remote': 'Delete Remote',
      'delete_remote_post': 'Delete Remote Post',
      'static_blog_prefix': 'Static Blog · {name}',
      'cms_remote_posts': '{type} Remote Posts',
      'current_site_name': 'Current Site · {name}',
      'all_site_posts': 'All Site Posts',
      'selected_site_posts': 'Selected Site Posts',
      'select_site_hint': 'Only shows posts of checked sites; logged-in (configured token) sites are checked by default.',
      'tap_refresh': 'Tap refresh to reload',
      'select_at_least_one_site': 'Please select at least one site',
      'site_static': 'Static',
      'site_cms': 'CMS',
      'confirm_delete_remote': 'Delete remote post "{title}"{site}? This cannot be undone.',
      'deleted_prefix': 'Deleted: {title}',
      'delete_failed': 'Delete failed: {error}',
      'log_delete_remote': 'Delete remote post',
      'log_delete_remote_failed': 'Delete remote post failed',

      // ── Dashboard ──
      'dashboard_local_drafts': 'Local Drafts',
      'dashboard_remote_posts': 'Remote Posts',
      'commits_count': 'Commits',
      'quick_actions': 'Quick Actions',
      'new_post': 'New Post',
      'new_post_sub': 'Start writing a new post',
      'manage_drafts': 'Manage Drafts',
      'manage_drafts_sub': 'View and edit local drafts',
      'remote_posts_sub': 'View and manage posts on GitHub',
      'commit_history': 'Commit History',
      'commit_history_sub': 'View commits and rollback files',
      'preview_site': 'Preview Site',
      'no_url_configured': 'No URL configured',
      'settings_sub': 'Configure Token, repos, AI, backup, etc.',
      'recent_commits': 'Recent Commits',

      // ── Drafts ──
      'unknown_site': 'Unknown Site',
      'all_sites_short': 'All Sites',
      'site_filter': 'Site filter:',
      'no_drafts': 'No drafts',
      'site_no_drafts': 'No drafts for this site',
      'untitled': 'Untitled',
      'delete_draft': 'Delete Draft',
      'confirm_delete_draft': 'Delete "{title}"?',
      'word_count': '{count} words',

      // ── Settings (sections & main entries) ──
      'settings_basic_info': 'Basic Info',
      'settings_github_token': 'GitHub Login Token',
      'settings_webdav': 'WebDAV Cloud Backup',
      'settings_draft_backup': 'Draft Backup Settings',
      'settings_publish_status': 'Publish Status Presets',
      'settings_network': 'Network Settings',
      'settings_image_host': 'Image Host (GitHub + CDN)',
      'settings_ai_relay': 'AI Relay (multiple profiles)',
      'settings_ai_scheduler': 'AI Scheduler',
      'settings_site_pwa': 'Site & PWA',
      'settings_about': 'About',
      'manage_tokens': 'Manage Saved Tokens',
      'dynamic_blog_login': 'Dynamic Blog Login',
      'multi_repo_manage': 'Multi-Repo Management',
      'repos_count': '{count} repos',
      'config_nutstore': 'Configure Nutstore / WebDAV',
      'upload_drafts_webdav': 'Upload Drafts to WebDAV',
      'sync_webdav_local': 'Sync from WebDAV to Local',
      'local_auto_save': 'Local Auto-Save',
      'auto_save_interval': 'Auto-Save Interval',
      'netdisk_auto_sync': 'Netdisk Auto-Sync',
      'netdisk_sync_interval': 'Netdisk Sync Interval',
      'only_wifi_sync': 'WiFi Only Sync',
      'only_wifi_sync_hint': 'Only auto-sync on WiFi when enabled',
      'restore_last_session': 'Restore Last Session on Launch',
      'restore_last_session_hint': 'Reopens to the last page when the app was killed in background',
      'http_timeout': 'HTTP Request Timeout',
      'allow_insecure_https': 'Allow Insecure HTTPS Certificates',
      'allow_insecure_https_hint': 'Ignore SSL certificate validation (for self-signed sites)',
      'image_host_sync': 'Sync Current Repo as Image Host',
      'image_host_synced': 'Image host repo synced to {name}',
      'auto_compress_image': 'Auto-Compress Images',
      'current_ai_profile': 'Current AI Profile',
      'auto_best_mode': 'Auto Best-Model Mode',
      'auto_best_mode_hint': 'Probes model latency in background and prefers the fastest model',
      'allow_ai_save_tool': 'Allow AI Auto-Save Tool',
      'allow_ai_save_tool_hint': 'Validated AI-generated MCP/Skill tools are auto-saved to the toolbox',
      'confirm_high_risk_tools': 'Require confirmation for high-risk tools',
      'confirm_high_risk_tools_hint': 'Ask before delete/rollback/clone operations; off means AI has full permissions',
      'blog_address': 'Blog Address',
      'pwa_guide': 'PWA Guide',
      'pwa_guide_hint': 'Site is deployed as a static website. Add to home screen in the browser.',
      'cloudflare_hook': 'Deploy Hooks',
      'theme_color_hint': 'Tap to change theme color',
      'about_author': 'Author',
      'about_developer': 'Developer',
      'about_version': 'Version',
      'about_email': 'Contact Email',
      'ai_request_timeout': 'Request Timeout (sec)',
      'ai_max_switch': 'Max Auto-Switch Count',
      'site_url_not_set': 'Site address not set',
      'site_url_copied': 'Site address copied',
      'cloudflare_hook_saved': 'Deploy hooks saved',
      'deploy_hook_configured': '{count} configured (auto re-deploys after publish)',
      'deploy_hook_not_configured': 'Not configured (manual deploy needed after publish)',
      'deploy_hook_title': 'Deploy Hooks',
      'deploy_hook_desc': 'Supports Deploy Hook (Build Hook) from Cloudflare Pages / Vercel / Netlify etc. Paste one hook URL per line. Publishing an article will trigger all redeployments automatically.',
      'deploy_hook_label': 'Deploy Hook URL',
      'deploy_hook_hint': 'https://api.cloudflare.com/... (one per line)',
      'site_editor_pages': 'Avatar · Name · Home · About · Guestbook · Now · Projects',
      'email_copied': 'Email address copied',
      'repo_copied': 'Repository address copied',
      'open_repo': 'Open Source Repository',
      'open_repo_hint': 'View source, file issues or give a star',
      'about_help': 'Help',
      'about_help_hint': 'Usage guide & FAQ',
      'help_title': 'Tuomo · Help',
      'help_quick_start': 'Quick Start',
      'help_quick_start_body': '1. Configure GitHub Token or WebDAV in Settings\n2. Add your blog repository in Repositories\n3. Start writing in Write Article, with AI assistance\n4. Publish to your sites with one click',
      'help_ai': 'AI Writing',
      'help_ai_body': 'Configure cloud models (OpenAI/Anthropic/Volcano Engine etc.) in Settings. In the editor you can ask AI to outline, continue, polish, or title your article, or use the Agent Workbench for multi-step writing tasks.',
      'help_publish': 'Static Blog Publishing',
      'help_publish_body': 'One-click publishing to GitHub Pages / static blogs / CMS sites. Configure multiple deploy hooks (Cloudflare / Vercel / Netlify) to auto-trigger redeploy after publishing.',
      'help_issue': 'Having issues?',
      'help_issue_body': 'File an issue on GitHub with the error info from the log panel, and we will respond soon.',
      'version_label': 'Version',
      'export_dir_copied': 'Export directory copied: {path}',
      'export_dir_hint': 'View the local drafts_md export path',
      'settings_global_storage': 'Global File Storage Directory',
      'global_storage_root': 'Global Storage Root',
      'global_storage_default': 'Default (app private directory)',
      'global_storage_hint': 'Local MD/image exports, cloud sync, Git pull/push and share temp cache are all stored in this directory. Category subfolders are auto-created: MD Articles / Article Long Images / Sync Cache / Git Posts / Share Temp.',
      'pick_global_storage_root': 'Select Global Storage Root',
      'global_storage_set': 'Global storage directory set: {path}',
      'global_storage_reset': 'Reset to default storage directory',
      'global_storage_migrated': 'Migrated {count} files to the new directory',
      'copy_path': 'Copy Path',
      'reset_storage_root': 'Reset',
      'migrate_storage_root': 'Migrate Files',
      'pick_dir_failed': 'Failed to pick directory',
      'hexo_writing_system': 'Tuomo · AI Writing & Static Blog Publishing',
      'sites_configured': '{count} site(s) configured',
      'token_hint': 'Logged-in tokens are stored locally and can be switched anytime; reuse them with one tap when creating/editing repos.',
      'webdav_placeholder': 'Enter WebDAV address, username and password',
      'webdav_configured': 'Configured: {url}',
      'webdav_not_configured': 'Configure WebDAV first',
      'upload_drafts_hint': 'Sync local drafts to cloud',
      'download_drafts_hint': 'Download cloud drafts to local',
      'auto_save_interval_hint': 'Auto-save draft snapshot every {count} seconds',
      'auto_save_dir': 'Save directory (default ~/.hexo_app/auto_save)',
      'backup_dir': 'Backup directory (default ~/.hexo_app/backup)',
      'auto_save_hint': 'Debounced save while typing, forced snapshot at interval, immediate save on background/exit.',
      'webdav_auto_sync_enabled': 'Sync to cloud every {count} minutes',
      'webdav_auto_sync_disabled': 'Manual sync only when disabled',
      'status_preset_hint': 'Customize available CMS publish statuses. Defaults: publish, draft, pending, private.',
      'http_timeout_hint': 'Timeout applies to all dynamic CMS sites (WordPress / Ghost / Typecho) HTTP requests. Increase it on slow networks.',
      'image_host_no_repo': 'Add a repo first',
      'image_host_repo_hint': 'Using {name} / {branch}, token falls back to logged-in token',
      'image_bed_token': 'Image host token (leave empty to use logged-in token)',
      'dir_path': 'Directory path',
      'cdn_prefix': 'Custom CDN prefix (optional)',
      'compress_hint': 'Max width {width}px / quality {quality}',
      'ai_not_configured': 'AI not configured yet',
      'ai_profile_empty_hint': 'Enter API key and URL, fetch models then save; add multiple profiles and switch freely',
      'ai_profile_count': '{count} profile(s) saved · tap to manage',
      'ai_relay_desc': 'Compatible with OpenAI-style relays: fill Base URL + API Key → fetch models → pick and save.',
      'status_label': 'Status {index}',
      'add_status': 'Add Status',
    },
    // Japanese
    'ja': {
      'app_title': 'Hexo ブログ管理',
      'home': 'ホーム',
      'posts': '投稿',
      'drafts': '下書き',
      'categories': 'カテゴリー',
      'tags': 'タグ',
      'settings': '設定',
      'add_site': 'サイトを追加',
      'edit_site': 'サイトを編集',
      'delete_site': 'サイトを削除',
      'site_name': 'サイト名',
      'site_url': 'サイトURL',
      'preview_url': 'プレビューURL',
      'test_connection': '接続テスト',
      'save': '保存',
      'cancel': 'キャンセル',
      'loading': '読み込み中...',
      'error': 'エラー',
      'success': '成功',
      'warning': '警告',
      'info': '情報',
      'confirm': '確認',
      'delete': '削除',
      'edit': '編集',
      'view': '表示',
      'publish': '公開',
      'unpublish': '非公開',
      'create_post': '投稿を作成',
      'edit_post': '投稿を編集',
      'delete_post': '投稿を削除',
      'post_title': '投稿タイトル',
      'post_content': '投稿内容',
      'post_tags': '投稿タグ',
      'post_categories': '投稿カテゴリー',
      'post_status': '投稿ステータス',
      'post_slug': '投稿スラッグ',
      'published': '公開済み',
      'draft': '下書き',
      'static_blog': '静的ブログ',
      'dynamic_cms': '動的CMS',
      'wordpress': 'WordPress',
      'ghost': 'Ghost',
      'typecho': 'Typecho',
      'all_sites': 'すべてのサイト',
      'current_site': '現在のサイト',
      'selected_sites': '選択したサイト',
      'batch_publish': '一括公開',
      'batch_publish_to_all': 'すべてのサイトに一括公開',
      'batch_publish_selected': '選択したサイトに一括公開',
      'preview': 'プレビュー',
      'language': '言語',
      'theme': 'テーマ',
      'about': 'について',
      'version': 'バージョン',
      'check_for_updates': 'アップデートを確認',
      'export_data': 'データをエクスポート',
      'import_data': 'データをインポート',
      'reset_settings': '設定をリセット',
      'logout': 'ログアウト',
      'language_updated': '言語が更新されました',
      'select_language': '言語を選択',
      'site_preview_url': 'サイトプレビューURL',
      'website_name': 'サイト名',
      'website_bio': 'サイト紹介',
      'basic_info': '基本情報',
      'github_token': 'GitHub ログイントークン',
      'author': '作者',
      'contact_email': '連絡先メール',
      'repository': 'リポジトリ',
      'export_dir': 'エクスポートディレクトリ',
      'website_pages': 'サイトページ編集',
      'theme_color': 'テーマカラー',
      'local_drafts': 'ローカル下書き · オフライン編集 · GitHub公開 · 画像ホスト · AI · RSS · 検索 · コミットロールバック',
      'not_logged_in': 'トークン未設定',
      'token_configured': 'トークン設定済み',
      'saved_tokens_reuse': '保存済みトークンは複数リポジトリで再利用できます',
      'saved_tokens_count': '{count} 個保存済み · タップして管理',
      'current_token': '現在のログイントークン',
      'switched_to': '切り替えました',
      'language_selector_hint': 'アプリの表示言語を選択',

      // ── ナビゲーションドロワー ──
      'drawer_section_create': '創作',
      'drawer_section_manage': '管理',
      'drawer_section_tools': 'ツール',
      'drawer_section_ai': 'AIツール',
      'drawer_section_system': 'システム',
      'nav_write': '記事を書く',
      'nav_drafts': '下書き箱',
      'nav_remote': 'リモート投稿',
      'nav_remote_single': 'リモート',
      'nav_dashboard': 'ダッシュボード',
      'nav_rss': 'RSS 購読',
      'nav_history': 'コミット履歴',
      'nav_upload': '一括アップロード',
      'nav_preview': 'サイトプレビュー',
      'nav_settings': '設定',
      'nav_ai_theme_migrate': 'AIテーマ移行',
      'nav_log': '操作ログ',
      'nav_sync_status': '同期状態',
      'nav_cloud_sync': 'クラウド同期',
      'page_read': '読む',
      'static_blog_posts': '静的ブログ記事',
      'all_blog_manage': '全ブログ管理',
      'p2p_sync': 'P2P同期',
      'template_manager': 'テンプレート管理',
      'snippet_library': 'スニペット素材',
      'config_editor': '設定エディター',
      'ai_batch_migrate': 'AI一括移行',
      'agent_workbench': 'Agent作業台',
      'ai_post_create': 'AI投稿作成',
      'ai_page_create': 'AIページ作成',
      'ai_theme_dev': 'AIテーマ開発',
      'ai_site_audit': 'AIサイト監査',
      'ai_templates': 'AIテンプレート',
      'ai_models': 'AIモデル管理',
      'tool_library': 'ツールライブラリ',

      // ── 共通操作 ──
      'batch_select': '一括選択',
      'refresh': '更新',
      'retry': '再試行',
      'no_title': '（無題）',
      'just_now': 'たった今',
      'minutes_ago': '{count}分前',
      'hours_ago': '{count}時間前',
      'days_ago': '{count}日前',
      'confirm_delete_title': '削除確認',

      // ── リモート投稿 ──
      'posts_count': '{count} 件',
      'static_blog_posts_count': '静的ブログ記事 ({count} 件)',
      'no_remote_posts': 'リモート投稿なし',
      'no_static_posts': '静的ブログ記事なし',
      'check_repo_config': 'リポジトリ設定を確認してください',
      'rollback_history': '履歴に戻す',
      'delete_remote': 'リモート削除',
      'delete_remote_post': 'リモート投稿を削除',
      'static_blog_prefix': '静的ブログ · {name}',
      'cms_remote_posts': '{type} リモート投稿',
      'current_site_name': '現在のサイト · {name}',
      'all_site_posts': '全サイトの投稿',
      'selected_site_posts': '選択サイトの投稿',
      'select_site_hint': 'チェックしたサイトの投稿のみ表示。ログイン済み（キー設定済み）サイトはデフォルトでチェックされます。',
      'tap_refresh': '更新ボタンをタップして再読み込み',
      'select_at_least_one_site': '少なくとも1つのサイトを選択してください',
      'site_static': '静的',
      'site_cms': 'CMS',
      'confirm_delete_remote': 'リモート投稿「{title}」{site}を削除しますか？\nこの操作は元に戻せません。',
      'deleted_prefix': '削除しました: {title}',
      'delete_failed': '削除失敗: {error}',
      'log_delete_remote': 'リモート投稿を削除',
      'log_delete_remote_failed': 'リモート投稿の削除に失敗',

      // ── ダッシュボード ──
      'dashboard_local_drafts': 'ローカル下書き',
      'dashboard_remote_posts': 'リモート投稿',
      'commits_count': 'コミット数',
      'quick_actions': 'クイック操作',
      'new_post': '新規投稿',
      'new_post_sub': '新しい投稿を書き始める',
      'manage_drafts': '下書き管理',
      'manage_drafts_sub': 'ローカル下書きを表示・編集',
      'remote_posts_sub': 'GitHub上の投稿を表示・管理',
      'commit_history': 'コミット履歴',
      'commit_history_sub': 'コミット履歴を確認してファイルを戻す',
      'preview_site': 'サイトをプレビュー',
      'no_url_configured': 'URL未設定',
      'settings_sub': 'Token・リポジトリ・AI・バックアップなどを設定',
      'recent_commits': '最近のコミット',

      // ── 下書き箱 ──
      'unknown_site': '不明なサイト',
      'all_sites_short': '全サイト',
      'site_filter': 'サイト絞り込み：',
      'no_drafts': '下書きなし',
      'site_no_drafts': 'このサイトには下書きがありません',
      'untitled': '無題',
      'delete_draft': '下書きを削除',
      'confirm_delete_draft': '「{title}」を削除しますか？',
      'word_count': '{count} 文字',

      // ── 設定（セクション見出しと主要項目） ──
      'settings_basic_info': '基本情報',
      'settings_github_token': 'GitHub ログイントークン',
      'settings_webdav': 'WebDAV クラウドバックアップ',
      'settings_draft_backup': '下書きバックアップ設定',
      'settings_publish_status': '公開ステータスプリセット',
      'settings_network': 'ネットワーク設定',
      'settings_image_host': '画像ホスト（GitHub + CDN）',
      'settings_ai_relay': 'AI 中継（複数プロファイル）',
      'settings_ai_scheduler': 'AI スケジューラー',
      'settings_site_pwa': 'サイトと PWA',
      'settings_about': 'について',
      'manage_tokens': '保存済みトークンを管理',
      'dynamic_blog_login': '動的ブログログイン',
      'multi_repo_manage': 'マルチリポジトリ管理',
      'repos_count': '現在 {count} 個のリポジトリ',
      'config_nutstore': 'Nutstore / WebDAV を設定',
      'upload_drafts_webdav': '下書きを WebDAV にアップロード',
      'sync_webdav_local': 'WebDAV からローカルへ同期',
      'local_auto_save': 'ローカル自動保存',
      'auto_save_interval': '自動保存間隔',
      'netdisk_auto_sync': 'クラウド自動同期',
      'netdisk_sync_interval': 'クラウド同期間隔',
      'only_wifi_sync': 'WiFi のみ同期',
      'only_wifi_sync_hint': '有効にすると WiFi 接続時のみ自動同期',
      'restore_last_session': '起動時に前回のセッションを復元',
      'restore_last_session_hint': 'バックグラウンドで終了した場合、最後のページから自動復元',
      'http_timeout': 'HTTP リクエストタイムアウト',
      'allow_insecure_https': '安全でない HTTPS 証明書を許可',
      'allow_insecure_https_hint': 'SSL 証明書検証を無視（自己署名サイト向け）',
      'image_host_sync': '現在のリポジトリを画像ホストに同期',
      'image_host_synced': '画像ホストリポジトリを {name} に同期しました',
      'auto_compress_image': '画像を自動圧縮',
      'current_ai_profile': '現在の AI プロファイル',
      'auto_best_mode': '自動最適化モード',
      'auto_best_mode_hint': 'バックグラウンドで各モデルの遅延を計測し、最速のモデルを優先',
      'allow_ai_save_tool': 'AI 自動保存ツールを許可',
      'allow_ai_save_tool_hint': '検証済みの AI 生成 MCP/Skill ツールをツールボックスに自動保存',
      'confirm_high_risk_tools': '高リスクツールの実行確認を要求',
      'confirm_high_risk_tools_hint': '削除・ロールバック・クローン前に確認ダイアログを表示。オフでAIが全権限を持つ',
      'blog_address': 'ブログアドレス',
      'pwa_guide': 'PWA ガイド',
      'pwa_guide_hint': '静的サイトとしてデプロイ済み。ブラウザでホーム画面に追加できます。',
      'cloudflare_hook': 'デプロイフック',
      'theme_color_hint': 'タップでテーマカラーを変更',
      'about_author': '作者',
      'about_developer': '開発者',
      'about_version': 'バージョン',
      'about_email': '連絡先メール',
      'ai_request_timeout': 'リクエストタイムアウト（秒）',
      'ai_max_switch': '最大自動切り替え回数',
      'site_url_not_set': 'サイトアドレスが未設定です',
      'site_url_copied': 'サイトアドレスをコピーしました',
      'cloudflare_hook_saved': 'デプロイフックを保存しました',
      'deploy_hook_configured': '{count} 件設定済み（公開後に自動再デプロイ）',
      'deploy_hook_not_configured': '未設定（公開後に手動デプロイが必要）',
      'deploy_hook_title': 'デプロイフック',
      'deploy_hook_desc': 'Cloudflare Pages / Vercel / Netlify などの Deploy Hook（Build Hook）に対応。1 行に 1 つ URL を貼り付けます。記事を公開するとすべての再デプロイが自動トリガーされます。',
      'deploy_hook_label': 'Deploy Hook URL',
      'deploy_hook_hint': 'https://api.cloudflare.com/...（1 行に 1 つ）',
      'site_editor_pages': 'アバター · 名前 · ホーム · 概要 · コメント · Now · 作品',
      'email_copied': 'メールアドレスをコピーしました',
      'repo_copied': 'リポジトリの URL をコピーしました',
      'open_repo': 'オープンソースリポジトリ',
      'open_repo_hint': 'ソースを表示、Issue 報告、Star を付ける',
      'about_help': 'ヘルプ',
      'about_help_hint': '使い方と FAQ',
      'help_title': '拓墨 · ヘルプ',
      'help_quick_start': 'クイックスタート',
      'help_quick_start_body': '1. 設定で GitHub Token または WebDAV を構成\n2. リポジトリにブログリポジトリを追加\n3. 「記事を書く」で AI アシスト付きで執筆\n4. ワンクリックでサイトに公開',
      'help_ai': 'AI 執筆',
      'help_ai_body': '設定でクラウドモデル（OpenAI/Anthropic/火山エンジンなど）を構成。エディタで AI にアウトライン生成、続き書き、推敲、タイトル付けを依頼できます。Agent ワークベンチで多段階の執筆タスクも可能。',
      'help_publish': '静的ブログ公開',
      'help_publish_body': 'GitHub Pages / 静的ブログ / CMS サイトへのワンクリック公開。複数のデプロイフック（Cloudflare / Vercel / Netlify）を構成すると、公開後に自動で再デプロイがトリガーされます。',
      'help_issue': '問題がありますか？',
      'help_issue_body': 'GitHub リポジトリで Issue を報告し、ログパネルのエラー情報を添付してください。',
      'version_label': 'バージョン',
      'export_dir_copied': 'エクスポートディレクトリをコピーしました: {path}',
      'export_dir_hint': 'ローカルの drafts_md エクスポートパスを表示',
      'settings_global_storage': 'グローバルファイル保存ディレクトリ',
      'global_storage_root': 'グローバル保存ルート',
      'global_storage_default': 'デフォルト（アプリプライベートディレクトリ）',
      'global_storage_hint': 'MD/画像エクスポート、クラウド同期、Git プル/プッシュ、共有一時キャッシュをすべてこのディレクトリに保存します。ルート配下に自動生成される分類サブフォルダ：MD文章 / 文章長図 / 同期キャッシュ / Git博文 / 一時共有ファイル。',
      'pick_global_storage_root': 'グローバル保存ルートを選択',
      'global_storage_set': 'グローバル保存ディレクトリを設定: {path}',
      'global_storage_reset': 'デフォルト保存ディレクトリにリセット',
      'global_storage_migrated': '{count} 個のファイルを新ディレクトリに移行',
      'copy_path': 'パスをコピー',
      'reset_storage_root': 'リセット',
      'migrate_storage_root': 'ファイルを移行',
      'pick_dir_failed': 'ディレクトリ選択に失敗',
      'hexo_writing_system': '拓墨 · AI ライティング＆静的ブログ公開',
      'sites_configured': '{count} サイト設定済み',
      'token_hint': 'ログイン済みトークンはローカルに保存され、いつでも切り替え可能です。リポジトリ作成/編集時にワンタップで再利用できます。',
      'webdav_placeholder': 'WebDAV アドレス・ユーザー名・パスワードを入力',
      'webdav_configured': '設定済み: {url}',
      'webdav_not_configured': '先に WebDAV を設定してください',
      'upload_drafts_hint': 'ローカル草稿をクラウドへ同期',
      'download_drafts_hint': 'クラウド草稿をローカルへダウンロード',
      'auto_save_interval_hint': '{count} 秒ごとに草稿スナップショットを自動保存',
      'auto_save_dir': '保存ディレクトリ（デフォルト ~/.hexo_app/auto_save）',
      'backup_dir': 'バックアップディレクトリ（デフォルト ~/.hexo_app/backup）',
      'auto_save_hint': '入力中はデバウンス保存、一定間隔で強制スナップショット、バックグラウンド/終了時に即時保存。',
      'webdav_auto_sync_enabled': '{count} 分ごとにクラウドへ同期',
      'webdav_auto_sync_disabled': '無効時は手動同期のみ',
      'status_preset_hint': 'CMS 公開時のステータスをカスタマイズ。デフォルト: publish（公開）、draft（下書き）、pending（保留）、private（非公開）。',
      'http_timeout_hint': 'タイムアウトはすべての動的 CMS サイト（WordPress / Ghost / Typecho）の HTTP リクエストに適用されます。ネットワークが遅い場合は増やしてください。',
      'image_host_no_repo': '先にリポジトリを追加してください',
      'image_host_repo_hint': '{name} / {branch} を使用、トークンはログイントークンにフォールバック',
      'image_bed_token': '画像ホストトークン（空の場合はログイントークンを使用）',
      'dir_path': 'ディレクトリパス',
      'cdn_prefix': 'カスタム CDN プレフィックス（任意）',
      'compress_hint': '最大幅 {width}px / 品質 {quality}',
      'ai_not_configured': 'AI はまだ設定されていません',
      'ai_profile_empty_hint': 'API キーと URL を入力してモデルを取得して保存。複数追加して自由に切り替えられます。',
      'ai_profile_count': '{count} プロファイル保存済み · タップして管理',
      'ai_relay_desc': 'OpenAI 互換リレーに対応: Base URL + API Key を入力 → モデル取得 → 選択して保存。',
      'status_label': 'ステータス {index}',
      'add_status': 'ステータスを追加',
    },
    // Korean
    'ko': {
      'app_title': 'Hexo 블로그 관리',
      'home': '홈',
      'posts': '게시글',
      'drafts': '초안',
      'categories': '카테고리',
      'tags': '태그',
      'settings': '설정',
      'add_site': '사이트 추가',
      'edit_site': '사이트 편집',
      'delete_site': '사이트 삭제',
      'site_name': '사이트 이름',
      'site_url': '사이트 URL',
      'preview_url': '미리보기 URL',
      'test_connection': '연결 테스트',
      'save': '저장',
      'cancel': '취소',
      'loading': '로딩 중...',
      'error': '오류',
      'success': '성공',
      'warning': '경고',
      'info': '정보',
      'confirm': '확인',
      'delete': '삭제',
      'edit': '편집',
      'view': '보기',
      'publish': '게시',
      'unpublish': '게시 취소',
      'create_post': '게시글 작성',
      'edit_post': '게시글 편집',
      'delete_post': '게시글 삭제',
      'post_title': '게시글 제목',
      'post_content': '게시글 내용',
      'post_tags': '게시글 태그',
      'post_categories': '게시글 카테고리',
      'post_status': '게시글 상태',
      'post_slug': '게시글 슬러그',
      'published': '게시됨',
      'draft': '초안',
      'static_blog': '정적 블로그',
      'dynamic_cms': '동적 CMS',
      'wordpress': 'WordPress',
      'ghost': 'Ghost',
      'typecho': 'Typecho',
      'all_sites': '모든 사이트',
      'current_site': '현재 사이트',
      'selected_sites': '선택한 사이트',
      'batch_publish': '일괄 게시',
      'batch_publish_to_all': '모든 사이트에 일괄 게시',
      'batch_publish_selected': '선택한 사이트에 일괄 게시',
      'preview': '미리보기',
      'language': '언어',
      'theme': '테마',
      'about': '정보',
      'version': '버전',
      'check_for_updates': '업데이트 확인',
      'export_data': '데이터 내보내기',
      'import_data': '데이터 가져오기',
      'reset_settings': '설정 초기화',
      'logout': '로그아웃',
      'language_updated': '언어가 업데이트되었습니다',
      'select_language': '언어 선택',
      'site_preview_url': '사이트 미리보기 URL',
      'website_name': '사이트 이름',
      'website_bio': '사이트 소개',
      'basic_info': '기본 정보',
      'github_token': 'GitHub 로그인 토큰',
      'author': '작성자',
      'contact_email': '연락 이메일',
      'repository': '저장소',
      'export_dir': '내보내기 디렉터리',
      'website_pages': '사이트 페이지 편집',
      'theme_color': '테마 색상',
      'local_drafts': '로컬 초안 · 오프라인 편집 · GitHub 게시 · 이미지 호스팅 · AI · RSS · 검색 · 커밋 롤백',
      'not_logged_in': '토큰 없음',
      'token_configured': '토큰 설정됨',
      'saved_tokens_reuse': '저장된 토큰은 여러 저장소에서 재사용할 수 있습니다',
      'saved_tokens_count': '{count}개 저장됨 · 탭하여 관리',
      'current_token': '현재 로그인 토큰',
      'switched_to': '전환됨',
      'language_selector_hint': '앱 인터페이스 언어 선택',

      // ── 내비게이션 드로어 ──
      'drawer_section_create': '작성',
      'drawer_section_manage': '관리',
      'drawer_section_tools': '도구',
      'drawer_section_ai': 'AI 도구',
      'drawer_section_system': '시스템',
      'nav_write': '글쓰기',
      'nav_drafts': '초안함',
      'nav_remote': '원격 글',
      'nav_remote_single': '원격',
      'nav_dashboard': '대시보드',
      'nav_rss': 'RSS 구독',
      'nav_history': '커밋 기록',
      'nav_upload': '일괄 업로드',
      'nav_preview': '사이트 미리보기',
      'nav_settings': '설정',
      'nav_ai_theme_migrate': 'AI 테마 마이그레이션',
      'nav_log': '작업 로그',
      'nav_sync_status': '동기화 상태',
      'nav_cloud_sync': '클라우드 동기화',
      'page_read': '읽기',
      'static_blog_posts': '정적 블로그 글',
      'all_blog_manage': '전체 블로그 관리',
      'p2p_sync': 'P2P 동기화',
      'template_manager': '템플릿 관리',
      'snippet_library': '스니펫 모음',
      'config_editor': '설정 편집기',
      'ai_batch_migrate': 'AI 일괄 마이그레이션',
      'agent_workbench': 'Agent 작업대',
      'ai_post_create': 'AI 글 작성',
      'ai_page_create': 'AI 페이지 제작',
      'ai_theme_dev': 'AI 테마 개발',
      'ai_site_audit': 'AI 사이트 점검',
      'ai_templates': 'AI 템플릿',
      'ai_models': 'AI 모델 관리',
      'tool_library': '도구 라이브러리',

      // ── 공통 동작 ──
      'batch_select': '일괄 선택',
      'refresh': '새로고침',
      'retry': '재시도',
      'no_title': '(제목 없음)',
      'just_now': '방금',
      'minutes_ago': '{count}분 전',
      'hours_ago': '{count}시간 전',
      'days_ago': '{count}일 전',
      'confirm_delete_title': '삭제 확인',

      // ── 원격 글 ──
      'posts_count': '{count}개',
      'static_blog_posts_count': '정적 블로그 글 ({count}개)',
      'no_remote_posts': '원격 글이 없습니다',
      'no_static_posts': '정적 블로그 글이 없습니다',
      'check_repo_config': '저장소 구성을 확인하세요',
      'rollback_history': '기록으로 롤백',
      'delete_remote': '원격 삭제',
      'delete_remote_post': '원격 글 삭제',
      'static_blog_prefix': '정적 블로그 · {name}',
      'cms_remote_posts': '{type} 원격 글',
      'current_site_name': '현재 사이트 · {name}',
      'all_site_posts': '전체 사이트 글',
      'selected_site_posts': '선택한 사이트 글',
      'select_site_hint': '체크한 사이트의 글만 표시됩니다. 로그인(키 구성)된 사이트가 기본 체크됩니다.',
      'tap_refresh': '새로고침 버튼을 눌러 다시 불러오기',
      'select_at_least_one_site': '사이트를 하나 이상 선택하세요',
      'site_static': '정적',
      'site_cms': 'CMS',
      'confirm_delete_remote': '원격 글 "{title}"{site}을(를) 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.',
      'deleted_prefix': '삭제됨: {title}',
      'delete_failed': '삭제 실패: {error}',
      'log_delete_remote': '원격 글 삭제',
      'log_delete_remote_failed': '원격 글 삭제 실패',

      // ── 대시보드 ──
      'dashboard_local_drafts': '로컬 초안',
      'dashboard_remote_posts': '원격 글',
      'commits_count': '커밋 수',
      'quick_actions': '빠른 작업',
      'new_post': '새 글 작성',
      'new_post_sub': '새 글 쓰기 시작',
      'manage_drafts': '초안 관리',
      'manage_drafts_sub': '로컬 초안 보기 및 편집',
      'remote_posts_sub': 'GitHub의 글 보기 및 관리',
      'commit_history': '커밋 기록',
      'commit_history_sub': '커밋 기록 보기 및 파일 롤백',
      'preview_site': '사이트 미리보기',
      'no_url_configured': 'URL 미구성',
      'settings_sub': 'Token, 저장소, AI, 백업 등 구성',
      'recent_commits': '최근 커밋',

      // ── 초안함 ──
      'unknown_site': '알 수 없는 사이트',
      'all_sites_short': '전체 사이트',
      'site_filter': '사이트 필터:',
      'no_drafts': '초안 없음',
      'site_no_drafts': '이 사이트에는 초안이 없습니다',
      'untitled': '제목 없음',
      'delete_draft': '초안 삭제',
      'confirm_delete_draft': '"{title}"을(를) 삭제하시겠습니까?',
      'word_count': '{count}자',

      // ── 설정 (섹션 및 주요 항목) ──
      'settings_basic_info': '기본 정보',
      'settings_github_token': 'GitHub 로그인 토큰',
      'settings_webdav': 'WebDAV 클라우드 백업',
      'settings_draft_backup': '초안 백업 설정',
      'settings_publish_status': '게시 상태 프리셋',
      'settings_network': '네트워크 설정',
      'settings_image_host': '이미지 호스팅 (GitHub + CDN)',
      'settings_ai_relay': 'AI 중계 (다중 프로필)',
      'settings_ai_scheduler': 'AI 스케줄러',
      'settings_site_pwa': '사이트 및 PWA',
      'settings_about': '정보',
      'manage_tokens': '저장된 토큰 관리',
      'dynamic_blog_login': '동적 블로그 로그인',
      'multi_repo_manage': '다중 저장소 관리',
      'repos_count': '현재 {count}개 저장소',
      'config_nutstore': 'Nutstore / WebDAV 구성',
      'upload_drafts_webdav': '초안을 WebDAV에 업로드',
      'sync_webdav_local': 'WebDAV에서 로컬로 동기화',
      'local_auto_save': '로컬 자동 저장',
      'auto_save_interval': '자동 저장 간격',
      'netdisk_auto_sync': '클라우드 자동 동기화',
      'netdisk_sync_interval': '클라우드 동기화 간격',
      'only_wifi_sync': 'WiFi에서만 동기화',
      'only_wifi_sync_hint': '활성화하면 WiFi 네트워크에서만 자동 동기화',
      'restore_last_session': '시작 시 마지막 세션 복원',
      'restore_last_session_hint': '백그라운드 종료 후 마지막 페이지로 자동 복원',
      'http_timeout': 'HTTP 요청 시간 제한',
      'allow_insecure_https': '안전하지 않은 HTTPS 인증서 허용',
      'allow_insecure_https_hint': 'SSL 인증서 검증 무시 (자체 서명 사이트용)',
      'image_host_sync': '현재 저장소를 이미지 호스팅으로 동기화',
      'image_host_synced': '이미지 호스팅 저장소를 {name}(으)로 동기화함',
      'auto_compress_image': '이미지 자동 압축',
      'current_ai_profile': '현재 AI 프로필',
      'auto_best_mode': '자동 최적 모드',
      'auto_best_mode_hint': '백그라운드에서 모델 지연을 측정하여 가장 빠른 모델 우선',
      'allow_ai_save_tool': 'AI 자동 저장 도구 허용',
      'allow_ai_save_tool_hint': '검증된 AI 생성 MCP/Skill 도구를 도구 상자에 자동 저장',
      'blog_address': '블로그 주소',
      'pwa_guide': 'PWA 안내',
      'pwa_guide_hint': '정적 사이트로 배포되어 브라우저에서 홈 화면에 추가할 수 있습니다.',
      'cloudflare_hook': '배포 훅',
      'theme_color_hint': '탭하여 테마 색상 변경',
      'about_author': '작성자',
      'about_developer': '개발자',
      'about_version': '버전',
      'about_email': '연락 이메일',
      'ai_request_timeout': '요청 시간 초과(초)',
      'ai_max_switch': '최대 자동 전환 횟수',
      'site_url_not_set': '사이트 주소가 설정되지 않았습니다',
      'site_url_copied': '사이트 주소를 복사했습니다',
      'cloudflare_hook_saved': '배포 훅이 저장되었습니다',
      'deploy_hook_configured': '{count}개 구성됨 (게시 후 자동 재배포)',
      'deploy_hook_not_configured': '구성되지 않음 (게시 후 수동 배포 필요)',
      'deploy_hook_title': '배포 훅',
      'deploy_hook_desc': 'Cloudflare Pages / Vercel / Netlify 등의 Deploy Hook(Build Hook)을 지원합니다. 줄마다 하나의 URL을 붙여넣으세요. 글을 게시하면 모든 재배포가 자동으로 트리거됩니다.',
      'deploy_hook_label': 'Deploy Hook URL',
      'deploy_hook_hint': 'https://api.cloudflare.com/... (줄마다 하나)',
      'site_editor_pages': '아바타 · 이름 · 홈 · 소개 · 방명록 · Now · 작품',
      'email_copied': '이메일 주소를 복사했습니다',
      'repo_copied': '저장소 주소를 복사했습니다',
      'open_repo': '오픈소스 저장소 열기',
      'open_repo_hint': '소스 보기, 이슈 제기, Star 주기',
      'about_help': '도움말',
      'about_help_hint': '사용법 및 FAQ',
      'help_title': '拓墨 · 도움말',
      'help_quick_start': '빠른 시작',
      'help_quick_start_body': '1. 설정에서 GitHub Token 또는 WebDAV 구성\n2. 저장소에 블로그 저장소 추가\n3. 「글쓰기」에서 AI 지원으로 작성\n4. 원클릭으로 사이트에 발행',
      'help_ai': 'AI 글쓰기',
      'help_ai_body': '설정에서 클라우드 모델(OpenAI/Anthropic/볼케이노 엔진 등)을 구성. 편집기에서 AI에게 개요 생성, 이어쓰기, 다듬기, 제목 만들기를 요청할 수 있습니다. Agent 워크벤치로 다단계 작성 작업도 가능합니다.',
      'help_publish': '정적 블로그 발행',
      'help_publish_body': 'GitHub Pages / 정적 블로그 / CMS 사이트에 원클릭 발행. 여러 배포 훅(Cloudflare / Vercel / Netlify)을 구성하면 발행 후 자동으로 재배포됩니다.',
      'help_issue': '문제가 있나요?',
      'help_issue_body': 'GitHub 저장소에 Issue를 제기하고 로그 패널의 오류 정보를 첨부하세요.',
      'version_label': '버전',
      'export_dir_copied': '내보내기 디렉터리를 복사했습니다: {path}',
      'export_dir_hint': '로컬 drafts_md 내보내기 경로 보기',
      'settings_global_storage': '글로벌 파일 저장 디렉터리',
      'global_storage_root': '글로벌 저장 루트',
      'global_storage_default': '기본값(앱 전용 디렉터리)',
      'global_storage_hint': 'MD/이미지 내보내기, 클라우드 동기화, Git 푸시/풀, 공유 임시 캐시를 모두 이 디렉터리에 저장합니다. 루트 아래에 자동 생성되는 분류 하위 폴더: MD文章 / 文章長図 / 同期キャッシュ / Git博文 / 一時共有ファイル.',
      'pick_global_storage_root': '글로벌 저장 루트 선택',
      'global_storage_set': '글로벌 저장 디렉터리 설정: {path}',
      'global_storage_reset': '기본 저장 디렉터리로 재설정',
      'global_storage_migrated': '{count}개 파일을 새 디렉터리로 마이그레이션',
      'copy_path': '경로 복사',
      'reset_storage_root': '재설정',
      'migrate_storage_root': '파일 마이그레이션',
      'pick_dir_failed': '디렉터리 선택 실패',
      'hexo_writing_system': '拓墨 · AI 글쓰기 & 정적 블로그 발행',
      'sites_configured': '{count}개 사이트 구성됨',
      'token_hint': '로그인한 토큰은 로컬에 저장되며 언제든 전환할 수 있습니다. 저장소 생성/편집 시 원터치로 재사용하세요.',
      'webdav_placeholder': 'WebDAV 주소, 사용자 이름, 비밀번호 입력',
      'webdav_configured': '구성됨: {url}',
      'webdav_not_configured': '먼저 WebDAV를 구성하세요',
      'upload_drafts_hint': '로컬 초안을 클라우드로 동기화',
      'download_drafts_hint': '클라우드 초안을 로컬로 다운로드',
      'auto_save_interval_hint': '{count}초마다 초안 스냅샷 자동 저장',
      'auto_save_dir': '저장 디렉터리 (기본 ~/.hexo_app/auto_save)',
      'backup_dir': '백업 디렉터리 (기본 ~/.hexo_app/backup)',
      'auto_save_hint': '입력 중 디바운스 저장, 주기마다 강제 스냅샷, 백그라운드/종료 시 즉시 저장.',
      'webdav_auto_sync_enabled': '{count}분마다 클라우드로 동기화',
      'webdav_auto_sync_disabled': '비활성화 시 수동 동기화만 가능',
      'status_preset_hint': 'CMS 게시 상태를 사용자 지정합니다. 기본: publish(게시), draft(초안), pending(보류), private(비공개).',
      'http_timeout_hint': '타임아웃은 모든 동적 CMS 사이트(WordPress / Ghost / Typecho) HTTP 요청에 적용됩니다. 네트워크가 느리면 늘리세요.',
      'image_host_no_repo': '먼저 저장소를 추가하세요',
      'image_host_repo_hint': '{name} / {branch} 사용, 토큰은 로그인 토큰으로 대체',
      'image_bed_token': '이미지 호스팅 토큰 (비우면 로그인 토큰 사용)',
      'dir_path': '디렉터리 경로',
      'cdn_prefix': '사용자 지정 CDN 접두사 (선택)',
      'compress_hint': '최대 너비 {width}px / 품질 {quality}',
      'ai_not_configured': 'AI가 아직 구성되지 않았습니다',
      'ai_profile_empty_hint': 'API 키와 URL을 입력하고 모델을 가져온 후 저장하세요. 여러 프로필을 추가해 자유롭게 전환할 수 있습니다.',
      'ai_profile_count': '{count}개 프로필 저장됨 · 탭하여 관리',
      'ai_relay_desc': 'OpenAI 호환 릴레이 지원: Base URL + API Key 입력 → 모델 가져오기 → 선택 후 저장.',
      'status_label': '상태 {index}',
      'add_status': '상태 추가',
    },
  };

  final String _locale;

  AppLocalizations(this._locale);

  /// 获取翻译文本
  String translate(String key, {Map<String, String>? params}) {
    final translations = _translations[_locale];
    if (translations != null && translations.containsKey(key)) {
      return _applyParams(translations[key]!, params);
    }
    
    // 如果找不到当前语言的翻译，尝试使用中文
    final chineseTranslations = _translations['zh-CN'];
    if (chineseTranslations != null && chineseTranslations.containsKey(key)) {
      return _applyParams(chineseTranslations[key]!, params);
    }
    
    // 如果中文也没有，返回 key
    return key;
  }

  /// 将 {占位符} 替换为具体值
  String _applyParams(String text, Map<String, String>? params) {
    if (params == null || params.isEmpty) return text;
    var result = text;
    params.forEach((k, v) {
      result = result.replaceAll('{$k}', v);
    });
    return result;
  }

  /// 获取应用标题
  String get appTitle => translate('app_title');

  /// 获取首页文本
  String get home => translate('home');

  /// 获取文章文本
  String get posts => translate('posts');

  /// 获取草稿文本
  String get drafts => translate('drafts');

  /// 获取分类文本
  String get categories => translate('categories');

  /// 获取标签文本
  String get tags => translate('tags');

  /// 获取设置文本
  String get settings => translate('settings');

  /// 获取添加站点文本
  String get addSite => translate('add_site');

  /// 获取编辑站点文本
  String get editSite => translate('edit_site');

  /// 获取删除站点文本
  String get deleteSite => translate('delete_site');

  /// 获取站点名称文本
  String get siteName => translate('site_name');

  /// 获取站点 URL 文本
  String get siteUrl => translate('site_url');

  /// 获取预览 URL 文本
  String get previewUrl => translate('preview_url');

  /// 获取测试连接文本
  String get testConnection => translate('test_connection');

  /// 获取保存文本
  String get save => translate('save');

  /// 获取取消文本
  String get cancel => translate('cancel');

  /// 获取加载中文本
  String get loading => translate('loading');

  /// 获取错误文本
  String get error => translate('error');

  /// 获取成功文本
  String get success => translate('success');

  /// 获取警告文本
  String get warning => translate('warning');

  /// 获取信息文本
  String get info => translate('info');

  /// 获取确认文本
  String get confirm => translate('confirm');

  /// 获取删除文本
  String get delete => translate('delete');

  /// 获取编辑文本
  String get edit => translate('edit');

  /// 获取查看文本
  String get view => translate('view');

  /// 获取发布文本
  String get publish => translate('publish');

  /// 获取取消发布文本
  String get unpublish => translate('unpublish');

  /// 获取创建文章文本
  String get createPost => translate('create_post');

  /// 获取编辑文章文本
  String get editPost => translate('edit_post');

  /// 获取删除文章文本
  String get deletePost => translate('delete_post');

  /// 获取文章标题文本
  String get postTitle => translate('post_title');

  /// 获取文章内容文本
  String get postContent => translate('post_content');

  /// 获取文章标签文本
  String get postTags => translate('post_tags');

  /// 获取文章分类文本
  String get postCategories => translate('post_categories');

  /// 获取文章状态文本
  String get postStatus => translate('post_status');

  /// 获取文章别名文本
  String get postSlug => translate('post_slug');

  /// 获取已发布文本
  String get published => translate('published');

  /// 获取草稿文本
  String get draft => translate('draft');

  /// 获取静态博客文本
  String get staticBlog => translate('static_blog');

  /// 获取动态 CMS 文本
  String get dynamicCms => translate('dynamic_cms');

  /// 获取 WordPress 文本
  String get wordpress => translate('wordpress');

  /// 获取 Ghost 文本
  String get ghost => translate('ghost');

  /// 获取 Typecho 文本
  String get typecho => translate('typecho');

  /// 获取所有站点文本
  String get allSites => translate('all_sites');

  /// 获取当前站点文本
  String get currentSite => translate('current_site');

  /// 获取选择站点文本
  String get selectedSites => translate('selected_sites');

  /// 获取批量发布文本
  String get batchPublish => translate('batch_publish');

  /// 获取批量发布到所有站点文本
  String get batchPublishToAll => translate('batch_publish_to_all');

  /// 获取批量发布到选定站点文本
  String get batchPublishSelected => translate('batch_publish_selected');

  /// 获取预览文本
  String get preview => translate('preview');

  /// 获取语言文本
  String get language => translate('language');

  /// 获取主题文本
  String get theme => translate('theme');

  /// 获取关于文本
  String get about => translate('about');

  /// 获取版本文本
  String get version => translate('version');

  /// 获取检查更新文本
  String get checkForUpdates => translate('check_for_updates');

  /// 获取导出数据文本
  String get exportData => translate('export_data');

  /// 获取导入数据文本
  String get importData => translate('import_data');

  /// 获取重置设置文本
  String get resetSettings => translate('reset_settings');

  /// 获取退出登录文本
  String get logout => translate('logout');

  /// 获取语言已更新文本
  String get languageUpdated => translate('language_updated');

  /// 获取选择语言文本
  String get selectLanguage => translate('select_language');

  /// 获取站点预览URL文本
  String get sitePreviewUrl => translate('site_preview_url');

  /// 获取网站名称文本
  String get websiteName => translate('website_name');

  /// 获取网站简介文本
  String get websiteBio => translate('website_bio');

  /// 获取基本信息文本
  String get basicInfo => translate('basic_info');

  /// 获取GitHub令牌文本
  String get githubToken => translate('github_token');

  /// 获取作者文本
  String get author => translate('author');

  /// 获取联系邮箱文本
  String get contactEmail => translate('contact_email');

  /// 获取仓库文本
  String get repository => translate('repository');

  /// 获取导出目录文本
  String get exportDir => translate('export_dir');

  /// 获取网站页面编辑文本
  String get websitePages => translate('website_pages');

  /// 获取主题颜色文本
  String get themeColor => translate('theme_color');

  /// 获取本地功能描述文本
  String get localDrafts => translate('local_drafts');

  /// 获取未登录文本
  String get notLoggedIn => translate('not_logged_in');

  /// 获取已配置文本
  String get tokenConfigured => translate('token_configured');

  /// 获取保存令牌复用文本
  String get savedTokensReuse => translate('saved_tokens_reuse');

  /// 获取已保存令牌数量文本
  String savedTokensCount(int count) => translate('saved_tokens_count').replaceAll('{count}', '$count');

  /// 获取当前令牌文本
  String get currentToken => translate('current_token');

  /// 获取已切换文本
  String get switchedTo => translate('switched_to');

  /// 获取语言选择提示文本
  String get languageSelectorHint => translate('language_selector_hint');

  /// 创建本地化实例
  static AppLocalizations? of(String locale) {
    return AppLocalizations(locale);
  }

  /// 从 BuildContext 获取当前语言的本地化实例
  /// 需在 MaterialApp 配置 [delegate] 后使用
  static AppLocalizations ofContext(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations('zh-CN');
  }

  /// 当前语言代码
  String get locale => _locale;

  /// MaterialApp 本地化代理
  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// 应用支持的语言列表
  static const List<Locale> supportedLocales = [
    Locale('zh'),
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
  ];
}

/// 本地化代理，负责按系统/应用语言加载对应翻译
class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLanguage.supportedLocales
      .any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final lang = AppLanguage.fromCode(locale.languageCode);
    return AppLocalizations(lang.locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}