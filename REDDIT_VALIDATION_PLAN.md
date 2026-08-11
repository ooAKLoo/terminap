# TermiNap Reddit 需求验证运营方案

本文用于验证 TermiNap 在 Reddit 用户中的真实需求结构，并指导首轮发帖、评论追问、Beta 邀请和结果判断。执行者应优先收集最近发生的真实行为，不以点赞数或泛泛的“愿意使用”作为产品证据。

- 文档类型：运营操作指南
- 适用阶段：公开下载前的需求验证与小范围 Beta 招募
- 目标社区：`r/codex`、`r/ClaudeCode`，产品成熟后再考虑 `r/macapps`
- 更新日期：2026-08-02
- 产品能力与营销边界：以 [`MARKETING_PLAN.md`](MARKETING_PLAN.md) 为准
- 状态定义：以 [`docs/PRODUCT_STATE_LOGIC.md`](docs/PRODUCT_STATE_LOGIC.md) 为准

## 明确本轮验证目标

本轮不再验证“是否有人睡前等待 Codex 或 Claude Code”。Reddit 已经出现过直接描述此行为的讨论。真正要验证的是：

> 当本地代码 Agent 在睡前仍然运行时，用户为什么不敢直接去睡？其中有多少问题是 TermiNap 当前或近期能够解决的？

用户不离开的原因决定了产品匹配程度：

| 用户不去睡的原因 | TermiNap 的匹配程度 |
| --- | --- |
| 担心 Mac 进入系统睡眠并中断任务 | 当前可以解决 |
| 使用 `caffeinate` 后担心电脑整夜不睡 | 当前可以解决 |
| 不知道最后一个任务什么时候完成 | 部分解决；需要完成通知 |
| Agent 停在 Permission，用户没有察觉 | 当前可以识别；需要远程提醒 |
| 想马上查看结果并安排下一轮任务 | 无法解决 |
| 忍不住继续迭代，“再改一点就睡” | 无法解决 |
| 任务运行在远程 VM 或云端 | 通常不是目标用户 |
| Codex 原生防睡眠已经完全满足需求 | 产品价值明显降低 |

发帖时必须准确区分显示器熄灭和系统睡眠：显示器熄灭通常不会中断终端任务，真正可能让本地任务停止的是 Mac 进入系统睡眠。

## 正视市场变化

### Codex 已经提供原生防睡眠能力

Codex 当前提供 **Prevent sleep while running** 设置，Codex CLI 也可以通过 `/experimental` 开启同名能力。因此，“Agent 工作时让 Mac 保持唤醒”不能继续作为唯一核心卖点。

首轮验证应重点判断：

- 多个终端任务是否需要统一监控；
- 最后一个任务完成后，用户是否希望 Mac 自动恢复睡眠；
- Permission 等待应算作“仍在工作”还是“已经停止推进”；
- 用户是否需要完成通知或远程授权提醒；
- 用户是否信任只读取生命周期状态、不读取代码和 Prompt 的工具。

### Agent 专用防睡眠产品已经出现

`r/ClaudeCode` 已经出现 Keepresso 等直接竞品，覆盖多 Agent、hooks、低电量保护和结束动作。这既证明需求不是凭空想象，也说明“Agent 工作时防睡眠”本身不足以形成差异。

TermiNap 需要验证的差异是：用户睡前无法放心离开的具体原因，是否集中在多任务生命周期、任务结束后的电源收尾、Permission 状态和远程提醒。

竞品、平台能力和社区规则会变化。正式发布前应重新核对本文末尾的来源，不把这里的描述当作长期不变的事实。

## 收集六类证据

### 1. 发生频率

不要问“Would you use this?”，而要问“上一次发生是什么时候？”并记录：

- 最近一个月发生过几次；
- 是偶发、每周发生，还是几乎每天发生；
- 单次任务通常运行多久；
- 是一个任务还是多个并行任务。

### 2. 用户为什么继续等待

至少区分以下原因：

