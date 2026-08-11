# Flutter 引擎的 PlayStoreDeferredComponentManager 引用了未打包的 play core 类
# 本项目未使用 Play 动态功能模块，忽略即可
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
