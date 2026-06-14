#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/manual"
APP_DIR="$BUILD_DIR/GTrans.app"
CORE_DIR="$BUILD_DIR/core"
ICONSET_DIR="$BUILD_DIR/GTrans.iconset"
ICON_FILE="$APP_DIR/Contents/Resources/GTrans.icns"
MENU_BAR_ICON_FILE="$APP_DIR/Contents/Resources/GTransMenuBarTemplate.png"

rm -rf "$BUILD_DIR"
mkdir -p "$CORE_DIR" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

swift "$ROOT_DIR/scripts/generate_app_icon.swift" "$ICONSET_DIR" "$MENU_BAR_ICON_FILE"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"

swiftc \
  -parse-as-library \
  -emit-library \
  -emit-module \
  -module-name GTransCore \
  "$ROOT_DIR"/Sources/GTransCore/*.swift \
  -emit-module-path "$CORE_DIR/GTransCore.swiftmodule" \
  -o "$CORE_DIR/libGTransCore.dylib"

swiftc \
  -I "$CORE_DIR" \
  -L "$CORE_DIR" \
  -lGTransCore \
  "$ROOT_DIR"/Sources/GTrans/*.swift \
  -o "$APP_DIR/Contents/MacOS/GTrans"

cp "$CORE_DIR/libGTransCore.dylib" "$APP_DIR/Contents/MacOS/libGTransCore.dylib"
install_name_tool -change "$CORE_DIR/libGTransCore.dylib" "@executable_path/libGTransCore.dylib" "$APP_DIR/Contents/MacOS/GTrans"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>G-Trans</string>
  <key>CFBundleExecutable</key>
  <string>GTrans</string>
  <key>CFBundleIdentifier</key>
  <string>local.g-trans.GTrans</string>
  <key>CFBundleIconFile</key>
  <string>GTrans</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>GTrans</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.1</string>
  <key>CFBundleVersion</key>
  <string>2</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 G-Trans.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_DIR/Contents/MacOS/libGTransCore.dylib"
codesign \
  --force \
  --sign - \
  --requirements '=designated => identifier "local.g-trans.GTrans"' \
  "$APP_DIR"
echo "$APP_DIR"