- 电脑可能进入系统睡眠；
- Agent 可能停在 Permission；
- 不知道任务是否已经完成；
- 想立刻检查结果；
- 想继续发送下一条任务；
- 担心电脑在完成后仍整夜保持唤醒。

不要把所有回答都解释成电源管理问题。只有其中一部分是 TermiNap 能解决的。

### 3. 当前替代方案

记录用户是否使用：

- Codex 原生 Prevent sleep while running；
- `caffeinate`；
- Amphetamine、Caffeine 等通用工具；
- 永久关闭系统睡眠；
- 定时关机；
- 远程 VM、`tmux` 或云端 Agent；
- 什么都不用，留在电脑前等待。

发现替代方案后继续问：“这个方案哪里还不够好？”

### 4. 任务结束后的期望动作

不要默认用户希望关机。需要自然问出用户更偏好：

- 保持原样；
- 仅让显示器熄灭；
- 恢复正常系统睡眠；
- 立即进入待机；
- 自动关机；
- 完成后通知手机，再由用户决定。

### 5. Permission 的期望处理

TermiNap 当前将 Permission 等待视为“不再自主推进”，不计入活跃电量，但仍视为未结束任务并保持系统唤醒；只有任务真正结束后才会进入倒计时。这是产品定义，不代表用户一定认同。

必须直接验证：

> 如果所有 Agent 都停在 Permission，你希望 Mac 睡眠、继续等待，还是先通知手机？

如果 Permission 是多数用户不敢离开的主要原因，应将远程提醒提升为正式发布前的核心能力。

### 6. 对本地工具的信任

TermiNap 的现有隐私承诺是：

- 不读取 Prompt、代码、项目内容或终端输出；
- 只根据 Agent 生命周期 hooks 判断状态；
- 数据仅保存在本机。

记录用户是否追问：

- hooks 会修改什么；
- 是否需要管理员权限；
- 是否可能误关机；
- App 崩溃后是否会持续阻止睡眠；
- 自动关机是否有二次确认和可取消倒计时。

这些问题应进入后续落地页、安装引导和常见问题。

## 按社区顺序发布

### 第一站：`r/codex`

首发选择 `r/codex`。当前产品只准确支持本地终端 Codex，不应在首轮假装支持 Claude Code 或所有 Agent。

帖子应从睡前真实行为切入，承认 Codex 原生防睡眠和 `caffeinate` 等替代方案，不发布普通的“我做了一个防睡眠工具”推广帖。发布前再次检查社区规则和近期重复话题。

### 第二站：`r/ClaudeCode`

与首帖间隔 4～7 天，并根据 `r/codex` 的回答重写内容，不要 Crosspost 或直接复制。明确说明第一版目前只支持终端 Codex，本帖是在判断 Claude Code 是否值得成为下一个适配对象。

鉴于该社区已有直接竞品，第一轮只验证问题，不附产品链接。需要展示产品时，遵守当时有效的 Showcase 和自我推广规则，透明说明开发者身份、产品用途和支持范围。

### 第三站：`r/macapps`

不要把 `r/macapps` 用作第一轮需求验证。只有产品具备以下条件后才考虑发布：

- 可下载 Beta；
- Developer ID 签名与 Apple 公证；
- 清晰的隐私说明；
- 稳定退出和防误关机机制；
- 满足社区当时有效的 Karma 与自我推广频率要求。

## 发布第一篇 `r/codex` 验证帖

标题：

```text
Do you ever stay up later than you meant to because Codex is still running?
```

正文：

```text
This happened to me again last night.

I started a refactor right before bed, told myself I’d wait five minutes to make sure it was going okay, and was still at the desk 40 minutes later.

I’m curious how common this actually is. When a local Codex task is still running at bedtime, do you just leave it and go to sleep, or do you wait around?

For me, the annoying part isn’t the display going dark. It’s not knowing whether the Mac will actually go to sleep, whether Codex will stop at a permission prompt, or whether caffeinate will leave the machine awake for hours after the task is already done.

What did you do the last time this happened? Use Codex’s prevent-sleep setting, caffeinate, Amphetamine, a remote machine, a shutdown timer, or just wait for it?

I’m prototyping a very small Mac utility around this, but I’m not posting a link yet. I’m trying to figure out whether the real problem is power management, permission/finish notifications, or just the “one more prompt” loop.
```

