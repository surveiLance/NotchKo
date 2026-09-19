import AppKit
import SwiftUI
import Combine
import Quartz

/// Borderless, transparent, non-activating panel that sits over the notch.
///
/// The panel is resized to exactly the notch when collapsed and to the
/// expanded size when open, so the transparent parts never swallow clicks
/// meant for the menu bar underneath.
@MainActor
final class NotchPanel: NSPanel {
    let state: NotchState
    /// Which display this panel belongs to. Looked up fresh on every relayout
    /// rather than holding an NSScreen, which goes stale after mode changes.
    let displayID: CGDirectDisplayID
    private var geometry: NotchGeometry

    /// Current NSScreen for this display (falls back to the main screen if it vanished).
    var currentScreen: NSScreen {
        NSScreen.screen(for: displayID) ?? NSScreen.main ?? NSScreen.screens[0]
    }
    private var cancellables = Set<AnyCancellable>()
    private var shrinkWork: DispatchWorkItem?
    private var wingWidth: CGFloat = 0
    private var noticeWing: CGFloat = 0
    private var expandedNow = false

    /// While collapsed, only the pill (top-centre of the window) is hoverable.
    /// NSHostingView is flipped (y grows downward), so "top" is y = 0.
    private var hoverRegion: NSRect? {
        guard !expandedNow, let view = contentView else { return nil }
        let size = collapsedPanelSize
        let b = view.bounds
        let y = view.isFlipped ? 0 : b.height - size.height
        return NSRect(x: (b.width - size.width) / 2, y: y, width: size.width, height: size.height)
    }
    private var noticeHeight: CGFloat = 0
    /// Key status is opt-in so ordinary clicks never steal focus from the app you're in.
    private var allowsKey = false
    private var previewURLs: [URL] = []

    init(state: NotchState, screen: NSScreen) {
        self.state = state
        self.displayID = screen.displayID
        self.geometry = NotchGeometry.detect(for: screen)
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        // Above the menu bar *and* the system volume/brightness HUD, which
        // otherwise lands on top of the notch and steals the hover. Kept below
        // the screen-saver tier: windows up there stop receiving drag-and-drop.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let root = NotchView(state: state, notchSize: geometry.notchSize)
        let host = HoverHostingView(rootView: root)
        host.sizingOptions = [] // we own the window frame; don't auto-fit to content
        host.onHover = { [weak state] hovering in state?.setHovering(hovering) }
        host.hoverRect = { [weak self] in self?.hoverRegion }
        host.airDropFrame = { [weak state] in state?.airDropFrame }
        host.onDragTargeted = { [weak state] zone in
            state?.setDragTargeted(zone.map { $0 == .airDrop ? .airDrop : .shelf })
        }
        host.onDropFiles = { [weak state] urls, zone in
            guard let state else { return }
            state.didDrop()
            switch zone {
            case .airDrop: ShelfStore.airDrop(urls)
            case .shelf:   state.shelf.add(urls)
            }
        }
        contentView = host

        // Grow the window *before* the open animation and shrink it *after*
        // the close animation, so content is never clipped mid-spring.
        state.$isExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                guard let self else { return }
                self.expandedNow = expanded
                self.resize(expanded: expanded)
                // Narrow (or widen) the hover region immediately, before the
                // window itself catches up.
                DispatchQueue.main.async { (self.contentView as? HoverHostingView<NotchView>)?.refreshHoverRegion() }
            }
            .store(in: &cancellables)

        // Wings appear/disappear with playback; resize the collapsed window to fit.
        // (@Published fires on willSet, so use the incoming value, not state.wingWidth.)
        // Growing: resize the window first so the spring has room. Shrinking
        // (pause, timer done): let the pill glide back in, then shrink.
        state.$wingWidth
            .removeDuplicates()
            .sink { [weak self] wing in
                guard let self else { return }
                let shrinking = wing < self.wingWidth
                self.wingWidth = wing
                if !self.state.isExpanded { self.resize(expanded: false, animatedDelay: shrinking) }
            }
            .store(in: &cancellables)

