import AppKit
import QuartzCore
import SwiftUI

/// Fully clear panel — no titlebar material, no opaque backing.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
    }
}

/// Transparent container that never paints a rectangular fill behind the island.
private final class ClearContainerView: NSView {
    override var isOpaque: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = CGColor.clear
        layer?.isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        layer?.backgroundColor = CGColor.clear
        layer?.isOpaque = false
    }

    override func draw(_ dirtyRect: NSRect) {
        // Intentionally empty — do not call super (avoids default gray fill).
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Still allow subviews to receive clicks.
        super.hitTest(point)
    }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        clearChrome()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        clearChrome()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        clearChrome()
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.hasShadow = false
    }

    override func layout() {
        super.layout()
        clearChrome()
    }

    override func draw(_ dirtyRect: NSRect) {
        // Skip default hosting fill; SwiftUI content still renders via its own path.
        // Calling through to SwiftUI rendering:
        super.draw(dirtyRect)
        layer?.backgroundColor = CGColor.clear
    }

    private func clearChrome() {
        wantsLayer = true
        layer?.backgroundColor = CGColor.clear
        layer?.isOpaque = false
        layer?.masksToBounds = false
        layer?.cornerRadius = 0
        layer?.borderWidth = 0
        layer?.shadowOpacity = 0
    }
}

/// Top-anchored spring morph so the island never “lifts off” the notch.
@MainActor
final class IslandPanelController: NSObject {
    private let store: IslandStore
    private var panel: IslandPanel?
    private var containerView: ClearContainerView?
    private var hostingView: FirstMouseHostingView<IslandRootView>?
    private var clickOutsideMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var sizeTimer: Timer?
    private var currentSize: CGSize = CGSize(width: 172, height: 36)

    private var animStartSize: CGSize = .zero
    private var animTargetSize: CGSize = .zero
    private var animStartTime: CFTimeInterval = 0
    private var animResponse: CGFloat = IslandMotion.expandResponse
    private var animDamping: CGFloat = IslandMotion.expandDamping
    private var isMorphing = false

    init(store: IslandStore) {
        self.store = store
        super.init()
    }

    func show() {
        guard panel == nil else {
            applyFrame(for: currentSize, animated: false)
            return
        }

        let root = IslandRootView(store: store)
        let hosting = FirstMouseHostingView(rootView: root)
        hostingView = hosting

        let container = ClearContainerView(frame: NSRect(origin: .zero, size: currentSize))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        containerView = container

        let panel = IslandPanel(
            contentRect: NSRect(origin: .zero, size: currentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        panel.contentView = container
        panel.acceptsMouseMovedEvents = true
        self.panel = panel

        sizeTimer?.invalidate()
        sizeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncSizeFromStore()
                self?.tickMorph()
            }
        }
        if let sizeTimer { RunLoop.main.add(sizeTimer, forMode: .common) }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.applyFrame(for: self.currentSize, animated: false)
            }
        }

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in self?.handleOutsideClick(event) }
        }

        applyFrame(for: currentSize, animated: false)
        panel.orderFrontRegardless()
    }

    func syncSizeFromStore() {
        let target = targetSizeFromStore()
        guard target != animTargetSize || (!isMorphing && target != currentSize) else { return }
        morph(to: target)
    }

    private func targetSizeFromStore() -> CGSize {
        let compact = CGSize(width: 172, height: 36)
        let topPad = NotchGeometry.expandedContentTopPadding()
        let expanded: CGSize = {
            switch store.displayedModule {
            case .cursor:
                let base: CGFloat = store.usage == nil ? 176 : 288
                return CGSize(width: 380, height: base + topPad - 12)
            case .spotify:
                // Extra height for comfortable control padding at the bottom.
                let base: CGFloat = store.spotifyError == nil ? 196 : 224
                return CGSize(width: 340, height: base + topPad - 12)
            case .screenshot:
                let extra: CGFloat = store.needsAccessibilityHint ? 28 : 0
                let base = ScreenshotClipboardLayout.expandedBaseHeight + extra
                return CGSize(
                    width: ScreenshotClipboardLayout.expandedWidth(itemCount: store.screenshots.count),
                    height: base + topPad - 12
                )
            }
        }()
        return store.presentation == .expanded ? expanded : compact
    }

    private func morph(to target: CGSize) {
        // Retarget from the live size if a morph is already in flight.
        animStartSize = currentSize
        animTargetSize = target
        animStartTime = CACurrentMediaTime()

        let deltaH = target.height - currentSize.height
        if deltaH > 40 {
            animResponse = IslandMotion.expandResponse
            animDamping = IslandMotion.expandDamping
        } else if deltaH < -40 {
            animResponse = IslandMotion.collapseResponse
            animDamping = IslandMotion.collapseDamping
        } else {
            animResponse = IslandMotion.moduleResponse
            animDamping = IslandMotion.moduleDamping
        }

        isMorphing = true
    }

    private func tickMorph() {
        guard isMorphing else { return }
        let t = CACurrentMediaTime() - animStartTime
        let response = animResponse
        let damping = animDamping

        let progress = springProgress(time: t, response: response, damping: damping)
        let width = lerp(animStartSize.width, animTargetSize.width, progress)
        let height = lerp(animStartSize.height, animTargetSize.height, progress)
        let size = CGSize(width: width, height: height)
        currentSize = size
        applyFrame(for: size, animated: false)

        if t > response * 2.8 || abs(progress - 1) < 0.0015 {
            currentSize = animTargetSize
            applyFrame(for: animTargetSize, animated: false)
            isMorphing = false
        }
    }

    private func springProgress(time: CGFloat, response: CGFloat, damping: CGFloat) -> CGFloat {
        let omega = (2 * CGFloat.pi) / max(response, 0.05)
        let zeta = damping
        let t = time

        let value: CGFloat
        if zeta < 1 {
            let omegaD = omega * sqrt(1 - zeta * zeta)
            value = 1 - exp(-zeta * omega * t) * (cos(omegaD * t) + (zeta * omega / omegaD) * sin(omegaD * t))
        } else {
            value = 1 - exp(-omega * t) * (1 + omega * t)
        }
        return min(max(value, 0), 1.08)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    private func applyFrame(for size: CGSize, animated: Bool) {
        guard let panel else { return }
        guard let screen = NotchGeometry.builtInNotchedScreen ?? NSScreen.main else { return }
        let frame = NotchGeometry.islandFrame(
            for: screen,
            size: size,
            expanded: store.presentation == .expanded
        )
        panel.setFrame(frame, display: true)
        containerView?.frame = NSRect(origin: .zero, size: size)
        hostingView?.frame = NSRect(origin: .zero, size: size)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.orderFrontRegardless()
    }

    private func handleOutsideClick(_ event: NSEvent) {
        guard store.presentation == .expanded, let panel else { return }

        if let clicked = event.window, clicked.title.localizedCaseInsensitiveContains("sign in") {
            return
        }

        let locationInPanel = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let insidePanel = panel.contentView?.bounds.contains(locationInPanel) ?? false
        if !insidePanel {
            store.collapse()
        }
    }

    deinit {
        if let clickOutsideMonitor {
            NSEvent.removeMonitor(clickOutsideMonitor)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }
}
