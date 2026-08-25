# 实现导航板 TeleopGuard、双 watchdog 与真车遥控

Status: needs-triage

Type: HITL

User stories covered: 92–105

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

在 Issue 33 已验收的 mapping-scoped TeleopGuard 基础上扩展普通、媒体联锁的 TeleopGuard
和唯一速度仲裁边界，把已验证的 App 归一化意图转换为受固定低速、加速度、碰撞保护、视频
新鲜度和独立 watchdog 约束的真实运动。先完成抬轮/HIL，再在清空的低速区域开放普通
`REAL teleop` capability；任何停止场景超出一秒即关闭真实遥控。

## Acceptance criteria

- [ ] 联合冻结 TeleopGuard control/data/status 合同，包含 lease、epoch、seq、TTL、arm/release/stop 和确认时间戳。
- [ ] Public Gateway 不直接发布 base velocity；只有 TeleopGuard 经认可的唯一 velocity mux/collision path 输出真实速度。
- [ ] 机器人端只接受归一化 intent，并应用版本化固定安全 profile；App/抓包无法提高 linear/angular/acceleration 上限。
- [ ] gateway watchdog 与 navigation-board watchdog 独立；任一 heartbeat/intent timeout 直接撤销 lease并维持 zero。
- [ ] 导航板/TeleopGuard 重启默认 unarmed + zero，旧 lease/epoch 不恢复、不接受晚到包。
- [ ] local privacy、safety/fall inhibitor、emergency stop、media stale 和 TaskCoordinator owner 变化立即 revoke/stop。
- [ ] App 显示控制、stop pending、真实 stopped、revoked 和 unconfirmed reason；未确认不得重新 acquire。
- [ ] HIL 覆盖 App kill、后台、锁屏、来电、Wi-Fi off、AP off、丢包、半开连接、gateway/media/guard/nav-board restart 和 video freeze。
- [ ] REAL 测试在封闭清空区域、最低速度 profile、硬件急停可触达的条件下进行。
- [ ] pointer release 与每类断链/抢占从触发到真实车轮停止均多轮测量，最差不超过一秒。
- [ ] 任一场景超标自动使 REAL teleop capability unavailable；修复后重新执行全部 REAL stop 回归。
- [ ] 保存 App/gateway/media/runtime/guard/base 版本、lease IDs、零速/停止时间和外部视频证据。

## Blocked by

- [14 实现独立紧急停止与机器人停止确认](14-emergency-stop-confirmation.md)
- [18 贯通实时画面、环境音与机器人持续提示](18-live-video-ambient-audio-notice.md)
- [21 贯通 MOCK_NO_MOTION 遥控会话、按压租约与视频门](21-mock-teleop-lease-video-gate.md)
- [33 贯通 REAL 手动建图、TeleopGuard 与充电桩闭环](33-real-manual-mapping-teleop-guard.md)
