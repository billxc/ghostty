import SwiftUI

/// The project sidebar view shown on the left side of the terminal window.
struct ProjectSidebarView: View {
    @ObservedObject var state: ProjectSidebarState
    var backgroundColor: Color = Color(nsColor: .controlBackgroundColor)
    var backgroundOpacity: Double = 1.0
    let onOpenProject: (ProjectConfig) -> Void

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
                    ForEach(state.projects) { project in
                        ProjectListItem(
                            project: project,
                            isActive: state.activeProjectPath == project.path,
                            claudeStatus: state.claudeStatus(for: project.path, in: NSApp.keyWindow)
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
                            Button("Move to Top") {
                                state.moveProjectToTop(project)
                            }
                            .disabled(state.projects.first?.id == project.id)
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
        .background(backgroundColor.opacity(backgroundOpacity))
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
