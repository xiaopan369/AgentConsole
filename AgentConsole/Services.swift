import AppKit
import Foundation

struct AppPaths {
    let homeDirectory: URL
    let workspaceDirectory: URL
    let registryURL: URL
    let templatesDirectory: URL
    let logsDirectory: URL
    let cacheDirectory: URL

    init(fileManager: FileManager = .default) {
        let home = fileManager.homeDirectoryForCurrentUser
        let workspace = home.appending(path: "AgentWorkspace", directoryHint: .isDirectory)
        homeDirectory = home
        workspaceDirectory = workspace
        registryURL = workspace.appending(path: "ProjectRegistry.json")
        templatesDirectory = workspace.appending(path: "templates", directoryHint: .isDirectory)
        logsDirectory = workspace.appending(path: "logs", directoryHint: .isDirectory)
        cacheDirectory = workspace.appending(path: "cache", directoryHint: .isDirectory)
    }
}

struct HandoffPaths {
    let projectURL: URL
    let handoffDir: URL
    let projectJsonURL: URL
    let activeProjectURL: URL
    let activeSessionURL: URL
    let runtimeDir: URL
    let sessionsDir: URL

    init(projectURL: URL) {
        self.projectURL = projectURL
        handoffDir = projectURL.appendingPathComponent(".agent-handoff", isDirectory: true)
        projectJsonURL = handoffDir.appendingPathComponent("project.json", isDirectory: false)
        activeProjectURL = handoffDir.appendingPathComponent("ACTIVE_PROJECT.md", isDirectory: false)
        activeSessionURL = handoffDir.appendingPathComponent("ACTIVE_SESSION.md", isDirectory: false)
        runtimeDir = handoffDir.appendingPathComponent("runtime", isDirectory: true)
        sessionsDir = handoffDir.appendingPathComponent("sessions", isDirectory: true)
    }

    func sessionDir(_ sessionID: String) -> URL {
        sessionsDir.appendingPathComponent(sessionID, isDirectory: true)
    }

    func promptsDir(_ sessionID: String) -> URL {
        sessionDir(sessionID).appendingPathComponent("PROMPTS", isDirectory: true)
    }

    func sessionJsonURL(_ sessionID: String) -> URL {
        sessionDir(sessionID).appendingPathComponent("session.json", isDirectory: false)
    }

    func handoffMarkdownURL(_ sessionID: String, name: String) -> URL {
        sessionDir(sessionID).appendingPathComponent(name, isDirectory: false)
    }
}

struct DiscoveredProject {
    var url: URL
    var reasons: [String]
}

struct ScanDiagnostics: Sendable {
    var scanRootCount: Int
    var lastScanAt: Date?
    var candidateDirectoryCount: Int
    var identifiedProjectCount: Int
    var skippedDirectoryCount: Int
    var filteredNonProjectCount: Int
    var overflowProtectionApplied: Bool
    var lastErrorMessage: String?

    static let empty = ScanDiagnostics(
        scanRootCount: 0,
        lastScanAt: nil,
        candidateDirectoryCount: 0,
        identifiedProjectCount: 0,
        skippedDirectoryCount: 0,
        filteredNonProjectCount: 0,
        overflowProtectionApplied: false,
        lastErrorMessage: nil
    )
}

struct ProjectScanReport: Sendable {
    var summaries: [ProjectSummary]
    var diagnostics: ScanDiagnostics
}

private struct ProjectContextFile {
    var url: URL
    var relativePath: String
    var size: Int
    var priority: Int
    var includeExcerpt: Bool
}

private struct ConversationLogEntry {
    var agent: AgentKind
    var timestamp: Date
    var role: String
    var sourceFile: String
    var text: String
}

private struct DiscoveryReport {
    var discovered: [DiscoveredProject]
    var candidateDirectoryCount: Int
    var skippedDirectoryCount: Int
    var errors: [String]
}

enum StoreError: LocalizedError {
    case missingProject
    case missingSession
    case unsafeSessionDelete
    case importFailed(ImportFailureContext)

    var errorDescription: String? {
        switch self {
        case .missingProject:
            return "当前未选择项目。"
        case .missingSession:
            return "当前未选择会话。"
        case .unsafeSessionDelete:
            return "安全检查失败：只能删除当前项目 .agent-handoff/sessions 下的会话目录。"
        case let .importFailed(context):
            return """
            导入路径初始化失败
            selectedProjectURL: \(context.selectedProjectURL)
            handoffDir: \(context.handoffDir)
            activeProjectURL: \(context.activeProjectURL)
            activeSessionURL: \(context.activeSessionURL)
            sessionsDir: \(context.sessionsDir)
            sessionDir: \(context.sessionDir ?? "nil")
            swiftError: \(context.underlyingError)
            """
        }
    }
}

struct ImportFailureContext: Sendable {
    var selectedProjectURL: String
    var handoffDir: String
    var activeProjectURL: String
    var activeSessionURL: String
    var sessionsDir: String
    var sessionDir: String?
    var underlyingError: String
}

