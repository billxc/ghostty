import SwiftUI
import os

private let sidebarLogger = Logger(subsystem: "com.mitchellh.ghostty", category: "sidebar")

/// Tracks which terminal NSWindow is currently the system key window so
/// per-window SwiftUI views can short-circuit expensive work when they
/// know they're not visible. Each tab is its own NSWindow with its own
/// SwiftUI tree; without this, every status push re-renders the sidebar
/// and tab bar in every tab regardless of visibility.
final class KeyWindowTracker: ObservableObject {
    static let shared = KeyWindowTracker()
    @Published var keyWindowID: ObjectIdentifier?

    func update(_ window: NSWindow?) {
        let id = window.map(ObjectIdentifier.init)
        guard id != keyWindowID else { return }
        keyWindowID = id
    }
}

/// Holds Claude Code per-tab status as its own ObservableObject.
/// Split from ProjectSidebarState so high-frequency status pushes
/// do not invalidate views that only care about projects/layout/width.
class ClaudeStatusStore: ObservableObject {
    static let shared = ClaudeStatusStore()

    @Published var tabStatuses: [String: ClaudeTabStatus] = [:] {
        didSet { recomputeProjectIndex() }
    }

    /// Cached per-project status snapshot. Recomputed once when tabStatuses
    /// or the tab/window set changes — consumers (sidebar list) read O(1)
    /// instead of walking every window per project per render.
    /// Each entry is the top-priority non-idle statuses for that project,
    /// capped to 4, sorted highest priority first.
    @Published private(set) var projectStatuses: [String: [ClaudeTabStatus]] = [:]

    /// Aggregated worst-case status per project (mirrors `claudeStatus(for:)`).
    @Published private(set) var projectAggregateStatus: [String: ClaudeTabStatus] = [:]

    /// Should be called whenever the tab/window set changes (creation,
    /// closure, project assignment) so the cached project index stays
    /// in sync. Cheap to call — recompute walks NSApp.windows once.
    func notifyTabsChanged() {
        recomputeProjectIndex()
    }

    private func recomputeProjectIndex() {
        var grouped: [String: [ClaudeTabStatus]] = [:]
        for window in NSApp.windows {
            guard let controller = window.windowController as? TerminalController,
                  let path = controller.project?.path,
                  let tabId = controller.ghosttyTabId,
                  let status = tabStatuses[tabId],
                  status != .idle else { continue }
            grouped[path, default: []].append(status)
        }
        // Sort + cap each project's list to 4
        var top: [String: [ClaudeTabStatus]] = [:]
        var aggregate: [String: ClaudeTabStatus] = [:]
        for (path, statuses) in grouped {
            let sorted = statuses.sorted { Self.priority($0) > Self.priority($1) }
            top[path] = Array(sorted.prefix(4))
            aggregate[path] = sorted.first ?? .idle
        }
        if top != projectStatuses { projectStatuses = top }
        if aggregate != projectAggregateStatus { projectAggregateStatus = aggregate }
    }

    private static func priority(_ status: ClaudeTabStatus) -> Int {
        switch status {
        case .idle: return 0
        case .completed: return 1
        case .pending: return 2
        case .actionNeeded: return 3
        }
    }
}

/// Holds per-project git status as its own ObservableObject.
/// Split from ProjectSidebarState so 60s git polling does not
/// invalidate the tab bar / quick launch views.
class GitStatusStore: ObservableObject {
    static let shared = GitStatusStore()
    @Published var gitStatuses: [String: GitStatusInfo] = [:]

    func gitStatus(for path: String?) -> GitStatusInfo? {
        guard let path else { return nil }
        return gitStatuses[path]
    }
}

/// Manages the state of the project sidebar.
/// Shared singleton so all windows display the same sidebar.
class ProjectSidebarState: ObservableObject {
    static let shared = ProjectSidebarState()

    @Published var isVisible: Bool
    @Published var width: CGFloat
    @Published var projects: [ProjectConfig]
    @Published var archivedProjects: [ProjectConfig] = []
    @Published var activeProjectPath: String? {
        didSet {
            guard activeProjectPath != oldValue else { return }
            persistSidebarSettings()
        }
    }

    /// Forwarders to the split stores. Kept here so existing callers
    /// (claudeStatus(for:), claudeStatuses(for:), gitStatus(for:)) keep working,
    /// but reads/writes go through stores that observers can target directly.
    var tabStatuses: [String: ClaudeTabStatus] {
        get { ClaudeStatusStore.shared.tabStatuses }
        set { ClaudeStatusStore.shared.tabStatuses = newValue }
    }

