import Cocoa

/// Launches AI tools (Claude, Codex, etc.) in new terminal tabs.
/// Used by both QuickLaunchBar buttons and keyboard shortcuts.
enum ProjectToolLauncher {
    /// Launch a command in a new tab, associated with the current project.
    /// Pass an empty command to open a plain terminal tab.
    static func launch(command: String, in window: NSWindow? = nil) {
        let targetWindow = window ?? NSApp.keyWindow
        guard let targetWindow else { return }
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }

        let activeProjectPath = ProjectSidebarState.shared.activeProjectPath

        if command.isEmpty {
            appDelegate.newTab(nil)
        } else {
            var config = Ghostty.SurfaceConfiguration()
            if let path = activeProjectPath {
                config.workingDirectory = path
            }

            let tabId = UUID().uuidString
            let socketPath = ProjectSidebarState.shared.claudeStatusSocketPath
            config.environmentVariables["GHOSTTY_TAB_ID"] = tabId
            config.environmentVariables["GHOSTTY_SOCKET"] = socketPath

            config.initialInput = "\(command)\n"
            let controller = TerminalController.newTab(
                appDelegate.ghostty,
                from: targetWindow,
                withBaseConfig: config
            )
            if let path = activeProjectPath {
                controller?.project = ProjectSidebarState.shared.projects.first(where: { $0.path == path })
            }
            controller?.ghosttyTabId = tabId
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ProjectTabState.shared.refresh(
                for: ProjectSidebarState.shared.activeProjectPath, in: NSApp.keyWindow)
        }
    }

    /// Launch Claude in a new tab.
    static func launchClaude(in window: NSWindow? = nil) {
        launch(command: "claude --dangerously-skip-permissions", in: window)
    }
}
