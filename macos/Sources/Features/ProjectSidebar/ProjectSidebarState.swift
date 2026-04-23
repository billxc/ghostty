import SwiftUI
import os

private let sidebarLogger = Logger(subsystem: "com.mitchellh.ghostty", category: "sidebar")

/// Manages the state of the project sidebar.
/// Shared singleton so all windows display the same sidebar.
class ProjectSidebarState: ObservableObject {
    static let shared = ProjectSidebarState()

    @Published var isVisible: Bool
    @Published var width: CGFloat
    @Published var projects: [ProjectConfig]
    @Published var activeProjectPath: String? {
        didSet {
            guard activeProjectPath != oldValue else { return }
            persistSidebarSettings()
        }
    }

    /// Per-tab Claude Code status, keyed by tab ID (GHOSTTY_TAB_ID).
    @Published var tabStatuses: [String: ClaudeTabStatus] = [:]

    /// Per-project git status, keyed by project path.
    @Published var gitStatuses: [String: GitStatusInfo] = [:]

    private let claudeStatus = ClaudeStatusServer()
    private var gitPollTimer: DispatchSourceTimer?

    /// Socket path for this Ghostty instance (used by env var injection).
    var claudeStatusSocketPath: String { claudeStatus.socketPath }

    /// Dismiss completed/actionNeeded status when user focuses a tab.
    func dismissClaudeStatus(for tabId: String?) {
        guard let tabId else { return }
        claudeStatus.dismissStatus(for: tabId)
    }

    /// Get aggregated Claude status for a project (worst-case across its tabs).
    func claudeStatus(for projectPath: String?, in window: NSWindow?) -> ClaudeTabStatus {
        guard let projectPath else { return .idle }
        let windows = tabWindows(for: projectPath, in: window)
        var worst: ClaudeTabStatus = .idle
        for win in windows {
            guard let controller = win.windowController as? TerminalController,
                  let tabId = controller.ghosttyTabId,
                  let status = tabStatuses[tabId] else { continue }
            if priority(status) > priority(worst) {
                worst = status
            }
        }
        return worst
    }

    /// Get git status for a project path.
    func gitStatus(for path: String?) -> GitStatusInfo? {
        guard let path else { return nil }
        return gitStatuses[path]
    }

    private func priority(_ status: ClaudeTabStatus) -> Int {
        switch status {
        case .idle: return 0
        case .completed: return 1
        case .pending: return 2
        case .actionNeeded: return 3
        }
    }

    /// Layout constants derived from uiScale in projects.json.
    @Published var layout: SidebarLayout

    static let defaultWidth: CGFloat = 240
    static let minWidth: CGFloat = 150
    static let maxWidth: CGFloat = 450

    init() {
        let file = ProjectConfigStore.load()
        let uiScale = file.sidebar?.uiScale ?? 1.0
        let layout = SidebarLayout(scale: CGFloat(uiScale))
        self.layout = layout

        var loadedProjects = file.projects
        // If no projects configured, add user home as default
        if loadedProjects.isEmpty {
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            loadedProjects = [ProjectConfig(
                name: NSUserName(),
                path: homePath,
                command: nil,
                icon: "house.fill"
            )]
        }
        self.projects = loadedProjects
        self.isVisible = true  // Always visible
        self.width = CGFloat(file.sidebar?.width ?? Double(layout.defaultWidth))
        // Default to first project if no active project saved
        self.activeProjectPath = file.sidebar?.activeProjectPath ?? loadedProjects.first?.path

        claudeStatus.onStatusChange = { [weak self] statuses in
            self?.tabStatuses = statuses
        }
        claudeStatus.start()
        startGitStatusPolling()
    }