    var gitStatuses: [String: GitStatusInfo] {
        get { GitStatusStore.shared.gitStatuses }
        set { GitStatusStore.shared.gitStatuses = newValue }
    }

    /// Per-project last active tab, keyed by project path → window ObjectIdentifier.
    private var lastActiveTabWindow: [String: ObjectIdentifier] = [:]

    private let claudeStatus = ClaudeStatusServer()
    private var gitPollTimer: DispatchSourceTimer?

    /// Per-project last poll timestamp. Combined with a hash-derived phase
    /// offset this spreads polls across the 60s window so all projects don't
    /// hit the minute mark together.
    private var gitLastPollAt: [String: Date] = [:]
    private let gitPollEpoch = Date()
    private static let gitPollInterval: TimeInterval = 60.0

    /// Socket path for this Ghostty instance (used by env var injection).
    var claudeStatusSocketPath: String { claudeStatus.socketPath }

    /// Dismiss completed/actionNeeded status when user focuses a tab.
    func dismissClaudeStatus(for tabId: String?) {
        guard let tabId else { return }
        claudeStatus.dismissStatus(for: tabId)
    }

    /// Remove all status for a tab unconditionally (tab closed / process exited).
    func removeClaudeStatus(for tabId: String?) {
        guard let tabId else { return }
        claudeStatus.removeStatus(for: tabId)
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

    /// Get up to 4 non-idle Claude statuses for a project, sorted by priority (highest first).
    func claudeStatuses(for projectPath: String?, in window: NSWindow?) -> [ClaudeTabStatus] {
        guard let projectPath else { return [] }
        let windows = tabWindows(for: projectPath, in: window)
        var statuses: [ClaudeTabStatus] = []
        for win in windows {
            guard let controller = win.windowController as? TerminalController,
                  let tabId = controller.ghosttyTabId,
                  let status = tabStatuses[tabId],
                  status != .idle else { continue }
            statuses.append(status)
        }
        return statuses
            .sorted { priority($0) > priority($1) }
            .prefix(4)
            .map { $0 }
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

        // Deduplicate by path (keep first occurrence)
        var loadedProjects: [ProjectConfig] = []
        var seenPaths: Set<String> = []
        for project in file.projects {
            if seenPaths.insert(project.path).inserted {
                loadedProjects.append(project)
            }
        }
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
        self.archivedProjects = file.archivedProjects ?? []
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
        guard !projects.contains(where: { $0.path == project.path }) else { return }
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

    /// Rename a project (persists immediately).
    func renameProject(_ project: ProjectConfig, to newName: String) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[idx].name = newName
        persistImmediately()
    }

    /// Update a project's full config (persists immediately).
    func updateProject(_ updated: ProjectConfig) {
        guard let idx = projects.firstIndex(where: { $0.path == updated.path }) else { return }
        // Clear cached git status if git was just disabled
        if updated.isGitDisabled && !projects[idx].isGitDisabled {
            gitStatuses.removeValue(forKey: updated.path)
        }
        projects[idx] = updated
        persistImmediately()
    }

    /// Toggle git status polling for a project (persists immediately).
    func toggleGitDisabled(_ project: ProjectConfig) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[idx].disableGit = !(projects[idx].disableGit ?? false)
        // Clear cached git status when disabling
        if projects[idx].isGitDisabled {
            gitStatuses.removeValue(forKey: project.path)
        }
        persistImmediately()
    }

