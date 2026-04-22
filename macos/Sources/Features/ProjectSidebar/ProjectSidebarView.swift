import SwiftUI

/// The project sidebar view shown on the left side of the terminal window.
struct ProjectSidebarView: View {
    @ObservedObject var state: ProjectSidebarState
    var backgroundColor: Color = Color(nsColor: .controlBackgroundColor)
    var backgroundOpacity: Double = 1.0
    let onOpenProject: (ProjectConfig) -> Void
    var onShowUnassigned: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Projects")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Project list
            ScrollView {
                LazyVStack(spacing: 2) {
                    // Unassigned (virtual project)
                    UnassignedListItem(
                        isActive: state.activeProjectPath == nil
                    ) {
                        onShowUnassigned?()
                    }

                    ForEach(state.projects) { project in
                        ProjectListItem(
                            project: project,
                            isActive: state.activeProjectPath == project.path
                        ) {
                            onOpenProject(project)
                        }
                        .contextMenu {
                            Button("Open Project") {
                                onOpenProject(project)
                            }
                            Button("Show in Finder") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
                            }
                            Divider()
                            Button("Remove from Sidebar") {
                                state.removeProject(project)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            Spacer()

            // Add button
            Divider()
            Button(action: { addProjectViaOpenPanel() }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                    Text("Add Project")
                        .font(.system(size: 12))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .background(backgroundColor)
    }

    private func addProjectViaOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a project directory"
        panel.prompt = "Add Project"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let name = url.lastPathComponent
        let project = ProjectConfig(
            name: name,
            path: url.path,
            command: nil,
            icon: "folder.fill"
        )
        state.addProject(project)
    }
}

/// List item for unassigned tabs (no project).
private struct UnassignedListItem: View {
    var isActive: Bool = false
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.system(size: 14))
                    .foregroundColor(isActive ? .white : .secondary)
                    .frame(width: 20)

                Text("Unassigned")
                    .font(.system(size: 13, weight: isActive ? .bold : .medium))
                    .foregroundColor(isActive ? .white : .primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.accentColor
                          : (isHovering ? Color.primary.opacity(0.08) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
