/// 应用常量配置
class AppConstants {
  // ── 命名规范 ──
  static const appName = 'Hexo 写作';
  static const appPackageName = 'com.hexo.blog.manager';

  // ── 框架预设路径 ──
  static const defaultHexoPostsPath = 'source/_posts';
  static const defaultHexoPagesPath = 'source';
  static const defaultHugoPostsPath = 'content/posts';
  static const defaultHugoPagesPath = 'content';
  static const defaultJekyllPostsPath = '_posts';
  static const defaultJekyllPagesPath = '';

  // ── 文件扩展名 ──
  static const markdownExtension = '.md';
  static const yamlExtension = '.yml';
  static const tomlExtension = '.toml';
  static const jsonExtension = '.json';

  // ── GitHub API ──
  static const githubApiBase = 'https://api.github.com';
  static const githubApiVersion = '2022-11-28';

  // ── 存储文件名 ──
  static const settingsFileName = 'settings.json';
  static const reposFileName = 'repos.json';
  static const draftsFileName = 'drafts.json';
  static const templatesFileName = 'templates.json';
  static const snippetsFileName = 'snippets.json';
  static const sessionFileName = 'session.json';

  // ── 默认值 ──
  static const defaultBranch = 'main';
  static const defaultAiBaseUrl = 'https://api.openai.com/v1';
  static const defaultAiModel = 'gpt-4o-mini';
  static const defaultImageBedPath = 'images';
  static const defaultCompressQuality = 80;
  static const defaultCompressMaxWidth = 1600;
  static const defaultAutoSaveInterval = 30; // 秒
  static const defaultWebdavSyncInterval = 300; // 秒
  static const maxAutoSaveSnapshots = 20;

  // ── 支持的框架列表 ──
  static const List<String> supportedFrameworks = [
    'hexo',
    'hugo',
    'jekyll',
    'vuepress',
    'gatsby',
    'nextjs',
    'astro',
    'pelican',
    '11ty',
  ];
}