    /// Move a project to the top of the list (persists immediately).
    func moveProjectToTop(_ project: ProjectConfig) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }), idx != 0 else { return }
        let p = projects.remove(at: idx)
        projects.insert(p, at: 0)
        persistImmediately()
    }

    /// Archive a project — moves it from the active list to the archived list.
    func archiveProject(_ project: ProjectConfig) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        let p = projects.remove(at: idx)
        archivedProjects.append(p)
        // If archived project was active, switch to first remaining project
        if activeProjectPath == p.path {
            activeProjectPath = projects.first?.path
        }
        persistImmediately()
    }

    /// Unarchive a project — moves it from the archived list back to the active list.
    func unarchiveProject(_ project: ProjectConfig) {
        guard let idx = archivedProjects.firstIndex(where: { $0.id == project.id }) else { return }
        let p = archivedProjects.remove(at: idx)
        projects.append(p)
        persistImmediately()
    }

    /// Remove a project from the archived list permanently.
    func removeArchivedProject(_ project: ProjectConfig) {
        archivedProjects.removeAll { $0.id == project.id }
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

    /// Record the last active tab for a project path.
    func recordActiveTab(for projectPath: String?, window: NSWindow?) {
        guard let projectPath, let window else { return }
        lastActiveTabWindow[projectPath] = ObjectIdentifier(window)
    }

    /// Switch to a project within the same window.
    /// Priority: notified tab > last active tab > first tab > create new.
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

        // Fall back to last active tab for this project.
        let lastActiveTab: NSWindow? = lastActiveTabWindow[project.path].flatMap { savedId in
            projectWindows.first { ObjectIdentifier($0) == savedId }
        }

        if let target = notifiedTab ?? lastActiveTab ?? projectWindows.first {
            tabGroup.selectedWindow = target
            // Dismiss status for the tab we just switched to
            if let controller = target.windowController as? TerminalController {
                dismissClaudeStatus(for: controller.ghosttyTabId)
            }
            return
        }

        // No existing tab — open a welcome placeholder in the project so
        // the user gets an instant switch instead of paying for a full
        // login shell. Falls back to a real shell if welcome isn't built.
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        var config = WelcomeSurface.makeBaseConfig() ?? Ghostty.SurfaceConfiguration()
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
        qos: .utility,
        attributes: .concurrent
    )

    private func startGitStatusPolling() {
        // Master timer ticks every 5s. Each project polls once per 60s,
        // staggered by a per-path hash so they don't pile on the minute mark.
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 1.0, repeating: 5.0)
        timer.setEventHandler { [weak self] in
            self?.refreshGitStatuses()
        }
        timer.resume()
        gitPollTimer = timer
    }

    /// Called on main. Picks the subset of projects whose 60s window has
    /// elapsed (offset by a per-path hash so polls spread across the window),
    /// fans out fetches concurrently, and merges only the changed entries
    /// back into `gitStatuses` to avoid redundant @Published republishes.
    private func refreshGitStatuses() {
        let now = Date()
        let interval = Self.gitPollInterval
        let pathsToPoll: [String] = projects.compactMap { project in
            guard !project.isGitDisabled else { return nil }
            let path = project.path
            // Phase offset in [0, interval): stable per path.
            let offset = TimeInterval(abs(path.hashValue) % Int(interval))
            // First poll at gitPollEpoch + offset; subsequent every `interval`.
            let last = gitLastPollAt[path]
                ?? gitPollEpoch.addingTimeInterval(offset - interval)
            return now.timeIntervalSince(last) >= interval ? path : nil
        }
        guard !pathsToPoll.isEmpty else { return }
        for path in pathsToPoll { gitLastPollAt[path] = now }

        Self.gitPollQueue.async { [weak self] in
            // Fan out: each git status fetch runs in parallel.
            // Use a lock-protected dict because GCD's concurrentPerform
            // worker callbacks may run on different threads.
            let lock = NSLock()
            var newStatuses: [String: GitStatusInfo] = [:]
            DispatchQueue.concurrentPerform(iterations: pathsToPoll.count) { idx in
                let path = pathsToPoll[idx]
                guard let info = GitStatusManager.fetchStatus(at: path) else { return }
                lock.lock()
                newStatuses[path] = info
                lock.unlock()
            }
            DispatchQueue.main.async {
                guard let self else { return }
                var merged = self.gitStatuses
                var changed = false
                for (path, info) in newStatuses where merged[path] != info {
                    merged[path] = info
                    changed = true
                }
                if changed { self.gitStatuses = merged }
            }
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
        let currentArchivedProjects = archivedProjects
        let currentWidth = Double(width)
        let currentIsVisible = isVisible
        let currentActiveProjectPath = activeProjectPath

        let item = DispatchWorkItem {
            var file = ProjectConfigStore.load()
            file.projects = currentProjects
            file.archivedProjects = currentArchivedProjects
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
        let currentArchivedProjects = archivedProjects
        let currentWidth = Double(width)
        let currentIsVisible = isVisible
        let currentActiveProjectPath = activeProjectPath

        Self.persistQueue.async {
            var file = ProjectConfigStore.load()
            file.projects = currentProjects
            file.archivedProjects = currentArchivedProjects
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
                    parentRepoPath: project.path,
                    quickCommands: project.quickCommands
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
