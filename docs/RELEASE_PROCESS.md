# 发布流程（RELEASE_PROCESS）

本文档是**唯一权威**的发版流程。任何 AI Agent / 维护者发布新版本时都必须遵守，
否则 Releases 页面会产生噪音 release、版本号错乱、客户端收不到更新。

## 目标

- 每次发布 = 一个正式 GitHub Release（tag `vX.Y.Z`），不是每次构建都发。
- 客户端（`UpdateCheckerService`）读取 `release.json` 清单获得：版本号、各平台下载链接、SHA256、更新日志。
- 全链路（升版本 → 构建 → 发 release → 更新清单）可重复、可审计。

## 现状问题（历史遗留）

- `.github/workflows/build.yml` 的 release job 原先对**每次 main push** 都创建
  `build-<sha>` 的 release，导致 Releases 页面全是噪音。已改为仅 tag push 触发。
- 客户端原先走 GitHub Releases API（方案 A），现改为读取 `release.json`（方案 B），
  无 API 限流、免服务器。

## 版本号与清单字段

- `pubspec.yaml`：`version: X.Y.Z+N`（N 为构建号）。**唯一版本来源**。
- `lib/main.dart` `_appVersion`、`lib/screens/settings_screen.dart` `_cachedVersion`：
  硬编码的展示版本，发版时需与 `pubspec.yaml` 同步。
- `release.json`（仓库根目录）：

```json
{
  "version": "1.0.5",
  "build": 6,
  "name": "Hexo 写作系统",
  "notes": "本次更新内容（支持 \n 换行）",
  "publishedAt": "2026-08-17T10:00:00+08:00",
  "platforms": {
    "android": {
      "url": "https://github.com/caogenfunan123/hexo/releases/download/v1.0.5/app-release.apk",
      "sha256": "64 位小写 hex",
      "size": 12345678,
      "abi": {
        "arm64": {
          "url": ".../app-arm64-v8a-release.apk",
          "sha256": "64 位小写 hex",
          "size": 12345678
        },
        "armv7": {
          "url": ".../app-armeabi-v7a-release.apk",
          "sha256": "64 位小写 hex",
          "size": 12345678
        },
        "universal": {
          "url": ".../app-release.apk",
          "sha256": "64 位小写 hex",
          "size": 12345678
        }
      }
    },
    "windows": { "url": ".../hexo-windows.zip", "sha256": "", "size": 0 },
    "linux": { "url": ".../hexo-linux.tar.gz", "sha256": "", "size": 0 }
  }
}
```

- 平台键与 GitHub Actions 产物一一对应：`android`/`windows`/`linux`（`web` 暂不用于分发）。
- Android 产物结构：`android.abi` 下的 `arm64`/`armv7`/`universal` 分别对应
  `app-arm64-v8a-release.apk` / `app-armeabi-v7a-release.apk` / `app-release.apk`。
  顶层 `android.url` 指向 universal 包，**兼容暂未升级的旧客户端**。
- 客户端（`UpdateCheckerService.androidArtifact`）按设备 `Build.SUPPORTED_ABIS[0]`
  自动匹配 arm64/armv7，无匹配时回退 universal。
- 产物 URL 固定形态：`https://github.com/caogenfunan123/hexo/releases/download/{tag}/{asset}`。

## 发布步骤（固定顺序）

### 1. 前置：合并到 main 且 CI 全绿

普通功能/修复提交 push 到 main，等待 CI（analyze/build-*）全绿。此阶段**不产生 release**。

### 2. 升版本号 + 更新清单 + 打 tag（推荐一键脚本）

```bash
# 脚本会自动：递增 pubspec 版本号 → 算 release.json → 提交 → 打 tag vX.Y.Z → push
./tools/release.sh --notes "更新说明"
```

脚本行为：

1. 读取 `pubspec.yaml` 当前版本，将 patch 位 +1（`1.0.4+5` → `1.0.5+6`），
   也可用 `--version 1.2.0` 显式指定。
2. 同步 `lib/main.dart` 的 `_appVersion` 与 `lib/screens/settings_screen.dart` 的 `_cachedVersion`。
3. 计算各平台安装包（arm64/armv7/universal APK、Windows zip / Linux tar.gz，需已存在）
   的 SHA256 与字节大小，写入 `release.json` 的 `platforms`（Android 写入 `abi` 三个子项），
   更新 `version`/`build`/`notes`/`publishedAt`。
4. `git add` 相关文件 → 提交 `chore(release): v1.0.5` → 打 tag `v1.0.5` → push main + tag。

### 3. CI 构建并发布

tag push 触发 `.github/workflows/build.yml`，`release` job 构建并上传产物到
GitHub Release `v1.0.5`（命名固定：`app-release.apk` / `hexo-windows.zip` / `hexo-linux.tar.gz`）。

### 4. 校验

- 用 `gh run list` 确认 CI 全绿（analyze / build-android / build-web / build-linux / build-windows / release）。
- 用 `gh release view vX.Y.Z --json assets --jq '.assets[].name'` 确认产物齐全。
- 客户端下载直链可访问：`https://github.com/caogenfunan123/hexo/releases/download/v1.0.5/app-release.apk`。

## 不使用脚本时的手工核对清单

1. `pubspec.yaml` version 递增（`+N` 构建号 +1）。
2. `lib/main.dart` / `lib/screens/settings_screen.dart` 版本字符串同步。
3. `release.json` 五处一致：`version` / `build` / `notes` / `publishedAt` / 各平台 `url`+`sha256`+`size`。
4. 提交信息 `chore(release): vX.Y.Z`，tag `vX.Y.Z` 与 pubspec 版本一致。
5. push 后 CI 全绿，Release assets 齐全。

## 注意

- **不要**为普通功能提交打 tag 或手动创建 release，否则污染 Releases 页面。
- **不要**直接改客户端检查逻辑去适配临时字段；`release.json` 结构变更需同步
  更新 `lib/services/update_checker_service.dart` 并走一次完整发布。
- 产物 sha256 为空时客户端不会展示校验值，但 URL 仍可下载。
