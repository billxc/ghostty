import Cocoa
import SwiftUI

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

            // Chain a SessionEnd notification after the command exits.
            // When the tool process exits (normal exit, Ctrl+C, etc.), the shell
            // continues to the cleanup command and clears the status indicator.
            // This mirrors Superset's terminal exit handler as a fallback for
            // when Claude Code's Stop hook doesn't fire (e.g., user interrupt).
            let cleanup = "printf '{\"event\":\"SessionEnd\",\"tabId\":\"\(tabId)\"}' | nc -U -w1 \"$GHOSTTY_SOCKET\" 2>/dev/null"
            config.initialInput = "\(command); \(cleanup)\n"
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

    /// Launch a CLI tool with a prompt/question in a new tab.
    static func launchWithPrompt(command: String, prompt: String, in window: NSWindow? = nil) {
        let escaped = prompt.replacingOccurrences(of: "'", with: "'\\''")
        launch(command: "\(command) $'\(escaped)'", in: window)
    }

    /// Launch Claude in a new tab.
    static func launchClaude(in window: NSWindow? = nil) {
        launch(command: "claude --dangerously-skip-permissions", in: window)
    }

    /// Present the Ask AI sheet as a modal sheet on the key window.
    static func showAskAISheet() {
        guard let keyWindow = NSApp.keyWindow else { return }

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )

        panel.contentView = NSHostingView(rootView: AskAISheet(
            onSubmit: { command, prompt in
                keyWindow.endSheet(panel)
                launchWithPrompt(command: command, prompt: prompt, in: keyWindow)
            },
            onCancel: {
                keyWindow.endSheet(panel)
            }
        ))

        keyWindow.beginSheet(panel)
    }
}

/// NSPanel subclass that accepts keyboard focus even when borderless.
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
