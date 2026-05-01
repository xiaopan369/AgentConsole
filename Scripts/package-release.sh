#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="AgentConsole"
BUNDLE_ID="com.agentconsole.app"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/$APP_NAME-macOS.zip"
RELEASE_EXECUTABLE="$ROOT_DIR/.build/release/$APP_NAME"

Scripts/generate-icons.swift
iconutil -c icns Assets/AppIcon.iconset -o Assets/AppIcon.icns
swift build -c release

rm -rf "$APP_DIR" "$ZIP_PATH"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$RELEASE_EXECUTABLE" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/Assets/AppMiniwindow.png" "$APP_DIR/Contents/Resources/AppMiniwindow.png"
cp "$ROOT_DIR/Assets/MenuBarLogo.png" "$APP_DIR/Contents/Resources/MenuBarLogo.png"
cp "$ROOT_DIR/Assets/MenuBarLogo@2x.png" "$APP_DIR/Contents/Resources/MenuBarLogo@2x.png"
cp "$ROOT_DIR/Assets/MenuBarTemplate.png" "$APP_DIR/Contents/Resources/MenuBarTemplate.png"
cp "$ROOT_DIR/Assets/MenuBarTemplate@2x.png" "$APP_DIR/Contents/Resources/MenuBarTemplate@2x.png"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>AppleDockIconEnabled</key>
  <true/>
</dict>
</plist>
PLIST

if find "$APP_DIR" -name ".agent-handoff" -o -path "*/.agent-handoff/*" | grep -q .; then
  echo "Refusing to package: .agent-handoff was found inside $APP_DIR" >&2
  exit 1
fi

if strings "$APP_DIR/Contents/MacOS/$APP_NAME" | grep -E "$HOME|claude\\+codex" >/dev/null; then
  echo "Refusing to package: private local path or project name was found in the executable." >&2
  exit 1
fi

xattr -cr "$APP_DIR" 2>/dev/null || true
(cd "$DIST_DIR" && COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --norsrc --keepParent "$APP_NAME.app" "$ZIP_PATH")

echo "Created $ZIP_PATH"