final class AgentWorkspaceStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let paths: AppPaths
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let gitService = GitService()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        paths = AppPaths(fileManager: fileManager)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func ensureGlobalWorkspace() throws {
        try fileManager.createDirectory(at: paths.workspaceDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.templatesDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.logsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.cacheDirectory, withIntermediateDirectories: true)
    }

    func loadRegistry() throws -> ProjectRegistry {
        try ensureGlobalWorkspace()

        if fileManager.fileExists(atPath: paths.registryURL.path) {
            let data = try Data(contentsOf: paths.registryURL)
            return try decoder.decode(ProjectRegistry.self, from: data)
        }

        let registry = ProjectRegistry.default(homeDirectory: paths.homeDirectory)
        try saveRegistry(registry)
        return registry
    }

    func saveRegistry(_ registry: ProjectRegistry) throws {
        try ensureGlobalWorkspace()
        let data = try encoder.encode(registry)
        try writeData(data, to: paths.registryURL)
    }

    func scanProjects(using scanRoots: [ScanRoot], knownProjectPaths: [String] = [], language: AppLanguage) throws -> ProjectScanReport {
        let focusedScanRoots = focusedAgentScanRoots(from: scanRoots)
        let knownProjectPathSet = Set(knownProjectPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        var discoveredByPath: [String: DiscoveredProject] = [:]
        var candidateDirectoryCount = 0
        var skippedDirectoryCount = 0
        var filteredNonProjectCount = 0
        var overflowProtectionApplied = false
        var errors: [String] = []

        for root in focusedScanRoots {
            let report = discoverProjects(in: root)
            candidateDirectoryCount += report.candidateDirectoryCount
            skippedDirectoryCount += report.skippedDirectoryCount
            errors.append(contentsOf: report.errors)

            for project in report.discovered {
                discoveredByPath[project.url.path] = project
            }
        }

        for path in knownProjectPaths {
            let url = URL(fileURLWithPath: path)
            guard shouldIncludeKnownProject(path: url.path, focusedRoots: focusedScanRoots.map(\.path)) else {
                skippedDirectoryCount += 1
                continue
            }
            guard fileManager.fileExists(atPath: url.path) else {
                skippedDirectoryCount += 1
                errors.append("项目不存在：\(path)")
                continue
            }

            candidateDirectoryCount += 1
            if discoveredByPath[url.path] == nil {
                let reasons = detectionReasons(for: url) ?? ["manual import"]
                discoveredByPath[url.path] = DiscoveredProject(url: url, reasons: reasons)
            }
        }

        var discoveredProjects = collapseNestedProjects(discoveredByPath.values.map { $0 }, knownProjectPaths: knownProjectPathSet)
        filteredNonProjectCount += max(0, discoveredByPath.count - discoveredProjects.count)
        if discoveredProjects.count > 50 {
            overflowProtectionApplied = true

            let strictProjects = discoveredProjects.filter { hasStrongProjectSignals($0.reasons) }
            let baselineProjects = strictProjects.isEmpty ? discoveredProjects : strictProjects
            let sortedForCapping = baselineProjects.sorted { lhs, rhs in
                let lhsScore = projectPriority(for: lhs)
                let rhsScore = projectPriority(for: rhs)
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                return lhs.url.lastPathComponent.localizedCaseInsensitiveCompare(rhs.url.lastPathComponent) == .orderedAscending
            }

            let cappedProjects = Array(sortedForCapping.prefix(50))
            filteredNonProjectCount += max(0, discoveredProjects.count - cappedProjects.count)
            discoveredProjects = cappedProjects
            errors.append(language == .zhHans ? "扫描结果过多，已自动过滤非项目目录。" : "Too many scan results; non-project folders were filtered automatically.")
        }

        var summaries: [ProjectSummary] = []

        for project in discoveredProjects.sorted(by: { $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending }) {
            do {
                let summary = try loadScannedProjectSummary(at: project.url, detectionReasons: project.reasons, language: language)
                summaries.append(summary)
            } catch {
                skippedDirectoryCount += 1
                filteredNonProjectCount += 1
                errors.append(language == .zhHans ? "跳过不可读项目：\(project.url.path)" : "Skipped unreadable project: \(project.url.path)")
            }
        }

        let derivedFilteredCount = max(skippedDirectoryCount, candidateDirectoryCount - summaries.count)
        filteredNonProjectCount = max(filteredNonProjectCount, derivedFilteredCount)

        return ProjectScanReport(
            summaries: summaries,
            diagnostics: ScanDiagnostics(
                scanRootCount: focusedScanRoots.count,
                lastScanAt: Date(),
                candidateDirectoryCount: candidateDirectoryCount,
                identifiedProjectCount: summaries.count,
                skippedDirectoryCount: max(skippedDirectoryCount, candidateDirectoryCount - summaries.count),
                filteredNonProjectCount: filteredNonProjectCount,
                overflowProtectionApplied: overflowProtectionApplied,
                lastErrorMessage: errors.last
            )
        )
    }

    func loadScannedProjectSummary(at projectURL: URL, detectionReasons: [String], language: AppLanguage) throws -> ProjectSummary {
        let metadata: ProjectMetadata
        let sessions: [SessionBundle]
        let handoffPaths = HandoffPaths(projectURL: projectURL)

        if fileManager.fileExists(atPath: handoffPaths.projectJsonURL.path) {
            let data = try Data(contentsOf: handoffPaths.projectJsonURL)
            metadata = try decoder.decode(ProjectMetadata.self, from: data)
            sessions = try loadSessions(for: projectURL)
        } else {
            let values = try? projectURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let createdAt = values?.creationDate ?? Date()
            let updatedAt = values?.contentModificationDate ?? createdAt
            metadata = ProjectMetadata(
                name: projectURL.lastPathComponent,
                path: projectURL.path,
                createdAt: createdAt,
                updatedAt: updatedAt,
                activeSessionID: nil
            )
            sessions = []
        }

        let gitSnapshot = gitService.snapshot(for: projectURL)
        return ProjectSummary(
            metadata: metadata,
            detectionReasons: detectionReasons,
            gitSnapshot: gitSnapshot,
            sessions: sessions.sorted(by: { $0.metadata.updatedAt > $1.metadata.updatedAt })
        )
    }

    func loadProjectSummary(at projectURL: URL, detectionReasons: [String], language: AppLanguage) throws -> ProjectSummary {
        let metadata = try ensureProjectHandoff(at: projectURL, language: language)
        let sessions = try loadSessions(for: projectURL)
        let gitSnapshot = gitService.snapshot(for: projectURL)
        return ProjectSummary(
            metadata: metadata,
            detectionReasons: detectionReasons,
            gitSnapshot: gitSnapshot,
            sessions: sessions.sorted(by: { $0.metadata.updatedAt > $1.metadata.updatedAt })
        )
    }

    func refreshGitSnapshot(for projectPath: String) -> GitSnapshot {
        gitService.snapshot(for: URL(fileURLWithPath: projectPath))
    }

    func createSession(projectPath: String, name: String? = nil, sessionID: String? = nil, language: AppLanguage) throws -> SessionBundle {
        let projectURL = URL(fileURLWithPath: projectPath)
        var metadata = try ensureProjectHandoff(at: projectURL, language: language)
        let handoffPaths = HandoffPaths(projectURL: projectURL)

        let sessionID = sessionID ?? makeSessionID()
        let sessionName = name ?? defaultSessionName(language: language)
        let sessionFolder = handoffPaths.sessionDir(sessionID)
        try fileManager.createDirectory(at: sessionFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: handoffPaths.promptsDir(sessionID), withIntermediateDirectories: true)

        let now = Date()
        let sessionMetadata = SessionMetadata(
            id: sessionID,
            name: sessionName,
            currentAgent: .codex,
            codexQuotaStatus: .unknown,
            claudeQuotaStatus: .unknown,
            createdAt: now,
            updatedAt: now
        )
        let starterDocs = starterDocuments(projectPath: projectPath, sessionName: sessionName, sessionID: sessionID, language: language)
        let bundle = SessionBundle(metadata: sessionMetadata, folderPath: sessionFolder.path, documents: starterDocs)

        try writeSession(bundle)

        metadata.activeSessionID = sessionMetadata.id
        metadata.updatedAt = now
        try writeProjectMetadata(metadata, for: projectURL)
        try updateActiveFiles(projectMetadata: metadata, session: bundle, language: language)

        return bundle
    }

    func importProject(at projectPath: String, language: AppLanguage) throws -> ProjectSummary {
        let projectURL = URL(fileURLWithPath: projectPath)
        let handoffPaths = HandoffPaths(projectURL: projectURL)
        let defaultSessionID = makeSessionID()

        do {
            _ = try ensureProjectHandoff(at: projectURL, language: language)

            let existingSessions = try loadSessions(for: projectURL)
            if existingSessions.isEmpty {
                _ = try createSession(
                    projectPath: projectPath,
                    name: language == .zhHans ? "默认会话" : "Default Session",
                    sessionID: defaultSessionID,
                    language: language
                )
            }

            let reasons = detectionReasons(for: projectURL) ?? ["manual import"]
            return try loadProjectSummary(at: projectURL, detectionReasons: reasons, language: language)
        } catch {
            throw StoreError.importFailed(
                ImportFailureContext(
                    selectedProjectURL: projectURL.path,
                    handoffDir: handoffPaths.handoffDir.path,
                    activeProjectURL: handoffPaths.activeProjectURL.path,
                    activeSessionURL: handoffPaths.activeSessionURL.path,
                    sessionsDir: handoffPaths.sessionsDir.path,
                    sessionDir: handoffPaths.sessionDir(defaultSessionID).path,
                    underlyingError: error.localizedDescription
                )
            )
        }
    }

    func saveSession(projectPath: String, session: SessionBundle, language: AppLanguage, makeActive: Bool = false) throws {
        let projectURL = URL(fileURLWithPath: projectPath)
        var metadata = try ensureProjectHandoff(at: projectURL, language: language)
        var updated = session
        updated.metadata.updatedAt = Date()
        try writeSession(updated)

        if makeActive || metadata.activeSessionID == updated.metadata.id || metadata.activeSessionID == nil {
            metadata.activeSessionID = updated.metadata.id
        }
        metadata.updatedAt = Date()
        try writeProjectMetadata(metadata, for: projectURL)
        try updateActiveFiles(projectMetadata: metadata, session: updated, language: language)
    }

    func writeSessionDocumentsOnly(projectPath: String, session: SessionBundle) throws {
        let folder = URL(fileURLWithPath: session.folderPath)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        for type in HandoffDocumentType.allCases {
            let text = session.documents[type] ?? ""
            let fileURL = folder.appendingPathComponent(type.rawValue, isDirectory: false)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        var meta = session.metadata
        meta.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metaData = try encoder.encode(meta)
        try metaData.write(to: folder.appendingPathComponent("session.json", isDirectory: false), options: .atomic)
    }

    func renameSession(projectPath: String, sessionID: String, newName: String, language: AppLanguage) throws {
        let projectURL = URL(fileURLWithPath: projectPath)
        guard var session = try loadSession(projectURL: projectURL, sessionID: sessionID) else {
            throw StoreError.missingSession
        }
        session.metadata.name = newName
        try saveSession(projectPath: projectPath, session: session, language: language)
    }

    func archiveSession(projectPath: String, sessionID: String, archived: Bool, language: AppLanguage) throws {
        let projectURL = URL(fileURLWithPath: projectPath)
        guard var session = try loadSession(projectURL: projectURL, sessionID: sessionID) else {
            throw StoreError.missingSession
        }
        session.metadata.isArchived = archived
        try saveSession(projectPath: projectPath, session: session, language: language)
    }

    func markPrimarySession(projectPath: String, sessionID: String, language: AppLanguage) throws {
        let projectURL = URL(fileURLWithPath: projectPath)
        var sessions = try loadSessions(for: projectURL)
        guard sessions.contains(where: { $0.metadata.id == sessionID }) else {
            throw StoreError.missingSession
        }

        for index in sessions.indices {
            sessions[index].metadata.isPrimary = sessions[index].metadata.id == sessionID
            try writeSession(sessions[index])
        }
        try activateSession(projectPath: projectPath, sessionID: sessionID, language: language)
    }

    func duplicateSession(projectPath: String, sessionID: String, language: AppLanguage) throws -> SessionBundle {
        let projectURL = URL(fileURLWithPath: projectPath)
        guard let source = try loadSession(projectURL: projectURL, sessionID: sessionID) else {
            throw StoreError.missingSession
        }

        var copy = source
        let now = Date()
        copy.metadata.id = makeSessionID()
        copy.metadata.name = language == .zhHans ? "\(source.metadata.name) 副本" : "\(source.metadata.name) Copy"
        copy.metadata.isArchived = false
        copy.metadata.isPrimary = false
        copy.metadata.parentSessionID = source.metadata.id
        copy.metadata.createdAt = now
        copy.metadata.updatedAt = now
        copy.folderPath = HandoffPaths(projectURL: projectURL).sessionDir(copy.metadata.id).path
        try saveSession(projectPath: projectPath, session: copy, language: language, makeActive: true)
        return copy
    }

    func cleanupTestSessions(projectPath: String, language: AppLanguage) throws -> Int {
        let projectURL = URL(fileURLWithPath: projectPath)
        let sessions = try loadSessions(for: projectURL)
        let testSessions = sessions.filter { session in
            let name = session.metadata.name.lowercased()
            return !session.metadata.isPrimary
                && name != "default session"
                && name != "默认会话"
                && (name.contains("test") || name.contains("测试"))
        }

        for session in testSessions {
            _ = try deleteSession(projectPath: projectPath, sessionID: session.metadata.id, language: language)
        }
        return testSessions.count
    }

    @discardableResult
    func deleteSession(projectPath: String, sessionID: String, language: AppLanguage) throws -> String? {
        let projectURL = URL(fileURLWithPath: projectPath)
        let handoffPaths = HandoffPaths(projectURL: projectURL)
        var metadata = try ensureProjectHandoff(at: projectURL, language: language)
        let sessionFolder = handoffPaths.sessionDir(sessionID).standardizedFileURL
        let sessionsFolder = handoffPaths.sessionsDir.standardizedFileURL
        let metadataURL = handoffPaths.sessionJsonURL(sessionID)

        guard sessionFolder.path.hasPrefix("\(sessionsFolder.path)/"),
              fileManager.fileExists(atPath: metadataURL.path) else {
            throw StoreError.unsafeSessionDelete
        }

        try fileManager.removeItem(at: sessionFolder)
        let remaining = try loadSessions(for: projectURL)
        if remaining.isEmpty {
            let defaultSession = try createSession(
                projectPath: projectPath,
                name: language == .zhHans ? "默认会话" : "Default Session",
                language: language
            )
            return defaultSession.metadata.id
        }
        let fallbackID = fallbackSessionID(from: remaining)
        metadata.activeSessionID = fallbackID
        metadata.updatedAt = Date()
        try writeProjectMetadata(metadata, for: projectURL)
        let fallback = fallbackID.flatMap { try? loadSession(projectURL: projectURL, sessionID: $0) }
        try updateActiveFiles(projectMetadata: metadata, session: fallback, language: language)
        return fallbackID
    }

    func activateSession(projectPath: String, sessionID: String, language: AppLanguage) throws {
        let projectURL = URL(fileURLWithPath: projectPath)
        var metadata = try ensureProjectHandoff(at: projectURL, language: language)
        guard let session = try loadSession(projectURL: projectURL, sessionID: sessionID) else {
            throw StoreError.missingSession
        }

        metadata.activeSessionID = sessionID
        metadata.updatedAt = Date()
        try writeProjectMetadata(metadata, for: projectURL)
        try updateActiveFiles(projectMetadata: metadata, session: session, language: language)
    }

    func generatePrompt(project: ProjectSummary, session: SessionBundle, targetAgent: AgentKind, language: AppLanguage, templates: PromptTemplateSet = .default) -> GeneratedPrompt {
        let sourceAgent = session.metadata.currentAgent
        let sessionFolder = URL(fileURLWithPath: session.folderPath)
        let git = project.gitSnapshot
        let handoffPaths = HandoffPaths(projectURL: URL(fileURLWithPath: project.metadata.path))
        let isGitRepository = git.state != .unavailable
        let gitSummary: String
        if isGitRepository {
            gitSummary = """
            git status --porcelain
            \(git.porcelain.isEmpty ? "(clean working tree)" : git.porcelain)

            git diff --stat
            \(git.diffStat.isEmpty ? "(no diff stat)" : git.diffStat)
            """
        } else if language == .zhHans {
            gitSummary = """
            当前项目不是 Git 仓库。
            请以项目文件系统和 .agent-handoff 为准，不要依赖 git status / git diff 作为主要检查方式。
            """
        } else {
            gitSummary = """
            The current project is not a Git repository.
            Use the project files and .agent-handoff as the source of truth; do not rely on git status / git diff as the primary check.
            """
        }

        let documentPaths = [
            HandoffDocumentType.projectContext: sessionFolder.appendingPathComponent(HandoffDocumentType.projectContext.rawValue, isDirectory: false).path,
            HandoffDocumentType.conversationLog: sessionFolder.appendingPathComponent(HandoffDocumentType.conversationLog.rawValue, isDirectory: false).path,
            HandoffDocumentType.currentState: sessionFolder.appendingPathComponent(HandoffDocumentType.currentState.rawValue, isDirectory: false).path,
            .todo: sessionFolder.appendingPathComponent(HandoffDocumentType.todo.rawValue, isDirectory: false).path,
            .decisions: sessionFolder.appendingPathComponent(HandoffDocumentType.decisions.rawValue, isDirectory: false).path,
            .changelog: sessionFolder.appendingPathComponent(HandoffDocumentType.changelog.rawValue, isDirectory: false).path,
            .openQuestions: sessionFolder.appendingPathComponent(HandoffDocumentType.openQuestions.rawValue, isDirectory: false).path,
        ]
        let direction = "\(sourceAgent.rawValue) → \(targetAgent.rawValue)"
        let body = buildPromptBody(
            language: language,
            template: templateText(sourceAgent: sourceAgent, targetAgent: targetAgent, language: language, templates: templates),
            direction: direction,
            sourceAgent: sourceAgent,
            targetAgent: targetAgent,
            project: project,
            session: session,
            activeProjectPath: handoffPaths.activeProjectURL.path,
            activeSessionPath: handoffPaths.activeSessionURL.path,
            documentPaths: documentPaths,
            gitSummary: gitSummary,
            isGitRepository: isGitRepository
        )

        let slug = targetAgent == .claude ? "to-claude" : "to-codex"
        return GeneratedPrompt(
            previousAgent: sourceAgent,
            targetAgent: targetAgent,
            title: direction,
            body: body,
            fileName: "\(timestampString(Date()))-\(slug).md"
        )
    }

    func persistPrompt(projectPath: String, sessionID: String, prompt: GeneratedPrompt) throws {
        let promptsDirectory = HandoffPaths(projectURL: URL(fileURLWithPath: projectPath)).promptsDir(sessionID)
        try fileManager.createDirectory(at: promptsDirectory, withIntermediateDirectories: true)
        try writeText(prompt.body, to: promptsDirectory.appendingPathComponent(prompt.fileName, isDirectory: false))
    }

    func syncSessionHandoff(
        project: ProjectSummary,
        session: SessionBundle,
        language: AppLanguage,
        promptDirection: String,
        includeChangelog: Bool = true,
        autoDetectReceipt: Bool = false
    ) -> SessionBundle {
        var synced = session
        let gitSnapshot = gitService.snapshot(for: URL(fileURLWithPath: project.metadata.path))
        let now = Date()
        let existingState = session.documents[.currentState] ?? ""
        let conversationEntries = collectConversationLogEntries(projectPath: project.metadata.path, projectName: project.metadata.name)
        let visibleConversationEntries = Array(conversationEntries.suffix(80))

        synced.documents[.projectContext] = buildProjectContextDocument(
            projectURL: URL(fileURLWithPath: project.metadata.path),
            language: language,
            generatedAt: now
        )
        synced.documents[.conversationLog] = buildConversationLogDocument(
            project: project,
            session: session,
            language: language,
            generatedAt: now,
            entries: visibleConversationEntries
        )
        if autoDetectReceipt,
           let detection = detectLatestHandoffReceipt(
               in: visibleConversationEntries,
               for: session.metadata.currentAgent,
               since: session.metadata.lastHandoffRequestedAt
           ) {
            synced.metadata.handoffReceiptStatus = detection.status
            synced.metadata.lastHandoffReceiptText = detection.text
            synced.metadata.lastHandoffReceiptAt = detection.detectedAt
        }
        synced.documents[.currentState] = mergeCurrentStateSnapshot(
            existing: existingState,
            project: project,
            session: synced,
            gitSnapshot: gitSnapshot,
            language: language,
            promptDirection: promptDirection,
            updatedAt: now,
            currentPhase: extractPhase(from: existingState, language: language)
        )
        if includeChangelog {
            synced.documents[.changelog] = appendChangelogEntry(
                existing: session.documents[.changelog] ?? "",
                project: project,
                session: synced,
                gitSnapshot: gitSnapshot,
                language: language,
                updatedAt: now
            )
        }
        synced.documents[.todo] = mergeTodoSuggestions(
            existing: session.documents[.todo] ?? "",
            project: project,
            session: synced,
            language: language
        )
        synced.metadata.updatedAt = now
        return synced
    }

    @MainActor
    func copyPromptToPasteboard(_ prompt: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
    }

    @MainActor
    func pickDirectory(prompt: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    @MainActor
    func revealInFinder(projectPath: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: projectPath)])
    }

    @MainActor
    func openDirectoryInFinder(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func workspaceDirectoryPath() -> String {
        paths.workspaceDirectory.path
    }

    func appBuildInfo() -> String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "swift-run"
        return "\(version) (\(build))"
    }

    func appRuntimeInfo() -> String {
        guard let executableURL = Bundle.main.executableURL else {
            return "Executable: unknown"
        }

        let modifiedAt: String
        if let values = try? executableURL.resourceValues(forKeys: [.contentModificationDateKey]),
           let date = values.contentModificationDate {
            modifiedAt = localizedDateTime(date, language: .zhHans)
        } else {
            modifiedAt = "unknown"
        }

        return "Executable: \(executableURL.path)\nModified: \(modifiedAt)"
    }

    func launcherScriptPath() -> String {
        guard let executableURL = Bundle.main.executableURL else {
            return ""
        }

        var current = executableURL.deletingLastPathComponent()
        for _ in 0..<8 {
            let packageSwift = current.appendingPathComponent("Package.swift")
            let scriptPath = current.appendingPathComponent("Scripts/run-agent-console.sh")
            if fileManager.fileExists(atPath: packageSwift.path),
               fileManager.fileExists(atPath: scriptPath.path) {
                return scriptPath.path
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path || parent.path == "/" { break }
            current = parent
        }
        return ""
    }

    func refreshSafeUsageWorkspace(existing: UsageWorkspace) -> UsageWorkspace {
        existing
    }

    func parseCodexUsageLogs(existingRecords: [TokenUsageRecord] = []) -> [TokenUsageRecord] {
        let codexDir = paths.homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        guard fileManager.fileExists(atPath: codexDir.path) else { return existingRecords }

        var records = existingRecords
        let existingIDSet = Set(records.map(\.id))
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()

        var jsonlFiles: [URL] = []

        let activeSessions = codexDir.appendingPathComponent("sessions", isDirectory: true)
        if fileManager.fileExists(atPath: activeSessions.path) {
            if let yearDirs = try? fileManager.contentsOfDirectory(at: activeSessions, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                for yearDir in yearDirs where (try? yearDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    if let monthDirs = try? fileManager.contentsOfDirectory(at: yearDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                        for monthDir in monthDirs where (try? monthDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                            if let dayDirs = try? fileManager.contentsOfDirectory(at: monthDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                                for dayDir in dayDirs {
                                    guard let files = try? fileManager.contentsOfDirectory(at: dayDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
                                    jsonlFiles.append(contentsOf: files.filter { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("rollout-") })
                                }
                            }
                        }
                    }
                }
            }
        }

        let archivedSessions = codexDir.appendingPathComponent("archived_sessions", isDirectory: true)
        if fileManager.fileExists(atPath: archivedSessions.path) {
            if let files = try? fileManager.contentsOfDirectory(at: archivedSessions, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                jsonlFiles.append(contentsOf: files.filter { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("rollout-") })
            }
        }

        for fileURL in jsonlFiles {
            parseCodexTokenEvents(fileURL: fileURL, cutoffDate: cutoffDate, existingIDSet: existingIDSet, into: &records)
        }

        records.sort { $0.createdAt > $1.createdAt }
        if records.count > 10000 {
            records = Array(records.prefix(10000))
        }
        return records
    }

    private func parseCodexTokenEvents(fileURL: URL, cutoffDate: Date, existingIDSet: Set<UUID>, into records: inout [TokenUsageRecord]) {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? fileHandle.close() }

        var lineBuffer = Data()
        let chunkSize = 64 * 1024

        while true {
            let chunk: Data
            if #available(macOS 14, *) {
                guard let c = try? fileHandle.read(upToCount: chunkSize) else { break }
                chunk = c
            } else {
                chunk = fileHandle.readData(ofLength: chunkSize)
            }
            if chunk.isEmpty { break }

            lineBuffer.append(chunk)
            while let newlineIndex = lineBuffer.firstIndex(of: 0x0A) {
                let lineData = lineBuffer[..<newlineIndex]
                lineBuffer.removeSubrange(0...newlineIndex)

                guard lineData.count > 60 else { continue }

                if let record = parseCodexTokenLine(lineData, cutoffDate: cutoffDate),
                   !existingIDSet.contains(record.id) {
                    records.append(record)
                    if records.count >= 8000 { return }
                }
            }

            if lineBuffer.count > 10 * 1024 * 1024 { lineBuffer.removeAll() }
        }
    }

    private func parseCodexTokenLine(_ data: Data, cutoffDate: Date) -> TokenUsageRecord? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "event_msg",
              let payload = json["payload"] as? [String: Any],
              let payloadType = payload["type"] as? String,
              payloadType == "token_count",
              let info = payload["info"] as? [String: Any],
              let usage = info["total_token_usage"] as? [String: Any] else {
            return nil
        }

        let usageData: [String: Any] = {
            if let last = info["last_token_usage"] as? [String: Any],
               (last["input_tokens"] as? Int ?? 0) > 0 {
                return last
            }
            return usage
        }()

        let inputTokens = usageData["input_tokens"] as? Int ?? 0
        let outputTokens = usageData["output_tokens"] as? Int ?? 0
        let cacheTokens = usageData["cached_input_tokens"] as? Int ?? 0
        let reasoningTokens = usageData["reasoning_output_tokens"] as? Int ?? 0

        guard (inputTokens > 0 || outputTokens > 0) else { return nil }
        guard inputTokens < 200_000, outputTokens < 100_000 else { return nil }

        let timestampString = json["timestamp"] as? String ?? ""
        let createdAt = parseISO8601(timestampString) ?? Date.distantPast
        guard createdAt >= cutoffDate else { return nil }

        return TokenUsageRecord(
            id: UUID(),
            provider: .codex,
            projectPath: nil,
            sessionID: nil,
            model: nil,
            inputTokens: inputTokens,
            outputTokens: outputTokens + reasoningTokens,
            cacheTokens: cacheTokens,
            cost: nil,
            createdAt: createdAt
        )
    }

    func parseClaudeUsageLogs(existingRecords: [TokenUsageRecord] = []) -> [TokenUsageRecord] {
        let projectsDir = paths.homeDirectory
            .appendingPathComponent(".claude/projects", isDirectory: true)

        guard fileManager.fileExists(atPath: projectsDir.path) else { return existingRecords }

        var records = existingRecords

        guard let projectDirs = try? fileManager.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return existingRecords }

        let existingIDSet = Set(records.map(\.id))
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()

        for projectDir in projectDirs {
            guard (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }

            guard let jsonlFiles = try? fileManager.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for fileURL in jsonlFiles where fileURL.pathExtension.lowercased() == "jsonl" {
                guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else { continue }
                defer { try? fileHandle.close() }

                var lineBuffer = Data()
                let chunkSize = 64 * 1024
                var eof = false

                while !eof {
                    let chunk: Data
                    do {
                        if #available(macOS 14, *) {
                            guard let c = try fileHandle.read(upToCount: chunkSize) else { eof = true; break }
                            chunk = c
                        } else {
                            chunk = fileHandle.readData(ofLength: chunkSize)
                        }
                    } catch {
                        break
                    }
                    if chunk.isEmpty { eof = true; break }

                    lineBuffer.append(chunk)
                    while let newlineIndex = lineBuffer.firstIndex(of: 0x0A) {
                        let lineData = lineBuffer[..<newlineIndex]
                        lineBuffer.removeSubrange(0...newlineIndex)

                        guard lineData.count > 50 else { continue }

                        if let record = parseClaudeJSONLLine(lineData, cutoffDate: cutoffDate),
                           !existingIDSet.contains(record.id) {
                            records.append(record)
                        }
                    }

                    if lineBuffer.count > 10 * 1024 * 1024 {
                        lineBuffer.removeAll()
                    }
                }
            }
        }

        records.sort { $0.createdAt > $1.createdAt }
        if records.count > 10000 {
            records = Array(records.prefix(10000))
        }

        return records
    }

    private func parseClaudeJSONLLine(_ data: Data, cutoffDate: Date) -> TokenUsageRecord? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "assistant",
              let message = json["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else {
            return nil
        }

        let inputTokens = usage["input_tokens"] as? Int ?? 0
        let outputTokens = usage["output_tokens"] as? Int ?? 0
        let cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
        let cacheTokens = cacheCreation + cacheRead

        guard inputTokens > 0 || outputTokens > 0 else { return nil }

        let timestampString = json["timestamp"] as? String ?? ""
        let createdAt = parseISO8601(timestampString) ?? Date.distantPast
        guard createdAt >= cutoffDate else { return nil }

        let model = message["model"] as? String
        let cwd = json["cwd"] as? String
        let sessionId = json["sessionId"] as? String

        return TokenUsageRecord(
            id: UUID(),
            provider: .claude,
            projectPath: cwd,
            sessionID: sessionId,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheTokens: cacheTokens,
            cost: nil,
            createdAt: createdAt
        )
    }

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    func filteredTokenRecords(_ records: [TokenUsageRecord], range: UsageRange, now: Date = Date()) -> [TokenUsageRecord] {
        guard range != .custom else { return records }
        let calendar = Calendar.current
        let startDate: Date?
        switch range {
        case .today:
            startDate = calendar.startOfDay(for: now)
        case .sevenDays:
            startDate = calendar.date(byAdding: .day, value: -7, to: now)
        case .thirtyDays:
            startDate = calendar.date(byAdding: .day, value: -30, to: now)
        case .custom:
            startDate = nil
        }
        guard let startDate else { return records }
        return records.filter { $0.createdAt >= startDate && $0.createdAt <= now }
    }

    func suggestedScanRootPaths() -> [String] {
        let home = paths.homeDirectory
        return [
            home.appendingPathComponent("Documents/Codex", isDirectory: true).path,
            home.appendingPathComponent("Documents/Claude", isDirectory: true).path,
            home.appendingPathComponent("Projects/Codex", isDirectory: true).path,
            home.appendingPathComponent("Projects/Claude", isDirectory: true).path,
            home.appendingPathComponent("Desktop/Codex", isDirectory: true).path,
            home.appendingPathComponent("Desktop/Claude", isDirectory: true).path,
        ]
    }

    func pathExists(_ path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    func createDirectoryIfNeeded(at path: String) throws {
        try fileManager.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true)
    }

    func normalizeScanRoots(_ roots: [ScanRoot]) -> [ScanRoot] {
        let suggested = Set(suggestedScanRootPaths())
        var deduped: [ScanRoot] = []
        var seen = Set<String>()

        for root in roots {
            let exists = pathExists(root.path)
            if root.isDefault {
                guard suggested.contains(root.path), exists else {
                    continue
                }
            }

            guard !seen.contains(root.path) else { continue }
            seen.insert(root.path)
            deduped.append(root)
        }

        return deduped
    }

    private func focusedAgentScanRoots(from scanRoots: [ScanRoot]) -> [ScanRoot] {
        var rootsByPath: [String: ScanRoot] = [:]

        let focusedSavedRoots = scanRoots.compactMap { root -> String? in
            guard root.isDefault else { return nil }
            guard let normalized = normalizeWorkspacePath(root.path) else { return nil }
            guard isAgentProjectContainerPath(normalized) else { return nil }
            return normalized
        }

        for path in focusedSavedRoots {
            if rootsByPath[path] == nil {
                rootsByPath[path] = ScanRoot(path: path, isDefault: true)
            }
        }

        for root in scanRoots where !root.isDefault {
            guard let normalized = normalizeWorkspacePath(root.path) else { continue }
            if rootsByPath[normalized] == nil {
                rootsByPath[normalized] = ScanRoot(path: normalized, isDefault: false)
            }
        }

        let workspaceRoots = codexWorkspaceRoots().union(claudeWorkspaceRoots())
        for path in workspaceRoots {
            guard let normalized = normalizeWorkspacePath(path) else { continue }
            if rootsByPath[normalized] == nil {
                rootsByPath[normalized] = ScanRoot(path: normalized, isDefault: true)
            }
        }

        return rootsByPath.values.sorted { lhs, rhs in
            lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }

    private func detectLocalAccounts(existing: [AccountSummary]) -> [AccountSummary] {
        var accountsByKey: [String: AccountSummary] = [:]

        for account in existing {
            let key = accountKey(provider: account.provider, source: account.source, mode: account.mode, displayName: account.displayName)
            accountsByKey[key] = account
        }

        func upsert(provider: AgentKind, displayName: String, source: AccountSource, mode: AccountMode, planName: String? = nil, isActive: Bool = true) {
            let key = accountKey(provider: provider, source: source, mode: mode, displayName: displayName)
            if var existing = accountsByKey[key] {
                existing.isActive = isActive
                existing.planName = planName ?? existing.planName
                accountsByKey[key] = existing
            } else {
                accountsByKey[key] = AccountSummary(
                    provider: provider,
                    displayName: displayName,
                    source: source,
                    mode: mode,
                    isActive: isActive,
                    planName: planName
                )
            }
        }

        let codexAuthURL = paths.homeDirectory.appendingPathComponent(".codex/auth.json", isDirectory: false)
        if fileManager.fileExists(atPath: codexAuthURL.path) {
            upsert(provider: .codex, displayName: "~/.codex/auth.json", source: .localImport, mode: .subscription, planName: "Local auth file present")
        }

        let codexConfigURL = paths.homeDirectory.appendingPathComponent(".codex/config.toml", isDirectory: false)
        if fileManager.fileExists(atPath: codexConfigURL.path) {
            upsert(provider: .codex, displayName: "~/.codex/config.toml", source: .api, mode: .api, planName: "Config file present", isActive: false)
        }

        let claudeConfigURL = paths.homeDirectory.appendingPathComponent(".claude/settings.json", isDirectory: false)
        if fileManager.fileExists(atPath: claudeConfigURL.path) {
            upsert(provider: .claude, displayName: "~/.claude/settings.json", source: .localImport, mode: .unknown, planName: "Local settings present")
        }

        let claudeProjectsURL = paths.homeDirectory.appendingPathComponent(".claude/projects", isDirectory: true)
        if fileManager.fileExists(atPath: claudeProjectsURL.path) {
            upsert(provider: .claude, displayName: "~/.claude/projects", source: .localImport, mode: .unknown, planName: "Local project logs present", isActive: false)
        }

        if ProcessInfo.processInfo.environment.keys.contains("OPENAI_API_KEY") {
            upsert(provider: .codex, displayName: "OPENAI_API_KEY", source: .api, mode: .api, planName: "Environment variable present", isActive: false)
        }

        if ProcessInfo.processInfo.environment.keys.contains("ANTHROPIC_API_KEY") {
            upsert(provider: .claude, displayName: "ANTHROPIC_API_KEY", source: .api, mode: .api, planName: "Environment variable present", isActive: false)
        }

        return accountsByKey.values.sorted { lhs, rhs in
            if lhs.provider.rawValue != rhs.provider.rawValue {
                return lhs.provider.rawValue < rhs.provider.rawValue
            }
            if lhs.isActive != rhs.isActive {
                return lhs.isActive && !rhs.isActive
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func accountKey(provider: AgentKind, source: AccountSource, mode: AccountMode, displayName: String) -> String {
        "\(provider.rawValue)|\(source.rawValue)|\(mode.rawValue)|\(displayName)"
    }

    private func shouldIncludeKnownProject(path: String, focusedRoots: [String]) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        let normalizedURL = URL(fileURLWithPath: normalized)

        if shouldExcludeScanPath(normalized) {
            return false
        }
        guard fileManager.fileExists(atPath: normalized) else {
            return false
        }
        guard detectionReasons(for: normalizedURL) != nil else {
            return false
        }

        if focusedRoots.contains(normalized) {
            return true
        }
        if focusedRoots.contains(normalizedURL.deletingLastPathComponent().path) {
            return true
        }
        return hasSavedHandoffSession(at: normalizedURL)
    }

    private func codexWorkspaceRoots() -> Set<String> {
        let globalStateURL = paths.homeDirectory
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent(".codex-global-state.json", isDirectory: false)

        guard let data = try? Data(contentsOf: globalStateURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var roots = Set<String>()
        let listKeys = ["project-order", "active-workspace-roots", "electron-saved-workspace-roots"]
        for key in listKeys {
            if let values = object[key] as? [String] {
                roots.formUnion(values)
            }
        }
        if let hints = object["thread-workspace-root-hints"] as? [String: String] {
            roots.formUnion(hints.values)
        }
        return roots
    }

    private func claudeWorkspaceRoots() -> Set<String> {
        var pathsFound = Set<String>()
        let home = paths.homeDirectory
        let projectStore = home.appendingPathComponent(".claude/projects", isDirectory: true)
        let desktop3PSessions = home.appendingPathComponent("Library/Application Support/Claude-3p/claude-code-sessions", isDirectory: true)

        for root in [projectStore, desktop3PSessions] {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            while let candidate = enumerator.nextObject() as? URL {
                guard candidate.pathExtension.lowercased() == "jsonl" else { continue }
                pathsFound.formUnion(extractCwdPaths(fromJSONLFile: candidate))
            }
        }

        return pathsFound
    }

    private func extractCwdPaths(fromJSONLFile url: URL) -> Set<String> {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var roots = Set<String>()
        let token = "\"cwd\":\""

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let range = line.range(of: token) else { continue }
            let tail = line[range.upperBound...]
            guard let endQuote = tail.firstIndex(of: "\"") else { continue }
            let rawPath = String(tail[..<endQuote]).replacingOccurrences(of: "\\/", with: "/")
            guard let normalized = normalizeWorkspacePath(rawPath) else { continue }
            roots.insert(normalized)
        }

        return roots
    }

    private func normalizeWorkspacePath(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard normalized != paths.homeDirectory.path else { return nil }
        guard fileManager.fileExists(atPath: normalized) else { return nil }
        guard !shouldExcludeScanPath(normalized) else { return nil }
        return normalized
    }

    private func isAgentInternalPath(_ path: String) -> Bool {
        let home = paths.homeDirectory.path
        let internalPrefixes = [
            "\(home)/.codex",
            "\(home)/.claude",
            "\(home)/Library/Application Support/Codex",
            "\(home)/Library/Application Support/Claude",
            "\(home)/Library/Application Support/Claude-3p",
            paths.workspaceDirectory.path,
        ]
        return internalPrefixes.contains(where: { path == $0 || path.hasPrefix("\($0)/") })
    }

    private func discoverProjects(in scanRoot: ScanRoot) -> DiscoveryReport {
        let rootURL = URL(fileURLWithPath: scanRoot.path)
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return DiscoveryReport(
                discovered: [],
                candidateDirectoryCount: 0,
                skippedDirectoryCount: 1,
                errors: scanRoot.isDefault ? [] : ["扫描目录不存在：\(scanRoot.path)"]
            )
        }

        var results: [DiscoveredProject] = []
        var seen = Set<String>()
        var candidateDirectoryCount = 0
        var skippedDirectoryCount = 0

        func appendIfProject(_ directoryURL: URL) {
            guard !seen.contains(directoryURL.path) else { return }
            guard let reasons = detectionReasons(for: directoryURL) else { return }
            seen.insert(directoryURL.path)
            results.append(DiscoveredProject(url: directoryURL, reasons: reasons))
        }

        func inspect(_ directoryURL: URL) {
            candidateDirectoryCount += 1

            if shouldSkipCandidateDirectory(directoryURL) {
                skippedDirectoryCount += 1
                return
            }

            let beforeCount = results.count
            appendIfProject(directoryURL)
            if beforeCount == results.count {
                skippedDirectoryCount += 1
            }
        }

        walk(rootURL, remainingDepth: discoveryDepth(for: rootURL))

        return DiscoveryReport(
            discovered: results,
            candidateDirectoryCount: candidateDirectoryCount,
            skippedDirectoryCount: skippedDirectoryCount,
            errors: []
        )

        func walk(_ directoryURL: URL, remainingDepth: Int) {
            inspect(directoryURL)
            if seen.contains(directoryURL.path) || remainingDepth <= 0 {
                return
            }

            for candidate in directChildDirectories(of: directoryURL) {
                walk(candidate, remainingDepth: remainingDepth - 1)
            }
        }
    }

    private func detectionReasons(for directoryURL: URL) -> [String]? {
        guard !shouldExcludeScanPath(directoryURL.path) else {
            return nil
        }
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directoryURL.path) else {
            return nil
        }

        let names = Set(contents)
        var reasons: [String] = []

        if names.contains(".agent-handoff") { reasons.append(".agent-handoff") }
        if names.contains(".git") { reasons.append(".git") }
        if names.contains("Package.swift") { reasons.append("Package.swift") }
        if names.contains("package.json") { reasons.append("package.json") }
        if names.contains("pyproject.toml") { reasons.append("pyproject.toml") }
        if names.contains("Cargo.toml") { reasons.append("Cargo.toml") }
        if names.contains("go.mod") { reasons.append("go.mod") }
        if names.contains("pnpm-workspace.yaml") { reasons.append("pnpm-workspace.yaml") }
        if names.contains("pom.xml") { reasons.append("pom.xml") }
        if names.contains("build.gradle") { reasons.append("build.gradle") }
        if names.contains("build.gradle.kts") { reasons.append("build.gradle.kts") }
        if names.contains("Gemfile") { reasons.append("Gemfile") }
        if names.contains("composer.json") { reasons.append("composer.json") }
        if names.contains("mix.exs") { reasons.append("mix.exs") }
        if contents.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
            reasons.append("xcodeproj")
        }

        return reasons.isEmpty ? nil : reasons
    }

    private func directChildDirectories(of rootURL: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let entries = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        return entries.filter { (try? $0.resourceValues(forKeys: Set(keys)).isDirectory) == true }
    }

    private func shouldSkipCandidateDirectory(_ directoryURL: URL) -> Bool {
        let lowercasedName = directoryURL.lastPathComponent.lowercased()
        let ignoredNames: Set<String> = [
            ".agent-handoff",
            ".build",
            ".claude",
            ".codex",
            ".git",
            ".idea",
            ".vscode",
            "__pycache__",
            "application support",
            "caches",
            "deriveddata",
            "dist",
            "dist-runtime",
            "library",
            "logs",
            "node_modules",
            "pods",
        ]

        if ignoredNames.contains(lowercasedName) {
            return true
        }
        return shouldExcludeScanPath(directoryURL.path)
    }

    private func shouldExcludeScanPath(_ path: String) -> Bool {
        if isAgentInternalPath(path) {
            return true
        }

        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        let ignoredComponents: Set<String> = [
            ".claude",
            ".codex",
            ".git",
            ".idea",
            ".vscode",
            "__pycache__",
            "application support",
            "caches",
            "deriveddata",
            "dist-runtime",
            "downloads",
            "library",
            "logs",
            "node_modules",
            "outputs",
            "pretrained_models",
            "proxy-dump",
            "proxy-logs",
            "references",
            "tmp",
            "training",
            "vendor",
            "weights",
            ".build",
            ".venv",
        ]
        let components = URL(fileURLWithPath: normalized).pathComponents.map { $0.lowercased() }
        return components.contains(where: ignoredComponents.contains)
    }

    private func isAgentProjectContainerPath(_ path: String) -> Bool {
        Set(suggestedScanRootPaths()).contains(path)
    }

    private func discoveryDepth(for rootURL: URL) -> Int {
        if isAgentProjectContainerPath(rootURL.path) {
            return 3
        }
        return detectionReasons(for: rootURL) == nil ? 2 : 0
    }

    private func hasSavedHandoffSession(at projectURL: URL) -> Bool {
        let sessionsDir = HandoffPaths(projectURL: projectURL).sessionsDir
        guard let entries = try? fileManager.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return false
        }

        return entries.contains { entry in
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return false
            }
            return fileManager.fileExists(atPath: entry.appendingPathComponent("session.json", isDirectory: false).path)
        }
    }

    private func collapseNestedProjects(_ projects: [DiscoveredProject], knownProjectPaths: Set<String>) -> [DiscoveredProject] {
        let sorted = projects.sorted { lhs, rhs in
            let lhsCount = lhs.url.standardizedFileURL.pathComponents.count
            let rhsCount = rhs.url.standardizedFileURL.pathComponents.count
            if lhsCount != rhsCount { return lhsCount < rhsCount }
            return lhs.url.path.localizedCaseInsensitiveCompare(rhs.url.path) == .orderedAscending
        }

        var kept: [DiscoveredProject] = []
        for project in sorted {
            let path = project.url.standardizedFileURL.path
            let isKnown = knownProjectPaths.contains(path)
            let hasSession = hasSavedHandoffSession(at: project.url)
            let hasAgentHandoff = project.reasons.contains(".agent-handoff")

            let isNestedUnderKept = kept.contains { keptProject in
                let keptPath = keptProject.url.standardizedFileURL.path
                return path != keptPath && path.hasPrefix("\(keptPath)/")
            }

            if isNestedUnderKept && !hasSession && !(isKnown && hasAgentHandoff) {
                continue
            }

            kept.append(project)
        }

        return kept
    }

    private func hasStrongProjectSignals(_ reasons: [String]) -> Bool {
        let strongSignals: Set<String> = [
            ".agent-handoff",
            "Package.swift",
            "package.json",
            "pyproject.toml",
            "Cargo.toml",
            "go.mod",
            "pnpm-workspace.yaml",
            "pom.xml",
            "build.gradle",
            "build.gradle.kts",
            "Gemfile",
            "composer.json",
            "mix.exs",
            "xcodeproj",
        ]
        return !strongSignals.isDisjoint(with: Set(reasons))
    }

    private func projectPriority(for project: DiscoveredProject) -> Int {
        var score = 0
        for reason in project.reasons {
            switch reason {
            case ".agent-handoff":
                score += 120
            case ".git":
                score += 20
            default:
                score += 40
            }
        }
        return score
    }

    private func ensureProjectHandoff(at projectURL: URL, language: AppLanguage) throws -> ProjectMetadata {
        let handoffPaths = HandoffPaths(projectURL: projectURL)

        try fileManager.createDirectory(at: handoffPaths.handoffDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: handoffPaths.sessionsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: handoffPaths.runtimeDir, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: handoffPaths.projectJsonURL.path) {
            let data = try Data(contentsOf: handoffPaths.projectJsonURL)
            let metadata = try decoder.decode(ProjectMetadata.self, from: data)
            return metadata
        }

        let now = Date()
        let metadata = ProjectMetadata(
            name: projectURL.lastPathComponent,
            path: projectURL.path,
            createdAt: now,
            updatedAt: now,
            activeSessionID: nil
        )
        try writeProjectMetadata(metadata, for: projectURL)
        try updateActiveFiles(projectMetadata: metadata, session: nil, language: language)
        return metadata
    }

    private func loadSessions(for projectURL: URL) throws -> [SessionBundle] {
        let directory = HandoffPaths(projectURL: projectURL).sessionsDir
        guard fileManager.fileExists(atPath: directory.path) else { return [] }

        let entries = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return try entries
            .filter { $0.hasDirectoryPath }
            .compactMap { try loadSession(projectURL: projectURL, sessionID: $0.lastPathComponent) }
    }

    private func loadSession(projectURL: URL, sessionID: String) throws -> SessionBundle? {
        let handoffPaths = HandoffPaths(projectURL: projectURL)
        let folder = handoffPaths.sessionDir(sessionID)
        let metadataURL = handoffPaths.sessionJsonURL(sessionID)
        guard fileManager.fileExists(atPath: metadataURL.path) else { return nil }

        let metadataData = try Data(contentsOf: metadataURL)
        let metadata = try decoder.decode(SessionMetadata.self, from: metadataData)
        let documents = Dictionary(uniqueKeysWithValues: HandoffDocumentType.allCases.map { type in
            let value = (try? String(contentsOf: handoffPaths.handoffMarkdownURL(sessionID, name: type.rawValue), encoding: .utf8)) ?? ""
            return (type, value)
        })
        return SessionBundle(metadata: metadata, folderPath: folder.path, documents: documents)
    }

    private func fallbackSessionID(from sessions: [SessionBundle]) -> String? {
        if let primary = sessions.first(where: { $0.metadata.isPrimary && !$0.metadata.isArchived }) {
            return primary.metadata.id
        }
        if let defaultSession = sessions.first(where: { !$0.metadata.isArchived && ($0.metadata.name == "Default Session" || $0.metadata.name == "默认会话") }) {
            return defaultSession.metadata.id
        }
        if let active = sessions.first(where: { !$0.metadata.isArchived }) {
            return active.metadata.id
        }
        return sessions.first?.metadata.id
    }

    private func starterDocuments(projectPath: String, sessionName: String, sessionID: String, language: AppLanguage) -> [HandoffDocumentType: String] {
        let projectName = URL(fileURLWithPath: projectPath).lastPathComponent
        if language == .zhHans {
            return [
                .projectContext: buildProjectContextDocument(
                    projectURL: URL(fileURLWithPath: projectPath),
                    language: language,
                    generatedAt: Date()
                ),
                .conversationLog: starterConversationLogDocument(projectPath: projectPath, sessionName: sessionName, language: language),
                .currentState: """
                # 当前状态

                - 项目：\(projectName)
                - 会话：\(sessionName)
                - 会话 ID：\(sessionID)
                - 当前 Agent：Codex
                - 最后更新：\(displayDate(Date(), language: language))
                - 项目目标：在 Codex 与 Claude 之间通过提示词和 .agent-handoff 无缝续接同一个项目会话。
                - 当前进展：已创建交接会话，并生成项目内容快照。
                - 已完成内容：导入项目；创建默认 handoff 文档；准备 Agent 切换提示词。
                - 当前阻塞：
                - 重要文件：PROJECT_CONTEXT.md、CURRENT_STATE.md、TODO.md、CHANGELOG.md
                - 下一步建议：点击“切换到 Claude”或“切换到 Codex”，复制提示词到新 Agent 会话继续。
                """,
                .todo: """
                # 待办事项

                ## 高优先级
                - [ ] 每轮切换前确认上一位 Agent 已把用户要求、完成内容、修改文件和验证结果写入 handoff。

                ## 中优先级

                ## 低优先级

                ## 已完成
                """,
                .decisions: """
                # 决策记录

                ## 当前有效决策

                ## 已废弃决策

                ## 决策原因
                """,
                .changelog: """
                # 变更记录

                ## \(displayDate(Date(), language: language)) - Agent 名称

                - 修改内容：
                - 测试情况：
                - 注意事项：
                """,
                .openQuestions: """
                # 待确认问题

                ## 问题

                ## 阻塞点

                ## 需要用户确认
                """,
            ]
        }

        return [
            .projectContext: buildProjectContextDocument(
                projectURL: URL(fileURLWithPath: projectPath),
                language: language,
                generatedAt: Date()
            ),
            .conversationLog: starterConversationLogDocument(projectPath: projectPath, sessionName: sessionName, language: language),
            .currentState: """
            # Current State

            - Project: \(projectName)
            - Session: \(sessionName)
            - Session ID: \(sessionID)
            - Current Agent: Codex
            - Last Updated: \(displayDate(Date(), language: language))
            - Goal: Continue one project conversation across Codex and Claude using prompts plus .agent-handoff.
            - Current Progress: Handoff session created and project context snapshot generated.
            - Completed Work: Imported project; created default handoff documents; prepared agent switch prompts.
            - Current Blockers:
            - Important Files: PROJECT_CONTEXT.md, CURRENT_STATE.md, TODO.md, CHANGELOG.md
            - Next Recommended Steps: Click "Switch to Claude" or "Switch to Codex", then paste the copied prompt into the new agent conversation.
            """,
            .todo: """
            # TODO

            ## High Priority
            - [ ] Before every switch, make sure the previous agent recorded the user request, completed work, changed files, and verification results in handoff.

            ## Medium Priority

            ## Low Priority

            ## Done
            """,
            .decisions: """
            # Decisions

            ## Active Decisions

            ## Deprecated Decisions

            ## Rationale
            """,
            .changelog: """
            # Changelog

            ## \(displayDate(Date(), language: language)) - Agent Name

            - Changes:
            - Tests:
            - Notes:
            """,
            .openQuestions: """
            # Open Questions

            ## Questions

            ## Blockers

            ## Needs User Confirmation
            """,
        ]
    }

    private func starterConversationLogDocument(projectPath: String, sessionName: String, language: AppLanguage) -> String {
        if language == .zhHans {
            return """
            # 自动对话捕获

            - 项目路径：\(projectPath)
            - 会话：\(sessionName)
            - 状态：等待 App 捕获本机 Codex / Claude 相关会话。
            - 刷新方式：点击“切换到 Claude / Codex”或“一键更新交接文件”时刷新。
            """
        }

        return """
        # Automatic Conversation Capture

        - Project Path: \(projectPath)
        - Session: \(sessionName)
        - Status: Waiting for Agent Console to capture related local Codex / Claude conversations.
        - Refresh: "Switch to Claude / Codex" and "Update Handoff Now" refresh it.
        """
    }

    private func writeSession(_ session: SessionBundle) throws {
        let folder = URL(fileURLWithPath: session.folderPath)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: folder.appendingPathComponent("PROMPTS", isDirectory: true), withIntermediateDirectories: true)
        let metadataData = try encoder.encode(session.metadata)
        try writeData(metadataData, to: folder.appendingPathComponent("session.json", isDirectory: false))

        for type in HandoffDocumentType.allCases {
            let text = session.documents[type] ?? ""
            try writeText(text, to: folder.appendingPathComponent(type.rawValue, isDirectory: false))
        }
    }

    private func updateActiveFiles(projectMetadata: ProjectMetadata, session: SessionBundle?, language: AppLanguage) throws {
        let projectURL = URL(fileURLWithPath: projectMetadata.path)
        let handoffPaths = HandoffPaths(projectURL: projectURL)
        let now = Date()

        let activeProject = if language == .zhHans {
            """
            # 当前项目

            - 项目名称：\(projectMetadata.name)
            - 项目路径：\(projectMetadata.path)
            - 当前会话 ID：\(projectMetadata.activeSessionID ?? "无")
            - 最后更新：\(displayDate(now, language: language))
            """
        } else {
            """
            # Active Project

            - Name: \(projectMetadata.name)
            - Path: \(projectMetadata.path)
            - Active Session ID: \(projectMetadata.activeSessionID ?? "None")
            - Last Updated: \(displayDate(now, language: language))
            """
        }
        try writeText(activeProject, to: handoffPaths.activeProjectURL)

        let activeSession = if let session {
            if language == .zhHans {
                """
                # 当前会话

                - 会话名称：\(session.metadata.name)
                - 会话 ID：\(session.metadata.id)
                - 当前 Agent：\(session.metadata.currentAgent.label(for: language))
                - PROJECT_CONTEXT.md：\(URL(fileURLWithPath: session.folderPath).appendingPathComponent(HandoffDocumentType.projectContext.rawValue, isDirectory: false).path)
                - CONVERSATION_LOG.md：\(URL(fileURLWithPath: session.folderPath).appendingPathComponent(HandoffDocumentType.conversationLog.rawValue, isDirectory: false).path)
                - CURRENT_STATE.md：\(URL(fileURLWithPath: session.folderPath).appendingPathComponent(HandoffDocumentType.currentState.rawValue, isDirectory: false).path)
                - TODO.md：\(URL(fileURLWithPath: session.folderPath).appendingPathComponent(HandoffDocumentType.todo.rawValue, isDirectory: false).path)
                - DECISIONS.md：\(URL(fileURLWithPath: session.folderPath).appendingPathComponent(HandoffDocumentType.decisions.rawValue, isDirectory: false).path)
                - CHANGELOG.md：\(URL(fileURLWithPath: session.folderPath).appendingPathComponent(HandoffDocumentType.changelog.rawValue, isDirectory: false).path)
                - OPEN_QUESTIONS.md：\(URL(fileURLWithPath: session.folderPath).appendingPathComponent(HandoffDocumentType.openQuestions.rawValue, isDirectory: false).path)
                """
            } else {
                """
                # Active Session

                - Name: \(session.metadata.name)
                - Session ID: \(session.metadata.id)
                - Current Agent: \(session.metadata.currentAgent.label(for: language))
                - PROJECT_CONTEXT.md: \(URL(fileURLWithPath: session.folderPath).appendingPathComponent(HandoffDocumentType.projectContext.rawValue, isDirectory: false).path)
                - CONVERSATION_LOG.md: \(URL(fileURLWithPath: session.folderPath).appendingPathComponent(HandoffDocumentType.conversationLog.rawValue, isDirectory: false).path)
                - CURRENT_STATE.md: \(URL(fileURLWithPath: session.folderPath).appendingPathComponent(HandoffDocumentType.currentState.rawValue, isDirectory: false).path)
                - TODO.md: \(URL(fileURLWithPath: session.folderPath).appendingPathComponent(HandoffDocumentType.todo.rawValue, isDirectory: false).path)
                - DECISIONS.md: \(URL(fileURLWithPath: session.folderPath).appendingPathComponent(HandoffDocumentType.decisions.rawValue, isDirectory: false).path)
                - CHANGELOG.md: \(URL(fileURLWithPath: session.folderPath).appendingPathComponent(HandoffDocumentType.changelog.rawValue, isDirectory: false).path)
                - OPEN_QUESTIONS.md: \(URL(fileURLWithPath: session.folderPath).appendingPathComponent(HandoffDocumentType.openQuestions.rawValue, isDirectory: false).path)
                """
            }
        } else {
            language == .zhHans
                ? """
                # 当前会话

                当前还没有活动会话。请先在 Agent Console 中创建一个。
                """
                : """
                # Active Session

                No active session yet. Create one from Agent Console.
                """
        }
        try writeText(activeSession, to: handoffPaths.activeSessionURL)
    }

    private func writeProjectMetadata(_ metadata: ProjectMetadata, for projectURL: URL) throws {
        let data = try encoder.encode(metadata)
        try writeData(data, to: HandoffPaths(projectURL: projectURL).projectJsonURL)
    }

    private func makeSessionID() -> String {
        "session-\(timestampString(Date()))-\(UUID().uuidString.prefix(4).lowercased())"
    }

    private func timestampString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    func displayDate(_ date: Date, language: AppLanguage) -> String {
        localizedDateTime(date, language: language)
    }

    private func syncEntryDate(_ date: Date, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .zhHans ? "zh_Hans_CN" : "en_US_POSIX")
        formatter.dateFormat = language == .zhHans ? "yyyy-MM-dd HH:mm" : "MMM d, yyyy h:mm a"
        return formatter.string(from: date)
    }

    private func defaultSessionName(language: AppLanguage) -> String {
        language == .zhHans
            ? "会话 \(displayDate(Date(), language: language))"
            : "Session \(displayDate(Date(), language: language))"
    }

    private func buildPromptBody(
        language: AppLanguage,
        template: String,
        direction: String,
        sourceAgent: AgentKind,
        targetAgent: AgentKind,
        project: ProjectSummary,
        session: SessionBundle,
        activeProjectPath: String,
        activeSessionPath: String,
        documentPaths: [HandoffDocumentType: String],
        gitSummary: String,
        isGitRepository: Bool
    ) -> String {
        let projectContextPath = documentPaths[.projectContext] ?? ""
        let conversationLogPath = documentPaths[.conversationLog] ?? ""
        let currentStatePath = documentPaths[.currentState] ?? ""
        let todoPath = documentPaths[.todo] ?? ""
        let decisionsPath = documentPaths[.decisions] ?? ""
        let changelogPath = documentPaths[.changelog] ?? ""
        let openQuestionsPath = documentPaths[.openQuestions] ?? ""
        let codeChangeRuleZH = isGitRepository
            ? "修改代码前请先检查 git status。"
            : "修改代码前请先检查当前项目文件和 .agent-handoff；不要依赖 git status / git diff 作为主要检查方式。"
        let codeChangeRuleEN = isGitRepository
            ? "Check git status before modifying code."
            : "Check the current project files and .agent-handoff before modifying code; do not rely on git status / git diff as the primary check."
        let summaryTitleZH = isGitRepository ? "Git 摘要" : "项目检查摘要"
        let summaryTitleEN = isGitRepository ? "Git Summary" : "Project Check Summary"

        if language == .zhHans {
            return """
            \(template)

            你正在通过 Agent Console 接手一个项目会话。
            这不是新任务说明，而是一次“续接同一个项目会话”的入口；读完下方文件后，请像仍在上一位 Agent 的同一段聊天里一样继续。

            【交接方向】
            \(direction)

            【你的身份】
            目标 Agent：\(targetAgent.rawValue)
            上一位 Agent：\(sourceAgent.rawValue)

            【项目】
            项目名称：\(project.metadata.name)
            项目路径：\(project.metadata.path)
            当前会话：\(session.metadata.name)
            会话 ID：\(session.metadata.id)

            【重要要求】
            1. 请不要依赖之前的聊天历史。
            2. 请只以当前项目目录和 .agent-handoff 文件为准；不要要求用户复述上一轮内容。
            3. 请不要读取其他项目。
            4. 请不要写入或泄露 API key、token、cookie、密码、私钥或 .env 内容。
            5. \(codeChangeRuleZH)
            6. 完成工作后必须更新交接文件，尤其要记录用户本轮提出的要求、你完成了什么、修改了哪些文件、如何验证。
            7. 如果用户随时切走，请把已知进展即时写入 handoff；不要等用户再次提醒。
            8. 请使用中文回复，并用中文更新交接文件。

            【请先读取这些文件】
            - \(activeProjectPath)
            - \(activeSessionPath)
            - \(projectContextPath)
            - \(conversationLogPath)
            - \(currentStatePath)
            - \(todoPath)
            - \(decisionsPath)
            - \(changelogPath)
            - \(openQuestionsPath)

            【第一步必须回复交接读取回执】
            请你读取上述文件后，先回复下面格式：

            【交接读取回执】
            - 已完成切换：\(direction)
            - 已读取项目路径：
            - 已读取会话：
            - 已读取 ACTIVE_PROJECT.md：是/否
            - 已读取 ACTIVE_SESSION.md：是/否
            - 已读取 PROJECT_CONTEXT.md：是/否
            - 已读取 CONVERSATION_LOG.md：是/否
            - 已读取 CURRENT_STATE.md：是/否
            - 已读取 TODO.md：是/否
            - 已读取 DECISIONS.md：是/否
            - 已读取 CHANGELOG.md：是/否
            - 已读取 OPEN_QUESTIONS.md：是/否
            - 最近一次记录的 Agent：
            - 当前下一步任务：
            - 无法读取的文件：

            规则：
            - 不要猜测。
            - 没读到就写“否”或“未读取到”。
            - 回执之后，请用中文总结当前状态。
            - 总结时请明确：上一位 Agent 做了什么、用户最近要求是什么、现在应该从哪里继续。
            - 如果需要我确认下一步，请停下来问我。
            - 如果任务已经明确，再继续执行。

            【\(summaryTitleZH)】
            \(gitSummary)

            【完成工作后】
            请更新：
            - PROJECT_CONTEXT.md（如果项目结构或关键文件有变化）
            - CONVERSATION_LOG.md（App 会在切换/一键更新时捕获本机相关记录；你也可以追加本轮关键聊天摘要）
            - CURRENT_STATE.md
            - TODO.md
            - CHANGELOG.md
            - 如有技术决策，更新 DECISIONS.md
            - 如有未解决问题，更新 OPEN_QUESTIONS.md
            """
        }

        return """
        \(template)

        You are taking over a project session through Agent Console.
        This is not a fresh task brief; it is a continuation entry for the same project conversation. After reading the files below, continue as if you were still in the previous agent's conversation.

        [Handoff Direction]
        \(direction)

        [Your Role]
        Target Agent: \(targetAgent.rawValue)
        Previous Agent: \(sourceAgent.rawValue)

        [Project]
        Project Name: \(project.metadata.name)
        Project Path: \(project.metadata.path)
        Current Session: \(session.metadata.name)
        Session ID: \(session.metadata.id)

        [Important Rules]
        1. Do not rely on previous chat history.
        2. Use only the current project directory and the .agent-handoff files as the source of truth; do not ask the user to restate the previous round.
        3. Do not read other projects.
        4. Do not write or expose API keys, tokens, cookies, passwords, private keys, or .env contents.
        5. \(codeChangeRuleEN)
        6. Update the handoff files after completing work, especially the user's latest request, what you completed, changed files, and verification.
        7. If the user switches away at any time, write known progress into handoff immediately; do not wait for another reminder.
        8. Reply in English and update the handoff files in English.

        [Read These Files First]
        - \(activeProjectPath)
        - \(activeSessionPath)
        - \(projectContextPath)
        - \(conversationLogPath)
        - \(currentStatePath)
        - \(todoPath)
        - \(decisionsPath)
        - \(changelogPath)
        - \(openQuestionsPath)

        [First Response Must Be a Handoff Read Receipt]
        After reading the files above, reply using this format:

        [Handoff Read Receipt]
        - Completed switch: \(direction)
        - Project path read:
        - Session read:
        - ACTIVE_PROJECT.md read: yes/no
        - ACTIVE_SESSION.md read: yes/no
        - PROJECT_CONTEXT.md read: yes/no
        - CONVERSATION_LOG.md read: yes/no
        - CURRENT_STATE.md read: yes/no
        - TODO.md read: yes/no
        - DECISIONS.md read: yes/no
        - CHANGELOG.md read: yes/no
        - OPEN_QUESTIONS.md read: yes/no
        - Most recent recorded agent:
        - Current next task:
        - Files that could not be read:

        Rules:
        - Do not guess.
        - If a file was not read, write "no" or "not read".
        - After the receipt, summarize the current state in English.
        - In the summary, state what the previous agent did, the user's latest request, and where work should continue.
        - If you need my confirmation, stop and ask me.
        - If the task is clear, continue.

        [\(summaryTitleEN)]
        \(gitSummary)

        [After Completing Work]
        Update:
        - PROJECT_CONTEXT.md if project structure or important files changed
        - CONVERSATION_LOG.md; Agent Console captures local matching records on switch/manual update, and you may append a short summary of this round
        - CURRENT_STATE.md
        - TODO.md
        - CHANGELOG.md
        - DECISIONS.md if a technical decision was made
        - OPEN_QUESTIONS.md if anything remains unresolved
        """
    }

    private func templateText(sourceAgent: AgentKind, targetAgent: AgentKind, language: AppLanguage, templates: PromptTemplateSet) -> String {
        let slot: PromptTemplateSlot
        switch (sourceAgent, targetAgent, language) {
        case (.claude, .codex, .zhHans):
            slot = .claudeToCodexZH
        case (.claude, .codex, .en):
            slot = .claudeToCodexEN
        case (_, .codex, .zhHans):
            slot = .claudeToCodexZH
        case (_, .codex, .en):
            slot = .claudeToCodexEN
        case (_, .claude, .zhHans):
            slot = .codexToClaudeZH
        case (_, .claude, .en):
            slot = .codexToClaudeEN
        default:
            slot = language == .zhHans ? .codexToClaudeZH : .codexToClaudeEN
        }

        let raw = templates.value(for: slot).trimmingCharacters(in: .whitespacesAndNewlines)
        let lockedRules = language == .zhHans
            ? """

            【Agent Console 锁定安全规则】
            - 必须读取 ACTIVE_PROJECT.md、ACTIVE_SESSION.md、PROJECT_CONTEXT.md、CONVERSATION_LOG.md 和当前 session 的 handoff 文件。
            - 不要读取其他项目。
            - 不要写入、记录、上传或泄露 token、cookie、API key、密码、私钥、auth.json 或 .env 内容。
            - 完成后必须更新 handoff 文件；如果用户中途切走，也必须把已知进展即时写入 handoff。
            """
            : """

            [Agent Console Locked Safety Rules]
            - Read ACTIVE_PROJECT.md, ACTIVE_SESSION.md, PROJECT_CONTEXT.md, CONVERSATION_LOG.md, and the current session handoff files.
            - Do not read other projects.
            - Do not write, log, upload, or expose tokens, cookies, API keys, passwords, private keys, auth.json, or .env contents.
            - Update the handoff files after completing work; if the user switches away mid-task, immediately write known progress into handoff.
            """
        return raw.isEmpty ? lockedRules.trimmingCharacters(in: .whitespacesAndNewlines) : raw + lockedRules
    }

    private func mergeCurrentStateSnapshot(
        existing: String,
        project: ProjectSummary,
        session: SessionBundle,
        gitSnapshot: GitSnapshot,
        language: AppLanguage,
        promptDirection: String,
        updatedAt: Date,
        currentPhase: String? = nil
    ) -> String {
        let startMarker = "<!-- AGENT_CONSOLE_SYNC_CURRENT_STATE_START -->"
        let endMarker = "<!-- AGENT_CONSOLE_SYNC_CURRENT_STATE_END -->"
        let block = buildCurrentStateSnapshotBlock(
            project: project,
            session: session,
            gitSnapshot: gitSnapshot,
            language: language,
            promptDirection: promptDirection,
            updatedAt: updatedAt,
            startMarker: startMarker,
            endMarker: endMarker,
            currentPhase: currentPhase
        )
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            let header = language == .zhHans ? "# 当前状态" : "# Current State"
            return "\(header)\n\n\(block)"
        }

        if let startRange = trimmed.range(of: startMarker),
           let endRange = trimmed.range(of: endMarker),
           startRange.lowerBound < endRange.upperBound {
            let prefix = trimmed[..<startRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = trimmed[endRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return [prefix, block, suffix]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }

        return "\(trimmed)\n\n\(block)"
    }

    private func buildCurrentStateSnapshotBlock(
        project: ProjectSummary,
        session: SessionBundle,
        gitSnapshot: GitSnapshot,
        language: AppLanguage,
        promptDirection: String,
        updatedAt: Date,
        startMarker: String,
        endMarker: String,
        currentPhase: String? = nil
    ) -> String {
        let receipt = session.metadata.handoffReceiptStatus.label(for: language)
        let gitSummary = gitSnapshot.summary(for: language)
        let phaseZH = currentPhase ?? "手动导入项目 + Agent 切换续接"
        let phaseEN = currentPhase ?? "Manual project import + agent handoff continuation"

        if language == .zhHans {
            return """
            \(startMarker)
            ## Agent Console 续接状态

            - 项目：\(project.metadata.name)
            - 项目路径：\(project.metadata.path)
            - 会话：\(session.metadata.name)
            - 当前 Agent：\(session.metadata.currentAgent.label(for: language))
            - 最后更新：\(displayDate(updatedAt, language: language))
            - 当前阶段：\(phaseZH)
            - Git 状态：\(gitSummary)
            - 提示词方向：\(promptDirection)
            - 回执状态：\(receipt)
            - Handoff 路径：\(HandoffPaths(projectURL: URL(fileURLWithPath: project.metadata.path)).handoffDir.path)
            - Session 文件夹：\(session.folderPath)
            - 项目内容快照：\(URL(fileURLWithPath: session.folderPath).appendingPathComponent(HandoffDocumentType.projectContext.rawValue, isDirectory: false).path)
            - 自动对话捕获：\(URL(fileURLWithPath: session.folderPath).appendingPathComponent(HandoffDocumentType.conversationLog.rawValue, isDirectory: false).path)

            ## 续接规则
            - 每次点击“切换到 Claude / Codex”都会先从磁盘重新加载当前 handoff，再刷新 PROJECT_CONTEXT.md 和 CONVERSATION_LOG.md，最后生成并复制提示词。
            - App 不在运行期定时重写大文件；切换 Agent 和“一键更新交接文件”时会捕获本机相关记录并写入 CONVERSATION_LOG.md。
            - 新 Agent 只需要粘贴提示词、读取列出的文件，就能知道项目位置、上下文、上一轮完成内容、用户最近要求和下一步。
            - 当前 Agent 完成一轮工作前，必须把真实用户要求、修改内容、涉及文件、验证结果写入 CURRENT_STATE.md 与 CHANGELOG.md。

            ## 更新检测
            - App 主界面会显示最近一次交接同步时间。
            - 如果你怀疑当前 Agent 没来得及写入，点击“一键更新交接文件”即可立即刷新项目快照、自动对话捕获和状态块。
            - “一键更新交接文件”会扫描最新 CONVERSATION_LOG.md，自动识别目标 Agent 在本次切换后写出的交接读取回执。

            ## 下一步建议
            - 继续按“导入项目 → 切换 Agent → 复制提示词 → 新 Agent 读取 handoff → 继续修改项目”的流程使用。
            - 切换前不需要额外刷新；切换按钮会自动刷新上下文。
            \(endMarker)
            """
        }

        return """
        \(startMarker)
        ## Agent Console Continuation State

        - Project: \(project.metadata.name)
        - Project Path: \(project.metadata.path)
        - Session: \(session.metadata.name)
        - Current Agent: \(session.metadata.currentAgent.label(for: language))
        - Last Updated: \(displayDate(updatedAt, language: language))
        - Current Phase: \(phaseEN)
        - Git Status: \(gitSummary)
        - Prompt Direction: \(promptDirection)
        - Receipt Status: \(receipt)
        - Handoff Path: \(HandoffPaths(projectURL: URL(fileURLWithPath: project.metadata.path)).handoffDir.path)
        - Session Folder: \(session.folderPath)
        - Project Context Snapshot: \(URL(fileURLWithPath: session.folderPath).appendingPathComponent(HandoffDocumentType.projectContext.rawValue, isDirectory: false).path)
        - Automatic Conversation Capture: \(URL(fileURLWithPath: session.folderPath).appendingPathComponent(HandoffDocumentType.conversationLog.rawValue, isDirectory: false).path)

        ## Continuation Rules
        - Every "Switch to Claude / Codex" click reloads the current handoff from disk, refreshes PROJECT_CONTEXT.md and CONVERSATION_LOG.md, then generates and copies the prompt.
        - The app does not rewrite large files on a timer; agent switching and "Update Handoff Now" capture local matching records into CONVERSATION_LOG.md.
        - The new agent only needs the pasted prompt and the listed files to know the project path, context, previous work, user's latest request, and next step.
        - Before ending a work round, the current agent must record the real user request, changes, files touched, and verification in CURRENT_STATE.md and CHANGELOG.md.

        ## Update Check
        - The main UI shows the most recent handoff sync time.
        - If you suspect the current agent did not write in time, click "Update Handoff Now" to immediately refresh project context, automatic conversation capture, and the state block.
        - "Update Handoff Now" scans the latest CONVERSATION_LOG.md and auto-detects the target agent's handoff read receipt written after the current switch.

        ## Next Recommended Steps
        - Continue using the "import project -> switch agent -> copy prompt -> new agent reads handoff -> keep editing" flow.
        - No extra refresh is needed before switching; the switch button refreshes context automatically.
        \(endMarker)
        """
    }

    private func extractPhase(from stateContent: String, language: AppLanguage) -> String? {
        let lines = stateContent.components(separatedBy: .newlines)
        let zhs = language == .zhHans
        let phaseKey = zhs ? "当前阶段：" : "Current Phase:"
        let goalKey = zhs ? "项目目标：" : "Goal:"
        let progressKey = zhs ? "当前进展：" : "Current Progress:"

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("<!--") else { continue }

            if trimmed.hasPrefix("- \(phaseKey)") {
                let value = trimmed.replacingOccurrences(of: "- \(phaseKey)", with: "").trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
            if trimmed.hasPrefix("- \(goalKey)") {
                let value = trimmed.replacingOccurrences(of: "- \(goalKey)", with: "").trimmingCharacters(in: .whitespaces)
                if !value.isEmpty, value.count <= 80 { return value }
            }
            if trimmed.hasPrefix("- \(progressKey)") {
                let value = trimmed.replacingOccurrences(of: "- \(progressKey)", with: "").trimmingCharacters(in: .whitespaces)
                if !value.isEmpty, value.count <= 80 { return value }
            }
        }
        return nil
    }

    private func appendChangelogEntry(
        existing: String,
        project: ProjectSummary,
        session: SessionBundle,
        gitSnapshot: GitSnapshot,
        language: AppLanguage,
        updatedAt: Date
    ) -> String {
        let entry: String
        if language == .zhHans {
            entry = """
            ## \(syncEntryDate(updatedAt, language: language)) - Codex

            ### 修改内容

            - Agent Console 在切换 Agent 前自动刷新 handoff。
            - 更新 PROJECT_CONTEXT.md 项目内容快照、CURRENT_STATE.md 续接状态和 TODO.md 自动建议。
            - 生成并保存本次 Agent 切换提示词，提示新 Agent 读取上下文后继续同一项目会话。
            - 保持安全边界：不读取或写入 token、cookie、API key、密码、私钥、auth.json 或 .env 内容。

            ### 测试情况

            - Agent Console 已完成提示词生成前的上下文刷新。
            - 当前 Agent 如有代码修改，仍需补充真实命令或 GUI 验证结果。

            ### 已知问题

            - App 无法知道未写入 handoff 的聊天内容；切换前仍需要当前 Agent 记录真实用户要求和完成内容。
            """
        } else {
            entry = """
            ## \(syncEntryDate(updatedAt, language: language)) - Codex

            ### Changes

            - Agent Console refreshed handoff before switching agents.
            - Updated PROJECT_CONTEXT.md, CURRENT_STATE.md continuation state, and TODO.md auto-suggestions.
            - Generated and saved the agent switch prompt so the next agent can continue the same project session after reading context.
            - Preserved the safety boundary: no tokens, cookies, API keys, passwords, private keys, auth.json, or .env contents are read or written.

            ### Testing

            - Agent Console refreshed context before prompt generation.
            - If the current agent changed code, it still needs to add the real command or GUI verification results.

            ### Known Issues

            - The app cannot know chat content that was not written into handoff; the current agent still needs to record the real user request and completed work before switching.
            """
        }

        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let header = language == .zhHans ? "# 变更记录" : "# Changelog"
            return "\(header)\n\n\(entry)"
        }
        return "\(trimmed)\n\n\(entry)"
    }

    private func mergeTodoSuggestions(
        existing: String,
        project: ProjectSummary,
        session: SessionBundle,
        language: AppLanguage
    ) -> String {
        let startMarker = language == .zhHans
            ? "<!-- AGENT_CONSOLE_SYNC_TODO_START -->"
            : "<!-- AGENT_CONSOLE_SYNC_TODO_START -->"
        let endMarker = language == .zhHans
            ? "<!-- AGENT_CONSOLE_SYNC_TODO_END -->"
            : "<!-- AGENT_CONSOLE_SYNC_TODO_END -->"
        let block = buildSuggestedTodoBlock(project: project, session: session, language: language, startMarker: startMarker, endMarker: endMarker)
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            let header = language == .zhHans ? "# 待办事项" : "# TODO"
            return "\(header)\n\n\(block)"
        }

        if let startRange = trimmed.range(of: startMarker),
           let endRange = trimmed.range(of: endMarker),
           startRange.lowerBound < endRange.upperBound {
            let prefix = trimmed[..<startRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = trimmed[endRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return [prefix, block, suffix]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }

        return "\(trimmed)\n\n\(block)"
    }

    private func buildSuggestedTodoBlock(
        project: ProjectSummary,
        session: SessionBundle,
        language: AppLanguage,
        startMarker: String,
        endMarker: String
    ) -> String {
        let items = language == .zhHans
            ? [
                "- [ ] 每轮完成前，把用户最新要求写入 CURRENT_STATE.md 或 CHANGELOG.md。",
                "- [ ] 每轮完成前，记录修改了哪些文件、做了哪些验证、还剩什么问题。",
                "- [ ] 切换 Agent 前直接点切换按钮；App 会自动刷新 PROJECT_CONTEXT.md 并复制提示词。",
            ]
            : [
                "- [ ] Before ending each round, write the user's latest request into CURRENT_STATE.md or CHANGELOG.md.",
                "- [ ] Before ending each round, record changed files, verification, and remaining issues.",
                "- [ ] To switch agents, click the switch button directly; the app refreshes PROJECT_CONTEXT.md and copies the prompt.",
            ]
        let title = language == .zhHans
            ? "## 自动建议"
            : "## Auto Suggestions"
        return """
        \(startMarker)
        \(title)

        \(items.joined(separator: "\n"))
        \(endMarker)
        """
    }

    private func buildProjectContextDocument(projectURL: URL, language: AppLanguage, generatedAt: Date) -> String {
        let files = collectProjectContextFiles(projectURL: projectURL)
        let treeLines = files.prefix(220).map { file in
            "- \(file.relativePath) (\(formatByteCount(file.size)))"
        }.joined(separator: "\n")
        let omittedCount = max(0, files.count - 220)
        let excerptFiles = files
            .filter(\.includeExcerpt)
            .sorted {
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                return $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
            }
            .prefix(24)

        var excerptBlocks: [String] = []
        var remainingBudget = 70_000
        for file in excerptFiles where remainingBudget > 0 {
            guard let raw = try? String(contentsOf: file.url, encoding: .utf8) else { continue }
            let excerpt = limitedContextExcerpt(raw, maxCharacters: min(remainingBudget, 8_000), maxLines: 140)
            guard !excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            remainingBudget -= excerpt.count
            excerptBlocks.append("""
            ## \(file.relativePath)

            ```\(codeFenceLanguage(for: file.url))
            \(excerpt)
            ```
            """)
        }

        if language == .zhHans {
            return """
            # 项目内容快照

            - 项目名称：\(projectURL.lastPathComponent)
            - 项目路径：\(projectURL.path)
            - 生成时间：\(displayDate(generatedAt, language: language))
            - 用途：让新 Agent 只靠提示词和 handoff 文件就能续接同一个项目会话。

            ## 安全边界
            - 已跳过 `.agent-handoff`、`.git`、`.build`、`node_modules`、构建产物、依赖目录和二进制文件。
            - 已跳过 `.env`、`auth.json`、包含 token/cookie/secret/password/private/key 等敏感命名的文件。
            - 如果项目结构变化，每次切换 Agent 时会重新生成本文件。

            ## 文件结构
            \(treeLines.isEmpty ? "- 未发现可展示的项目文件。" : treeLines)
            \(omittedCount > 0 ? "\n- 另有 \(omittedCount) 个文件已省略。" : "")

            ## 关键文件摘录
            \(excerptBlocks.isEmpty ? "未发现适合安全摘录的文本文件。" : excerptBlocks.joined(separator: "\n\n"))
            """
        }

        return """
        # Project Context Snapshot

        - Project Name: \(projectURL.lastPathComponent)
        - Project Path: \(projectURL.path)
        - Generated At: \(displayDate(generatedAt, language: language))
        - Purpose: allow the next agent to continue the same project conversation using only the prompt and handoff files.

        ## Safety Boundary
        - Skipped `.agent-handoff`, `.git`, `.build`, `node_modules`, build outputs, dependency folders, and binary files.
        - Skipped `.env`, `auth.json`, and files whose names contain token/cookie/secret/password/private/key.
        - This file is regenerated on every agent switch if the project structure changes.

        ## File Tree
        \(treeLines.isEmpty ? "- No displayable project files found." : treeLines)
        \(omittedCount > 0 ? "\n- \(omittedCount) additional files omitted." : "")

        ## Key File Excerpts
        \(excerptBlocks.isEmpty ? "No safe text excerpts found." : excerptBlocks.joined(separator: "\n\n"))
        """
    }

    private func buildConversationLogDocument(project: ProjectSummary, session: SessionBundle, language: AppLanguage, generatedAt: Date, entries: [ConversationLogEntry]) -> String {
        let body = entries.map { entry -> String in
            let label = entry.agent.label(for: language)
            let time = displayDate(entry.timestamp, language: language)
            let role = entry.role == "user"
                ? (language == .zhHans ? "用户" : "User")
                : (language == .zhHans ? "Agent" : "Agent")
            return """
            ## \(time) - \(label) / \(role)

            来源：\(entry.sourceFile)

            \(entry.text)
            """
        }.joined(separator: "\n\n")

        if language == .zhHans {
            return """
            # 自动对话捕获

            - 项目：\(project.metadata.name)
            - 项目路径：\(project.metadata.path)
            - 会话：\(session.metadata.name)
            - 生成时间：\(displayDate(generatedAt, language: language))
            - 用途：记录本机 Codex / Claude 中与当前项目路径相关的最近用户要求和 Agent 回复，降低用户中途切换时丢上下文的风险。

            ## 安全边界
            - 只读取本机 `.codex` 与 `.claude` 的本地 JSONL 会话记录。
            - 只保留命中当前项目路径或项目名的会话文件中的用户/Agent 文本消息。
            - 不读取 `.env`、`auth.json`、token、cookie、secret、password、private key 文件；疑似密钥赋值行会被脱敏。
            - 本文件会在每次切换 Agent 前和“一键更新交接文件”时刷新。

            ## 最近捕获
            \(body.isEmpty ? "未捕获到与当前项目相关的本机 Agent 对话记录。" : body)
            """
        }

        return """
        # Automatic Conversation Capture

        - Project: \(project.metadata.name)
        - Project Path: \(project.metadata.path)
        - Session: \(session.metadata.name)
        - Generated At: \(displayDate(generatedAt, language: language))
        - Purpose: record recent user requests and agent replies from local Codex / Claude sessions related to this project path, reducing context loss when the user switches mid-task.

        ## Safety Boundary
        - Reads only local `.codex` and `.claude` JSONL conversation records.
        - Keeps only user/agent text messages from files matching the current project path or project name.
        - Does not read `.env`, `auth.json`, token, cookie, secret, password, or private key files; suspicious assignment lines are redacted.
        - This file refreshes before every agent switch and when "Update Handoff Now" is used.

        ## Recent Captures
        \(body.isEmpty ? "No local agent conversation records matching this project were captured." : body)
        """
    }

    private func detectLatestHandoffReceipt(in entries: [ConversationLogEntry], for targetAgent: AgentKind, since requestedAt: Date?) -> HandoffReceiptDetection? {
        let lowerBound = requestedAt?.addingTimeInterval(-30)
        for entry in entries.reversed() {
            guard entry.role == "assistant" else { continue }
            if targetAgent != .unknown, entry.agent != targetAgent {
                continue
            }
            if let lowerBound, entry.timestamp < lowerBound {
                continue
            }
            guard let receiptText = HandoffReceiptParser.extractReceipt(in: entry.text) else {
                continue
            }
            let status = HandoffReceiptParser.detectStatus(in: receiptText)
            guard status != .pending else { continue }
            return HandoffReceiptDetection(
                status: status,
                text: receiptText,
                detectedAt: entry.timestamp,
                sourceAgent: entry.agent
            )
        }
        return nil
    }

    private func collectConversationLogEntries(projectPath: String, projectName: String) -> [ConversationLogEntry] {
        let codexFiles = collectCodexConversationFiles()
        let claudeFiles = collectClaudeConversationFiles()
        var entries: [ConversationLogEntry] = []
        let candidates = Array((codexFiles + claudeFiles).prefix(160))

        for fileURL in candidates {
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            guard text.contains(projectPath) || (!projectName.isEmpty && text.localizedCaseInsensitiveContains(projectName)) else { continue }
            let agent: AgentKind = fileURL.path.contains("/.claude/") ? .claude : .codex
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = String(line).data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if agent == .codex {
                    if let entry = parseCodexConversationLine(json, fileURL: fileURL) {
                        entries.append(entry)
                    }
                } else if let entry = parseClaudeConversationLine(json, fileURL: fileURL) {
                    entries.append(entry)
                }
            }
        }

        entries.sort { $0.timestamp < $1.timestamp }
        return entries
    }

    private func collectCodexConversationFiles() -> [URL] {
        var roots = [
            paths.homeDirectory.appendingPathComponent(".codex/sessions", isDirectory: true),
            paths.homeDirectory.appendingPathComponent(".codex/archived_sessions", isDirectory: true),
        ]
        roots = roots.filter { fileManager.fileExists(atPath: $0.path) }
        return collectJSONLFiles(roots: roots)
    }

    private func collectClaudeConversationFiles() -> [URL] {
        let root = paths.homeDirectory.appendingPathComponent(".claude/projects", isDirectory: true)
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        return collectJSONLFiles(roots: [root])
    }

    private func collectJSONLFiles(roots: [URL]) -> [URL] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date.distantPast
        var files: [(url: URL, modifiedAt: Date)] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]

        for root in roots {
            guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }
            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension.lowercased() == "jsonl" else { continue }
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true else { continue }
                let modifiedAt = values.contentModificationDate ?? Date.distantPast
                guard modifiedAt >= cutoff else { continue }
                if let size = values.fileSize, size > 20 * 1024 * 1024 { continue }
                files.append((url, modifiedAt))
            }
        }

        return files.sorted { $0.modifiedAt > $1.modifiedAt }.map(\.url)
    }

    private func parseCodexConversationLine(_ json: [String: Any], fileURL: URL) -> ConversationLogEntry? {
        guard let timestamp = parseISO8601(json["timestamp"] as? String ?? "") else { return nil }
        guard let type = json["type"] as? String else { return nil }

        if type == "response_item",
           let payload = json["payload"] as? [String: Any],
           let payloadType = payload["type"] as? String,
           payloadType == "message",
           let role = payload["role"] as? String,
           role == "user" || role == "assistant" {
            let text = extractCodexMessageText(payload["content"])
            return makeConversationEntry(agent: .codex, timestamp: timestamp, role: role, sourceFile: fileURL.lastPathComponent, text: text)
        }

        if type == "event_msg",
           let payload = json["payload"] as? [String: Any],
           let lastAgentMessage = payload["last_agent_message"] as? String {
            return makeConversationEntry(agent: .codex, timestamp: timestamp, role: "assistant", sourceFile: fileURL.lastPathComponent, text: lastAgentMessage)
        }

        return nil
    }

    private func parseClaudeConversationLine(_ json: [String: Any], fileURL: URL) -> ConversationLogEntry? {
        guard let timestamp = parseISO8601(json["timestamp"] as? String ?? "") else { return nil }
        guard let type = json["type"] as? String,
              type == "user" || type == "assistant",
              let message = json["message"] as? [String: Any],
              let role = message["role"] as? String,
              role == "user" || role == "assistant" else { return nil }
        let text = extractClaudeMessageText(message["content"])
        return makeConversationEntry(agent: .claude, timestamp: timestamp, role: role, sourceFile: fileURL.lastPathComponent, text: text)
    }

    private func extractCodexMessageText(_ content: Any?) -> String {
        guard let items = content as? [[String: Any]] else { return "" }
        return items.compactMap { item in
            item["text"] as? String
        }.joined(separator: "\n")
    }

    private func extractClaudeMessageText(_ content: Any?) -> String {
        if let string = content as? String { return string }
        guard let items = content as? [[String: Any]] else { return "" }
        return items.compactMap { item in
            guard (item["type"] as? String) == "text" else { return nil }
            return item["text"] as? String
        }.joined(separator: "\n")
    }

    private func makeConversationEntry(agent: AgentKind, timestamp: Date, role: String, sourceFile: String, text: String) -> ConversationLogEntry? {
        let sanitized = sanitizeConversationText(text)
        guard !sanitized.isEmpty else { return nil }
        return ConversationLogEntry(agent: agent, timestamp: timestamp, role: role, sourceFile: sourceFile, text: sanitized)
    }

    private func sanitizeConversationText(_ text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .prefix(28)
            .map { line -> String in
                let lower = line.lowercased()
                let looksLikeSecretAssignment = ["token", "cookie", "secret", "password", "api_key", "apikey", "private_key"].contains { lower.contains($0) }
                    && (line.contains("=") || line.contains(":"))
                return looksLikeSecretAssignment ? "[已脱敏：疑似敏感配置行]" : line
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard lines.count > 1_600 else { return lines }
        let index = lines.index(lines.startIndex, offsetBy: 1_600)
        return String(lines[..<index]) + "\n...[已截断]"
    }

    private func collectProjectContextFiles(projectURL: URL) -> [ProjectContextFile] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: projectURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [ProjectContextFile] = []
        while let url = enumerator.nextObject() as? URL {
            let relativePath = relativeContextPath(for: url, root: projectURL)
            if shouldSkipContextPath(relativePath) {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if values.isDirectory == true {
                if shouldSkipContextPath(relativePath) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true else { continue }

            let size = values.fileSize ?? 0
            guard size <= 500_000 else { continue }
            let includeExcerpt = shouldIncludeContextExcerpt(relativePath: relativePath, size: size)
            files.append(ProjectContextFile(
                url: url,
                relativePath: relativePath,
                size: size,
                priority: contextPriority(for: relativePath),
                includeExcerpt: includeExcerpt
            ))
        }

        return files.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }
    }

    private func relativeContextPath(for url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix("\(rootPath)/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func shouldSkipContextPath(_ relativePath: String) -> Bool {
        let lower = relativePath.lowercased()
        let components = lower.split(separator: "/").map(String.init)
        let ignoredComponents: Set<String> = [
            ".agent-handoff",
            ".build",
            ".git",
            ".idea",
            ".vscode",
            "build",
            "coverage",
            "deriveddata",
            "dist",
            "node_modules",
            "pods",
            "vendor",
            "__pycache__",
        ]
        if components.contains(where: ignoredComponents.contains) {
            return true
        }

        let name = components.last ?? lower
        if name == ".env" || name.hasPrefix(".env.") || name == "auth.json" {
            return true
        }

        let sensitiveFragments = ["token", "cookie", "secret", "password", "passwd", "private", "apikey", "api_key", "credential"]
        if sensitiveFragments.contains(where: { name.contains($0) }) {
            return true
        }

        let sensitiveExtensions: Set<String> = ["pem", "p12", "pfx", "key", "crt", "cer", "der", "sqlite", "db"]
        if let ext = name.split(separator: ".").last.map(String.init), sensitiveExtensions.contains(ext) {
            return true
        }

        return false
    }

    private func shouldIncludeContextExcerpt(relativePath: String, size: Int) -> Bool {
        guard size > 0, size <= 120_000 else { return false }
        let lower = relativePath.lowercased()
        let name = URL(fileURLWithPath: lower).lastPathComponent
        let importantNames: Set<String> = [
            "readme.md",
            "package.swift",
            "package.json",
            "pyproject.toml",
            "cargo.toml",
            "go.mod",
            "pnpm-workspace.yaml",
            "pom.xml",
            "build.gradle",
            "build.gradle.kts",
            "project_context.md",
        ]
        if importantNames.contains(name) { return true }

        let allowedExtensions: Set<String> = [
            "swift", "js", "jsx", "ts", "tsx", "py", "rs", "go", "java", "kt",
            "html", "css", "scss", "md", "sh", "rb", "php", "ex", "exs"
        ]
        let ext = URL(fileURLWithPath: lower).pathExtension
        guard allowedExtensions.contains(ext) else { return false }
        return lower.hasPrefix("sources/") || lower.hasPrefix("src/") || lower.hasPrefix("app/") || lower.hasPrefix("lib/") || lower.hasPrefix("tests/") || lower.hasPrefix("scripts/") || !lower.contains("/")
    }

    private func contextPriority(for relativePath: String) -> Int {
        let lower = relativePath.lowercased()
        let name = URL(fileURLWithPath: lower).lastPathComponent
        if name == "readme.md" || name == "project_context.md" { return 120 }
        if ["package.swift", "package.json", "pyproject.toml", "cargo.toml", "go.mod"].contains(name) { return 110 }
        if lower.hasPrefix("sources/") || lower.hasPrefix("src/") || lower.hasPrefix("app/") { return 90 }
        if lower.hasPrefix("tests/") { return 70 }
        if lower.hasPrefix("scripts/") { return 60 }
        return 20
    }

    private func limitedContextExcerpt(_ text: String, maxCharacters: Int, maxLines: Int) -> String {
        var result = ""
        var lineCount = 0
        for line in text.components(separatedBy: .newlines) {
            if lineCount >= maxLines { break }
            let candidate = result.isEmpty ? line : "\(result)\n\(line)"
            if candidate.count > maxCharacters { break }
            result = candidate
            lineCount += 1
        }
        if result.count < text.count {
            result += "\n...（已截断）"
        }
        return result
    }

    private func codeFenceLanguage(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "swift": return "swift"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py": return "python"
        case "rs": return "rust"
        case "go": return "go"
        case "java": return "java"
        case "kt": return "kotlin"
        case "html": return "html"
        case "css", "scss": return "css"
        case "md": return "markdown"
        case "sh": return "bash"
        case "json": return "json"
        case "toml": return "toml"
        case "yaml", "yml": return "yaml"
        default: return ""
        }
    }

    private func formatByteCount(_ value: Int) -> String {
        if value < 1024 { return "\(value) B" }
        if value < 1024 * 1024 {
            return String(format: "%.1f KB", Double(value) / 1024.0)
        }
        return String(format: "%.1f MB", Double(value) / 1024.0 / 1024.0)
    }

    private func writeText(_ text: String, to fileURL: URL) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func writeData(_ data: Data, to fileURL: URL) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}

