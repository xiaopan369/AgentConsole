import Foundation

struct AppStrings {
    let language: AppLanguage

    var appTitle: String { "Agent Console" }
    var ready: String { language == .zhHans ? "就绪。" : "Ready." }
    var settings: String { language == .zhHans ? "设置" : "Settings" }
    var languageLabel: String { language == .zhHans ? "语言" : "Language" }
    var searchProjects: String { language == .zhHans ? "搜索项目" : "Search projects" }
    var projects: String { language == .zhHans ? "项目" : "Projects" }
    var sessions: String { language == .zhHans ? "会话" : "Sessions" }
    var projectListTitle: String { language == .zhHans ? "项目列表" : "Projects" }
    var currentAgent: String { language == .zhHans ? "当前 Agent" : "Current Agent" }
    var previousAgent: String { language == .zhHans ? "上一位 Agent" : "Previous Agent" }
    var targetAgent: String { language == .zhHans ? "目标 Agent" : "Target Agent" }
    var promptDirection: String { language == .zhHans ? "提示词方向" : "Prompt Direction" }
    var codexQuota: String { language == .zhHans ? "Codex 额度" : "Codex Quota" }
    var claudeQuota: String { language == .zhHans ? "Claude 额度" : "Claude Quota" }
    var unknown: String { language == .zhHans ? "未知" : "Unknown" }
    var scanProjects: String { language == .zhHans ? "扫描项目" : "Scan Projects" }
    var rescan: String { language == .zhHans ? "重新扫描" : "Rescan" }
    var refreshHandoff: String { language == .zhHans ? "刷新交接文件" : "Refresh Handoff" }
    var refreshHandoffShort: String { language == .zhHans ? "刷新交接" : "Refresh Handoff" }
    var syncToHandoff: String { language == .zhHans ? "同步到交接文件" : "Sync to Handoff" }
    var syncToHandoffShort: String { language == .zhHans ? "同步交接" : "Sync Handoff" }
    var rescanHelp: String { language == .zhHans ? "重新扫描已配置的目录" : "Rescan configured directories" }
    var importProject: String { language == .zhHans ? "导入项目" : "Import Project" }
    var importSingleProject: String { language == .zhHans ? "导入单个项目" : "Import Project" }
    var addDirectory: String { language == .zhHans ? "添加目录" : "Add Directory" }
    var newSession: String { language == .zhHans ? "新建会话" : "New Session" }
    var switchToClaude: String { language == .zhHans ? "切换到 Claude" : "Switch to Claude" }
    var switchToCodex: String { language == .zhHans ? "切换到 Codex" : "Switch to Codex" }
    var copyPrompt: String { language == .zhHans ? "复制提示词" : "Copy Prompt" }
    var openProject: String { language == .zhHans ? "打开项目" : "Open Project" }
    var openWorkspace: String { language == .zhHans ? "打开工作台" : "Open Workspace" }
    var startupHandoffNoticeTitle: String { language == .zhHans ? "交接文件会自动更新" : "Handoff Files Update Automatically" }
    var startupHandoffNoticeBody: String {
        language == .zhHans
            ? "切换到 Claude 或 Codex 时，App 会自动刷新项目快照和交接文件。\n\n如果你不放心，也可以随时点击\n「一键更新交接文件」手动刷新。"
            : "When switching to Claude or Codex, the app refreshes the project snapshot and handoff files automatically.\n\nYou can also click\n\"Update Handoff Now\" anytime if you want to refresh manually."
    }
    var startupHandoffNoticeAcknowledge: String { language == .zhHans ? "我知道了" : "Got It" }
    var saveHandoffFiles: String { language == .zhHans ? "保存交接文件" : "Save Handoff Files" }
    var checkGit: String { language == .zhHans ? "检查 Git" : "Check Git" }
    var moreActions: String { language == .zhHans ? "更多操作" : "More Actions" }
    var rescanProjects: String { language == .zhHans ? "重新扫描项目" : "Rescan Projects" }
    var openSettings: String { language == .zhHans ? "打开设置" : "Open Settings" }
    var updatedAt: String { language == .zhHans ? "更新时间" : "Updated At" }
    var sessionID: String { language == .zhHans ? "会话 ID" : "Session ID" }
    var git: String { "Git" }
    var handoffFiles: String { language == .zhHans ? "交接文件" : "Handoff Files" }
    var document: String { language == .zhHans ? "文档" : "Document" }
    var sessionOverview: String { language == .zhHans ? "会话概览" : "Session Overview" }
    var promptPreview: String { language == .zhHans ? "提示词预览" : "Prompt Preview" }
    var generatedPromptFallback: String { language == .zhHans ? "未生成" : "Not Generated" }
    var promptPreviewHint: String {
        language == .zhHans
            ? "切换到 Codex 或 Claude 后，这里会生成交接提示词。"
            : "A handoff prompt will appear here after switching to Codex or Claude."
    }
    var saveHint: String {
        language == .zhHans ? "保存当前编辑内容到磁盘。" : "Save the current edits to disk."
    }
    var syncHint: String {
        language == .zhHans ? "根据当前 App 状态整理并写回交接文件。" : "Write the current app state back into the handoff files."
    }
    var receiptTitle: String { language == .zhHans ? "交接读取回执" : "Handoff Read Receipt" }
    var receiptStatus: String { language == .zhHans ? "状态" : "Status" }
    var pasteReceipt: String { language == .zhHans ? "粘贴回执" : "Paste Receipt" }
    var markConfirmed: String { language == .zhHans ? "标记为已确认" : "Mark Confirmed" }
    var markFailed: String { language == .zhHans ? "标记为读取失败" : "Mark Failed" }
    var clearReceipt: String { language == .zhHans ? "清空回执" : "Clear Receipt" }
    var autoDetectedReceipt: String { language == .zhHans ? "已自动检测到交接读取回执。" : "Handoff read receipt auto-detected." }
    var receiptUpdated: String { language == .zhHans ? "已更新交接回执。" : "Handoff receipt updated." }
    var receiptCleared: String { language == .zhHans ? "已清空交接回执。" : "Handoff receipt cleared." }
    var refreshBlockedUnsaved: String {
        language == .zhHans
            ? "当前交接文件有未保存修改，请先保存后再刷新。"
            : "The current handoff files have unsaved edits. Save them before refreshing."
    }
    var syncBlockedUnsaved: String {
        language == .zhHans
            ? "当前交接文件有未保存修改，请先保存后再同步。"
            : "The current handoff files have unsaved edits. Save them before syncing."
    }
    var syncedToHandoff: String {
        language == .zhHans ? "已将当前状态同步到交接文件。" : "Synced the current state to the handoff files."
    }
    var noProjectsTitle: String {
        language == .zhHans ? "Agent Console 尚未导入项目" : "Agent Console hasn't imported any projects yet"
    }
    var noProjectsBody: String {
        if language == .zhHans {
            return """
            当前没有可管理的项目。

            点击"导入项目"，选择一个包含 .agent-handoff 文件夹的项目目录，或任意你希望管理的本地项目文件夹。
            导入后会自动创建 Default Session 和交接文件。
            """
        }
        return """
        No projects to manage yet.

        Click "Import Project" and select a folder containing a .agent-handoff directory, or any local project folder you want to manage.
        A Default Session and handoff files will be created automatically after import.
        """
    }
    var noProjectsCompactTitle: String { language == .zhHans ? "还没有项目" : "No Projects Yet" }
    var noProjectsCompactDescription: String {
        language == .zhHans ? "导入你的第一个项目来开始。" : "Import your first project to get started."
    }
    var scanRoots: String { language == .zhHans ? "扫描目录" : "Scan Roots" }
    var addRoot: String { language == .zhHans ? "添加目录" : "Add Directory" }
    var noActiveScanRoots: String {
        language == .zhHans
            ? "当前没有可显示的本地 Codex / Claude 项目目录。仍可直接导入项目，或点击扫描读取 Agent 记录。"
            : "No visible local Codex / Claude project folders. You can still import a project or scan Agent records."
    }
    var scanningLabel: String { language == .zhHans ? "正在扫描" : "Scanning" }
    var customScanRoot: String { language == .zhHans ? "自定义扫描目录" : "Custom Scan Root" }
    var unavailableCustomRoots: String { language == .zhHans ? "不可用的自定义目录" : "Unavailable Custom Roots" }
    var pathDoesNotExist: String { language == .zhHans ? "目录不存在" : "Directory does not exist" }
    var suggestedDirectories: String { language == .zhHans ? "建议目录" : "Suggested Directories" }
    var notCreated: String { language == .zhHans ? "未创建" : "Not Created" }
    var create: String { language == .zhHans ? "创建" : "Create" }
    var open: String { language == .zhHans ? "打开" : "Open" }
    var remove: String { language == .zhHans ? "移除" : "Remove" }
    var createProjectsDirectory: String { language == .zhHans ? "创建 ~/Projects" : "Create ~/Projects" }
    var chooseOtherDirectory: String { language == .zhHans ? "选择其他目录" : "Choose Another Directory" }
    var diagnostics: String { language == .zhHans ? "诊断信息" : "Diagnostics" }
    var defaultDirectory: String { language == .zhHans ? "默认目录" : "Default Directory" }
    var customDirectory: String { language == .zhHans ? "自定义目录" : "Custom Directory" }
    var scanNow: String { language == .zhHans ? "立即扫描" : "Scan Now" }
    var settingsDescription: String {
        language == .zhHans
            ? "Agent Console 只围绕手动导入项目、刷新交接上下文、生成切换提示词工作；全局记录保存在 `~/AgentWorkspace`。"
            : "Agent Console only handles manually imported projects, refreshed handoff context, and switch prompts; global records are stored in `~/AgentWorkspace`."
    }
    var discoveredCountPrefix: String { language == .zhHans ? "已发现" : "Found" }
    var foundProjectsCountSuffix: String { language == .zhHans ? "个" : "" }
    var noSessionsTitle: String { language == .zhHans ? "还没有会话" : "No Sessions Yet" }
    var noSessionsDescription: String {
        language == .zhHans ? "先为这个项目创建第一个交接会话。" : "Create the first handoff session for this project."
    }
    var noSelectedProjectBody: String {
        language == .zhHans ? "从左侧选择一个项目，然后在中间查看会话列表。" : "Choose a project from the sidebar, then review its sessions in the middle column."
    }
    var selectProjectTitle: String { language == .zhHans ? "选择一个项目" : "Select a Project" }
    var selectProjectDescription: String {
        language == .zhHans ? "先扫描目录，然后选择一个项目来管理它的会话。" : "Scan directories first, then choose a project to manage its sessions."
    }
    var selectSessionTitle: String { language == .zhHans ? "选择一个会话" : "Select a Session" }
    var selectSessionDescription: String {
        language == .zhHans ? "选择已有会话，或创建一个新会话来编辑交接文件。" : "Select an existing session or create a new one to edit handoff files."
    }
    var gitDirtyTitle: String { language == .zhHans ? "Git 工作区不干净。" : "The Git working tree is not clean." }
    var gitDirtyBody: String {
        language == .zhHans
            ? "切换 Agent 或修改代码前，请先检查 `git status --porcelain` 和 `git diff --stat`。"
            : "Before switching agents or changing code, check `git status --porcelain` and `git diff --stat` first."
    }
    var statusCurrentProject: String { language == .zhHans ? "当前项目" : "Current Project" }
    var statusCurrentSession: String { language == .zhHans ? "当前会话" : "Current Session" }
    var statusCurrentAgent: String { currentAgent }
    var recentSync: String { language == .zhHans ? "最近同步" : "Last Sync" }
    var none: String { language == .zhHans ? "无" : "None" }
    var noScansYet: String { language == .zhHans ? "尚未扫描" : "Not scanned yet" }
    var activeProjectLabel: String { language == .zhHans ? "活动项目" : "Active Project" }
    var activeSessionLabel: String { language == .zhHans ? "活动会话" : "Active Session" }
    var lastUpdatedLabel: String { language == .zhHans ? "最后更新" : "Last Updated" }
    var openDiagnosticsInSettings: String { language == .zhHans ? "诊断信息已移至设置页。" : "Diagnostics have moved to Settings." }
    var selectProjectFirst: String { language == .zhHans ? "请先选择项目" : "Select a project first" }
    var selectSessionFirst: String { language == .zhHans ? "请先创建或选择会话" : "Create or select a session first" }
    var saveBeforeRefreshing: String {
        language == .zhHans ? "请先保存当前交接文件修改，再刷新。" : "Save the current handoff edits before refreshing."
    }
    var saveBeforeSyncing: String {
        language == .zhHans ? "请先保存当前交接文件修改，再同步。" : "Save the current handoff edits before syncing."
    }

