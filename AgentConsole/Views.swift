import AppKit
import SwiftUI

private enum LayoutMetrics {
    static let sidebarMinWidth: CGFloat = 240
    static let sidebarIdealWidth: CGFloat = 320
    static let sidebarMaxWidth: CGFloat = 380
    static let sidebarAnimationDuration: TimeInterval = 0.18
    static let sessionsMinWidth: CGFloat = 290
    static let sessionsIdealWidth: CGFloat = 310
    static let sessionsMaxWidth: CGFloat = 360
    static let detailHorizontalPadding: CGFloat = 20
    static let detailBottomPadding: CGFloat = 28
    static let statusBarHeight: CGFloat = 23
    static let defaultContentSize = NSSize(width: 1100, height: 709)
    static let minWindowSize = NSSize(width: 1100, height: 720)
}

private enum AppTheme {
    static let windowBackground = adaptive(
        light: NSColor(calibratedRed: 0.945, green: 0.944, blue: 0.936, alpha: 1),
        dark: NSColor(calibratedRed: 0.045, green: 0.047, blue: 0.052, alpha: 1)
    )
    static let barBackground = adaptive(
        light: NSColor(calibratedRed: 0.965, green: 0.963, blue: 0.955, alpha: 1),
        dark: NSColor(calibratedRed: 0.086, green: 0.083, blue: 0.087, alpha: 1)
    )
    static let sidebarBackground = adaptive(
        light: NSColor(calibratedRed: 0.925, green: 0.929, blue: 0.925, alpha: 1),
        dark: NSColor(calibratedRed: 0.078, green: 0.083, blue: 0.092, alpha: 1)
    )
    static let panelBackground = adaptive(
        light: NSColor(calibratedRed: 0.985, green: 0.982, blue: 0.973, alpha: 1),
        dark: NSColor(calibratedRed: 0.112, green: 0.108, blue: 0.111, alpha: 1)
    )
    static let editorBackground = adaptive(
        light: NSColor(calibratedRed: 0.995, green: 0.993, blue: 0.985, alpha: 1),
        dark: NSColor(calibratedRed: 0.075, green: 0.073, blue: 0.076, alpha: 1)
    )
    static let hairline = adaptive(
        light: NSColor.black.withAlphaComponent(0.12),
        dark: NSColor.white.withAlphaComponent(0.085)
    )
    static let subtleFill = adaptive(
        light: NSColor.black.withAlphaComponent(0.055),
        dark: NSColor.white.withAlphaComponent(0.055)
    )
    static let selectedFill = adaptive(
        light: NSColor(calibratedRed: 0.78, green: 0.88, blue: 0.98, alpha: 1),
        dark: NSColor(calibratedRed: 0.14, green: 0.28, blue: 0.42, alpha: 1)
    )
    static let cellFill = adaptive(
        light: NSColor.white.withAlphaComponent(0.48),
        dark: NSColor.white.withAlphaComponent(0.035)
    )
    static let border = adaptive(
        light: NSColor.black.withAlphaComponent(0.10),
        dark: NSColor.white.withAlphaComponent(0.075)
    )
    static let softBorder = adaptive(
        light: NSColor.black.withAlphaComponent(0.08),
        dark: NSColor.white.withAlphaComponent(0.055)
    )
    static let sectionText = adaptive(
        light: NSColor.black.withAlphaComponent(0.54),
        dark: NSColor.white.withAlphaComponent(0.58)
    )
    static let controlForeground = adaptive(
        light: NSColor.black.withAlphaComponent(0.88),
        dark: NSColor.white.withAlphaComponent(0.94)
    )
    static let controlForegroundPressed = adaptive(
        light: NSColor.black.withAlphaComponent(0.66),
        dark: NSColor.white.withAlphaComponent(0.82)
    )
    static let controlFill = adaptive(
        light: NSColor.black.withAlphaComponent(0.045),
        dark: NSColor.white.withAlphaComponent(0.065)
    )
    static let controlFillPressed = adaptive(
        light: NSColor.black.withAlphaComponent(0.09),
        dark: NSColor.white.withAlphaComponent(0.13)
    )
    static let controlBorder = adaptive(
        light: NSColor.black.withAlphaComponent(0.12),
        dark: NSColor.white.withAlphaComponent(0.12)
    )
    static let controlBorderPressed = adaptive(
        light: NSColor.black.withAlphaComponent(0.18),
        dark: NSColor.white.withAlphaComponent(0.22)
    )
    static let accent = Color(red: 0.37, green: 0.67, blue: 1.0)

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? dark : light
        })
    }
}

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @AppStorage("ui.sidebarCollapsed") private var sidebarCollapsed = false
    @State private var sidebarIsAnimating = false
    @State private var sidebarAnimationSerial = 0
    @State private var didPresentStartupHandoffNotice = false

    var body: some View {
        let sidebarWidth: CGFloat = sidebarCollapsed ? 0 : LayoutMetrics.sidebarIdealWidth

        VStack(spacing: 0) {
            AppTopBar(
                onOpenSettings: { openSettings() }
            )

            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    PrimarySidebarView()
                        .frame(width: LayoutMetrics.sidebarIdealWidth)
                        .frame(width: sidebarWidth, alignment: .leading)
                        .clipped()
                        .allowsHitTesting(!sidebarCollapsed)
                        .accessibilityHidden(sidebarCollapsed)

                    MainWorkspaceView(isSidebarAnimating: sidebarIsAnimating)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.top, 8)
                }

                SidebarHandleButton(
                    collapsed: sidebarCollapsed,
                    onToggle: toggleSidebar
                )
                .offset(x: sidebarCollapsed ? 10 : LayoutMetrics.sidebarIdealWidth - 16)
            }
            .tint(Color(red: 0.37, green: 0.67, blue: 1.0))
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            StatusBarView()
        }
        .background {
            ZStack {
                AppTheme.windowBackground
            }
            .ignoresSafeArea()

            WindowConfigurator()
        }
        .onAppear {
            presentStartupHandoffNoticeOnce()
        }
    }

    private func presentStartupHandoffNoticeOnce() {
        guard !didPresentStartupHandoffNotice else { return }
        didPresentStartupHandoffNotice = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            let strings = appState.strings
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = strings.startupHandoffNoticeTitle
            alert.informativeText = strings.startupHandoffNoticeBody
            alert.addButton(withTitle: strings.startupHandoffNoticeAcknowledge)

            if let window = NSApp.windows.first(where: { $0.title == "Agent Console" && $0.isVisible })
                ?? NSApp.keyWindow
                ?? NSApp.mainWindow {
                _ = await alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
        }
    }

    private func toggleSidebar() {
        sidebarAnimationSerial += 1
        let animationSerial = sidebarAnimationSerial

        withTransaction(Transaction(animation: nil)) {
            sidebarIsAnimating = true
        }

        withAnimation(.easeOut(duration: LayoutMetrics.sidebarAnimationDuration)) {
            sidebarCollapsed.toggle()
        }

        Task { @MainActor in
            let delay = UInt64((LayoutMetrics.sidebarAnimationDuration + 0.06) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard sidebarAnimationSerial == animationSerial else { return }
            withTransaction(Transaction(animation: nil)) {
                sidebarIsAnimating = false
            }
        }
    }
}

