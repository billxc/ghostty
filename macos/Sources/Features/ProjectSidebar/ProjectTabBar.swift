import SwiftUI

/// Custom tab bar styled to match macOS native tab bar appearance.
struct ProjectTabBar: View {
    let tabs: [ProjectTabState.TabInfo]
    let selectedIndex: Int?
    var tabStatuses: [String: ClaudeTabStatus] = [:]
    var backgroundColor: Color = Color(nsColor: .windowBackgroundColor)
    var backgroundOpacity: Double = 1.0
    var layout: SidebarLayout = SidebarLayout()
    let onSelect: (NSWindow) -> Void
    let onClose: (NSWindow) -> Void
    let onNewTab: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                if let window = tab.window {
                    TabItemView(
                        tab: tab,
                        isSelected: tab.id == selectedIndex,
                        isOnly: tabs.count == 1,
                        tabStatus: tab.ghosttyTabId.flatMap { tabStatuses[$0] } ?? .idle,
                        themeBackgroundColor: backgroundColor,
                        themeBackgroundOpacity: backgroundOpacity,
                        layout: layout,
                        onSelect: { onSelect(window) },
                        onClose: { onClose(window) }
                    )
                    .contextMenu {
                        if let tabId = tab.ghosttyTabId,
                           let status = tabStatuses[tabId], status != .idle {
                            Button("Clear Status") {
                                ProjectSidebarState.shared.removeClaudeStatus(for: tabId)
                            }
                            Divider()
                        }
                        Button("Close Tab") {
                            onClose(window)
                        }
                        Button("Close Other Tabs") {
                            for other in tabs where other.id != tab.id {
                                if let otherWin = other.window {
                                    onClose(otherWin)
                                }
                            }
                        }
                        .disabled(tabs.count <= 1)
                        Divider()
                        Button("New Tab") {
                            onNewTab()
                        }
                    }

                    // Separator between tabs (not after the last one)
                    if tab.id < tabs.count - 1 {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor).opacity(0.5))
                            .frame(width: 1, height: layout.tabSeparatorHeight)
                    }
                }
            }

            // New tab button
            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: layout.tabPlusFont, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: layout.tabPlusWidth, height: layout.tabHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Tab")

            Spacer()
        }
        .frame(height: layout.tabHeight)
        .background(
            ZStack {
                backgroundColor
                    .opacity(backgroundOpacity)
                // Subtle top-to-bottom gradient for depth
                LinearGradient(
                    colors: [Color.white.opacity(0.04), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
    }
}

private struct TabItemView: View {
    let tab: ProjectTabState.TabInfo
    let isSelected: Bool
    let isOnly: Bool
    var tabStatus: ClaudeTabStatus = .idle
    var themeBackgroundColor: Color = Color(nsColor: .controlBackgroundColor)
    var themeBackgroundOpacity: Double = 1.0
    var layout: SidebarLayout = SidebarLayout()
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    @State private var isCloseHovering = false

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                // Background — fills the full tab height
                Rectangle()
                    .fill(backgroundColor)
                    .padding(.horizontal, 0)

                HStack(spacing: 0) {
                    // Running indicator (per-tab status)
                    if tabStatus != .idle {
                        StatusDot(status: tabStatus, layout: layout)
                            .padding(.trailing, 4)
                    }

                    // Tab title
                    Text(tab.title.isEmpty ? "Terminal" : tab.title)
                        .font(.system(size: layout.tabTitleFont, weight: isSelected ? .medium : .regular))
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity)

                    // Close button (visible on hover or selected, except if only tab)
                    if !isOnly {
                        Group {
                            if isHovering || isSelected {
                                Button(action: onClose) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: layout.tabCloseFont, weight: .bold))
                                        .foregroundColor(isCloseHovering ? .primary : .secondary)
                                        .frame(width: layout.tabCloseSize, height: layout.tabCloseSize)
                                        .background(
                                            Circle()
                                                .fill(isCloseHovering ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06))
                                        )
                                }
                                .buttonStyle(.plain)
                                .onHover { isCloseHovering = $0 }
                            } else {
                                Color.clear.frame(width: layout.tabCloseSize, height: layout.tabCloseSize)
                            }
                        }
                        .padding(.leading, 4)
                    }
                }
                .padding(.horizontal, layout.tabHPadding)
            }
            .frame(minWidth: layout.tabMinWidth, idealWidth: layout.tabIdealWidth, maxWidth: layout.tabMaxWidth, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        if isSelected {
            return themeBackgroundColor.opacity(themeBackgroundOpacity * 0.85)
        } else if isHovering {
            return Color.primary.opacity(0.04)
        } else {
            return Color.clear
        }
    }
}
