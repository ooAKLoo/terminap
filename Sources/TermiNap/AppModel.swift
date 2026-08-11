import AppKit
import TermiNapCore
import Foundation

enum HookSetupState: Equatable {
    case checking
    case needsTrust(CodexHookTrustReport)
    case ready
    case unavailable(String)
    case installFailed(String)
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var tasks: [CodexTask] = []
    @Published private(set) var waitingForPermissionTasks: [CodexTask] = []
    @Published private(set) var settings: BatterySettings
    @Published private(set) var countdown: Int?
    @Published private(set) var hookSetupState: HookSetupState = .checking
    @Published private(set) var isCheckingHookTrust = false
    @Published private(set) var copiedHooksCommand = false
    @Published private(set) var lastError: String?
    @Published private(set) var isPreventingIdleSleep = false

    private let activityStore: ActivityStore
    private let settingsStore: SettingsStore
    private let staleTaskPruner: HookProcessor
    private let sessionReconciler: CodexSessionReconciler
    private let idleSleepAssertionController: IdleSleepAssertionController
    private let hookTrustChecker = CodexHookTrustChecker()
    private var decisionEngine = IdleDecisionEngine()
    private var pollTimer: Timer?
    private var countdownTimer: Timer?
    private var trustPollTimer: Timer?
    private var trustPollDeadline: Date?
    private var countdownDeadline: Date?
    private var appExecutablePath: String?
    private var codexExecutableURL: URL?
    private var pollCount = 0
    private var isReconcilingSessions = false

