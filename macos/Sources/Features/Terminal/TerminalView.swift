import SwiftUI
import GhosttyKit
import os

/// This delegate is notified of actions and property changes regarding the terminal view. This
/// delegate is optional and can be used by a TerminalView caller to react to changes such as
/// titles being set, cell sizes being changed, etc.
protocol TerminalViewDelegate: AnyObject {
    /// Called when the currently focused surface changed. This can be nil.
    func focusedSurfaceDidChange(to: Ghostty.SurfaceView?)

    /// The URL of the pwd should change.
    func pwdDidChange(to: URL?)

    /// The cell size changed.
    func cellSizeDidChange(to: NSSize)

    /// Perform an action. At the time of writing this is only triggered by the command palette.
    func performAction(_ action: String, on: Ghostty.SurfaceView)

    /// A split tree operation
    func performSplitAction(_ action: TerminalSplitOperation)
}

/// The view model is a required implementation for TerminalView callers. This contains
/// the main state between the TerminalView caller and SwiftUI. This abstraction is what
/// allows AppKit to own most of the data in SwiftUI.
protocol TerminalViewModel: ObservableObject {
    /// The tree of terminal surfaces (splits) within the view. This is mutated by TerminalView
    /// and children. This should be @Published.
    var surfaceTree: SplitTree<Ghostty.SurfaceView> { get set }

    /// The command palette state.
    var commandPaletteIsShowing: Bool { get set }

    /// The update overlay should be visible.
    var updateOverlayIsVisible: Bool { get }
}

/// The main terminal view. This terminal view supports splits.
struct TerminalView<ViewModel: TerminalViewModel>: View {
    @ObservedObject var ghostty: Ghostty.App

    // The required view model
    @ObservedObject var viewModel: ViewModel

    // An optional delegate to receive information about terminal changes.
    weak var delegate: (any TerminalViewDelegate)?

    // Project sidebar state (shared singleton)
    @ObservedObject private var sidebarState = ProjectSidebarState.shared

    // Cached tab state (separate from sidebar to reduce re-render blast radius)
    @ObservedObject private var tabState = ProjectTabState.shared

    /// The most recently focused surface, equal to `focusedSurface` when it is non-nil.
    @State private var lastFocusedSurface: Weak<Ghostty.SurfaceView>?

    // This seems like a crutch after switching from SwiftUI to AppKit lifecycle.
    @FocusState private var focused: Bool

    // Various state values sent back up from the currently focused terminals.
    @FocusedValue(\.ghosttySurfaceView) private var focusedSurface
    @FocusedValue(\.ghosttySurfacePwd) private var surfacePwd
    @FocusedValue(\.ghosttySurfaceCellSize) private var cellSize

    // The pwd of the focused surface as a URL
    private var pwdURL: URL? {
        guard let surfacePwd, surfacePwd != "" else { return nil }
        return URL(fileURLWithPath: surfacePwd)
    }

    var body: some View {
        switch ghostty.readiness {
        case .loading:
            Text("Loading")
        case .error:
            ErrorView()
        case .ready:
            ZStack {
                VStack(spacing: 0) {
                    // Debug build warning disabled for local development
                    // if Ghostty.info.mode == GHOSTTY_BUILD_MODE_DEBUG || Ghostty.info.mode == GHOSTTY_BUILD_MODE_RELEASE_SAFE {
                    //     DebugBuildWarningView()
                    // }

                    HStack(spacing: 0) {
                        if sidebarState.isVisible {
                            ProjectSidebarView(
                                state: sidebarState,
                                backgroundColor: ghostty.config.backgroundColor,
                                backgroundOpacity: ghostty.config.backgroundOpacity,
                                onOpenProject: { project in
                                    sidebarState.switchToProject(project, in: NSApp.keyWindow)
                                    ProjectTabState.shared.refresh(
                                        for: sidebarState.activeProjectPath, in: NSApp.keyWindow)
                                },
                                onShowUnassigned: {
                                    sidebarState.showUnassigned(in: NSApp.keyWindow)
                                    ProjectTabState.shared.refresh(
                                        for: sidebarState.activeProjectPath, in: NSApp.keyWindow)
                                }
                            )
                            .frame(width: sidebarState.width)

                            SidebarResizeHandle(sidebarState: sidebarState)
                        }

                        VStack(spacing: 0) {
                            // Custom tab bar and quick launch — isolated in own view
                            ProjectTabBarSection(
                                tabState: tabState,
                                sidebarState: sidebarState,
                                ghosttyConfig: ghostty.config
                            )

                            TerminalSplitTreeView(
                                tree: viewModel.surfaceTree,
                                action: { delegate?.performSplitAction($0) })
                                .environmentObject(ghostty)
                                .ghosttyLastFocusedSurface(lastFocusedSurface)
                                .focused($focused)
                                .onAppear {
                                    self.focused = true
                                    DispatchQueue.main.async {
                                        if sidebarState.isVisible, let window = NSApp.keyWindow as? TerminalWindow {
                                            window.tabBarAccessoryViewController?.isHidden = true
                                        }
                                    }
                                }
                                .onChange(of: focusedSurface) { newValue in
                                    if newValue != nil {
                                        lastFocusedSurface = .init(newValue)
                                        self.delegate?.focusedSurfaceDidChange(to: newValue)
                                    }
                                    ProjectTabState.shared.refresh(
                                        for: sidebarState.activeProjectPath, in: NSApp.keyWindow)
                                    // Dismiss status for the focused tab
                                    if let controller = NSApp.keyWindow?.windowController as? TerminalController {
                                        sidebarState.dismissClaudeStatus(for: controller.ghosttyTabId)
                                    }
                                }
                                .onChange(of: pwdURL) { newValue in
                                    self.delegate?.pwdDidChange(to: newValue)
                                }
                                .onChange(of: cellSize) { newValue in
                                    guard let size = newValue else { return }
                                    self.delegate?.cellSizeDidChange(to: size)
                                }
                                .frame(idealWidth: lastFocusedSurface?.value?.initialSize?.width,
                                       idealHeight: lastFocusedSurface?.value?.initialSize?.height)
                        }
                    }
                }
                // Ignore safe area to extend up in to the titlebar region if we have the "hidden" titlebar style
                .ignoresSafeArea(.container, edges: ghostty.config.macosTitlebarStyle == .hidden ? .top : [])

                if let surfaceView = lastFocusedSurface?.value {
                    TerminalCommandPaletteView(
                        surfaceView: surfaceView,
                        isPresented: $viewModel.commandPaletteIsShowing,
                        ghosttyConfig: ghostty.config,
                        updateViewModel: (NSApp.delegate as? AppDelegate)?.updateViewModel) { action in
                        self.delegate?.performAction(action, on: surfaceView)
                    }
                }

                // Show update information above all else.
                if viewModel.updateOverlayIsVisible {
                    UpdateOverlay()
                }
            }
            .frame(maxWidth: .greatestFiniteMagnitude, maxHeight: .greatestFiniteMagnitude)
        }
    }
}

