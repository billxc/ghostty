import SwiftUI

/// Manages cached tab state for the custom tab bar.
/// Separated from ProjectSidebarState to avoid cascading re-renders
/// when only tab state changes (not sidebar visibility/width/projects).
class ProjectTabState: ObservableObject {
    static let shared = ProjectTabState()

    struct TabInfo: Identifiable, Equatable {
        let id: Int
        let title: String
        weak var window: NSWindow?
        let windowIdentifier: ObjectIdentifier
        let ghosttyTabId: String?
        let isLazygit: Bool
        let quickCommandName: String?

        static func == (lhs: TabInfo, rhs: TabInfo) -> Bool {
            lhs.id == rhs.id
                && lhs.title == rhs.title
                && lhs.windowIdentifier == rhs.windowIdentifier
                && lhs.ghosttyTabId == rhs.ghosttyTabId
                && lhs.isLazygit == rhs.isLazygit
                && lhs.quickCommandName == rhs.quickCommandName
        }
    }

    @Published private(set) var tabs: [TabInfo] = []
    @Published private(set) var selectedTabIndex: Int? = nil

    /// Custom ordering per project. Stores window ObjectIdentifiers in the
    /// user's preferred order. Keyed by project path; nil-project (bare
    /// windows) uses the empty-string key. A missing key means "no custom
    /// order yet, use AppKit default".
    private var customOrderByProject: [String: [ObjectIdentifier]] = [:]

    private static func key(for projectPath: String?) -> String {
        projectPath ?? ""
    }

    /// Project path passed to the most recent refresh — used by moveTab so
    /// the drag updates the correct project's custom order.
    private var lastRefreshProjectKey: String = ""

    /// Recompute tab list from AppKit window state.
    /// Only publishes if the result actually changed.
    /// Preserves user's custom drag order via stable merge.
    func refresh(for projectPath: String?, in window: NSWindow?) {
        let windows = ProjectSidebarState.shared.tabWindows(for: projectPath, in: window)
        let projectKey = Self.key(for: projectPath)
        lastRefreshProjectKey = projectKey

        // Build lookup from window identifier to NSWindow
        let windowMap = Dictionary(uniqueKeysWithValues: windows.map { (ObjectIdentifier($0), $0) })

        // Stable merge: keep existing custom order for THIS project, append
        // new tabs, drop closed ones. Other projects' orders stay untouched.
        let orderedWindows: [NSWindow]
        if let custom = customOrderByProject[projectKey] {
            var result: [NSWindow] = []
            for id in custom {
                if let win = windowMap[id] {
                    result.append(win)
                }
            }
            for win in windows where !custom.contains(ObjectIdentifier(win)) {
                result.append(win)
            }
            customOrderByProject[projectKey] = result.map { ObjectIdentifier($0) }
            orderedWindows = result
        } else {
            orderedWindows = windows
        }

        let newTabs = orderedWindows.enumerated().map { i, win in
            let controller = win.windowController as? TerminalController
            let tabId = controller?.ghosttyTabId
            let lazygit = controller?.isLazygitTab ?? false
            let cmdName = controller?.quickCommandName
            return TabInfo(
                id: i,
                title: win.title,
                window: win,
                windowIdentifier: ObjectIdentifier(win),
                ghosttyTabId: tabId,
                isLazygit: lazygit,
                quickCommandName: cmdName
            )
        }

        let selected = window?.tabGroup?.selectedWindow ?? window
        let newSelectedIndex = orderedWindows.firstIndex(where: { $0 === selected })

        if !tabsEqual(tabs, newTabs) || selectedTabIndex != newSelectedIndex {
            tabs = newTabs
            selectedTabIndex = newSelectedIndex
            // Tab/window set changed — let the Claude status cache rebuild
            // its per-project index (cheap; one walk of NSApp.windows).
            ClaudeStatusStore.shared.notifyTabsChanged()
        }
    }

    /// Move a tab from one position to another (drag-to-reorder).
    func moveTab(from source: Int, to destination: Int) {
        guard source != destination,
              source >= 0, source < tabs.count,
              destination >= 0, destination < tabs.count else { return }

        let projectKey = lastRefreshProjectKey
        // Initialize this project's custom order from current state if needed
        if customOrderByProject[projectKey] == nil {
            customOrderByProject[projectKey] = tabs.map { $0.windowIdentifier }
        }

        customOrderByProject[projectKey]!.move(
            fromOffsets: IndexSet(integer: source),
            toOffset: destination > source ? destination + 1 : destination
        )

        // Re-index tabs to match new order
        var reordered = tabs
        let moved = reordered.remove(at: source)
        let insertAt = destination > source ? destination : destination
        reordered.insert(moved, at: insertAt)

        // Re-assign sequential IDs
        tabs = reordered.enumerated().map { i, tab in
            TabInfo(id: i, title: tab.title, window: tab.window,
                    windowIdentifier: tab.windowIdentifier,
                    ghosttyTabId: tab.ghosttyTabId, isLazygit: tab.isLazygit,
                    quickCommandName: tab.quickCommandName)
        }

        // Update selected index
        if let selected = tabs.first(where: { $0.window === (tabs.first?.window?.tabGroup?.selectedWindow) }) {
            selectedTabIndex = selected.id
        }
    }

    private func tabsEqual(_ lhs: [TabInfo], _ rhs: [TabInfo]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy {
            $0.windowIdentifier == $1.windowIdentifier && $0.title == $1.title
        }
    }
}
