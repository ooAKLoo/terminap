import Darwin
import Foundation

public enum HookKind: String {
    case start
    case permission
    case resume
    case stop
    case end
}

public struct CodexProcessContext: Equatable {
    public let pid: Int32?
    public let tty: String

    public init(pid: Int32?, tty: String) {
        self.pid = pid
        self.tty = tty
    }
}

public enum TerminalCodexDetector {
    public static func detect() -> CodexProcessContext? {
        if ProcessInfo.processInfo.environment["TERMINAP_FORCE_TERMINAL"] == "1" {
            return CodexProcessContext(pid: nil, tty: "forced")
        }

        var pid = getppid()
        for _ in 0..<12 {
            guard let snapshot = snapshot(pid: pid) else {
                break
            }
            let executable = URL(fileURLWithPath: snapshot.command)
                .lastPathComponent
                .lowercased()
            if executable == "codex" || executable.hasPrefix("codex-") {
                guard snapshot.tty != "??", snapshot.tty != "-", !snapshot.tty.isEmpty else {
                    return nil
                }
                return CodexProcessContext(pid: pid, tty: snapshot.tty)
            }
            guard snapshot.parentPID > 1, snapshot.parentPID != pid else {
                break
            }
            pid = snapshot.parentPID
        }

        if openControllingTerminal() {
            return CodexProcessContext(pid: nil, tty: "controlling-tty")
        }
        return nil
    }

    private struct Snapshot {
        let parentPID: Int32
        let tty: String
        let command: String
    }

    private static func snapshot(pid: Int32) -> Snapshot? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "ppid=,tty=,comm=", "-p", String(pid)]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let line = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !line.isEmpty
        else {
            return nil
        }

        let fields = line.split(
            maxSplits: 2,
            omittingEmptySubsequences: true,
            whereSeparator: \.isWhitespace
        )
        guard fields.count == 3, let parentPID = Int32(fields[0]) else {
            return nil
        }
        return Snapshot(
            parentPID: parentPID,
            tty: String(fields[1]),
            command: String(fields[2])
        )
    }

    private static func openControllingTerminal() -> Bool {
        let descriptor = open("/dev/tty", O_RDONLY | O_NONBLOCK)
        guard descriptor >= 0 else {
            return false
        }
        close(descriptor)
        return true
    }
}

public final class HookProcessor {
    private let store: ActivityStore
    private let now: () -> Date
    private let terminalContext: () -> CodexProcessContext?
    private let processIsAlive: (Int32) -> Bool
    private let maximumBusyAge: TimeInterval

    public init(
        store: ActivityStore,
        now: @escaping () -> Date = Date.init,
        terminalContext: @escaping () -> CodexProcessContext? = TerminalCodexDetector.detect,
        processIsAlive: @escaping (Int32) -> Bool = HookProcessor.defaultProcessIsAlive,
        maximumBusyAge: TimeInterval = 86_400
    ) {
        self.store = store
        self.now = now
        self.terminalContext = terminalContext
        self.processIsAlive = processIsAlive
        self.maximumBusyAge = maximumBusyAge
    }

    public func handle(_ kind: HookKind, event: HookEvent) throws {
        switch kind {
        case .start:
            try handleStart(event)
        case .permission:
            try handlePermissionRequest(event)
        case .resume:
            try handleResume(event)
        case .stop:
            try handleStop(event)
        case .end:
            try handleEnd(event)
        }
    }

    public func pruneStaleTasks() throws {
        try store.mutate { state in
            let countBefore = state.tracked.count
            prune(&state)
            if state.tracked.count != countBefore {
                state.lastCompletedAt = now()
                state.revision &+= 1
            }
        }
    }

    private func handleStart(_ event: HookEvent) throws {
        guard
            let sessionID = event.sessionID,
            let turnID = event.turnID,
            let context = terminalContext()
        else {
            return
        }

        try store.mutate { state in
            prune(&state)
            state.tracked[sessionID] = CodexTask(
                sessionID: sessionID,
                turnID: turnID,
                cwd: event.cwd,
                startedAt: now(),
                codexPID: context.pid
            )
            state.revision &+= 1
        }
    }

    private func handlePermissionRequest(_ event: HookEvent) throws {
        guard let sessionID = event.sessionID else {
            return
        }

        try store.mutate { state in
            prune(&state)
            guard
                let existing = state.tracked[sessionID],
                existing.progress == .running
            else {
                return
            }
            if let turnID = event.turnID, existing.turnID != turnID {
                return
            }
            state.tracked[sessionID] = CodexTask(
                sessionID: existing.sessionID,
                turnID: existing.turnID,
                cwd: event.cwd ?? existing.cwd,
                startedAt: existing.startedAt,
                codexPID: existing.codexPID,
                progress: .waitingForPermission
            )
            state.revision &+= 1
        }
    }

    private func handleResume(_ event: HookEvent) throws {
        guard let sessionID = event.sessionID else {
            return
        }

        try store.mutate { state in
            prune(&state)
            guard
                let existing = state.tracked[sessionID],
                existing.progress == .waitingForPermission
            else {
                return
            }
            if let turnID = event.turnID, existing.turnID != turnID {
                return
            }
            let context = terminalContext()
            state.tracked[sessionID] = CodexTask(
                sessionID: existing.sessionID,
                turnID: existing.turnID,
                cwd: event.cwd ?? existing.cwd,
                startedAt: now(),
                codexPID: context?.pid ?? existing.codexPID,
                progress: .running
            )
            state.revision &+= 1
        }
    }

    private func handleStop(_ event: HookEvent) throws {
        guard let sessionID = event.sessionID else {
            return
        }

        try store.mutate { state in
            prune(&state)
            guard let existing = state.tracked[sessionID] else {
                return
            }
            if let turnID = event.turnID, existing.turnID != turnID {
                return
            }
            state.tracked.removeValue(forKey: sessionID)
            state.lastCompletedAt = now()
            state.revision &+= 1
        }
    }

    private func handleEnd(_ event: HookEvent) throws {
        guard let sessionID = event.sessionID else {
            return
        }

        try store.mutate { state in
            prune(&state)
            guard state.tracked.removeValue(forKey: sessionID) != nil else {
                return
            }
            state.lastCompletedAt = now()
            state.revision &+= 1
        }
    }

    private func prune(_ state: inout ActivityState) {
        let currentDate = now()
        for (sessionID, task) in state.tracked {
            let expiredWithoutPID = task.codexPID == nil
                && currentDate.timeIntervalSince(task.startedAt) > maximumBusyAge
            let dead = task.codexPID.map { !processIsAlive($0) } ?? false
            if expiredWithoutPID || dead {
                state.tracked.removeValue(forKey: sessionID)
            }
        }
    }

    public static func defaultProcessIsAlive(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }
}
