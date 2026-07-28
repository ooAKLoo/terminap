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

struct BatteryView: View {
    @ObservedObject var model: AppModel
    @State private var confirmingShutdown = false

    var body: some View {
        VStack(spacing: 16) {
            header
            if model.shouldShowHookSetup {
                hookSetup
            } else {
                dashboard
            }
        }
        .padding(18)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Palette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Palette.border, lineWidth: 1)
        )
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
        if model.shouldShowHookSetup {
            return Palette.warning
        }
        return model.busyCount > 0 ? Palette.accent : Palette.secondary
    }

    private var dashboard: some View {
        VStack(spacing: 16) {
            BatteryMeter(activeCount: model.busyCount)

            VStack(spacing: 4) {
                Text(model.statusText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.primary)
                Text(detailText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }

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
                    title: "信任 3 个 TermiNap hooks",
                    detail: "\(model.trustedHookCount)/3 已确认",
                    complete: model.trustedHookCount == 3
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
            return "3 个 hooks 均已信任。"
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
        if model.busyCount == 0 {
            return model.settings.enabled ? "等待下一批任务" : "自动动作目前关闭"
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
        Button(action: model.toggleAutomation) {
            HStack(spacing: 9) {
                Image(systemName: model.settings.enabled ? "power.circle.fill" : "power.circle")
                    .font(.system(size: 16, weight: .semibold))
                Text(model.settings.enabled ? "完成后自动\(model.settings.action.title)" : "打开完成后自动动作")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Text(model.settings.enabled ? "ON" : "OFF")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(0.7)
            }
            .foregroundStyle(model.settings.enabled ? Color.black.opacity(0.82) : Palette.primary)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(model.settings.enabled ? Palette.accent : Palette.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(model.settings.enabled ? Color.clear : Palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.settings.enabled ? "关闭自动动作" : "打开自动动作")
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
            .frame(width: 238, height: 68)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(activeCount) 个 Codex 任务正在进行")
    }
}