/// Isolated view for tab bar + quick launch, observing only ProjectTabState
/// to avoid re-rendering the entire TerminalView on tab changes.
private struct ProjectTabBarSection: View {
    @ObservedObject var tabState: ProjectTabState
    @ObservedObject var sidebarState: ProjectSidebarState
    let ghosttyConfig: Ghostty.Config

    var body: some View {
        VStack(spacing: 0) {
            ProjectTabBar(
                tabs: tabState.tabs,
                selectedIndex: tabState.selectedTabIndex,
                projectStatus: sidebarState.claudeStatus(for: sidebarState.activeProjectPath, in: NSApp.keyWindow),
                backgroundColor: ghosttyConfig.backgroundColor,
                backgroundOpacity: ghosttyConfig.backgroundOpacity,
                onSelect: { window in
                    window.makeKeyAndOrderFront(nil)
                    tabState.refresh(for: sidebarState.activeProjectPath, in: NSApp.keyWindow)
                    if let controller = window.windowController as? TerminalController {
                        sidebarState.dismissClaudeStatus(for: controller.ghosttyTabId)
                    }
                },
                onClose: { window in
                    window.close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        tabState.refresh(for: sidebarState.activeProjectPath, in: NSApp.keyWindow)
                    }
                },
                onNewTab: {
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.newTab(nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            tabState.refresh(for: sidebarState.activeProjectPath, in: NSApp.keyWindow)
                        }
                    }
                }
            )
            QuickLaunchBar(
                activeProjectPath: sidebarState.activeProjectPath,
                backgroundColor: ghosttyConfig.backgroundColor,
                backgroundOpacity: ghosttyConfig.backgroundOpacity
            )
            Divider()
        }
    }
}

/// A draggable handle between the sidebar and terminal content.
private struct SidebarResizeHandle: View {
    @ObservedObject var sidebarState: ProjectSidebarState
    @State private var isDragging = false
    @State private var startWidth: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor))
            .frame(width: isDragging ? 3 : 1)
            .contentShape(Rectangle().inset(by: -3))
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            startWidth = sidebarState.width
                        }
                        sidebarState.setWidthWithoutPersist(startWidth + value.translation.width)
                    }
                    .onEnded { _ in
                        isDragging = false
                        sidebarState.persistSidebarSettings()
                    }
            )
    }
}

private struct UpdateOverlay: View {
    var body: some View {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            VStack {
                Spacer()

                HStack {
                    Spacer()
                    UpdatePill(model: appDelegate.updateViewModel)
                        .padding(.bottom, 9)
                        .padding(.trailing, 9)
                }
            }
        }
    }
}

struct DebugBuildWarningView: View {
    @State private var isPopover = false

    var body: some View {
        HStack {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)

            Text("You're running a debug build of Ghostty! Performance will be degraded.")
                .padding(.all, 8)
                .popover(isPresented: $isPopover, arrowEdge: .bottom) {
                    Text("""
                    Debug builds of Ghostty are very slow and you may experience
                    performance problems. Debug builds are only recommended during
                    development.
                    """)
                    .padding(.all)
                }

            Spacer()
        }
        .background(Color(.windowBackgroundColor))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Debug build warning")
        .accessibilityValue("Debug builds of Ghostty are very slow and you may experience performance problems. Debug builds are only recommended during development.")
        .accessibilityAddTraits(.isStaticText)
        .onTapGesture {
            isPopover = true
        }
    }
}
