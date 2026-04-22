import SwiftUI

/// Custom tab bar styled to match macOS native tab bar appearance.
struct ProjectTabBar: View {
    let tabs: [TabInfo]
    let selectedIndex: Int?
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
                    onSelect: { onSelect(tab.window) },
                    onClose: { onClose(tab.window) }
                )

                // Divider between tabs
                if tab.id < tabs.count - 1 {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 1, height: 20)
                }
            }

            // New tab button
            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(height: 34)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
    }
}

private struct TabItemView: View {
    let tab: ProjectTabBar.TabInfo
    let isSelected: Bool
    let isOnly: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                // Selected tab background
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 4)
                }

                HStack(spacing: 6) {
                    Text(tab.title.isEmpty ? "Terminal" : tab.title)
                        .font(.system(size: 12))
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    // Close button
                    if !isOnly && (isHovering || isSelected) {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 16, height: 16)
                                .background(
                                    Circle()
                                        .fill(Color.primary.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(minWidth: 100, maxWidth: 200, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
