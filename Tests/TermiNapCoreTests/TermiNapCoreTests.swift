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

    func testPermissionWaitStopsProgressUntilPostToolUseResumes() throws {
        let store = ActivityStore(baseDirectory: temporaryDirectory())
        let context = CodexProcessContext(pid: 1234, tty: "ttys001")
        let processor = HookProcessor(
            store: store,
            terminalContext: { context },
            processIsAlive: { _ in true }
        )
        let event = HookEvent(
            sessionID: "a",
            turnID: "turn-a",
            cwd: "/a"
        )

        try processor.handle(.start, event: event)
        try processor.handle(.permission, event: event)

        var state = try store.read()
        XCTAssertTrue(state.busy.isEmpty)
        XCTAssertEqual(
            state.waitingForPermission["a"]?.progress,
            .waitingForPermission
        )

        try processor.handle(.resume, event: event)

        state = try store.read()
        XCTAssertEqual(state.busy["a"]?.progress, .running)
        XCTAssertTrue(state.waitingForPermission.isEmpty)
    }

    func testStopRemovesTaskAlreadyWaitingForPermission() throws {
        let store = ActivityStore(baseDirectory: temporaryDirectory())
        let processor = HookProcessor(
            store: store,
            terminalContext: {
                CodexProcessContext(pid: 1234, tty: "ttys001")
            },
            processIsAlive: { _ in true }
        )
        let event = HookEvent(
            sessionID: "a",
            turnID: "turn-a",
            cwd: "/a"
        )

        try processor.handle(.start, event: event)
        try processor.handle(.permission, event: event)
        try processor.handle(.stop, event: event)

        XCTAssertTrue(try store.read().tracked.isEmpty)
    }

    func testLiveProcessIsNotExpiredByWallClockAge() throws {
        let store = ActivityStore(baseDirectory: temporaryDirectory())
        var now = Date(timeIntervalSince1970: 1_000)
        let processor = HookProcessor(
            store: store,
            now: { now },
            terminalContext: {
                CodexProcessContext(pid: 1234, tty: "ttys001")
            },
            processIsAlive: { _ in true },
            maximumBusyAge: 60
        )

        try processor.handle(
            .start,
            event: HookEvent(
                sessionID: "a",
                turnID: "turn-a",
                cwd: "/a"
            )
        )
        now = now.addingTimeInterval(61)
        try processor.pruneStaleTasks()

        XCTAssertNotNil(try store.read().busy["a"])
    }

    func testIdleDecisionOnlyArmsOnBusyToZeroTransition() {
        var engine = IdleDecisionEngine()
        XCTAssertEqual(engine.observe(busyCount: 0, automationEnabled: true), .none)
        XCTAssertEqual(engine.observe(busyCount: 2, automationEnabled: true), .cancel)
        XCTAssertEqual(engine.observe(busyCount: 1, automationEnabled: true), .cancel)
        XCTAssertEqual(engine.observe(busyCount: 0, automationEnabled: true), .arm)
        XCTAssertEqual(engine.observe(busyCount: 0, automationEnabled: true), .none)
    }

    func testWakeGuardPolicyCoversWorkAndCompletionCountdown() {
        XCTAssertTrue(
            WakeGuardPolicy.shouldPreventIdleSleep(
                busyCount: 2,
                automationEnabled: true,
                countdownActive: false
            )
        )
        XCTAssertTrue(
            WakeGuardPolicy.shouldPreventIdleSleep(
                busyCount: 0,
                automationEnabled: true,
                countdownActive: true
            )
        )
        XCTAssertFalse(
            WakeGuardPolicy.shouldPreventIdleSleep(
                busyCount: 2,
                automationEnabled: false,
                countdownActive: true
            )
        )
        XCTAssertFalse(
            WakeGuardPolicy.shouldPreventIdleSleep(
                busyCount: 0,
                automationEnabled: true,
                countdownActive: false
            )
        )
    }

    func testIdleSleepAssertionIsAcquiredAndReleasedIdempotently() throws {
        var acquiredCount = 0
        var releasedIDs: [UInt32] = []
        let controller = IdleSleepAssertionController(
            acquireAssertion: {
                acquiredCount += 1
                return 42
            },
            releaseAssertion: { releasedIDs.append($0) }
        )

        try controller.setPreventingIdleSleep(true)
        try controller.setPreventingIdleSleep(true)
        XCTAssertTrue(controller.isPreventingIdleSleep)
        XCTAssertEqual(acquiredCount, 1)

        try controller.setPreventingIdleSleep(false)
        try controller.setPreventingIdleSleep(false)
        XCTAssertFalse(controller.isPreventingIdleSleep)
        XCTAssertEqual(releasedIDs, [42])
    }

    func testIdleSleepAssertionIsReleasedWhenControllerDeinitializes() throws {
        var releasedIDs: [UInt32] = []
        var controller: IdleSleepAssertionController? =
            IdleSleepAssertionController(
                acquireAssertion: { 99 },
                releaseAssertion: { releasedIDs.append($0) }
            )

        try controller?.setPreventingIdleSleep(true)
        controller = nil

        XCTAssertEqual(releasedIDs, [99])
    }

    func testIdleSleepAssertionFailureDoesNotReportHeldState() {
        enum TestError: Error {
            case failed
        }
        let controller = IdleSleepAssertionController(
            acquireAssertion: { throw TestError.failed },
            releaseAssertion: { _ in
                XCTFail("A failed assertion must not be released")
            }
        )

        XCTAssertThrowsError(
            try controller.setPreventingIdleSleep(true)
        )
        XCTAssertFalse(controller.isPreventingIdleSleep)
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
                    ], [
                        "type": "command",
                        "command": "'/Applications/Old TermiNap.app/Contents/MacOS/TermiNap' --hook stop",
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
        XCTAssertFalse(commands.contains(where: { $0.contains("Old TermiNap.app") }))

        let expectedCommands = [
            "UserPromptSubmit": "--hook start",
            "PermissionRequest": "--hook permission",
            "PostToolUse": "--hook resume",
            "Stop": "--hook stop",
            "SessionEnd": "--hook end",
        ]
        for (eventName, commandSuffix) in expectedCommands {
            let groups = hooks[eventName] as! [[String: Any]]
            let eventCommands = groups.flatMap { group -> [String] in
                let handlers = group["hooks"] as? [[String: Any]] ?? []
                return handlers.compactMap { $0["command"] as? String }
            }
            XCTAssertTrue(
                eventCommands.contains(where: { $0.contains(commandSuffix) }),
                "\(eventName) should install \(commandSuffix)"
            )
        }
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

    func testReportsAllRequiredHooksAsReady() throws {
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
        XCTAssertEqual(
            report.trustedCount,
            CodexHookTrustReport.requiredKinds.count
        )
    }

    func testMigratesLegacyFifteenSecondCountdownToThirtySeconds() throws {
        let data = Data(
            #"{"enabled":true,"action":"systemSleep","delaySeconds":15}"#.utf8
        )

        let settings = try JSONDecoder().decode(BatterySettings.self, from: data)

        XCTAssertEqual(settings.delaySeconds, 30)
    }

    func testKeepsExplicitCurrentSchemaCountdown() throws {
        let data = Data(
            #"{"schemaVersion":2,"enabled":true,"action":"systemSleep","delaySeconds":15}"#.utf8
        )

        let settings = try JSONDecoder().decode(BatterySettings.self, from: data)

        XCTAssertEqual(settings.delaySeconds, 15)
    }

    func testLegacyTaskStateDefaultsToRunning() throws {
        let data = Data(
            #"{"sessionID":"a","turnID":"turn-a","cwd":"/a","startedAt":"1970-01-01T00:00:00Z","codexPID":1234}"#.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let task = try decoder.decode(CodexTask.self, from: data)

        XCTAssertEqual(task.progress, .running)
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

    func testPanelResizeKeepsItsTopEdgeFixed() {
        let frame = CGRect(x: 1396, y: 943, width: 300, height: 104)

        let expanded = PanelPlacement.resizedFrameKeepingTopEdge(
            frame,
            targetHeight: 360
        )
        let collapsed = PanelPlacement.resizedFrameKeepingTopEdge(
            expanded,
            targetHeight: 104
        )

        XCTAssertEqual(expanded, CGRect(x: 1396, y: 687, width: 300, height: 360))
        XCTAssertEqual(collapsed, frame)
        XCTAssertEqual(expanded.maxY, frame.maxY)
    }

    func testPanelResizeKeepsItsBottomEdgeFixed() {
        let frame = CGRect(x: 32, y: 32, width: 300, height: 104)

        let expanded = PanelPlacement.resizedFrame(
            frame,
            targetHeight: 330,
            keeping: .bottomEdge
        )
        let collapsed = PanelPlacement.resizedFrame(
            expanded,
            targetHeight: 104,
            keeping: .bottomEdge
        )

        XCTAssertEqual(expanded, CGRect(x: 32, y: 32, width: 300, height: 330))
        XCTAssertEqual(collapsed, frame)
        XCTAssertEqual(expanded.minY, frame.minY)
    }

    func testPanelNearBottomPrefersUpwardExpansion() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1728, height: 1080)
        let frame = CGRect(x: 32, y: 32, width: 300, height: 104)

        let anchor = PanelPlacement.preferredResizeAnchor(
            for: frame,
            targetHeight: 330,
            visibleFrame: visibleFrame,
            margin: 32
        )

        XCTAssertEqual(anchor, .bottomEdge)
    }

    func testPanelWithRoomBelowKeepsDownwardExpansion() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1728, height: 1080)
        let frame = CGRect(x: 32, y: 700, width: 300, height: 104)

        let anchor = PanelPlacement.preferredResizeAnchor(
            for: frame,
            targetHeight: 330,
            visibleFrame: visibleFrame,
            margin: 32
        )

        XCTAssertEqual(anchor, .topEdge)
    }

    func testPanelRelativePositionSurvivesDisplayGeometryChanges() {
        let panelSize = CGSize(width: 300, height: 104)
        let oldDisplay = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let newDisplay = CGRect(x: 0, y: 25, width: 2560, height: 1415)
        let expectedPosition = PanelRelativePosition(
            horizontal: 0.25,
            vertical: 0.75
        )
        let oldOrigin = PanelPlacement.origin(
            for: expectedPosition,
            panelSize: panelSize,
            visibleFrame: oldDisplay,
            margin: 32
        )

        let rememberedPosition = PanelPlacement.relativePosition(
            for: oldOrigin,
            panelSize: panelSize,
            visibleFrame: oldDisplay,
            margin: 32
        )
        let restoredOrigin = PanelPlacement.origin(
            for: rememberedPosition,
            panelSize: panelSize,
            visibleFrame: newDisplay,
            margin: 32
        )

        XCTAssertEqual(
            rememberedPosition.horizontal,
            expectedPosition.horizontal,
            accuracy: 0.001
        )
        XCTAssertEqual(
            rememberedPosition.vertical,
            expectedPosition.vertical,
            accuracy: 0.001
        )
        XCTAssertEqual(restoredOrigin.x, 581, accuracy: 0.001)
        XCTAssertEqual(restoredOrigin.y, 992.25, accuracy: 0.001)
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
