import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case zhHans
    case en

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zhHans:
            return "中文"
        case .en:
            return "English"
        }
    }

}

enum HandoffReceiptStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case pending
    case confirmed
    case failed

    var id: String { rawValue }

    func label(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.pending, .zhHans):
            return "待回执"
        case (.pending, .en):
            return "Pending"
        case (.confirmed, .zhHans):
            return "已确认"
        case (.confirmed, .en):
            return "Confirmed"
        case (.failed, .zhHans):
            return "读取失败"
        case (.failed, .en):
            return "Failed"
        }
    }
}

enum AgentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex = "Codex"
    case claude = "Claude"
    case unknown = "Unknown"

    var id: String { rawValue }

    func label(for language: AppLanguage) -> String {
        switch self {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        case .unknown:
            return language == .zhHans ? "未知" : "Unknown"
        }
    }
}

enum QuotaStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case available = "available"
    case exhausted = "exhausted"
    case unknown = "unknown"

    var id: String { rawValue }

    func label(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.available, .zhHans):
            return "可用"
        case (.available, .en):
            return "Available"
        case (.exhausted, .zhHans):
            return "已用尽"
        case (.exhausted, .en):
            return "Exhausted"
        case (.unknown, .zhHans):
            return "未知"
        case (.unknown, .en):
            return "Unknown"
        }
    }
}

enum ConsolePage: String, CaseIterable, Identifiable, Sendable {
    case handoff
    case prompts
    case usage
    case diagnostics
    case settings

    var id: String { rawValue }

    func label(for language: AppLanguage) -> String {
        switch self {
        case .handoff:
            return language == .zhHans ? "控制台" : "Console"
        case .prompts:
            return language == .zhHans ? "Prompt 模板" : "Prompt Templates"
        case .usage:
            return language == .zhHans ? "用量与额度" : "Usage & Quotas"
        case .diagnostics:
            return language == .zhHans ? "诊断" : "Diagnostics"
        case .settings:
            return language == .zhHans ? "设置" : "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .handoff:
            return "rectangle.3.group"
        case .prompts:
            return "text.badge.checkmark"
        case .usage:
            return "chart.bar.xaxis"
        case .diagnostics:
            return "stethoscope"
        case .settings:
            return "gearshape"
        }
    }
}

enum SessionArchiveFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case active
    case archived
    case all

    var id: String { rawValue }

    func label(for language: AppLanguage) -> String {
        switch self {
        case .active:
            return language == .zhHans ? "活动" : "Active"
        case .archived:
            return language == .zhHans ? "归档" : "Archived"
        case .all:
            return language == .zhHans ? "全部" : "All"
        }
    }
}

enum GitWorkingTreeState: String, Codable, Sendable {
    case clean
    case dirty
    case unavailable
}

struct GitSnapshot: Codable, Equatable, Sendable {
    var state: GitWorkingTreeState
    var branch: String?
    var porcelain: String
    var diffStat: String
    var checkedAt: Date

    func summary(for language: AppLanguage) -> String {
        switch (state, language) {
        case (.clean, .zhHans):
            if let branch, !branch.isEmpty {
                return "\(branch) 干净"
            }
            return "干净"
        case (.clean, .en):
            if let branch, !branch.isEmpty {
                return "\(branch) clean"
            }
            return "Clean"
        case (.dirty, .zhHans):
            let branchPrefix = branch.map { "\($0) " } ?? ""
            return "\(branchPrefix)有未提交改动"
        case (.dirty, .en):
            let branchPrefix = branch.map { "\($0) " } ?? ""
            return "\(branchPrefix)has uncommitted changes"
        case (.unavailable, .zhHans):
            return "不是 Git 仓库"
        case (.unavailable, .en):
            return "Not a Git repository"
        }
    }
}

struct ScanRoot: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var path: String
    var isDefault: Bool

    init(id: UUID = UUID(), path: String, isDefault: Bool) {
        self.id = id
        self.path = path
        self.isDefault = isDefault
    }
}

struct KnownProjectRecord: Codable, Hashable, Sendable {
    var path: String
    var name: String
    var lastSeenAt: Date
}

