# 贯通 MOCK_NO_MOTION 手动建图与 App 摇杆

Status: ready-for-human

Resolution: landed

Type: AFK

User stories covered: 176, 187–195

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

在 `MOCK_NO_MOTION` 下交付完整的现场手动建图 tracer bullet。Android 完成二维码授权和准备
引导后进入无视频的地图+摇杆页面；持续按压产生受 lease、epoch、seq 和 TTL 约束的归一化
控制意图，fake TeleopGuard 与 fake SLAM 返回停车、增量地图、评分、保存和回桩结果。所有
生命周期都可验收，但任何输入都不能到达真实速度边界。

## Acceptance criteria

- [x] 页面和 capability 持续明确显示 `MOCK_NO_MOTION`，测试证明未打开真实 SLAM、底盘或 `/cmd_vel*` 输出。
- [x] 开始前消费本次 `mapping_authorization`，显示统一现场安全公告和一个确认按钮，并投影充电、静止、电量 `>=50%`、传感器、碰撞保护、停止链、存储、motion owner 和版本预检。
- [x] 二维模拟量摇杆只有持续按压才产生意图；离中心距离控制幅度，前后最大线速度对称、左右最大角速度对称，App 不展示或修改真实速度参数。
- [x] 每次按压使用新的 lease/epoch；intent 包含 session、lease、epoch、递增 seq、sent time、短 TTL 和有限范围，重复、倒序、过期、NaN、超范围和错误 lease 被拒绝。
- [x] 松手、移出控制区和 pointer cancel 先在 App 本地归零，再等待 fake guard 的停止确认后允许下一次按压。
- [x] fake 碰撞保护可减速或阻断意图，并让 App 显示稳定“受阻”原因；不存在关闭保护的入口。
- [x] 页面显示实时增量地图、机器人位置、已探索面积、电量、阶段和耗时，不接视频/环境音，也不显示伪精确完成百分比。
- [x] 采集阶段最长 30 分钟；结束后进入最长 5 分钟手动回桩阶段。计时、提前结束、正常保存、未验证保存、立即停止和放弃均有独立状态与结果。
- [x] 控制连接丢失时 fake wheel 在一秒红线内确认停止，3 秒内可重连继续；超过 3 秒、App 后台、锁屏或进程结束则终止并保存未验证地图。
- [x] 模拟崩溃恢复最后原子快照为异常中止地图，但不恢复控制 lease；普通远程 teleop capability 始终保持不可用。
- [x] Android lifecycle、WSS/IPC schema、lease validator、fake watchdog、地图事件恢复、容量失败和状态文案测试通过。

## Blocked by

- [31 贯通现场地图授权与事务性地图切换](31-onsite-map-authorization-transactional-switch.md)

## Comments

### 2026-08-27 最终软件验收

- 已按 TDD 完成 MOCK_NO_MOTION 手动建图的 App、Dart 客户端、OpenAPI 1.6、App Gateway、
  WSS、SQLite 恢复、fake TeleopGuard/fake SLAM 与 Android lifecycle 纵向切片；11 条验收
  标准均有自动化证据并已逐项勾选。
- 正式 MOCK CLI 明确拒绝导航板参数且不构造 SSH 导航板；fake 边界没有物理输出端口，
  `manual_mapping` capability 只在 MOCK 可用，普通 `teleop` 始终不可用。本验收不声称或
  提前开放 Issue 33 的真实车轮能力。
- Provider 最终 `master` 全量为 `3137 passed, 1 skipped, 4 warnings`；App 合同消费者 26 个入口、工程
  客户端 38 个入口、Flutter 63 项全部通过，三个 Dart/Flutter 包静态分析均无问题，合同
  audit 与 provider fixtures 全绿。
- 最终 clean rebuild 的 ARM64 调试 APK 为
  `flutter/duole_engineering_app/build/app/outputs/flutter-apk/app-debug.apk`，96,348,925 bytes，
  SHA-256 `d4e1d472172509524e23fcdb27866bbeb4651c01cbbe7c716883f95dadc47600`；
  ZIP 完整性、APK Signature Scheme v2、包名 `com.duole.engineering.duole_engineering_app`、
  minSdk 24 和 targetSdk 36 均已复核。
- 详细逐条证据见 `docs/evidence/issue32/20260827/README.md`。Issue 状态转为
  `ready-for-human`，供维护者最终审阅；MOCK 范围内没有遗留 HIL 或真实运动前置条件。

### 2026-08-27 落地验收

- 维护者要求提交并落地 Issue 32；本地跟踪器没有 `completed` 状态，因此保留标准状态
  `ready-for-human`，并以 `Resolution: landed` 记录完成结论。
- 落地前独立复审发现的半帧 watchdog、deadline 绕过、stop ack lease 绑定、runtime mode
  漂移、WSS fail-closed、revision 竞态和终态文案问题均已补充红灯测试并修复；两边复审均
  确认没有剩余代码阻断项。
- 修复后重新执行 Provider 全量、App 三层全量、生成合同漂移检查及 clean APK 构建；上方
  测试数字、APK 大小与哈希均为本次落地版本的最终结果。
