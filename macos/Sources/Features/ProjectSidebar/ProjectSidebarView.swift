import SwiftUI

/// The project sidebar view shown on the left side of the terminal window.
struct ProjectSidebarView: View {
    @ObservedObject var state: ProjectSidebarState
    var backgroundColor: Color = Color(nsColor: .controlBackgroundColor)
    var backgroundOpacity: Double = 1.0
    let onOpenProject: (ProjectConfig) -> Void

    @State private var worktreeSourceProject: ProjectConfig?
    @State private var renamingProject: ProjectConfig?
    @State private var isArchivedExpanded: Bool = false

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
                            Button(project.isGitDisabled ? "Enable Git Status" : "Disable Git Status") {
                                state.toggleGitDisabled(project)
                            }
                            Divider()
                            Button("Archive") {
                                state.archiveProject(project)
                            }
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

            // Archived section
            if !state.archivedProjects.isEmpty {
                Divider()
                SidebarHoverButton(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isArchivedExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isArchivedExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                        Text("Archived (\(state.archivedProjects.count))")
                            .font(.system(size: lo.headerFont - 1, weight: .medium))
                        Spacer()
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, lo.headerHPadding)
                    .padding(.vertical, lo.addButtonVPadding)
                }

                if isArchivedExpanded {
                    ScrollView {
                        LazyVStack(spacing: lo.listSpacing) {
                            ForEach(state.archivedProjects) { project in
                                ProjectListItem(
                                    project: project,
                                    isActive: false,
                                    isArchived: true,
                                    layout: lo
                                ) {
                                    // Unarchive and open on click
                                    state.unarchiveProject(project)
                                    onOpenProject(project)
                                }
                                .contextMenu {
                                    Button("Unarchive") {
                                        state.unarchiveProject(project)
                                    }
                                    Button("Show in Finder") {
                                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
                                    }
                                    Divider()
                                    Button("Remove from Sidebar") {
                                        state.removeArchivedProject(project)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, lo.listHPadding)
                    }
                    .frame(maxHeight: 200)
                }
            }

            Spacer()

            // Add button
            Divider()
            SidebarHoverButton(action: { addProjectViaOpenPanel() }) {
                HStack(spacing: lo.quickButtonSpacing) {
                    Image(systemName: "plus")
                        .font(.system(size: lo.addButtonFont))
                    Text("Add Project")
                        .font(.system(size: lo.addButtonFont))
                    Spacer()
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, lo.addButtonHPadding)
                .padding(.vertical, lo.addButtonVPadding)
            }
            .help("Click to browse · Right-click to enter a path")
            .contextMenu {
                Button("Browse...") { addProjectViaOpenPanel() }
                Button("Enter Path...") { showAddProjectByPathAlert() }
            }
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
        panel.showsHiddenFiles = true
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

    /// Prompt the user to type a project path manually. Useful when a path is
    /// already on the clipboard (from `pwd`, Finder, etc.).
    private func showAddProjectByPathAlert() {
        let alert = NSAlert()
        alert.messageText = "Add Project by Path"
        alert.informativeText = "Enter the path to a project directory (~ supported)."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        textField.placeholderString = "/Users/me/code/my-project"
        alert.accessoryView = textField

        let submit: (Bool) -> Void = { sheetMode in
            let raw = textField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { return }
            let expanded = (raw as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir)
            guard exists, isDir.boolValue else {
                showInvalidPathAlert(path: expanded, sheetMode: sheetMode)
                return
            }
            let url = URL(fileURLWithPath: expanded)
            let project = ProjectConfig(
                name: url.lastPathComponent,
                path: url.path,
                command: nil,
                icon: "folder.fill"
            )
            state.addProject(project)
        }

        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { response in
                guard response == .alertFirstButtonReturn else { return }
                submit(true)
            }
            DispatchQueue.main.async { textField.becomeFirstResponder() }
        } else {
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            submit(false)
        }
    }

    private func showInvalidPathAlert(path: String, sheetMode: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Path is not a directory"
        alert.informativeText = path
        alert.addButton(withTitle: "OK")
        if sheetMode, let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: { _ in })
        } else {
            alert.runModal()
        }
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

/// Sidebar button that fills the available width, makes the entire row
/// clickable, and adds a subtle hover background tint.
private struct SidebarHoverButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isHovered = false

    var body: some View {
        // ZStack lets the background Rectangle expand to whatever width the
        // parent provides, independent of how SwiftUI sizes the inner Button.
        // (Putting `.background` directly on the Button gave inconsistent
        // widths depending on parent context — `if` blocks vs Spacers etc.)
        ZStack {
            Rectangle()
                .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)

            Button(action: action) {
                HStack(spacing: 0) {
                    label()
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .onHover { isHovered = $0 }
    }
}
