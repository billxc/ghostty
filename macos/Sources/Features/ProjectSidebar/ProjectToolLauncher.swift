import Cocoa
import SwiftUI

/// Launches AI tools (Claude, Codex, etc.) in new terminal tabs.
/// Used by both QuickLaunchBar buttons and keyboard shortcuts.
enum ProjectToolLauncher {
    /// Launch a command in a new tab, associated with the current project.
    /// Pass an empty command to open a plain terminal tab.
    /// When `reuseTab` is true and a tab with the same `commandName` already exists
    /// in the current project, switches to it instead of creating a new one.
    static func launch(
        command: String,
        commandName: String? = nil,
        reuseTab: Bool = false,
        in window: NSWindow? = nil
    ) {
        let targetWindow = window ?? NSApp.keyWindow
        guard let targetWindow else { return }
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }

        let activeProjectPath = ProjectSidebarState.shared.activeProjectPath

        // Tab reuse: find an existing tab running this command
        if reuseTab, let name = commandName,
           let (existingWin, existingController) = findExistingTab(named: name, in: targetWindow, projectPath: activeProjectPath) {
            existingWin.makeKeyAndOrderFront(nil)

            // If the previous command has exited, re-run it in the same tab.
            // Primary: commandExited flag set via SessionEnd socket event.
            // Fallback: shell integration reports cursor is at prompt (needsConfirmQuit == false).
            let shellIsIdle = !(existingController.focusedSurface?.needsConfirmQuit ?? true)
            if existingController.commandExited || shellIsIdle, !command.isEmpty,
               let surfaceModel = existingController.focusedSurface?.surfaceModel {
                existingController.commandExited = false
                MainActor.assumeIsolated {
                    _ = surfaceModel.perform(action: "text:\(command)\\x0d")
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                ProjectTabState.shared.refresh(
                    for: ProjectSidebarState.shared.activeProjectPath, in: NSApp.keyWindow)
            }
            return
        }

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

            // For Claude commands, inject --session-id so we can resume after restart.
            var actualCommand = command
            var claudeSessionId: String?
            if ClaudeSessionPersistence.isClaudeCommand(command) {
                let (transformed, sid) = ClaudeSessionPersistence.injectSessionId(into: command)
                actualCommand = transformed
                claudeSessionId = sid
            }

            // Chain a SessionEnd notification after the command exits.
            let cleanup = "printf '{\"event\":\"SessionEnd\",\"tabId\":\"\(tabId)\"}' | nc -U -w1 \"$GHOSTTY_SOCKET\" 2>/dev/null"
            config.initialInput = "\(actualCommand); \(cleanup)\n"
            let controller = TerminalController.newTab(
                appDelegate.ghostty,
                from: targetWindow,
                withBaseConfig: config
            )
            if let path = activeProjectPath {
                controller?.project = ProjectSidebarState.shared.projects.first(where: { $0.path == path })
            }
            controller?.ghosttyTabId = tabId
            controller?.quickCommandName = commandName
            controller?.quickCommand = command
            controller?.claudeSessionId = claudeSessionId

            // Detect lazygit commands and pin the tab title.
            let baseCmdName = command.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? ""
            if baseCmdName == "lazygit" {
                controller?.titleOverride = "LazyGit"
                controller?.isLazygitTab = true
            }
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
        launch(command: QuickCommandDefaults.claudeCommand, in: window)
    }

    /// Launch lazygit in a new tab with a fixed title.
    static func launchLazygit(in window: NSWindow? = nil) {
        launch(command: QuickCommandDefaults.lazygitCommand, commandName: "Lazygit", reuseTab: true, in: window)
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

    // MARK: - Private

    /// Find an existing tab in the current project that was launched with the given command name.
    private static func findExistingTab(
        named commandName: String,
        in window: NSWindow,
        projectPath: String?
    ) -> (NSWindow, TerminalController)? {
        guard let tabGroup = window.tabGroup else { return nil }

        for win in tabGroup.windows {
            guard let controller = win.windowController as? TerminalController else { continue }
            // Match by project (if applicable) and command name
            if let projectPath {
                guard controller.project?.path == projectPath else { continue }
            }
            if controller.quickCommandName == commandName {
                // Don't reuse tabs whose shell process has fully exited
                if let surface = controller.focusedSurface, surface.processExited {
                    continue
                }
                return (win, controller)
            }
        }
        return nil
    }
}

/// NSPanel subclass that accepts keyboard focus even when borderless.
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
