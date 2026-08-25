# 实现持久事件投影、WebSocket 补拉与重同步

Status: ready-for-human

Implementation: complete-2026-08-23

Acceptance: accepted-2026-08-24

Type: AFK

User stories covered: 51–57, 155, 159–162

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

建立面向 App 的持久 event projection/outbox，并交付 Android 从快照 sequence 接续事件、断线
补拉、去重、缺口检测和完整重同步的端到端链路。投影只观察现有业务分发结果一次，不能为
App 再次调用安全、任务或日程 workflow。

## Acceptance criteria

- [x] 单 writer 为每个已提交 App event 分配机器人范围内单调递增 seq，并保存稳定 event ID、source key、发生/发布时间和 correlation。
- [x] event append 与受影响 read model 在同一事务提交，进程崩溃后不存在事件/快照半状态。
- [x] 相同 source identity/revision 并发重入只产生一个 event/seq；乱序 source revision 不能让终态回退。
- [x] 快照 high-water 与 replay/live barrier 能保证二者之间没有漏事件或重复副作用。
- [x] Events WS 提供 hello、heartbeat、ordered replay、sync complete 和 resync required 语义。
- [x] App 保存最后成功应用的 seq；重复安全忽略、缺口暂停同步、游标过期或 continuity degraded 时获取完整快照。
- [x] gateway 与正式运行时分别重启后不会从头分配 seq，也不会自动重发结果不明的写命令。
- [x] 投影损坏、磁盘满、队列溢出和 schema 不兼容会降级 capability 并要求 resync，不伪装连续。
- [x] 慢 WebSocket 客户端被独立断开并从 cursor 恢复，不阻塞 writer、业务线程或其他客户端。
- [x] 安全 workflow 在投影故障时仍继续本地处置；事件观察回调只执行有界 enqueue。
- [x] 通过高并发去重、每个 seq 断线、retention 裁剪、DB integrity/rebuild 和未知事件类型测试。

## Blocked by

- [04 实现一次性配对、安装实例绑定与撤销](04-pairing-session-revocation.md)
- [05 实现一致能力快照与机器人状态页面](05-capability-snapshot-robot-status.md)

## Comments

### 2026-08-23 implementation evidence

- 已交付 SQLite 单 writer/outbox、事务型 read-model 更新、持久 seq、并发去重、乱序拒绝、
  retention/resync、64 KiB 完整 frame 上限与可恢复 rebuild。
- TLS Events WS 已覆盖 hello、严格 replay、live barrier、heartbeat、resync、撤销和慢客户端
  独立写超时；重新连接从最后 cursor 接续，不会重放写命令。
- Android/Dart controller 先持久化再推进 cursor；重复、缺口、未知类型、坏 envelope、存储
  故障和 continuity degraded 均失败关闭。`EventSyncSession.close()` 可等待且不会遗留后台 loop。
- 共享软件门结果：141 passed、1 skipped；合同/fixtures、26 个 Dart 入口、24 个
  Flutter 测试、静态分析和 Android Kotlin 离线编译全部通过。
- 协议、故障语义、运行激活边界和 HIL 剩余项见
  `docs/interface_freeze/app_v1/issue_06_event_projection_replay.md`。

### Human acceptance boundary

- 正式 product session 仍需把各领域“已提交结果”观察器一次性接入有界 observer queue；
  不得从观察器再次调用 workflow。
- 需在目标机器人/Android 上执行 gateway/runtime 独立重启、短断网逐 cursor、慢客户端、
  retention、受控数据库损坏/存储耗尽与 rebuild 演练。

### 2026-08-24 Physical Android/robot acceptance

- 正式 runtime 与 Gateway 分别独立重启；Android 事件游标从 `#3444` 连续恢复至
  `#3465`，后台/前台后继续至 `#3473`，未从零分配或重放写命令。
- App 进程重启及手机整机重启后，Keystore 会话保持；重启后的 Robot Status 显示
  snapshot `#6784`、事件连续同步至 `#6789`，游标由安全存储恢复。
- disposable database 下 21 项受控演练全部通过，覆盖并发去重、retention/resync、
  完整 frame 上限、投影/回放损坏、磁盘满、队列溢出、慢客户端隔离、schema 拒绝、
  TLS replay/live、撤销和带备份的 controlled rebuild；live database 未被修改。
- 根据用户“不修改板端/手机网络配置”的明确约束，没有切换真实 Wi-Fi；以正式 Gateway
  中断/恢复验证连接断开和 cursor 恢复，并在证据中明确标记为批准的安全替代项。
- 手机重启后仅恢复官方无线 ADB 动态端口，未插 USB；最终 App `logcat` 和 448 行板端
  日志的 secret scan 均为零命中。完整证据见
  `docs/evidence/app_gateway/20260824/README.md`。

Issue 06 的全部验收条件已正式关闭。
