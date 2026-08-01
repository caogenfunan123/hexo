#!/bin/sh
set -e
flutter pub get --offline || flutter pub get
rm -rf build/her_flutter_debug
flutter assemble --no-version-check --output=build/her_flutter_debug \
  -dTargetPlatform=android-arm64 \
  -dTargetFile=lib/main.dart \
  -dBuildMode=debug \
  -dTrackWidgetCreation=true \
  -dTreeShakeIcons=false \
  debug_android_application
sh android/build_flutter_host_apk.sh
