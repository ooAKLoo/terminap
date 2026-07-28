import CoreGraphics
import XCTest
@testable import TermiNapCore

final class TermiNapCoreTests: XCTestCase {
    func testTracksEveryTerminalUntilTheLastTaskStops() throws {
        let directory = temporaryDirectory()
        let store = ActivityStore(baseDirectory: directory)
        let context = CodexProcessContext(pid: 1234, tty: "ttys001")
        let processor = HookProcessor(
            store: store,
            terminalContext: { context },
            processIsAlive: { _ in true }
        )

        try processor.handle(
            .start,
            event: HookEvent(sessionID: "a", turnID: "turn-a", cwd: "/a")
        )
        try processor.handle(
            .start,
            event: HookEvent(sessionID: "b", turnID: "turn-b", cwd: "/b")
        )
        XCTAssertEqual(try store.read().busy.count, 2)

        try processor.handle(
            .stop,
            event: HookEvent(sessionID: "a", turnID: "turn-a", cwd: "/a")
        )
        XCTAssertEqual(Set(try store.read().busy.keys), ["b"])

        try processor.handle(
            .stop,
            event: HookEvent(sessionID: "b", turnID: "turn-b", cwd: "/b")
        )
        XCTAssertTrue(try store.read().busy.isEmpty)
        XCTAssertNotNil(try store.read().lastCompletedAt)
    }

    func testIgnoresNonTerminalCodexEvents() throws {
        let store = ActivityStore(baseDirectory: temporaryDirectory())
        let processor = HookProcessor(
            store: store,
            terminalContext: { nil }
        )

        try processor.handle(
            .start,
            event: HookEvent(sessionID: "desktop", turnID: "turn", cwd: "/app")
        )
        XCTAssertTrue(try store.read().busy.isEmpty)
    }

    func testMismatchedStopDoesNotClearNewerTurn() throws {
        let store = ActivityStore(baseDirectory: temporaryDirectory())
        let processor = HookProcessor(
            store: store,
            terminalContext: {
                CodexProcessContext(pid: 1234, tty: "ttys001")
            },
            processIsAlive: { _ in true }
        )
        try processor.handle(
            .start,
            event: HookEvent(sessionID: "a", turnID: "new-turn", cwd: "/a")
        )
        try processor.handle(
            .stop,
            event: HookEvent(sessionID: "a", turnID: "old-turn", cwd: "/a")
        )
        XCTAssertEqual(try store.read().busy["a"]?.turnID, "new-turn")
    }

    func testIdleDecisionOnlyArmsOnBusyToZeroTransition() {
        var engine = IdleDecisionEngine()
        XCTAssertEqual(engine.observe(busyCount: 0, automationEnabled: true), .none)
        XCTAssertEqual(engine.observe(busyCount: 2, automationEnabled: true), .cancel)
        XCTAssertEqual(engine.observe(busyCount: 1, automationEnabled: true), .cancel)
        XCTAssertEqual(engine.observe(busyCount: 0, automationEnabled: true), .arm)
        XCTAssertEqual(engine.observe(busyCount: 0, automationEnabled: true), .none)
    }

    func testHookInstallerPreservesUnrelatedHooks() throws {
        let codexDirectory = temporaryDirectory()
        let hooksURL = codexDirectory.appendingPathComponent("hooks.json")
        let existing: [String: Any] = [
            "description": "existing",
            "hooks": [
                "Stop": [[
                    "hooks": [[
                        "type": "command",
                        "command": "/usr/bin/python3 /tmp/existing.py",
                    ]],
                ]],
            ],
        ]
        let data = try JSONSerialization.data(
            withJSONObject: existing,
            options: [.prettyPrinted]
        )
        try data.write(to: hooksURL)

        _ = try HookInstaller.install(
            executablePath: "/Users/test/Applications/TermiNap.app/Contents/MacOS/TermiNap",
            codexDirectory: codexDirectory
        )

        let result = try JSONSerialization.jsonObject(
            with: Data(contentsOf: hooksURL)
        ) as! [String: Any]
        let hooks = result["hooks"] as! [String: Any]
        let stopGroups = hooks["Stop"] as! [[String: Any]]
        XCTAssertEqual(stopGroups.count, 2)
        let commands = stopGroups.flatMap { group -> [String] in
            let handlers = group["hooks"] as? [[String: Any]] ?? []
            return handlers.compactMap { $0["command"] as? String }
        }
        XCTAssertTrue(commands.contains("/usr/bin/python3 /tmp/existing.py"))
    }

