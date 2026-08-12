/// UI 设置子配置
/// 从 AppSettings 拆分，独立管理主题、护眼、站点信息、发布状态预设
library;

import 'design_config.dart';
import 'editor_theme.dart';

class UiSettings {
  // 站点信息
  final String siteAvatar;
  final String siteName;
  final String siteBio;
  final String siteHome;
  final String siteAbout;
  final String siteGuestbook;
  final String siteNow;
  final String siteWorks;

  // 主题
  final int themeColor;

  // 夜间护眼
  final bool nightEyeProtection;
  final double nightEyeIntensity;

  // 网络
  final int httpTimeoutSeconds;
  final bool allowInsecureHttps;

  // 发布状态预设
  final List<String> statusPresets;

  // 站点预览 URL
  final String sitePreviewUrl;

  // 部署钩子（多平台可并存，如 Cloudflare/Vercel/Netlify Deploy Hook）
  final List<String> deployHooks;

  // 应用 UI 设计配置
  final DesignConfig designConfig;

  // 编辑器主题（写作界面全屏背景 + 全局文字色）
  final EditorTheme editorTheme;

  const UiSettings({
    this.siteAvatar = '',
    this.siteName = '',
    this.siteBio = '分享技术、生活和思考',
    this.siteHome = '',
    this.siteAbout = '',
    this.siteGuestbook = '',
    this.siteNow = '',
    this.siteWorks = '',
    this.themeColor = 0xFF0EA5E9,
    this.nightEyeProtection = false,
    this.nightEyeIntensity = 0.5,
    this.httpTimeoutSeconds = 30,
    this.allowInsecureHttps = false,
    this.statusPresets = const ['publish', 'draft', 'pending', 'private'],
    this.sitePreviewUrl = '',
    this.deployHooks = const [],
    this.designConfig = const DesignConfig(),
    this.editorTheme = const EditorTheme(),
  });

  /// 向后兼容：首个部署钩子
  String get cloudflareDeployHook => deployHooks.isNotEmpty ? deployHooks.first : '';

  UiSettings copyWith({
    String? siteAvatar,
    String? siteName,
    String? siteBio,
    String? siteHome,
    String? siteAbout,
    String? siteGuestbook,
    String? siteNow,
    String? siteWorks,
    int? themeColor,
    bool? nightEyeProtection,
    double? nightEyeIntensity,
    int? httpTimeoutSeconds,
    bool? allowInsecureHttps,
    List<String>? statusPresets,
    String? sitePreviewUrl,
    List<String>? deployHooks,
    DesignConfig? designConfig,
    EditorTheme? editorTheme,
  }) {
    return UiSettings(
      siteAvatar: siteAvatar ?? this.siteAvatar,
      siteName: siteName ?? this.siteName,
      siteBio: siteBio ?? this.siteBio,
      siteHome: siteHome ?? this.siteHome,
      siteAbout: siteAbout ?? this.siteAbout,
      siteGuestbook: siteGuestbook ?? this.siteGuestbook,
      siteNow: siteNow ?? this.siteNow,
      siteWorks: siteWorks ?? this.siteWorks,
      themeColor: themeColor ?? this.themeColor,
      nightEyeProtection: nightEyeProtection ?? this.nightEyeProtection,
      nightEyeIntensity: nightEyeIntensity ?? this.nightEyeIntensity,
      httpTimeoutSeconds: httpTimeoutSeconds ?? this.httpTimeoutSeconds,
      allowInsecureHttps: allowInsecureHttps ?? this.allowInsecureHttps,
      statusPresets: statusPresets ?? this.statusPresets,
      sitePreviewUrl: sitePreviewUrl ?? this.sitePreviewUrl,
      deployHooks: deployHooks ?? this.deployHooks,
      designConfig: designConfig ?? this.designConfig,
      editorTheme: editorTheme ?? this.editorTheme,
    );
  }

  Map<String, dynamic> toJson() => {
    'siteAvatar': siteAvatar,
    'siteName': siteName,
    'siteBio': siteBio,
    'siteHome': siteHome,
    'siteAbout': siteAbout,
    'siteGuestbook': siteGuestbook,
    'siteNow': siteNow,
    'siteWorks': siteWorks,
    'themeColor': themeColor,
    'nightEyeProtection': nightEyeProtection,
    'nightEyeIntensity': nightEyeIntensity,
    'httpTimeoutSeconds': httpTimeoutSeconds,
    'allowInsecureHttps': allowInsecureHttps,
    'statusPresets': statusPresets,
    'sitePreviewUrl': sitePreviewUrl,
    'deployHooks': deployHooks,
    'designConfig': designConfig.toJson(),
    'editorTheme': editorTheme.toJson(),
  };

  factory UiSettings.fromJson(Map<String, dynamic> j) => UiSettings(
    siteAvatar: j['siteAvatar']?.toString() ?? '',
    siteName: j['siteName']?.toString() ?? '',
    siteBio: j['siteBio']?.toString() ?? '分享技术、生活和思考',
    siteHome: j['siteHome']?.toString() ?? '',
    siteAbout: j['siteAbout']?.toString() ?? '',
    siteGuestbook: j['siteGuestbook']?.toString() ?? '',
    siteNow: j['siteNow']?.toString() ?? '',
    siteWorks: j['siteWorks']?.toString() ?? '',
    themeColor: (j['themeColor'] as num?)?.toInt() ?? 0xFF0EA5E9,
    nightEyeProtection: j['nightEyeProtection'] == true,
    nightEyeIntensity: (j['nightEyeIntensity'] as num?)?.toDouble() ?? 0.5,
    httpTimeoutSeconds: (j['httpTimeoutSeconds'] as num?)?.toInt() ?? 30,
    allowInsecureHttps: j['allowInsecureHttps'] == true,
    statusPresets: _parseList(j['statusPresets'], const [
      'publish',
      'draft',
      'pending',
      'private',
    ]),
    sitePreviewUrl: j['sitePreviewUrl']?.toString() ?? '',
    deployHooks: _parseDeployHooks(j),
    designConfig: j['designConfig'] is Map
        ? DesignConfig.fromJson(
            Map<String, dynamic>.from(j['designConfig'] as Map),
          )
        : const DesignConfig(),
    editorTheme: j['editorTheme'] is Map
        ? EditorTheme.fromJson(
            Map<String, dynamic>.from(j['editorTheme'] as Map),
          )
        : const EditorTheme(),
  );

  static List<String> _parseList(dynamic raw, List<String> fallback) {
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return fallback;
  }

  /// 解析部署钩子：优先新键 deployHooks（List），回退旧键 cloudflareDeployHook（String）
  static List<String> _parseDeployHooks(Map<String, dynamic> j) {
    final raw = j['deployHooks'];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    final legacy = j['cloudflareDeployHook']?.toString() ?? '';
    return legacy.isEmpty ? const [] : [legacy];
  }
}
