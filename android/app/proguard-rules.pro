# Flutter 引擎的 PlayStoreDeferredComponentManager 引用了未打包的 play core 类
# 本项目未使用 Play 动态功能模块，忽略即可
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# ── Flutter 引擎 keep 规则 ──
# Flutter 使用反射加载插件与引擎组件，R8 混淆会破坏这些调用链路。
# 保持所有 Flutter 引擎类名称不变（GeneratedPluginRegistrant 已有 @Keep 注解）。
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keep class io.flutter.embedding.** { *; }

# 保持 @Keep 注解本身，R8 依赖它保留带注解的类
-keep class androidx.annotation.Keep
-keep @androidx.annotation.Keep class * { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}
