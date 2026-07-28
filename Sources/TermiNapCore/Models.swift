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
    public var enabled: Bool
    public var action: PowerAction
    public var delaySeconds: Int

    public init(
        enabled: Bool = false,
        action: PowerAction = .systemSleep,
        delaySeconds: Int = 15
    ) {
        self.enabled = enabled
        self.action = action
        self.delaySeconds = delaySeconds
    }
}

public struct CodexTask: Codable, Equatable, Identifiable {
    public let sessionID: String
    public let turnID: String
    public let cwd: String?
    public let startedAt: Date
    public let codexPID: Int32?

    public var id: String { sessionID }

    public init(
        sessionID: String,
        turnID: String,
        cwd: String?,
        startedAt: Date = Date(),
        codexPID: Int32? = nil
    ) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.cwd = cwd
        self.startedAt = startedAt
        self.codexPID = codexPID
    }
}

public struct ActivityState: Codable, Equatable {
    public var busy: [String: CodexTask]
    public var revision: UInt64
    public var updatedAt: Date
    public var lastCompletedAt: Date?

    public init(
        busy: [String: CodexTask] = [:],
        revision: UInt64 = 0,
        updatedAt: Date = Date(),
        lastCompletedAt: Date? = nil
    ) {
        self.busy = busy
        self.revision = revision
        self.updatedAt = updatedAt
        self.lastCompletedAt = lastCompletedAt
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
    private var previousBusyCount: Int?

    public init() {}

    public mutating func observe(busyCount: Int, automationEnabled: Bool) -> IdleDecision {
        defer { previousBusyCount = busyCount }

        guard let previousBusyCount else {
            return .none
        }

        if busyCount > 0 {
            return .cancel
        }

        if previousBusyCount > 0, busyCount == 0, automationEnabled {
            return .arm
        }

        return .none
    }
}