第一篇帖子不带产品名、下载链接或设计效果图。它只讲一个具体经历，询问上一次真实行为，承认现有替代方案，并允许用户否定产品假设。

## 发布首条置顶评论

主帖保持生活化，在自己的第一条评论补充产品边界：

```text
A little more context on what I’m testing:

The prototype watches local terminal Codex lifecycle events. It lets the display turn off, prevents system idle sleep while any tracked task remains unfinished, and starts a five-minute cancelable countdown after the last task truly finishes.

It doesn’t read prompts, code, project contents, or terminal output. The first build is Codex-only.

The part I’m least sure about is permission waits. If every task is waiting for approval, should the Mac sleep, stay awake, or ping your phone and wait?
```

首轮不要在主帖或置顶评论中加入产品名、官网、GitHub、价格、下载地址或演示视频。

## 发布 `r/ClaudeCode` 改写帖

标题：

```text
Do you actually go to bed while Claude Code is still running?
```

正文：

```text
I keep doing the same stupid thing.

I start a long Claude Code task near midnight, tell myself I’ll only wait until it’s safely underway, and then end up babysitting it for another hour.

I’m curious what actually keeps people at the desk in this situation.

Is it because the Mac might sleep? Because Claude might stop for permission? Because you want to check the result immediately? Or because one finished task always turns into “I may as well start the next one”?

What did you do the last time this happened?

I have a small Codex-only Mac prototype at the moment, so this isn’t a Claude Code product post. I’m trying to understand whether the same bedtime workflow is common enough to make Claude Code support worth building next.
```

该版本不介绍未实现的 Claude Code 功能，只收集行为证据。

## 在评论区每次只追问一个问题

不要复制统一客服话术。根据回答追问最能改变产品判断的一件事。

| 用户回答 | 推荐回复 | 要验证的判断 |
| --- | --- | --- |
| “Just use caffeinate” | `Yep, that’s what I use now too. Do you ever forget to stop it after the task finishes, or does it basically solve the problem for you?` | `caffeinate` 是完整解法还是只解决一半 |
| “Codex already has Prevent sleep while running” | `Good point. Does that fully solve it for you, including what the Mac does after the last task finishes?` | 原生能力是否已经完全满足 |
| “我在远程服务器上跑” | `That probably removes the Mac power problem entirely. Do you still wait around because you want to review or steer the task, or do you genuinely just leave it overnight?` | 是否属于目标用户 |
| “主要怕 Permission” | `This is the case I’m most interested in. Would a phone notification be enough, or would you want the Mac to stay awake until you respond?` | 远程提醒的优先级与唤醒策略 |
| “我想看结果，然后再发一轮” | `Honestly, that may be the real problem. A power utility probably wouldn’t fix that loop.` | 痛点是否无法由电源工具解决 |
| 提到 Keepresso、Amphetamine 或类似工具 | `Yep, that’s a very relevant comparison. I’m trying to work out whether people want a smaller agent-lifecycle and permission-focused tool, or whether a broader keep-awake app already covers the job.` | 小型生命周期工具是否还有差异价值 |

如果用户描述了完整真实经历，先问：

```text
How often has that happened in the last month?
```

确认其属于目标用户后再问：

```text
Would you be open to trying a rough beta for one night and telling me where it fails?
```

只有对方明确同意后再私信，不主动群发消息。

## 邀请用户测试一晚 Beta

```text
Thanks for the detailed reply on the Codex bedtime thread.

I’m building a tiny local Mac beta for the case you described. It tracks terminal Codex lifecycle events, keeps the system awake only while work is progressing, and starts a cancelable countdown after the final task stops.

It doesn’t read prompts, code, or terminal output. The current build is still rough and Codex-only.

Would you be willing to use it for one real evening and tell me where it gets the state wrong? I’m more interested in failures than polite feedback.
```

