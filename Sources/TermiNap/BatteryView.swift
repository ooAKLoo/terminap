import TermiNapCore
import SwiftUI

private enum Palette {
    static let panel = Color(red: 0.075, green: 0.086, blue: 0.078)
    static let raised = Color(red: 0.11, green: 0.125, blue: 0.113)
    static let border = Color.white.opacity(0.12)
    static let primary = Color(red: 0.91, green: 0.94, blue: 0.91)
    static let secondary = Color(red: 0.62, green: 0.67, blue: 0.63)
    static let accent = Color(red: 0.60, green: 0.94, blue: 0.42)
    static let warning = Color(red: 1.00, green: 0.76, blue: 0.32)
}

private enum PanelLayout {
    static let padding: CGFloat = 18
    static let contentSpacing: CGFloat = 16
    static let batteryHeight: CGFloat = 68
    static let batteryContentInset =
        padding + batteryHeight + contentSpacing
}

@MainActor
final class PanelPresentationState: ObservableObject {
    @Published private(set) var isContentExpanded: Bool
    @Published private(set) var isPanelExpanded: Bool
    @Published private(set) var resizeAnchor: PanelResizeAnchor

    private var pointerIsInside = false
    private var interactionIsLocked = false
    private var pendingCollapse: Task<Void, Never>?

    init(
        initiallyExpanded: Bool = false,
        resizeAnchor: PanelResizeAnchor = .topEdge
    ) {
        isContentExpanded = initiallyExpanded
        isPanelExpanded = initiallyExpanded
        self.resizeAnchor = resizeAnchor
    }

    func setPointerInside(_ isInside: Bool) {
        pointerIsInside = isInside
        if isInside {
            expand()
        } else {
            scheduleCollapse()
        }
    }

    func setInteractionLocked(_ isLocked: Bool) {
        interactionIsLocked = isLocked
        if isLocked {
            pendingCollapse?.cancel()
            pendingCollapse = nil
            expand()
        } else if !pointerIsInside {
            scheduleCollapse()
        }
    }

    func panelAnimationDidComplete() {
        if !isPanelExpanded {
            isContentExpanded = false
        }
    }

    func setResizeAnchor(_ resizeAnchor: PanelResizeAnchor) {
        self.resizeAnchor = resizeAnchor
    }

    private func expand() {
        pendingCollapse?.cancel()
        pendingCollapse = nil

        isContentExpanded = true
        isPanelExpanded = true
    }

    private func scheduleCollapse() {
        guard !interactionIsLocked else {
            return
        }
        pendingCollapse?.cancel()
        pendingCollapse = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard
                !Task.isCancelled,
                !pointerIsInside,
                !interactionIsLocked
            else {
                return
            }
            collapse()
        }
    }

    private func collapse() {
        guard isPanelExpanded else {
            return
        }
        isPanelExpanded = false
    }
}

struct BatteryView: View {
    static let panelWidth: CGFloat = 300
    static let collapsedHeight: CGFloat = 104
    static let dashboardExpandedHeight: CGFloat = 330
    static let recoveryExpandedHeight: CGFloat = 456
    static let setupExpandedHeight: CGFloat = 490

    @ObservedObject var model: AppModel
    @ObservedObject var presentation: PanelPresentationState
    @State private var confirmingShutdown = false

    private let onPreferredHeightChange: (CGFloat) -> Void
    private let onDragEnded: () -> Void

    init(
        model: AppModel,
        presentation: PanelPresentationState,
        onPreferredHeightChange: @escaping (CGFloat) -> Void = { _ in },
        onDragEnded: @escaping () -> Void = {}
    ) {
        self.model = model
        self.presentation = presentation
        self.onPreferredHeightChange = onPreferredHeightChange
        self.onDragEnded = onDragEnded
    }

