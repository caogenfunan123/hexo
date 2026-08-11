/// 编辑器主题配置
///
/// 控制写作界面的全屏背景与全局文字颜色：
/// - [bgMode]：0=纯白，1=纯黑，2=自定义壁纸
/// - [wallpaperPath]：壁纸图片文件路径（bgMode == 2 时生效）
/// - [forceTextMode]：0=自动适配背景，1=强制黑色字体，2=强制白色字体
library;

class EditorTheme {
  final int bgMode;
  final String wallpaperPath;
  final int forceTextMode;

  const EditorTheme({
    this.bgMode = 0,
    this.wallpaperPath = '',
    this.forceTextMode = 0,
  });

  EditorTheme copyWith({
    int? bgMode,
    String? wallpaperPath,
    int? forceTextMode,
  }) {
    return EditorTheme(
      bgMode: bgMode ?? this.bgMode,
      wallpaperPath: wallpaperPath ?? this.wallpaperPath,
      forceTextMode: forceTextMode ?? this.forceTextMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'bgMode': bgMode,
    'wallpaperPath': wallpaperPath,
    'forceTextMode': forceTextMode,
  };

  factory EditorTheme.fromJson(Map<String, dynamic> j) => EditorTheme(
    bgMode: (j['bgMode'] as num?)?.toInt() ?? 0,
    wallpaperPath: j['wallpaperPath']?.toString() ?? '',
    forceTextMode: (j['forceTextMode'] as num?)?.toInt() ?? 0,
  );

  /// 背景是否深色（用于自动判断文字颜色）
  bool get isDarkBackground {
    if (bgMode == 1) return true;
    return false;
  }
}
