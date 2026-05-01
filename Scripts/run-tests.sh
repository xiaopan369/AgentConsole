#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== Agent Console Smoke Tests ==="
swift build

echo ""
echo "Checking continuation workflow text..."
grep -q "PROJECT_CONTEXT.md" Sources/AgentConsole/Services.swift
grep -q "CONVERSATION_LOG.md" Sources/AgentConsole/Services.swift
grep -q "续接同一个项目会话" Sources/AgentConsole/Services.swift
grep -q ".defaultSize(width: 1100, height: 709)" Sources/AgentConsole/AgentConsoleApp.swift
grep -q "handoffUpdateStatusDescription" Sources/AgentConsole/AppState.swift
grep -q "lastHandoffSyncCompactDescription" Sources/AgentConsole/AppState.swift
grep -q "lastHandoffRequestedAt" Sources/AgentConsole/Models.swift
grep -q "HandoffReceiptDetection" Sources/AgentConsole/Models.swift
grep -q "startupHandoffNoticeTitle" Sources/AgentConsole/Localization.swift
grep -q "随时点击\\\\n「一键更新交接文件」" Sources/AgentConsole/Localization.swift
grep -q "我知道了" Sources/AgentConsole/Localization.swift
grep -q "NSAlert()" Sources/AgentConsole/Views.swift
grep -q "presentStartupHandoffNoticeOnce" Sources/AgentConsole/Views.swift
grep -q "extractReceipt" Sources/AgentConsole/Localization.swift
grep -q "autoDetectReceipt" Sources/AgentConsole/Services.swift
grep -q "didAutoDetectReceipt" Sources/AgentConsole/AppState.swift
grep -q "一键更新交接文件" Sources/AgentConsole/Views.swift
grep -q "xiaopan_369&ChatGPT-5.5" Sources/AgentConsole/Views.swift
! grep -q "Picker(strings.currentAgent" Sources/AgentConsole/Views.swift
test -f Assets/AppIcon.icns
test -f Assets/AppIcon-1024.png
test -f Assets/AppMiniwindow.png
test -f Assets/MenuBarTemplate.png
test -f Assets/MenuBarTemplate@2x.png
test -f Assets/MenuBarLogo.png
test -f Assets/MenuBarLogo@2x.png
grep -q "CFBundleIconFile" Scripts/package-release.sh
grep -q "AppMiniwindow.png" Scripts/package-release.sh
grep -q "AppMiniwindow.png" Scripts/package-dmg.sh
grep -q "AppMiniwindow.png" Scripts/run-agent-console.sh
grep -q "MenuBarLogo@2x.png" Scripts/package-release.sh
grep -q "MenuBarLogo@2x.png" Scripts/package-dmg.sh
grep -q "MenuBarLogo@2x.png" Scripts/run-agent-console.sh
grep -q "MenuBarTemplate@2x.png" Scripts/package-release.sh
grep -q "CFBundleIconFile AppIcon.icns" Scripts/run-agent-console.sh
grep -q "CFBundleIconName" Scripts/package-release.sh
grep -q "CFBundleIconName" Scripts/package-dmg.sh
grep -q "CFBundleIconName" Scripts/run-agent-console.sh
grep -q "dmgbuild" Scripts/package-dmg.sh
grep -q "icon_locations" Scripts/dmgbuild-settings.py
grep -q "background" Scripts/dmgbuild-settings.py
grep -q '\$APP_NAME.dmg' Scripts/package-dmg.sh
grep -q "apply_custom_file_icon" Scripts/package-dmg.sh
grep -q ".VolumeIcon.icns" Scripts/package-dmg.sh
grep -q "ln -s /Applications" Scripts/package-dmg.sh
grep -q "refuse_private_payload" Scripts/package-dmg.sh
grep -q "configureApplicationIcon" Sources/AgentConsole/AppIconProvider.swift
grep -q "miniwindowIconImage" Sources/AgentConsole/AppIconProvider.swift
grep -q "willMiniaturizeNotification" Sources/AgentConsole/Views.swift
grep -q "didMiniaturizeNotification" Sources/AgentConsole/Views.swift
grep -q "window.miniwindowImage" Sources/AgentConsole/Views.swift
grep -q "window.dockTile.contentView" Sources/AgentConsole/Views.swift
grep -q "NSStatusBar.system.statusItem" Sources/AgentConsole/MenuBarController.swift
grep -q "MenuBarLogo" Sources/AgentConsole/MenuBarController.swift
grep -q "isTemplate: false" Sources/AgentConsole/MenuBarController.swift
grep -q "MenuBarTemplate" Sources/AgentConsole/MenuBarController.swift
grep -q "退出 Agent Console" Sources/AgentConsole/MenuBarController.swift
grep -q "MenuBarController.shared.configure" Sources/AgentConsole/AgentConsoleApp.swift
grep -q "AppleDockIconEnabled" Sources/AgentConsole/AgentConsoleApp.swift
grep -q "AppleDockIconEnabled" Scripts/package-release.sh
grep -q "AppleDockIconEnabled" Scripts/package-dmg.sh
grep -q "AppleDockIconEnabled" Scripts/run-agent-console.sh
grep -q "titlebarAppearsTransparent = false" Sources/AgentConsole/Views.swift
grep -q "defaultContentSize = NSSize(width: 1100, height: 709)" Sources/AgentConsole/Views.swift
grep -q "window.setContentSize(LayoutMetrics.defaultContentSize)" Sources/AgentConsole/Views.swift
! grep -q "toolbar(.hidden, for: .windowToolbar)" Sources/AgentConsole/Views.swift
! grep -q "NavigationSplitView" Sources/AgentConsole/Views.swift
! grep -q "navigationSplitView" Sources/AgentConsole/Views.swift
! grep -q "transition(.move" Sources/AgentConsole/Views.swift
grep -q "sidebarAnimationDuration" Sources/AgentConsole/Views.swift
grep -q "PrimarySidebarView()" Sources/AgentConsole/Views.swift
grep -q "SidebarHandleButton" Sources/AgentConsole/Views.swift
grep -q "sidebarIsAnimating" Sources/AgentConsole/Views.swift
grep -q "sidebarAnimationSerial" Sources/AgentConsole/Views.swift
grep -q "LightweightTextPlaceholder" Sources/AgentConsole/Views.swift
grep -q "ZStack(alignment: .leading)" Sources/AgentConsole/Views.swift
grep -q "HStack(spacing: 0)" Sources/AgentConsole/Views.swift
grep -q "frame(width: sidebarWidth, alignment: .leading)" Sources/AgentConsole/Views.swift
! grep -q "Button(action: onToggleSidebar)" Sources/AgentConsole/Views.swift
! grep -q "onToggleSidebar" Sources/AgentConsole/Views.swift
! grep -q "shadow(color:" Sources/AgentConsole/Views.swift
! grep -q "window.setFrame" Sources/AgentConsole/Views.swift
! grep -q "startConversationCaptureLoop" Sources/AgentConsole/AppState.swift
! grep -q "conversationSyncTask" Sources/AgentConsole/AppState.swift
! grep -q "App 运行时定期刷新" Sources/AgentConsole/Services.swift
grep -q "切换时自动刷新项目快照" README.md

echo ""
echo "All smoke checks passed."
