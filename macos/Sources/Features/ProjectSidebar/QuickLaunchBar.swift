import SwiftUI

/// Quick launch toolbar for starting common AI tools and terminal.
struct QuickLaunchBar: View {
    let activeProjectPath: String?
    var backgroundColor: Color = Color(nsColor: .windowBackgroundColor)
    var backgroundOpacity: Double = 1.0

    private let tools: [(name: String, command: String, icon: String)] = [
        ("Claude", "claude --dangerously-skip-permissions", "brain"),
        ("Codex", "codex --dangerously-bypass-approvals-and-sandbox", "chevron.left.forwardslash.chevron.right"),
        ("Copilot", "gh copilot", "sparkles"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tools, id: \.name) { tool in
                QuickLaunchButton(
                    name: tool.name,
                    icon: tool.icon,
                    helpText: tool.command.isEmpty ? "Open terminal" : "Run \(tool.command)"
                ) {
                    launch(tool)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(height: 30)
        .background(backgroundColor.opacity(backgroundOpacity * 0.85))
    }

    private func launch(_ tool: (name: String, command: String, icon: String)) {
        guard let window = NSApp.keyWindow else { return }
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }

        if tool.command.isEmpty {
            // Plain terminal — just new tab
            appDelegate.newTab(nil)
        } else {
            // Launch with specific command via the user's login shell so that
            // PATH (e.g. Homebrew) is available.
            var config = Ghostty.SurfaceConfiguration()
            if let path = activeProjectPath {
                config.workingDirectory = path
            }

            // Inject Ghostty status env vars for hook integration
            let tabId = UUID().uuidString
            let socketPath = ProjectSidebarState.shared.claudeStatusSocketPath
            config.environmentVariables["GHOSTTY_TAB_ID"] = tabId
            config.environmentVariables["GHOSTTY_SOCKET"] = socketPath

            config.initialInput = "\(tool.command)\n"
            let controller = TerminalController.newTab(
                appDelegate.ghostty,
                from: window,
                withBaseConfig: config
            )
            // Associate with current project and tab ID
            if let path = activeProjectPath {
                controller?.project = ProjectSidebarState.shared.projects.first(where: { $0.path == path })
            }
            controller?.ghosttyTabId = tabId
        }

        // Refresh tab bar after new tab is added to the tab group
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ProjectTabState.shared.refresh(
                for: ProjectSidebarState.shared.activeProjectPath, in: NSApp.keyWindow)
        }
    }
}

/// A single quick-launch button with hover highlight.
private struct QuickLaunchButton: View {
    let name: String
    let icon: String
    let helpText: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(name)
                    .font(.system(size: 11))
            }
            .foregroundColor(isHovering ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(isHovering ? 0.10 : 0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(helpText)
    }
}