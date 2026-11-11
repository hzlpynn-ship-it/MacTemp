#!/bin/bash
# MacTemp 构建脚本：编译 C 桥接 + Swift 源码，生成 dist/MacTemp.app（无 Xcode，纯 CLT）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
APP="$ROOT/dist/MacTemp.app"
MC="$BUILD/modulecache"
TARGET="arm64-apple-macosx14.0"

mkdir -p "$BUILD" "$MC" "$ROOT/dist"

echo "[1/5] 编译 SMC C 桥接层"
clang -O2 -Wall -Wextra -c "$ROOT/Sources/SMC/smc_bridge.c" -o "$BUILD/smc_bridge.o"

echo "[2/5] 编译 Swift 应用"
swiftc -O -target "$TARGET" \
  -module-cache-path "$MC" \
  -Xcc -fmodules-cache-path="$MC" \
  -import-objc-header "$ROOT/Sources/SMC/smc_bridge.h" \
  "$ROOT"/Sources/Models/*.swift \
  "$ROOT"/Sources/SMC/*.swift \
  "$ROOT"/Sources/Collectors/*.swift \
  "$ROOT"/Sources/App/*.swift \
  "$ROOT"/Sources/UI/*.swift \
  "$BUILD/smc_bridge.o" \
  -framework SwiftUI \
  -framework AppKit \
  -framework IOKit \
  -framework CoreGraphics \
  -o "$BUILD/MacTemp"

echo "[3/5] 生成应用图标"
if [ ! -f "$ROOT/Resources/AppIcon.icns" ] || [ "${MAC_TEMP_FORCE_ICON:-0}" = "1" ]; then
  /usr/bin/python3 "$ROOT/scripts/make_icon.py" "$BUILD/AppIcon.iconset"
  iconutil -c icns "$BUILD/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
fi

echo "[4/5] 组装 App Bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/MacTemp" "$APP/Contents/MacOS/MacTemp"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "[5/5] 代码签名（ad-hoc）"
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo ""
echo "构建完成：$APP"
echo "自测：  \"$APP/Contents/MacOS/MacTemp\" --selftest"
echo "运行：  open \"$APP\""
