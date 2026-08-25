# 实现一致能力快照与机器人状态页面

Status: ready-for-human

Implementation: complete-2026-08-23

Acceptance: accepted-2026-08-24

Type: AFK

User stories covered: 32–43

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

把现有机器人领域事实投影成一个带 high-water sequence 的一致快照，并在 Android 的首页
摘要和机器人状态页展示连接、模式、能力、设备健康、活动任务、视觉状态、更新时间和陈旧
原因。普通页面读取投影，不在每次 HTTP 请求中同步执行无界硬件探针。

## Acceptance criteria

- [x] 快照包含 `snapshot_seq`、server time、robot identity/mode、capabilities、states、活动事件/任务摘要、今日日程摘要和隐私/媒体摘要占位。
- [x] 同一响应中的投影行均不晚于 `snapshot_seq`，并包含各自更新时间和 stale threshold。
- [x] capability 由构建、运行配置、adapter 兼容、依赖健康和当前安全/隐私门共同决定。
- [x] App 明确区分 ok、degraded、unavailable、disabled、unknown 和 stale，不能把旧缓存显示为实时绿色。
- [x] 设备状态至少展示电量、网络、麦克风、摄像头、导航、版本、人员覆盖、视觉监护和当前活动的真实可用项。
- [x] 人员状态使用“检测到人/无人可见/覆盖退化”等表述，不把视觉观察归因为具体老人。
- [x] App 后台、重连和机器人时钟变化后按 server time 重新计算新鲜度；写能力在快照连续性不确定时禁用。
- [x] 工程强制刷新需要专有 scope、速率限制和 deadline，并与普通首页快照读取分离。
- [x] provider timeout/异常只降级对应项，其余快照仍可用；诊断字段经过白名单和大小限制。
- [x] Android 页面、projection、领域 adapter 和 contract 测试覆盖正常、陈旧、部分故障和未知 enum。

## Blocked by

- [02 贯通真实 Device Status 只读链路](02-real-device-status-tracer-bullet.md)
- [04 实现一次性配对、安装实例绑定与撤销](04-pairing-session-revocation.md)

## Comments

### 2026-08-23 implementation evidence

- 已交付事务型 `snapshot_seq` high-water、六类 read-model 分组、server-time
  freshness、能力组合门、真实 Device Status projector 和稳定降级错误。
- 工程强制刷新与普通读路径分离，并受 scope、installation proof、速率、TTL、
  idempotency 和 runtime deadline 约束；空 body 防止未签名隐藏参数。
- Android 机器人状态页区分五种健康状态与 stale，人员表述保持匿名；只有快照连续且
  Events 处于 live 时才显示写能力可用。
- 共享软件门结果：141 passed、1 skipped；合同/fixtures、26 个 Dart 入口、24 个
  Flutter 测试、静态分析和 Android Kotlin 离线编译全部通过。
- 设计、运行边界与实机剩余项见
  `docs/interface_freeze/app_v1/issue_05_capability_snapshot.md`。

### Human acceptance boundary

- 正式 product-session owner 需要以有界 cadence 激活 factory 产出的 projector；gateway
  本身不会同步探测硬件，也不会暗中启动无所有者线程。
- 需在目标机器人/Android 上逐项核对真实设备来源、后台/重连/时钟变化和强制刷新负载。

### 2026-08-24 Physical Android/robot acceptance

- 正式 product session 以 5 秒有界 cadence 持有 projector，正式 Gateway 只读取共享
  projection database；运行时独立重启后投影继续前进。
- PHK110 实机页面核对了电量、网络、麦克风、摄像头、导航、版本、匿名人员覆盖、
  视觉监护、当前活动及隐私/媒体摘要，并正确区分健康、降级和新鲜度。
- 真实电量工程强制刷新成功；紧接的第二次调用稳定返回
  `429 FORCE_REFRESH_RATE_LIMITED`。
- 仅停止运行时、保持 Gateway 在线时，强制刷新稳定降级为
  `capabilityUnavailable`，App 保留最后快照且不崩页；恢复原正式运行时后，投影从
  45% 前进到新鲜 44%，再次强制刷新成功并恢复 `battery_ready`。
- App 后台/恢复、Gateway 连接中断/恢复和手机整机重启后均保持失败关闭与连续投影；
  完整截图、哈希和日志扫描见 `docs/evidence/app_gateway/20260824/README.md`。

Issue 05 的全部验收条件已正式关闭。
