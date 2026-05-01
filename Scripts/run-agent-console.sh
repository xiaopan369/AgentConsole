#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

pkill -f AgentConsole || true
swift build

DEBUG_EXECUTABLE=".build/debug/AgentConsole"
APP_EXECUTABLE=".build/AgentConsole.app/Contents/MacOS/AgentConsole"
APP_RESOURCES=".build/AgentConsole.app/Contents/Resources"
APP_PLIST=".build/AgentConsole.app/Contents/Info.plist"

if [[ -f "$DEBUG_EXECUTABLE" && -d ".build/AgentConsole.app/Contents/MacOS" ]]; then
  cp "$DEBUG_EXECUTABLE" "$APP_EXECUTABLE"
  chmod +x "$APP_EXECUTABLE"
  mkdir -p "$APP_RESOURCES"
  if [[ -f "Assets/AppIcon.icns" ]]; then
    cp "Assets/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon.icns" "$APP_PLIST" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon.icns" "$APP_PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconName AppIcon" "$APP_PLIST" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$APP_PLIST"
    /usr/libexec/PlistBuddy -c "Set :AppleDockIconEnabled true" "$APP_PLIST" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :AppleDockIconEnabled bool true" "$APP_PLIST"
  fi
  if [[ -f "Assets/AppMiniwindow.png" ]]; then
    cp "Assets/AppMiniwindow.png" "$APP_RESOURCES/AppMiniwindow.png"
  fi
  if [[ -f "Assets/MenuBarLogo.png" ]]; then
    cp "Assets/MenuBarLogo.png" "$APP_RESOURCES/MenuBarLogo.png"
  fi
  if [[ -f "Assets/MenuBarLogo@2x.png" ]]; then
    cp "Assets/MenuBarLogo@2x.png" "$APP_RESOURCES/MenuBarLogo@2x.png"
  fi
  if [[ -f "Assets/MenuBarTemplate.png" ]]; then
    cp "Assets/MenuBarTemplate.png" "$APP_RESOURCES/MenuBarTemplate.png"
  fi
  if [[ -f "Assets/MenuBarTemplate@2x.png" ]]; then
    cp "Assets/MenuBarTemplate@2x.png" "$APP_RESOURCES/MenuBarTemplate@2x.png"
  fi
  echo "Synced $DEBUG_EXECUTABLE -> $APP_EXECUTABLE"
fi

open "$ROOT_DIR/.build/AgentConsole.app"
