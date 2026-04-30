import Cocoa

/// Persists active Claude session IDs across app restarts so they can be
/// resumed with `claude --resume <id>` on the next launch.
///
/// Strategy: at launch time, inject `--session-id <uuid>` into the claude
/// command so we control the session ID. At quit time, save it. At next
/// launch, use `--resume <id>` to restore.
enum ClaudeSessionPersistence {
    // MARK: - Types

    struct SavedTab: Codable {
        let projectPath: String
        let quickCommand: String
        let quickCommandName: String
        let claudeSessionId: String
    }

    struct SavedState: Codable {
        let savedAt: Date
        let tabs: [SavedTab]
    }

    // MARK: - File path (same pattern as ProjectConfigStore)

    static let stateURL: URL = {
        #if DEBUG
        let dirName = ".config/ghostty-debug"
        #else
        let dirName = ".config/ghostty"
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(dirName)
            .appendingPathComponent("claude-sessions.json")
    }()

    // MARK: - Save

    /// Collect all running Claude tabs and persist their session IDs.
    static func save() {
        var saved: [SavedTab] = []
        let archivedPaths = Set(ProjectSidebarState.shared.archivedProjects.map { $0.path })

        for controller in TerminalController.all {
            guard let sessionId = controller.claudeSessionId,
                  let cmd = controller.quickCommand else { continue }

            let path = controller.project?.path ?? ""
            if archivedPaths.contains(path) {
                print("[ClaudeSession] Skipping save for archived project: \(path)")
                continue
            }
            saved.append(SavedTab(
                projectPath: path,
                quickCommand: cmd,
                quickCommandName: controller.quickCommandName ?? "",
                claudeSessionId: sessionId
            ))
        }

        guard !saved.isEmpty else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(SavedState(savedAt: Date(), tabs: saved))

            let dir = stateURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: stateURL, options: .atomic)

            print("[ClaudeSession] Saved \(saved.count) session(s)")
        } catch {
            print("[ClaudeSession] Failed to save: \(error)")
        }
    }

    // MARK: - Load & clear

    /// Read saved sessions and delete the file to prevent double-restore.
    /// Sanitizes loaded `quickCommand` values by stripping any stale
    /// `--resume` / `--session-id` flags — historical disk state from
    /// older versions could contain these baked in, which would cause
    /// flag-stacking on each save/restore cycle.
    static func loadAndClear() -> [SavedTab] {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return [] }

        defer {
            try? FileManager.default.removeItem(at: stateURL)
        }

        do {
            let data = try Data(contentsOf: stateURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(SavedState.self, from: data)

            let cleaned = state.tabs.map { tab in
                SavedTab(
                    projectPath: tab.projectPath,
                    quickCommand: stripSessionFlags(tab.quickCommand),
                    quickCommandName: tab.quickCommandName,
                    claudeSessionId: tab.claudeSessionId
                )
            }

            print("[ClaudeSession] Loaded \(cleaned.count) session(s) to restore")
            return cleaned
        } catch {
            print("[ClaudeSession] Failed to load: \(error)")
            return []
        }
    }

    // MARK: - Command helpers

    /// Detect whether a quick command invokes `claude`.
    static func isClaudeCommand(_ command: String) -> Bool {
        let base = command.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ").first ?? ""
        return base == "claude"
    }

    /// Inject `--session-id <uuid>` into a claude command.
    /// If it already has `--resume <id>` or `--session-id <id>`, extract and reuse that ID.
    /// Returns (transformedCommand, sessionId).
    static func injectSessionId(into command: String) -> (String, String) {
        let parts = command.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ")

        // Already has --resume <id> (restored session) — keep as-is.
        if let idx = parts.firstIndex(of: "--resume"),
           idx + 1 < parts.count {
            return (command, parts[idx + 1])
        }

        // Already has --session-id <id> — keep as-is.
        if let idx = parts.firstIndex(of: "--session-id"),
           idx + 1 < parts.count {
            return (command, parts[idx + 1])
        }

        // Fresh launch: inject --session-id <new-uuid>.
        let sessionId = UUID().uuidString.lowercased()
        var result = [parts[0], "--session-id", sessionId]
        result.append(contentsOf: parts.dropFirst())
        return (result.joined(separator: " "), sessionId)
    }

    /// Build a resume command from a base command + session ID.
    /// Assumes input is already a clean base command (no `--resume` / `--session-id`);
    /// the invariant is enforced by `ProjectToolLauncher.launch()` callers always
    /// passing base commands.
    static func buildResumeCommand(originalCommand: String, sessionId: String) -> String {
        var parts = originalCommand.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ")
        var result = [parts[0], "--resume", sessionId]
        result.append(contentsOf: parts.dropFirst())
        return result.joined(separator: " ")
    }

    // MARK: - Boundary defense

    /// Remove any `--session-id <value>` or `--resume <value>` pair from a
    /// command. Used only at the persistence boundary (`loadAndClear`) to
    /// sanitize potentially-polluted disk state from older app versions.
    private static func stripSessionFlags(_ command: String) -> String {
        var parts = command.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ")

        for flag in ["--session-id", "--resume"] {
            while let idx = parts.firstIndex(of: flag), idx + 1 < parts.count {
                parts.removeSubrange(idx...idx + 1)
            }
        }

        return parts.joined(separator: " ")
    }
}
