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
    var disableGit: Bool?

    /// The command to run when opening this project (defaults to plain terminal).
    var resolvedCommand: String? { command }

    /// Whether this project entry is a git worktree.
    var isWorktreeProject: Bool { isWorktree ?? false }

    /// Whether git status polling is disabled for this project.
    var isGitDisabled: Bool { disableGit ?? false }
}

/// Top-level JSON structure for ~/.config/ghostty/projects.json
struct ProjectsFile: Codable {
    var projects: [ProjectConfig]
    var archivedProjects: [ProjectConfig]?
    var sidebar: SidebarSettings?

    struct SidebarSettings: Codable {
        var width: Double?
        var visible: Bool?
        var activeProjectPath: String?
        var uiScale: Double?
    }
}

/// Reads and writes the projects configuration file.
enum ProjectConfigStore {
    static let configURL: URL = {
        #if DEBUG
        let dirName = ".config/ghostty-debug"
        #else
        let dirName = ".config/ghostty"
        #endif
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(dirName)
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

/// Centralized layout constants scaled by `uiScale` from projects.json.
/// Default scale is 1.0; range clamped to 0.5–2.0.
struct SidebarLayout {
    let scale: CGFloat

    init(scale: CGFloat = 1.0) {
        self.scale = max(0.5, min(2.0, scale))
    }

    private func s(_ v: CGFloat) -> CGFloat { v * scale }

    // MARK: - Sidebar width

    var defaultWidth: CGFloat { s(240) }
    var minWidth: CGFloat { s(150) }
    var maxWidth: CGFloat { s(450) }

    // MARK: - Sidebar header

    var headerFont: CGFloat { s(14) }
    var headerHPadding: CGFloat { s(12) }
    var headerTopPadding: CGFloat { s(14) }
    var headerBottomPadding: CGFloat { s(10) }

    // MARK: - Project list

    var listSpacing: CGFloat { s(4) }
    var listHPadding: CGFloat { s(6) }

    // MARK: - Add project button

    var addButtonFont: CGFloat { s(14) }
    var addButtonHPadding: CGFloat { s(12) }
    var addButtonVPadding: CGFloat { s(10) }

    // MARK: - Project list item

    var itemIconFont: CGFloat { s(16) }
    var itemIconWidth: CGFloat { s(24) }
    var itemNameFont: CGFloat { s(15) }
    var itemPathFont: CGFloat { s(12) }
    var itemHSpacing: CGFloat { s(10) }
    var itemVSpacing: CGFloat { s(2) }
    var itemHPadding: CGFloat { s(10) }
    var itemVPadding: CGFloat { s(8) }
    var itemCornerRadius: CGFloat { s(8) }

    // MARK: - Git badge

    var gitIconFont: CGFloat { s(10) }
    var gitBranchFont: CGFloat { s(12) }
    var gitDirtyFont: CGFloat { s(12) }
    var gitAheadBehindFont: CGFloat { s(11) }
    var gitBadgeSpacing: CGFloat { s(4) }

    // MARK: - Status dot

    var statusDotSize: CGFloat { s(10) }

    // MARK: - Tab bar

    var tabHeight: CGFloat { s(42) }
    var tabTitleFont: CGFloat { s(13.5) }
    var tabSeparatorHeight: CGFloat { s(22) }
    var tabPlusFont: CGFloat { s(13) }
    var tabPlusWidth: CGFloat { s(38) }
    var tabMinWidth: CGFloat { s(100) }
    var tabIdealWidth: CGFloat { s(180) }
    var tabMaxWidth: CGFloat { s(260) }
    var tabHPadding: CGFloat { s(12) }
    var tabCloseSize: CGFloat { s(18) }
    var tabCloseFont: CGFloat { s(9) }

    // MARK: - Quick launch bar

    var quickBarHeight: CGFloat { s(38) }
    var quickBarHPadding: CGFloat { s(8) }
    var quickBarVPadding: CGFloat { s(6) }
    var quickBarSpacing: CGFloat { s(4) }
    var quickButtonIconFont: CGFloat { s(12) }
    var quickButtonNameFont: CGFloat { s(13) }
    var quickButtonHPadding: CGFloat { s(10) }
    var quickButtonVPadding: CGFloat { s(6) }
    var quickButtonCornerRadius: CGFloat { s(6) }
    var quickButtonSpacing: CGFloat { s(5) }
}
