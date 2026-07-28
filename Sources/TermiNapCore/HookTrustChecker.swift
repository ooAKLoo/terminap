import Foundation

public enum CodexHookTrustStatus: String, Sendable {
    case managed
    case untrusted
    case trusted
    case modified
    case unknown

    public var isAccepted: Bool {
        self == .trusted || self == .managed
    }
}

public struct CodexHookTrustReport: Equatable, Sendable {
    public static let requiredKinds = ["start", "stop", "end"]

    public let statuses: [String: CodexHookTrustStatus]

    public init(statuses: [String: CodexHookTrustStatus]) {
        self.statuses = statuses
    }

    public var foundCount: Int {
        statuses.count
    }

    public var trustedCount: Int {
        Self.requiredKinds.filter {
            statuses[$0]?.isAccepted == true
        }.count
    }

    public var modifiedCount: Int {
        statuses.values.filter { $0 == .modified }.count
    }

    public var isFullyTrusted: Bool {
        trustedCount == Self.requiredKinds.count
    }
}

public enum CodexHookTrustError: LocalizedError {
    case codexNotFound
    case launchFailed(String)
    case timedOut
    case invalidResponse
    case serverError(String)

    public var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "未找到 Codex 命令行程序"
        case let .launchFailed(message):
            return "无法启动 Codex 状态检测：\(message)"
        case .timedOut:
            return "Codex 状态检测超时"
        case .invalidResponse:
            return "Codex 返回了无法识别的 hooks 状态"
        case let .serverError(message):
            return "Codex hooks 状态读取失败：\(message)"
        }
    }
}

public enum CodexExecutableLocator {
    public static func locate(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            homeDirectory.appendingPathComponent(".local/bin/codex").path,
            homeDirectory.appendingPathComponent(".npm-global/bin/codex").path,
            homeDirectory.appendingPathComponent(".volta/bin/codex").path,
        ]

        return candidates
            .first(where: { fileManager.isExecutableFile(atPath: $0) })
            .map(URL.init(fileURLWithPath:))
    }
}

public enum CodexHookTrustParser {
    public static func parse(
        responseData: Data,
        appExecutablePath: String
    ) throws -> CodexHookTrustReport {
        guard
            let root = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        else {
            throw CodexHookTrustError.invalidResponse
        }

        if let error = root["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "未知错误"
            throw CodexHookTrustError.serverError(message)
        }

        guard
            let result = root["result"] as? [String: Any],
            let data = result["data"] as? [[String: Any]]
        else {
            throw CodexHookTrustError.invalidResponse
        }

        var statuses: [String: CodexHookTrustStatus] = [:]
        for workspace in data {
            let hooks = workspace["hooks"] as? [[String: Any]] ?? []
            for hook in hooks {
                guard
                    hook["enabled"] as? Bool != false,
                    let command = hook["command"] as? String,
                    command.contains(appExecutablePath),
                    let kind = hookKind(in: command)
                else {
                    continue
                }
                let rawStatus = hook["trustStatus"] as? String ?? ""
                let status = CodexHookTrustStatus(rawValue: rawStatus) ?? .unknown
                statuses[kind] = preferred(status, over: statuses[kind])
            }
        }

        return CodexHookTrustReport(statuses: statuses)
    }

    private static func hookKind(in command: String) -> String? {
        CodexHookTrustReport.requiredKinds.first {
            command.contains("--hook \($0)")
        }
    }

    private static func preferred(
        _ candidate: CodexHookTrustStatus,
        over existing: CodexHookTrustStatus?
    ) -> CodexHookTrustStatus {
        guard let existing else {
            return candidate
        }
        let rank: [CodexHookTrustStatus: Int] = [
            .unknown: 0,
            .untrusted: 1,
            .modified: 2,
            .trusted: 3,
            .managed: 4,
        ]
        return rank[candidate, default: 0] > rank[existing, default: 0]
            ? candidate
            : existing
    }
}

public final class CodexHookTrustChecker: @unchecked Sendable {
    public init() {}

    public func check(
        codexExecutableURL: URL,
        appExecutablePath: String,
        cwd: String,
        timeout: TimeInterval = 5
    ) throws -> CodexHookTrustReport {
        let process = Process()
        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = codexExecutableURL
        process.arguments = ["app-server"]
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        let responseLock = NSLock()
        let responseReady = DispatchSemaphore(value: 0)
        var bufferedData = Data()
        var responseData: Data?
        var errorData = Data()

        standardOutput.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                return
            }

            responseLock.lock()
            bufferedData.append(chunk)
            while let newline = bufferedData.firstIndex(of: 0x0A) {
                let line = bufferedData.prefix(upTo: newline)
                bufferedData.removeSubrange(...newline)
                guard
                    let object = try? JSONSerialization.jsonObject(with: line),
                    let dictionary = object as? [String: Any],
                    (dictionary["id"] as? NSNumber)?.intValue == 1
                else {
                    continue
                }
                responseData = Data(line)
                responseReady.signal()
                break
            }
            responseLock.unlock()
        }

        standardError.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                return
            }
            responseLock.lock()
            if errorData.count < 16_384 {
                errorData.append(chunk)
            }
            responseLock.unlock()
        }

        do {
            try process.run()
        } catch {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            throw CodexHookTrustError.launchFailed(error.localizedDescription)
        }

        do {
            let messages: [[String: Any]] = [
                [
                    "method": "initialize",
                    "id": 0,
                    "params": [
                        "clientInfo": [
                            "name": "terminap",
                            "title": "TermiNap",
                            "version": "0.1.0",
                        ],
                        "capabilities": ["experimentalApi": true],
                    ],
                ],
                ["method": "initialized", "params": [:]],
                [
                    "method": "hooks/list",
                    "id": 1,
                    "params": ["cwds": [cwd]],
                ],
            ]
            for message in messages {
                var data = try JSONSerialization.data(withJSONObject: message)
                data.append(0x0A)
                try standardInput.fileHandleForWriting.write(contentsOf: data)
            }
        } catch {
            stop(
                process,
                standardInput: standardInput,
                standardOutput: standardOutput,
                standardError: standardError
            )
            throw CodexHookTrustError.launchFailed(error.localizedDescription)
        }

        let waitResult = responseReady.wait(timeout: .now() + timeout)
        responseLock.lock()
        let capturedResponse = responseData
        let capturedError = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        responseLock.unlock()

        stop(
            process,
            standardInput: standardInput,
            standardOutput: standardOutput,
            standardError: standardError
        )

        guard waitResult == .success, let capturedResponse else {
            if let capturedError, !capturedError.isEmpty {
                throw CodexHookTrustError.serverError(capturedError)
            }
            throw CodexHookTrustError.timedOut
        }
        return try CodexHookTrustParser.parse(
            responseData: capturedResponse,
            appExecutablePath: appExecutablePath
        )
    }

    private func stop(
        _ process: Process,
        standardInput: Pipe,
        standardOutput: Pipe,
        standardError: Pipe
    ) {
        standardOutput.fileHandleForReading.readabilityHandler = nil
        standardError.fileHandleForReading.readabilityHandler = nil
        try? standardInput.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }
}
