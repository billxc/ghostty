import SwiftUI

/// Quick launch toolbar for starting common AI tools and terminal.
struct QuickLaunchBar: View {
    let activeProjectPath: String?
    let quickCommands: [QuickCommand]?
    var backgroundColor: Color = Color(nsColor: .windowBackgroundColor)
    var backgroundOpacity: Double = 1.0
    var layout: SidebarLayout = SidebarLayout()

    private static let defaultCommands: [QuickCommand] = [
        QuickCommand(name: "Claude", command: "claude --dangerously-skip-permissions", icon: "brain"),
        QuickCommand(name: "Codex", command: "codex --dangerously-bypass-approvals-and-sandbox", icon: "chevron.left.forwardslash.chevron.right"),
        QuickCommand(name: "Copilot", command: "copilot", icon: "sparkles"),
        QuickCommand(name: "Lazygit", command: "lazygit", icon: "arrow.triangle.branch"),
    ]

    private static let maxQuickCommands = 10

    private var resolvedCommands: [QuickCommand] {
        if let cmds = quickCommands, !cmds.isEmpty {
            return cmds.prefix(Self.maxQuickCommands).map { $0 }
        }
        return Self.defaultCommands
    }

    var body: some View {
        HStack(spacing: layout.quickBarSpacing) {
            ForEach(Array(resolvedCommands.enumerated()), id: \.offset) { _, cmd in
                QuickLaunchButton(
                    name: cmd.name,
                    icon: cmd.icon,
                    helpText: cmd.command.isEmpty ? "Open terminal" : "Run \(cmd.command)",
                    layout: layout
                ) {
                    ProjectToolLauncher.launch(command: cmd.command)
                }
            }

            Spacer()
        }
        .padding(.horizontal, layout.quickBarHPadding)
        .padding(.vertical, layout.quickBarVPadding)
        .frame(height: layout.quickBarHeight)
        .background(backgroundColor.opacity(backgroundOpacity * 0.85))
    }
}

/// A single quick-launch button with hover highlight.
private struct QuickLaunchButton: View {
    let name: String
    let icon: String?
    let helpText: String
    var layout: SidebarLayout = SidebarLayout()
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: layout.quickButtonSpacing) {
                if let icon, !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: layout.quickButtonIconFont))
                }
                Text(name)
                    .font(.system(size: layout.quickButtonNameFont))
            }
            .foregroundColor(isHovering ? .primary : .secondary)
            .padding(.horizontal, layout.quickButtonHPadding)
            .padding(.vertical, layout.quickButtonVPadding)
            .background(
                RoundedRectangle(cornerRadius: layout.quickButtonCornerRadius)
                    .fill(Color.primary.opacity(isHovering ? 0.10 : 0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(helpText)
    }
}
