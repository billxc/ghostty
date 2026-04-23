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
    }

    @Published private(set) var tabs: [TabInfo] = []
    @Published private(set) var selectedTabIndex: Int? = nil

    /// Recompute tab list from AppKit window state.
    /// Only publishes if the result actually changed.
    func refresh(for projectPath: String?, in window: NSWindow?) {
        let windows = ProjectSidebarState.shared.tabWindows(for: projectPath, in: window)
        let newTabs = windows.enumerated().map { i, win in
            let tabId = (win.windowController as? TerminalController)?.ghosttyTabId
            return TabInfo(
                id: i,
                title: win.title,
                window: win,
                windowIdentifier: ObjectIdentifier(win),
                ghosttyTabId: tabId
            )
        }

        let selected = window?.tabGroup?.selectedWindow ?? window
        let newSelectedIndex = windows.firstIndex(where: { $0 === selected })

        if !tabsEqual(tabs, newTabs) || selectedTabIndex != newSelectedIndex {
            tabs = newTabs
            selectedTabIndex = newSelectedIndex
        }
    }

    private func tabsEqual(_ lhs: [TabInfo], _ rhs: [TabInfo]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy {
            $0.windowIdentifier == $1.windowIdentifier && $0.title == $1.title
        }
    }
}
