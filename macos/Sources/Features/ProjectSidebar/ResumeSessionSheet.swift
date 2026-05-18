import SwiftUI

/// A sheet that lists historical Claude sessions for the current project,
/// previews them, and resumes the selected session in a new tab.
struct ResumeSessionSheet: View {
    let projectPath: String?
    let onSubmit: (_ sessionId: String) -> Void
    let onCancel: () -> Void

    @State private var sessions: [ClaudeSessionScanner.SessionStub] = []
    @State private var selectedId: String?
    @State private var preview: [ClaudeSessionScanner.PreviewMessage] = []
    @State private var previewLoadingFor: String?

    /// Cache of metadata loaded lazily as rows scroll into view.
    @State private var metadataCache: [String: ClaudeSessionScanner.SessionMetadata] = [:]
    /// IDs currently being fetched in the background — avoids dispatching duplicates.
    @State private var metadataInFlight: Set<String> = []

    /// Preview cache keyed by session id, populated both by the selection-driven
    /// loader and by the search-driven batch loader. Used so search can match
    /// against message bodies, not just the first prompt.
    @State private var previewCache: [String: [ClaudeSessionScanner.PreviewMessage]] = [:]

    @State private var searchText: String = ""
    /// True once the search-triggered batch load has been kicked off for the
    /// current `sessions` list. Reset whenever sessions reload.
    @State private var bulkLoadStarted: Bool = false
    @FocusState private var searchFocused: Bool

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
        .onChange(of: filteredSessions) { newList in
            if let sel = selectedId, newList.contains(where: { $0.id == sel }) { return }
            selectedId = newList.first?.id
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

            searchField
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
                .frame(width: 180)
                .onChange(of: searchText) { newValue in
                    if !newValue.isEmpty { startBulkLoadIfNeeded() }
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .background(
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if !sessions.isEmpty {
                let total = sessions.count
                let shown = filteredSessions.count
                let label = searchText.isEmpty
                    ? "\(total) session\(total == 1 ? "" : "s")"
                    : "\(shown) of \(total)"
                Text(label)
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
            } else if filteredSessions.isEmpty {
                placeholderPreview(
                    icon: "magnifyingglass",
                    text: "No matches for \u{201C}\(searchText)\u{201D}"
                )
            } else {
                List(filteredSessions, selection: $selectedId) { stub in
                    sessionRow(stub)
                        .tag(stub.id as String?)
                        .onAppear { ensureMetadata(for: stub.id) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func sessionRow(_ stub: ClaudeSessionScanner.SessionStub) -> some View {
        let meta = metadataCache[stub.id]
        let title: String
        let isPlaceholder: Bool
        if let meta {
            title = meta.firstPrompt.isEmpty ? "(no prompt)" : meta.firstPrompt
            isPlaceholder = meta.firstPrompt.isEmpty
        } else {
            title = "Loading…"
            isPlaceholder = true
        }

        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isPlaceholder ? .secondary : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .redacted(reason: meta == nil ? .placeholder : [])

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 9))
                    .accessibilityHidden(true)
                Text(relativeTime(stub.lastModified))
                    .font(.system(size: 10))
                if let count = meta?.userMessageCount {
                    Text("·")
                        .font(.system(size: 10))
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 9))
                        .accessibilityHidden(true)
                    Text("\(count)")
                        .font(.system(size: 10))
                        .accessibilityLabel("\(count) user messages")
                }
                Spacer()
                Text(String(stub.id.prefix(8)))
                    .font(.system(size: 9, design: .monospaced))
                    .accessibilityLabel("session id \(stub.id)")
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
            let stubs = ClaudeSessionScanner.listSessions(projectPath: path)
            DispatchQueue.main.async {
                sessions = stubs
                bulkLoadStarted = false
                if let first = stubs.first {
                    selectedId = first.id
                    loadPreview(for: first.id)
                }
            }
        }
    }

    // MARK: - Search

    private var filteredSessions: [ClaudeSessionScanner.SessionStub] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return sessions }
        let qLower = q.lowercased()
        return sessions.filter { stub in
            if stub.id.lowercased().hasPrefix(qLower) { return true }
            if let meta = metadataCache[stub.id] {
                if meta.firstPrompt.localizedCaseInsensitiveContains(q) { return true }
                if meta.lastPrompt.localizedCaseInsensitiveContains(q) { return true }
            }
            if let msgs = previewCache[stub.id] {
                for m in msgs where m.text.localizedCaseInsensitiveContains(q) {
                    return true
                }
            }
            return false
        }
    }

    /// Eagerly load metadata + preview for every session so the search filter
    /// can match content beyond what's been scrolled into view. Runs once per
    /// session list; results stream in and the filter re-evaluates as state updates.
    private func startBulkLoadIfNeeded() {
        guard !bulkLoadStarted, let path = projectPath else { return }
        bulkLoadStarted = true
        let ids = sessions.map { $0.id }
        DispatchQueue.global(qos: .userInitiated).async {
            for id in ids {
                let needMeta = DispatchQueue.main.sync { metadataCache[id] == nil }
                if needMeta {
                    let meta = ClaudeSessionScanner.loadMetadata(sessionId: id, projectPath: path)
                    DispatchQueue.main.async {
                        metadataCache[id] = meta
                        metadataInFlight.remove(id)
                    }
                }
                let needPreview = DispatchQueue.main.sync { previewCache[id] == nil }
                if needPreview {
                    let msgs = ClaudeSessionScanner.loadPreview(sessionId: id, projectPath: path)
                    DispatchQueue.main.async {
                        previewCache[id] = msgs
                    }
                }
            }
        }
    }

    /// Lazy metadata fetch: triggered when a row scrolls into view.
    /// Skips already-cached and in-flight requests.
    private func ensureMetadata(for sessionId: String) {
        guard metadataCache[sessionId] == nil,
              !metadataInFlight.contains(sessionId),
              let path = projectPath else { return }

        metadataInFlight.insert(sessionId)
        DispatchQueue.global(qos: .userInitiated).async {
            let meta = ClaudeSessionScanner.loadMetadata(sessionId: sessionId, projectPath: path)
            DispatchQueue.main.async {
                metadataCache[sessionId] = meta
                metadataInFlight.remove(sessionId)
            }
        }
    }

    /// Load preview without flickering: keep the previously-shown messages visible
    /// until the new ones are ready, then swap in one frame.
    private func loadPreview(for sessionId: String) {
        guard let path = projectPath else { return }
        if let cached = previewCache[sessionId] {
            preview = cached
        }
        previewLoadingFor = sessionId
        DispatchQueue.global(qos: .userInitiated).async {
            let messages = ClaudeSessionScanner.loadPreview(sessionId: sessionId, projectPath: path)
            DispatchQueue.main.async {
                previewCache[sessionId] = messages
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
