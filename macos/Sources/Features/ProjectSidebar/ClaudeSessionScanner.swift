import Foundation

/// Scans Claude Code's session storage to find historical sessions for a project.
///
/// Claude stores each session as a JSONL file under:
///   ~/.claude/projects/<encoded-cwd>/<session-uuid>.jsonl
///
/// Where `encoded-cwd` replaces both `/` and `.` with `-` in the absolute project path.
///
/// Two-stage API:
///   - `listSessions` returns lightweight stubs (id + mtime) with no file reads
///   - `loadMetadata` is called per stub to populate first/last prompt + counts
/// This lets the UI render the list instantly and only pay the per-file read
/// cost for rows the user actually scrolls into view.
enum ClaudeSessionScanner {
    /// Lightweight session reference — no file content read yet.
    struct SessionStub: Identifiable, Hashable {
        let id: String
        let lastModified: Date
    }

    /// Metadata extracted from a session's jsonl content.
    struct SessionMetadata: Hashable {
        let firstPrompt: String
        let lastPrompt: String
        let userMessageCount: Int
    }

    struct PreviewMessage: Identifiable, Hashable {
        let id: String
        let role: String
        let text: String
    }

    /// Encode an absolute path the same way Claude does.
    /// `/`, `.`, and `_` are all replaced with `-`, so:
    ///   `/Users/me/code/ghostty`           → `-Users-me-code-ghostty`
    ///   `/Users/me/.boxagent/work`         → `-Users-me--boxagent-work`
    ///   `/Users/me/code/browser_dev/x`     → `-Users-me-code-browser-dev-x`
    static func encodePath(_ path: String) -> String {
        return path
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: "_", with: "-")
    }

    /// Directory under ~/.claude/projects/ for a given project path.
    static func sessionDir(for projectPath: String) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")
            .appendingPathComponent(encodePath(projectPath))
    }

    /// List sessions for the project, sorted by last modified (newest first).
    /// Returns only stubs — no file contents are read here. Optional `limit`
    /// caps the result; pass nil to return all sessions.
    static func listSessions(projectPath: String, limit: Int? = 500) -> [SessionStub] {
        let dir = sessionDir(for: projectPath)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let stubs: [SessionStub] = entries
            .filter { $0.pathExtension == "jsonl" }
            .map { url in
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                return SessionStub(
                    id: url.deletingPathExtension().lastPathComponent,
                    lastModified: mtime
                )
            }
            .sorted { $0.lastModified > $1.lastModified }

        if let limit { return Array(stubs.prefix(limit)) }
        return stubs
    }

    /// Load metadata (first/last user prompt + count) for a single session.
    /// Streams the file via FileHandle so peak memory stays bounded for
    /// multi-MB session logs.
    static func loadMetadata(sessionId: String, projectPath: String) -> SessionMetadata {
        let url = sessionDir(for: projectPath).appendingPathComponent("\(sessionId).jsonl")
        var firstPrompt = ""
        var lastPrompt = ""
        var count = 0

        readLines(at: url) { line in
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { return true }

            guard let type = obj["type"] as? String, type == "user" else { return true }
            guard let content = extractText(from: obj["message"] as? [String: Any]),
                  !content.isEmpty else { return true }

            // Skip tool result messages (auto-generated, often start with `<`)
            if content.hasPrefix("<") { return true }

            if firstPrompt.isEmpty {
                firstPrompt = String(content.prefix(200))
            }
            lastPrompt = String(content.prefix(200))
            count += 1
            return true
        }

        return SessionMetadata(
            firstPrompt: firstPrompt,
            lastPrompt: lastPrompt,
            userMessageCount: count
        )
    }

    /// Read recent messages from a session for preview.
    /// Returns up to `limit` user/assistant messages from the end.
    static func loadPreview(sessionId: String, projectPath: String, limit: Int = 10) -> [PreviewMessage] {
        let url = sessionDir(for: projectPath).appendingPathComponent("\(sessionId).jsonl")

        var messages: [PreviewMessage] = []
        var lineIndex = 0
        readLines(at: url) { line in
            defer { lineIndex += 1 }

            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { return true }

            guard let type = obj["type"] as? String,
                  type == "user" || type == "assistant" else { return true }

            guard let content = extractText(from: obj["message"] as? [String: Any]),
                  !content.isEmpty else { return true }

            messages.append(PreviewMessage(
                id: "\(sessionId):\(lineIndex)",
                role: type,
                text: content
            ))
            return true
        }

        return Array(messages.suffix(limit))
    }

    // MARK: - Private

    /// Extract plain text from a Claude message dict.
    /// `content` can be a string or an array of content blocks. For arrays,
    /// concatenates text from ALL `text` blocks (not just the first), so messages
    /// like `tool_use + text` don't lose their text portion.
    private static func extractText(from message: [String: Any]?) -> String? {
        guard let message else { return nil }
        if let text = message["content"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let blocks = message["content"] as? [[String: Any]] {
            let texts = blocks.compactMap { block -> String? in
                guard block["type"] as? String == "text",
                      let text = block["text"] as? String else { return nil }
                return text
            }
            let joined = texts.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    /// Stream lines from a file using FileHandle. Visitor returns `false` to abort.
    /// Keeps peak memory bounded to the chunk size + one line; safe for very
    /// large jsonl files (multi-MB conversation logs).
    private static func readLines(at url: URL, _ visit: (String) -> Bool) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        var buffer = Data()
        let chunkSize = 64 * 1024
        let newline: UInt8 = 0x0A

        while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
            buffer.append(chunk)
            while let nlPos = buffer.firstIndex(of: newline) {
                let lineData = buffer.subdata(in: 0..<nlPos)
                buffer.removeSubrange(0...nlPos)
                if let line = String(data: lineData, encoding: .utf8) {
                    if !visit(line) { return }
                }
            }
        }
        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
            _ = visit(line)
        }
    }
}