final class GitService {
    func snapshot(for projectURL: URL) -> GitSnapshot {
        let check = run(["git", "-C", projectURL.path, "rev-parse", "--is-inside-work-tree"])
        guard check.exitCode == 0 else {
            return GitSnapshot(
                state: .unavailable,
                branch: nil,
                porcelain: "",
                diffStat: "",
                checkedAt: Date()
            )
        }

        let branch = run(["git", "-C", projectURL.path, "rev-parse", "--abbrev-ref", "HEAD"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let porcelain = run(["git", "-C", projectURL.path, "status", "--porcelain"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let diffStat = run(["git", "-C", projectURL.path, "diff", "--stat"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        return GitSnapshot(
            state: porcelain.isEmpty ? .clean : .dirty,
            branch: branch.isEmpty ? nil : branch,
            porcelain: porcelain,
            diffStat: diffStat,
            checkedAt: Date()
        )
    }

    private func run(_ arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)
            return (process.terminationStatus, output)
        } catch {
            return (1, error.localizedDescription)
        }
    }
}

final class HandoffFileWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private var onChange: (@Sendable () -> Void)?
    private let debounceQueue = DispatchQueue(label: "com.agentconsole.handoff-watcher")
    private let debounceInterval: TimeInterval = 1.5

    deinit {
        stop()
    }

    func startWatching(path: String, onChange: @escaping @Sendable () -> Void) {
        stop()
        self.onChange = onChange

        let paths = [path] as CFArray
        let rawSelf = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        var context = FSEventStreamContext(
            version: 0,
            info: rawSelf,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (_, clientInfo, _, _, _, _) in
                guard let info = clientInfo else { return }
                let watcher = Unmanaged<HandoffFileWatcher>.fromOpaque(info).takeUnretainedValue()
                let cb = watcher.onChange
                guard let cb else { return }
                Task { @MainActor in cb() }
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        )

        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, debounceQueue)
        FSEventStreamStart(stream)
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        onChange = nil
    }
}
