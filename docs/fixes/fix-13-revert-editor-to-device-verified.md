# 修复13：手机端真所见即所得纯空白——整体回退到真机验证过的 f6504e7

日期：2026-09-16
范围：`lib/widgets/wysiwyg_web_editor.dart`、`tools/wysiwyg-builder/editor.js`、
`assets/wysiwyg/web/editor.min.js`（三件套整体回退）

## 问题描述

用户安卓真机：v1.0.15 / v1.0.16 的「真·所见即所得」开启后整页纯空白，
无 fatal、无提示。v1.0.16 的 8s 超时兜底也没有触发——说明 onLoadStop
续体根本没走到任何 await 之后。

用户提供关键情报：CI run 34793355918（commit f6504e7，fix-10 提交）
的 APK 在同一台手机上**工作正常**。回归窗口锁定 f6504e7 → v1.0.15。

## 根因

f6504e7 与 v1.0.15 在编辑器初始化链路上的唯一行为差异是 fa6115d
(fix-11) 加入的续体守卫：

```dart
if (!mounted || _webCtrl != ctrl) return;
```

在用户机型上，onWebViewCreated 与 onLoadStop 交付的 controller 引用
不一致（OEM WebView 对 PlatformView 回调时序/实例的差异化实现），
守卫恒真 → init 被无条件跳过 → 无 init、无 fatal 的纯空白。
jsdom 只模拟 JS 侧，模拟不了 Dart 侧回调时序，因此开发期全绿但真机翻车。

v1.0.16（fix-12）保留了该守卫，且把 await 链全部挂在守卫之后的路径里
（探测在守卫前但注入结果同样被守卫作废），故依旧空白；超时兜底设计上
依赖 onLoadStop 能跑到 await 点，对「守卫提前返回」这一失败类无效。

## 修复

把编辑器三件套（Dart 组件 + JS 源 + esbuild 产物）原样回退到
f6504e7——用户真机验证过的工作版本：

- `git checkout f6504e7 -- lib/widgets/wysiwyg_web_editor.dart
  tools/wysiwyg-builder/editor.js assets/wysiwyg/web/editor.min.js`
- 与 f6504e7 零差异（`git diff f6504e7 -- <三件套>` 输出为空）。

放弃的 v1.0.15/16 改动（后续需带真机验证再重新引入）：

- fix-11 续体守卫（本次空白根因，防止 dark 重建竞态的初衷需换实现）
- fix-11 editor.js 同步守卫（防丢字改进，回退到 300ms 定时窗版本）
- fix-12 IPC 注入转正/求值超时/虚拟域弃用

## 教训

1. WebView 编辑器必须过真机才能进发布版；jsdom 全绿不代表 Dart↔
   平台层正确。
2. 「纯空白无 fatal」类问题的排查顺序：先找真机可用的基线版本做 diff，
   再做架构推理。基线 diff 一步就锁定了三个版本没定位到的根因。

## 验证

- `git diff f6504e7` 三件套零差异。
- jsdom test14（探测→注入→init→回转→重复 load，11/11）、
  test12（渲染路径）全绿；test13 断言的是被回退的同步守卫行为，
  随回退作废。
- dart analyze 零新增；flutter test 46/46。
- 真机验证：装 v1.0.17 开所见即所得，行为应与 f6504e7 CI 构建的 APK
  一致。
