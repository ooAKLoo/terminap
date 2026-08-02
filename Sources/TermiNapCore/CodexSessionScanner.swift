import Foundation

struct ProcessCommandResult {
    let data: Data
    let terminationStatus: Int32
}

enum CodexSessionScanError: LocalizedError {
    case commandFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, status):
            return "\(command) 退出码为 \(status)"
        }
    }
}

struct CodexSessionScanResult: Equatable {
    let observedSessionIDs: Set<String>
    let completedSessionIDs: Set<String>
    let activeTasks: [String: CodexTask]

    init(
        observedSessionIDs: Set<String> = [],
        completedSessionIDs: Set<String> = [],
        activeTasks: [String: CodexTask] = [:]
    ) {
        self.observedSessionIDs = observedSessionIDs
        self.completedSessionIDs = completedSessionIDs
        self.activeTasks = activeTasks
    }
}

final class TerminalCodexSessionScanner: @unchecked Sendable {
    private struct SessionMetadata {
        let sessionID: String
        let cwd: String?
    }

    private enum LifecycleState {
        case active(turnID: String, startedAt: Date)
        case completed
    }

    private struct CachedLifecycle {
        let fileSize: UInt64
        let state: LifecycleState?
    }

    private let sessionsRoot: URL
    private let runProcess: (URL, [String]) throws -> ProcessCommandResult
    private let cacheLock = NSLock()
    private var lifecycleCache: [URL: CachedLifecycle] = [:]

