# 实现一对一全双工通话与音频仲裁

Status: needs-triage

Type: HITL

User stories covered: 76–83

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

交付 Engineering V1 的机器人加一台手机全双工通话。家属点击“开始通话”后机器人自动接通
并保持持续提示，AudioModeArbiter 进入 full-duplex call，真实 AEC/NS/AGC 和普通 ASR/TTS
策略有明确状态；结束、断网或故障后恢复正常语音链。

## Acceptance criteria

- [ ] 已授权用户可从 Live 页面创建/升级一对一 call session，无需老人操作机器人端确认。
- [ ] call 与 PTT 状态互斥；进入 call 前释放 talk lease，退出 call 后不自动恢复旧 lease。
- [ ] robot notice 明确区分观看与通话，并在整个 call live/degraded 期间持续可感知。
- [ ] App 与机器人实现双向 Opus/批准 codec 音频，实际 AEC、NS、AGC 和 audio mode 可诊断。
- [ ] full-duplex call 期间普通 wake/ASR 按冻结策略暂停或防回声，远程扬声器内容不能触发业务命令。
- [ ] safety/fall output 保留最高本地可听优先级，可抢占/duck call 并将状态变化通知 App。
- [ ] camera 或 robot display 故障按能力返回明确降级；E1 不显示多人、九宫格或邀请按钮。
- [ ] App/WS/media 断开、token/permission 撤销、privacy off 和进程 crash 均结束 call 并运行恢复事务。
- [ ] 恢复事务验证 speaker/mixer、microphone fan-out、ASR、wake 和 TTS owner 回到正常状态；失败则 voice capability degraded。
- [ ] 真实距离、音量和房间回声条件下无不可接受啸叫、回声命令触发或持续资源占用。
- [ ] 30 分钟 call、网络抖动、扬声器音量、安全抢占及正常/异常退出 HIL 证据通过。
- [ ] call contract、media/audio state machine、Android lifecycle 和现有语音/TTS 回归通过。

## Blocked by

- [19 实现互斥按住喊话及音频恢复](19-exclusive-push-to-talk.md)