struct MainWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    let isSidebarAnimating: Bool

    var body: some View {
        SessionDetailView(isSidebarAnimating: isSidebarAnimating)
    }
}

private struct AppTopBar: View {
    @EnvironmentObject private var appState: AppState
    let onOpenSettings: () -> Void

    var body: some View {
        let strings = appState.strings
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(strings.appTitle)
                    .font(.system(size: 15, weight: .semibold))
                Text(statusSummary(strings: strings))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 14)

            HStack(spacing: 8) {
                Button {
                    appState.importSingleProject()
                } label: {
                    ToolbarIcon(systemName: "square.and.arrow.down")
                }
                .buttonStyle(TopBarTextButtonStyle())
                .help(strings.importProject)

                Button {
                    appState.switchToAgent(.claude)
                } label: {
                    ToolbarIcon(systemName: "arrow.right.circle")
                }
                .buttonStyle(TopBarTextButtonStyle())
                .disabledWithReason(appState.switchAgentDisabledReason)
                .help(strings.switchToClaude)

                Button {
                    appState.switchToAgent(.codex)
                } label: {
                    ToolbarIcon(systemName: "arrow.left.circle")
                }
                .buttonStyle(TopBarTextButtonStyle())
                .disabledWithReason(appState.switchAgentDisabledReason)
                .help(strings.switchToCodex)

                Button {
                    appState.copyPrompt()
                } label: {
                    ToolbarIcon(systemName: "doc.on.doc")
                }
                .buttonStyle(TopBarTextButtonStyle())
                .disabledWithReason(appState.copyPromptDisabledReason)
                .help(strings.copyPrompt)
            }

            Menu {
                Button(strings.importProject) {
                    appState.importSingleProject()
                }
                Divider()
                Button(menuTitle(strings.openProject, disabledReason: appState.projectActionDisabledReason)) {
                    appState.revealProjectInFinder()
                }
                .disabled(appState.projectActionDisabledReason != nil)
                Button(menuTitle(appState.appLanguage == .zhHans ? "打开 .agent-handoff" : "Open .agent-handoff", disabledReason: appState.projectActionDisabledReason)) {
                    appState.openHandoffDirectory()
                }
                .disabled(appState.projectActionDisabledReason != nil)
                Button(menuTitle(appState.appLanguage == .zhHans ? "打开当前 session 文件夹" : "Open Current Session Folder", disabledReason: appState.switchAgentDisabledReason)) {
                    appState.openCurrentSessionDirectory()
                }
                .disabled(appState.switchAgentDisabledReason != nil)
                Divider()
                Button(strings.openSettings) {
                    onOpenSettings()
                }
            } label: {
                Label(strings.moreActions, systemImage: "ellipsis.circle")
            }
            .buttonStyle(TopBarTextButtonStyle())
        }
        .labelStyle(.titleAndIcon)
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .center)
        .background(AppTheme.barBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.hairline)
                .frame(height: 1)
        }
    }

    private func statusSummary(strings: AppStrings) -> String {
        let project = appState.selectedProject?.metadata.name ?? strings.none
        let session = appState.selectedSession?.metadata.name ?? strings.none
        return "\(project) · \(session)"
    }

    private func menuTitle(_ title: String, disabledReason: String?) -> String {
        guard let disabledReason else { return title }
        return "\(title) (\(disabledReason))"
    }
}

