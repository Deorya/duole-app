# 贯通 MOCK_NO_MOTION 遥控会话、按压租约与视频门

Status: needs-triage

Type: AFK

User stories covered: 92–102, 104

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

在全局 `MOCK_NO_MOTION` 下交付完整但不会驱动车轮的 teleop tracer bullet：Android 沉浸式
页面读取实时视频和 gate，创建 session，每次持续按压取得新 control lease/epoch，发送有序
归一化 intent，并在松手、生命周期、网络或视频故障时进入 stop pending/stopped。机器人端
使用 fake base adapter 验证全部协议和状态，不产生真实速度输出。

## Acceptance criteria

- [ ] Teleop 页面始终显示 `MOCK_NO_MOTION`，任何 UI/响应都不能声称真实机器人移动成功。
- [ ] session 创建检查 media session、video freshness、mode、scope、motion owner、safety/privacy 和 adapter capability。
- [ ] 每次按压单独 acquire control lease/epoch；松手确认 stopped 后才允许下一次 acquire。
- [ ] intent 包含 session、lease、epoch、递增 seq、sent time、短 TTL 和 `[-1,1]` linear/angular。
- [ ] duplicate、out-of-order、expired、wrong lease/epoch、NaN/Infinity、超范围和过高频率消息被拒绝并可诊断。
- [ ] 多客户端并发只有一个 holder；其他客户端得到 busy，松手后自然可用，不存在接管申请。
- [ ] App pointer-up 先回中，后台、锁屏、来电、process kill、WS half-open 和网络断开均触发 watchdog stop。
- [ ] source frame freeze、编码积压或服务端估算视频延迟超过公布门限时撤销 lease 并锁定控制。
- [ ] fake base adapter 记录 arm、intent、zero、release 和 stop confirm，且测试证明未访问真实 velocity boundary。
- [ ] TaskCoordinator 使用 `app_teleop` 语义申请/释放 motion；busy/external/stale/inhibited 均 fail closed。
- [ ] Android lifecycle、WS protocol、lease/order validator、video gate、fake watchdog 和事件恢复测试通过。

## Blocked by

- [05 实现一致能力快照与机器人状态页面](05-capability-snapshot-robot-status.md)
- [06 实现持久事件投影、WebSocket 补拉与重同步](06-event-projection-replay-resync.md)
- [18 贯通实时画面、环境音与机器人持续提示](18-live-video-ambient-audio-notice.md)
