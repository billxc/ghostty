import Foundation

/// Centralized default quick commands and related constants.
/// All default command definitions live here — do NOT hardcode them elsewhere.
enum QuickCommandDefaults {
    // MARK: - Command strings

    static let claudeCommand = "claude --dangerously-skip-permissions"
    static let codexCommand = "codex --dangerously-bypass-approvals-and-sandbox"
    static let copilotCommand = "copilot"
    static let lazygitCommand = "lazygit"

    // MARK: - Limits

    static let maxCommands = 10

    // MARK: - Default quick commands (shown when project has no custom commands)

    static let defaultCommands: [QuickCommand] = [
        QuickCommand(name: "Claude", command: claudeCommand, icon: "brain"),
        QuickCommand(name: "Codex", command: codexCommand, icon: "chevron.left.forwardslash.chevron.right"),
        QuickCommand(name: "Copilot", command: copilotCommand, icon: "sparkles"),
        QuickCommand(name: "Lazygit", command: lazygitCommand, icon: "arrow.triangle.branch", reuseTab: true),
    ]

    // MARK: - AI tools for Ask AI sheet (subset of defaults)

    typealias AITool = (name: String, command: String, icon: String)

    static let aiTools: [AITool] = [
        (name: "Claude", command: claudeCommand, icon: "brain"),
        (name: "Codex", command: codexCommand, icon: "chevron.left.forwardslash.chevron.right"),
        (name: "Copilot", command: copilotCommand, icon: "sparkles"),
    ]
}
