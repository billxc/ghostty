import Foundation
import GhosttyKit

/// Welcome surface: a near-zero-cost placeholder shown when a window would
/// otherwise spawn a full login shell with nothing meaningful to do (e.g.
/// app launch with no projects configured). Backed by the `ghostty-welcome`
/// binary built from `src/welcome/main.zig`.
///
/// Surface/Metal/keybind pipeline still runs as normal — only the PTY child
/// is replaced, so all keyboard shortcuts behave exactly the same as in a
/// real terminal tab.
enum WelcomeSurface {
    /// Absolute path to the `ghostty-welcome` binary inside the .app bundle.
    /// Returns nil if the binary is missing (older builds before this was
    /// embedded), in which case callers fall back to the default shell.
    static let binaryPath: String? = {
        guard let exec = Bundle.main.executableURL else { return nil }
        let candidate = exec.deletingLastPathComponent()
            .appendingPathComponent("ghostty-welcome")
            .path
        return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
    }()

    /// Build a SurfaceConfiguration that runs the welcome binary as the
    /// PTY child. Returns nil when the binary isn't available so callers
    /// can fall back to default behaviour.
    static func makeBaseConfig() -> Ghostty.SurfaceConfiguration? {
        guard let path = binaryPath else { return nil }
        var config = Ghostty.SurfaceConfiguration()
        config.command = path
        return config
    }

    /// True when the given config was produced by `makeBaseConfig` — used
    /// to mark the resulting TerminalController so we can auto-close it
    /// when a real tab opens in the same window.
    static func isWelcomeConfig(_ config: Ghostty.SurfaceConfiguration?) -> Bool {
        guard let path = binaryPath, let cmd = config?.command else { return false }
        return cmd == path
    }
}
