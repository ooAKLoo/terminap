import Foundation

public enum PowerController {
    public static func execute(
        _ action: PowerAction,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        if environment["TERMINAP_DRY_RUN"] == "1" {
            try appendDryRun(action)
            return
        }

        let process = Process()
        switch action {
        case .displaySleep:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["displaysleepnow"]
        case .systemSleep:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["sleepnow"]
        case .shutdown:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = [
                "-e",
                "tell application \"System Events\" to shut down",
            ]
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private static func appendDryRun(_ action: PowerAction) throws {
        let directory = TermiNapPaths.applicationSupportDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let logURL = directory.appendingPathComponent("dry-run.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(action.rawValue)\n"
        let data = Data(line.utf8)

        if FileManager.default.fileExists(atPath: logURL.path) {
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: logURL, options: .atomic)
        }
    }
}
