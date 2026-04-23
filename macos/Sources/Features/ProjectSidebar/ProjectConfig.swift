import Foundation

/// A quick-launch command configured per project.
struct QuickCommand: Codable, Hashable {
    var name: String
    var command: String
    var icon: String?  // SF Symbols name, nil to show text only
}

/// A single project entry in the sidebar.
struct ProjectConfig: Codable, Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var command: String?
    var icon: String?
    var isWorktree: Bool?
    var parentRepoPath: String?
    var quickCommands: [QuickCommand]?

    /// The command to run when opening this project (defaults to plain terminal).
    var resolvedCommand: String? { command }

    /// Whether this project entry is a git worktree.
    var isWorktreeProject: Bool { isWorktree ?? false }
}

/// Top-level JSON structure for ~/.config/ghostty/projects.json
struct ProjectsFile: Codable {
    var projects: [ProjectConfig]
    var sidebar: SidebarSettings?

    struct SidebarSettings: Codable {
        var width: Double?
        var visible: Bool?
        var activeProjectPath: String?
    }
}

/// Reads and writes the projects configuration file.
enum ProjectConfigStore {
    static let configURL: URL = {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ghostty")
        return configDir.appendingPathComponent("projects.json")
    }()

    static func load() -> ProjectsFile {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return ProjectsFile(projects: [], sidebar: nil)
        }

        do {
            let data = try Data(contentsOf: configURL)
            return try JSONDecoder().decode(ProjectsFile.self, from: data)
        } catch {
            print("[ProjectSidebar] Failed to load projects.json: \(error)")
            return ProjectsFile(projects: [], sidebar: nil)
        }
    }

    static func save(_ file: ProjectsFile) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(file)

            // Ensure the directory exists
            let dir = configURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            try data.write(to: configURL, options: .atomic)
        } catch {
            print("[ProjectSidebar] Failed to save projects.json: \(error)")
        }
    }
}
