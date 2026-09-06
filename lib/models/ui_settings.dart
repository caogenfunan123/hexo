/// UI 设置子配置
/// 从 AppSettings 拆分，独立管理主题、护眼、站点信息、发布状态预设
library;

import 'design_config.dart';
import 'editor_theme.dart';
import 'nav_custom_config.dart';

/// 应用界面模式
enum AppMode {
  simple, // 简易普通用户模式（默认）
  standard; // 标准专业模式

  /// 反查：非法/缺失值回退 simple
  static AppMode fromKey(Object? key) =>
      key?.toString() == 'standard' ? AppMode.standard : AppMode.simple;
}

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

  // Cloudflare 凭据（模式二建站后保存，模式一为空）
  final String cfApiToken;
  final String cfAccountId;

  // 应用 UI 设计配置
  final DesignConfig designConfig;

  // 编辑器主题（写作界面全屏背景 + 全局文字色）
  final EditorTheme editorTheme;

  // 界面模式（简易普通用户模式 / 标准专业模式）
  final AppMode appMode;

  // 简易模式下手动加回显示的入口 id 集合（见 FeatureEntry）
  final List<String> simpleModeExtras;

  // 桌面侧边栏折叠的分组 key 集合（保持上次折叠状态）
  final List<String> collapsedLeftSections;

  // 用户是否显式设置过分组折叠（区分"未设置"与"全部展开"的空列表）
  final bool collapsedLeftSectionsSet;

  // 桌面左侧面板整体是否收起（持久化折叠状态）
  final bool leftPanelCollapsed;

  // 侧边栏自定义导航配置（显隐偏好 + 置顶顺序）
  final NavCustomConfig navCustom;

  // 设置页折叠的分区 key 集合（保持上次折叠状态）
  final List<String> collapsedSettingsSections;

  // 速记锚点：新建速记草稿时自动插入的文本位置（如 "## 灵感\n"）
  final String quickNoteAnchor;

  // 时间戳插入格式：date / datetime / time / yyyy-mm-dd 等
  final String timestampFormat;

  // 是否在速记草稿自动插入时间戳（配合锚点）
  final bool quickNoteTimestamp;

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
    this.cfApiToken = '',
    this.cfAccountId = '',
    this.designConfig = const DesignConfig(),
    this.editorTheme = const EditorTheme(),
    this.appMode = AppMode.simple,
    this.simpleModeExtras = const [],
    this.collapsedLeftSections = const [],
    this.collapsedLeftSectionsSet = false,
    this.leftPanelCollapsed = false,
    this.navCustom = const NavCustomConfig(),
    this.collapsedSettingsSections = const [],
    this.quickNoteAnchor = '',
    this.timestampFormat = 'date',
    this.quickNoteTimestamp = false,
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
    String? cfApiToken,
    String? cfAccountId,
    DesignConfig? designConfig,
    EditorTheme? editorTheme,
    AppMode? appMode,
    List<String>? simpleModeExtras,
    List<String>? collapsedLeftSections,
    bool? collapsedLeftSectionsSet,
    bool? leftPanelCollapsed,
    NavCustomConfig? navCustom,
    List<String>? collapsedSettingsSections,
    String? quickNoteAnchor,
    String? timestampFormat,
    bool? quickNoteTimestamp,
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
      cfApiToken: cfApiToken ?? this.cfApiToken,
      cfAccountId: cfAccountId ?? this.cfAccountId,
      designConfig: designConfig ?? this.designConfig,
      editorTheme: editorTheme ?? this.editorTheme,
      appMode: appMode ?? this.appMode,
      simpleModeExtras: simpleModeExtras ?? this.simpleModeExtras,
      collapsedLeftSections: collapsedLeftSections ?? this.collapsedLeftSections,
      collapsedLeftSectionsSet: collapsedLeftSectionsSet ?? this.collapsedLeftSectionsSet,
      leftPanelCollapsed: leftPanelCollapsed ?? this.leftPanelCollapsed,
      navCustom: navCustom ?? this.navCustom,
      collapsedSettingsSections: collapsedSettingsSections ?? this.collapsedSettingsSections,
      quickNoteAnchor: quickNoteAnchor ?? this.quickNoteAnchor,
      timestampFormat: timestampFormat ?? this.timestampFormat,
      quickNoteTimestamp: quickNoteTimestamp ?? this.quickNoteTimestamp,
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
    'cfApiToken': cfApiToken,
    'cfAccountId': cfAccountId,
    'designConfig': designConfig.toJson(),
    'editorTheme': editorTheme.toJson(),
    'appMode': appMode.name,
    'simpleModeExtras': simpleModeExtras,
    'collapsedLeftSections': collapsedLeftSections,
    'collapsedLeftSectionsSet': collapsedLeftSectionsSet,
    'leftPanelCollapsed': leftPanelCollapsed,
    'navCustom': navCustom.toJson(),
    'collapsedSettingsSections': collapsedSettingsSections,
    'quickNoteAnchor': quickNoteAnchor,
    'timestampFormat': timestampFormat,
    'quickNoteTimestamp': quickNoteTimestamp,
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
    cfApiToken: j['cfApiToken']?.toString() ?? '',
    cfAccountId: j['cfAccountId']?.toString() ?? '',
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
    appMode: AppMode.fromKey(j['appMode']),
    simpleModeExtras: _parseList(j['simpleModeExtras'], const []),
    collapsedLeftSections: _parseList(j['collapsedLeftSections'], const []),
    collapsedLeftSectionsSet: j['collapsedLeftSectionsSet'] == true,
    leftPanelCollapsed: j['leftPanelCollapsed'] == true,
    navCustom: j['navCustom'] is Map
        ? NavCustomConfig.fromJson(Map<String, dynamic>.from(j['navCustom'] as Map))
        : const NavCustomConfig(),
    collapsedSettingsSections: _parseList(j['collapsedSettingsSections'], const []),
    quickNoteAnchor: j['quickNoteAnchor']?.toString() ?? '',
    timestampFormat: j['timestampFormat']?.toString() ?? 'date',
    quickNoteTimestamp: j['quickNoteTimestamp'] == true,
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
