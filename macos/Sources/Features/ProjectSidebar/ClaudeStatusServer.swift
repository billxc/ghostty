import Foundation
import AppKit
import os

private let statusLogger = Logger(subsystem: "com.mitchellh.ghostty", category: "claude-status")

/// Status of a Claude Code tab.
enum ClaudeTabStatus: Equatable {
    case idle
    /// AI is thinking (orange pulsing).
    case pending
    /// AI finished, response ready (green).
    case completed
    /// AI needs user action (red).
    case actionNeeded
}

/// Listens on a Unix Domain Socket for Claude Code status updates.
///
/// Hook JSON format:
/// ```json
/// {
///   "event": "Start" | "Stop" | "PermissionRequest" | "SessionEnd",
///   "tabId": "unique-tab-id"
/// }
/// ```
class ClaudeStatusServer {
    static let socketDir = "/tmp/ghostty-claude"
    let socketPath: String

    private var socketFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.mitchellh.ghostty.claude-status", qos: .utility)

    /// Called on main thread when tab statuses change.
    var onStatusChange: (([String: ClaudeTabStatus]) -> Void)?

    /// Tab statuses keyed by tab ID.
    private var tabStatuses: [String: ClaudeTabStatus] = [:]

    init() {
        self.socketPath = "\(Self.socketDir)/\(ProcessInfo.processInfo.processIdentifier).sock"
    }

    /// Dismiss status for a tab when user focuses it.
    /// Clears completed and actionNeeded; pending stays (AI is still working).
    func dismissStatus(for tabId: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let status = self.tabStatuses[tabId] else { return }
            switch status {
            case .completed, .actionNeeded:
                self.tabStatuses.removeValue(forKey: tabId)
            case .pending:
                return  // AI still working, don't dismiss
            case .idle:
                return
            }
            let snapshot = self.tabStatuses
            DispatchQueue.main.async {
                self.onStatusChange?(snapshot)
            }
        }
    }

    func start() {
        queue.async { [weak self] in
            self?.setupSocket()
        }
    }

    func stop() {
        listenSource?.cancel()
        listenSource = nil
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
        unlink(socketPath)
    }

    private func setupSocket() {
        mkdir(Self.socketDir, 0o755)
        unlink(socketPath)

        socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            statusLogger.error("Failed to create socket")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            raw.copyMemory(from: Array(pathBytes), byteCount: pathBytes.count)
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(socketFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            statusLogger.error("Failed to bind socket: \(errno)")
            close(socketFD)
            socketFD = -1
            return
        }

        chmod(Self.socketDir, 0o755)
        chmod(socketPath, 0o777)

        guard Darwin.listen(socketFD, 5) == 0 else {
            statusLogger.error("Failed to listen on socket")
            close(socketFD)
            socketFD = -1
            return
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.socketFD, fd >= 0 {
                close(fd)
                self?.socketFD = -1
            }
        }
        source.resume()
        listenSource = source
        statusLogger.info("Claude status socket listening at \(self.socketPath)")
    }

    private func acceptConnection() {
        let clientFD = accept(socketFD, nil, nil)
        guard clientFD >= 0 else { return }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(clientFD, &buffer, buffer.count)
        close(clientFD)

        guard bytesRead > 0 else { return }
        let data = Data(buffer[0..<bytesRead])

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let event = json["event"],
              let tabId = json["tabId"] else {
            return
        }

        var playSound = false

        switch event {
        case "Start":
            tabStatuses[tabId] = .pending

        case "Stop":
            if tabStatuses[tabId] != nil {
                tabStatuses[tabId] = .completed
                playSound = true
            }

        case "PermissionRequest":
            if tabStatuses[tabId] != nil {
                tabStatuses[tabId] = .actionNeeded
                playSound = true
            }

        case "SessionEnd":
            tabStatuses.removeValue(forKey: tabId)

        default:
            break
        }

        let snapshot = tabStatuses

        DispatchQueue.main.async { [weak self] in
            if playSound {
                NSSound.beep()
            }
            self?.onStatusChange?(snapshot)
        }
    }

    deinit {
        stop()
    }
}
