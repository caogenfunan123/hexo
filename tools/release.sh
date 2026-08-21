#!/usr/bin/env bash
# 发布脚本：升版本号 → 更新清单 → 提交 → 打 tag → 推送。
# 用法：
#   ./tools/release.sh                     # patch +1
#   ./tools/release.sh --version 1.2.0     # 显式指定版本
#   ./tools/release.sh --notes "更新说明"   # 指定更新日志
#   ./tools/release.sh --skip-build        # 跳过 SHA256（产物未构建时）
# 依赖：git、sha256sum、python3（生成 release.json）。
# 产物路径（可选，存在才计算 SHA256）：
#   build/app/outputs/flutter-apk/app-release.apk            (universal)
#   build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
#   build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
#   hexo-windows.zip
#   hexo-linux.tar.gz
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

NOTES=""
SKIP_BUILD=0
EXPLICIT_VERSION=""

# 解析参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) EXPLICIT_VERSION="$2"; shift 2 ;;
    --notes) NOTES="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

# ── 1. 读取并递增版本号 ──
CURRENT="$(grep -E '^version:' pubspec.yaml | awk '{print $2}')"
if [[ -z "$CURRENT" ]]; then
  echo "错误：pubspec.yaml 中未找到 version"
  exit 1
fi

if [[ -n "$EXPLICIT_VERSION" ]]; then
  NEW_VERSION="$EXPLICIT_VERSION"
else
  # 形如 1.0.4+5：patch 位 +1，构建号 +1 → 1.0.5+6
  BASE="${CURRENT%%+*}"       # 1.0.4
  BUILD_NUM="${CURRENT##*+}"  # 5
  IFS='.' read -r MAJOR MINOR PATCH <<< "$BASE"
  NEW_PATCH=$((10#$PATCH + 1))
  NEW_BUILD=$((10#$BUILD_NUM + 1))
  NEW_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}+${NEW_BUILD}"
fi

# 拆出版本展示串（去 +N 构建号）
NEW_BASE="${NEW_VERSION%%+*}"
NEW_BUILD_NUM="${NEW_VERSION##*+}"
TAG="v${NEW_BASE}"

echo "版本: $CURRENT → $NEW_VERSION (tag $TAG)"

# ── 2. 同步硬编码版本字符串 ──
python3 - "$NEW_BASE" <<'PY'
import re, sys
ver = sys.argv[1]
paths = [
    "lib/main.dart",
    "lib/screens/settings_screen.dart",
]
for p in paths:
    with open(p, encoding="utf-8") as f:
        content = f.read()
    content = re.sub(r"_appVersion = '[^']*'", f"_appVersion = '{ver}'", content)
    content = re.sub(r"_cachedVersion = '[^']*'", f"_cachedVersion = '{ver}'", content)
    with open(p, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"更新版本串: {p} -> {ver}")
PY

# 更新 pubspec.yaml
python3 - "$NEW_VERSION" <<'PY'
import re, sys
ver = sys.argv[1]
with open("pubspec.yaml", encoding="utf-8") as f:
    content = f.read()
content = re.sub(r"^version: .*$", f"version: {ver}", content, flags=re.MULTILINE)
with open("pubspec.yaml", "w", encoding="utf-8") as f:
    f.write(content)
print(f"更新 pubspec.yaml -> {ver}")
PY

# ── 3. 计算各平台产物 SHA256 / size ──
# Android：universal（app-release.apk）+ arm64 + armv7 三个 APK
declare -A ARTIFACTS=(
  [android_universal]="build/app/outputs/flutter-apk/app-release.apk"
  [android_arm64]="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
  [android_armv7]="build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk"
  [windows]="hexo-windows.zip"
  [linux]="hexo-linux.tar.gz"
)

SHA_ANDROID_U=""; SIZE_ANDROID_U=0
SHA_ANDROID_ARM64=""; SIZE_ANDROID_ARM64=0
SHA_ANDROID_ARMV7=""; SIZE_ANDROID_ARMV7=0
SHA_WINDOWS=""; SIZE_WINDOWS=0
SHA_LINUX=""; SIZE_LINUX=0

if [[ "$SKIP_BUILD" == "0" ]]; then
  for key in "${!ARTIFACTS[@]}"; do
    f="${ARTIFACTS[$key]}"
    if [[ -f "$f" ]]; then
      sha=$(sha256sum "$f" | awk '{print $1}')
      size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")
      case "$key" in
        android_universal) SHA_ANDROID_U="$sha"; SIZE_ANDROID_U="$size" ;;
        android_arm64) SHA_ANDROID_ARM64="$sha"; SIZE_ANDROID_ARM64="$size" ;;
        android_armv7) SHA_ANDROID_ARMV7="$sha"; SIZE_ANDROID_ARMV7="$size" ;;
        windows) SHA_WINDOWS="$sha"; SIZE_WINDOWS="$size" ;;
        linux) SHA_LINUX="$sha"; SIZE_LINUX="$size" ;;
      esac
      echo "产物: $f sha256=${sha:0:16}... size=$size"
    else
      echo "警告: 未找到 $f（跳过 SHA256，清单留空）"
    fi
  done
