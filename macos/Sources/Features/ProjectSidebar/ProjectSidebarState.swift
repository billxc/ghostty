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
        didSet { persistSidebarSettings() }
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

    /// Switch to a project within the same window.
    /// Finds an existing tab for the project and selects it,
    /// or creates a new tab if none exists.
    func switchToProject(_ project: ProjectConfig, in window: NSWindow?) {
        guard let window else { return }

        activeProjectPath = project.path

        // Look for an existing tab belonging to this project
        if let tabWindows = window.tabGroup?.windows,
           let existing = tabWindows.first(where: {
               ($0.windowController as? TerminalController)?.project?.path == project.path
           }) {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        // No existing tab — create a new one
        NotificationCenter.default.post(
            name: Ghostty.Notification.ghosttyOpenProject,
            object: window,
            userInfo: ["project": project]
        )
    }

    /// Show unassigned tabs (no project).
    func showUnassigned(in window: NSWindow?) {
        guard let window else { return }
        activeProjectPath = nil

        if let unassigned = window.tabGroup?.windows.first(where: {
            ($0.windowController as? TerminalController)?.project == nil
        }) {
            unassigned.makeKeyAndOrderFront(nil)
        }
    }

    /// Get windows belonging to a specific project (or unassigned if nil).
    func tabWindows(for projectPath: String?, in window: NSWindow?) -> [NSWindow] {
        guard let tabbedWindows = window?.tabbedWindows ?? (window.map { [$0] }) else { return [] }
        return tabbedWindows.filter { win in
            let p = (win.windowController as? TerminalController)?.project?.path
            if let projectPath {
                return p == projectPath
            } else {
                return p == nil
            }
        }
    }

    // MARK: - Persistence

    private func persistAll() {
        var file = ProjectConfigStore.load()
        file.projects = projects
        file.sidebar = ProjectsFile.SidebarSettings(
            width: Double(width),
            visible: isVisible,
            activeProjectPath: activeProjectPath
        )
        ProjectConfigStore.save(file)
    }

    private func persistSidebarSettings() {
        var file = ProjectConfigStore.load()
        file.sidebar = ProjectsFile.SidebarSettings(
            width: Double(width),
            visible: isVisible,
            activeProjectPath: activeProjectPath
        )
        ProjectConfigStore.save(file)
    }
}