    func toggle() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isVisible.toggle()
        }
        persistSidebarSettings()
    }

    func addProject(_ project: ProjectConfig) {
        projects.append(project)
        persistAll()
    }

    func removeProject(at index: Int) {
        projects.remove(at: index)
        persistAll()
    }

    func removeProject(_ project: ProjectConfig) {
        projects.removeAll { $0.id == project.id }
        persistAll()
    }

    /// Move a project to the top of the list (persists immediately).
    func moveProjectToTop(_ project: ProjectConfig) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }), idx != 0 else { return }
        let p = projects.remove(at: idx)
        projects.insert(p, at: 0)
        persistImmediately()
    }

    func updateWidth(_ newWidth: CGFloat) {
        width = max(layout.minWidth, min(layout.maxWidth, newWidth))
        persistSidebarSettings()
    }

    /// Update width without scheduling persistence (used during drag).
    func setWidthWithoutPersist(_ newWidth: CGFloat) {
        width = max(layout.minWidth, min(layout.maxWidth, newWidth))
    }

    /// Switch to a project within the same window.
    /// Prefers tabs with status notifications, then falls back to any existing tab.
    func switchToProject(_ project: ProjectConfig, in window: NSWindow?) {
        guard let window else { return }

        activeProjectPath = project.path

        guard let tabGroup = window.tabGroup else { return }
        let projectWindows = tabGroup.windows.filter {
            ($0.windowController as? TerminalController)?.project?.path == project.path
        }

        // Prefer a tab with a notification (actionNeeded > completed).
        // Skip pending — AI hasn't responded yet, no point switching there.
        let notifiedTab = projectWindows
            .compactMap { win -> (NSWindow, Int)? in
                guard let controller = win.windowController as? TerminalController,
                      let tabId = controller.ghosttyTabId,
                      let status = tabStatuses[tabId],
                      status != .pending else { return nil }
                return (win, priority(status))
            }
            .max(by: { $0.1 < $1.1 })?
            .0

        if let target = notifiedTab ?? projectWindows.first {
            tabGroup.selectedWindow = target
            return
        }

        // No existing tab — create a plain terminal in the project directory
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = project.path
        let controller = TerminalController.newTab(
            appDelegate.ghostty,
            from: window,
            withBaseConfig: config
        )
        controller?.project = project
    }

    /// Get windows belonging to a specific project.
    /// Uses tabGroup.windows for stable ordering.
    func tabWindows(for projectPath: String?, in window: NSWindow?) -> [NSWindow] {
        guard let windows = window?.tabGroup?.windows ?? (window.map { [$0] }) else { return [] }
        return windows.filter { win in
            let p = (win.windowController as? TerminalController)?.project?.path
            if let projectPath {
                return p == projectPath
            } else {
                return p == nil
            }
        }
    }

    // MARK: - Git Status Polling

    private static let gitPollQueue = DispatchQueue(
        label: "com.mitchellh.ghostty.git-status-poll",
        qos: .utility
    )

    private func startGitStatusPolling() {
        let timer = DispatchSource.makeTimerSource(queue: Self.gitPollQueue)
        timer.schedule(deadline: .now(), repeating: 10.0)
        timer.setEventHandler { [weak self] in
            self?.refreshGitStatuses()
        }
        timer.resume()
        gitPollTimer = timer
    }

    private func refreshGitStatuses() {
        let paths = DispatchQueue.main.sync { projects.map(\.path) }
        var newStatuses: [String: GitStatusInfo] = [:]
        for path in paths {
            if let info = GitStatusManager.fetchStatus(at: path) {
                newStatuses[path] = info
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.gitStatuses = newStatuses
        }
    }

    // MARK: - Persistence

    private static let persistQueue = DispatchQueue(
        label: "com.mitchellh.ghostty.sidebar-persist",
        qos: .utility
    )

    /// Debounced work item for sidebar settings persistence.
    private var persistWorkItem: DispatchWorkItem?

    /// Schedule a debounced persist — waits 3 seconds, resets on each new call.
    /// Captures current state on main thread, writes on background queue.
    private func schedulePersist() {
        persistWorkItem?.cancel()
        let currentProjects = projects
        let currentWidth = Double(width)
        let currentIsVisible = isVisible
        let currentActiveProjectPath = activeProjectPath

        let item = DispatchWorkItem {
            var file = ProjectConfigStore.load()
            file.projects = currentProjects
            let existingScale = file.sidebar?.uiScale
            file.sidebar = ProjectsFile.SidebarSettings(
                width: currentWidth,
                visible: currentIsVisible,
                activeProjectPath: currentActiveProjectPath,
                uiScale: existingScale
            )
            ProjectConfigStore.save(file)
        }
        persistWorkItem = item
        Self.persistQueue.asyncAfter(deadline: .now() + 3, execute: item)
    }

    private func persistAll() {
        schedulePersist()
    }

    /// Persist immediately without debounce (for user-initiated reorder).
    private func persistImmediately() {
        persistWorkItem?.cancel()
        let currentProjects = projects
        let currentWidth = Double(width)
        let currentIsVisible = isVisible
        let currentActiveProjectPath = activeProjectPath

        Self.persistQueue.async {
            var file = ProjectConfigStore.load()
            file.projects = currentProjects
            let existingScale = file.sidebar?.uiScale
            file.sidebar = ProjectsFile.SidebarSettings(
                width: currentWidth,
                visible: currentIsVisible,
                activeProjectPath: currentActiveProjectPath,
                uiScale: existingScale
            )
            ProjectConfigStore.save(file)
        }
    }

    func persistSidebarSettings() {
        schedulePersist()
    }

    // MARK: - Worktree

    func createWorktree(branchName: String, baseBranch: String?, from sourceProject: ProjectConfig? = nil, in window: NSWindow?) {
        let project: ProjectConfig
        if let sourceProject {
            project = sourceProject
        } else if let activePath = activeProjectPath,
                  let activeProject = projects.first(where: { $0.path == activePath }) {
            project = activeProject
        } else {
            showError("No Active Project", detail: "Select a project first.", in: window)
            return
        }

        guard GitWorktreeManager.isGitRepository(at: project.path) else {
            showError("Not a Git Repository",
                      detail: "\(project.name) is not inside a git repository.",
                      in: window)
            return
        }

        GitWorktreeManager.createWorktree(
            repoPath: project.path,
            branchName: branchName,
            baseBranch: baseBranch
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let worktreePath):
                let repoName = GitWorktreeManager.repoName(from: project.path)
                let newProject = ProjectConfig(
                    name: "\(repoName)/\(branchName)",
                    path: worktreePath,
                    command: nil,
                    icon: "arrow.triangle.branch",
                    isWorktree: true,
                    parentRepoPath: project.path
                )
                self.addProject(newProject)
                // Use the current key window (sheet has dismissed by now)
                let terminalWindow = self.findTerminalWindow()
                self.switchToProject(newProject, in: terminalWindow)
            case .failure(let error):
                self.showError("Failed to Create Worktree",
                               detail: error.localizedDescription,
                               in: window)
            }
        }
    }

    func deleteWorktree(_ project: ProjectConfig, in window: NSWindow?) {
        guard project.isWorktreeProject,
              let parentRepo = project.parentRepoPath else { return }

        let alert = NSAlert()
        alert.messageText = "Delete Worktree?"
        alert.informativeText = "This will run 'git worktree remove' and delete the directory:\n\(project.path)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        let doRemove = { [weak self] in
            GitWorktreeManager.removeWorktree(
                worktreePath: project.path,
                parentRepoPath: parentRepo
            ) { result in
                guard let self else { return }
                switch result {
                case .success:
                    self.removeProject(project)
                case .failure(let error):
                    self.showError("Failed to Remove Worktree",
                                   detail: error.localizedDescription,
                                   in: window)
                }
            }
        }

        if let window {
            alert.beginSheetModal(for: window) { response in
                guard response == .alertFirstButtonReturn else { return }
                doRemove()
            }
        } else {
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return }
            doRemove()
        }
    }

    private func showError(_ title: String, detail: String, in window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    /// Find the first terminal window (not a sheet or panel).
    private func findTerminalWindow() -> NSWindow? {
        NSApp.windows.first { $0.windowController is TerminalController }
    }
}
