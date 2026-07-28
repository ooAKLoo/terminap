import Foundation
import IOKit.pwr_mgt

public enum IdleSleepAssertionError: LocalizedError {
    case createFailed(IOReturn)

    public var errorDescription: String? {
        switch self {
        case let .createFailed(code):
            return "无法阻止 Mac 自动待机（IOKit 错误 \(code)）"
        }
    }
}

/// Holds a process-scoped assertion that prevents user-idle system sleep.
///
/// This intentionally does not prevent display sleep. macOS also removes the
/// assertion automatically if the TermiNap process exits unexpectedly.
public final class IdleSleepAssertionController {
    public private(set) var isPreventingIdleSleep = false

    private var assertionID: IOPMAssertionID =
        IOPMAssertionID(kIOPMNullAssertionID)
    private let acquireAssertion: () throws -> IOPMAssertionID
    private let releaseAssertion: (IOPMAssertionID) -> Void

    public convenience init(
        reason: String = "Terminal coding agents are still working"
    ) {
        self.init(
            acquireAssertion: {
                var assertionID =
                    IOPMAssertionID(kIOPMNullAssertionID)
                let result = IOPMAssertionCreateWithName(
                    kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    reason as CFString,
                    &assertionID
                )
                guard result == kIOReturnSuccess else {
                    throw IdleSleepAssertionError.createFailed(result)
                }
                return assertionID
            },
            releaseAssertion: { assertionID in
                IOPMAssertionRelease(assertionID)
            }
        )
    }

    init(
        acquireAssertion: @escaping () throws -> IOPMAssertionID,
        releaseAssertion: @escaping (IOPMAssertionID) -> Void
    ) {
        self.acquireAssertion = acquireAssertion
        self.releaseAssertion = releaseAssertion
    }

    public func setPreventingIdleSleep(_ shouldPrevent: Bool) throws {
        guard shouldPrevent != isPreventingIdleSleep else {
            return
        }

        if shouldPrevent {
            assertionID = try acquireAssertion()
            isPreventingIdleSleep = true
        } else {
            release()
        }
    }

    public func release() {
        guard isPreventingIdleSleep else {
            return
        }

        let heldAssertionID = assertionID
        assertionID = IOPMAssertionID(kIOPMNullAssertionID)
        isPreventingIdleSleep = false
        releaseAssertion(heldAssertionID)
    }

    deinit {
        release()
    }
}

public enum WakeGuardPolicy {
    public static func shouldPreventIdleSleep(
        busyCount: Int,
        automationEnabled: Bool,
        countdownActive: Bool
    ) -> Bool {
        automationEnabled && (busyCount > 0 || countdownActive)
    }
}
