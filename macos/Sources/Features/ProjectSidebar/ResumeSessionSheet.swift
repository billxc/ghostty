import SwiftUI

/// A sheet that lists historical Claude sessions for the current project,
/// previews them, and resumes the selected session in a new tab.
struct ResumeSessionSheet: View {
    let projectPath: String?
    let onSubmit: (_ sessionId: String) -> Void
    let onCancel: () -> Void

    @State private var sessions: [ClaudeSessionScanner.SessionInfo] = []
    @State private var selectedId: String?
    @State private var preview: [ClaudeSessionScanner.PreviewMessage] = []
    @State private var previewLoadingFor: String?

    private static let previewCharLimit = 500

    private var projectName: String {
        projectPath.map { ($0 as NSString).lastPathComponent } ?? "No project"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            HSplitView {
                sessionList
                    .frame(minWidth: 240, idealWidth: 320, maxWidth: 480)
                previewPane
                    .frame(minWidth: 320)
            }
            .frame(maxHeight: .infinity)

            Divider()

            footer
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(SheetGlassBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .onAppear(perform: loadSessions)
        .onChange(of: selectedId) { newValue in
            guard let id = newValue else { return }
            loadPreview(for: id)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Resume Claude Session")
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                    Text(projectName)
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if !sessions.isEmpty {
                Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }

            Spacer()

            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button(action: submit) {
                Text("Resume")
                    .frame(minWidth: 60)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(selectedId == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Session list

    private var sessionList: some View {
        Group {
            if sessions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                    Text("No previous sessions")
                        .font(.system(size: 13, weight: .medium))
                    Text("Start a Claude session in this project\nto see it here")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sessions, selection: $selectedId) { session in
                    sessionRow(session)
                        .tag(session.id as String?)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func sessionRow(_ session: ClaudeSessionScanner.SessionInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.firstPrompt.isEmpty ? "(no prompt)" : session.firstPrompt)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(session.firstPrompt.isEmpty ? .secondary : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 9))
                    .accessibilityHidden(true)
                Text(relativeTime(session.lastModified))
                    .font(.system(size: 10))
                Text("·")
                    .font(.system(size: 10))
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 9))
                    .accessibilityHidden(true)
                Text("\(session.userMessageCount)")
                    .font(.system(size: 10))
                    .accessibilityLabel("\(session.userMessageCount) user messages")
                Spacer()
                Text(String(session.id.prefix(8)))
                    .font(.system(size: 9, design: .monospaced))
                    .accessibilityLabel("session id \(session.id)")
            }
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Preview pane

    private var previewPane: some View {
        Group {
            if selectedId == nil {
                placeholderPreview(
                    icon: "doc.text.magnifyingglass",
                    text: "Select a session to preview"
                )
            } else if preview.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(preview) { msg in
                            previewMessage(msg)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholderPreview(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func previewMessage(_ msg: ClaudeSessionScanner.PreviewMessage) -> some View {
        let isUser = msg.role == "user"
        let displayText = truncate(msg.text, to: Self.previewCharLimit)
        return HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(isUser ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 22, height: 22)
                Image(systemName: isUser ? "person.fill" : "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(isUser ? "You" : "Claude")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(displayText)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Actions

    private func loadSessions() {
        guard let path = projectPath else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = ClaudeSessionScanner.scan(projectPath: path)
            DispatchQueue.main.async {
                sessions = result
                if let first = result.first {
                    selectedId = first.id
                    loadPreview(for: first.id)
                }
            }
        }
    }

    /// Load preview without flickering: keeps the previously-shown messages visible
    /// until the new ones are ready, then swaps in one frame.
    private func loadPreview(for sessionId: String) {
        guard let path = projectPath else { return }
        previewLoadingFor = sessionId
        DispatchQueue.global(qos: .userInitiated).async {
            let messages = ClaudeSessionScanner.loadPreview(sessionId: sessionId, projectPath: path)
            DispatchQueue.main.async {
                // Drop result if user has moved on to a different session.
                guard previewLoadingFor == sessionId, selectedId == sessionId else { return }
                preview = messages
                previewLoadingFor = nil
            }
        }
    }

    private func submit() {
        guard let id = selectedId else { return }
        onSubmit(id)
    }

    // MARK: - Helpers

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return text.prefix(limit) + "…"
    }
}

/// Translucent glass background for the sheet card.
///
/// Uses NSVisualEffectView with `.behindWindow` blending so the material
/// actually blurs through to the parent terminal window. SwiftUI's
/// `.ultraThinMaterial` defaults to within-window blending and renders as
/// an opaque gray when the view lives in a separate panel/window.
private struct SheetGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
