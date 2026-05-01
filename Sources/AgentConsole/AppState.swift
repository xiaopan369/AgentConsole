import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var registry: ProjectRegistry
    @Published private(set) var projects: [ProjectSummary] = []
    @Published private(set) var diagnostics: ScanDiagnostics = .empty
    @Published var appLanguage: AppLanguage
    @Published var selectedProjectPath: String?
    @Published var selectedSessionID: String?
    @Published var selectedDocument: HandoffDocumentType = .currentState
    @Published var documentDrafts: [HandoffDocumentType: String] = [:]
    @Published var receiptDraft: String = ""
    @Published var generatedPrompt: String = ""
    @Published var generatedPromptTitle: String = ""
    @Published var promptPreviousAgent: AgentKind = .unknown
    @Published var promptTargetAgent: AgentKind = .claude
    @Published var searchText: String = ""
    @Published var selectedConsolePage: ConsolePage = .handoff
    @Published var sessionRenameDraft: String = ""
    @Published var selectedPromptTemplateSlot: PromptTemplateSlot = .codexToClaudeZH
    @Published var promptTemplateDrafts: [PromptTemplateSlot: String] = [:]
    @Published var selectedUsageRange: UsageRange = .today
    @Published var customUsageStartDate: Date
    @Published var customUsageEndDate: Date
    @Published var sessionArchiveFilter: SessionArchiveFilter = .active
    @Published var isScanning: Bool = false
    @Published var statusMessage: String

    private let store = AgentWorkspaceStore()
    private let handoffWatcher = HandoffFileWatcher()
    private var didLoad = false
    private var autoReloadEnabled = true
    private var isAutoSyncing = false
    private var keepLastGeneratedPrompt = false

    var strings: AppStrings {
        AppStrings(language: appLanguage)
    }

    init() {
        let initialRegistry: ProjectRegistry
        let initialStatus: String
        do {
            initialRegistry = try store.loadRegistry()
            initialStatus = AppStrings(language: initialRegistry.appLanguage).ready
        } catch {
            initialRegistry = ProjectRegistry.default(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
            initialStatus = "已创建新的 AgentWorkspace 注册表。"
        }
        registry = initialRegistry
        appLanguage = initialRegistry.appLanguage
        statusMessage = initialStatus
        let defaultStartDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        customUsageStartDate = initialRegistry.usageWorkspace.customStartDate ?? defaultStartDate
        customUsageEndDate = initialRegistry.usageWorkspace.customEndDate ?? Date()
        registry.scanRoots = store.normalizeScanRoots(registry.scanRoots)
        promptTemplateDrafts = Dictionary(uniqueKeysWithValues: PromptTemplateSlot.allCases.map { ($0, registry.promptTemplates.value(for: $0)) })
        selectedUsageRange = registry.usageWorkspace.selectedRange
        sessionArchiveFilter = registry.sessionArchiveFilter
        selectedProjectPath = registry.selectedProjectPath
        selectedSessionID = registry.selectedSessionID
        diagnostics = ScanDiagnostics(
            scanRootCount: activeScanRoots.count,
            lastScanAt: registry.lastScanAt,
            candidateDirectoryCount: 0,
            identifiedProjectCount: registry.knownProjects.count,
            skippedDirectoryCount: 0,
            filteredNonProjectCount: 0,
            overflowProtectionApplied: false,
            lastErrorMessage: nil
        )
        try? persistRegistry()
    }

    var activeScanRoots: [ScanRoot] {
        registry.scanRoots.filter { store.pathExists($0.path) }
    }

    var unavailableCustomScanRoots: [ScanRoot] {
        registry.scanRoots.filter { !$0.isDefault && !store.pathExists($0.path) }
    }

    var suggestedScanRootPaths: [String] {
        let activePaths = Set(registry.scanRoots.map(\.path))
        return store.suggestedScanRootPaths().filter { !activePaths.contains($0) }
    }

    var filteredProjects: [ProjectSummary] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return projects }
        let query = searchText.lowercased()
        return projects.filter { project in
            project.metadata.name.lowercased().contains(query) || project.metadata.path.lowercased().contains(query)
        }
    }

    var selectedProject: ProjectSummary? {
        guard let selectedProjectPath else { return nil }
        return projects.first(where: { $0.metadata.path == selectedProjectPath })
    }

    var selectedSession: SessionBundle? {
        guard let selectedSessionID, let selectedProject else { return nil }
        return selectedProject.sessions.first(where: { $0.metadata.id == selectedSessionID })
    }

    var visibleSessions: [SessionBundle] {
        guard let selectedProject else { return [] }
        return selectedProject.sessions.filter { !$0.metadata.isArchived }
    }

    var archivedSessions: [SessionBundle] {
        guard let selectedProject else { return [] }
        return selectedProject.sessions.filter { $0.metadata.isArchived }
    }

    var filteredSessionsForArchiveFilter: [SessionBundle] {
        guard let selectedProject else { return [] }
        switch sessionArchiveFilter {
        case .active:
            return selectedProject.sessions.filter { !$0.metadata.isArchived }
        case .archived:
            return selectedProject.sessions.filter { $0.metadata.isArchived }
        case .all:
            return selectedProject.sessions
        }
    }

    var workspacePath: String {
        store.workspaceDirectoryPath()
    }

    var handoffPath: String {
        guard let selectedProject else { return strings.none }
        return HandoffPaths(projectURL: URL(fileURLWithPath: selectedProject.metadata.path)).handoffDir.path
    }

    var activeHandoffFilePath: String {
        guard let selectedSession else { return strings.none }
        return selectedSession.folderPath
    }

    var appBuildInfo: String {
        store.appBuildInfo()
    }

    var appRuntimeInfo: String {
        store.appRuntimeInfo()
    }

    var launcherScriptPath: String {
        store.launcherScriptPath()
    }

    var usageWorkspace: UsageWorkspace {
        registry.usageWorkspace
    }

    var autoSyncHandoffEnabled: Bool {
        registry.autoSyncHandoff
    }

    var lastHandoffSyncDescription: String {
        let time = registry.lastHandoffSyncAt.map { store.displayDate($0, language: appLanguage) } ?? strings.none
        guard let summary = lastHandoffSyncDisplaySummary else { return time }
        return "\(time) · \(summary)"
    }

    var lastHandoffSyncDisplaySummary: String? {
        guard let summary = registry.lastHandoffSyncSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty else {
            return nil
        }

        let lowercaseSummary = summary.lowercased()
        if summary.contains("低频捕获") || lowercaseSummary.contains("low-frequency") {
            return appLanguage == .zhHans ? "切换或一键更新时刷新" : "Refreshes on switch or manual update"
        }

        return summary
    }

    var lastHandoffSyncCompactDescription: String {
        guard let date = registry.lastHandoffSyncAt else { return strings.none }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: appLanguage == .zhHans ? "zh_Hans_CN" : "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    var handoffUpdateStatusDescription: String {
        if registry.lastHandoffSyncAt == nil {
            return appLanguage == .zhHans ? "未更新" : "Not updated"
        }
        return appLanguage == .zhHans ? "已更新" : "Updated"
    }

    var filteredUsageTokenRecords: [TokenUsageRecord] {
        if selectedUsageRange == .custom {
            return customFilteredTokenRecords
        }
        return store.filteredTokenRecords(registry.usageWorkspace.tokenRecords, range: selectedUsageRange)
    }

    private var customFilteredTokenRecords: [TokenUsageRecord] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: customUsageStartDate)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customUsageEndDate)) ?? customUsageEndDate
        return registry.usageWorkspace.tokenRecords.filter { record in
            record.createdAt >= start && record.createdAt < end
        }
    }

    var hasProjectSelection: Bool {
        selectedProject != nil
    }

    var hasSessionSelection: Bool {
        selectedSession != nil
    }

    var newSessionDisabledReason: String? {
        hasProjectSelection ? nil : strings.selectProjectFirst
    }

    var switchAgentDisabledReason: String? {
        hasSessionSelection ? nil : strings.selectSessionFirst
    }

    var refreshHandoffDisabledReason: String? {
        if !hasSessionSelection {
            return strings.selectSessionFirst
        }
        return hasUnsavedDocumentDrafts() ? strings.saveBeforeRefreshing : nil
    }

    var syncHandoffDisabledReason: String? {
        if !hasSessionSelection {
            return strings.selectSessionFirst
        }
        return hasUnsavedDocumentDrafts() ? strings.saveBeforeSyncing : nil
    }

    var copyPromptDisabledReason: String? {
        hasSessionSelection ? nil : strings.selectSessionFirst
    }

    var isSelectedSessionDefault: Bool {
        guard let session = selectedSession else { return false }
        let name = session.metadata.name.lowercased()
        return name == "default session" || name == "默认会话"
    }

    var deleteSessionDisabledReason: String? {
        if isSelectedSessionDefault {
            return appLanguage == .zhHans ? "Default Session 不可删除。" : "Default Session cannot be deleted."
        }
        return nil
    }

    var archiveSessionDisabledReason: String? {
        if isSelectedSessionDefault {
            return appLanguage == .zhHans ? "Default Session 不可归档。" : "Default Session cannot be archived."
        }
        return nil
    }

    var projectActionDisabledReason: String? {
        hasProjectSelection ? nil : strings.selectProjectFirst
    }

    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        loadImportedProjectsFromRegistry()
        startWatchingHandoff()
    }

    func loadImportedProjectsFromRegistry() {
        var loadedProjects: [ProjectSummary] = []

        if let path = selectedProjectPath ?? registry.selectedProjectPath,
           store.pathExists(path) {
            do {
                let summary = try store.loadProjectSummary(
                    at: URL(fileURLWithPath: path),
                    detectionReasons: ["manual import"],
                    language: appLanguage
                )
                loadedProjects.append(summary)
                selectedProjectPath = summary.metadata.path
            } catch {
                diagnostics.lastErrorMessage = error.localizedDescription
            }
        }

        projects = loadedProjects

        if let selectedProjectPath, projects.contains(where: { $0.metadata.path == selectedProjectPath }) {
            if let project = selectedProject {
                selectedSessionID = resolvedSessionID(for: project, preferredSessionID: selectedSessionID ?? project.metadata.activeSessionID)
            }
        } else {
            selectedProjectPath = nil
            selectedSessionID = nil
        }

        diagnostics.lastScanAt = Date()
        diagnostics.identifiedProjectCount = projects.count
        diagnostics.candidateDirectoryCount = projects.count
        loadDraftsFromSelection()
        refreshPromptPreview()
        try? persistRegistry()
        statusMessage = appLanguage == .zhHans
            ? "已加载手动导入的项目。切换 Agent 时会自动刷新上下文。"
            : "Loaded manually imported projects. Switching agents refreshes context automatically."
    }

    func scanProjects() async {
        await rescanProjects()
    }

    func rescanProjects() async {
        loadImportedProjectsFromRegistry()
        statusMessage = appLanguage == .zhHans
            ? "当前版本只加载手动导入项目，不执行项目扫描。"
            : "This version only loads manually imported projects and does not scan."
    }

    func selectProject(_ path: String?) {
        keepLastGeneratedPrompt = false
        selectedProjectPath = path
        let project = selectedProject
        selectedSessionID = resolvedSessionID(for: project, preferredSessionID: project?.metadata.activeSessionID)
        loadDraftsFromSelection()
        refreshPromptPreview()
        try? persistRegistry()
        startWatchingHandoff()
    }

    func selectSession(_ id: String?) {
        keepLastGeneratedPrompt = false
        guard let id, let project = selectedProject else {
            selectedSessionID = id
            loadDraftsFromSelection()
            refreshPromptPreview()
            try? persistRegistry()
            return
        }

        selectedSessionID = id
        do {
            try store.activateSession(projectPath: project.metadata.path, sessionID: id, language: appLanguage)
            try reloadProject(path: project.metadata.path, preferredSessionID: id)
            startWatchingHandoff()
            _ = autoSyncSelectedHandoff(reason: appLanguage == .zhHans ? "切换 active session" : "Active session changed")
        } catch {
            loadDraftsFromSelection()
            refreshPromptPreview()
            statusMessage = appLanguage == .zhHans ? "切换活动会话失败：\(error.localizedDescription)" : "Failed to activate the session: \(error.localizedDescription)"
            try? persistRegistry()
        }
    }

    func createSession() {
        guard let project = selectedProject else {
            statusMessage = appLanguage == .zhHans ? "请先选择项目，再创建会话。" : "Select a project before creating a session."
            return
        }

        do {
            _ = try store.createSession(projectPath: project.metadata.path, language: appLanguage)
            try reloadProject(path: project.metadata.path, preferredSessionID: nil)
            let autoSynced = autoSyncSelectedHandoff(reason: appLanguage == .zhHans ? "创建会话" : "Session created")
            statusMessage = appendAutoSyncStatus(
                to: appLanguage == .zhHans ? "已为 \(project.metadata.name) 创建新会话。" : "Created a new session for \(project.metadata.name).",
                autoSynced: autoSynced
            )
        } catch {
            statusMessage = appLanguage == .zhHans ? "创建会话失败：\(error.localizedDescription)" : "Failed to create session: \(error.localizedDescription)"
        }
    }

    func refreshGitStatus() {
        guard let project = selectedProject else { return }
        do {
            try reloadProject(path: project.metadata.path, preferredSessionID: selectedSessionID)
            let summary = selectedProject?.gitSnapshot.summary(for: appLanguage) ?? strings.unknown
            if selectedProject?.gitSnapshot.state == .unavailable {
                statusMessage = appLanguage == .zhHans ? "当前项目不是 Git 仓库。" : "The selected project is not a Git repository."
            } else {
                statusMessage = appLanguage == .zhHans ? "已刷新 Git 状态：\(summary)" : "Git status refreshed: \(summary)"
            }
        } catch {
            statusMessage = appLanguage == .zhHans ? "刷新 Git 状态失败：\(error.localizedDescription)" : "Failed to refresh Git status: \(error.localizedDescription)"
        }
    }

    func saveCurrentSession() {
        guard let project = selectedProject, var session = selectedSession else {
            statusMessage = appLanguage == .zhHans ? "请先选择会话，再保存。" : "Select a session before saving."
            return
        }

        session.documents = mergedDocuments(for: session)
        do {
            try store.saveSession(projectPath: project.metadata.path, session: session, language: appLanguage)
            try reloadProject(path: project.metadata.path, preferredSessionID: session.metadata.id)
            statusMessage = appLanguage == .zhHans ? "已保存交接文件。" : "Handoff files saved."
        } catch {
            statusMessage = appLanguage == .zhHans ? "保存失败：\(error.localizedDescription)" : "Save failed: \(error.localizedDescription)"
        }
    }

    func switchToAgent(_ targetAgent: AgentKind) {
        keepLastGeneratedPrompt = false
        guard targetAgent != .unknown else { return }
        guard let projectPath = selectedProjectPath, let currentSessionID = selectedSessionID else {
            statusMessage = appLanguage == .zhHans ? "请先选择项目和会话，再切换 Agent。" : "Select a project and session before switching agents."
            return
        }

        do {
            if let project = selectedProject, var session = selectedSession {
                session.documents = mergedDocuments(for: session)
                try store.saveSession(projectPath: project.metadata.path, session: session, language: appLanguage, makeActive: true)
            }

            try reloadProject(path: projectPath, preferredSessionID: currentSessionID)
            guard let project = selectedProject, var sourceSession = selectedSession else {
                throw StoreError.missingSession
            }

            sourceSession.documents = mergedDocuments(for: sourceSession)
            if sourceSession.metadata.currentAgent == .unknown {
                sourceSession.metadata.currentAgent = suggestedSourceAgent(for: targetAgent)
            }

            let direction = "\(sourceSession.metadata.currentAgent.rawValue) → \(targetAgent.rawValue)"
            sourceSession = store.syncSessionHandoff(
                project: project,
                session: sourceSession,
                language: appLanguage,
                promptDirection: direction,
                includeChangelog: true
            )

            let prompt = store.generatePrompt(project: project, session: sourceSession, targetAgent: targetAgent, language: appLanguage, templates: registry.promptTemplates)
            try store.persistPrompt(projectPath: project.metadata.path, sessionID: sourceSession.metadata.id, prompt: prompt)
            store.copyPromptToPasteboard(prompt.body)

            var updatedSession = sourceSession
            let handoffRequestedAt = Date()
            updatedSession.metadata.currentAgent = targetAgent
            updatedSession.metadata.handoffReceiptStatus = .pending
            updatedSession.metadata.lastHandoffReceiptText = nil
            updatedSession.metadata.lastHandoffReceiptAt = nil
            updatedSession.metadata.lastHandoffRequestedAt = handoffRequestedAt
            updatedSession = store.syncSessionHandoff(
                project: project,
                session: updatedSession,
                language: appLanguage,
                promptDirection: direction,
                includeChangelog: false
            )
            try store.saveSession(projectPath: project.metadata.path, session: updatedSession, language: appLanguage, makeActive: true)
            try reloadProject(path: project.metadata.path, preferredSessionID: sourceSession.metadata.id)
            registry.lastHandoffSyncAt = Date()
            registry.lastHandoffSyncSummary = appLanguage == .zhHans ? "切换 Agent 前自动刷新交接文件" : "Refreshed handoff before agent switch"
            try? persistRegistry()
            applyGeneratedPrompt(prompt)
            keepLastGeneratedPrompt = true
            receiptDraft = ""
            statusMessage = appLanguage == .zhHans
                ? "已刷新项目内容和交接记录，并复制 \(prompt.title) 续接提示词。"
                : "Refreshed project context and handoff records, then copied the \(prompt.title) continuation prompt."
        } catch {
            statusMessage = appLanguage == .zhHans ? "切换失败：\(error.localizedDescription)" : "Agent switch failed: \(error.localizedDescription)"
        }
    }

    func copyPrompt() {
        if generatedPrompt.isEmpty {
            refreshPromptPreview()
        }
        guard !generatedPrompt.isEmpty else {
            statusMessage = appLanguage == .zhHans ? "当前还没有可复制的提示词。" : "There is no prompt to copy yet."
            return
        }
        store.copyPromptToPasteboard(generatedPrompt)
        statusMessage = appLanguage == .zhHans ? "已复制提示词到剪贴板。" : "Prompt copied to the clipboard."
    }

    func updateSelectedSessionAgent(_ agent: AgentKind) {
        keepLastGeneratedPrompt = false
        mutateSelectedSession { session in
            session.metadata.currentAgent = agent
        }
    }

    func updateSelectedCodexQuota(_ status: QuotaStatus) {
        mutateSelectedSession { session in
            session.metadata.codexQuotaStatus = status
        }
    }

    func updateSelectedClaudeQuota(_ status: QuotaStatus) {
        mutateSelectedSession { session in
            session.metadata.claudeQuotaStatus = status
        }
    }

    func updateDraft(_ text: String, for type: HandoffDocumentType) {
        documentDrafts[type] = text
    }

    func refreshPromptPreview() {
        if keepLastGeneratedPrompt, !generatedPrompt.isEmpty {
            return
        }
        guard let project = selectedProject, let session = selectedSession else {
            generatedPrompt = ""
            generatedPromptTitle = ""
            promptPreviousAgent = .unknown
            promptTargetAgent = .unknown
            return
        }

        let targetAgent = suggestedTargetAgent(from: session.metadata.currentAgent)
        var metadata = session.metadata
        if metadata.currentAgent == .unknown {
            metadata.currentAgent = suggestedSourceAgent(for: targetAgent)
        }
        let hydratedSession = SessionBundle(metadata: metadata, folderPath: session.folderPath, documents: mergedDocuments(for: session))
        let prompt = store.generatePrompt(project: project, session: hydratedSession, targetAgent: targetAgent, language: appLanguage, templates: registry.promptTemplates)
        applyGeneratedPrompt(prompt)
    }

    func changeLanguage(_ language: AppLanguage) {
        guard appLanguage != language else { return }
        appLanguage = language
        registry.appLanguage = language
        do {
            if let selectedProjectPath {
                try reloadProject(path: selectedProjectPath, preferredSessionID: selectedSessionID)
            } else {
                refreshPromptPreview()
                try persistRegistry()
            }
            statusMessage = language == .zhHans ? "界面语言已切换为中文。" : "App language switched to English."
        } catch {
            statusMessage = language == .zhHans ? "切换语言失败：\(error.localizedDescription)" : "Failed to switch language: \(error.localizedDescription)"
        }
    }

    func refreshCurrentHandoff() {
        guard let project = selectedProject, let session = selectedSession else {
            statusMessage = appLanguage == .zhHans ? "请先选择会话，再刷新交接文件。" : "Select a session before refreshing handoff files."
            return
        }
        guard !hasUnsavedDocumentDrafts() else {
            statusMessage = strings.refreshBlockedUnsaved
            return
        }

        do {
            try reloadProject(path: project.metadata.path, preferredSessionID: session.metadata.id)
            statusMessage = appLanguage == .zhHans ? "已刷新当前交接文件。" : "Current handoff files refreshed."
        } catch {
            statusMessage = appLanguage == .zhHans ? "刷新交接文件失败：\(error.localizedDescription)" : "Failed to refresh handoff files: \(error.localizedDescription)"
        }
    }

    func syncCurrentStateToHandoff() {
        guard let project = selectedProject, let session = selectedSession else {
            statusMessage = appLanguage == .zhHans ? "请先选择会话，再同步交接文件。" : "Select a session before syncing handoff files."
            return
        }
        guard !hasUnsavedDocumentDrafts() else {
            statusMessage = strings.syncBlockedUnsaved
            return
        }

        let promptDirection = generatedPromptTitle.isEmpty ? "\(session.metadata.currentAgent.rawValue) → \(suggestedTargetAgent(from: session.metadata.currentAgent).rawValue)" : generatedPromptTitle
        let syncedSession = store.syncSessionHandoff(
            project: project,
            session: session,
            language: appLanguage,
            promptDirection: promptDirection,
            autoDetectReceipt: true
        )
        let receiptAutoDetected = didAutoDetectReceipt(previous: session, current: syncedSession)

        do {
            try store.saveSession(projectPath: project.metadata.path, session: syncedSession, language: appLanguage)
            registry.lastHandoffSyncAt = Date()
            registry.lastHandoffSyncSummary = appLanguage == .zhHans ? "一键更新交接文件" : "Updated handoff files"
            try reloadProject(path: project.metadata.path, preferredSessionID: syncedSession.metadata.id)
            statusMessage = appendReceiptDetectionStatus(to: strings.syncedToHandoff, detected: receiptAutoDetected)
        } catch {
            statusMessage = appLanguage == .zhHans ? "同步交接文件失败：\(error.localizedDescription)" : "Failed to sync the handoff files: \(error.localizedDescription)"
        }
    }

    func saveReceiptDraft() {
        guard var session = selectedSession else {
            statusMessage = appLanguage == .zhHans ? "请先选择会话，再保存回执。" : "Select a session before saving a receipt."
            return
        }

        let trimmed = receiptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        session.metadata.lastHandoffReceiptText = trimmed.isEmpty ? nil : receiptDraft
        session.metadata.lastHandoffReceiptAt = trimmed.isEmpty ? nil : Date()
        session.metadata.handoffReceiptStatus = trimmed.isEmpty ? .pending : HandoffReceiptParser.detectStatus(in: receiptDraft)
        persistSelectedSession(session, successMessage: session.metadata.handoffReceiptStatus == .confirmed ? strings.autoDetectedReceipt : strings.receiptUpdated)
    }

    func renameSelectedSession() {
        guard let project = selectedProject, let session = selectedSession else { return }
        let trimmed = sessionRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = appLanguage == .zhHans ? "会话名称不能为空。" : "Session name cannot be empty."
            return
        }
        do {
            try store.renameSession(projectPath: project.metadata.path, sessionID: session.metadata.id, newName: trimmed, language: appLanguage)
            try reloadProject(path: project.metadata.path, preferredSessionID: session.metadata.id)
            let autoSynced = autoSyncSelectedHandoff(reason: appLanguage == .zhHans ? "重命名会话" : "Session renamed")
            statusMessage = appendAutoSyncStatus(
                to: appLanguage == .zhHans ? "已重命名会话。" : "Session renamed.",
                autoSynced: autoSynced
            )
        } catch {
            statusMessage = appLanguage == .zhHans ? "重命名会话失败：\(error.localizedDescription)" : "Failed to rename session: \(error.localizedDescription)"
        }
    }

    func archiveSelectedSession() {
        setSelectedSessionArchived(true)
    }

    func restoreSelectedSession() {
        setSelectedSessionArchived(false)
    }

    func markSelectedSessionPrimary() {
        guard let project = selectedProject, let session = selectedSession else { return }
        do {
            try store.markPrimarySession(projectPath: project.metadata.path, sessionID: session.metadata.id, language: appLanguage)
            try reloadProject(path: project.metadata.path, preferredSessionID: session.metadata.id)
            let autoSynced = autoSyncSelectedHandoff(reason: appLanguage == .zhHans ? "标记主会话" : "Primary session marked")
            statusMessage = appendAutoSyncStatus(
                to: appLanguage == .zhHans ? "已标记为主会话。" : "Marked as primary session.",
                autoSynced: autoSynced
            )
        } catch {
            statusMessage = appLanguage == .zhHans ? "标记主会话失败：\(error.localizedDescription)" : "Failed to mark primary session: \(error.localizedDescription)"
        }
    }

    func duplicateSelectedSession() {
        guard let project = selectedProject, let session = selectedSession else { return }
        do {
            let copy = try store.duplicateSession(projectPath: project.metadata.path, sessionID: session.metadata.id, language: appLanguage)
            try reloadProject(path: project.metadata.path, preferredSessionID: copy.metadata.id)
            let autoSynced = autoSyncSelectedHandoff(reason: appLanguage == .zhHans ? "复制 / 派生会话" : "Session duplicated")
            statusMessage = appendAutoSyncStatus(
                to: appLanguage == .zhHans ? "已复制 / 派生会话。" : "Session duplicated.",
                autoSynced: autoSynced
            )
        } catch {
            statusMessage = appLanguage == .zhHans ? "复制会话失败：\(error.localizedDescription)" : "Failed to duplicate session: \(error.localizedDescription)"
        }
    }

    func deleteSelectedSession() {
        guard let project = selectedProject, let session = selectedSession else { return }
        do {
            let fallbackID = try store.deleteSession(projectPath: project.metadata.path, sessionID: session.metadata.id, language: appLanguage)
            try reloadProject(path: project.metadata.path, preferredSessionID: fallbackID)
            let autoSynced = autoSyncSelectedHandoff(reason: appLanguage == .zhHans ? "删除会话后切换回可用会话" : "Session deleted and fallback selected")
            statusMessage = appendAutoSyncStatus(
                to: appLanguage == .zhHans ? "已删除会话，仅移除 handoff session 文件夹。" : "Session deleted; only the handoff session folder was removed.",
                autoSynced: autoSynced
            )
        } catch {
            statusMessage = appLanguage == .zhHans ? "删除会话失败：\(error.localizedDescription)" : "Failed to delete session: \(error.localizedDescription)"
        }
    }

    func cleanupTestSessions() {
        guard let project = selectedProject else { return }
        do {
            let count = try store.cleanupTestSessions(projectPath: project.metadata.path, language: appLanguage)
            try reloadProject(path: project.metadata.path, preferredSessionID: selectedSessionID)
            let autoSynced = autoSyncSelectedHandoff(reason: appLanguage == .zhHans ? "清理测试会话" : "Test sessions cleaned up")
            statusMessage = appendAutoSyncStatus(
                to: appLanguage == .zhHans ? "已清理 \(count) 个测试会话。" : "Cleaned up \(count) test sessions.",
                autoSynced: autoSynced
            )
        } catch {
            statusMessage = appLanguage == .zhHans ? "清理测试会话失败：\(error.localizedDescription)" : "Failed to clean up test sessions: \(error.localizedDescription)"
        }
    }

    func updatePromptTemplateDraft(_ text: String, for slot: PromptTemplateSlot) {
        promptTemplateDrafts[slot] = text
    }

    func savePromptTemplates() {
        var templates = registry.promptTemplates
        for slot in PromptTemplateSlot.allCases {
            templates.setValue(promptTemplateDrafts[slot] ?? "", for: slot)
        }
        registry.promptTemplates = templates
        do {
            refreshPromptPreview()
            try persistRegistry()
            statusMessage = appLanguage == .zhHans ? "已保存 Prompt 模板。" : "Prompt templates saved."
        } catch {
            statusMessage = appLanguage == .zhHans ? "保存 Prompt 模板失败：\(error.localizedDescription)" : "Failed to save prompt templates: \(error.localizedDescription)"
        }
    }

    func restoreDefaultPromptTemplate() {
        registry.promptTemplates.setValue(PromptTemplateSet.default.value(for: selectedPromptTemplateSlot), for: selectedPromptTemplateSlot)
        promptTemplateDrafts[selectedPromptTemplateSlot] = registry.promptTemplates.value(for: selectedPromptTemplateSlot)
        do {
            refreshPromptPreview()
            try persistRegistry()
            statusMessage = appLanguage == .zhHans ? "已恢复当前模板默认值。" : "Restored the selected template."
        } catch {
            statusMessage = appLanguage == .zhHans ? "恢复模板失败：\(error.localizedDescription)" : "Failed to restore template: \(error.localizedDescription)"
        }
    }

    func restoreAllDefaultPromptTemplates() {
        registry.promptTemplates = .default
        promptTemplateDrafts = Dictionary(uniqueKeysWithValues: PromptTemplateSlot.allCases.map { ($0, registry.promptTemplates.value(for: $0)) })
        do {
            refreshPromptPreview()
            try persistRegistry()
            statusMessage = appLanguage == .zhHans ? "已恢复全部默认模板。" : "Restored all default templates."
        } catch {
            statusMessage = appLanguage == .zhHans ? "恢复模板失败：\(error.localizedDescription)" : "Failed to restore templates: \(error.localizedDescription)"
        }
    }

    func changeUsageRange(_ range: UsageRange) {
        selectedUsageRange = range
        registry.usageWorkspace.selectedRange = range
        try? persistRegistry()
    }

    func updateCustomUsageRange(start: Date? = nil, end: Date? = nil) {
        if let start {
            customUsageStartDate = start
        }
        if let end {
            customUsageEndDate = end
        }
        if customUsageStartDate > customUsageEndDate {
            customUsageEndDate = customUsageStartDate
        }
        registry.usageWorkspace.customStartDate = customUsageStartDate
        registry.usageWorkspace.customEndDate = customUsageEndDate
        try? persistRegistry()
    }

    func changeSessionArchiveFilter(_ filter: SessionArchiveFilter) {
        sessionArchiveFilter = filter
        registry.sessionArchiveFilter = filter
        try? persistRegistry()
    }

    func refreshUsageSources() {
        statusMessage = appLanguage == .zhHans
            ? "当前版本不提供用量读取；只保留 Agent 切换续接工作流。"
            : "Usage reading is disabled in this version; only the agent handoff workflow remains."
    }

    func refreshUsageSourcesSync() {
        refreshUsageSources()
    }

    func setActiveUsageAccount(_ account: AccountSummary) {
        var workspace = registry.usageWorkspace
        workspace.accounts = workspace.accounts.map { existing in
            var copy = existing
            if existing.provider == account.provider {
                copy.isActive = existing.id == account.id
            }
            return copy
        }
        workspace.activeAccountIDsByProvider[account.provider.rawValue] = account.id
        registry.usageWorkspace = workspace
        do {
            try persistRegistry()
            statusMessage = appLanguage == .zhHans ? "已更新本地 active account 标记。" : "Updated the local active account marker."
        } catch {
            statusMessage = appLanguage == .zhHans ? "保存 active account 失败：\(error.localizedDescription)" : "Failed to save active account: \(error.localizedDescription)"
        }
    }

    func setAutoSyncHandoffEnabled(_ enabled: Bool) {
        registry.autoSyncHandoff = enabled
        setAutoReloadEnabled(enabled)
        do {
            try persistRegistry()
            statusMessage = enabled
                ? (appLanguage == .zhHans ? "已开启自动交接（文件监听）。" : "Auto-handoff enabled (file watch).")
                : (appLanguage == .zhHans ? "已关闭自动交接。" : "Auto-handoff disabled.")
        } catch {
            statusMessage = appLanguage == .zhHans ? "保存自动交接设置失败：\(error.localizedDescription)" : "Failed to save auto-handoff setting: \(error.localizedDescription)"
        }
    }

    func markReceiptConfirmed() {
        guard var session = selectedSession else { return }
        session.metadata.lastHandoffReceiptText = receiptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? session.metadata.lastHandoffReceiptText : receiptDraft
        session.metadata.lastHandoffReceiptAt = Date()
        session.metadata.handoffReceiptStatus = .confirmed
        persistSelectedSession(session, successMessage: strings.receiptUpdated)
    }

    func markReceiptFailed() {
        guard var session = selectedSession else { return }
        session.metadata.lastHandoffReceiptText = receiptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? session.metadata.lastHandoffReceiptText : receiptDraft
        session.metadata.lastHandoffReceiptAt = Date()
        session.metadata.handoffReceiptStatus = .failed
        persistSelectedSession(session, successMessage: strings.receiptUpdated)
    }

    func clearReceipt() {
        guard var session = selectedSession else { return }
        receiptDraft = ""
        session.metadata.lastHandoffReceiptText = nil
        session.metadata.lastHandoffReceiptAt = nil
        session.metadata.handoffReceiptStatus = .pending
        persistSelectedSession(session, successMessage: strings.receiptCleared)
    }

    func startWatchingHandoff() {
        guard let session = selectedSession else {
            handoffWatcher.stop()
            return
        }
        let sessionPath = session.folderPath
        handoffWatcher.startWatching(path: sessionPath) { [weak self] in
            Task { @MainActor [weak self] in
                self?.autoReloadFromDisk()
            }
        }
    }

    func stopWatchingHandoff() {
        handoffWatcher.stop()
    }

    func autoReloadFromDisk() {
        guard autoReloadEnabled, !isAutoSyncing, let project = selectedProject, let session = selectedSession else { return }
        isAutoSyncing = true
        do {
            try reloadProject(path: project.metadata.path, preferredSessionID: session.metadata.id)
        } catch {
            diagnostics.lastErrorMessage = error.localizedDescription
        }
        isAutoSyncing = false
    }

    func handleAppDidBecomeActive() {
        guard autoReloadEnabled, let project = selectedProject, let session = selectedSession else { return }
        do {
            try reloadProject(path: project.metadata.path, preferredSessionID: session.metadata.id)
            startWatchingHandoff()
        } catch {
            diagnostics.lastErrorMessage = error.localizedDescription
        }
    }

    func setAutoReloadEnabled(_ enabled: Bool) {
        autoReloadEnabled = enabled
        if enabled {
            startWatchingHandoff()
        } else {
            stopWatchingHandoff()
        }
    }

    func revealProjectInFinder() {
        guard let project = selectedProject else {
            statusMessage = appLanguage == .zhHans ? "请先选择项目。" : "Select a project first."
            return
        }
        store.revealInFinder(projectPath: project.metadata.path)
        statusMessage = appLanguage == .zhHans ? "已在 Finder 中打开项目。" : "Opened the project in Finder."
    }

    func importSingleProject() {
        guard let path = store.pickDirectory(prompt: strings.importProject) else { return }
        keepLastGeneratedPrompt = false

        do {
            let summary = try store.importProject(at: path, language: appLanguage)
            upsertProject(summary)
            upsertKnownProject(path: summary.metadata.path, name: summary.metadata.name)
            selectedProjectPath = summary.metadata.path
            selectedSessionID = summary.metadata.activeSessionID ?? summary.sessions.first?.metadata.id
            diagnostics.scanRootCount = registry.scanRoots.count
            diagnostics.lastScanAt = Date()
            diagnostics.candidateDirectoryCount = max(diagnostics.candidateDirectoryCount, 1)
            diagnostics.identifiedProjectCount = projects.count
            diagnostics.filteredNonProjectCount = max(diagnostics.filteredNonProjectCount, 0)
            diagnostics.overflowProtectionApplied = false
            diagnostics.lastErrorMessage = nil
            loadDraftsFromSelection()
            refreshPromptPreview()
            try persistRegistry()
            if let project = selectedProject, let session = selectedSession {
                let direction = "\(session.metadata.currentAgent.rawValue) → \(suggestedTargetAgent(from: session.metadata.currentAgent).rawValue)"
                let synced = store.syncSessionHandoff(
                    project: project,
                    session: session,
                    language: appLanguage,
                    promptDirection: direction,
                    includeChangelog: false
                )
                try store.saveSession(projectPath: project.metadata.path, session: synced, language: appLanguage, makeActive: true)
                try reloadProject(path: project.metadata.path, preferredSessionID: synced.metadata.id)
            }
            statusMessage = appLanguage == .zhHans
                ? "已导入项目，创建交接会话，并生成项目内容快照。"
                : "Imported the project, created the handoff session, and generated a project context snapshot."
        } catch {
            diagnostics.lastErrorMessage = error.localizedDescription
            statusMessage = appLanguage == .zhHans ? "导入项目失败：\(error.localizedDescription)" : "Project import failed: \(error.localizedDescription)"
        }
    }

    func addScanRoot() {
        guard let path = store.pickDirectory(prompt: strings.addDirectory) else { return }
        guard !registry.scanRoots.contains(where: { $0.path == path }) else {
            statusMessage = appLanguage == .zhHans ? "该文件夹已经在扫描列表中了。" : "That folder is already in the scan list."
            return
        }

        registry.scanRoots.append(ScanRoot(path: path, isDefault: false))
        do {
            try persistRegistry()
            statusMessage = appLanguage == .zhHans ? "已添加扫描目录：\(path)" : "Added scan root: \(path)"
            Task { await rescanProjects() }
        } catch {
            diagnostics.lastErrorMessage = error.localizedDescription
            statusMessage = appLanguage == .zhHans ? "保存扫描目录失败：\(error.localizedDescription)" : "Failed to save the scan root: \(error.localizedDescription)"
        }
    }

    func removeScanRoot(_ root: ScanRoot) {
        guard !root.isDefault else {
            statusMessage = appLanguage == .zhHans ? "这版 MVP 暂时保留默认扫描目录。" : "This MVP keeps the default scan roots for now."
            return
        }
        registry.scanRoots.removeAll(where: { $0.id == root.id })
        do {
            try persistRegistry()
            statusMessage = appLanguage == .zhHans ? "已移除扫描目录。" : "Removed the scan root."
            Task { await rescanProjects() }
        } catch {
            diagnostics.lastErrorMessage = error.localizedDescription
            statusMessage = appLanguage == .zhHans ? "更新扫描目录失败：\(error.localizedDescription)" : "Failed to update scan roots: \(error.localizedDescription)"
        }
    }

    func openScanRoot(_ root: ScanRoot) {
        guard FileManager.default.fileExists(atPath: root.path) else {
            statusMessage = root.isDefault
                ? (appLanguage == .zhHans ? "默认建议目录尚未创建。" : "The default suggested directory has not been created yet.")
                : (appLanguage == .zhHans ? "目录不存在：\(root.path)" : "Directory does not exist: \(root.path)")
            return
        }
        store.openDirectoryInFinder(root.path)
    }

    func openAgentWorkspace() {
        do {
            try store.ensureGlobalWorkspace()
            store.openDirectoryInFinder(store.workspaceDirectoryPath())
            statusMessage = appLanguage == .zhHans ? "已打开 AgentWorkspace。" : "Opened AgentWorkspace."
        } catch {
            statusMessage = appLanguage == .zhHans ? "打开 AgentWorkspace 失败：\(error.localizedDescription)" : "Failed to open AgentWorkspace: \(error.localizedDescription)"
        }
    }

    func openHandoffDirectory() {
        guard let project = selectedProject else {
            statusMessage = appLanguage == .zhHans ? "请先选择项目。" : "Select a project first."
            return
        }
        store.openDirectoryInFinder(HandoffPaths(projectURL: URL(fileURLWithPath: project.metadata.path)).handoffDir.path)
        statusMessage = appLanguage == .zhHans ? "已打开当前项目 .agent-handoff。" : "Opened the current project .agent-handoff folder."
    }

    func openCurrentSessionDirectory() {
        guard let session = selectedSession else {
            statusMessage = appLanguage == .zhHans ? "请先选择会话。" : "Select a session first."
            return
        }
        store.openDirectoryInFinder(session.folderPath)
        statusMessage = appLanguage == .zhHans ? "已打开当前 session 文件夹。" : "Opened the current session folder."
    }

    func createSuggestedRoot(_ path: String) {
        do {
            try store.createDirectoryIfNeeded(at: path)
            if !registry.scanRoots.contains(where: { $0.path == path }) {
                registry.scanRoots.append(ScanRoot(path: path, isDefault: true))
            }
            try persistRegistry()
            statusMessage = appLanguage == .zhHans ? "已创建默认目录：\(path)" : "Created the default directory: \(path)"
            Task { await rescanProjects() }
        } catch {
            diagnostics.lastErrorMessage = error.localizedDescription
            statusMessage = appLanguage == .zhHans ? "创建默认目录失败：\(error.localizedDescription)" : "Failed to create the default directory: \(error.localizedDescription)"
        }
    }

    private func mutateSelectedSession(_ mutation: (inout SessionBundle) -> Void) {
        guard let project = selectedProject, var session = selectedSession else { return }
        session.documents = mergedDocuments(for: session)
        mutation(&session)

        do {
            try store.saveSession(projectPath: project.metadata.path, session: session, language: appLanguage)
            try reloadProject(path: project.metadata.path, preferredSessionID: session.metadata.id)
            let autoSynced = autoSyncSelectedHandoff(reason: appLanguage == .zhHans ? "更新会话状态" : "Session state updated")
            statusMessage = appendAutoSyncStatus(
                to: appLanguage == .zhHans ? "会话已更新。" : "Session updated.",
                autoSynced: autoSynced
            )
        } catch {
            statusMessage = appLanguage == .zhHans ? "更新会话失败：\(error.localizedDescription)" : "Failed to update the session: \(error.localizedDescription)"
        }
    }

    private func setSelectedSessionArchived(_ archived: Bool) {
        guard let project = selectedProject, let session = selectedSession else { return }
        do {
            try store.archiveSession(projectPath: project.metadata.path, sessionID: session.metadata.id, archived: archived, language: appLanguage)
            let preferredID = archived ? nil : session.metadata.id
            try reloadProject(path: project.metadata.path, preferredSessionID: preferredID)
            let autoSynced = autoSyncSelectedHandoff(reason: archived
                ? (appLanguage == .zhHans ? "归档会话" : "Session archived")
                : (appLanguage == .zhHans ? "恢复归档会话" : "Session restored"))
            let message = archived
                ? (appLanguage == .zhHans ? "已归档会话。" : "Session archived.")
                : (appLanguage == .zhHans ? "已取消归档会话。" : "Session restored.")
            statusMessage = appendAutoSyncStatus(to: message, autoSynced: autoSynced)
        } catch {
            statusMessage = appLanguage == .zhHans ? "更新归档状态失败：\(error.localizedDescription)" : "Failed to update archive state: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func autoSyncSelectedHandoff(reason: String) -> Bool {
        guard registry.autoSyncHandoff, let project = selectedProject, let session = selectedSession else { return false }
        guard !hasUnsavedDocumentDrafts() else { return false }

        let promptDirection = generatedPromptTitle.isEmpty ? "\(session.metadata.currentAgent.rawValue) → \(suggestedTargetAgent(from: session.metadata.currentAgent).rawValue)" : generatedPromptTitle
        let syncedSession = store.syncSessionHandoff(
            project: project,
            session: session,
            language: appLanguage,
            promptDirection: promptDirection,
            includeChangelog: false,
            autoDetectReceipt: true
        )

        do {
            try store.writeSessionDocumentsOnly(projectPath: project.metadata.path, session: syncedSession)
            registry.lastHandoffSyncAt = Date()
            registry.lastHandoffSyncSummary = reason
            return true
        } catch {
            diagnostics.lastErrorMessage = error.localizedDescription
            return false
        }
    }

    private func appendAutoSyncStatus(to message: String, autoSynced: Bool) -> String {
        guard autoSynced else { return message }
        return message + (appLanguage == .zhHans ? " 交接快照已自动同步。" : " Handoff snapshot auto-synced.")
    }

    private func appendReceiptDetectionStatus(to message: String, detected: Bool) -> String {
        guard detected else { return message }
        return "\(message) \(strings.autoDetectedReceipt)"
    }

    private func didAutoDetectReceipt(previous: SessionBundle, current: SessionBundle) -> Bool {
        let newText = current.metadata.lastHandoffReceiptText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard current.metadata.handoffReceiptStatus != .pending, !newText.isEmpty else {
            return false
        }
        let oldText = previous.metadata.lastHandoffReceiptText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return current.metadata.handoffReceiptStatus != previous.metadata.handoffReceiptStatus
            || newText != oldText
            || current.metadata.lastHandoffReceiptAt != previous.metadata.lastHandoffReceiptAt
    }

    private func mergedDocuments(for session: SessionBundle) -> [HandoffDocumentType: String] {
        var documents = session.documents
        for type in HandoffDocumentType.allCases {
            documents[type] = documentDrafts[type] ?? session.documents[type] ?? ""
        }
        return documents
    }

    private func loadDraftsFromSelection() {
        guard let session = selectedSession else {
            documentDrafts = [:]
            receiptDraft = ""
            sessionRenameDraft = ""
            return
        }
        documentDrafts = session.documents
        receiptDraft = session.metadata.lastHandoffReceiptText ?? ""
        sessionRenameDraft = session.metadata.name
    }

    private func suggestedTargetAgent(from current: AgentKind) -> AgentKind {
        switch current {
        case .claude:
            return .codex
        case .codex, .unknown:
            return .claude
        }
    }

    private func suggestedSourceAgent(for target: AgentKind) -> AgentKind {
        switch target {
        case .claude:
            return .codex
        case .codex:
            return .claude
        case .unknown:
            return .unknown
        }
    }

    private func applyGeneratedPrompt(_ prompt: GeneratedPrompt) {
        generatedPrompt = prompt.body
        generatedPromptTitle = prompt.title
        promptPreviousAgent = prompt.previousAgent
        promptTargetAgent = prompt.targetAgent
    }

    private func reloadProject(path: String, preferredSessionID: String?) throws {
        let existing = projects.first(where: { $0.metadata.path == path })
        let summary = try store.loadProjectSummary(
            at: URL(fileURLWithPath: path),
            detectionReasons: existing?.detectionReasons ?? ["manual"],
            language: appLanguage
        )
        if let index = projects.firstIndex(where: { $0.metadata.path == path }) {
            projects[index] = summary
        } else {
            projects.append(summary)
            projects.sort(by: { $0.metadata.name.localizedCaseInsensitiveCompare($1.metadata.name) == .orderedAscending })
        }

        selectedProjectPath = path
        selectedSessionID = resolvedSessionID(for: summary, preferredSessionID: preferredSessionID ?? summary.metadata.activeSessionID)
        loadDraftsFromSelection()
        refreshPromptPreview()
        upsertKnownProject(path: summary.metadata.path, name: summary.metadata.name)
        try persistRegistry()
    }

    private func resolvedSessionID(for project: ProjectSummary?, preferredSessionID: String?) -> String? {
        guard let project else { return nil }
        if let preferredSessionID,
           project.sessions.contains(where: { $0.metadata.id == preferredSessionID }) {
            return preferredSessionID
        }
        return project.sessions.first?.metadata.id
    }

    private func upsertProject(_ summary: ProjectSummary) {
        if let index = projects.firstIndex(where: { $0.metadata.path == summary.metadata.path }) {
            projects[index] = summary
        } else {
            projects.append(summary)
            projects.sort(by: { $0.metadata.name.localizedCaseInsensitiveCompare($1.metadata.name) == .orderedAscending })
        }
    }

    private func upsertKnownProject(path: String, name: String) {
        let record = KnownProjectRecord(path: path, name: name, lastSeenAt: Date())
        if let index = registry.knownProjects.firstIndex(where: { $0.path == path }) {
            registry.knownProjects[index] = record
        } else {
            registry.knownProjects.append(record)
            registry.knownProjects.sort(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    private func mergeKnownProjects(from summaries: [ProjectSummary]) {
        for summary in summaries {
            upsertKnownProject(path: summary.metadata.path, name: summary.metadata.name)
        }
    }

    private func pruneKnownProjects(using summaries: [ProjectSummary]) {
        var keep = Set(summaries.map(\.metadata.path))
        if let selectedProjectPath {
            keep.insert(selectedProjectPath)
        }
        registry.knownProjects.removeAll(where: { !keep.contains($0.path) })
    }

    private func persistRegistry() throws {
        registry.selectedProjectPath = selectedProjectPath
        registry.selectedSessionID = selectedSessionID
        registry.appLanguage = appLanguage
        registry.sessionArchiveFilter = sessionArchiveFilter
        registry.usageWorkspace.selectedRange = selectedUsageRange
        registry.usageWorkspace.customStartDate = customUsageStartDate
        registry.usageWorkspace.customEndDate = customUsageEndDate
        diagnostics.scanRootCount = activeScanRoots.count
        try store.saveRegistry(registry)
    }

    private func persistSelectedSession(_ session: SessionBundle, successMessage: String) {
        guard let project = selectedProject else { return }
        do {
            try store.saveSession(projectPath: project.metadata.path, session: session, language: appLanguage)
            try reloadProject(path: project.metadata.path, preferredSessionID: session.metadata.id)
            let autoSynced = autoSyncSelectedHandoff(reason: appLanguage == .zhHans ? "更新交接回执" : "Handoff receipt updated")
            statusMessage = appendAutoSyncStatus(to: successMessage, autoSynced: autoSynced)
        } catch {
            statusMessage = appLanguage == .zhHans ? "保存回执失败：\(error.localizedDescription)" : "Failed to save the receipt: \(error.localizedDescription)"
        }
    }

    private func hasUnsavedDocumentDrafts() -> Bool {
        guard let session = selectedSession else { return false }
        return HandoffDocumentType.allCases.contains { type in
            let draft = documentDrafts[type] ?? ""
            let persisted = session.documents[type] ?? ""
            return draft != persisted
        }
    }
}