    var body: some View {
        GeometryReader { geometry in
            let currentHeight = geometry.size.height
            let progress = morphProgress(
                currentHeight: currentHeight
            )
            let cornerRadius = 30 - (6 * progress)
            let detailProgress = normalizedProgress(
                progress,
                start: 0.10,
                end: 0.62
            )
            let footerProgress = normalizedProgress(
                progress,
                start: 0.56,
                end: 0.94
            )
            let shape = RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
            let expandsUpward =
                presentation.resizeAnchor == .bottomEdge

            ZStack(alignment: expandsUpward ? .bottom : .top) {
                shape.fill(Palette.panel)

                if presentation.isContentExpanded {
                    VStack(spacing: PanelLayout.contentSpacing) {
                        if expandsUpward {
                            header
                                .opacity(Double(footerProgress))
                                .offset(y: 4 * (1 - footerProgress))

                            Spacer(minLength: 0)

                            panelDetails
                                .opacity(Double(detailProgress))
                                .offset(y: 7 * (1 - detailProgress))
                        } else {
                            panelDetails
                                .opacity(Double(detailProgress))
                                .offset(y: 7 * (1 - detailProgress))

                            Spacer(minLength: 0)

                            header
                                .opacity(Double(footerProgress))
                                .offset(y: 4 * (1 - footerProgress))
                        }
                    }
                    .padding(.horizontal, PanelLayout.padding)
                    .padding(
                        expandsUpward ? .top : .bottom,
                        PanelLayout.padding
                    )
                    .padding(
                        expandsUpward ? .bottom : .top,
                        PanelLayout.batteryContentInset
                    )
                    .frame(
                        width: Self.panelWidth,
                        height: currentHeight
                    )
                }

                BatteryMeter(
                    activeCount: model.busyCount,
                    interruptedCount: model.interruptedTaskCount,
                    onDragEnded: onDragEnded
                )
                .padding(PanelLayout.padding)
                .frame(
                    width: Self.panelWidth,
                    height: currentHeight,
                    alignment: expandsUpward ? .bottom : .top
                )
            }
            .clipShape(shape)
            .overlay(
                shape.stroke(
                    Palette.border.opacity(0.78 + (0.22 * progress)),
                    lineWidth: 1
                )
            )
            .contentShape(shape)
        }
        .frame(width: Self.panelWidth)
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSMenu.didBeginTrackingNotification
            )
        ) { _ in
            presentation.setInteractionLocked(true)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSMenu.didEndTrackingNotification
            )
        ) { _ in
            presentation.setInteractionLocked(false)
        }
        .onChange(of: presentation.isPanelExpanded) { isExpanded in
            onPreferredHeightChange(
                isExpanded ? expandedHeight : Self.collapsedHeight
            )
        }
        .onChange(of: model.shouldShowHookSetup) { shouldShowSetup in
            guard presentation.isPanelExpanded else {
                return
            }
            onPreferredHeightChange(
                shouldShowSetup
                    ? Self.setupExpandedHeight
                    : expandedHeight
            )
        }
        .onChange(of: model.interruptedTaskCount) { _ in
            guard
                presentation.isPanelExpanded,
                !model.shouldShowHookSetup
            else {
                return
            }
            onPreferredHeightChange(expandedHeight)
        }
        .onChange(of: confirmingShutdown) { isConfirming in
            presentation.setInteractionLocked(isConfirming)
        }
        .alert("确认允许自动关机？", isPresented: $confirmingShutdown) {
            Button("取消", role: .cancel) {}
            Button("允许关机", role: .destructive) {
                model.setAction(.shutdown)
            }
        } message: {
            Text("所有终端 Codex 任务完成后，应用会在倒计时结束时关闭电脑。请先保存其他应用中的工作。")
        }
        .environment(\.colorScheme, .dark)
    }

    private var expandedHeight: CGFloat {
        if model.shouldShowHookSetup {
            return Self.setupExpandedHeight
        }
        if model.interruptedTaskCount > 0 {
            return Self.recoveryExpandedHeight
        }
        return Self.dashboardExpandedHeight
    }

    @ViewBuilder
    private var panelDetails: some View {
        if model.shouldShowHookSetup {
            hookSetup
        } else {
            dashboard
        }
    }

    private func morphProgress(currentHeight: CGFloat) -> CGFloat {
        let range = max(expandedHeight - Self.collapsedHeight, 1)
        return min(
            max(
                (currentHeight - Self.collapsedHeight) / range,
                0
            ),
            1
        )
    }

    private func normalizedProgress(
        _ progress: CGFloat,
        start: CGFloat,
        end: CGFloat
    ) -> CGFloat {
        min(max((progress - start) / max(end - start, 0.001), 0), 1)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(headerIndicatorColor)
                .frame(width: 7, height: 7)
                .shadow(
                    color: headerIndicatorColor.opacity(0.5),
                    radius: 5
                )
            Text("TermiNap")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Palette.primary)

            Spacer()

            Menu {
                Button("隐藏窗口") {
                    NSApp.hide(nil)
                }
                Divider()
                Button("退出 TermiNap") {
                    NSApp.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 28, height: 24)
                    .background(
                        Capsule().fill(Palette.raised)
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var headerIndicatorColor: Color {
        if model.shouldShowHookSetup || model.interruptedTaskCount > 0 {
            return Palette.warning
        }
        return model.busyCount > 0 ? Palette.accent : Palette.secondary
    }

    private var dashboard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(model.statusText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.primary)
                Text(detailText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }

            interruptionRecovery
            actionPicker
            automationButton

            if let countdownText = model.countdownText {
                Button(action: model.cancelCountdown) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.badge.xmark")
                        Text(countdownText)
                        Text("· 点击取消")
                            .foregroundStyle(Palette.secondary)
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.warning)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            } else {
                Text(model.hookStatus)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.secondary.opacity(0.82))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var interruptionRecovery: some View {
        if let task = model.interruptedTasks.first {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.warning)
                        .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(interruptedTaskLabel(task))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.primary)
                        Text("Codex 进程已退出 · 会话仍可恢复")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 4)

                    if model.interruptedTaskCount > 1 {
                        Text("+\(model.interruptedTaskCount - 1)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.warning)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        model.resumeInterruptedTask(task)
                    } label: {
                        HStack(spacing: 6) {
                            if model.isResuming(task) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Color.black.opacity(0.76))
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(
                                model.isResuming(task)
                                    ? "正在打开 Terminal…"
                                    : "恢复任务"
                            )
                        }
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.82))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Palette.accent)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isResuming(task))
                    .accessibilityLabel("恢复中断的 Codex 任务")

                    Button("结束跟踪") {
                        model.stopTrackingInterruptedTask(task)
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.secondary)
                    .buttonStyle(.plain)
                    .disabled(model.isResuming(task))
                    .accessibilityHint("不恢复该任务，并允许进入收尾倒计时")
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.warning.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Palette.warning.opacity(0.28), lineWidth: 1)
            )
        }
    }

    private func interruptedTaskLabel(_ task: CodexTask) -> String {
        guard let cwd = task.cwd, !cwd.isEmpty else {
            return "Codex 会话 \(task.sessionID.prefix(8))"
        }
        let project = URL(fileURLWithPath: cwd).lastPathComponent
        return project.isEmpty ? cwd : project
    }

    private var hookSetup: some View {
        VStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Palette.raised)
                    .frame(width: 68, height: 55)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(Palette.warning.opacity(0.35), lineWidth: 1)
                    )
                Image(systemName: setupSymbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Palette.warning)
            }

            VStack(spacing: 5) {
                Text(setupTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.primary)
                Text(setupDetail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 7) {
                SetupRow(
                    title: "监控已自动安装",
                    detail: "~/.codex/hooks.json",
                    complete: hooksWereInstalled
                )
                SetupRow(
                    title: "信任 \(model.requiredHookCount) 个 TermiNap hooks",
                    detail: "\(model.trustedHookCount)/\(model.requiredHookCount) 已确认",
                    complete: model.trustedHookCount == model.requiredHookCount
                )
            }

            Button(action: model.launchGuidedCodex) {
                HStack(spacing: 8) {
                    Image(systemName: "terminal.fill")
                    Text("新开引导 Codex")
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.82))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Palette.accent)
                )
            }
            .buttonStyle(.plain)
            .disabled(!hooksWereInstalled)
            .opacity(hooksWereInstalled ? 1 : 0.45)

            HStack(spacing: 8) {
                setupSecondaryButton(
                    title: model.copiedHooksCommand ? "已复制" : "复制 /hooks",
                    symbol: model.copiedHooksCommand ? "checkmark" : "doc.on.doc",
                    action: model.copyHooksCommand
                )
                setupSecondaryButton(
                    title: model.isCheckingHookTrust ? "检测中…" : "重新检测",
                    symbol: "arrow.clockwise",
                    action: model.checkHookTrust
                )
                .disabled(model.isCheckingHookTrust)
            }

            Text("出于安全要求，最后的“信任”必须由你在 Codex 中确认；App 不会代点或绕过。")
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.secondary.opacity(0.78))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hooksWereInstalled: Bool {
        if case .installFailed = model.hookSetupState {
            return false
        }
        return true
    }

    private var setupSymbol: String {
        switch model.hookSetupState {
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .installFailed, .unavailable:
            return "exclamationmark.shield.fill"
        case .needsTrust:
            return "checkmark.shield.fill"
        case .ready:
            return "checkmark.shield.fill"
        }
    }

    private var setupTitle: String {
        switch model.hookSetupState {
        case .checking:
            return "正在检查监控"
        case .needsTrust:
            return "最后一步：信任监控"
        case .ready:
            return "监控已就绪"
        case .unavailable:
            return "需要手动确认"
        case .installFailed:
            return "监控安装失败"
        }
    }

    private var setupDetail: String {
        switch model.hookSetupState {
        case .checking:
            return "正在读取 Codex 的 hooks 信任状态…"
        case let .needsTrust(report):
            if report.modifiedCount > 0 {
                return "监控命令发生过变化，请在新开的 Codex 中重新信任。"
            }
            return "点击下方按钮，新 Codex 启动后粘贴并运行 /hooks。"
        case .ready:
            return "\(model.requiredHookCount) 个 hooks 均已信任。"
        case let .unavailable(message):
            return "\(message)。仍可在 Codex 中运行 /hooks 完成确认。"
        case let .installFailed(message):
            return message
        }
    }

    private func setupSecondaryButton(
        title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var detailText: String {
        if model.isPreventingIdleSleep {
            if model.interruptedTaskCount > 0 {
                return "Mac 保持唤醒 · \(model.interruptedTaskCount) 个任务待恢复"
            }
            if model.busyCount == 0 {
                if model.waitingForPermissionCount > 0 {
                    return "等待授权中 · Mac 保持唤醒"
                }
                return "收尾倒计时中 · Mac 保持唤醒"
            }
            if model.waitingForPermissionCount > 0 {
                return "Mac 保持唤醒 · \(model.waitingForPermissionCount) 个等待授权"
            }
            return "Mac 保持唤醒 · 屏幕仍可自动熄灭"
        }
        if model.interruptedTaskCount > 0 {
            return "未执行收尾动作 · Mac 可正常休眠"
        }
        if model.busyCount == 0 {
            if model.waitingForPermissionCount > 0 {
                return "等待授权不计入活跃任务"
            }
            return model.settings.enabled
                ? "本次夜班守护已开启 · 等待任务"
                : "Agent 夜班守护目前关闭"
        }
        if model.busyCount > 8 {
            return "电量条显示前 8 个，另有 \(model.busyCount - 8) 个"
        }
        return "每个活跃终端占一格电量"
    }

    private var actionPicker: some View {
        HStack {
            Text("归零动作")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.secondary)
            Spacer()
            Menu {
                ForEach(PowerAction.allCases) { action in
                    Button {
                        if action == .shutdown {
                            confirmingShutdown = true
                        } else {
                            model.setAction(action)
                        }
                    } label: {
                        Label(action.title, systemImage: action.symbolName)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: model.settings.action.symbolName)
                    Text(model.settings.action.title)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.primary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    Capsule().fill(Palette.raised)
                )
                .overlay(
                    Capsule().stroke(Palette.border, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var automationButton: some View {
        let isPrimary = model.settings.enabled
            && model.interruptedTaskCount == 0
        return Button(action: model.toggleAutomation) {
            HStack(spacing: 9) {
                Image(systemName: model.settings.enabled ? "power.circle.fill" : "power.circle")
                    .font(.system(size: 16, weight: .semibold))
                Text(model.settings.enabled ? "本次夜班守护已开启" : "打开本次夜班守护")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Text(model.settings.enabled ? "ON" : "OFF")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(0.7)
            }
            .foregroundStyle(isPrimary ? Color.black.opacity(0.82) : Palette.primary)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isPrimary ? Palette.accent : Palette.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isPrimary ? Color.clear : Palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.settings.enabled ? "关闭本次夜班守护" : "打开本次夜班守护")
    }
}

private struct SetupRow: View {
    let title: String
    let detail: String
    let complete: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(complete ? Palette.accent : Palette.warning)
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.primary)
            Spacer()
            Text(detail)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.16))
        )
    }
}

