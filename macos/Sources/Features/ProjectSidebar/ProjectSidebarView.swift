import SwiftUI

/// The project sidebar view shown on the left side of the terminal window.
struct ProjectSidebarView: View {
    @ObservedObject var state: ProjectSidebarState
    var backgroundColor: Color = Color(nsColor: .controlBackgroundColor)
    var backgroundOpacity: Double = 1.0
    let onOpenProject: (ProjectConfig) -> Void

    @State private var worktreeSourceProject: ProjectConfig?
    @State private var renamingProject: ProjectConfig?

    private var lo: SidebarLayout { state.layout }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Projects")
                    .font(.system(size: lo.headerFont, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, lo.headerHPadding)
            .padding(.top, lo.headerTopPadding)
            .padding(.bottom, lo.headerBottomPadding)

            // Project list
            ScrollView {
                LazyVStack(spacing: lo.listSpacing) {
                    ForEach(state.projects) { project in
                        ProjectListItem(
                            project: project,
                            isActive: state.activeProjectPath == project.path,
                            claudeStatuses: state.claudeStatuses(for: project.path, in: NSApp.keyWindow),
                            gitStatus: state.gitStatus(for: project.path),
                            layout: lo
                        ) {
                            onOpenProject(project)
                        }
                        .contextMenu {
                            Button("Open Project") {
                                onOpenProject(project)
                            }
                            Button("Rename...") {
                                renamingProject = project
                            }
                            Button("Show in Finder") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
                            }
                            Divider()
                            if !project.isWorktreeProject {
                                Button("New Worktree...") {
                                    worktreeSourceProject = project
                                }
                            }
                            Button("Move to Top") {
                                state.moveProjectToTop(project)
                            }
                            .disabled(state.projects.first?.id == project.id)
                            Divider()
                            if project.isWorktreeProject {
                                Button("Remove & Delete Worktree") {
                                    state.deleteWorktree(project, in: NSApp.keyWindow)
                                }
                            }
                            Button("Remove from Sidebar") {
                                state.removeProject(project)
                            }
                        }
                    }
                }
                .padding(.horizontal, lo.listHPadding)
            }

            Spacer()

            // Add button
            Divider()
            Button(action: { addProjectViaOpenPanel() }) {
                HStack(spacing: lo.quickButtonSpacing) {
                    Image(systemName: "plus")
                        .font(.system(size: lo.addButtonFont))
                    Text("Add Project")
                        .font(.system(size: lo.addButtonFont))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, lo.addButtonHPadding)
                .padding(.vertical, lo.addButtonVPadding)
            }
            .buttonStyle(.plain)
        }
        .background(backgroundColor.opacity(backgroundOpacity))
        .sheet(item: $worktreeSourceProject) { project in
            NewWorktreeSheet(
                repoPath: project.path,
                onCreated: { branchName, baseBranch in
                    worktreeSourceProject = nil
                    state.createWorktree(branchName: branchName, baseBranch: baseBranch, from: project, in: NSApp.keyWindow)
                },
                onCancel: { worktreeSourceProject = nil }
            )
        }
        .onChange(of: renamingProject) { project in
            guard let project else { return }
            renamingProject = nil
            showRenameAlert(for: project)
        }
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

    private func showRenameAlert(for project: ProjectConfig) {
        let alert = NSAlert()
        alert.messageText = "Rename Project"
        alert.informativeText = "Enter a new name for \"\(project.name)\":"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = project.name
        alert.accessoryView = textField

        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { response in
                guard response == .alertFirstButtonReturn else { return }
                let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)
                guard !newName.isEmpty else { return }
                state.renameProject(project, to: newName)
            }
            // Focus the text field after the sheet is shown
            DispatchQueue.main.async {
                textField.selectText(nil)
            }
        } else {
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return }
            let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !newName.isEmpty else { return }
            state.renameProject(project, to: newName)
        }
    }
}