邀请目标是获得一次真实夜间使用和错误状态反馈，不是把用户导入泛化等待名单。

## 用统一表格记录反馈

每条包含真实经历或明确反对意见的评论都记录到同一张表中：

| 字段 | 记录口径 |
| --- | --- |
| 来源 | `r/codex` 或 `r/ClaudeCode` |
| Agent | Codex CLI、Codex App 或 Claude Code |
| 运行位置 | 本机 Mac、远程机器或云端 |
| 最近一次发生 | 用户描述的具体任务和时间 |
| 发生频率 | 从未、每月一次、每月两次以上、每周或几乎每天 |
| 为什么继续等 | 睡眠、Permission、看结果、下一轮 Prompt 或状态不确定 |
| 当前方案 | 原生设置、`caffeinate`、Amphetamine、远程主机或手工等待 |
| 当前方案问题 | 任务中断、整夜不睡、无通知或无法识别 Permission |
| 希望的结束动作 | 通知、熄屏、待机、关机或保持唤醒 |
| 是否愿意测试 | 是或否 |
| 产品匹配 | 当前能解决、需要通知或非目标用户 |
| 可引用原话 | 一句最有价值的用户表达；公开使用前取得授权 |

不要只记录支持产品的评论。原生功能已满足、远程环境没有电源问题、行为循环无法解决等反对意见，都是范围判断的重要证据。

## 按证据判断第一轮结果

### 继续推进的工作阈值

两篇帖子合计达到以下条件时，可以继续推进当前方向：

- 获得 15～20 条包含真实经历的回复；
- 至少 8 位是本机 Mac Agent 用户；
- 至少 5 位每月发生两次以上；
- 至少 5 位正在使用手工或全局防睡眠方案；
- 至少 3 位愿意实际安装 Beta；
- 至少三分之一提到任务结束后仍保持唤醒、Permission 或不知道最后一个任务是否完成。

这些数值是内部工作阈值，不是统计显著性结论。

### 根据回答调整产品重点

| 主要反馈 | 产品判断 | 后续动作 |
| --- | --- | --- |
| Codex 原生防睡眠已经够用 | 单纯防睡眠不再适合作为独立核心卖点 | 强化多任务状态、结束动作、完成通知、Permission 提醒和任务历史 |
| Permission 是不敢离开的主因 | 远程提醒可能是发布前核心能力 | 将 Permission 到来通知和可取消等待策略提升到 P0 评估 |
| 用户主要想立即看结果并继续下一轮 | 睡眠延迟主要是行为循环 | 保持产品轻量，不高估市场空间 |
| 多数用户运行在远程 VM 或云端 | 本机 Mac 电源伴侣是较窄市场 | 重新评估独立商业化价值和目标人群 |

## 只在有证据后发布第二轮产品帖

拿到首轮反馈并完成相应调整后，再发布带产品链接和真实演示的帖子。

标题：

```text
I asked why people stay up waiting for Codex. Keeping the Mac awake was only half the problem.
```

正文：

```text
Last week I asked why people stay up when Codex is still running.

The answers split into a few groups. Some people already use Codex’s prevent-sleep setting or caffeinate and are completely fine. Others don’t want the Mac staying awake all night after the work finishes. A few said permission prompts are the real reason they don’t trust leaving.

I built a small prototype around the second group.

It watches local terminal Codex lifecycle events, keeps the system awake while any tracked task remains unfinished, and starts a cancelable five-minute countdown after the last task truly finishes. The display can still turn off normally.

It doesn’t read prompts, source code, project contents, or terminal output.

The current beta is Codex-only and doesn’t promise lid-closed operation. I’m looking for a small number of Mac users who already run long local tasks and are willing to test it on a real evening.

Here’s a 12-second recording of the current flow.

If this is already fully solved by your setup, I’d also like to hear that.
```

