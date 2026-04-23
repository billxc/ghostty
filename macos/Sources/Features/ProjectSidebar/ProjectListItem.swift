import SwiftUI

/// A single row in the project sidebar list.
struct ProjectListItem: View {
    let project: ProjectConfig
    var isActive: Bool = false
    var claudeStatus: ClaudeTabStatus = .idle
    var gitStatus: GitStatusInfo?
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: project.icon ?? "folder.fill")
                    .font(.system(size: 14))
                    .foregroundColor(isActive ? .white : .accentColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name)
                        .font(.system(size: 13, weight: isActive ? .bold : .medium))
                        .foregroundColor(isActive ? .white : .primary)
                        .lineLimit(1)

                    if let git = gitStatus {
                        GitBadge(info: git, isActive: isActive)
                    } else {
                        Text(shortenedPath(project.path))
                            .font(.system(size: 10))
                            .foregroundColor(isActive ? .white.opacity(0.7) : .secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                StatusDot(status: claudeStatus)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(project.path)
    }

    private var backgroundColor: Color {
        if isActive {
            return Color.accentColor
        } else if isHovering {
            return Color.primary.opacity(0.08)
        } else {
            return Color.clear
        }
    }

    private func shortenedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

/// Displays git branch, dirty indicator, and ahead/behind counts.
struct GitBadge: View {
    let info: GitStatusInfo
    var isActive: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            // Branch icon
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 8))

            // Branch name
            Text(info.branch)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)

            // Dirty indicator
            if info.isDirty {
                Text("*")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }

            // Ahead/behind
            if info.ahead > 0 {
                Text("↑\(info.ahead)")
                    .font(.system(size: 9, design: .monospaced))
            }
            if info.behind > 0 {
                Text("↓\(info.behind)")
                    .font(.system(size: 9, design: .monospaced))
            }
        }
        .foregroundColor(isActive ? .white.opacity(0.7) : .secondary)
    }
}

/// Status indicator dot for Claude Code state.
struct StatusDot: View {
    let status: ClaudeTabStatus
    @State private var isPulsing = false

    var body: some View {
        switch status {
        case .idle:
            EmptyView()
        case .pending:
            // AI thinking — orange pulsing
            Circle()
                .fill(Color.orange)
                .frame(width: 7, height: 7)
                .opacity(isPulsing ? 0.4 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                .onAppear { isPulsing = true }
        case .completed:
            // AI done — green solid
            Circle()
                .fill(Color.green)
                .frame(width: 7, height: 7)
        case .actionNeeded:
            // Needs user action — red solid
            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)
        }
    }
}