    init(
        activityStore: ActivityStore = ActivityStore(),
        settingsStore: SettingsStore = SettingsStore(),
        idleSleepAssertionController: IdleSleepAssertionController =
            IdleSleepAssertionController()
    ) {
        self.activityStore = activityStore
        self.settingsStore = settingsStore
        self.idleSleepAssertionController = idleSleepAssertionController
        staleTaskPruner = HookProcessor(store: activityStore)
        sessionReconciler = CodexSessionReconciler(store: activityStore)
        settings = (try? settingsStore.read()) ?? BatterySettings()
        refresh()
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    deinit {
        pollTimer?.invalidate()
        countdownTimer?.invalidate()
        trustPollTimer?.invalidate()
        idleSleepAssertionController.release()
    }

    var busyCount: Int {
        tasks.count
    }

    var waitingForPermissionCount: Int {
        waitingForPermissionTasks.count
    }

    var trackedTaskCount: Int {
        busyCount + waitingForPermissionCount
    }

    var statusText: String {
        if busyCount == 0 {
            if waitingForPermissionCount > 0 {
                return "\(waitingForPermissionCount) 个 Codex 任务等待授权"
            }
            return "所有终端任务已空闲"
        }
        if waitingForPermissionCount > 0 {
            return "\(busyCount) 个进行中 · \(waitingForPermissionCount) 个等待授权"
        }
        return "\(busyCount) 个 Codex 任务进行中"
    }

    var countdownText: String? {
        guard let countdown else {
            return nil
        }
        if countdown >= 60 {
            let minutes = countdown / 60
            let seconds = countdown % 60
            let duration = seconds == 0
                ? "\(minutes) 分钟"
                : "\(minutes) 分 \(seconds) 秒"
            return "\(duration)后\(settings.action.title)"
        }
        return "\(countdown) 秒后\(settings.action.title)"
    }

    var shouldShowHookSetup: Bool {
        hookSetupState != .ready
    }

    var trustedHookCount: Int {
        if case let .needsTrust(report) = hookSetupState {
            return report.trustedCount
        }
        return hookSetupState == .ready
            ? CodexHookTrustReport.requiredKinds.count
            : 0
    }

    var hookStatus: String {
        switch hookSetupState {
        case .checking:
            return "正在检查监控信任状态…"
        case let .needsTrust(report):
            if report.modifiedCount > 0 {
                return "监控配置有变化 · 需重新信任"
            }
            return "监控已安装 · \(report.trustedCount)/\(requiredHookCount) 已信任"
        case .ready:
            return "监控已安装 · \(requiredHookCount)/\(requiredHookCount) 已信任"
        case .unavailable:
            return "监控已安装 · 暂时无法自动检测"
        case .installFailed:
            return "监控安装失败"
        }
    }

    var requiredHookCount: Int {
        CodexHookTrustReport.requiredKinds.count
    }

    func setHookInstalled(_ installed: Bool, error: Error? = nil) {
        if installed {
            hookSetupState = .ready
        } else {
            hookSetupState = .installFailed(
                error?.localizedDescription ?? "无法写入 ~/.codex/hooks.json"
            )
        }
        if let error {
            lastError = error.localizedDescription
        }
    }

    func setHookTrustForPreview(trustedCount: Int) {
        var statuses: [String: CodexHookTrustStatus] = [:]
        for (index, kind) in CodexHookTrustReport.requiredKinds.enumerated() {
            statuses[kind] = index < trustedCount ? .trusted : .untrusted
        }
        hookSetupState = .needsTrust(
            CodexHookTrustReport(statuses: statuses)
        )
    }

    func hookInstallationDidFinish(executablePath: String) {
        appExecutablePath = executablePath
        codexExecutableURL = CodexExecutableLocator.locate()
        hookSetupState = .checking
        startTrustPolling()
        checkHookTrust()
    }

    func hookInstallationDidFail(_ error: Error) {
        hookSetupState = .installFailed(error.localizedDescription)
        lastError = error.localizedDescription
    }

    func checkHookTrust() {
        guard !isCheckingHookTrust else {
            return
        }
        guard
            let appExecutablePath,
            let codexExecutableURL
        else {
            hookSetupState = .unavailable("未找到 Codex 命令行程序")
            return
        }

        isCheckingHookTrust = true
        let checker = hookTrustChecker
        let cwd = FileManager.default.homeDirectoryForCurrentUser.path
        Task {
            let result = await Task.detached(priority: .utility) {
                Result {
                    try checker.check(
                        codexExecutableURL: codexExecutableURL,
                        appExecutablePath: appExecutablePath,
                        cwd: cwd
                    )
                }
            }.value

            isCheckingHookTrust = false
            switch result {
            case let .success(report):
                lastError = nil
                if report.isFullyTrusted {
                    hookSetupState = .ready
                    stopTrustPolling()
                } else {
                    hookSetupState = .needsTrust(report)
                }
            case let .failure(error):
                hookSetupState = .unavailable(error.localizedDescription)
            }
        }
    }

    func copyHooksCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("/hooks", forType: .string)
        copiedHooksCommand = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedHooksCommand = false
        }
    }

    func launchGuidedCodex() {
        copyHooksCommand()
        guard let codexExecutableURL else {
            NSWorkspace.shared.open(
                URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            )
            lastError = "未找到 Codex，可在已有 Codex 终端中粘贴 /hooks"
            return
        }

        do {
            let directory = TermiNapPaths.applicationSupportDirectory()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let launcherURL = directory.appendingPathComponent(
                "信任 TermiNap.command"
            )
            let quotedCodex = shellQuote(codexExecutableURL.path)
            let script = """
            #!/bin/zsh
            clear
            echo "TermiNap 已把 /hooks 复制到剪贴板。"
            echo "Codex 启动后，请按 Command-V 粘贴并回车，然后信任 \(requiredHookCount) 个 TermiNap hooks。"
            echo
            exec \(quotedCodex)
            """
            try Data(script.utf8).write(to: launcherURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: launcherURL.path
            )
            NSWorkspace.shared.open(launcherURL)
            startTrustPolling()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func toggleAutomation() {
        var next = settings
        next.enabled.toggle()
        guard persist(next) else {
            return
        }
        if !settings.enabled {
            clearCountdownState()
        }
        synchronizeWakeGuard()
    }

    func setAction(_ action: PowerAction) {
        var next = settings
        next.action = action
        guard persist(next) else {
            return
        }
        if countdown != nil {
            armCountdown()
        }
    }

    func cancelCountdown() {
        clearCountdownState()
        synchronizeWakeGuard()
    }

    private func clearCountdownState() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownDeadline = nil
        countdown = nil
    }

    @discardableResult
    private func persist(_ next: BatterySettings) -> Bool {
        do {
            try settingsStore.write(next)
            settings = next
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func startTrustPolling() {
        trustPollDeadline = Date().addingTimeInterval(180)
        if trustPollTimer == nil {
            trustPollTimer = Timer.scheduledTimer(
                withTimeInterval: 5,
                repeats: true
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else {
                        return
                    }
                    guard
                        self.hookSetupState != .ready,
                        self.trustPollDeadline.map({ $0 > Date() }) == true
                    else {
                        self.stopTrustPolling()
                        return
                    }
                    self.checkHookTrust()
                }
            }
        }
    }

    private func stopTrustPolling() {
        trustPollTimer?.invalidate()
        trustPollTimer = nil
        trustPollDeadline = nil
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func refresh() {
        do {
            pollCount += 1
            if pollCount == 1 || pollCount.isMultiple(of: 10) {
                try staleTaskPruner.pruneStaleTasks()
            }
            if pollCount == 1 || pollCount.isMultiple(of: 10) {
                reconcileExistingSessions()
            }
            let state = try activityStore.read()
            tasks = state.busy.values.sorted { $0.startedAt < $1.startedAt }
            waitingForPermissionTasks = state.waitingForPermission.values.sorted {
                $0.startedAt < $1.startedAt
            }
            let decision = decisionEngine.observe(
                trackedTaskCount: trackedTaskCount,
                automationEnabled: settings.enabled
            )
            switch decision {
            case .none:
                break
            case .cancel:
                clearCountdownState()
            case .arm:
                armCountdown()
            }
            if synchronizeWakeGuard() {
                lastError = nil
            }
        } catch {
            releaseWakeGuard()
            lastError = error.localizedDescription
        }
    }

    private func reconcileExistingSessions() {
        guard !isReconcilingSessions else {
            return
        }
        isReconcilingSessions = true
        let reconciler = sessionReconciler
        Task {
            _ = await Task.detached(priority: .utility) {
                try? reconciler.reconcile()
            }.value
            isReconcilingSessions = false
        }
    }

    private func armCountdown() {
        clearCountdownState()
        guard settings.enabled, trackedTaskCount == 0 else {
            synchronizeWakeGuard()
            return
        }

        countdownDeadline = Date().addingTimeInterval(
            TimeInterval(settings.delaySeconds)
        )
        updateCountdown()
        guard countdownDeadline != nil else {
            return
        }
        countdownTimer = Timer.scheduledTimer(
            withTimeInterval: 0.25,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateCountdown()
            }
        }
        synchronizeWakeGuard()
    }

    private func updateCountdown() {
        guard let deadline = countdownDeadline else {
            clearCountdownState()
            synchronizeWakeGuard()
            return
        }
        let remaining = max(Int(ceil(deadline.timeIntervalSinceNow)), 0)
        countdown = remaining

        guard remaining == 0 else {
            return
        }

        do {
            let latestState = try activityStore.read()
            guard latestState.tracked.isEmpty else {
                clearCountdownState()
                refresh()
                return
            }
        } catch {
            clearCountdownState()
            releaseWakeGuard()
            lastError = error.localizedDescription
            return
        }

        clearCountdownState()
        synchronizeWakeGuard()
        guard settings.enabled, trackedTaskCount == 0 else {
            return
        }

        // Completion actions are deliberately one-shot. Persist the disabled
        // state before asking macOS to sleep or shut down because this process
        // may be suspended or terminated as soon as the action is launched.
        let action = settings.action
        var next = settings
        next.enabled = false
        guard persist(next) else {
            return
        }

        do {
            try PowerController.execute(action)
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    private func synchronizeWakeGuard() -> Bool {
        let shouldPrevent = WakeGuardPolicy.shouldPreventIdleSleep(
            trackedTaskCount: trackedTaskCount,
            automationEnabled: settings.enabled,
            countdownActive: countdown != nil
        )

        do {
            try idleSleepAssertionController.setPreventingIdleSleep(
                shouldPrevent
            )
            isPreventingIdleSleep =
                idleSleepAssertionController.isPreventingIdleSleep
            return true
        } catch {
            releaseWakeGuard()
            lastError = error.localizedDescription
            return false
        }
    }

    private func releaseWakeGuard() {
        idleSleepAssertionController.release()
        isPreventingIdleSleep = false
    }
}