private struct SidebarHandleButton: View {
    @EnvironmentObject private var appState: AppState
    let collapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack {
            Spacer(minLength: 0)

            Button {
                onToggle()
            } label: {
                Image(systemName: collapsed ? "chevron.right" : "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SidebarHandleButtonStyle())
            .help(collapsed
                ? (appState.appLanguage == .zhHans ? "展开侧边栏" : "Expand sidebar")
                : (appState.appLanguage == .zhHans ? "折叠侧边栏" : "Collapse sidebar")
            )
            .accessibilityLabel(collapsed
                ? (appState.appLanguage == .zhHans ? "展开侧边栏" : "Expand sidebar")
                : (appState.appLanguage == .zhHans ? "折叠侧边栏" : "Collapse sidebar")
            )

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

struct PrimarySidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let strings = appState.strings
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(strings.appTitle)
                            .font(.system(size: 18, weight: .semibold))

                        Text(strings.importedProjects(appState.filteredProjects.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 10)
                }

                Text(appState.appLanguage == .zhHans
                    ? "只做一件事：导入项目，切换 Agent，复制续接提示词。"
                    : "One job: import a project, switch agents, copy the continuation prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appState.filteredProjects.isEmpty {
                    if appState.projects.isEmpty {
                        ContentUnavailableView(
                            strings.noProjectsCompactTitle,
                            systemImage: "folder.badge.questionmark",
                            description: Text(strings.noProjectsCompactDescription)
                        )
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        ContentUnavailableView(
                            appState.appLanguage == .zhHans ? "没有匹配的项目" : "No Matching Projects",
                            systemImage: "magnifyingglass",
                            description: Text(appState.appLanguage == .zhHans ? "调整搜索关键字后再试。" : "Try a different search query.")
                        )
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionTitle(strings.projects)

                            VStack(spacing: 8) {
                                ForEach(appState.filteredProjects) { project in
                            Button {
                                appState.selectProject(project.metadata.path)
                            } label: {
                                ZStack(alignment: .leading) {
                                    sidebarCellBackground(isSelected: appState.selectedProjectPath == project.metadata.path)
                                    if appState.selectedProjectPath == project.metadata.path {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(AppTheme.accent)
                                            .frame(width: 3)
                                            .padding(.vertical, 10)
                                            .padding(.leading, 1)
                                    }
                                    ProjectRow(project: project, language: appState.appLanguage)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 9)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                            }

                            if let project = appState.selectedProject {
                                sectionTitle(appState.appLanguage == .zhHans ? "当前交接" : "Current Handoff")
                                Text(project.metadata.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                if let session = appState.selectedSession {
                                    SessionRow(session: session, gitSnapshot: project.gitSnapshot, language: appState.appLanguage)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 9)
                                        .background(sidebarCellBackground(isSelected: true))
                                } else {
                                    Text(strings.noSessionsDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 8)
                                }

                                Text(appState.appLanguage == .zhHans
                                    ? "切换时自动刷新 handoff 和项目内容快照。"
                                    : "Switching refreshes handoff and project context automatically.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(strings.selectProjectFirst)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 8)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Rectangle()
                .fill(AppTheme.hairline)
                .frame(height: 1)

            sidebarFooter(strings: strings)
                .padding(.horizontal, 12)
                .padding(.top, 9)
                .padding(.bottom, 10)
        }
        .frame(
            minWidth: LayoutMetrics.sidebarMinWidth,
            idealWidth: LayoutMetrics.sidebarIdealWidth,
            maxWidth: LayoutMetrics.sidebarMaxWidth,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            Rectangle()
                .fill(AppTheme.sidebarBackground)
        )
        .overlay {
            Rectangle()
                .strokeBorder(AppTheme.hairline)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.sectionText)
            .textCase(.uppercase)
            .tracking(0.4)
    }

    private func sidebarCellBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? AppTheme.selectedFill.opacity(0.92) : AppTheme.cellFill)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? AppTheme.accent.opacity(0.55) : AppTheme.border)
            )
    }

    private func sidebarFooter(strings: AppStrings) -> some View {
        HStack(spacing: 8) {
            Button {
                appState.importSingleProject()
            } label: {
                Label(strings.importProject, systemImage: "square.and.arrow.down")
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .buttonStyle(SidebarToolButtonStyle())
            .controlSize(.small)
            .help(strings.importProject)
            .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 40)
        .frame(maxWidth: .infinity)
    }
}

struct ProjectRow: View {
    let project: ProjectSummary
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.metadata.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                BadgeLabel(text: project.displayAgent.label(for: language), tint: badgeTint)
            }

            Text(shortenedPath(project.metadata.path))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack {
                Text(localizedDateTime(project.displayUpdatedAt, language: language))
                Spacer()
                Text(project.activeSession?.metadata.name ?? AppStrings(language: language).none)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private var badgeTint: Color {
        switch project.displayAgent {
        case .codex:
            return .blue
        case .claude:
            return .green
        case .unknown:
            return .secondary
        }
    }

    private func shortenedPath(_ path: String) -> String {
        path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}

struct SessionListView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let strings = appState.strings
        Group {
            if appState.projects.isEmpty {
                FirstRunEmptyStateView()
            } else if let project = appState.selectedProject {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(strings.sessions)
                            .font(.headline.weight(.semibold))
                        Text(project.metadata.name)
                            .font(.headline)
                        Text(project.metadata.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14)

                    if project.sessions.isEmpty {
                        ContentUnavailableView(
                            strings.noSessionsTitle,
                            systemImage: "tray",
                            description: Text(strings.noSessionsDescription)
                        )
                    } else {
                        Picker(appState.appLanguage == .zhHans ? "会话筛选" : "Session Filter", selection: Binding(
                            get: { appState.sessionArchiveFilter },
                            set: { appState.changeSessionArchiveFilter($0) }
                        )) {
                            ForEach(SessionArchiveFilter.allCases) { filter in
                                Text(filter.label(for: appState.appLanguage)).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .padding(.horizontal, 14)

                        List(selection: Binding(
                            get: { appState.selectedSessionID },
                            set: { appState.selectSession($0) }
                        )) {
                            ForEach(appState.filteredSessionsForArchiveFilter) { session in
                                SessionRow(session: session, gitSnapshot: project.gitSnapshot, language: appState.appLanguage)
                                    .tag(session.metadata.id as String?)
                            }
                        }
                        .listStyle(.inset)
                    }
                }
                .frame(
                    minWidth: LayoutMetrics.sessionsMinWidth,
                    idealWidth: LayoutMetrics.sessionsIdealWidth,
                    maxWidth: LayoutMetrics.sessionsMaxWidth,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView(
                    strings.selectProjectTitle,
                    systemImage: "folder",
                    description: Text(strings.noSelectedProjectBody)
                )
            }
        }
    }
}

struct SessionRow: View {
    let session: SessionBundle
    let gitSnapshot: GitSnapshot
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.metadata.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if session.metadata.isPrimary {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.yellow)
                        .help(language == .zhHans ? "主会话" : "Primary Session")
                }
                BadgeLabel(text: session.metadata.currentAgent.label(for: language), tint: agentTint)
            }

            HStack {
                Text(formattedDate(session.metadata.updatedAt))
                Spacer()
                Text(gitSnapshot.summary(for: language))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)

            HStack {
                BadgeLabel(text: session.metadata.handoffReceiptStatus.label(for: language), tint: receiptTint)
                if session.metadata.isArchived {
                    BadgeLabel(text: language == .zhHans ? "已归档" : "Archived", tint: .secondary)
                }
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        localizedDateTime(date, language: language)
    }

    private var agentTint: Color {
        switch session.metadata.currentAgent {
        case .codex:
            return .blue
        case .claude:
            return .green
        case .unknown:
            return .secondary
        }
    }

    private var receiptTint: Color {
        switch session.metadata.handoffReceiptStatus {
        case .pending:
            return .orange
        case .confirmed:
            return .green
        case .failed:
            return .red
        }
    }
}

struct SessionDetailView: View {
    @EnvironmentObject private var appState: AppState
    let isSidebarAnimating: Bool
    @State private var showDeleteConfirmation = false
    @State private var showCleanupConfirmation = false

    var body: some View {
        let strings = appState.strings
        Group {
            if appState.projects.isEmpty {
                FirstRunEmptyStateView()
            } else if let project = appState.selectedProject, let session = appState.selectedSession {
                VStack(alignment: .leading, spacing: 14) {
                    sessionHeader(project: project, session: session)
                        .padding(.horizontal, LayoutMetrics.detailHorizontalPadding)
                        .padding(.top, 14)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            gitWarning(project.gitSnapshot)
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .top, spacing: 14) {
                                    documentsEditor
                                    .frame(minWidth: 580, maxWidth: .infinity, alignment: .topLeading)
                                VStack(alignment: .leading, spacing: 14) {
                                    promptPreview
                                }
                                .frame(width: 390, alignment: .topLeading)
                            }

                            VStack(alignment: .leading, spacing: 14) {
                                documentsEditor
                                promptPreview
                            }
                        }
                    }
                        .padding(.horizontal, LayoutMetrics.detailHorizontalPadding)
                        .padding(.bottom, LayoutMetrics.detailBottomPadding)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView(
                    strings.selectSessionTitle,
                    systemImage: "note.text",
                    description: Text(strings.selectSessionDescription)
                )
            }
        }
    }

    @ViewBuilder
    private func sessionHeader(project: ProjectSummary, session: SessionBundle) -> some View {
        let strings = appState.strings
        SurfacePanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.metadata.name)
                            .font(.system(size: 25, weight: .semibold))
                        Text(project.metadata.path)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Text(appState.appLanguage == .zhHans
                    ? "你的操作只需要：确认当前 Agent，点击切换按钮，复制提示词到另一个 Agent 的新会话。切换会刷新 handoff；一键更新会顺便检测交接回执。"
                    : "Use only this flow: confirm the current agent, click a switch button, then paste the copied prompt into the other agent's new chat. Switching refreshes handoff; manual update also checks the receipt.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                    DetailChip(title: strings.currentAgent, value: session.metadata.currentAgent.label(for: appState.appLanguage), tint: chipTint(for: session.metadata.currentAgent))
                    DetailChip(title: strings.git, value: project.gitSnapshot.summary(for: appState.appLanguage), tint: project.gitSnapshot.state == .dirty ? .orange : .secondary)
                    DetailChip(title: strings.promptDirection, value: appState.generatedPromptTitle.isEmpty ? strings.generatedPromptFallback : appState.generatedPromptTitle, tint: .secondary)
                    DetailChip(title: strings.receiptStatus, value: session.metadata.handoffReceiptStatus.label(for: appState.appLanguage), tint: receiptTint(for: session.metadata.handoffReceiptStatus))
                    DetailChip(title: appState.appLanguage == .zhHans ? "交接状态" : "Handoff Status", value: appState.handoffUpdateStatusDescription, tint: appState.registry.lastHandoffSyncAt == nil ? .orange : .green)
                }

                HStack(spacing: 6) {
                    Image(systemName: appState.registry.lastHandoffSyncAt == nil ? "clock.badge.exclamationmark" : "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(appState.registry.lastHandoffSyncAt == nil ? .orange : .secondary)
                    Text(appState.appLanguage == .zhHans
                        ? "交接更新时间：\(appState.lastHandoffSyncCompactDescription)"
                        : "Handoff updated: \(appState.lastHandoffSyncCompactDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let summary = appState.lastHandoffSyncDisplaySummary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .help(appState.lastHandoffSyncDescription)

                HStack(spacing: 10) {
                    Button {
                        appState.switchToAgent(.claude)
                    } label: {
                        Label(strings.switchToClaude, systemImage: "arrow.right.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabledWithReason(appState.switchAgentDisabledReason)

                    Button {
                        appState.switchToAgent(.codex)
                    } label: {
                        Label(strings.switchToCodex, systemImage: "arrow.left.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabledWithReason(appState.switchAgentDisabledReason)

                    Button {
                        appState.syncCurrentStateToHandoff()
                    } label: {
                        Label(appState.appLanguage == .zhHans ? "一键更新交接文件" : "Update Handoff Now", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabledWithReason(appState.syncHandoffDisabledReason)
                }
            }
        }
    }

    @ViewBuilder
    private func gitWarning(_ snapshot: GitSnapshot) -> some View {
        let strings = appState.strings
        if snapshot.state == .dirty {
            SurfacePanel {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(strings.gitDirtyTitle)
                            .font(.headline)
                        Text(strings.gitDirtyBody)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var documentsEditor: some View {
        let strings = appState.strings
        return SurfacePanel {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.handoffFiles)
                        .font(.headline.weight(.semibold))
                    Text(appState.appLanguage == .zhHans
                         ? "交接文件由 Agent 自动维护；切换和一键更新时刷新快照。"
                         : "Handoff files are maintained by agents; switching and manual update refresh snapshots.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Picker(strings.document, selection: $appState.selectedDocument) {
                    ForEach(HandoffDocumentType.allCases) { doc in
                        Text(doc.title(for: appState.appLanguage)).tag(doc)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 520)
            }

            if isSidebarAnimating {
                LightweightTextPlaceholder(
                    title: appState.selectedDocument.title(for: appState.appLanguage),
                    detail: layoutPlaceholderDetail(for: appState.documentDrafts[appState.selectedDocument] ?? ""),
                    minHeight: 520
                )
            } else {
                TextEditor(text: Binding(
                    get: { appState.documentDrafts[appState.selectedDocument] ?? "" },
                    set: { appState.updateDraft($0, for: appState.selectedDocument) }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 520)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(AppTheme.editorBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(AppTheme.softBorder)
                )
            }
        }
    }

    private var promptPreview: some View {
        let strings = appState.strings
        return SurfacePanel {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(strings.promptPreview)
                        .font(.headline.weight(.semibold))
                    if !appState.generatedPromptTitle.isEmpty {
                        Text(appState.generatedPromptTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    appState.copyPrompt()
                } label: {
                    Label(strings.copyPrompt, systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabledWithReason(appState.copyPromptDisabledReason)
            }

            HStack(spacing: 10) {
                InfoCard(title: strings.previousAgent, value: appState.promptPreviousAgent.label(for: appState.appLanguage))
                InfoCard(title: strings.targetAgent, value: appState.promptTargetAgent.label(for: appState.appLanguage))
                InfoCard(title: strings.promptDirection, value: appState.generatedPromptTitle.isEmpty ? strings.generatedPromptFallback : appState.generatedPromptTitle)
            }

            if isSidebarAnimating {
                LightweightTextPlaceholder(
                    title: strings.promptPreview,
                    detail: layoutPlaceholderDetail(for: appState.generatedPrompt),
                    minHeight: 230
                )
            } else {
                ScrollView {
                    Text(appState.generatedPrompt.isEmpty ? strings.promptPreviewHint : appState.generatedPrompt)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 230)
                .background(AppTheme.editorBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(AppTheme.softBorder)
                )
            }
        }
    }

    private var receiptSection: some View {
        let strings = appState.strings
        let receiptStatus = appState.selectedSession?.metadata.handoffReceiptStatus.label(for: appState.appLanguage) ?? strings.generatedPromptFallback
        let lastUpdated = appState.selectedSession?.metadata.lastHandoffReceiptAt.map { formattedDate($0) } ?? strings.none

        return SurfacePanel {
            ViewThatFits(in: .horizontal) {
                HStack {
                    receiptSummary(strings: strings, receiptStatus: receiptStatus, lastUpdated: lastUpdated)
                    Spacer()
                    receiptButtons(strings: strings)
                }

                VStack(alignment: .leading, spacing: 10) {
                    receiptSummary(strings: strings, receiptStatus: receiptStatus, lastUpdated: lastUpdated)
                    receiptButtons(strings: strings)
                }
            }

            TextEditor(text: $appState.receiptDraft)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 190)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(AppTheme.editorBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(AppTheme.softBorder)
                )
        }
    }

    private func formattedDate(_ date: Date) -> String {
        localizedDateTime(date, language: appState.appLanguage)
    }

    private func layoutPlaceholderDetail(for text: String) -> String {
        let count = text.count
        if appState.appLanguage == .zhHans {
            return count == 0 ? "空内容" : "\(count) 字"
        }
        return count == 0 ? "Empty" : "\(count) characters"
    }

    private func chipTint(for agent: AgentKind) -> Color {
        switch agent {
        case .codex:
            return .blue
        case .claude:
            return .green
        case .unknown:
            return .secondary
        }
    }

    private func receiptTint(for status: HandoffReceiptStatus) -> Color {
        switch status {
        case .pending:
            return .orange
        case .confirmed:
            return .green
        case .failed:
            return .red
        }
    }



    private func receiptSummary(strings: AppStrings, receiptStatus: String, lastUpdated: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(strings.receiptTitle)
                .font(.headline.weight(.semibold))
            Text("\(strings.receiptStatus): \(receiptStatus) · \(strings.updatedAt): \(lastUpdated)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func receiptButtons(strings: AppStrings) -> some View {
        HStack(spacing: 8) {
            Button(strings.pasteReceipt) {
                appState.saveReceiptDraft()
            }
            .buttonStyle(.bordered)

            Button(strings.markConfirmed) {
                appState.markReceiptConfirmed()
            }
            .buttonStyle(.bordered)

            Button(strings.markFailed) {
                appState.markReceiptFailed()
            }
            .buttonStyle(.bordered)

            Button(strings.clearReceipt) {
                appState.clearReceipt()
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct LightweightTextPlaceholder: View {
    let title: String
    let detail: String
    let minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            RoundedRectangle(cornerRadius: 4)
                .fill(AppTheme.subtleFill)
                .frame(width: 180, height: 8)
            RoundedRectangle(cornerRadius: 4)
                .fill(AppTheme.subtleFill)
                .frame(width: 260, height: 8)
            RoundedRectangle(cornerRadius: 4)
                .fill(AppTheme.subtleFill)
                .frame(maxWidth: .infinity, minHeight: 8, maxHeight: 8)

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(AppTheme.editorBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppTheme.softBorder)
        )
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

struct PromptTemplatesView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pageHeader(
                    title: appState.appLanguage == .zhHans ? "Prompt 模板编辑器" : "Prompt Template Editor",
                    subtitle: appState.appLanguage == .zhHans
                        ? "中文和英文模板分开维护。安全规则与 handoff 读取规则会在生成提示词时锁定追加，避免误删。"
                        : "Chinese and English templates are maintained separately. Safety and handoff-read rules are locked into generated prompts."
                )

                SurfacePanel {
                    Picker(appState.appLanguage == .zhHans ? "模板" : "Template", selection: $appState.selectedPromptTemplateSlot) {
                        ForEach(PromptTemplateSlot.allCases) { slot in
                            Text(slot.title(for: appState.appLanguage)).tag(slot)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextEditor(text: Binding(
                        get: { appState.promptTemplateDrafts[appState.selectedPromptTemplateSlot] ?? "" },
                        set: { appState.updatePromptTemplateDraft($0, for: appState.selectedPromptTemplateSlot) }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 360)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.editorBackground, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AppTheme.softBorder))

                    HStack {
                        Button {
                            appState.savePromptTemplates()
                        } label: {
                            Label(appState.appLanguage == .zhHans ? "保存模板" : "Save Templates", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            appState.restoreDefaultPromptTemplate()
                        } label: {
                            Label(appState.appLanguage == .zhHans ? "恢复当前默认" : "Restore Selected", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            appState.restoreAllDefaultPromptTemplates()
                        } label: {
                            Label(appState.appLanguage == .zhHans ? "恢复全部默认" : "Restore All", systemImage: "arrow.2.circlepath")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                SurfacePanel {
                    Text(appState.appLanguage == .zhHans ? "锁定规则预览" : "Locked Rules Preview")
                        .font(.headline.weight(.semibold))
                    Text(appState.appLanguage == .zhHans
                        ? "生成提示词时始终附加：读取 ACTIVE_PROJECT.md / ACTIVE_SESSION.md / 当前 session handoff；不得读取其他项目；不得写入、记录、上传或泄露 token、cookie、API key、密码、私钥、auth.json 或 .env；完成后更新 handoff。"
                        : "Generated prompts always include: read ACTIVE_PROJECT.md / ACTIVE_SESSION.md / current session handoff; do not read other projects; do not write, log, upload, or expose tokens, cookies, API keys, passwords, private keys, auth.json, or .env; update handoff after completion.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, LayoutMetrics.detailHorizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, LayoutMetrics.detailBottomPadding)
        }
    }
}

struct UsageQuotaView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedBreakdown: UsageBreakdown = .project

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pageHeader(
                    title: appState.appLanguage == .zhHans ? "用量与额度" : "Usage & Quotas",
                    subtitle: appState.appLanguage == .zhHans
                        ? "先建立安全的本地数据模型和 UI。没有真实 usage 数据时显示空状态，不伪造统计。"
                        : "This page starts with a safe local model and UI. Empty states are shown when no real usage data exists."
                )

                HStack {
                    Button {
                        appState.refreshUsageSources()
                    } label: {
                        Label(appState.appLanguage == .zhHans ? "刷新本地来源" : "Refresh Local Sources", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Text(appState.appLanguage == .zhHans
                        ? "只检测文件或环境变量是否存在，不读取 token 内容。"
                        : "Only detects whether files or environment variables exist; token values are not read.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        accountPanel(provider: .codex)
                        accountPanel(provider: .claude)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        accountPanel(provider: .codex)
                        accountPanel(provider: .claude)
                    }
                }

                tokenPanel
            }
            .padding(.horizontal, LayoutMetrics.detailHorizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, LayoutMetrics.detailBottomPadding)
        }
    }

    private func accountPanel(provider: AgentKind) -> some View {
        let accounts = appState.usageWorkspace.accounts.filter { $0.provider == provider }
        let activeMode = accounts.first(where: \.isActive)?.mode.label(for: appState.appLanguage) ?? (appState.appLanguage == .zhHans ? "未知" : "Unknown")
        return SurfacePanel {
            HStack {
                Label(provider.rawValue, systemImage: provider == .codex ? "terminal" : "sparkle.magnifyingglass")
                    .font(.headline.weight(.semibold))
                Spacer()
                BadgeLabel(text: activeMode, tint: accounts.contains(where: \.isActive) ? .green : .secondary)
            }

            if accounts.isEmpty {
                ContentUnavailableView(
                    appState.appLanguage == .zhHans ? "没有账号数据" : "No Account Data",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text(provider == .codex ? codexAccountHint : claudeAccountHint)
                )
                .frame(minHeight: 120)
            } else {
                ForEach(accounts) { account in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text("\(account.source.rawValue) · \(account.mode.label(for: appState.appLanguage))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let planName = account.planName {
                                Text(planName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if account.isActive {
                            BadgeLabel(text: appState.appLanguage == .zhHans ? "当前" : "Active", tint: .green)
                        } else {
                            Button(appState.appLanguage == .zhHans ? "设为当前" : "Set Active") {
                                appState.setActiveUsageAccount(account)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help(appState.appLanguage == .zhHans ? "只更新 Agent Console 的本地 active account 标记，不切换真实账号。" : "Only updates Agent Console's local active account marker; it does not switch real accounts.")
                        }
                    }
                }
            }

            HStack {
                Button(provider == .codex ? codexOAuthLabel : claudeOAuthLabel) {}
                    .buttonStyle(.bordered)
                    .disabled(true)
                    .help(appState.appLanguage == .zhHans ? "预留入口，尚未接入真实 OAuth。" : "Reserved entry; real OAuth is not connected yet.")
                Button(provider == .codex ? codexImportLabel : claudeImportLabel) {}
                    .buttonStyle(.bordered)
                    .disabled(true)
                    .help(appState.appLanguage == .zhHans ? "预留入口，不会自动读取或上传 token 文件。" : "Reserved entry; token files are not read or uploaded automatically.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var tokenPanel: some View {
        SurfacePanel {
            HStack {
                Text(appState.appLanguage == .zhHans ? "Token 统计" : "Token Usage")
                    .font(.headline.weight(.semibold))
                Spacer()
                Picker(appState.appLanguage == .zhHans ? "时间范围" : "Range", selection: Binding(
                    get: { appState.selectedUsageRange },
                    set: { appState.changeUsageRange($0) }
                )) {
                    ForEach(UsageRange.allCases) { range in
                        Text(range.label(for: appState.appLanguage)).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 360)
            }

            if appState.selectedUsageRange == .custom {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        DatePicker(appState.appLanguage == .zhHans ? "开始" : "Start", selection: Binding(
                            get: { appState.customUsageStartDate },
                            set: { appState.updateCustomUsageRange(start: $0) }
                        ), displayedComponents: [.date])
                        DatePicker(appState.appLanguage == .zhHans ? "结束" : "End", selection: Binding(
                            get: { appState.customUsageEndDate },
                            set: { appState.updateCustomUsageRange(end: $0) }
                        ), displayedComponents: [.date])
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        DatePicker(appState.appLanguage == .zhHans ? "开始" : "Start", selection: Binding(
                            get: { appState.customUsageStartDate },
                            set: { appState.updateCustomUsageRange(start: $0) }
                        ), displayedComponents: [.date])
                        DatePicker(appState.appLanguage == .zhHans ? "结束" : "End", selection: Binding(
                            get: { appState.customUsageEndDate },
                            set: { appState.updateCustomUsageRange(end: $0) }
                        ), displayedComponents: [.date])
                    }
                }
                .font(.caption)
            }

            HStack {
                Text(appState.appLanguage == .zhHans ? "汇总维度" : "Breakdown")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker(appState.appLanguage == .zhHans ? "汇总维度" : "Breakdown", selection: $selectedBreakdown) {
                    ForEach(UsageBreakdown.allCases) { breakdown in
                        Text(breakdown.label(for: appState.appLanguage)).tag(breakdown)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 330)
            }

            let records = usageRecordsForCurrentSelection
            if records.isEmpty {
                ContentUnavailableView(
                    appState.appLanguage == .zhHans ? "暂无真实 Token 数据" : "No Real Token Data",
                    systemImage: "chart.xyaxis.line",
                    description: Text(emptyTokenDescription)
                )
                .frame(minHeight: 160)
            } else {
                usageSummaryGrid(records)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Provider")
                        Text("Project")
                        Text("Session")
                        Text("Model")
                        Text("Input")
                        Text("Output")
                        Text("Cache")
                        Text("Total")
                        Text("Cost")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    ForEach(records) { record in
                        GridRow {
                            Text(record.provider.rawValue)
                            Text(record.projectPath ?? appState.strings.none)
                            Text(record.sessionID ?? appState.strings.none)
                            Text(record.model ?? appState.strings.none)
                            tokenText(record.inputTokens)
                            tokenText(record.outputTokens)
                            tokenText(record.cacheTokens)
                            tokenText(record.totalTokens)
                            Text(record.cost.map { "\($0)" } ?? appState.strings.none)
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private var usageRecordsForCurrentSelection: [TokenUsageRecord] {
        appState.filteredUsageTokenRecords
    }

    private var emptyTokenDescription: String {
        let base = appState.appLanguage == .zhHans
            ? "当前只显示本地安全模型。接入真实数据源前不会伪造 input/output/cache/cost。"
            : "Only the safe local model is present. Input/output/cache/cost are not fabricated."
        let breakdown = selectedBreakdown.label(for: appState.appLanguage)
        return appState.appLanguage == .zhHans
            ? "\(base) 当前维度：\(breakdown)。"
            : "\(base) Current breakdown: \(breakdown)."
    }

    private func usageSummaryGrid(_ records: [TokenUsageRecord]) -> some View {
        let groups = groupedUsageRows(records)
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text(selectedBreakdown.label(for: appState.appLanguage))
                Text("Input")
                Text("Output")
                Text("Cache")
                Text("Total")
                Text("Cost")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            ForEach(groups, id: \.key) { row in
                GridRow {
                    Text(row.key)
                    tokenText(row.input)
                    tokenText(row.output)
                    tokenText(row.cache)
                    tokenText(row.total)
                    Text(row.cost)
                }
                .font(.caption)
            }
        }
        .padding(.bottom, 8)
    }

    private func groupedUsageRows(_ records: [TokenUsageRecord]) -> [(key: String, input: Int, output: Int, cache: Int, total: Int, cost: String)] {
        var grouped: [String: (input: Int, output: Int, cache: Int, total: Int, cost: Decimal?)] = [:]
        for record in records {
            let key: String
            switch selectedBreakdown {
            case .project:
                key = record.projectPath ?? appState.strings.none
            case .session:
                key = record.sessionID ?? appState.strings.none
            case .model:
                key = record.model ?? appState.strings.none
            }
            var current = grouped[key] ?? (0, 0, 0, 0, nil)
            current.input += record.inputTokens
            current.output += record.outputTokens
            current.cache += record.cacheTokens
            current.total += record.totalTokens
            if let cost = record.cost {
                current.cost = (current.cost ?? 0) + cost
            }
            grouped[key] = current
        }
        return grouped.map { key, value in
            (key, value.input, value.output, value.cache, value.total, value.cost.map { "\($0)" } ?? appState.strings.none)
        }
        .sorted { lhs, rhs in
            if lhs.total != rhs.total { return lhs.total > rhs.total }
            return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }
    }

    private var codexAccountHint: String {
        appState.appLanguage == .zhHans
            ? "预留 OAuth、导入 ~/.codex/auth.json、API 配置识别和 active account。不会偷读 cookies。"
            : "Reserved for OAuth, importing ~/.codex/auth.json, API config detection, and active account. Cookies are not read."
    }

    private var claudeAccountHint: String {
        appState.appLanguage == .zhHans
            ? "预留本地导入、OAuth 可行性和 API 配置识别。不会把 token 写入 handoff、prompt 或日志。"
            : "Reserved for local import, OAuth feasibility, and API config detection. Tokens are not written to handoff, prompts, or logs."
    }

    private var codexOAuthLabel: String { appState.appLanguage == .zhHans ? "Codex OAuth（预留）" : "Codex OAuth (Reserved)" }
    private var claudeOAuthLabel: String { appState.appLanguage == .zhHans ? "Claude OAuth（预留）" : "Claude OAuth (Reserved)" }
    private var codexImportLabel: String { appState.appLanguage == .zhHans ? "导入 auth.json（预留）" : "Import auth.json (Reserved)" }
    private var claudeImportLabel: String { appState.appLanguage == .zhHans ? "本地导入（预留）" : "Local Import (Reserved)" }

    private func tokenText(_ value: Int) -> some View {
        Text(formatTokenCount(value))
            .help("\(value)")
    }
}

private enum UsageBreakdown: String, CaseIterable, Identifiable {
    case project
    case session
    case model

    var id: String { rawValue }

    func label(for language: AppLanguage) -> String {
        switch self {
        case .project:
            return language == .zhHans ? "按项目" : "By Project"
        case .session:
            return language == .zhHans ? "按 Session" : "By Session"
        case .model:
            return language == .zhHans ? "按 Model" : "By Model"
        }
    }
}

struct DiagnosticsWorkspaceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DiagnosticsPanel()
            }
            .padding(.horizontal, LayoutMetrics.detailHorizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, LayoutMetrics.detailBottomPadding)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let strings = appState.strings
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(strings.settings)
                    .font(.largeTitle.weight(.bold))

                Text(strings.settingsDescription)
                    .foregroundStyle(.secondary)

                SurfacePanel {
                    HStack {
                        Label(strings.languageLabel, systemImage: "globe")
                            .font(.headline)
                        Spacer()
                        Picker(strings.languageLabel, selection: Binding(
                            get: { appState.appLanguage },
                            set: { appState.changeLanguage($0) }
                        )) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }

                    settingsRow(appState.appLanguage == .zhHans ? "外观" : "Appearance", value: appState.appLanguage == .zhHans ? "跟随系统（浅色 / 深色）" : "Follow System (Light / Dark)")
                    settingsRow(appState.appLanguage == .zhHans ? "App 工作台路径" : "App Workspace Path", value: appState.workspacePath)
                    settingsRow(appState.appLanguage == .zhHans ? "版本 / 当前构建产物" : "Version / Current Build", value: appState.appBuildInfo)
                    settingsRow(appState.appLanguage == .zhHans ? "实际运行产物" : "Running Executable", value: appState.appRuntimeInfo)
                    settingsRow(appState.appLanguage == .zhHans ? "推荐启动脚本" : "Recommended Launcher", value: appState.launcherScriptPath.isEmpty ? (appState.appLanguage == .zhHans ? "未在项目源码中找到" : "Not found in project source") : appState.launcherScriptPath)
                    Toggle(isOn: Binding(
                        get: { appState.autoSyncHandoffEnabled },
                        set: { appState.setAutoSyncHandoffEnabled($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appState.appLanguage == .zhHans ? "自动交接（文件监听）" : "Auto Handoff (File Watch)")
                            Text(appState.appLanguage == .zhHans ? "监听交接文件变化并刷新界面；切换和一键更新时才重写快照。" : "Watch handoff files and refresh the UI; snapshots are rewritten only on switch or manual update.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    settingsRow(appState.appLanguage == .zhHans ? "最近 handoff 同步" : "Last Handoff Sync", value: appState.lastHandoffSyncDescription)
                    settingsRow(appState.appLanguage == .zhHans ? "工作流" : "Workflow", value: appState.appLanguage == .zhHans ? "导入项目、确认当前 Agent、切换并复制提示词。" : "Import project, confirm current agent, switch and copy prompt.")
                }

                Text("xiaopan_369&ChatGPT-5.5")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func settingsRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.caption)
    }
}

struct StatusBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let strings = appState.strings
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                statusItem(strings.statusCurrentProject, value: appState.selectedProject?.metadata.name ?? strings.none)
                statusSeparator
                statusItem(strings.statusCurrentSession, value: appState.selectedSession?.metadata.name ?? strings.none)
                statusSeparator
                statusItem(strings.statusCurrentAgent, value: appState.selectedSession?.metadata.currentAgent.label(for: appState.appLanguage) ?? strings.unknown)
                statusSeparator
                statusItem(strings.git, value: appState.selectedProject?.gitSnapshot.summary(for: appState.appLanguage) ?? strings.unknown)

                if let compact = compactStatusMessage(appState.statusMessage) {
                    statusSeparator
                    Text(compact.text)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(compact.isTruncated ? appState.statusMessage : compact.text)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.trailing, 8)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: LayoutMetrics.statusBarHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Color(red: 0.01, green: 0.03, blue: 0.08).opacity(0.14))
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.hairline)
                .frame(height: 1)
        }
    }

    private func statusItem(_ title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
    }

    private var statusSeparator: some View {
        Text("·")
            .foregroundStyle(.tertiary)
    }

    private func compactStatusMessage(_ message: String) -> (text: String, isTruncated: Bool)? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()

        if trimmed.contains("失败")
            || trimmed.contains("错误")
            || lowered.contains("failed")
            || lowered.contains("error")
            || lowered.contains("couldn't")
            || lowered.contains("could not")
            || lowered.contains("cannot")
            || lowered.contains("unable to")
            || lowered.contains("could not be opened")
            || lowered.contains("can't be opened") {
            return (appState.appLanguage == .zhHans ? "操作失败" : "Operation failed", false)
        }

        let maxLength = 36
        guard trimmed.count > maxLength else {
            return (trimmed, false)
        }
        return ("\(trimmed.prefix(maxLength - 1))…", true)
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            WindowLayoutController.shared.configure(using: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            WindowLayoutController.shared.configure(using: nsView)
        }
    }
}

@MainActor
private final class WindowLayoutController {
    static let shared = WindowLayoutController()

    private var didConfigureWindow = false
    private var miniwindowObserverTokens: [ObjectIdentifier: [NSObjectProtocol]] = [:]

    func configure(using view: NSView) {
        guard let window = view.window else { return }
        window.minSize = LayoutMetrics.minWindowSize
        window.title = "Agent Console"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.styleMask.remove(.fullSizeContentView)
        applyMiniwindowIcon(to: window)
        observeMiniaturizeIfNeeded(window)
        if !didConfigureWindow {
            window.setContentSize(LayoutMetrics.defaultContentSize)
        }
        didConfigureWindow = true
    }

    private func applyMiniwindowIcon(to window: NSWindow) {
        guard let icon = AppIconProvider.shared.miniwindowIconImage() else { return }
        window.miniwindowImage = icon
        window.dockTile.contentView = makeDockTileIconView(icon: icon, tileSize: window.dockTile.size)
        window.dockTile.display()
    }

    private func makeDockTileIconView(icon: NSImage, tileSize: NSSize) -> NSView {
        let size = NSSize(
            width: max(tileSize.width, 128),
            height: max(tileSize.height, 128)
        )
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = icon
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.clear.cgColor
        return imageView
    }

    private func observeMiniaturizeIfNeeded(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        guard miniwindowObserverTokens[id] == nil else { return }

        let willToken = NotificationCenter.default.addObserver(
            forName: NSWindow.willMiniaturizeNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            Task { @MainActor in
                guard let self, let window else { return }
                self.applyMiniwindowIcon(to: window)
            }
        }

        let didToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didMiniaturizeNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            Task { @MainActor in
                guard let self, let window else { return }
                self.applyMiniwindowIcon(to: window)
                try? await Task.sleep(nanoseconds: 120_000_000)
                self.applyMiniwindowIcon(to: window)
            }
        }

        miniwindowObserverTokens[id] = [willToken, didToken]
    }
}

struct GitBadge: View {
    let snapshot: GitSnapshot
    let language: AppLanguage

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
    }

    private var label: String {
        switch snapshot.state {
        case .clean:
            return language == .zhHans ? "干净" : "Clean"
        case .dirty:
            return language == .zhHans ? "有改动" : "Dirty"
        case .unavailable:
            return language == .zhHans ? "无 Git" : "No Git"
        }
    }

    private var foreground: Color {
        switch snapshot.state {
        case .clean:
            return .green
        case .dirty:
            return .orange
        case .unavailable:
            return .secondary
        }
    }

    private var background: Color {
        switch snapshot.state {
        case .clean:
            return .green.opacity(0.14)
        case .dirty:
            return .orange.opacity(0.16)
        case .unavailable:
            return .secondary.opacity(0.12)
        }
    }
}

extension View {
    @ViewBuilder
    func disabledWithReason(_ reason: String?, fallbackHelp: String? = nil) -> some View {
        if let reason {
            self
                .disabled(true)
                .help(reason)
        } else if let fallbackHelp {
            self
                .disabled(false)
                .help(fallbackHelp)
        } else {
            self
        }
    }

    @ViewBuilder
    func hideSystemSidebarToggle(_ hidden: Bool) -> some View {
        if hidden {
            self.toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}

private struct ToolbarSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.subheadline.weight(.medium))
                .frame(minWidth: 160)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 140, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.subtleFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.controlBorder)
        )
    }
}

private struct ToolbarIcon: View {
    let systemName: String

    var body: some View {
        Text("")
            .frame(width: 18, height: 18)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
            }
            .accessibilityHidden(true)
    }
}

private struct ToolbarGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(configuration.isPressed ? AppTheme.controlForegroundPressed : AppTheme.controlForeground)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? AppTheme.controlFillPressed : AppTheme.controlFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(configuration.isPressed ? AppTheme.controlBorderPressed : AppTheme.controlBorder)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct TopBarTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .foregroundStyle(configuration.isPressed ? AppTheme.controlForegroundPressed : AppTheme.controlForeground)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? AppTheme.controlFillPressed : AppTheme.controlFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(configuration.isPressed ? AppTheme.controlBorderPressed : AppTheme.controlBorder)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct SidebarToolButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(configuration.isPressed ? AppTheme.controlForegroundPressed : AppTheme.controlForeground)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? AppTheme.controlFillPressed : AppTheme.controlFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(configuration.isPressed ? AppTheme.controlBorderPressed : AppTheme.controlBorder)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct SidebarHandleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? AppTheme.controlForegroundPressed : AppTheme.controlForeground)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? AppTheme.controlFillPressed : AppTheme.controlFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(configuration.isPressed ? AppTheme.controlBorderPressed : AppTheme.controlBorder)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct BadgeLabel: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.controlForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.18), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(tint.opacity(0.30))
            )
    }
}

struct DetailChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.cellFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppTheme.border)
        )
    }
}

struct SurfacePanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.panelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.border)
        )
    }
}

struct InfoCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.medium))
                .textSelection(.enabled)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.cellFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppTheme.border)
        )
    }
}

