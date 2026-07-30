import AppKit
import TermiNapCore
import SwiftUI

@MainActor
func renderPreview(
    to outputURL: URL,
    activeCount: Int,
    enabled: Bool,
    expanded: Bool = true,
    resizeAnchor: PanelResizeAnchor = .topEdge,
    renderedHeight: CGFloat? = nil
) throws {
    _ = NSApplication.shared
    let previewDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("TermiNapPreview-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: previewDirectory)
    }

    let activityStore = ActivityStore(baseDirectory: previewDirectory)
    try activityStore.mutate { state in
        for index in 0..<activeCount {
            let sessionID = "preview-\(index)"
            state.busy[sessionID] = CodexTask(
                sessionID: sessionID,
                turnID: "turn-\(index)",
                cwd: "/Users/demo/project-\(index)",
                codexPID: nil
            )
        }
        state.revision = UInt64(activeCount)
    }

    let settingsStore = SettingsStore(baseDirectory: previewDirectory)
    try settingsStore.write(
        BatterySettings(
            enabled: enabled,
            action: .systemSleep,
            delaySeconds: 15
        )
    )

    let model = AppModel(
        activityStore: activityStore,
        settingsStore: settingsStore
    )
    model.setHookInstalled(true)

    let hostingView = NSHostingView(
        rootView: BatteryView(
            model: model,
            presentation: PanelPresentationState(
                initiallyExpanded: expanded,
                resizeAnchor: resizeAnchor
            )
        )
    )
    hostingView.frame = NSRect(
        origin: .zero,
        size: NSSize(
            width: BatteryView.panelWidth,
            height:
                renderedHeight
                ?? (
                    expanded
                    ? BatteryView.dashboardExpandedHeight
                    : BatteryView.collapsedHeight
                )
        )
    )
    hostingView.layoutSubtreeIfNeeded()

    guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
        throw CocoaError(.fileWriteUnknown)
    }
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: outputURL, options: .atomic)
}

@MainActor
func renderSetupPreview(to outputURL: URL, trustedCount: Int) throws {
    _ = NSApplication.shared
    let previewDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("TermiNapSetupPreview-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: previewDirectory)
    }

    let model = AppModel(
        activityStore: ActivityStore(baseDirectory: previewDirectory),
        settingsStore: SettingsStore(baseDirectory: previewDirectory)
    )
    model.setHookTrustForPreview(trustedCount: min(max(trustedCount, 0), 3))

    let hostingView = NSHostingView(
        rootView: BatteryView(
            model: model,
            presentation: PanelPresentationState(
                initiallyExpanded: true
            )
        )
    )
    hostingView.frame = NSRect(
        origin: .zero,
        size: NSSize(
            width: BatteryView.panelWidth,
            height: BatteryView.setupExpandedHeight
        )
    )
    hostingView.layoutSubtreeIfNeeded()

    guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
        throw CocoaError(.fileWriteUnknown)
    }
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: outputURL, options: .atomic)
}
