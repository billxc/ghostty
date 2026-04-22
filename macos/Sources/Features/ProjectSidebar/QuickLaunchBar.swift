import SwiftUI

/// Quick launch toolbar for starting common AI tools and terminal.
struct QuickLaunchBar: View {
    let activeProjectPath: String?
    var backgroundColor: Color = Color(nsColor: .windowBackgroundColor)

    private let tools: [(name: String, command: String, icon: String)] = [
        ("Claude", "claude --dangerously-skip-permissions", "brain"),
        ("Codex", "codex --dangerously-bypass-approvals-and-sandbox", "chevron.left.forwardslash.chevron.right"),
        ("Copilot", "gh copilot", "sparkles"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tools, id: \.name) { tool in
                Button(action: { launch(tool) }) {
                    HStack(spacing: 4) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 10))
                        Text(tool.name)
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tool.command.isEmpty ? "Open terminal" : "Run \(tool.command)")
            }

            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(height: 30)
        .background(backgroundColor.opacity(0.85))
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
            config.initialInput = "\(tool.command)\n"
            let controller = TerminalController.newTab(
                appDelegate.ghostty,
                from: window,
                withBaseConfig: config
            )
            // Associate with current project
            if let path = activeProjectPath {
                controller?.project = ProjectSidebarState.shared.projects.first(where: { $0.path == path })
            }
        }
    }
}
