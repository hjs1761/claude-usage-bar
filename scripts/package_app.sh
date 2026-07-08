#!/bin/bash
# swift build → .app 번들 조립 → LSUIElement Info.plist → ad-hoc 서명 → 실행.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Claude Usage Bar"
BIN_NAME="ClaudeUsageBar"
BUILD_CONFIG="${1:-debug}"   # debug(기본) | release
VERSION="${2:-1.3}"          # 배포 버전(Info.plist 스탬프). 예: package_app.sh release 1.3

echo ">> swift build ($BUILD_CONFIG) v$VERSION"
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
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>$BIN_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

echo ">> ad-hoc 서명"
codesign --force --deep --sign - "$APP_DIR"

# release는 /Applications에 설치해 거기서 실행(안정 위치 — .build 클린돼도 무관).
# debug는 .build에서 실행(개발 편의).
RUN_APP="$APP_DIR"
if [ "$BUILD_CONFIG" = "release" ]; then
  DEST="/Applications/$APP_NAME.app"
  echo ">> /Applications 설치"
  rm -rf "$DEST"
  ditto "$APP_DIR" "$DEST"
  RUN_APP="$DEST"
fi

echo ">> 실행 ($RUN_APP)"
# 기존 인스턴스 종료 후 재실행 (중복 방지)
pkill -x "$BIN_NAME" 2>/dev/null || true
sleep 0.3
open "$RUN_APP"
echo "완료: $RUN_APP"
# ⚠ 로그인 항목(SMAppService)은 앱 설정 토글에서만 등록됨 → 설치 위치 바꾼 뒤엔
#    앱 설정에서 '로그인 시 실행' off→on 한 번 해줘야 새 경로로 재등록됨.
