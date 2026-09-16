# 修复12：安卓真机所见即所得静默空白——弃用虚拟域外链 + 求值超时兜底

日期：2026-09-16
范围：`lib/widgets/wysiwyg_web_editor.dart`

## 问题描述

用户在安卓真机（v1.0.15 正式版 APK）上开启「真·所见即所得」后整页空白：
无 fatal 提示、无回退源码、无任何报错。v1.0.14 无此模式（WebView 编辑器
v1.0.15 首次进发布版，本会话全程无真机，安卓 WebView 层从未真机验证过）。

「空白而无 fatal」只有三类可能：onLoadStop 永不触发、evaluateJavascript
挂起、init 前空模板 + 透明背景。三者都无人兜底。

## 根因

### 1. 虚拟域外链必然 404（结构性）

`_buildHtml` 在安卓把 KaTeX css/js 挂到 WebViewAssetLoader 虚拟域
（`appassets.androidplatform.net/assets/...`）。但插件（flutter_inappwebview
6.1.5 `WebViewAssetLoaderExt.fromMap`）直接用 androidx `AssetsPathHandler`
注册——它以**安卓资产根**为基准解析路径，而 Flutter 资产在 APK 里带
`flutter_assets/` 前缀，`/assets/wysiwyg/web/katex.min.css` 永远映射到
不存在的安卓资产（848786f 当年弃用编辑器 bundle 虚拟域的正是这个 404，
fix-10 只给 katex 加了兜底注入，外链本身还挂着）。

404 通常能快速失败，但一旦设备上 `shouldInterceptRequest` 拦截未生效，
请求落到真实网络（该域名无公网解析），`<link>` + `<script src>` 的
load 阻塞特征就会把 `load` 事件卡住 → onLoadStop 永不触发 → 无 init、
无 fatal、纯空白。

### 2. evaluateJavascript 无超时

onLoadStop 里探测/注入（642KB IPC）/init 全是裸 await。安卓渲染进程
卡死或 IPC 挂起时这些调用永不返回，整个续体悬挂，症状同样是纯空白。

## 修复

1. **HTML 内不再有任何 KaTeX 外链**：`__KATEX_CSS__` / `__KATEX_JS__`
   占位符全平台替换为空串。KaTeX 统一在 onLoadStop 经 IPC 注入
   （css 367KB / js 275KB，单次均低于 1MB Binder 限制），load 事件
   不再依赖任何网络/拦截行为。
2. **`_evalTimed` 统一包装**：每次 evaluateJavascript 带 8s 超时。
   注入步骤超时降级为 latex 原文（math-raw），init 超时/返回 null 走
   fatal——用户至多等 8 秒就能看到明确失败态并自动回源码模式，
   静默空白路径全部封死。
3. **探测无响应立即判死**：`!!window.katex` 探测 8s 无返回说明渲染
   进程已卡死，继续注入只会连环超时白等 20 多秒，直接 `_reportFatal`。
4. **保留虚拟域仅作安全网**：安卓仍配 baseUrl + AssetLoader（https
   安全上下文 + 零星绝对路径请求 404 兜住，不落到真实网络），但任何
   页面资源都不再依赖它。

## 验证

- jsdom test14（新增，11/11）：模拟 onLoadStop 序列——探测 → 注入真
  katex.min.css（367KB style 语句）→ eval 真 katex.min.js（275KB）→
  init 返回 true → 公式 KaTeX 渲染无 raw 回落 → 编辑回转不丢 →
  模拟安卓 load 重复触发二次 init 不炸。
- jsdom test12（渲染路径）、test13（守卫同步释放）全绿。
- dart analyze：改档仅存量 2 条 info，零新增。

## 遗留

真机上若仍空白（修复后应为「8 秒内报错+回源码」而非静默空白），
fatal 文案会带定位信息（探测无响应 / init 未确认 / 求值超时），
可据此进一步定位设备侧问题。
