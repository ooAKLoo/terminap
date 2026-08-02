import AppKit
import TermiNapCore
import SwiftUI

@MainActor
final class PanelFrameMorphAnimator {
    private weak var panel: NSPanel?
    private var targetHeight: CGFloat = 0
    private var resizeAnchor: PanelResizeAnchor = .topEdge
    private var velocity: CGFloat = 0
    private var timer: Timer?
    private var lastTimestamp: TimeInterval = 0
    private var completion: (() -> Void)?

    private let stiffness: CGFloat = 260
    private let damping: CGFloat = 34

    func animate(
        panel: NSPanel,
        to targetFrame: CGRect,
        keeping resizeAnchor: PanelResizeAnchor,
        completion: @escaping () -> Void
    ) {
        self.panel = panel
        targetHeight = targetFrame.height
        self.resizeAnchor = resizeAnchor
        self.completion = completion
        align(panel, with: targetFrame, keeping: resizeAnchor)

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            stop()
            return
        }

        guard timer == nil else {
            return
        }

        velocity = 0
        lastTimestamp = ProcessInfo.processInfo.systemUptime
        let timer = Timer(
            timeInterval: 1 / 120,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func updateResizeAnchor(_ resizeAnchor: PanelResizeAnchor) {
        self.resizeAnchor = resizeAnchor
    }

    private func tick() {
        guard let panel else {
            timer?.invalidate()
            timer = nil
            return
        }

        let timestamp = ProcessInfo.processInfo.systemUptime
        let delta = min(
            max(timestamp - lastTimestamp, 1 / 240),
            1 / 10
        )
        lastTimestamp = timestamp
        let dt = CGFloat(delta)
        let frame = panel.frame

        let nextHeight = integrateSpring(
            current: frame.height,
            target: targetHeight,
            velocity: &velocity,
            delta: dt
        )

        let nextFrame = PanelPlacement.resizedFrame(
            frame,
            targetHeight: max(nextHeight, 1),
            keeping: resizeAnchor
        )
        panel.setFrame(nextFrame, display: true)
        updateContentMask(panel, height: nextFrame.height)

        if abs(nextFrame.height - targetHeight) < 0.5,
           abs(velocity) < 4
        {
            stop()
        }
    }

    private func integrateSpring(
        current: CGFloat,
        target: CGFloat,
        velocity: inout CGFloat,
        delta: CGFloat
    ) -> CGFloat {
        var value = current
        var remaining = delta
        while remaining > 0 {
            let step = min(remaining, 1 / 240)
            let displacement = value - target
            let acceleration =
                (-stiffness * displacement) - (damping * velocity)
            velocity += acceleration * step
            value += velocity * step
            remaining -= step
        }
        return value
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        velocity = 0
        if let panel {
            let finalFrame = PanelPlacement.resizedFrame(
                panel.frame,
                targetHeight: targetHeight,
                keeping: resizeAnchor
            )
            panel.setFrame(finalFrame, display: true)
            updateContentMask(panel, height: targetHeight)
        }
        let completion = self.completion
        self.completion = nil
        completion?()
    }

    private func align(
        _ panel: NSPanel,
        with targetFrame: CGRect,
        keeping anchor: PanelResizeAnchor
    ) {
        let currentFrame = panel.frame
        let originY: CGFloat
        switch anchor {
        case .topEdge:
            originY = targetFrame.maxY - currentFrame.height
        case .bottomEdge:
            originY = targetFrame.minY
        }
        let alignedFrame = CGRect(
            x: targetFrame.minX,
            y: originY,
            width: targetFrame.width,
            height: currentFrame.height
        )
        panel.setFrame(alignedFrame, display: true)
    }

    private func updateContentMask(_ panel: NSPanel, height: CGFloat) {
        let range =
            BatteryView.dashboardExpandedHeight
            - BatteryView.collapsedHeight
        let progress = min(
            max(
                (height - BatteryView.collapsedHeight) / max(range, 1),
                0
            ),
            1
        )
        let cornerRadius = 30 - (6 * progress)
        panel.contentView?.layer?.cornerRadius = cornerRadius
        panel.contentView?.needsDisplay = true
    }

    deinit {
        timer?.invalidate()
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class HoverHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChange: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?
    private var pointerIsInside = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [
                .mouseEnteredAndExited,
                .activeAlways,
                .enabledDuringMouseDrag,
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
        synchronizePointerLocation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.synchronizePointerLocation()
        }
    }

    override func layout() {
        super.layout()
        synchronizePointerLocation()
    }

    override func mouseEntered(with event: NSEvent) {
        setPointerInside(true)
    }

    override func mouseExited(with event: NSEvent) {
        setPointerInside(false)
    }

    private func synchronizePointerLocation() {
        guard let window, window.isVisible else {
            setPointerInside(false)
            return
        }
        let locationInWindow = window.convertPoint(
            fromScreen: NSEvent.mouseLocation
        )
        let location = convert(
            locationInWindow,
            from: nil
        )
        setPointerInside(bounds.contains(location))
    }

    private func setPointerInside(_ isInside: Bool) {
        guard pointerIsInside != isInside else {
            return
        }
        pointerIsInside = isInside
        onHoverChange?(isInside)
    }
}

private struct RememberedPanelPlacement {
    let displayIdentifier: String
    let relativePosition: PanelRelativePosition
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let panelMargin: CGFloat = 32
    private var panel: FloatingPanel?
    private var statusItem: NSStatusItem?
    private var model: AppModel?
    private var panelPresentation: PanelPresentationState?
    private let panelMorphAnimator = PanelFrameMorphAnimator()
    private var screenChangeObserver: NSObjectProtocol?
    private var resizeAnchor: PanelResizeAnchor = .topEdge
    private var rememberedPanelPlacement: RememberedPanelPlacement?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let model = AppModel()
        self.model = model
        installHooksIfNeeded(model: model)
        createPanel(model: model)
        createStatusItem()
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.keepPanelOnScreen()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
    }