struct ProjectRegistry: Codable, Sendable {
    var scanRoots: [ScanRoot]
    var knownProjects: [KnownProjectRecord]
    var selectedProjectPath: String?
    var selectedSessionID: String?
    var lastScanAt: Date?
    var appLanguage: AppLanguage
    var promptTemplates: PromptTemplateSet
    var usageWorkspace: UsageWorkspace
    var autoSyncHandoff: Bool
    var lastHandoffSyncAt: Date?
    var lastHandoffSyncSummary: String?
    var sessionArchiveFilter: SessionArchiveFilter

    init(
        scanRoots: [ScanRoot],
        knownProjects: [KnownProjectRecord],
        selectedProjectPath: String?,
        selectedSessionID: String?,
        lastScanAt: Date?,
        appLanguage: AppLanguage = .zhHans,
        promptTemplates: PromptTemplateSet = .default,
        usageWorkspace: UsageWorkspace = .empty,
        autoSyncHandoff: Bool = true,
        lastHandoffSyncAt: Date? = nil,
        lastHandoffSyncSummary: String? = nil,
        sessionArchiveFilter: SessionArchiveFilter = .active
    ) {
        self.scanRoots = scanRoots
        self.knownProjects = knownProjects
        self.selectedProjectPath = selectedProjectPath
        self.selectedSessionID = selectedSessionID
        self.lastScanAt = lastScanAt
        self.appLanguage = appLanguage
        self.promptTemplates = promptTemplates
        self.usageWorkspace = usageWorkspace
        self.autoSyncHandoff = autoSyncHandoff
        self.lastHandoffSyncAt = lastHandoffSyncAt
        self.lastHandoffSyncSummary = lastHandoffSyncSummary
        self.sessionArchiveFilter = sessionArchiveFilter
    }

    static func `default`(homeDirectory: URL) -> ProjectRegistry {
        let fileManager = FileManager.default
        let roots = [
            homeDirectory.appendingPathComponent("Documents/Codex", isDirectory: true).path,
            homeDirectory.appendingPathComponent("Documents/Claude", isDirectory: true).path,
            homeDirectory.appendingPathComponent("Projects/Codex", isDirectory: true).path,
            homeDirectory.appendingPathComponent("Projects/Claude", isDirectory: true).path,
        ]
        .filter { fileManager.fileExists(atPath: $0) }
        return ProjectRegistry(
            scanRoots: roots.map { ScanRoot(path: $0, isDefault: true) },
            knownProjects: [],
            selectedProjectPath: nil,
            selectedSessionID: nil,
            lastScanAt: nil,
            appLanguage: .zhHans,
            promptTemplates: .default,
            usageWorkspace: .empty
        )
    }

    private enum CodingKeys: String, CodingKey {
        case scanRoots
        case knownProjects
        case selectedProjectPath
        case selectedSessionID
        case lastScanAt
        case appLanguage
        case promptTemplates
        case usageWorkspace
        case autoSyncHandoff
        case lastHandoffSyncAt
        case lastHandoffSyncSummary
        case sessionArchiveFilter
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scanRoots = try container.decode([ScanRoot].self, forKey: .scanRoots)
        knownProjects = try container.decode([KnownProjectRecord].self, forKey: .knownProjects)
        selectedProjectPath = try container.decodeIfPresent(String.self, forKey: .selectedProjectPath)
        selectedSessionID = try container.decodeIfPresent(String.self, forKey: .selectedSessionID)
        lastScanAt = try container.decodeIfPresent(Date.self, forKey: .lastScanAt)
        appLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? .zhHans
        promptTemplates = try container.decodeIfPresent(PromptTemplateSet.self, forKey: .promptTemplates) ?? .default
        usageWorkspace = try container.decodeIfPresent(UsageWorkspace.self, forKey: .usageWorkspace) ?? .empty
        autoSyncHandoff = try container.decodeIfPresent(Bool.self, forKey: .autoSyncHandoff) ?? true
        lastHandoffSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastHandoffSyncAt)
        lastHandoffSyncSummary = try container.decodeIfPresent(String.self, forKey: .lastHandoffSyncSummary)
        sessionArchiveFilter = try container.decodeIfPresent(SessionArchiveFilter.self, forKey: .sessionArchiveFilter) ?? .active
    }
}