    func testParsesTermiNapHookTrustStatus() throws {
        let executablePath = "/Users/test/Applications/TermiNap.app/Contents/MacOS/TermiNap"
        let response: [String: Any] = [
            "id": 1,
            "result": [
                "data": [[
                    "cwd": "/Users/test/project",
                    "hooks": [
                        hook(
                            command: "'\(executablePath)' --hook start",
                            status: "trusted"
                        ),
                        hook(
                            command: "'\(executablePath)' --hook stop",
                            status: "managed"
                        ),
                        hook(
                            command: "'\(executablePath)' --hook end",
                            status: "untrusted"
                        ),
                        hook(
                            command: "/usr/bin/other-hook",
                            status: "trusted"
                        ),
                    ],
                ]],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: response)

        let report = try CodexHookTrustParser.parse(
            responseData: data,
            appExecutablePath: executablePath
        )

        XCTAssertEqual(report.foundCount, 3)
        XCTAssertEqual(report.trustedCount, 2)
        XCTAssertEqual(report.statuses["end"], .untrusted)
        XCTAssertFalse(report.isFullyTrusted)
    }

    func testReportsAllThreeAcceptedHooksAsReady() throws {
        let executablePath = "/Applications/TermiNap.app/Contents/MacOS/TermiNap"
        let hooks = CodexHookTrustReport.requiredKinds.map {
            hook(
                command: "'\(executablePath)' --hook \($0)",
                status: "trusted"
            )
        }
        let response: [String: Any] = [
            "id": 1,
            "result": ["data": [["cwd": "/tmp", "hooks": hooks]]],
        ]
        let data = try JSONSerialization.data(withJSONObject: response)

        let report = try CodexHookTrustParser.parse(
            responseData: data,
            appExecutablePath: executablePath
        )

        XCTAssertTrue(report.isFullyTrusted)
        XCTAssertEqual(report.trustedCount, 3)
    }

    func testPanelPlacementStaysInsideDisplayWithNegativeCoordinates() {
        let visibleFrame = CGRect(
            x: -975,
            y: 1117,
            width: 3360,
            height: 1418
        )
        let panelSize = CGSize(width: 300, height: 390)

        let origin = PanelPlacement.topTrailingOrigin(
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            margin: 32
        )

        XCTAssertEqual(origin.x, 2053)
        XCTAssertEqual(origin.y, 2113)
        XCTAssertGreaterThanOrEqual(origin.x, visibleFrame.minX + 32)
        XCTAssertLessThanOrEqual(
            origin.x + panelSize.width,
            visibleFrame.maxX - 32
        )
        XCTAssertLessThanOrEqual(
            origin.y + panelSize.height,
            visibleFrame.maxY - 32
        )
    }

    func testPanelPlacementClampsAnOffscreenWindow() {
        let visibleFrame = CGRect(x: 0, y: 72, width: 1728, height: 1007)
        let panelSize = CGSize(width: 300, height: 390)

        let origin = PanelPlacement.clampedOrigin(
            CGPoint(x: 1700, y: 1050),
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            margin: 32
        )

        XCTAssertEqual(origin.x, 1396)
        XCTAssertEqual(origin.y, 657)
    }

    private func hook(command: String, status: String) -> [String: Any] {
        [
            "enabled": true,
            "command": command,
            "trustStatus": status,
        ]
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
