import SwiftUI

/// Custom tab bar styled to match macOS native tab bar appearance.
struct ProjectTabBar: View {
    let tabs: [TabInfo]
    let selectedIndex: Int?
    var backgroundColor: Color = Color(nsColor: .windowBackgroundColor)
    var backgroundOpacity: Double = 1.0
    let onSelect: (NSWindow) -> Void
    let onClose: (NSWindow) -> Void
    let onNewTab: () -> Void

    struct TabInfo: Identifiable {
        let id: Int
        let title: String
        let window: NSWindow
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                TabItemView(
                    tab: tab,
                    isSelected: tab.id == selectedIndex,
                    isOnly: tabs.count == 1,
                    themeBackgroundColor: backgroundColor,
                    themeBackgroundOpacity: backgroundOpacity,
                    onSelect: { onSelect(tab.window) },
                    onClose: { onClose(tab.window) }
                )
                .contextMenu {
                    Button("Close Tab") {
                        onClose(tab.window)
                    }
                    Button("Close Other Tabs") {
                        for other in tabs where other.id != tab.id {
                            onClose(other.window)
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
                        .frame(width: 1, height: 18)
                }
            }

            // New tab button
            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Tab")

            Spacer()
        }
        .frame(height: 36)
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
    let tab: ProjectTabBar.TabInfo
    let isSelected: Bool
    let isOnly: Bool
    var themeBackgroundColor: Color = Color(nsColor: .controlBackgroundColor)
    var themeBackgroundOpacity: Double = 1.0
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
                    // Tab title
                    Text(tab.title.isEmpty ? "Terminal" : tab.title)
                        .font(.system(size: 11.5, weight: isSelected ? .medium : .regular))
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
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(isCloseHovering ? .primary : .secondary)
                                        .frame(width: 16, height: 16)
                                        .background(
                                            Circle()
                                                .fill(isCloseHovering ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06))
                                        )
                                }
                                .buttonStyle(.plain)
                                .onHover { isCloseHovering = $0 }
                            } else {
                                Color.clear.frame(width: 16, height: 16)
                            }
                        }
                        .padding(.leading, 4)
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(minWidth: 80, idealWidth: 160, maxWidth: 220, maxHeight: .infinity)
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
