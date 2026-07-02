#!/bin/bash
# swift build → .app 번들 조립 → LSUIElement Info.plist → ad-hoc 서명 → 실행.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Claude Usage Bar"
BIN_NAME="ClaudeUsageBar"
BUILD_CONFIG="${1:-debug}"   # debug(기본) | release

echo ">> swift build ($BUILD_CONFIG)"
swift build -c "$BUILD_CONFIG" --product "$BIN_NAME"
BIN_PATH="$(swift build -c "$BUILD_CONFIG" --show-bin-path)/$BIN_NAME"

APP_DIR=".build/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$BIN_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>local.claude-usage-bar</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>$BIN_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

echo ">> ad-hoc 서명"
codesign --force --deep --sign - "$APP_DIR"

echo ">> 실행"
# 기존 인스턴스 종료 후 재실행 (중복 방지)
pkill -x "$BIN_NAME" 2>/dev/null || true
sleep 0.3
open "$APP_DIR"
echo "완료: $APP_DIR"
