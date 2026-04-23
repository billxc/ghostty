import SwiftUI

/// A single row in the project sidebar list.
struct ProjectListItem: View {
    let project: ProjectConfig
    var isActive: Bool = false
    var claudeStatus: ClaudeTabStatus = .idle
    var gitStatus: GitStatusInfo?
    var layout: SidebarLayout = SidebarLayout()
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: layout.itemHSpacing) {
                Image(systemName: project.icon ?? "folder.fill")
                    .font(.system(size: layout.itemIconFont))
                    .foregroundColor(isActive ? .white : .accentColor)
                    .frame(width: layout.itemIconWidth)

                VStack(alignment: .leading, spacing: layout.itemVSpacing) {
                    Text(project.name)
                        .font(.system(size: layout.itemNameFont, weight: isActive ? .bold : .medium))
                        .foregroundColor(isActive ? .white : .primary)
                        .lineLimit(1)

                    if let git = gitStatus {
                        GitBadge(info: git, isActive: isActive, layout: layout)
                    } else {
                        Text(shortenedPath(project.path))
                            .font(.system(size: layout.itemPathFont))
                            .foregroundColor(isActive ? .white.opacity(0.7) : .secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                StatusDot(status: claudeStatus, layout: layout)
            }
            .padding(.horizontal, layout.itemHPadding)
            .padding(.vertical, layout.itemVPadding)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: layout.itemCornerRadius)
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
    var layout: SidebarLayout = SidebarLayout()

    var body: some View {
        HStack(spacing: layout.gitBadgeSpacing) {
            // Branch icon
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: layout.gitIconFont))

            // Branch name
            Text(info.branch)
                .font(.system(size: layout.gitBranchFont, design: .monospaced))
                .lineLimit(1)

            // Dirty indicator
            if info.isDirty {
                Text("*")
                    .font(.system(size: layout.gitDirtyFont, weight: .bold, design: .monospaced))
            }

            // Ahead/behind
            if info.ahead > 0 {
                Text("\u{2191}\(info.ahead)")
                    .font(.system(size: layout.gitAheadBehindFont, design: .monospaced))
            }
            if info.behind > 0 {
                Text("\u{2193}\(info.behind)")
                    .font(.system(size: layout.gitAheadBehindFont, design: .monospaced))
            }
        }
        .foregroundColor(isActive ? .white.opacity(0.7) : .secondary)
    }
}

/// Status indicator dot for Claude Code state.
struct StatusDot: View {
    let status: ClaudeTabStatus
    var layout: SidebarLayout = SidebarLayout()
    @State private var isPulsing = false

    var body: some View {
        switch status {
        case .idle:
            EmptyView()
        case .pending:
            // AI thinking — orange pulsing
            Circle()
                .fill(Color.orange)
                .frame(width: layout.statusDotSize, height: layout.statusDotSize)
                .opacity(isPulsing ? 0.4 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                .onAppear { isPulsing = true }
        case .completed:
            // AI done — green solid
            Circle()
                .fill(Color.green)
                .frame(width: layout.statusDotSize, height: layout.statusDotSize)
        case .actionNeeded:
            // Needs user action — red solid
            Circle()
                .fill(Color.red)
                .frame(width: layout.statusDotSize, height: layout.statusDotSize)
        }
    }
}
