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

    static let defaultWidth: CGFloat = 200
    static let minWidth: CGFloat = 120
    static let maxWidth: CGFloat = 400

    init() {
        let file = ProjectConfigStore.load()
        self.projects = file.projects
        self.isVisible = true  // Always visible
        self.width = CGFloat(file.sidebar?.width ?? Double(Self.defaultWidth))
        self.activeProjectPath = file.sidebar?.activeProjectPath
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

    func updateWidth(_ newWidth: CGFloat) {
        width = max(Self.minWidth, min(Self.maxWidth, newWidth))
        persistSidebarSettings()
    }

    /// Update width without scheduling persistence (used during drag).
    func setWidthWithoutPersist(_ newWidth: CGFloat) {
        width = max(Self.minWidth, min(Self.maxWidth, newWidth))
    }

    /// Switch to a project within the same window.
    /// Finds an existing tab for the project and selects it,
    /// or creates a new tab if none exists.
    func switchToProject(_ project: ProjectConfig, in window: NSWindow?) {
        guard let window else { return }

        activeProjectPath = project.path

        // Look for an existing tab belonging to this project
        if let tabGroup = window.tabGroup,
           let existing = tabGroup.windows.first(where: {
               ($0.windowController as? TerminalController)?.project?.path == project.path
           }) {
            tabGroup.selectedWindow = existing
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

    /// Show unassigned tabs (no project).
    func showUnassigned(in window: NSWindow?) {
        guard let window else { return }
        activeProjectPath = nil

        if let tabGroup = window.tabGroup,
           let unassigned = tabGroup.windows.first(where: {
               ($0.windowController as? TerminalController)?.project == nil
           }) {
            tabGroup.selectedWindow = unassigned
        }
    }

    /// Get windows belonging to a specific project (or unassigned if nil).
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
            file.sidebar = ProjectsFile.SidebarSettings(
                width: currentWidth,
                visible: currentIsVisible,
                activeProjectPath: currentActiveProjectPath
            )
            ProjectConfigStore.save(file)
        }
        persistWorkItem = item
        Self.persistQueue.asyncAfter(deadline: .now() + 3, execute: item)
    }

    private func persistAll() {
        schedulePersist()
    }

    func persistSidebarSettings() {
        schedulePersist()
    }
}