        state.previewHandler = { [weak self] urls in self?.preview(urls) }

        // Become key only while a text field asks for it.
        state.$keyboardWanted
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] wanted in
                guard let self else { return }
                self.allowsKey = wanted
                if wanted { self.makeKey() } else if self.isKeyWindow { self.resignKey() }
            }
            .store(in: &cancellables)

        // Clicking elsewhere ends editing.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: self, queue: .main
        ) { [weak state] _ in
            MainActor.assumeIsolated { state?.keyboardWanted = false }
        }

        // Teleprompter toggles between the two expanded sizes.
        state.$isPrompting
            .removeDuplicates()
            .sink { [weak self] prompting in
                guard let self else { return }
                // Grow immediately; shrink after the strip has animated away.
                DispatchQueue.main.asyncAfter(deadline: .now() + (prompting ? 0 : 0.4)) {
                    guard self.state.isExpanded else { return }
                    self.setFrame(self.geometry.frame(for: self.state.expandedSize), display: true)
                }
            }
            .store(in: &cancellables)

        // Notice pill: grow the window at once, shrink after the glide back.
        state.$notice
            .map { ($0?.wing ?? 0, $0?.height ?? 0) }
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] wing, height in
                guard let self else { return }
                self.noticeWing = wing
                self.noticeHeight = height
                self.resize(expanded: false, animatedDelay: wing == 0)
            }
            .store(in: &cancellables)
    }

    func show() {
        relayout()
        orderFrontRegardless()
    }

    /// Called on Space changes: some transitions drop windows out of the
    /// all-spaces set or reorder them; putting it back is cheap.
    func reassert() {
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        if !isVisible { orderFrontRegardless() }
        orderFrontRegardless()
    }

    func relayout() {
        geometry = NotchGeometry.detect(for: currentScreen)
        resize(expanded: state.isExpanded, animatedDelay: false)
        if let host = contentView as? HoverHostingView<NotchView> {
            host.rootView = NotchView(state: state, notchSize: geometry.notchSize)
        }
    }

    private func resize(expanded: Bool, animatedDelay: Bool = true) {
        shrinkWork?.cancel()
        let collapsed = collapsedPanelSize
        let target = expanded ? state.expandedSize : collapsed
        let apply = { [weak self] in
            guard let self else { return }
            self.setFrame(self.geometry.frame(for: target), display: true)
        }
        if expanded || !animatedDelay {
            // Our sinks fire from @Published's willSet; a synchronous setFrame
            // here would make SwiftUI render *before* the new value lands and
            // then skip the real update. One hop later is still before the
            // next frame, so the window is grown in time for the animation.
            DispatchQueue.main.async { apply() }
        } else {
            // Wait for the collapse spring to settle before shrinking the window.
            let work = DispatchWorkItem(block: apply)
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    /// Collapsed panel is exactly the notch. On notchless screens we still
    /// show a small black pill so there's something to hover.
    /// Collapsed window = notch + wings + an invisible margin so a drag or
    /// hover that lands just beside the notch is still caught.
    private var collapsedPanelSize: CGSize {
        let wing = max(noticeWing, wingWidth)
        return CGSize(width: geometry.notchSize.width + 2 * (wing + Motion.catchMargin),
                      height: max(geometry.notchSize.height, noticeHeight))
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    // MARK: - Quick Look

    /// QLPreviewPanel looks for its controller on the key window's responder
    /// chain, so we briefly become key, then hand control back when it closes.
    private func preview(_ urls: [URL]) {
        guard !urls.isEmpty, let ql = QLPreviewPanel.shared() else { return }
        previewURLs = urls
        allowsKey = true
        makeKey()
        NSApp.activate(ignoringOtherApps: true)
        ql.makeKeyAndOrderFront(nil)
        ql.reloadData()
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: ql, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.allowsKey = self.state.keyboardWanted
                self.state.collapseNow()
            }
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}

extension NotchPanel: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURLs[index] as NSURL
    }
}
