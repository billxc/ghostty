import SwiftUI
import ObjectiveC
import os

private let sidebarLogger = Logger(subsystem: "com.mitchellh.ghostty", category: "sidebar")

private func log(_ msg: String) {
    sidebarLogger.info("\(msg)")
}

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
    /// or creates a new tab if none exists. Then filters visible tabs.
    func switchToProject(_ project: ProjectConfig, in window: NSWindow?) {
        guard let window else {
            log("switchToProject: no window")
            return
        }

        log("switchToProject: \(project.name) path=\(project.path)")
        activeProjectPath = project.path

        // Look for an existing tab belonging to this project
        if let tabWindows = window.tabGroup?.windows {
            log("switchToProject: tabGroup has \(tabWindows.count) windows")
            for (i, tw) in tabWindows.enumerated() {
                let p = (tw.windowController as? TerminalController)?.project
                log("  tab[\(i)]: project=\(p?.name ?? "nil") path=\(p?.path ?? "nil")")
            }
            if let existing = tabWindows.first(where: {
                ($0.windowController as? TerminalController)?.project?.path == project.path
            }) {
                log("switchToProject: found existing tab, switching")
                existing.makeKeyAndOrderFront(nil)
                filterTabButtons(in: existing)
                return
            }
        } else {
            log("switchToProject: no tabGroup")
        }

        // No existing tab — create a new one
        log("switchToProject: creating new tab via notification")
        NotificationCenter.default.post(
            name: Ghostty.Notification.ghosttyOpenProject,
            object: window,
            userInfo: ["project": project]
        )

        // Filter after a short delay to let the new tab appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            if let w = NSApp.keyWindow {
                self?.filterTabButtons(in: w)
            }
        }
    }

    /// Show unassigned tabs (no project).
    func showUnassigned(in window: NSWindow?) {
        guard let window else { return }
        activeProjectPath = nil

        // Switch to first unassigned tab if exists
        if let unassigned = window.tabGroup?.windows.first(where: {
            ($0.windowController as? TerminalController)?.project == nil
        }) {
            unassigned.makeKeyAndOrderFront(nil)
        }

        filterTabButtons(in: window)
    }

    /// Hide tab buttons that don't belong to the active project.
    func filterTabButtons(in window: NSWindow?) {
        guard let window else {
            log("filterTabButtons: no window")
            return
        }
        let tabbedWindows = window.tabbedWindows ?? [window]
        let tabButtons = window.tabButtonsInVisualOrder()

        log("filterTabButtons: \(tabbedWindows.count) tabs, \(tabButtons.count) buttons, active=\(activeProjectPath ?? "nil")")

        let count = min(tabButtons.count, tabbedWindows.count)
        for i in 0..<count {
            let project = (tabbedWindows[i].windowController as? TerminalController)?.project
            let belongsToActive: Bool
            if let activePath = activeProjectPath {
                belongsToActive = project?.path == activePath
            } else {
                belongsToActive = project == nil
            }

            let button = tabButtons[i]
            log("  tab[\(i)]: project=\(project?.name ?? "nil") belongs=\(belongsToActive) buttonClass=\(button.className) frame=\(button.frame)")

            if belongsToActive {
                button.isHidden = false
                if let original = objc_getAssociatedObject(button, &Self.originalWidthKey) as? CGFloat {
                    var frame = button.frame
                    frame.size.width = original
                    button.frame = frame
                    log("  tab[\(i)]: restored width=\(original)")
                }
            } else {
                if objc_getAssociatedObject(button, &Self.originalWidthKey) == nil {
                    objc_setAssociatedObject(button, &Self.originalWidthKey, button.frame.width, .OBJC_ASSOCIATION_RETAIN)
                }
                button.isHidden = true
                var frame = button.frame
                frame.size.width = 0
                button.frame = frame
                log("  tab[\(i)]: hidden, width set to 0")
            }
        }

        window.tabBarView?.needsLayout = true
        window.tabBarView?.needsDisplay = true
        log("filterTabButtons: done, triggered relayout")
    }

    private static var originalWidthKey: UInt8 = 0

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