    private func installHooksIfNeeded(model: AppModel) {
        if ProcessInfo.processInfo.environment["TERMINAP_SKIP_HOOK_INSTALL"] == "1" {
            model.setHookInstalled(false)
            return
        }

        guard let executablePath = Bundle.main.executablePath else {
            model.setHookInstalled(false)
            return
        }

        let codexDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        do {
            _ = try HookInstaller.install(
                executablePath: executablePath,
                codexDirectory: codexDirectory
            )
            model.hookInstallationDidFinish(executablePath: executablePath)
        } catch {
            model.hookInstallationDidFail(error)
        }
    }

    private func createPanel(model: AppModel) {
        let presentation = PanelPresentationState()
        panelPresentation = presentation
        let panel = FloatingPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: BatteryView.panelWidth,
                height: BatteryView.collapsedHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isRestorable = false
        let hostingView = HoverHostingView(
            rootView: BatteryView(
                model: model,
                presentation: presentation,
                onPreferredHeightChange: { [weak self] height in
                    self?.resizePanel(to: height)
                },
                onDragEnded: { [weak self] in
                    self?.rememberCurrentPanelPlacement()
                }
            )
        )
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layerContentsRedrawPolicy = .duringViewResize
        hostingView.layer?.cornerRadius = 30
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        hostingView.onHoverChange = { [weak presentation] isInside in
            presentation?.setPointerInside(isInside)
        }
        panel.contentView = hostingView
        panel.contentView?.layoutSubtreeIfNeeded()
        placePanelAtTopTrailing(panel)
        panel.orderFrontRegardless()
        self.panel = panel

        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel else {
                return
            }
            panel.contentView?.layoutSubtreeIfNeeded()
            self.placePanelAtTopTrailing(panel)
        }
    }

    private func resizePanel(to height: CGFloat) {
        guard let panel, abs(panel.frame.height - height) > 0.5 else {
            return
        }

        let screen =
            screenContainingPanel(panel)
            ?? screenContainingMouse()
            ?? NSScreen.main
            ?? NSScreen.screens.first

        if let screen {
            if height > panel.frame.height {
                resizeAnchor = PanelPlacement.preferredResizeAnchor(
                    for: panel.frame,
                    targetHeight: height,
                    visibleFrame: screen.visibleFrame,
                    margin: panelMargin
                )
            }
        }
        panelPresentation?.setResizeAnchor(resizeAnchor)

        var targetFrame = PanelPlacement.resizedFrame(
            panel.frame,
            targetHeight: height,
            keeping: resizeAnchor
        )

        if let screen {
            targetFrame.origin = PanelPlacement.clampedOrigin(
                targetFrame.origin,
                panelSize: targetFrame.size,
                visibleFrame: screen.visibleFrame,
                margin: panelMargin
            )
        }

        panelMorphAnimator.animate(
            panel: panel,
            to: targetFrame,
            keeping: resizeAnchor
        ) { [weak self] in
            self?.panelPresentation?.panelAnimationDidComplete()
        }
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "battery.100percent",
            accessibilityDescription: "TermiNap"
        )
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        statusItem = item
    }

    @objc private func togglePanel() {
        guard let panel else {
            return
        }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            placePanelAtTopTrailing(panel)
            panel.orderFrontRegardless()
            panel.makeKey()
        }
    }

    private func placePanelAtTopTrailing(_ panel: NSPanel) {
        guard let screen = screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first else {
            panel.center()
            return
        }
        let origin = PanelPlacement.topTrailingOrigin(
            panelSize: panel.frame.size,
            visibleFrame: screen.visibleFrame,
            margin: panelMargin
        )
        panel.setFrameOrigin(origin)
        rememberPanelPlacement(panel, on: screen)
    }

    private func keepPanelOnScreen() {
        guard let panel else {
            return
        }

        if let rememberedPanelPlacement,
           let rememberedScreen = NSScreen.screens.first(where: {
               displayIdentifier(for: $0)
                   == rememberedPanelPlacement.displayIdentifier
           })
        {
            restorePanel(
                panel,
                to: rememberedPanelPlacement,
                on: rememberedScreen
            )
            return
        }

        let screen =
            screenContainingPanel(panel)
            ?? screenContainingMouse()
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            return
        }
        let origin = PanelPlacement.clampedOrigin(
            panel.frame.origin,
            panelSize: panel.frame.size,
            visibleFrame: screen.visibleFrame,
            margin: panelMargin
        )
        panel.setFrameOrigin(origin)
    }

    private func rememberCurrentPanelPlacement() {
        guard
            let panel,
            let screen =
                screenContainingPanel(panel)
                ?? screenContainingMouse()
                ?? NSScreen.main
                ?? NSScreen.screens.first
        else {
            return
        }
        rememberPanelPlacement(panel, on: screen)
    }

    private func rememberPanelPlacement(
        _ panel: NSPanel,
        on screen: NSScreen
    ) {
        let collapsedFrame = PanelPlacement.resizedFrame(
            panel.frame,
            targetHeight: BatteryView.collapsedHeight,
            keeping: resizeAnchor
        )
        let relativePosition = PanelPlacement.relativePosition(
            for: collapsedFrame.origin,
            panelSize: collapsedFrame.size,
            visibleFrame: screen.visibleFrame,
            margin: panelMargin
        )
        rememberedPanelPlacement = RememberedPanelPlacement(
            displayIdentifier: displayIdentifier(for: screen),
            relativePosition: relativePosition
        )
    }

    private func restorePanel(
        _ panel: NSPanel,
        to placement: RememberedPanelPlacement,
        on screen: NSScreen
    ) {
        let collapsedSize = CGSize(
            width: panel.frame.width,
            height: BatteryView.collapsedHeight
        )
        let collapsedOrigin = PanelPlacement.origin(
            for: placement.relativePosition,
            panelSize: collapsedSize,
            visibleFrame: screen.visibleFrame,
            margin: panelMargin
        )
        let collapsedFrame = CGRect(
            origin: collapsedOrigin,
            size: collapsedSize
        )

        let expandedHeight =
            model?.shouldShowHookSetup == true
            ? BatteryView.setupExpandedHeight
            : BatteryView.dashboardExpandedHeight
        resizeAnchor = PanelPlacement.preferredResizeAnchor(
            for: collapsedFrame,
            targetHeight: expandedHeight,
            visibleFrame: screen.visibleFrame,
            margin: panelMargin
        )
        panelPresentation?.setResizeAnchor(resizeAnchor)
        panelMorphAnimator.updateResizeAnchor(resizeAnchor)

        var restoredFrame = PanelPlacement.resizedFrame(
            collapsedFrame,
            targetHeight: panel.frame.height,
            keeping: resizeAnchor
        )
        restoredFrame.origin = PanelPlacement.clampedOrigin(
            restoredFrame.origin,
            panelSize: restoredFrame.size,
            visibleFrame: screen.visibleFrame,
            margin: panelMargin
        )
        panel.setFrame(restoredFrame, display: true)
    }

    private func screenContainingPanel(_ panel: NSWindow) -> NSScreen? {
        let panelCenter = NSPoint(
            x: panel.frame.midX,
            y: panel.frame.midY
        )
        return NSScreen.screens.first {
            NSMouseInRect(panelCenter, $0.frame, false)
        }
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        }
    }

    private func displayIdentifier(for screen: NSScreen) -> String {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard
            let screenNumber =
                screen.deviceDescription[screenNumberKey] as? NSNumber
        else {
            return screen.localizedName
        }

        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        guard
            let uuid =
                CGDisplayCreateUUIDFromDisplayID(displayID)?
                    .takeRetainedValue()
        else {
            return "display-\(displayID)"
        }
        guard let uuidString = CFUUIDCreateString(nil, uuid) else {
            return "display-\(displayID)"
        }
        return uuidString as String
    }
}
