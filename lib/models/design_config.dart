/// 应用 UI 设计配置
///
/// 将应用界面的可定制属性抽象为配置项，
/// AI 可通过工具读取和修改这些配置，应用实时响应变化。
/// AppTheme 根据 DesignConfig 动态生成 ThemeData。
class DesignConfig {
  // ── 主题色系 ──
  /// 种子色（主色调），0xAARRGGBB 格式
  final int seedColor;

  /// 背景色（浅色模式），0xAARRGGBB
  final int lightBgColor;

  /// 卡片背景色（浅色模式）
  final int lightCardColor;

  /// 文字主色（浅色模式）
  final int lightTextColor;

  /// 背景色（深色模式）
  final int darkBgColor;

  /// 卡片背景色（深色模式）
  final int darkCardColor;

  // ── 尺寸与间距 ──
  /// 全局圆角缩放因子（1.0 = 默认，0.5 = 更尖锐，1.5 = 更圆润）
  final double borderRadiusScale;

  /// 全局内边距缩放因子
  final double paddingScale;

  /// 字号缩放因子（1.0 = 默认，0.9 = 更紧凑，1.1 = 更大）
  final double fontScale;

  // ── 布局 ──
  /// 左侧面板默认宽度
  final double leftPanelWidth;

  /// 编辑器字号
  final double editorFontSize;

  /// 编辑器行高
  final double editorLineHeight;

  // ── 视觉密度 ──
  /// 视觉密度：0=紧凑, 1=标准, 2=舒适
  final int density;

  /// 是否启用毛玻璃效果
  final bool enableBlur;

  // ── 编辑器主题 ──
  /// 编辑器代码主题名称
  final String editorTheme;

  const DesignConfig({
    this.seedColor = 0xFF0EA5E9,
    this.lightBgColor = 0xFFF0F4F8,
    this.lightCardColor = 0xFFFFFFFF,
    this.lightTextColor = 0xFF0F172A,
    this.darkBgColor = 0xFF0F172A,
    this.darkCardColor = 0xFF1E293B,
    this.borderRadiusScale = 1.0,
    this.paddingScale = 1.0,
    this.fontScale = 1.0,
    this.leftPanelWidth = 260,
    this.editorFontSize = 14.0,
    this.editorLineHeight = 1.6,
    this.density = 1,
    this.enableBlur = true,
    this.editorTheme = 'auto',
  });

  DesignConfig copyWith({
    int? seedColor,
    int? lightBgColor,
    int? lightCardColor,
    int? lightTextColor,
    int? darkBgColor,
    int? darkCardColor,
    double? borderRadiusScale,
    double? paddingScale,
    double? fontScale,
    double? leftPanelWidth,
    double? editorFontSize,
    double? editorLineHeight,
    int? density,
    bool? enableBlur,
    String? editorTheme,
  }) {
    return DesignConfig(
      seedColor: seedColor ?? this.seedColor,
      lightBgColor: lightBgColor ?? this.lightBgColor,
      lightCardColor: lightCardColor ?? this.lightCardColor,
      lightTextColor: lightTextColor ?? this.lightTextColor,
      darkBgColor: darkBgColor ?? this.darkBgColor,
      darkCardColor: darkCardColor ?? this.darkCardColor,
      borderRadiusScale: borderRadiusScale ?? this.borderRadiusScale,
      paddingScale: paddingScale ?? this.paddingScale,
      fontScale: fontScale ?? this.fontScale,
      leftPanelWidth: leftPanelWidth ?? this.leftPanelWidth,
      editorFontSize: editorFontSize ?? this.editorFontSize,
      editorLineHeight: editorLineHeight ?? this.editorLineHeight,
      density: density ?? this.density,
      enableBlur: enableBlur ?? this.enableBlur,
      editorTheme: editorTheme ?? this.editorTheme,
    );
  }

