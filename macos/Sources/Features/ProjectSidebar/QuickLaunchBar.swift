import SwiftUI

/// Quick launch toolbar for starting common AI tools and terminal.
struct QuickLaunchBar: View {
    let activeProject: ProjectConfig?
    let onProjectChanged: ((ProjectConfig) -> Void)?
    var backgroundColor: Color = Color(nsColor: .windowBackgroundColor)
    var backgroundOpacity: Double = 1.0
    var layout: SidebarLayout = SidebarLayout()

    @State private var isEditingProject = false

    private var resolvedCommands: [QuickCommand] {
        if let cmds = activeProject?.quickCommands, !cmds.isEmpty {
            return cmds.prefix(QuickCommandDefaults.maxCommands).map { $0 }
        }
        return QuickCommandDefaults.defaultCommands
    }

    var body: some View {
        HStack(spacing: layout.quickBarSpacing) {
            // Resume Claude session button
            if !(activeProject?.hideResumeButton ?? false) {
                IconBarButton(
                    icon: "clock.arrow.circlepath",
                    helpText: "Resume Claude session (⌘⇧T)",
                    iconSize: layout.quickButtonIconFont + 3,
                    cornerRadius: layout.quickButtonCornerRadius
                ) {
                    ProjectToolLauncher.showResumeSessionSheet()
                }
            }

            // Config button
            if !(activeProject?.hideSettingsButton ?? false) {
                IconBarButton(
                    icon: "gearshape",
                    helpText: "Project settings",
                    iconSize: layout.quickButtonIconFont + 3,
                    cornerRadius: layout.quickButtonCornerRadius
                ) {
                    isEditingProject = true
                }
            }

            ForEach(Array(resolvedCommands.enumerated()), id: \.offset) { _, cmd in
                QuickLaunchButton(
                    name: cmd.name,
                    icon: cmd.icon,
                    helpText: cmd.command.isEmpty ? "Open terminal" : "Run \(cmd.command)",
                    layout: layout
                ) {
                    ProjectToolLauncher.launch(
                        command: cmd.command,
                        commandName: cmd.name,
                        reuseTab: cmd.reuseTab ?? false
                    )
                }
            }

            Spacer()
        }
        .padding(.horizontal, layout.quickBarHPadding)
        .padding(.vertical, layout.quickBarVPadding)
        .frame(height: layout.quickBarHeight)
        .background(backgroundColor.opacity(backgroundOpacity * 0.85))
        .sheet(isPresented: $isEditingProject) {
            if let project = activeProject {
                ProjectSettingsEditor(
                    project: project,
                    onSave: { updated in
                        isEditingProject = false
                        onProjectChanged?(updated)
                    },
                    onCancel: {
                        isEditingProject = false
                    }
                )
            }
        }
    }
}

/// Icon-only toolbar button with hover background highlight.
private struct IconBarButton: View {
    let icon: String
    let helpText: String
    var iconSize: CGFloat = 14
    var cornerRadius: CGFloat = 4
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundColor(isHovering ? .primary : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.primary.opacity(isHovering ? 0.10 : 0.04))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(helpText)
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
