#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="AgentConsole"
BUNDLE_ID="com.agentconsole.app"
DMG_VOLUME_NAME="$APP_NAME Installer"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
DMG_ROOT="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
RELEASE_EXECUTABLE="$ROOT_DIR/.build/release/$APP_NAME"
DMG_BACKGROUND_NAME="agentconsole-dmg-background.tiff"
DMGBUILD_PYTHON="$ROOT_DIR/.build/dmgbuild-venv/bin/python"

refuse_private_payload() {
  local target="$1"

  if find "$target" -name ".agent-handoff" -o -path "*/.agent-handoff/*" | grep -q .; then
    echo "Refusing to package: .agent-handoff was found inside $target" >&2
    exit 1
  fi

  if find "$target" -path "*/AgentWorkspace/*" -o -name "ProjectRegistry.json" | grep -q .; then
    echo "Refusing to package: AgentWorkspace data was found inside $target" >&2
    exit 1
  fi

  while IFS= read -r -d '' file; do
    if strings "$file" 2>/dev/null | grep -E "$HOME|claude\\+codex|/Users/mac/Desktop|/Users/mac/Documents" >/dev/null; then
      echo "Refusing to package: private local path or project name was found in $file" >&2
      exit 1
    fi
  done < <(find "$target" -type f -print0)
}

apply_custom_file_icon() {
  local target="$1"
  local icon_png="$DIST_DIR/dmg-file-icon.png"
  local icon_rsrc="$DIST_DIR/dmg-file-icon.rsrc"

  if ! command -v Rez >/dev/null 2>&1 || ! command -v DeRez >/dev/null 2>&1 || ! command -v SetFile >/dev/null 2>&1; then
    return 0
  fi

  cp "$ROOT_DIR/Assets/AppIcon-1024.png" "$icon_png"
  sips -i "$icon_png" >/dev/null
  DeRez -only icns "$icon_png" > "$icon_rsrc" 2>/dev/null || {
    rm -f "$icon_png" "$icon_rsrc"
    return 0
  }
  Rez -append "$icon_rsrc" -o "$target" >/dev/null
  SetFile -a C "$target" >/dev/null
  rm -f "$icon_png" "$icon_rsrc"
}

Scripts/generate-icons.swift
swift Scripts/generate-dmg-background.swift
iconutil -c icns Assets/AppIcon.iconset -o Assets/AppIcon.icns
swift build -c release

rm -rf "$APP_DIR" "$DMG_ROOT" "$DMG_PATH"
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

xattr -cr "$APP_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR" >/dev/null
refuse_private_payload "$APP_DIR"

mkdir -p "$DMG_ROOT"
cp -R "$APP_DIR" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
mkdir -p "$DMG_ROOT/.background"
cp "$ROOT_DIR/Assets/$DMG_BACKGROUND_NAME" "$DMG_ROOT/.background/$DMG_BACKGROUND_NAME"
cp "$ROOT_DIR/Assets/AppIcon.icns" "$DMG_ROOT/.VolumeIcon.icns"
refuse_private_payload "$DMG_ROOT"

if [[ ! -x "$DMGBUILD_PYTHON" ]]; then
  python3 -m venv "$ROOT_DIR/.build/dmgbuild-venv"
  "$DMGBUILD_PYTHON" -m pip install --upgrade pip >/dev/null
  "$DMGBUILD_PYTHON" -m pip install dmgbuild >/dev/null
fi

"$DMGBUILD_PYTHON" -m dmgbuild \
  -s "$ROOT_DIR/Scripts/dmgbuild-settings.py" \
  -D "app_path=$APP_DIR" \
  -D "background_path=$ROOT_DIR/Assets/$DMG_BACKGROUND_NAME" \
  -D "volume_icon=$ROOT_DIR/Assets/AppIcon.icns" \
  "$DMG_VOLUME_NAME" \
  "$DMG_PATH" >/dev/null

hdiutil verify "$DMG_PATH" >/dev/null
apply_custom_file_icon "$DMG_PATH"
echo "Created $DMG_PATH"
