import Foundation

/// Wraps git subprocess calls for worktree management.
enum GitWorktreeManager {
    static let worktreeBaseDir: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".super-ghostty-worktrees")

    // MARK: - Queries (synchronous, fast)

    static func isGitRepository(at path: String) -> Bool {
        let result = runGit(args: ["rev-parse", "--is-inside-work-tree"], currentDirectory: path)
        return result.exitCode == 0
    }

    static func listLocalBranches(in repoPath: String) -> [String] {
        let result = runGit(args: ["branch", "--format=%(refname:short)"], currentDirectory: repoPath)
        guard result.exitCode == 0 else { return [] }
        return result.stdout
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func currentBranch(in repoPath: String) -> String? {
        let result = runGit(args: ["rev-parse", "--abbrev-ref", "HEAD"], currentDirectory: repoPath)
        guard result.exitCode == 0 else { return nil }
        let branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty ? nil : branch
    }

    static func repoName(from path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    // MARK: - Worktree Operations (async, background thread)

    static func createWorktree(
        repoPath: String,
        branchName: String,
        baseBranch: String?,
        completion: @escaping (Result<String, WorktreeError>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let repo = repoName(from: repoPath)
            let worktreePath = worktreeBaseDir
                .appendingPathComponent(repo)
                .appendingPathComponent(branchName)
                .path

            // Ensure parent directory exists
            let parentDir = URL(fileURLWithPath: worktreePath).deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.directoryCreation(error.localizedDescription)))
                }
                return
            }

            var args = ["worktree", "add", "-b", branchName, worktreePath]
            if let base = baseBranch, !base.isEmpty {
                args.append(base)
            }

            let result = runGit(args: args, currentDirectory: repoPath)
            DispatchQueue.main.async {
                if result.exitCode == 0 {
                    completion(.success(worktreePath))
                } else {
                    let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(.failure(.gitError(msg.isEmpty ? "Unknown git error" : msg)))
                }
            }
        }
    }

    static func removeWorktree(
        worktreePath: String,
        parentRepoPath: String,
        completion: @escaping (Result<Void, WorktreeError>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = runGit(
                args: ["worktree", "remove", worktreePath],
                currentDirectory: parentRepoPath
            )
            DispatchQueue.main.async {
                if result.exitCode == 0 {
                    completion(.success(()))
                } else {
                    let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(.failure(.gitError(msg.isEmpty ? "Unknown git error" : msg)))
                }
            }
        }
    }

    // MARK: - Error Type

    enum WorktreeError: LocalizedError {
        case notGitRepo
        case directoryCreation(String)
        case gitError(String)

        var errorDescription: String? {
            switch self {
            case .notGitRepo:
                return "The active project is not a git repository."
            case .directoryCreation(let msg):
                return "Failed to create directory: \(msg)"
            case .gitError(let msg):
                return msg
            }
        }
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
