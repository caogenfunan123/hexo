#!/bin/sh
set -e
SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
ROOT="$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"
FLUTTER_OUT=build/her_flutter_debug
if [ ! -d "$FLUTTER_OUT/flutter_assets" ]; then
  echo "缺少 $FLUTTER_OUT/flutter_assets，请先运行 Flutter debug assemble。" >&2
  exit 31
fi
if [ ! -f /her/toolchains/flutter/bin/cache/artifacts/engine/android-arm64/flutter.jar ]; then
  echo "缺少 Flutter Android ARM64 debug engine，请重新执行一键配置。" >&2
  exit 32
fi
if [ ! -d /her/toolchains/flutter-android-libs ]; then
  echo "缺少 Flutter Android 打包依赖，请重新执行一键配置。" >&2
  exit 33
fi
ENGINE_JAR=/her/toolchains/flutter/bin/cache/artifacts/engine/android-arm64/flutter.jar
rm -rf android/app/src/main/assets/flutter_assets android/app/src/main/jniLibs/arm64-v8a
mkdir -p android/app/src/main/assets/flutter_assets android/app/libs android/app/src/main/jniLibs/arm64-v8a
cp -R "$FLUTTER_OUT/flutter_assets/." android/app/src/main/assets/flutter_assets/
rm -f android/app/libs/*.jar android/app/libs/*.aar
python3 - "$ENGINE_JAR" android/app/libs/flutter_embedding.jar android/app/src/main/jniLibs/arm64-v8a <<'PY'
import os
import sys
import zipfile

src, jar_out, jni_dir = sys.argv[1:4]
os.makedirs(os.path.dirname(jar_out), exist_ok=True)
os.makedirs(jni_dir, exist_ok=True)
with zipfile.ZipFile(src, "r") as zin, zipfile.ZipFile(jar_out, "w", zipfile.ZIP_DEFLATED) as jout:
    for info in zin.infolist():
        name = info.filename
        if name.endswith("/"):
            continue
        data = zin.read(info)
        if name.startswith("lib/arm64-v8a/") and os.path.basename(name) == "libflutter.so":
            with open(os.path.join(jni_dir, os.path.basename(name)), "wb") as output:
                output.write(data)
        elif name.endswith(".class") or name.startswith("META-INF/"):
            jout.writestr(name, data)
PY
cp -f /her/toolchains/flutter-android-libs/* android/app/libs/
cd android
./gradlew --no-daemon --no-watch-fs --console=plain :app:assembleDebug
ls -lh app/build/outputs/apk/debug/*.apk
