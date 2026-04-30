import Foundation

/// Scans Claude Code's session storage to find historical sessions for a project.
///
/// Claude stores each session as a JSONL file under:
///   ~/.claude/projects/<encoded-cwd>/<session-uuid>.jsonl
///
/// Where `encoded-cwd` replaces both `/` and `.` with `-` in the absolute project path.
enum ClaudeSessionScanner {
    struct SessionInfo: Identifiable, Hashable {
        let id: String
        let firstPrompt: String
        let lastPrompt: String
        let lastModified: Date
        let userMessageCount: Int
    }

    struct PreviewMessage: Identifiable, Hashable {
        let id: String
        let role: String
        let text: String
    }

    /// Encode an absolute path the same way Claude does.
    /// Both `/` and `.` are replaced with `-`, so:
    ///   `/Users/me/code/ghostty`     → `-Users-me-code-ghostty`
    ///   `/Users/me/.boxagent/work`   → `-Users-me--boxagent-work`
    static func encodePath(_ path: String) -> String {
        return path
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    /// Directory under ~/.claude/projects/ for a given project path.
    static func sessionDir(for projectPath: String) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")
            .appendingPathComponent(encodePath(projectPath))
    }

    /// Scan all .jsonl files in the project's session directory.
    /// Returns up to `limit` sessions sorted by last modified time (newest first).
    ///
    /// Performance: directory listing first to gather (url, mtime), then sort
    /// and take top N — only reads file content for the N selected files.
    /// Per-file content is streamed via `FileHandle` rather than loaded as a
    /// single `Data` blob, keeping peak memory bounded.
    static func scan(projectPath: String, limit: Int = 50) -> [SessionInfo] {
        let dir = sessionDir(for: projectPath)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        // Pass 1: cheap directory listing — just (url, mtime).
        let candidates: [(url: URL, mtime: Date)] = entries
            .filter { $0.pathExtension == "jsonl" }
            .map { url in
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                return (url, mtime)
            }

        // Sort newest first, then keep only the top `limit` for the expensive read pass.
        let topCandidates = candidates.sorted { $0.mtime > $1.mtime }.prefix(limit)

        // Pass 2: stream-read metadata only for the top N files.
        var infos: [SessionInfo] = []
        infos.reserveCapacity(topCandidates.count)
        for (url, mtime) in topCandidates {
            let id = url.deletingPathExtension().lastPathComponent
            let metadata = readMetadata(from: url)
            guard !metadata.firstPrompt.isEmpty || metadata.userMessageCount > 0 else { continue }
            infos.append(SessionInfo(
                id: id,
                firstPrompt: metadata.firstPrompt,
                lastPrompt: metadata.lastPrompt,
                lastModified: mtime,
                userMessageCount: metadata.userMessageCount
            ))
        }
        return infos
    }

    /// Read recent messages from a session for preview.
    /// Returns up to `limit` user/assistant messages from the end.
    /// Streams the file rather than loading it whole.
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

    private struct Metadata {
        var firstPrompt: String = ""
        var lastPrompt: String = ""
        var userMessageCount: Int = 0
    }

    /// Single-pass scan to extract first/last user prompts and count user messages.
    /// Streams the file via `readLines` so peak memory stays bounded regardless
    /// of how large the session log is.
    private static func readMetadata(from url: URL) -> Metadata {
        var meta = Metadata()
        readLines(at: url) { line in
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { return true }

            guard let type = obj["type"] as? String, type == "user" else { return true }
            guard let content = extractText(from: obj["message"] as? [String: Any]),
                  !content.isEmpty else { return true }

            // Skip tool result messages (they appear as type:user but are auto-generated)
            if content.hasPrefix("<") { return true }

            if meta.firstPrompt.isEmpty {
                meta.firstPrompt = String(content.prefix(200))
            }
            meta.lastPrompt = String(content.prefix(200))
            meta.userMessageCount += 1
            return true
        }
        return meta
    }

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
        // Trailing line without a final newline
        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
            _ = visit(line)
        }
    }
}
