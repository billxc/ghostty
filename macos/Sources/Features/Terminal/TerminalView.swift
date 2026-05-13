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

    // Tracks which window is currently key. Used to skip sidebar/tab bar
    // SwiftUI work in non-visible tabs (each tab = one NSWindow = one
    // SwiftUI tree, so without gating, status pushes hit N copies).
    @ObservedObject private var keyWindowTracker = KeyWindowTracker.shared
    @State private var ownWindowID: ObjectIdentifier?

    /// True when this view's hosting window is the system's key window.
    /// While false, sidebar/tab bar are replaced with cheap placeholders —
    /// the window is invisible (not the selected tab) so nothing is shown
    /// anyway, and we save a per-store-publish body evaluation.
    private var isKeyWindow: Bool {
        guard let ownWindowID else { return true } // mount until we learn our window
        return keyWindowTracker.keyWindowID == ownWindowID
    }

    /// The most recently focused surface, equal to `focusedSurface` when it is non-nil.
    @State private var lastFocusedSurface: Weak<Ghostty.SurfaceView>?

    /// Last tab id we asked to dismiss status for. focusedSurface flips on
    /// every split / palette focus change; without this dedup, every flip
    /// dispatches to ClaudeStatusServer.queue (and possibly publishes) for
    /// the same tab — wasted on every keystroke that moves focus.
    @State private var lastDismissedTabId: String?

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
                        if sidebarState.isVisible && isKeyWindow {
                            SidebarHost(
                                sidebarState: sidebarState,
                                backgroundColor: ghostty.config.backgroundColor,
                                backgroundOpacity: ghostty.config.backgroundOpacity,
                                onOpenProject: { project in
                                    sidebarState.switchToProject(project, in: NSApp.keyWindow)
                                    ProjectTabState.shared.refresh(
                                        for: sidebarState.activeProjectPath, in: NSApp.keyWindow)
                                }
                            )
                        }

                        VStack(spacing: 0) {
                            // Custom tab bar and quick launch — isolated in own view.
                            // Only mount in the key window: tab bars in background
                            // tabs are invisible anyway, and observing the stores
                            // costs a body re-eval per status push × N tabs.
                            if isKeyWindow {
                                ProjectTabBarSection(
                                    tabState: tabState,
                                    sidebarState: sidebarState,
                                    ghosttyConfig: ghostty.config
                                )
                            }

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
                                    // Note: tab-switch sites already call refresh.
                                    // focusedSurface flips on every key/split focus
                                    // change too — running refresh here was an
                                    // O(N_windows) walk per keystroke for nothing.
                                    // Dismiss status for the focused tab — but only
                                    // if the tab actually changed (split focus moves
                                    // within the same tab fire here too).
                                    if let controller = NSApp.keyWindow?.windowController as? TerminalController {
                                        let tabId = controller.ghosttyTabId
                                        if tabId != lastDismissedTabId {
                                            lastDismissedTabId = tabId
                                            sidebarState.dismissClaudeStatus(for: tabId)
                                        }
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
                .background(WindowAccessor { window in
                    if let window {
                        let id = ObjectIdentifier(window)
                        if ownWindowID != id { ownWindowID = id }
                        // First-time mount: if we ARE the key window, push our id
                        // into the tracker (windowDidBecomeKey may have fired
                        // before our SwiftUI tree existed).
                        if window.isKeyWindow {
                            KeyWindowTracker.shared.update(window)
                        }
                    }
                })

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

/// Bridges SwiftUI to AppKit so a SwiftUI view can learn its hosting
/// NSWindow. Used by TerminalView to decide whether it's the visible
/// (key) tab and skip work otherwise.
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { onResolve(v.window) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}

/// Wraps the sidebar + resize handle. Owns the in-flight drag width as
/// local @State so the sidebar's frame can update at 60fps without
/// republishing ProjectSidebarState.width on every pixel of drag.
private struct SidebarHost: View {
    @ObservedObject var sidebarState: ProjectSidebarState
    let backgroundColor: Color
    let backgroundOpacity: Double
    let onOpenProject: (ProjectConfig) -> Void

    @State private var liveWidth: CGFloat?

    var body: some View {
        HStack(spacing: 0) {
            ProjectSidebarView(
                state: sidebarState,
                backgroundColor: backgroundColor,
                backgroundOpacity: backgroundOpacity,
                onOpenProject: onOpenProject
            )
            .frame(width: liveWidth ?? sidebarState.width)

            SidebarResizeHandle(sidebarState: sidebarState, liveWidth: $liveWidth)
        }
    }
}

/// Isolated view for tab bar + quick launch, observing only ProjectTabState
/// and ClaudeStatusStore to avoid re-rendering on sidebar width drags or
/// git status polling ticks.
private struct ProjectTabBarSection: View {
    @ObservedObject var tabState: ProjectTabState
    @ObservedObject var sidebarState: ProjectSidebarState
    @ObservedObject private var claudeStore = ClaudeStatusStore.shared
    let ghosttyConfig: Ghostty.Config

    var body: some View {
        VStack(spacing: 0) {
            ProjectTabBar(
                tabs: tabState.tabs,
                selectedIndex: tabState.selectedTabIndex,
                tabStatuses: claudeStore.tabStatuses,
                backgroundColor: ghosttyConfig.backgroundColor,
                backgroundOpacity: ghosttyConfig.backgroundOpacity,
                layout: sidebarState.layout,
                onSelect: { window in
                    window.makeKeyAndOrderFront(nil)
                    // Use the clicked window directly; NSApp.keyWindow is still
                    // the OLD window at this point (makeKeyAndOrderFront is async).
                    tabState.refresh(for: sidebarState.activeProjectPath, in: window)
                    if let controller = window.windowController as? TerminalController {
                        sidebarState.dismissClaudeStatus(for: controller.ghosttyTabId)
                    }
                },
                onClose: { window in
                    let tabGroup = window.tabGroup
                    window.close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        tabState.refresh(
                            for: sidebarState.activeProjectPath,
                            in: tabGroup?.selectedWindow ?? NSApp.keyWindow)
                    }
                },
                onNewTab: {
                    // The static TerminalController.newTab now refreshes
                    // ProjectTabState itself, so we no longer need a manual
                    // asyncAfter refresh here.
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.newTab(nil)
                    }
                }
            )
            QuickLaunchBar(
                activeProject: sidebarState.projects.first(where: { $0.path == sidebarState.activeProjectPath }),
                onProjectChanged: { updated in
                    sidebarState.updateProject(updated)
                },
                backgroundColor: ghosttyConfig.backgroundColor,
                backgroundOpacity: ghosttyConfig.backgroundOpacity,
                layout: sidebarState.layout
            )
            Divider()
        }
    }
}

/// A draggable handle between the sidebar and terminal content.
/// Drag updates a caller-provided live width binding (local @State),
/// then commits to ProjectSidebarState exactly once on drag end.
private struct SidebarResizeHandle: View {
    @ObservedObject var sidebarState: ProjectSidebarState
    @Binding var liveWidth: CGFloat?
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
                        let proposed = startWidth + value.translation.width
                        liveWidth = max(sidebarState.layout.minWidth,
                                        min(sidebarState.layout.maxWidth, proposed))
                    }
                    .onEnded { _ in
                        isDragging = false
                        if let final = liveWidth {
                            sidebarState.updateWidth(final)
                        }
                        liveWidth = nil
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