struct FirstRunEmptyStateView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let strings = appState.strings
        let title = appState.appLanguage == .zhHans ? "Agent Console 尚未导入项目" : "Agent Console hasn't imported any projects yet"
        let subtitle = appState.appLanguage == .zhHans
            ? "导入你的第一个项目文件夹来开始管理交接会话。"
            : "Import your first project folder to start managing handoff sessions."
        VStack(spacing: 18) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }

            Button {
                appState.importSingleProject()
            } label: {
                Label(strings.importProject, systemImage: "square.and.arrow.down")
            }
            .buttonStyle(ToolbarGlassButtonStyle())
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(32)
    }
}

struct DiagnosticsPanel: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let strings = appState.strings
        VStack(alignment: .leading, spacing: 8) {
            Text(strings.diagnostics)
                .font(.headline)

            diagnosticRow(appState.appLanguage == .zhHans ? "最近加载时间" : "Last Load", value: appState.diagnostics.lastScanAt.map(formattedDate) ?? strings.noScansYet)
            diagnosticRow(appState.appLanguage == .zhHans ? "自动交接（文件监听）" : "Auto Handoff (File Watch)", value: appState.autoSyncHandoffEnabled ? (appState.appLanguage == .zhHans ? "开启" : "On") : (appState.appLanguage == .zhHans ? "关闭" : "Off"))
            diagnosticRow(appState.appLanguage == .zhHans ? "最近 handoff 同步" : "Last Handoff Sync", value: appState.lastHandoffSyncDescription)
            diagnosticRow(appState.appLanguage == .zhHans ? "候选目录数量" : "Candidate Directories", value: "\(appState.diagnostics.candidateDirectoryCount)")
            diagnosticRow(appState.appLanguage == .zhHans ? "识别项目数量 (X)" : "Identified Projects (X)", value: "\(appState.diagnostics.identifiedProjectCount)")
            diagnosticRow(appState.appLanguage == .zhHans ? "候选目录数量" : "Candidate Directories", value: "\(appState.diagnostics.candidateDirectoryCount)")
            diagnosticRow(appState.appLanguage == .zhHans ? "跳过目录数量" : "Skipped Directories", value: "\(appState.diagnostics.skippedDirectoryCount)")
            diagnosticRow(appState.appLanguage == .zhHans ? "结果收敛保护" : "Overflow Protection", value: appState.diagnostics.overflowProtectionApplied ? (appState.appLanguage == .zhHans ? "已启用" : "Applied") : (appState.appLanguage == .zhHans ? "未触发" : "Not Needed"))
            diagnosticRow(appState.appLanguage == .zhHans ? "当前 active project" : "Current Active Project", value: appState.selectedProject?.metadata.path ?? strings.none)
            diagnosticRow(appState.appLanguage == .zhHans ? "当前 active session" : "Current Active Session", value: appState.selectedSession?.metadata.id ?? strings.none)
            diagnosticRow(appState.appLanguage == .zhHans ? "当前 handoff 路径" : "Current Handoff Path", value: appState.handoffPath)
            diagnosticRow(appState.appLanguage == .zhHans ? "当前 session 文件夹" : "Current Session Folder", value: appState.activeHandoffFilePath)
            diagnosticRow(appState.appLanguage == .zhHans ? "实际运行产物" : "Running Executable", value: appState.appRuntimeInfo)
            diagnosticRow(appState.appLanguage == .zhHans ? "推荐启动脚本" : "Recommended Launcher", value: appState.launcherScriptPath.isEmpty ? (appState.appLanguage == .zhHans ? "未在项目源码中找到" : "Not found in project source") : appState.launcherScriptPath)
            diagnosticRow(appState.appLanguage == .zhHans ? "最近错误摘要" : "Recent Error Summary", value: appState.diagnostics.lastErrorMessage.map { shortError($0) } ?? strings.none)
            diagnosticRow(appState.appLanguage == .zhHans ? "详细错误" : "Detailed Error", value: appState.diagnostics.lastErrorMessage ?? strings.none)
        }
        .font(.caption)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.panelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppTheme.border)
        )
    }

    private func diagnosticRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        localizedDateTime(date, language: appState.appLanguage)
    }

    private func shortError(_ error: String) -> String {
        let maxLength = 90
        guard error.count > maxLength else { return error }
        return "\(error.prefix(maxLength - 1))…"
    }
}

private func pageHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        Text(title)
            .font(.system(size: 25, weight: .semibold))
        Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

func formatTokenCount(_ value: Int) -> String {
    if value < 1_000 {
        return "\(value)"
    }

    let divisor = value < 1_000_000 ? 1_000.0 : 1_000_000.0
    let suffix = value < 1_000_000 ? "K" : "M"
    let number = Double(value) / divisor
    let formatted = String(format: "%.1f", number)
        .replacingOccurrences(of: ".0", with: "")
    return "\(formatted)\(suffix)"
}
