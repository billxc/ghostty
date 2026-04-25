import SwiftUI

/// Manages cached tab state for the custom tab bar.
/// Separated from ProjectSidebarState to avoid cascading re-renders
/// when only tab state changes (not sidebar visibility/width/projects).
class ProjectTabState: ObservableObject {
    static let shared = ProjectTabState()

    struct TabInfo: Identifiable {
        let id: Int
        let title: String
        weak var window: NSWindow?
        let windowIdentifier: ObjectIdentifier
        let ghosttyTabId: String?
        let isLazygit: Bool
        let quickCommandName: String?
    }

    @Published private(set) var tabs: [TabInfo] = []
    @Published private(set) var selectedTabIndex: Int? = nil

    /// Custom ordering: stores window ObjectIdentifiers in the user's preferred order.
    /// When nil, uses the default AppKit order.
    private var customOrder: [ObjectIdentifier]?

    /// Recompute tab list from AppKit window state.
    /// Only publishes if the result actually changed.
    /// Preserves user's custom drag order via stable merge.
    func refresh(for projectPath: String?, in window: NSWindow?) {
        let windows = ProjectSidebarState.shared.tabWindows(for: projectPath, in: window)

        // Build lookup from window identifier to NSWindow
        let windowMap = Dictionary(uniqueKeysWithValues: windows.map { (ObjectIdentifier($0), $0) })
        let currentIds = Set(windowMap.keys)

        // Stable merge: keep existing custom order, append new tabs, remove closed ones
        let orderedWindows: [NSWindow]
        if let custom = customOrder {
            var result: [NSWindow] = []
            for id in custom {
                if let win = windowMap[id] {
                    result.append(win)
                }
            }
            // Append any new windows not in custom order
            for win in windows where !custom.contains(ObjectIdentifier(win)) {
                result.append(win)
            }
            // Update custom order to reflect current state
            customOrder = result.map { ObjectIdentifier($0) }
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
        }
    }

    /// Move a tab from one position to another (drag-to-reorder).
    func moveTab(from source: Int, to destination: Int) {
        guard source != destination,
              source >= 0, source < tabs.count,
              destination >= 0, destination < tabs.count else { return }

        // Initialize custom order from current state if needed
        if customOrder == nil {
            customOrder = tabs.map { $0.windowIdentifier }
        }

        customOrder!.move(fromOffsets: IndexSet(integer: source),
                          toOffset: destination > source ? destination + 1 : destination)

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
