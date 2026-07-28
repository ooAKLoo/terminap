import AppKit
import TermiNapCore
import SwiftUI

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let panelMargin: CGFloat = 32
    private var panel: FloatingPanel?
    private var statusItem: NSStatusItem?
    private var model: AppModel?
    private var screenChangeObserver: NSObjectProtocol?

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
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 390),
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
        panel.contentViewController = NSHostingController(
            rootView: BatteryView(model: model)
        )
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
    }

    private func keepPanelOnScreen() {
        guard let panel else {
            return
        }
        let panelCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let screen = NSScreen.screens.first(where: {
            NSMouseInRect(panelCenter, $0.frame, false)
        }) ?? screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
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

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        }
    }
}
