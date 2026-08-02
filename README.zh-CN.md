# TermiNap

**终端 Agent 做完，Mac 再小睡。**

TermiNap 是一个原生 macOS 菜单栏工具。它把每个活跃的终端 Codex 任务显示为一格电量，并在最后一个任务完成后自动熄屏、系统待机或关机。

[English](README.md) · [产品状态与电源逻辑](docs/PRODUCT_STATE_LOGIC.md) · [营销执行方案](MARKETING_PLAN.md) · [Product Hunt 发布材料](PRODUCT_HUNT.md)

> 当前为开发预览版：从 Agent 工作到 Mac 自动待机的核心闭环已经实现。公开二进制版本仍需补齐低电量保护、Developer ID 正式签名和 Apple 公证。

## 为什么需要 TermiNap

长时间运行终端 Agent 时，Mac 进入系统睡眠可能中断任务；普通防睡眠工具又不知道最后一个 Agent 何时完成。

TermiNap 按 Agent 生命周期工作：

- 一个活跃终端任务对应一格电量。
- 多个 Codex 终端统一计数。
- 至少一个任务活跃时，Mac 保持唤醒，显示器仍可按系统设置正常熄灭。
- Codex 等待 Permission 时按“暂停推进”处理，不再计入活跃任务。
- 最后一个任务完成后启动可取消倒计时。
- 倒计时中出现新任务会取消本次电源动作。
- 活动状态和设置只保存在本机。

## 当前能力

- 通过五个生命周期 hooks 跟踪终端 Codex 的运行、等待授权、恢复和结束。
- App 启动时会补扫已经打开的终端 Codex，并恢复其中尚未完成的 Turn。
- 忽略没有 TTY 的 Codex/ChatGPT 桌面会话。
- 最多显示八个任务，超出后显示 `+N`。
- Agent 工作时使用进程级 macOS 断言，只阻止用户空闲导致的系统睡眠。
- 完成倒计时期间继续保持唤醒，倒计时归零后先释放断言，再执行电源动作。
- 关闭守护、状态读取失败、会话过期、App 退出或进程终止时释放断言。
- 支持显示器熄灭、系统待机和关机。
- 开启关机前必须二次确认。
- 合并用户级 hooks，不会删除其他工具的配置。
- 首次启动显示 `0/5` 至 `5/5` 的 hooks 信任进度。
- 在多显示器环境中确保悬浮窗口不会越界。

## 环境要求

- macOS 13 或更高版本
- Apple Silicon
- Codex CLI，或 ChatGPT/Codex macOS App 内置的 Codex 可执行程序
- 从源码构建时需要 Swift 5.9 或更高版本

## 构建与安装

```bash
swift test
./scripts/build-app.sh
./scripts/install-app.sh
open ~/Applications/TermiNap.app
```

构建产物为 `.build/TermiNap.app`，安装脚本会复制到 `~/Applications/TermiNap.app`。

当前构建仅使用适合本地开发的临时签名。公开二进制版本必须完成 Developer ID 正式签名和 Apple 公证。

## 信任 Codex hooks

首次启动时，TermiNap 会向 `~/.codex/hooks.json` 合并五个处理器，并保留其中已有的其他 hooks。若配置文件已经存在，会创建 `~/.codex/hooks.json.before-terminap`。

Codex 强制要求用户本人批准新的 hook 定义：

1. 在 TermiNap 中点击“新开引导 Codex”。
2. 粘贴 TermiNap 已复制到剪贴板的 `/hooks`。
3. 检查并信任五个 TermiNap hooks。

TermiNap 通过 Codex app-server 自动复检；五项全部通过后切换到电量界面。它不会修改 Codex 私有信任状态，也不会使用绕过信任的危险参数。

## 隐私与安全

- 不需要账号。
- 不收集提示词、源代码、项目内容或终端输出。
- 补扫已有会话时，只读取 TTY Codex 当前持有的 rollout 中的会话 ID、工作目录、PID 和生命周期事件字段。
- 状态保存在 `~/Library/Application Support/TermiNap/`。
- 电源自动化默认关闭。
- 夜班守护使用 `PreventUserIdleSystemSleep`，不会持有阻止显示器熄灭的断言。
- 断言属于 TermiNap 进程；即使 App 崩溃或被强制结束，macOS 也会自动清理。
- 关机需要二次确认和可取消倒计时。

开发时可以设置 `TERMINAP_DRY_RUN=1`。电源动作只会写入 `dry-run.log`，不会真实执行。

## 公开发布前的路线图

- 增加仅接通电源启用和低电量保护。
- 增加登录时启动和完成通知。
- 增加 Permission 等待时的飞书等即时通讯提醒。
- 发布 Developer ID 签名并通过 Apple 公证的 DMG。

在实现权限范围明确、可审计且能可靠恢复的辅助程序前，不支持也不宣传合盖运行。

## 参与贡献

欢迎提交 Issue 和 Pull Request。提交前请运行：

```bash
swift test
```

不要把路线图中的未完成功能宣传为现有能力。

## 许可证

MIT，参见 [LICENSE](LICENSE)。

TermiNap 是独立开源项目，与 OpenAI 不存在隶属、认可或赞助关系。