    func importedProjects(_ count: Int) -> String {
        language == .zhHans ? "已导入 \(count) 个项目" : "\(count) projects imported"
    }

    func discoveredProjects(_ count: Int) -> String {
        language == .zhHans ? "已发现 \(count) 个" : "Found \(count)"
    }

    func sessionCount(_ count: Int) -> String {
        language == .zhHans ? "\(count) 个会话" : "\(count) sessions"
    }

    func saveOrUpdateMessage(_ value: String) -> String {
        language == .zhHans ? value : value
    }

    func diagnosticsValue(_ value: String) -> String {
        value
    }
}

struct HandoffReceiptParser {
    static func detectStatus(in text: String) -> HandoffReceiptStatus {
        let normalized = normalizedReceiptText(text)
        guard !normalized.isEmpty else {
            return .pending
        }

        if normalized.contains("读取失败") || normalized.contains("readfailed") || normalized.contains("failedtoread") {
            return .failed
        }

        let requiredFiles = [
            "project_context.md",
            "conversation_log.md",
            "current_state.md",
            "todo.md",
            "decisions.md",
            "changelog.md",
            "open_questions.md",
        ]
        let chineseReadsConfirmed = requiredFiles.allSatisfy { normalized.contains("已读取\($0):是") }
        let englishReadsConfirmed = requiredFiles.allSatisfy { normalized.contains("\($0)read:yes") }

        if (normalized.contains("已完成切换") && chineseReadsConfirmed)
            || (normalized.contains("completedswitch") && englishReadsConfirmed) {
            return .confirmed
        }

        return .pending
    }

    static func extractReceipt(in text: String) -> String? {
        let markers = [
            "【交接读取回执】",
            "[Handoff Read Receipt]",
            "Handoff Read Receipt",
        ]
        let latestMarker = markers
            .compactMap { text.range(of: $0, options: [.caseInsensitive, .backwards]) }
            .max { $0.lowerBound < $1.lowerBound }
        guard let markerRange = latestMarker else { return nil }

        let searchRange = markerRange.upperBound..<text.endIndex
        var endIndex = text.endIndex
        if let nextEntry = text.range(of: "\n## ", range: searchRange)?.lowerBound {
            endIndex = nextEntry
        }
        if let maxIndex = text.index(markerRange.lowerBound, offsetBy: 4_000, limitedBy: text.endIndex),
           maxIndex < endIndex {
            endIndex = maxIndex
        }

        let receipt = text[markerRange.lowerBound..<endIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return receipt.isEmpty ? nil : receipt
    }

    private static func normalizedReceiptText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "：", with: ":")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }
}

func localizedDateTime(_ date: Date, language: AppLanguage) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: language == .zhHans ? "zh_Hans_CN" : "en_US_POSIX")
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}
