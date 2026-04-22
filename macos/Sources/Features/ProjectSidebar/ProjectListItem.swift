import SwiftUI

/// A single row in the project sidebar list.
struct ProjectListItem: View {
    let project: ProjectConfig
    var isActive: Bool = false
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: project.icon ?? "folder.fill")
                    .font(.system(size: 14))
                    .foregroundColor(isActive ? .white : .accentColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name)
                        .font(.system(size: 13, weight: isActive ? .bold : .medium))
                        .foregroundColor(isActive ? .white : .primary)
                        .lineLimit(1)

                    Text(shortenedPath(project.path))
                        .font(.system(size: 10))
                        .foregroundColor(isActive ? .white.opacity(0.7) : .secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var backgroundColor: Color {
        if isActive {
            return Color.accentColor
        } else if isHovering {
            return Color.primary.opacity(0.08)
        } else {
            return Color.clear
        }
    }

    private func shortenedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