    convenience init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        self.init(
            sessionsRoot: homeDirectory
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
        )
    }

    init(
        sessionsRoot: URL,
        runProcess: @escaping (URL, [String]) throws -> ProcessCommandResult =
            TerminalCodexSessionScanner.defaultRunProcess
    ) {
        self.sessionsRoot = sessionsRoot.standardizedFileURL
        self.runProcess = runProcess
    }

    func scan() throws -> CodexSessionScanResult {
        let processResult = try runProcess(
            URL(fileURLWithPath: "/bin/ps"),
            ["-axo", "pid=,tty=,comm="]
        )
        guard processResult.terminationStatus == 0 else {
            throw CodexSessionScanError.commandFailed(
                "ps",
                processResult.terminationStatus
            )
        }

        let terminalPIDs = Self.terminalCodexPIDs(from: processResult.data)
        guard !terminalPIDs.isEmpty else {
            cacheLock.lock()
            lifecycleCache.removeAll()
            cacheLock.unlock()
            return CodexSessionScanResult()
        }

        let pidList = terminalPIDs.sorted().map(String.init).joined(separator: ",")
        let openFilesResult = try runProcess(
            URL(fileURLWithPath: "/usr/sbin/lsof"),
            ["-n", "-P", "-a", "-p", pidList, "-Fpn"]
        )
        guard [0, 1].contains(openFilesResult.terminationStatus) else {
            throw CodexSessionScanError.commandFailed(
                "lsof",
                openFilesResult.terminationStatus
            )
        }

        let rolloutFiles = Self.rolloutFiles(
            from: openFilesResult.data,
            allowedPIDs: terminalPIDs,
            sessionsRoot: sessionsRoot
        )
        var observedSessionIDs: Set<String> = []
        var completedSessionIDs: Set<String> = []
        var activeTasks: [String: CodexTask] = [:]

        cacheLock.lock()
        defer {
            lifecycleCache = lifecycleCache.filter { rolloutFiles[$0.key] != nil }
            cacheLock.unlock()
        }

        for (rolloutURL, pid) in rolloutFiles {
            guard
                let metadata = try Self.readSessionMetadata(from: rolloutURL),
                let lifecycle = try lifecycleState(for: rolloutURL)
            else {
                continue
            }
            observedSessionIDs.insert(metadata.sessionID)

            switch lifecycle {
            case let .active(turnID, startedAt):
                activeTasks[metadata.sessionID] = CodexTask(
                    sessionID: metadata.sessionID,
                    turnID: turnID,
                    cwd: metadata.cwd,
                    startedAt: startedAt,
                    codexPID: pid,
                    trackingSource: .sessionScan
                )
            case .completed:
                completedSessionIDs.insert(metadata.sessionID)
            }
        }

        return CodexSessionScanResult(
            observedSessionIDs: observedSessionIDs,
            completedSessionIDs: completedSessionIDs,
            activeTasks: activeTasks
        )
    }

    static func terminalCodexPIDs(from data: Data) -> Set<Int32> {
        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }

        var result: Set<Int32> = []
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(
                maxSplits: 2,
                omittingEmptySubsequences: true,
                whereSeparator: \.isWhitespace
            )
            guard fields.count == 3, let pid = Int32(fields[0]) else {
                continue
            }
            let tty = String(fields[1])
            guard tty != "??", tty != "-" else {
                continue
            }
            let executable = URL(fileURLWithPath: String(fields[2]))
                .lastPathComponent
                .lowercased()
            if executable == "codex" {
                result.insert(pid)
            }
        }
        return result
    }

    static func rolloutFiles(
        from data: Data,
        allowedPIDs: Set<Int32>,
        sessionsRoot: URL
    ) -> [URL: Int32] {
        guard let output = String(data: data, encoding: .utf8) else {
            return [:]
        }

        let normalizedRoot = sessionsRoot.standardizedFileURL.path
        let rootPrefix = normalizedRoot.hasSuffix("/")
            ? normalizedRoot
            : normalizedRoot + "/"
        var currentPID: Int32?
        var result: [URL: Int32] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            guard let marker = line.first else {
                continue
            }
            let value = String(line.dropFirst())
            if marker == "p" {
                let pid = Int32(value)
                currentPID = pid.flatMap { allowedPIDs.contains($0) ? $0 : nil }
                continue
            }
            guard marker == "n", let currentPID else {
                continue
            }
            let url = URL(fileURLWithPath: value).standardizedFileURL
            guard
                url.path.hasPrefix(rootPrefix),
                url.pathExtension == "jsonl"
            else {
                continue
            }
            result[url] = currentPID
        }
        return result
    }

    private static func readSessionMetadata(
        from url: URL
    ) throws -> SessionMetadata? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: 65_536), !data.isEmpty else {
            return nil
        }
        let line = data.prefix { $0 != 0x0A }
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(line)),
            let root = object as? [String: Any],
            root["type"] as? String == "session_meta",
            let payload = root["payload"] as? [String: Any],
            let sessionID = payload["id"] as? String,
            !sessionID.isEmpty
        else {
            return nil
        }

        let originator = payload["originator"] as? String
        if let source = payload["source"] {
            guard let source = source as? String, source == "cli" else {
                return nil
            }
        } else {
            guard originator == "codex-tui" else {
                return nil
            }
        }
        return SessionMetadata(
            sessionID: sessionID,
            cwd: payload["cwd"] as? String
        )
    }

    private func lifecycleState(for url: URL) throws -> LifecycleState? {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileSize = (attributes[.size] as? NSNumber)?.uint64Value else {
            return nil
        }
        if let cached = lifecycleCache[url], cached.fileSize == fileSize {
            return cached.state
        }

        let cached = lifecycleCache[url]
        let lowerBound: UInt64
        if let cached, fileSize >= cached.fileSize {
            lowerBound = cached.fileSize > 65_536
                ? cached.fileSize - 65_536
                : 0
        } else {
            lowerBound = 0
        }
        let latest = try Self.readLatestLifecycle(
            from: url,
            fileSize: fileSize,
            lowerBound: lowerBound
        ) ?? cached?.state
        lifecycleCache[url] = CachedLifecycle(
            fileSize: fileSize,
            state: latest
        )
        return latest
    }

    private static func readLatestLifecycle(
        from url: URL,
        fileSize: UInt64,
        lowerBound: UInt64
    ) throws -> LifecycleState? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard fileSize > 0 else {
            return nil
        }

        let chunkSize: UInt64 = 65_536
        var position = fileSize
        var laterLineFragment = Data()

        while position > lowerBound {
            let start = position - lowerBound > chunkSize
                ? position - chunkSize
                : lowerBound
            try handle.seek(toOffset: start)
            guard let chunk = try handle.read(upToCount: Int(position - start)) else {
                return nil
            }
            var combined = chunk
            combined.append(laterLineFragment)
            let lines = combined.split(
                separator: 0x0A,
                omittingEmptySubsequences: false
            )
            let firstCompleteIndex = start == 0 ? 0 : 1

            if lines.count > firstCompleteIndex {
                for index in stride(
                    from: lines.count - 1,
                    through: firstCompleteIndex,
                    by: -1
                ) {
                    if let lifecycle = lifecycle(from: Data(lines[index])) {
                        return lifecycle
                    }
                }
            }

            laterLineFragment = lines.isEmpty ? Data() : Data(lines[0])
            position = start
        }
        return nil
    }

    private static func lifecycle(from line: Data) -> LifecycleState? {
        let taskStarted = Data("\"task_started\"".utf8)
        let taskComplete = Data("\"task_complete\"".utf8)
        let turnAborted = Data("\"turn_aborted\"".utf8)
        guard
            line.range(of: taskStarted) != nil
                || line.range(of: taskComplete) != nil
                || line.range(of: turnAborted) != nil,
            let object = try? JSONSerialization.jsonObject(with: line),
            let root = object as? [String: Any],
            root["type"] as? String == "event_msg",
            let payload = root["payload"] as? [String: Any],
            let eventType = payload["type"] as? String
        else {
            return nil
        }

        if eventType == "task_complete" || eventType == "turn_aborted" {
            return .completed
        }
        guard
            eventType == "task_started",
            let turnID = payload["turn_id"] as? String,
            !turnID.isEmpty
        else {
            return nil
        }
        let timestamp = (payload["started_at"] as? NSNumber)?.doubleValue
        return .active(
            turnID: turnID,
            startedAt: timestamp.map(Date.init(timeIntervalSince1970:)) ?? Date()
        )
    }

    private static func defaultRunProcess(
        executableURL: URL,
        arguments: [String]
    ) throws -> ProcessCommandResult {
        let process = Process()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProcessCommandResult(
            data: data,
            terminationStatus: process.terminationStatus
        )
    }
}

