# 修复5：组件层硬编码色值收敛到主题令牌

日期：2026-09-12
范围：`lib/theme/app_color.dart`（新增 12 个语义令牌）+ 5 个桌面组件共 33 处替换

## 问题描述

桌面组件层散落大量硬编码色值（复盘点名列出的 5 个文件）：
`status_bar.dart`（保存/未保存状态点 0xFF4ADE80/0xFF22C55E/0xFFFBBF24/0xFFF59E0B）、
`spell_check_panel.dart`、`ai_selection_edit_dialog.dart`（AI 紫 0xFF7C4DFF ×8）、
`conflict_diff_view.dart` 与 `version_snapshot_view.dart`（diff 新增/删除/修改
三组 bg/边框色，两文件各自维护同一套值）。改一处主题要逐文件翻找，亮/暗双分支
写法碎片化。前次 chrome 收敛（commit 3312da0）已确立先例，本轮延续到组件层。

## 修复方案

### 新增语义令牌（AppColor，值取自现有硬编码，保持视觉）

| 令牌 | 亮/暗值 | 语义 |
|---|---|---|
| success | 0xFF22C55E / 0xFF4ADE80 | 成功/已保存 |
| warning | 0xFFF59E0B / 0xFFFBBF24 | 警告/未保存 |
| error | Colors.red | 错误/失败 |
| aiAccent | 0xFF7C4DFF | AI 功能强调（选区编辑/接受态） |
| diffAddedBg / diffAddedAccent | 0xFFE8F5E9·0xFF66BB6A / 0xFF1A3A2A·0xFF4CAF50 | 新增行 |
| diffRemovedBg / diffRemovedAccent | 0xFFFFEBEE·0xFFEF9A9A / 0xFF3A1A1A·0xFFEF5350 | 删除行 |
| diffModifiedBg / diffModifiedAccent | 0xFFFFF8E1·0xFFFFE082 / 0xFF2A2A1A·0xFFFFCA28 | 修改行 |
| infoBg | 0xFFE3F2FD / 0xFF2A3A5A | 信息蓝背景（选中项/远程面板头） |

### 替换原则（对齐 chrome 收敛先例）

- 状态点/徽标/diff 行背景与边框/AI 紫强调 → 新令牌（绝大多数为精确同值，
  少数近似归并，见下）。
- 通用灰阶/文字（`Colors.white : Colors.black87`、`white.withOpacity(0.7) : 0xFF374151`
  等）→ 既有 textPrimary/textSecondary/textMuted/borderStrong 令牌（近似值归并，
  与 chrome 提交做法一致）。
- **保留不动**（对比度敏感或语义成对的设计，避免为收敛而收敛）：
  - conflict_diff_view 面板标签的成对 bg+文字（0xFF1A3A2A/0xFFE8F5E9 + 深 shade 文字，
    6 处）——文字用暗 shade 保证浅底可读，替换成亮 accent 会伤对比度；
  - diff 前缀符号文字（+/− 着色 2 处）；
  - Material 调色板引用（`Colors.red.shade400`、`Colors.grey.shade500` 等 .shade 系列）；
  - status_bar L257 的 `useDark` 编辑器主题叠加色（随编辑器背景而非系统主题变化）。

## 验证

- `flutter analyze`：lib/ 0 error / 0 warning。
- `flutter test`：26/26 通过。
- 5 个文件中硬编码 hex 从 74 处降至 7 处（均为上述有意保留项）。
