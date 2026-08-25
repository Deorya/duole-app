# 实现独立紧急停止与机器人停止确认

Status: ready-for-human

Implementation: complete-2026-08-24

Acceptance: accepted-2026-08-25

Type: HITL

User stories covered: 103–105, 116

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

交付不依赖 teleop ownership 的高优先级停止纵向切片：有 `robot.stop` scope 的 Android 用户
可以从机器人、任务和未来遥控页面发起幂等 stop operation；正式运行时撤销 App 运动、取消
明确属于 App 的任务并调用机器人正式 stop boundary，直到获得可信停止确认或明确要求现场
核查。

## Acceptance criteria

- [x] stop API/command 只要求 `robot.stop` scope，不要求控制租约或当前任务 owner。
- [x] 每次首次请求返回稳定 stop operation ID；相同 idempotency key 重试返回同一 operation。
- [x] stop 首先撤销现有/未来 App teleop lease，然后让共享 TaskCoordinator 取消明确属于 App 的 motion tasks。
- [x] 机器人端调用正式 stop/cancel boundary，不由公网关直接发布底盘速度。
- [x] operation 状态至少覆盖 accepted、stopping、stopped、failed 和 unconfirmed，并通过查询/事件恢复。
- [x] Android 在真实停止确认前持续显示 stop pending；超时显示红色锁定和现场核查提示。
- [x] HTTP 202、ROS publish 成功或本地任务状态清空均不能单独映射为 `stopped`。
- [x] 重复 stop 幂等且安全；无活动任务、导航 busy、wrapper 部分故障和网关重连均有明确结果。
- [x] HIL/REAL 记录从 App 操作到真实机器人停止的时间戳和最差延迟，不超过现有一秒红线。
- [x] 现场测试在封闭区域/抬轮架进行，硬件急停可触达，并保存版本化脱敏证据。
- [x] TaskCoordinator、stop adapter、事件、REST、Android UI 和真机验收测试通过。

## Blocked by

- [04 实现一次性配对、安装实例绑定与撤销](04-pairing-session-revocation.md)
- [06 实现持久事件投影、WebSocket 补拉与重同步](06-event-projection-replay-resync.md)

## Comments

### 2026-08-24 software and stationary HIL evidence

- 软件纵向切片已完成：持久幂等 operation、lease revoke/inhibit、共享 TaskCoordinator
  App-motion cancel、正式 `/stop_actions` boundary、独立 fresh `/odom` 确认、事件/查询恢复，
  以及 Android pending/confirmed/fail-closed 控件。
- 最终 App Gateway/HIL 证据回归为 151 passed；合同 42 passed、Flutter 35 passed，
  Dart/Flutter analyze 无问题。ARM64 主机构建的新 APK 为 165590497 bytes，SHA-256
  `d73432db28a4cb2ef56ca9b929916f8d25b1d3580636aa17fdae23206ede83da`。
- 六次静止真实边界成功延迟为 964.470、577.230、586.936、715.174、700.566、
  723.233 ms，最差 964.470 ms；最后两次立即重复调用均接受并由 fresh `/odom` 确认。
- REAL harness 只接受 stop 请求前 250 ms 至确认之间的非零 odom 样本，陈旧运动样本不能
  关闭验收。当前证据明确为 `moving_sample_observed=false`。

### 2026-08-25 moving HIL/REAL acceptance

- 操作者已确认封闭区域/抬轮架和可触达硬件急停；Issue 13/14 APK 已在 OnePlus PHK110
  真机验证，SHA-256 为
  `d73432db28a4cb2ef56ca9b929916f8d25b1d3580636aa17fdae23206ede83da`。
- 手机确认前 91 ms 的 fresh `/odom` 为 0.137 m/s、0.331 rad/s，满足真实运动证据，
  不是静止探针。机器人在估算 683 ms 后进入停止阈值，并在 907 ms 后完成连续
  200 ms 停稳窗口；计入 29 ms 校时不确定度的保守结果为 936 ms，低于一秒红线。
- durable operation `stop_ce2153cfbdc447eca6ea5d8bb3ca901d` 从服务端接收到
  `stopped`/`robot_motion_stationary_confirmed` 用时 831.749 ms；保守手机确认到终态
  为 934.032 ms。最终 `/odom` 保持零速，App 仅在独立确认后显示“已确认停止”。
- REAL 预验收暴露导航板 `stop_actions_node` 在发送 cancel 前同步制动 600 ms 的根因。
  已改为先批量发送所有正式 Action cancel，再制动并在统一期限内收集结果；远端 8 项
  回归通过，部署源码 SHA-256 为
  `ea7cc8038221a8b2c3eca260c8fddb4b97addd62d709be2c2a4dc1acaa7ac732`，
  可恢复备份为 `stop_actions_node.py.bak_issue14_20260825`。
- 版本化脱敏时间轴和截图位于
  `docs/evidence/app_gateway/20260825/issue14_moving_stop_hil.json` 与
  `docs/evidence/app_gateway/20260825/issue14_moving_stop_hil_confirmed.png`。

Issue 14 的软件、导航板和 Android 真机移动急停验收条件已全部关闭。
