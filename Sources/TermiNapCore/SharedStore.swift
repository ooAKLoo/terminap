import Darwin
import Foundation

public enum TermiNapPaths {
    public static func applicationSupportDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["TERMINAP_STATE_DIR"],
           !override.isEmpty
        {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return root.appendingPathComponent("TermiNap", isDirectory: true)
    }
}

private final class AdvisoryFileLock {
    private let descriptor: Int32

    init(url: URL) throws {
        descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard flock(descriptor, LOCK_EX) == 0 else {
            close(descriptor)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}

public final class ActivityStore {
    public let baseDirectory: URL
    private let stateURL: URL
    private let lockURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseDirectory: URL = TermiNapPaths.applicationSupportDirectory()) {
        self.baseDirectory = baseDirectory
        stateURL = baseDirectory.appendingPathComponent("activity.json")
        lockURL = baseDirectory.appendingPathComponent("activity.lock")

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func read() throws -> ActivityState {
        try ensureDirectory()
        let lock = try AdvisoryFileLock(url: lockURL)
        _ = lock
        return try readUnlocked()
    }

    @discardableResult
    public func mutate<T>(_ body: (inout ActivityState) throws -> T) throws -> T {
        try ensureDirectory()
        let lock = try AdvisoryFileLock(url: lockURL)
        _ = lock
        var state = try readUnlocked()
        let result = try body(&state)
        state.updatedAt = Date()
        try writeUnlocked(state)
        return result
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func readUnlocked() throws -> ActivityState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return ActivityState()
        }
        let data = try Data(contentsOf: stateURL)
        return try decoder.decode(ActivityState.self, from: data)
    }

    private func writeUnlocked(_ state: ActivityState) throws {
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: stateURL.path
        )
    }
}

public final class SettingsStore {
    public let baseDirectory: URL
    private let settingsURL: URL
    private let lockURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseDirectory: URL = TermiNapPaths.applicationSupportDirectory()) {
        self.baseDirectory = baseDirectory
        settingsURL = baseDirectory.appendingPathComponent("settings.json")
        lockURL = baseDirectory.appendingPathComponent("settings.lock")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    public func read() throws -> BatterySettings {
        try ensureDirectory()
        let lock = try AdvisoryFileLock(url: lockURL)
        _ = lock
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            return BatterySettings()
        }
        return try decoder.decode(
            BatterySettings.self,
            from: Data(contentsOf: settingsURL)
        )
    }

    public func write(_ settings: BatterySettings) throws {
        try ensureDirectory()
        let lock = try AdvisoryFileLock(url: lockURL)
        _ = lock
        let data = try encoder.encode(settings)
        try data.write(to: settingsURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: settingsURL.path
        )
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}
