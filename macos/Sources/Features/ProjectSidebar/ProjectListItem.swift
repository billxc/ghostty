import SwiftUI

/// A single row in the project sidebar list.
struct ProjectListItem: View {
    let project: ProjectConfig
    var isActive: Bool = false
    var isArchived: Bool = false
    var claudeStatuses: [ClaudeTabStatus] = []
    var gitStatus: GitStatusInfo?
    var layout: SidebarLayout = SidebarLayout()
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: layout.itemHSpacing) {
                Image(systemName: isArchived ? "archivebox" : (project.icon ?? "folder.fill"))
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

                StatusDots(statuses: claudeStatuses, layout: layout)
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
        .opacity(isArchived ? 0.6 : 1.0)
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

/// Shows status indicator dots for a project's Claude Code tabs.
/// Layout adapts: 1 → single large dot, 2 → 1×2, 3–4 → 2×2, 5–6 → 3×2.
struct StatusDots: View {
    let statuses: [ClaudeTabStatus]
    var layout: SidebarLayout = SidebarLayout()

    /// Rectangular area: wider than tall so dots stay visible at higher counts.
    private var areaWidth: CGFloat { layout.statusDotSize * 2.4 }
    private var areaHeight: CGFloat { layout.statusDotSize * 1.6 }
    private var dotSpacing: CGFloat { layout.statusDotSize * 0.25 }

    var body: some View {
        if statuses.isEmpty {
            EmptyView()
        } else {
            Group {
                switch activeStatuses.count {
                case 1:
                    StatusDot(status: activeStatuses[0], layout: layout, size: layout.statusDotSize * 1.2)
                case 2:
                    let dotSize = (areaWidth - dotSpacing) / 2
                    HStack(spacing: dotSpacing) {
                        ForEach(0..<2, id: \.self) { i in
                            StatusDot(status: activeStatuses[i], layout: layout, size: dotSize)
                        }
                    }
                case 3, 4:
                    let dotSize = min((areaWidth - dotSpacing) / 2, (areaHeight - dotSpacing) / 2)
                    let grid = padded(to: 4)
                    VStack(spacing: dotSpacing) {
                        HStack(spacing: dotSpacing) {
                            StatusDot(status: grid[0], layout: layout, size: dotSize)
                            StatusDot(status: grid[1], layout: layout, size: dotSize)
                        }
                        HStack(spacing: dotSpacing) {
                            StatusDot(status: grid[2], layout: layout, size: dotSize)
                            StatusDot(status: grid[3], layout: layout, size: dotSize)
                        }
                    }
                default:
                    // 5–6: 3×2 grid (3 columns, 2 rows)
                    let dotSize = min((areaWidth - 2 * dotSpacing) / 3, (areaHeight - dotSpacing) / 2)
                    let grid = padded(to: 6)
                    VStack(spacing: dotSpacing) {
                        HStack(spacing: dotSpacing) {
                            StatusDot(status: grid[0], layout: layout, size: dotSize)
                            StatusDot(status: grid[1], layout: layout, size: dotSize)
                            StatusDot(status: grid[2], layout: layout, size: dotSize)
                        }
                        HStack(spacing: dotSpacing) {
                            StatusDot(status: grid[3], layout: layout, size: dotSize)
                            StatusDot(status: grid[4], layout: layout, size: dotSize)
                            StatusDot(status: grid[5], layout: layout, size: dotSize)
                        }
                    }
                }
            }
            .frame(width: areaWidth, height: areaHeight)
            .allowsHitTesting(false)
        }
    }

    /// Non-idle statuses (capped at 6).
    private var activeStatuses: [ClaudeTabStatus] {
        Array(statuses.filter { $0 != .idle }.prefix(6))
    }

    private func padded(to count: Int) -> [ClaudeTabStatus] {
        var result = activeStatuses
        while result.count < count { result.append(.idle) }
        return result
    }
}

/// Status indicator dot for Claude Code state.
/// Uses compositingGroup + allowsHitTesting(false) so parent opacity does not dim the dot.
struct StatusDot: View {
    let status: ClaudeTabStatus
    var layout: SidebarLayout = SidebarLayout()
    var size: CGFloat? = nil
    @State private var isPulsing = false

    private var dotSize: CGFloat { size ?? layout.statusDotSize }

    private var dotColor: Color {
        switch status {
        case .idle: return .clear
        case .pending: return Color(red: 1.0, green: 0.6, blue: 0.0)   // saturated amber
        case .completed: return Color(red: 0.15, green: 0.82, blue: 0.35) // saturated green
        case .actionNeeded: return Color(red: 1.0, green: 0.22, blue: 0.22) // saturated red
        }
    }

    var body: some View {
        switch status {
        case .idle:
            Circle()
                .fill(Color.clear)
                .frame(width: dotSize, height: dotSize)
        case .pending:
            // AI thinking — amber pulsing
            Circle()
                .fill(dotColor)
                .frame(width: dotSize, height: dotSize)
                .opacity(isPulsing ? 0.4 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                .compositingGroup()
                .onAppear { isPulsing = true }
        case .completed:
            // AI done — green solid
            Circle()
                .fill(dotColor)
                .frame(width: dotSize, height: dotSize)
                .compositingGroup()
        case .actionNeeded:
            // Needs user action — red solid
            Circle()
                .fill(dotColor)
                .frame(width: dotSize, height: dotSize)
                .compositingGroup()
        }
    }
}
