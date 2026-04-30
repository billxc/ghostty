import Cocoa
import SwiftUI

/// Launches AI tools (Claude, Codex, etc.) in new terminal tabs.
/// Used by both QuickLaunchBar buttons and keyboard shortcuts.
enum ProjectToolLauncher {
    /// Launch a command in a new tab, associated with the current project.
    /// Pass an empty command to open a plain terminal tab.
    /// When `reuseTab` is true and a tab with the same `commandName` already exists
    /// in the current project, switches to it instead of creating a new one.
    /// When `existingSessionId` is provided (Claude resume), the session ID is also
    /// used as `GHOSTTY_TAB_ID` so hook notifications route correctly.
    static func launch(
        command: String,
        commandName: String? = nil,
        reuseTab: Bool = false,
        existingSessionId: String? = nil,
        in window: NSWindow? = nil
    ) {
        let targetWindow = window ?? NSApp.keyWindow
        guard let targetWindow else { return }
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }

        let activeProjectPath = ProjectSidebarState.shared.activeProjectPath

        if reuseTab, let name = commandName,
           let (existingWin, existingController) = findExistingTab(
               named: name, in: targetWindow, projectPath: activeProjectPath) {
            reuseExistingTab(existingWin, existingController, command: command)
            scheduleTabRefresh()
            return
        }

        if command.isEmpty {
            appDelegate.newTab(nil)
        } else {
            spawnNewTab(
                command: command,
                commandName: commandName,
                existingSessionId: existingSessionId,
                projectPath: activeProjectPath,
                in: targetWindow,
                appDelegate: appDelegate
            )
        }

        scheduleTabRefresh()
    }

    /// Resume a Claude session by ID. Passes the base claude command and lets
    /// `launch()` apply the `--resume <id>` flag internally.
    static func launchResume(sessionId: String, in window: NSWindow? = nil) {
        launch(
            command: QuickCommandDefaults.claudeCommand,
            existingSessionId: sessionId,
            in: window
        )
    }

    /// Launch Claude in a new tab.
    static func launchClaude(in window: NSWindow? = nil) {
        launch(command: QuickCommandDefaults.claudeCommand, in: window)
    }

    /// Launch lazygit in a new tab with a fixed title.
    static func launchLazygit(in window: NSWindow? = nil) {
        launch(command: QuickCommandDefaults.lazygitCommand, commandName: "Lazygit", reuseTab: true, in: window)
    }

    /// Present the Resume Session sheet as a modal sheet on the key window.
    static func showResumeSessionSheet() {
        guard let keyWindow = NSApp.keyWindow else { return }

        let projectPath = ProjectSidebarState.shared.activeProjectPath

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let hosting = NSHostingView(rootView: ResumeSessionSheet(
            projectPath: projectPath,
            onSubmit: { sessionId in
                keyWindow.endSheet(panel)
                launchResume(sessionId: sessionId, in: keyWindow)
            },
            onCancel: {
                keyWindow.endSheet(panel)
            }
        ))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting

        keyWindow.beginSheet(panel)
    }

    // MARK: - Private

    /// Reuse an existing tab: focus it, and re-run the command if its shell
    /// is sitting at a prompt (previous command exited).
    private static func reuseExistingTab(
        _ window: NSWindow,
        _ controller: TerminalController,
        command: String
    ) {
        window.makeKeyAndOrderFront(nil)

        let shellIsIdle = !(controller.focusedSurface?.needsConfirmQuit ?? true)
        if shellIsIdle, !command.isEmpty,
           let surfaceModel = controller.focusedSurface?.surfaceModel {
            MainActor.assumeIsolated {
                _ = surfaceModel.perform(action: "text:\(command)\\x0d")
            }
        }
    }

    /// Spawn a brand-new tab running `command`. Handles Claude session-id
    /// injection / resume, hook routing env vars, and special tab decoration
    /// (e.g. lazygit title).
    private static func spawnNewTab(
        command: String,
        commandName: String?,
        existingSessionId: String?,
        projectPath: String?,
        in window: NSWindow,
        appDelegate: AppDelegate
    ) {
        var config = Ghostty.SurfaceConfiguration()
        if let path = projectPath {
            config.workingDirectory = path
        }

        let prepared = prepareClaudeCommand(command, existingSessionId: existingSessionId)
        config.environmentVariables["GHOSTTY_TAB_ID"] = prepared.tabId
        config.environmentVariables["GHOSTTY_SOCKET"] = ProjectSidebarState.shared.claudeStatusSocketPath
        config.initialInput = "\(prepared.runCommand)\n"

        let controller = TerminalController.newTab(
            appDelegate.ghostty,
            from: window,
            withBaseConfig: config
        )
        if let path = projectPath {
            controller?.project = ProjectSidebarState.shared.projects.first(where: { $0.path == path })
        }
        controller?.ghosttyTabId = prepared.tabId
        controller?.quickCommandName = commandName
        // Caller contract: `command` is always a base command, so we can
        // store it directly. Resume / session-id transformations live in
        // `prepared.runCommand`, not `quickCommand`.
        controller?.quickCommand = command
        controller?.claudeSessionId = prepared.claudeSessionId

        // Detect lazygit commands and pin the tab title.
        let baseCmdName = command.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? ""
        if baseCmdName == "lazygit" {
            controller?.titleOverride = "LazyGit"
            controller?.isLazygitTab = true
        }
    }

    /// Result of preparing a Claude (or non-Claude) command for execution:
    /// the actual command string to run, the session ID (Claude only), and
    /// the tab routing ID (also used for hook notifications).
    private struct PreparedCommand {
        let runCommand: String
        let claudeSessionId: String?
        let tabId: String
    }

    /// Apply Claude session flags (`--resume <id>` for resume, `--session-id <new>`
    /// for fresh launches) and pick a stable tab routing ID.
    /// Non-Claude commands pass through unchanged with a fresh random tabId.
    private static func prepareClaudeCommand(
        _ command: String,
        existingSessionId: String?
    ) -> PreparedCommand {
        guard ClaudeSessionPersistence.isClaudeCommand(command) else {
            return PreparedCommand(
                runCommand: command,
                claudeSessionId: nil,
                tabId: existingSessionId ?? UUID().uuidString
            )
        }

        if let resumeId = existingSessionId {
            let runCmd = ClaudeSessionPersistence.buildResumeCommand(
                originalCommand: command, sessionId: resumeId)
            return PreparedCommand(runCommand: runCmd, claudeSessionId: resumeId, tabId: resumeId)
        }

        let (transformed, sid) = ClaudeSessionPersistence.injectSessionId(into: command)
        return PreparedCommand(runCommand: transformed, claudeSessionId: sid, tabId: sid)
    }

    /// Refresh the visible tab list shortly after a tab change so the custom
    /// `ProjectTabBar` reflects the new state.
    private static func scheduleTabRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ProjectTabState.shared.refresh(
                for: ProjectSidebarState.shared.activeProjectPath, in: NSApp.keyWindow)
        }
    }

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