struct ProjectMetadata: Codable, Sendable {
    var name: String
    var path: String
    var createdAt: Date
    var updatedAt: Date
    var activeSessionID: String?
}

struct SessionMetadata: Codable, Identifiable, Sendable {
    var id: String
    var name: String
    var currentAgent: AgentKind
    var codexQuotaStatus: QuotaStatus
    var claudeQuotaStatus: QuotaStatus
    var handoffReceiptStatus: HandoffReceiptStatus
    var lastHandoffReceiptText: String?
    var lastHandoffReceiptAt: Date?
    var lastHandoffRequestedAt: Date?
    var isArchived: Bool
    var isPrimary: Bool
    var parentSessionID: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        name: String,
        currentAgent: AgentKind,
        codexQuotaStatus: QuotaStatus,
        claudeQuotaStatus: QuotaStatus,
        handoffReceiptStatus: HandoffReceiptStatus = .pending,
        lastHandoffReceiptText: String? = nil,
        lastHandoffReceiptAt: Date? = nil,
        lastHandoffRequestedAt: Date? = nil,
        isArchived: Bool = false,
        isPrimary: Bool = false,
        parentSessionID: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.currentAgent = currentAgent
        self.codexQuotaStatus = codexQuotaStatus
        self.claudeQuotaStatus = claudeQuotaStatus
        self.handoffReceiptStatus = handoffReceiptStatus
        self.lastHandoffReceiptText = lastHandoffReceiptText
        self.lastHandoffReceiptAt = lastHandoffReceiptAt
        self.lastHandoffRequestedAt = lastHandoffRequestedAt
        self.isArchived = isArchived
        self.isPrimary = isPrimary
        self.parentSessionID = parentSessionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case currentAgent
        case codexQuotaStatus
        case claudeQuotaStatus
        case handoffReceiptStatus
        case lastHandoffReceiptText
        case lastHandoffReceiptAt
        case lastHandoffRequestedAt
        case isArchived
        case isPrimary
        case parentSessionID
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        currentAgent = try container.decode(AgentKind.self, forKey: .currentAgent)
        codexQuotaStatus = try container.decode(QuotaStatus.self, forKey: .codexQuotaStatus)
        claudeQuotaStatus = try container.decode(QuotaStatus.self, forKey: .claudeQuotaStatus)
        handoffReceiptStatus = try container.decodeIfPresent(HandoffReceiptStatus.self, forKey: .handoffReceiptStatus) ?? .pending
        lastHandoffReceiptText = try container.decodeIfPresent(String.self, forKey: .lastHandoffReceiptText)
        lastHandoffReceiptAt = try container.decodeIfPresent(Date.self, forKey: .lastHandoffReceiptAt)
        lastHandoffRequestedAt = try container.decodeIfPresent(Date.self, forKey: .lastHandoffRequestedAt)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        isPrimary = try container.decodeIfPresent(Bool.self, forKey: .isPrimary) ?? false
        parentSessionID = try container.decodeIfPresent(String.self, forKey: .parentSessionID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct HandoffReceiptDetection: Sendable {
    var status: HandoffReceiptStatus
    var text: String
    var detectedAt: Date
    var sourceAgent: AgentKind
}

enum PromptTemplateSlot: String, Codable, CaseIterable, Identifiable, Sendable {
    case codexToClaudeZH
    case claudeToCodexZH
    case codexToClaudeEN
    case claudeToCodexEN

    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .codexToClaudeZH:
            return language == .zhHans ? "Codex → Claude（中文）" : "Codex → Claude (Chinese)"
        case .claudeToCodexZH:
            return language == .zhHans ? "Claude → Codex（中文）" : "Claude → Codex (Chinese)"
        case .codexToClaudeEN:
            return language == .zhHans ? "Codex → Claude（英文）" : "Codex → Claude (English)"
        case .claudeToCodexEN:
            return language == .zhHans ? "Claude → Codex（英文）" : "Claude → Codex (English)"
        }
    }
}

struct PromptTemplateSet: Codable, Sendable {
    var codexToClaudeZH: String
    var claudeToCodexZH: String
    var codexToClaudeEN: String
    var claudeToCodexEN: String

