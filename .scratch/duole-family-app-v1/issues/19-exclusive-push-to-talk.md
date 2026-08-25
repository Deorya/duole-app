# 实现互斥按住喊话及音频恢复

Status: needs-triage

Type: HITL

User stories covered: 70–75, 78–79

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

在 live watch session 中增加独立“按住喊话”动作。只有服务器授予短期互斥 talk lease 后，
Android 才启用上行音轨；松手先在手机本地静音，再释放租约。机器人 AudioModeArbiter 负责
扬声器路径、ASR 防回声、安全音频抢占以及异常结束后的语音恢复。

## Acceptance criteria

- [ ] Live 页面将“按住喊话”和“开始通话”作为两个独立按钮和意图。
- [ ] `talk.acquire` 在 scope、session、privacy、audio health 通过后返回唯一短期 lease 或稳定 busy。
- [ ] 未收到 granted 前 App 上行音轨保持 muted，服务端拒绝非 holder 的音频包。
- [ ] 同一时间最多一个 talk holder；竞争客户端显示安全截断的“某某正在喊话中”和 retry hint。
- [ ] 持有期间通过有界 heartbeat 续租；松手、滑出、App 后台、WS/media 断开、token 撤销和超时自动释放。
- [ ] App pointer-up 时先本地 mute，再发送 release；服务端 lease 未及时释放也不能继续听到 App 音频。
- [ ] AudioModeArbiter 进入 PTT playback 时抑制/保护 ASR，避免机器人扬声器内容触发普通命令。
- [ ] 本地 safety/fall P0 输出可抢占或 duck 远程播放，并向 App 发出明确原因。
- [ ] 正常 release、断网、media crash 和 audio error 后 mixer、ASR、wake/TTS policy 恢复并可验证。
- [ ] 本地 privacy off 立即静音、撤销 lease 并结束关联媒体；不存在 takeover/force 接口。
- [ ] 在真实扬声器/麦克风环境完成互斥、回声触发、安全抢占、延迟和异常恢复 HIL 测试。
- [ ] lease state machine、signaling、audio arbiter、Android press lifecycle 和 fault injection 测试通过。

## Blocked by

- [18 贯通实时画面、环境音与机器人持续提示](18-live-video-ambient-audio-notice.md)
