# TermiNap

**终端 Agent 做完，Mac 再小睡。**

TermiNap 是一个原生 macOS 菜单栏工具。它把每个活跃的终端 Codex 任务显示为一格电量，并在最后一个任务完成后自动熄屏、系统待机或关机。

[English](README.md) · [营销执行方案](MARKETING_PLAN.md) · [Product Hunt 发布材料](PRODUCT_HUNT.md)

> 当前处于早期 Alpha：TermiNap 已能识别终端 Codex 任务并在全部完成后执行电源动作。“任务运行时阻止系统空闲睡眠”是下一版本的发布门槛，目前尚未实现。

## 为什么需要 TermiNap

长时间运行终端 Agent 时，Mac 进入系统睡眠可能中断任务；普通防睡眠工具又不知道最后一个 Agent 何时完成。

TermiNap 按 Agent 生命周期工作：

- 一个活跃终端任务对应一格电量。
- 多个 Codex 终端统一计数。
- 最后一个任务完成后启动可取消倒计时。
- 倒计时中出现新任务会取消本次电源动作。
- 活动状态和设置只保存在本机。

## 当前能力

- 通过生命周期 hooks 跟踪终端 Codex。
- 忽略没有 TTY 的 Codex/ChatGPT 桌面会话。
- 最多显示八个任务，超出后显示 `+N`。
- 支持显示器熄灭、系统待机和关机。
- 开启关机前必须二次确认。
- 合并用户级 hooks，不会删除其他工具的配置。
- 首次启动显示 `0/3` 至 `3/3` 的 hooks 信任进度。
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

首次启动时，TermiNap 会向 `~/.codex/hooks.json` 合并三个处理器，并保留其中已有的其他 hooks。若配置文件已经存在，会创建 `~/.codex/hooks.json.before-terminap`。

Codex 强制要求用户本人批准新的 hook 定义：

1. 在 TermiNap 中点击“新开引导 Codex”。
2. 粘贴 TermiNap 已复制到剪贴板的 `/hooks`。
3. 检查并信任三个 TermiNap hooks。

TermiNap 通过 Codex app-server 自动复检；三项全部通过后切换到电量界面。它不会修改 Codex 私有信任状态，也不会使用绕过信任的危险参数。

## 隐私与安全

- 不需要账号。
- 不收集提示词、源代码、项目内容或终端输出。
- 状态保存在 `~/Library/Application Support/TermiNap/`。
- 电源自动化默认关闭。
- 关机需要二次确认和可取消倒计时。

开发时可以设置 `TERMINAP_DRY_RUN=1`。电源动作只会写入 `dry-run.log`，不会真实执行。

## 公开发布前的路线图

- 仅在至少一个 Agent 工作时持有 macOS 空闲睡眠断言。
- 阻止系统睡眠时仍允许显示器正常熄灭。
- App 退出、崩溃或会话过期后释放断言。
- 增加仅接通电源启用和低电量保护。
- 增加登录时启动和完成通知。
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