    static let `default` = PromptTemplateSet(
        codexToClaudeZH: PromptTemplateDefaults.codexToClaudeZH,
        claudeToCodexZH: PromptTemplateDefaults.claudeToCodexZH,
        codexToClaudeEN: PromptTemplateDefaults.codexToClaudeEN,
        claudeToCodexEN: PromptTemplateDefaults.claudeToCodexEN
    )

    func value(for slot: PromptTemplateSlot) -> String {
        switch slot {
        case .codexToClaudeZH:
            return codexToClaudeZH
        case .claudeToCodexZH:
            return claudeToCodexZH
        case .codexToClaudeEN:
            return codexToClaudeEN
        case .claudeToCodexEN:
            return claudeToCodexEN
        }
    }

    mutating func setValue(_ value: String, for slot: PromptTemplateSlot) {
        switch slot {
        case .codexToClaudeZH:
            codexToClaudeZH = value
        case .claudeToCodexZH:
            claudeToCodexZH = value
        case .codexToClaudeEN:
            codexToClaudeEN = value
        case .claudeToCodexEN:
            claudeToCodexEN = value
        }
    }
}

enum PromptTemplateDefaults {
    static let codexToClaudeZH = """
    请接手当前 Agent Console 会话。你是目标 Agent：Claude；上一位 Agent：Codex。
    先读取列出的 .agent-handoff 文件，第一条回复必须给出交接读取回执。
    """

    static let claudeToCodexZH = """
    请接手当前 Agent Console 会话。你是目标 Agent：Codex；上一位 Agent：Claude。
    先读取列出的 .agent-handoff 文件，第一条回复必须给出交接读取回执。
    """

    static let codexToClaudeEN = """
    Take over the current Agent Console session. You are the target agent: Claude; the previous agent was Codex.
    Read the listed .agent-handoff files first, and make your first reply a handoff read receipt.
    """

    static let claudeToCodexEN = """
    Take over the current Agent Console session. You are the target agent: Codex; the previous agent was Claude.
    Read the listed .agent-handoff files first, and make your first reply a handoff read receipt.
    """
}

enum AccountSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case oauth = "OAuth"
    case localImport = "LocalImport"
    case api = "API"

    var id: String { rawValue }
}

enum AccountMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case subscription = "Subscription"
    case api = "API"
    case unknown = "Unknown"

    var id: String { rawValue }

    func label(for language: AppLanguage) -> String {
        switch self {
        case .subscription:
            return language == .zhHans ? "订阅模式" : "Subscription"
        case .api:
            return "API"
        case .unknown:
            return language == .zhHans ? "未知" : "Unknown"
        }
    }
}

enum UsageRange: String, Codable, CaseIterable, Identifiable, Sendable {
    case today
    case sevenDays
    case thirtyDays
    case custom

    var id: String { rawValue }

    func label(for language: AppLanguage) -> String {
        switch self {
        case .today:
            return language == .zhHans ? "今天" : "Today"
        case .sevenDays:
            return language == .zhHans ? "7 天" : "7 Days"
        case .thirtyDays:
            return language == .zhHans ? "30 天" : "30 Days"
        case .custom:
            return language == .zhHans ? "自定义" : "Custom"
        }
    }
}

struct AccountSummary: Codable, Identifiable, Sendable {
    var id: UUID
    var provider: AgentKind
    var displayName: String
    var source: AccountSource
    var mode: AccountMode
    var isActive: Bool
    var planName: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        provider: AgentKind,
        displayName: String,
        source: AccountSource,
        mode: AccountMode,
        isActive: Bool = false,
        planName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.source = source
        self.mode = mode
        self.isActive = isActive
        self.planName = planName
        self.createdAt = createdAt
    }
}

struct TokenUsageRecord: Codable, Identifiable, Sendable {
    var id: UUID
    var provider: AgentKind
    var projectPath: String?
    var sessionID: String?
    var model: String?
    var inputTokens: Int
    var outputTokens: Int
    var cacheTokens: Int
    var cost: Decimal?
    var createdAt: Date

    var totalTokens: Int {
        inputTokens + outputTokens + cacheTokens
    }
}

