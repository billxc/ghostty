import SwiftUI

/// Sheet for creating a new git worktree from the active project.
struct NewWorktreeSheet: View {
    let repoPath: String
    let onCreated: (_ branchName: String, _ baseBranch: String?) -> Void
    let onCancel: () -> Void

    @State private var branchName = ""
    @State private var baseBranch = ""
    @State private var branches: [String] = []
    @State private var currentBranchName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Worktree")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Branch name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("feature/my-branch", text: $branchName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Base branch")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Picker("", selection: $baseBranch) {
                    Text("HEAD (\(currentBranchName ?? "unknown"))")
                        .tag("")
                    ForEach(branches, id: \.self) { branch in
                        Text(branch).tag(branch)
                    }
                }
                .labelsHidden()
            }

            if let error = validationError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            branches = GitWorktreeManager.listLocalBranches(in: repoPath)
            currentBranchName = GitWorktreeManager.currentBranch(in: repoPath)
        }
    }

    private var isValid: Bool {
        validationError == nil && !branchName.isEmpty
    }

    private var validationError: String? {
        let name = branchName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return nil } // Don't show error for empty (just disable button)
        if name.contains(" ") { return "Branch name cannot contain spaces." }
        if name.contains("..") { return "Branch name cannot contain '..'." }
        if name.hasPrefix("-") { return "Branch name cannot start with '-'." }
        let forbidden: [Character] = ["~", "^", ":", "?", "*", "[", "\\"]
        for ch in forbidden {
            if name.contains(ch) { return "Branch name cannot contain '\(ch)'." }
        }
        return nil
    }

    private func create() {
        let name = branchName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        onCreated(name, baseBranch.isEmpty ? nil : baseBranch)
    }
}