else
  echo "跳过构建产物 SHA256（--skip-build）"
fi

# ── 4. 生成 release.json ──
python3 - "$NEW_BASE" "$NEW_BUILD_NUM" "$NOTES" "$TAG" \
  "$SHA_ANDROID_U" "$SIZE_ANDROID_U" \
  "$SHA_ANDROID_ARM64" "$SIZE_ANDROID_ARM64" \
  "$SHA_ANDROID_ARMV7" "$SIZE_ANDROID_ARMV7" \
  "$SHA_WINDOWS" "$SIZE_WINDOWS" "$SHA_LINUX" "$SIZE_LINUX" <<'PY'
import json, sys, datetime

version, build_num, notes, tag = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
sha_au, size_au, sha_a64, size_a64, sha_a7, size_a7, sha_w, size_w, sha_l, size_l = sys.argv[5:]

release = {
    "version": version,
    "build": int(build_num or 0),
    "name": "Hexo 写作系统",
    "notes": notes,
    "publishedAt": datetime.datetime.now().astimezone().replace(microsecond=0).isoformat(),
    "platforms": {
        "android": {
            "url": f"https://ghfast.top/https://github.com/caogenfunan123/hexo/releases/download/{tag}/app-release.apk",
            "sha256": sha_au,
            "size": int(size_au or 0),
            "abi": {
                "arm64": {
                    "url": f"https://ghfast.top/https://github.com/caogenfunan123/hexo/releases/download/{tag}/app-arm64-v8a-release.apk",
                    "sha256": sha_a64,
                    "size": int(size_a64 or 0),
                },
                "armv7": {
                    "url": f"https://ghfast.top/https://github.com/caogenfunan123/hexo/releases/download/{tag}/app-armeabi-v7a-release.apk",
                    "sha256": sha_a7,
                    "size": int(size_a7 or 0),
                },
                "universal": {
"url": f"https://ghfast.top/https://github.com/caogenfunan123/hexo/releases/download/{tag}/app-release.apk",
                    "sha256": sha_au,
                    "size": int(size_au or 0),
                },
            },
        },
        "windows": {
            "url": f"https://ghfast.top/https://github.com/caogenfunan123/hexo/releases/download/{tag}/hexo-windows.zip",
            "sha256": sha_w,
            "size": int(size_w or 0),
        },
        "linux": {
            "url": f"https://ghfast.top/https://github.com/caogenfunan123/hexo/releases/download/{tag}/hexo-linux.tar.gz",
            "sha256": sha_l,
            "size": int(size_l or 0),
        },
    },
}
with open("release.json", "w", encoding="utf-8") as f:
    json.dump(release, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(f"生成 release.json: v{version} (build {build_num})")
PY

# ── 5. 提交 + 打 tag + 推送 ──
git add pubspec.yaml lib/main.dart lib/screens/settings_screen.dart release.json
git commit -m "chore(release): v${NEW_BASE} (${NEW_VERSION})"
git tag "$TAG"
echo "推送 main 与 tag $TAG ..."
git push origin main
git push origin "$TAG"

echo ""
echo "发布已触发。请用以下命令确认 CI 全绿："
echo "  gh run list --limit 3"
echo "  gh release view $TAG --json assets --jq '.assets[].name'"
