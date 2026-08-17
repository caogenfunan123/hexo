/// 侧边栏自定义导航配置
///
/// 用户可在"自定义侧边栏"对话框中切换每个入口的显隐并置顶常用项。
/// 已自定义（customized=true）时显隐偏好覆盖模式默认过滤；
/// 未自定义（customized=false）时回落 AppMode 默认过滤逻辑。
library;

class NavCustomConfig {
  /// 用户是否做过自定义（false 时回落模式默认过滤）
  final bool customized;

  /// 入口 id → 是否显示于侧边栏（customized 后生效）
  final Map<String, bool> visible;

  /// 置顶入口 id 列表（有序），其余按原分组渲染
  final List<String> pinnedOrder;

  const NavCustomConfig({
    this.customized = false,
    this.visible = const {},
    this.pinnedOrder = const [],
  });

  /// 判断某入口是否被用户显式配置过
  bool hasOverride(String id) =>
      customized && visible.containsKey(id);

  /// 判断某入口是否在置顶列表中
  bool isPinned(String id) => pinnedOrder.contains(id);

  NavCustomConfig copyWith({
    bool? customized,
    Map<String, bool>? visible,
    List<String>? pinnedOrder,
  }) {
    return NavCustomConfig(
      customized: customized ?? this.customized,
      visible: visible ?? this.visible,
      pinnedOrder: pinnedOrder ?? this.pinnedOrder,
    );
  }

  Map<String, dynamic> toJson() => {
    'customized': customized,
    'visible': visible,
    'pinnedOrder': pinnedOrder,
  };

  factory NavCustomConfig.fromJson(Map<String, dynamic> j) {
    final visRaw = j['visible'];
    final pinRaw = j['pinnedOrder'];
    return NavCustomConfig(
      customized: j['customized'] == true,
      visible: visRaw is Map
          ? (visRaw.map((k, v) => MapEntry(k.toString(), v == true)))
          : const {},
      pinnedOrder: pinRaw is List
          ? pinRaw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : const [],
    );
  }
}