  Map<String, dynamic> toJson() => {
        'seedColor': seedColor,
        'lightBgColor': lightBgColor,
        'lightCardColor': lightCardColor,
        'lightTextColor': lightTextColor,
        'darkBgColor': darkBgColor,
        'darkCardColor': darkCardColor,
        'borderRadiusScale': borderRadiusScale,
        'paddingScale': paddingScale,
        'fontScale': fontScale,
        'leftPanelWidth': leftPanelWidth,
        'editorFontSize': editorFontSize,
        'editorLineHeight': editorLineHeight,
        'density': density,
        'enableBlur': enableBlur,
        'editorTheme': editorTheme,
      };

  factory DesignConfig.fromJson(Map<String, dynamic> j) => DesignConfig(
        seedColor: (j['seedColor'] as num?)?.toInt() ?? 0xFF0EA5E9,
        lightBgColor: (j['lightBgColor'] as num?)?.toInt() ?? 0xFFF0F4F8,
        lightCardColor: (j['lightCardColor'] as num?)?.toInt() ?? 0xFFFFFFFF,
        lightTextColor: (j['lightTextColor'] as num?)?.toInt() ?? 0xFF0F172A,
        darkBgColor: (j['darkBgColor'] as num?)?.toInt() ?? 0xFF0F172A,
        darkCardColor: (j['darkCardColor'] as num?)?.toInt() ?? 0xFF1E293B,
        borderRadiusScale: (j['borderRadiusScale'] as num?)?.toDouble() ?? 1.0,
        paddingScale: (j['paddingScale'] as num?)?.toDouble() ?? 1.0,
        fontScale: (j['fontScale'] as num?)?.toDouble() ?? 1.0,
        leftPanelWidth: (j['leftPanelWidth'] as num?)?.toDouble() ?? 260,
        editorFontSize: (j['editorFontSize'] as num?)?.toDouble() ?? 14.0,
        editorLineHeight: (j['editorLineHeight'] as num?)?.toDouble() ?? 1.6,
        density: (j['density'] as num?)?.toInt() ?? 1,
        enableBlur: j['enableBlur'] != false,
        editorTheme: j['editorTheme']?.toString() ?? 'auto',
      );

  /// 返回人类可读的配置描述（供 AI 读取）
  String toReadableDescription() {
    final densityName = switch (density) {
      0 => '紧凑',
      1 => '标准',
      2 => '舒适',
      _ => '标准',
    };
    return '''当前应用 UI 设计配置：
- 种子色: 0x${seedColor.toRadixString(16).toUpperCase()} (${_colorName(seedColor)})
- 浅色背景: 0x${lightBgColor.toRadixString(16).toUpperCase()}
- 浅色卡片: 0x${lightCardColor.toRadixString(16).toUpperCase()}
- 浅色文字: 0x${lightTextColor.toRadixString(16).toUpperCase()}
- 深色背景: 0x${darkBgColor.toRadixString(16).toUpperCase()}
- 深色卡片: 0x${darkCardColor.toRadixString(16).toUpperCase()}
- 圆角缩放: ${borderRadiusScale}x
- 内边距缩放: ${paddingScale}x
- 字号缩放: ${fontScale}x
- 左面板宽度: ${leftPanelWidth}px
- 编辑器字号: ${editorFontSize}px
- 编辑器行高: $editorLineHeight
- 视觉密度: $densityName
- 毛玻璃效果: ${enableBlur ? "开启" : "关闭"}
- 编辑器主题: $editorTheme''';
  }

  String _colorName(int color) {
    const names = {
      0xFF0EA5E9: '天蓝色',
      0xFF3B82F6: '蓝色',
      0xFF8B5CF6: '紫色',
      0xFF10B981: '绿色',
      0xFFF59E0B: '橙色',
      0xFFEF4444: '红色',
      0xFFEC4899: '粉色',
      0xFF6366F1: '靛蓝',
      0xFF14B8A6: '青色',
      0xFF0F172A: '深蓝黑',
    };
    return names[color] ?? '自定义';
  }
}
