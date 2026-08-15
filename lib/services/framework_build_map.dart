/// 框架构建映射
///
/// 对齐 design.md 第 4 节映射表（对齐 Cloudflare Pages / GitHub Actions / GitLab CI 文档），
/// 供 CI 流水线生成与首次构建产物目录校验使用。构建产物目录不写死，统一从该映射读取。
class FrameworkBuildInfo {
  final String buildCommand; // 构建命令
  final String buildOutputDirectory; // 构建产物目录
  final String buildType; // 构建类型：node / jekyll / hugo / pelican

  const FrameworkBuildInfo({
    required this.buildCommand,
    required this.buildOutputDirectory,
    required this.buildType,
  });
}

/// 框架构建映射表
class FrameworkBuildMap {
  const FrameworkBuildMap._();

  /// 各框架构建信息（对齐 design.md 第 4 节映射表）
  static const Map<String, FrameworkBuildInfo> _map = {
    'hexo': FrameworkBuildInfo(
      buildCommand: 'npm run build',
      buildOutputDirectory: 'public',
      buildType: 'node',
    ),
    'hugo': FrameworkBuildInfo(
      buildCommand: 'hugo --minify',
      buildOutputDirectory: 'public',
      buildType: 'hugo',
    ),
    'jekyll': FrameworkBuildInfo(
      buildCommand: 'jekyll build',
      buildOutputDirectory: '_site',
      buildType: 'jekyll',
    ),
    'vuepress': FrameworkBuildInfo(
      buildCommand: 'npm run docs:build',
      buildOutputDirectory: 'docs/.vuepress/dist',
      buildType: 'node',
    ),
    'gatsby': FrameworkBuildInfo(
      buildCommand: 'gatsby build',
      buildOutputDirectory: 'public',
      buildType: 'node',
    ),
    'nextjs': FrameworkBuildInfo(
      buildCommand: 'npm run build',
      buildOutputDirectory: 'out',
      buildType: 'node',
    ),
    'astro': FrameworkBuildInfo(
      buildCommand: 'npm run build',
      buildOutputDirectory: 'dist',
      buildType: 'node',
    ),
    'pelican': FrameworkBuildInfo(
      buildCommand: 'pelican content -o output -s publishconf.py',
      buildOutputDirectory: 'output',
      buildType: 'pelican',
    ),
    '11ty': FrameworkBuildInfo(
      buildCommand: 'npm run build',
      buildOutputDirectory: '_site',
      buildType: 'node',
    ),
  };

  /// 默认映射（custom 等未覆盖框架）
  static const FrameworkBuildInfo _default = FrameworkBuildInfo(
    buildCommand: 'npm run build',
    buildOutputDirectory: 'public',
    buildType: 'node',
  );

  /// 按 frameworkId 返回构建信息；未覆盖框架回退默认（node / public）
  static FrameworkBuildInfo forFramework(String frameworkId) =>
      _map[frameworkId] ?? _default;

  /// 是否内置支持的框架
  static bool isKnown(String frameworkId) => _map.containsKey(frameworkId);

  /// 全部内置框架 id 列表
  static List<String> get knownFrameworkIds => _map.keys.toList();
}
