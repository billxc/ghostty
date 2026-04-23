import Foundation

/// Git status information for a project directory.
struct GitStatusInfo {
    let branch: String
    let isDirty: Bool
    let ahead: Int
    let behind: Int
}

/// Fetches git status for project directories.
enum GitStatusManager {

    /// Fetch git status for a directory. Returns nil if not a git repo.
    /// **Must be called off the main thread** — runs synchronous git subprocesses.
    static func fetchStatus(at path: String) -> GitStatusInfo? {
        // Check if this is a git repo
        let check = runGit(args: ["rev-parse", "--is-inside-work-tree"], currentDirectory: path)
        guard check.exitCode == 0 else { return nil }

        // Branch name
        let branchResult = runGit(args: ["rev-parse", "--abbrev-ref", "HEAD"], currentDirectory: path)
        let branch: String
        if branchResult.exitCode == 0 {
            let raw = branchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            branch = raw.isEmpty ? "HEAD" : raw
        } else {
            branch = "HEAD"
        }

        // Dirty check
        let statusResult = runGit(args: ["status", "--porcelain"], currentDirectory: path)
        let isDirty = statusResult.exitCode == 0
            && !statusResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // Ahead / behind upstream
        var ahead = 0
        var behind = 0
        let revResult = runGit(
            args: ["rev-list", "--left-right", "--count", "HEAD...@{upstream}"],
            currentDirectory: path
        )
        if revResult.exitCode == 0 {
            let parts = revResult.stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\t")
            if parts.count == 2 {
                ahead = Int(parts[0]) ?? 0
                behind = Int(parts[1]) ?? 0
            }
        }

        return GitStatusInfo(branch: branch, isDirty: isDirty, ahead: ahead, behind: behind)
    }

    // MARK: - Private

    private struct GitResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private static func runGit(args: [String], currentDirectory: String) -> GitResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return GitResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return GitResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
