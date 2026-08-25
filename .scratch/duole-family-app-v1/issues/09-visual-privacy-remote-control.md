# 实现视觉隐私远程控制及媒体与运动联动关闭

Status: needs-triage

Type: HITL

User stories covered: 68–69, 141–148

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

让已授权 App 查询视觉监护 desired/actual state、本地隐私锁和受影响能力，并通过正式运行时
内同一个 Visual Monitoring 服务请求开启或关闭。关闭必须沿用现有顺序完成运动抑制、策略
持久化、视觉子进程停止以及媒体/teleop authorization 撤销；本地隐私锁始终阻止远程静默
开启。

## Acceptance criteria

- [ ] App 视觉隐私页展示 desired/actual state、local privacy lock、supervisor health、更新时间和受影响能力。
- [ ] 网络 actor 映射为 canonical actor，命令 source 固定为 `app`；客户端无法伪造 local voice/UI/system。
- [ ] 所有切换包含稳定 correlation/idempotency identity、timezone-aware request time、TTL 和有界 reason。
- [ ] 远程关闭先激活共享 motion inhibitor/cancel，再持久化/audit，再停止精确视觉 child，确认 actual off 后才返回成功。
- [ ] 关闭会撤销现有或未来接入的 media、PTT、call 和 teleop authorization；联动 port 可用 fake 验证。
- [ ] 本地隐私锁存在时远程 on 返回稳定 `LOCAL_PRIVACY_LOCKED`，外部合同不存在 force override。
- [ ] duplicate correlation 返回同一结果，并发 on/off 在机器人服务边界串行化。
- [ ] 隐私 off 在重启后保持；App 断开或网关重启不能自动开启视觉。
- [ ] 视觉关闭不会删除已经发生的安全事故或事件历史，但人员覆盖/跌倒视觉 capability 诚实变为 disabled/unavailable。
- [ ] HIL 验证本地开关优先、真实视觉 child 停止、控制 socket 权限以及 App UI 状态一致。
- [ ] 既有视觉隐私回归与新增 App contract、IPC、事件和 Android 页面测试全部通过。

## Blocked by

- [04 实现一次性配对、安装实例绑定与撤销](04-pairing-session-revocation.md)
- [06 实现持久事件投影、WebSocket 补拉与重同步](06-event-projection-replay-resync.md)
