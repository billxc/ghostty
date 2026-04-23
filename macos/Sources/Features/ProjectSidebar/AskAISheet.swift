import SwiftUI

/// A sheet that prompts the user to type a question and pick an AI tool,
/// then launches the tool in a new tab with the question pre-filled.
/// Press Cmd+Enter to submit, Enter for new line.
struct AskAISheet: View {
    let onSubmit: (_ command: String, _ prompt: String) -> Void
    let onCancel: () -> Void

    @State private var prompt = ""
    @State private var selectedTool = 0

    static let tools: [(name: String, command: String, icon: String)] = [
        ("Claude", "claude --dangerously-skip-permissions", "brain"),
        ("Codex", "codex --dangerously-bypass-approvals-and-sandbox",
         "chevron.left.forwardslash.chevron.right"),
        ("Copilot", "gh copilot", "sparkles"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Text editor - main area
            TextEditor(text: $prompt)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(8)

            Divider()

            // Bottom bar: tool picker + ask button
            HStack(spacing: 8) {
                Picker("", selection: $selectedTool) {
                    ForEach(Array(Self.tools.enumerated()), id: \.offset) { index, tool in
                        Text(tool.name).tag(index)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)

                Spacer()

                Button(action: submit) {
                    HStack(spacing: 4) {
                        Text("Ask")
                        Text("⌘↩")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .controlSize(.small)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 520, height: 300)
        .background(
            Button("") { submit() }
                .keyboardShortcut(.return, modifiers: .command)
                .hidden()
        )
        .background(
            Button("") { onCancel() }
                .keyboardShortcut(.cancelAction)
                .hidden()
        )
    }

    private func submit() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let tool = Self.tools[selectedTool]
        onSubmit(tool.command, text)
    }
}