public final class CodexSessionReconciler: @unchecked Sendable {
    private let store: ActivityStore
    private let now: () -> Date
    private let scan: () throws -> CodexSessionScanResult

    public convenience init(
        store: ActivityStore,
        now: @escaping () -> Date = Date.init
    ) {
        let scanner = TerminalCodexSessionScanner()
        self.init(store: store, now: now, scan: scanner.scan)
    }

    init(
        store: ActivityStore,
        now: @escaping () -> Date = Date.init,
        scan: @escaping () throws -> CodexSessionScanResult
    ) {
        self.store = store
        self.now = now
        self.scan = scan
    }

    public func reconcile() throws {
        let result = try scan()
        try store.mutate { state in
            var changed = false
            var removedTask = false

            for (sessionID, task) in state.tracked {
                let explicitlyCompleted = result.completedSessionIDs.contains(sessionID)
                let scannerLostSession = task.trackingSource == .sessionScan
                    && !result.observedSessionIDs.contains(sessionID)
                if explicitlyCompleted || scannerLostSession {
                    state.tracked.removeValue(forKey: sessionID)
                    changed = true
                    removedTask = true
                }
            }

            for (sessionID, discovered) in result.activeTasks {
                if let existing = state.tracked[sessionID],
                   existing.turnID == discovered.turnID,
                   existing.trackingSource == .hook
                {
                    continue
                }
                if state.tracked[sessionID] != discovered {
                    state.tracked[sessionID] = discovered
                    changed = true
                }
            }

            guard changed else {
                return
            }
            if removedTask {
                state.lastCompletedAt = now()
            }
            state.revision &+= 1
        }
    }
}
