# Issue 32 MOCK_NO_MOTION 手动建图验收

日期：2026-08-27

## 结论

Issue 32 的 MOCK tracer bullet 已完成落地验收。正式 MOCK App Gateway 不构造 SSH
导航板、真实 SLAM、底盘适配器或 `/cmd_vel*` 发布边界；普通 `teleop` capability 仍为
不可用。此结论不授权或声称 Issue 33 的真实车轮手动建图能力。

## 验收映射

1. capability、页面和 WSS 会话持续返回 `MOCK_NO_MOTION`；正式 CLI 测试禁止构造
   `SshNavigationBoardClient`，fake guard 的物理输出计数和 fake SLAM 的真实进程计数均为 0。
2. 开始操作消费 Issue 31 的单次 `mapping_authorization`，要求安全公告确认，并返回充电、
   静止、电量不低于 50%、传感器、防碰撞、停止链、存储、motion owner 和版本九项预检。
3. Flutter 摇杆使用二维径向限幅；四轴最大值对称，按下位置立即生效，只有持续按压才按
   100 ms 周期发送归一化意图，不暴露真实速度参数。
4. 每次按压取得新的 400 ms lease/epoch；服务端严格验证 session、lease、epoch、连续 seq、
   sent time、最大 200 ms TTL、有限数值和 `[-1, 1]` 范围。
5. 松手、移出和 pointer cancel 均先本地归零；fake guard 未确认停车时保持
   `stop_pending`，包括终止命令、回桩完成和重连超时路径，不会伪造停车确认。
6. fake 防碰撞保护可稳定返回 `collision_slowdown` 或 `collision_blocked`，协议和 App
   均没有关闭保护的入口。
7. 页面显示增量栅格、机器人位置、探索面积、电量、阶段和耗时；合同没有视频、环境音或
   完成百分比。fake SLAM 使用冻结的 `MapQuality` 结构返回进行中、已验证、未验证和中断评分。
8. 自动时钟测试覆盖 30 分钟采集和 5 分钟手动回桩，以及提前结束、验证保存、未验证保存、
   立即停止、放弃和容量失败的独立结果。
9. 实际 TLS WSS 测试验证 lease watchdog 在一秒内请求停止，三秒静止重连窗口和超时终止；
   Flutter 覆盖后台、锁屏/非活跃和进程结束的 fail-closed 命令。
10. SQLite 原子快照在服务重启后恢复为 `interrupted_saved`，不恢复 lease；跨进程 IPC
    验证 `manual_mapping` 可用且普通 `teleop` 不可用。
11. Android lifecycle、WSS/IPC schema、validator、watchdog、地图恢复、容量失败和六种独立
    终态文案测试均已进入全量回归；协议错误会本地归零并关闭控制通道，陈旧 revision 不能
    覆盖终态。

## 自动化结果

- 机器人仓全量：`3059 passed, 1 skipped, 4 warnings`。跳过项为既有硬件依赖测试；警告为
  TLS 1.0/1.1 拒绝测试和既有第三方弃用告警。
- App Gateway + 合同定向回归通过；Issue 32 核心服务与 CLI 定向回归为 `38 passed`。
- App 合同消费者 26 个入口、工程客户端 38 个入口全部退出码 0。
- Flutter：`63 tests passed`。
- `duole_app_contract`、`duole_engineering_client` 和 `duole_engineering_app` 三个包静态分析
  均为 `No issues found`。
- App 合同 audit、27 项 provider/unknown-value 检查、生成 Dart 合同漂移检查以及未知枚举/
  能力拒绝审计全部通过。

## Android 制品

- 路径：`flutter/duole_engineering_app/build/app/outputs/flutter-apk/app-debug.apk`
- 目标：ARM64 Flutter 引擎；包内第三方扫码插件同时携带其上游提供的其他 ABI 库。
- 大小：`96,348,925` bytes
- SHA-256：`d4e1d472172509524e23fcdb27866bbeb4651c01cbbe7c716883f95dadc47600`
- ZIP 完整性：通过
- 签名：Android Debug，APK Signature Scheme v2 验证通过
- 包名/版本：`com.duole.engineering.duole_engineering_app`，`0.1.0 (1)`
- SDK：minSdk 24，targetSdk 36，compileSdk 36

ARM64 开发主机使用本地 ARM64 `aapt2` 覆盖 Google Maven 提供的 x86_64 二进制；该覆盖
仅用于构建工具兼容，不进入产品源码或 APK。最终构建前执行了 clean rebuild，排除了旧多
ABI 中间制品造成的尾随数据，最终 APK 的物理大小、ZIP 目录、哈希与签名彼此一致。
