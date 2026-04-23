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
        ProjectToolLauncher.launch(command: tool.command)
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