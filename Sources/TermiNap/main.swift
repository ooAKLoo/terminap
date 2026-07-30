import AppKit
import TermiNapCore
import Foundation

private func runHook(arguments: [String]) -> Int32 {
    guard
        arguments.count >= 3,
        arguments[1] == "--hook",
        let kind = HookKind(rawValue: arguments[2])
    else {
        return 2
    }

    defer {
        if kind == .stop {
            print("{}")
        }
    }

    do {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let event = try JSONDecoder().decode(HookEvent.self, from: data)
        try HookProcessor(store: ActivityStore()).handle(kind, event: event)
        return 0
    } catch {
        let directory = TermiNapPaths.applicationSupportDirectory()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let message = "\(ISO8601DateFormatter().string(from: Date())) \(error)\n"
        let logURL = directory.appendingPathComponent("hook-errors.log")
        if let data = message.data(using: .utf8) {
            try? data.write(to: logURL, options: .atomic)
        }
        return 0
    }
}

if CommandLine.arguments.dropFirst().first == "--hook" {
    exit(runHook(arguments: CommandLine.arguments))
}

if CommandLine.arguments.dropFirst().first == "--render-preview" {
    guard CommandLine.arguments.count >= 5,
          let activeCount = Int(CommandLine.arguments[3])
    else {
        exit(2)
    }
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let enabled = CommandLine.arguments[4] == "true"
    let previewMode =
        CommandLine.arguments.count < 6
        ? "expanded"
        : CommandLine.arguments[5]
    let expanded = previewMode != "collapsed"
    let renderedHeight: CGFloat? =
        previewMode == "collapsing"
        ? BatteryView.collapsedHeight
        : nil
    let resizeAnchor: PanelResizeAnchor =
        CommandLine.arguments.count >= 7
        && CommandLine.arguments[6] == "upward"
        ? .bottomEdge
        : .topEdge
    let status: Int32 = MainActor.assumeIsolated {
        do {
            try renderPreview(
                to: outputURL,
                activeCount: max(activeCount, 0),
                enabled: enabled,
                expanded: expanded,
                resizeAnchor: resizeAnchor,
                renderedHeight: renderedHeight
            )
            return 0
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            return 1
        }
    }
    exit(status)
}

if CommandLine.arguments.dropFirst().first == "--render-setup-preview" {
    guard CommandLine.arguments.count >= 4,
          let trustedCount = Int(CommandLine.arguments[3])
    else {
        exit(2)
    }
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let status: Int32 = MainActor.assumeIsolated {
        do {
            try renderSetupPreview(
                to: outputURL,
                trustedCount: trustedCount
            )
            return 0
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            return 1
        }
    }
    exit(status)
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) {
        application.run()
    }
}
