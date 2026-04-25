import SwiftUI

/// A sheet for editing project settings: info, quick commands, and options.
struct ProjectSettingsEditor: View {
    let originalProject: ProjectConfig
    let onSave: (ProjectConfig) -> Void
    let onCancel: () -> Void

    @State private var draft: ProjectConfig
    @State private var draftCommands: [QuickCommand]

    init(project: ProjectConfig, onSave: @escaping (ProjectConfig) -> Void, onCancel: @escaping () -> Void) {
        self.originalProject = project
        self.onSave = onSave
        self.onCancel = onCancel
        self._draft = State(initialValue: project)
        self._draftCommands = State(initialValue: project.quickCommands ?? [])
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: draft.icon ?? "folder.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text(draft.name)
                    .font(.headline)
                Spacer()
                Text(draft.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding()

            Divider()

            // Tabbed content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Project info section
                    GroupBox("Project Info") {
                        VStack(spacing: 8) {
                            HStack {
                                Text("Name")
                                    .frame(width: 80, alignment: .leading)
                                TextField("Project name", text: $draft.name)
                                    .textFieldStyle(.roundedBorder)
                            }
                            HStack {
                                Text("Icon")
                                    .frame(width: 80, alignment: .leading)
                                TextField("SF Symbol name", text: Binding(
                                    get: { draft.icon ?? "" },
                                    set: { draft.icon = $0.isEmpty ? nil : $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                if let icon = draft.icon, !icon.isEmpty {
                                    Image(systemName: icon)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Options section
                    GroupBox("Options") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Disable Git Status", isOn: Binding(
                                get: { draft.disableGit ?? false },
                                set: { draft.disableGit = $0 ? true : nil }
                            ))
                        }
                        .padding(.vertical, 4)
                    }

                    // Quick commands section
                    GroupBox {
                        VStack(spacing: 8) {
                            ForEach(Array(draftCommands.enumerated()), id: \.offset) { index, _ in
                                QuickCommandRow(
                                    command: $draftCommands[index],
                                    index: index,
                                    total: draftCommands.count,
                                    onMoveUp: {
                                        guard index > 0 else { return }
                                        draftCommands.swapAt(index, index - 1)
                                    },
                                    onMoveDown: {
                                        guard index < draftCommands.count - 1 else { return }
                                        draftCommands.swapAt(index, index + 1)
                                    },
                                    onDelete: {
                                        draftCommands.remove(at: index)
                                    }
                                )
                                if index < draftCommands.count - 1 {
                                    Divider()
                                }
                            }

                            if draftCommands.isEmpty {
                                Text("No custom commands. Default commands will be used.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 8)
                            }

                            HStack {
                                Button(action: {
                                    draftCommands.append(QuickCommand(name: "", command: "", icon: nil))
                                }) {
                                    Label("Add Command", systemImage: "plus")
                                        .font(.caption)
                                }
                                .disabled(draftCommands.count >= QuickCommandDefaults.maxCommands)

                                Spacer()

                                Menu {
                                    Button("Insert Defaults to Front") {
                                        let merged = QuickCommandDefaults.defaultCommands + draftCommands
                                        draftCommands = Array(merged.prefix(QuickCommandDefaults.maxCommands))
                                    }
                                    .disabled(draftCommands.count >= QuickCommandDefaults.maxCommands)

                                    Button("Reset to Defaults") {
                                        draftCommands = QuickCommandDefaults.defaultCommands
                                    }
                                } label: {
                                    Label("Defaults", systemImage: "arrow.counterclockwise")
                                        .font(.caption)
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }
                        }
                        .padding(.vertical, 4)
                    } label: {
                        HStack {
                            Text("Quick Commands")
                            Spacer()
                            Text("\(draftCommands.count)/\(QuickCommandDefaults.maxCommands)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Actions
            HStack {
                Spacer()

                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    var result = draft
                    let cleaned = draftCommands.filter { !$0.name.isEmpty && !$0.command.isEmpty }
                    result.quickCommands = cleaned.isEmpty ? nil : cleaned
                    onSave(result)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 560, height: 520)
    }
}

/// A single row for editing one quick command, with move up/down and delete buttons.
private struct QuickCommandRow: View {
    @Binding var command: QuickCommand
    let index: Int
    let total: Int
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    @State private var iconText: String

    init(
        command: Binding<QuickCommand>,
        index: Int,
        total: Int,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self._command = command
        self.index = index
        self.total = total
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onDelete = onDelete
        self._iconText = State(initialValue: command.wrappedValue.icon ?? "")
    }

    var body: some View {
        HStack(spacing: 8) {
            // Move up/down buttons
            VStack(spacing: 0) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 16, height: 14)
                }
                .buttonStyle(.plain)
                .foregroundColor(index > 0 ? .secondary : .secondary.opacity(0.2))
                .disabled(index == 0)

                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 16, height: 14)
                }
                .buttonStyle(.plain)
                .foregroundColor(index < total - 1 ? .secondary : .secondary.opacity(0.2))
                .disabled(index >= total - 1)
            }

            // Icon preview
            if let icon = command.icon, !icon.isEmpty {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .frame(width: 20)
                    .foregroundColor(.secondary.opacity(0.3))
            }

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    TextField("Name", text: $command.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)

                    TextField("SF Symbol icon", text: $iconText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .onChange(of: iconText) { newValue in
                            command.icon = newValue.isEmpty ? nil : newValue
                        }
                }

                HStack(spacing: 6) {
                    TextField("Command", text: $command.command)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Toggle("Reuse", isOn: Binding(
                        get: { command.reuseTab ?? false },
                        set: { command.reuseTab = $0 ? true : nil }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .help("Reuse existing tab instead of opening a new one")
                }
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}