帖子应透明说明开发者身份、当前支持范围和限制，并附 10～12 秒真实产品录屏。

## 录制 12 秒产品流程

| 时间 | 画面 | 验证的能力 |
| --- | --- | --- |
| 0～3 秒 | 两个终端 Codex 任务启动，TermiNap 显示两格电量 | 多任务与生命周期识别 |
| 3～6 秒 | 一个任务结束，电量减少一格 | 单任务完成不会过早收尾 |
| 6～9 秒 | 最后一个任务结束，出现 5 分钟倒计时 | 所有任务归零后的自动收尾 |
| 9～12 秒 | 新任务启动，倒计时取消，电量重新增加 | 新任务安全取消电源动作 |

录屏必须展示真实产品行为，不使用只表达概念的设计效果图。

## 遵守首轮宣传边界

第一篇验证帖禁止使用以下宣传语：

```text
Introducing TermiNap
Revolutionary AI agent power manager
Boost your productivity
Seamless integration
Supports all coding agents
Never lose an overnight task again
Works with the lid closed
```

首轮也不得声称已经支持 Claude Code、所有 Agent、低电量保护、正式签名公证安装包、普通合盖运行或绝不误判状态。所有公开表述必须与 `MARKETING_PLAN.md` 的当前实现和禁止宣传清单一致。

## 按 10 天节奏执行

| 时间 | 动作 | 预期产出 |
| --- | --- | --- |
| 第 1 天 | 在 `r/codex` 发布文本帖，并预留两小时亲自回复 | 首批真实经历和反对意见 |
| 第 2 天 | 整理评论，邀请 3～5 位描述具体的用户短访谈或测试一晚 | 结构化反馈与 Beta 候选人 |
| 第 4～7 天 | 根据首轮结果重写并发布 `r/ClaudeCode` 版本 | 跨 Agent 行为证据 |
| 第 7 天 | 汇总发生人数、原因、替代方案、产品匹配和安装意愿 | 一页验证结论 |
| 第 8～10 天 | 仅在出现足够强的真实案例后发布第二轮产品帖 | 真实演示与小范围 Beta 招募 |

首帖建议安排在新加坡时间晚上 8:30～10:30。该时间只是工作假设，执行后应记录实际浏览量、回复速度和有效评论比例，再决定是否沿用。

## 形成一页验证结论

第 7 天的结论页必须回答：

1. 有多少人描述了最近发生的真实经历？
2. 他们为什么不去睡？
3. 他们正在使用什么替代方案，哪里不够好？
4. TermiNap 当前能解决其中多少问题？
5. 哪项能力必须提前，哪类需求不应进入产品？
6. 有多少人愿意在真实夜间任务中安装 Beta？

最终决策不以“有多少人回答 yes”为依据，而以问题是否集中在本地 Mac 电源状态、Agent Permission 和结束状态为依据。如果回答主要集中在立刻看结果和继续发送 Prompt，应明确记录这不是电源工具能够解决的问题。

## 参考来源

- [r/codex：睡前不愿中断 Codex 的讨论](https://www.reddit.com/r/codex/comments/1spb2h2/when_you_wanna_go_to_sleep_but_it_gives_you_this/)
- [OpenAI Academy：Codex Settings](https://openai.com/academy/codex-settings/)
- [r/ClaudeCode：Keepresso 发布帖](https://www.reddit.com/r/ClaudeCode/comments/1v6vdrg/my_mac_kept_sleeping_through_long_claude_code/)
- [r/codex 社区主页与规则](https://www.reddit.com/r/codex/)
- [r/ClaudeCode Weekly Showcase Thread](https://www.reddit.com/r/ClaudeCode/comments/1v7vewn/weekly_showcase_thread_show_us_what_you_built/)
- [r/macapps 发帖规则更新](https://www.reddit.com/r/macapps/comments/1qghsc5/new_post_guidelines_and_updates_on_rmacapps/)