struct UsageWorkspace: Codable, Sendable {
    var accounts: [AccountSummary]
    var tokenRecords: [TokenUsageRecord]
    var selectedRange: UsageRange
    var customStartDate: Date?
    var customEndDate: Date?
    var activeAccountIDsByProvider: [String: UUID]

    static let empty = UsageWorkspace(
        accounts: [],
        tokenRecords: [],
        selectedRange: .today,
        customStartDate: nil,
        customEndDate: nil,
        activeAccountIDsByProvider: [:]
    )

    private enum CodingKeys: String, CodingKey {
        case accounts
        case tokenRecords
        case selectedRange
        case customStartDate
        case customEndDate
        case activeAccountIDsByProvider
    }

    init(
        accounts: [AccountSummary],
        tokenRecords: [TokenUsageRecord],
        selectedRange: UsageRange,
        customStartDate: Date?,
        customEndDate: Date?,
        activeAccountIDsByProvider: [String: UUID]
    ) {
        self.accounts = accounts
        self.tokenRecords = tokenRecords
        self.selectedRange = selectedRange
        self.customStartDate = customStartDate
        self.customEndDate = customEndDate
        self.activeAccountIDsByProvider = activeAccountIDsByProvider
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try container.decode([AccountSummary].self, forKey: .accounts)
        tokenRecords = try container.decode([TokenUsageRecord].self, forKey: .tokenRecords)
        selectedRange = try container.decodeIfPresent(UsageRange.self, forKey: .selectedRange) ?? .today
        customStartDate = try container.decodeIfPresent(Date.self, forKey: .customStartDate)
        customEndDate = try container.decodeIfPresent(Date.self, forKey: .customEndDate)
        activeAccountIDsByProvider = try container.decodeIfPresent([String: UUID].self, forKey: .activeAccountIDsByProvider) ?? [:]
    }
}

enum HandoffDocumentType: String, CaseIterable, Identifiable, Hashable, Sendable {
    case projectContext = "PROJECT_CONTEXT.md"
    case conversationLog = "CONVERSATION_LOG.md"
    case currentState = "CURRENT_STATE.md"
    case todo = "TODO.md"
    case decisions = "DECISIONS.md"
    case changelog = "CHANGELOG.md"
    case openQuestions = "OPEN_QUESTIONS.md"

    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.projectContext, .zhHans):
            return "项目内容"
        case (.projectContext, .en):
            return "Project Context"
        case (.conversationLog, .zhHans):
            return "自动对话"
        case (.conversationLog, .en):
            return "Conversation Log"
        case (.currentState, .zhHans):
            return "当前状态"
        case (.currentState, .en):
            return "Current State"
        case (.todo, .zhHans):
            return "待办"
        case (.todo, .en):
            return "TODO"
        case (.decisions, .zhHans):
            return "决策记录"
        case (.decisions, .en):
            return "Decisions"
        case (.changelog, .zhHans):
            return "变更记录"
        case (.changelog, .en):
            return "Changelog"
        case (.openQuestions, .zhHans):
            return "待确认问题"
        case (.openQuestions, .en):
            return "Open Questions"
        }
    }
}

struct SessionBundle: Identifiable, Sendable {
    var metadata: SessionMetadata
    var folderPath: String
    var documents: [HandoffDocumentType: String]

    var id: String { metadata.id }
}

struct ProjectSummary: Identifiable, Sendable {
    var metadata: ProjectMetadata
    var detectionReasons: [String]
    var gitSnapshot: GitSnapshot
    var sessions: [SessionBundle]

    var id: String { metadata.path }

    var activeSession: SessionBundle? {
        if let activeID = metadata.activeSessionID,
           let match = sessions.first(where: { $0.metadata.id == activeID }) {
            return match
        }
        return sessions.first
    }

    var displayAgent: AgentKind {
        activeSession?.metadata.currentAgent ?? .unknown
    }

    var displayUpdatedAt: Date {
        activeSession?.metadata.updatedAt ?? metadata.updatedAt
    }
}

struct GeneratedPrompt: Sendable {
    var previousAgent: AgentKind
    var targetAgent: AgentKind
    var title: String
    var body: String
    var fileName: String

    func directionLabel(for language: AppLanguage) -> String {
        "\(previousAgent.label(for: language)) → \(targetAgent.label(for: language))"
    }
}