private struct BatteryMeter: View {
    let activeCount: Int
    let interruptedCount: Int
    let onDragEnded: () -> Void
    private let segmentCount = 8

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<segmentCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(index < activeCount ? Palette.accent : Palette.raised)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(
                                    index < activeCount
                                        ? Palette.accent.opacity(0.2)
                                        : Palette.border,
                                    lineWidth: 1
                                )
                        )
                }
            }
            .padding(7)
            .frame(width: 238, height: PanelLayout.batteryHeight)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.black.opacity(0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Palette.primary.opacity(0.44), lineWidth: 2)
            )

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Palette.primary.opacity(0.44))
                .frame(width: 7, height: 25)
                .padding(.leading, 3)
        }
        .overlay(alignment: .center) {
            if activeCount > segmentCount {
                Text("+\(activeCount - segmentCount)")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Palette.warning))
            }
        }
        .overlay(alignment: .topTrailing) {
            if interruptedCount > 0 {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Color.black.opacity(0.78))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Palette.warning))
                    .padding(.trailing, 12)
                    .padding(.top, 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            interruptedCount > 0
                ? "\(activeCount) 个 Codex 任务正在进行，\(interruptedCount) 个任务等待恢复"
                : "\(activeCount) 个 Codex 任务正在进行"
        )
        .overlay {
            WindowDragHandle(onDragEnded: onDragEnded)
                .accessibilityHidden(true)
        }
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> DragHandleView {
        DragHandleView(onDragEnded: onDragEnded)
    }

    func updateNSView(_ nsView: DragHandleView, context: Context) {
        nsView.onDragEnded = onDragEnded
    }
}

private final class DragHandleView: NSView {
    private var lastMouseLocation: NSPoint?
    var onDragEnded: () -> Void

    init(onDragEnded: @escaping () -> Void) {
        self.onDragEnded = onDragEnded
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        lastMouseLocation = NSEvent.mouseLocation
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let lastMouseLocation else {
            return
        }
        let mouseLocation = NSEvent.mouseLocation
        let delta = NSPoint(
            x: mouseLocation.x - lastMouseLocation.x,
            y: mouseLocation.y - lastMouseLocation.y
        )
        let origin = window.frame.origin
        window.setFrameOrigin(
            NSPoint(
                x: origin.x + delta.x,
                y: origin.y + delta.y
            )
        )
        self.lastMouseLocation = mouseLocation
    }

    override func mouseUp(with event: NSEvent) {
        lastMouseLocation = nil
        window?.invalidateCursorRects(for: self)
        onDragEnded()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}
