import Foundation

public enum PowerAction: String, Codable, CaseIterable, Identifiable {
    case displaySleep
    case systemSleep
    case shutdown

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .displaySleep:
            return "仅熄屏"
        case .systemSleep:
            return "待机"
        case .shutdown:
            return "关机"
        }
    }

    public var symbolName: String {
        switch self {
        case .displaySleep:
            return "display"
        case .systemSleep:
            return "moon.zzz.fill"
        case .shutdown:
            return "power"
        }
    }
}

public struct BatterySettings: Codable, Equatable {
    private static let currentSchemaVersion = 3

    public static let defaultDelaySeconds = 5 * 60

    public var enabled: Bool
    public var action: PowerAction
    public var delaySeconds: Int

    public init(
        enabled: Bool = false,
        action: PowerAction = .systemSleep,
        delaySeconds: Int = Self.defaultDelaySeconds
    ) {
        self.enabled = enabled
        self.action = action
        self.delaySeconds = delaySeconds
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case enabled
        case action
        case delaySeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .schemaVersion
        ) ?? 1
        enabled = try container.decode(Bool.self, forKey: .enabled)
        action = try container.decode(PowerAction.self, forKey: .action)
        let storedDelay = try container.decodeIfPresent(
            Int.self,
            forKey: .delaySeconds
        )
        switch (schemaVersion, storedDelay) {
        case (_, nil):
            delaySeconds = Self.defaultDelaySeconds
        case (..<2, 15), (2, 30):
            delaySeconds = Self.defaultDelaySeconds
        case let (_, storedDelay?):
            delaySeconds = storedDelay
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            Self.currentSchemaVersion,
            forKey: .schemaVersion
        )
        try container.encode(enabled, forKey: .enabled)
        try container.encode(action, forKey: .action)
        try container.encode(delaySeconds, forKey: .delaySeconds)
    }
}

public enum CodexTaskProgress: String, Codable, Equatable {
    case running
    case waitingForPermission
    case interrupted
}

public enum CodexTaskTrackingSource: String, Codable, Equatable {
    case hook
    case sessionScan
}

public struct CodexTask: Codable, Equatable, Identifiable {
    public let sessionID: String
    public let turnID: String
    public let cwd: String?
    public let startedAt: Date
    public let codexPID: Int32?
    public let codexExecutablePath: String?
    public let progress: CodexTaskProgress
    public let trackingSource: CodexTaskTrackingSource
    public let interruptedAt: Date?

    public var id: String { sessionID }

    public init(
        sessionID: String,
        turnID: String,
        cwd: String?,
        startedAt: Date = Date(),
        codexPID: Int32? = nil,
        codexExecutablePath: String? = nil,
        progress: CodexTaskProgress = .running,
        trackingSource: CodexTaskTrackingSource = .hook,
        interruptedAt: Date? = nil
    ) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.cwd = cwd
        self.startedAt = startedAt
        self.codexPID = codexPID
        self.codexExecutablePath = codexExecutablePath
        self.progress = progress
        self.trackingSource = trackingSource
        self.interruptedAt = interruptedAt
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case turnID
        case cwd
        case startedAt
        case codexPID
        case codexExecutablePath
        case progress
        case trackingSource
        case interruptedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        turnID = try container.decode(String.self, forKey: .turnID)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        codexPID = try container.decodeIfPresent(Int32.self, forKey: .codexPID)
        codexExecutablePath = try container.decodeIfPresent(
            String.self,
            forKey: .codexExecutablePath
        )
        progress = try container.decodeIfPresent(
            CodexTaskProgress.self,
            forKey: .progress
        ) ?? .running
        trackingSource = try container.decodeIfPresent(
            CodexTaskTrackingSource.self,
            forKey: .trackingSource
        ) ?? .hook
        interruptedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .interruptedAt
        )
    }
}

public struct ActivityState: Codable, Equatable {
    public var tracked: [String: CodexTask]
    public var revision: UInt64
    public var updatedAt: Date
    public var lastCompletedAt: Date?

    public var busy: [String: CodexTask] {
        tracked.filter { $0.value.progress == .running }
    }

    public var waitingForPermission: [String: CodexTask] {
        tracked.filter { $0.value.progress == .waitingForPermission }
    }

    public var interrupted: [String: CodexTask] {
        tracked.filter { $0.value.progress == .interrupted }
    }

    public init(
        busy: [String: CodexTask] = [:],
        revision: UInt64 = 0,
        updatedAt: Date = Date(),
        lastCompletedAt: Date? = nil
    ) {
        tracked = busy
        self.revision = revision
        self.updatedAt = updatedAt
        self.lastCompletedAt = lastCompletedAt
    }

    private enum CodingKeys: String, CodingKey {
        case tracked = "busy"
        case revision
        case updatedAt
        case lastCompletedAt
    }
}

public struct HookEvent: Codable, Equatable {
    public let sessionID: String?
    public let turnID: String?
    public let cwd: String?
    public let eventName: String?

    public init(
        sessionID: String?,
        turnID: String?,
        cwd: String?,
        eventName: String? = nil
    ) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.cwd = cwd
        self.eventName = eventName
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case turnID = "turn_id"
        case cwd
        case eventName = "hook_event_name"
    }
}

public enum IdleDecision: Equatable {
    case none
    case cancel
    case arm
}

public struct IdleDecisionEngine {
    private var previousUnfinishedTaskCount: Int?

    public init() {}

    public mutating func observe(
        unfinishedTaskCount: Int,
        automationEnabled: Bool
    ) -> IdleDecision {
        defer { previousUnfinishedTaskCount = unfinishedTaskCount }

        guard let previousUnfinishedTaskCount else {
            return .none
        }

        if unfinishedTaskCount > 0 {
            return .cancel
        }

        if previousUnfinishedTaskCount > 0,
            unfinishedTaskCount == 0,
            automationEnabled
        {
            return .arm
        }

        return .none
    }
}
