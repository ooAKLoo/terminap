import Foundation

public struct HookInstallResult: Equatable {
    public let installed: Bool
    public let hooksURL: URL
    public let backupURL: URL?

    public init(installed: Bool, hooksURL: URL, backupURL: URL?) {
        self.installed = installed
        self.hooksURL = hooksURL
        self.backupURL = backupURL
    }
}

public enum HookInstaller {
    private static let ownedNeedles = [
        "TermiNap --hook",
        "TermiNap' --hook",
        "CodexBattery --hook",
        "CodexBattery' --hook",
        "terminal_codex_idle_sleep.py",
    ]

    public static func install(
        executablePath: String,
        codexDirectory: URL
    ) throws -> HookInstallResult {
        try FileManager.default.createDirectory(
            at: codexDirectory,
            withIntermediateDirectories: true
        )

        let hooksURL = codexDirectory.appendingPathComponent("hooks.json")
        let backupURL = codexDirectory.appendingPathComponent(
            "hooks.json.before-terminap"
        )
        var root: [String: Any] = [:]
        var createdBackup: URL?

        if FileManager.default.fileExists(atPath: hooksURL.path) {
            let data = try Data(contentsOf: hooksURL)
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            root = dictionary

            if !FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.copyItem(at: hooksURL, to: backupURL)
                createdBackup = backupURL
            }
        }

        if root["description"] == nil {
            root["description"] = "用户级 Codex 生命周期 hooks。"
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for eventName in Array(hooks.keys) {
            guard let groups = hooks[eventName] as? [[String: Any]] else {
                continue
            }
            let preservedGroups = groups.compactMap(removingOwnedCommands)
            if preservedGroups.isEmpty {
                hooks.removeValue(forKey: eventName)
            } else {
                hooks[eventName] = preservedGroups
            }
        }

        let eventCommands: [(String, String)] = [
            ("UserPromptSubmit", "start"),
            ("PermissionRequest", "permission"),
            ("PostToolUse", "resume"),
            ("Stop", "stop"),
            ("SessionEnd", "end"),
        ]

        for (eventName, hookKind) in eventCommands {
            var groups = hooks[eventName] as? [[String: Any]] ?? []
            groups.append([
                "hooks": [[
                    "type": "command",
                    "command": "\(shellQuote(executablePath)) --hook \(hookKind)",
                    "timeout": 3,
                ]],
            ])
            hooks[eventName] = groups
        }

        root["hooks"] = hooks
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: hooksURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: hooksURL.path
        )

        return HookInstallResult(
            installed: true,
            hooksURL: hooksURL,
            backupURL: createdBackup
        )
    }

    private static func removingOwnedCommands(
        from group: [String: Any]
    ) -> [String: Any]? {
        guard var handlers = group["hooks"] as? [[String: Any]] else {
            return group
        }
        handlers.removeAll { handler in
            guard let command = handler["command"] as? String else {
                return false
            }
            return ownedNeedles.contains(where: command.contains)
        }
        guard !handlers.isEmpty else {
            return nil
        }
        var preserved = group
        preserved["hooks"] = handlers
        return preserved
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
