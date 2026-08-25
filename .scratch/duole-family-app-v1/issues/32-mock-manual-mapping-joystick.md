# 贯通 MOCK_NO_MOTION 手动建图与 App 摇杆

Status: needs-triage

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

- [ ] 页面和 capability 持续明确显示 `MOCK_NO_MOTION`，测试证明未打开真实 SLAM、底盘或 `/cmd_vel*` 输出。
- [ ] 开始前消费本次 `mapping_authorization`，显示统一现场安全公告和一个确认按钮，并投影充电、静止、电量 `>=50%`、传感器、碰撞保护、停止链、存储、motion owner 和版本预检。
- [ ] 二维模拟量摇杆只有持续按压才产生意图；离中心距离控制幅度，前后最大线速度对称、左右最大角速度对称，App 不展示或修改真实速度参数。
- [ ] 每次按压使用新的 lease/epoch；intent 包含 session、lease、epoch、递增 seq、sent time、短 TTL 和有限范围，重复、倒序、过期、NaN、超范围和错误 lease 被拒绝。
- [ ] 松手、移出控制区和 pointer cancel 先在 App 本地归零，再等待 fake guard 的停止确认后允许下一次按压。
- [ ] fake 碰撞保护可减速或阻断意图，并让 App 显示稳定“受阻”原因；不存在关闭保护的入口。
- [ ] 页面显示实时增量地图、机器人位置、已探索面积、电量、阶段和耗时，不接视频/环境音，也不显示伪精确完成百分比。
- [ ] 采集阶段最长 30 分钟；结束后进入最长 5 分钟手动回桩阶段。计时、提前结束、正常保存、未验证保存、立即停止和放弃均有独立状态与结果。
- [ ] 控制连接丢失时 fake wheel 在一秒红线内确认停止，3 秒内可重连继续；超过 3 秒、App 后台、锁屏或进程结束则终止并保存未验证地图。
- [ ] 模拟崩溃恢复最后原子快照为异常中止地图，但不恢复控制 lease；普通远程 teleop capability 始终保持不可用。
- [ ] Android lifecycle、WSS/IPC schema、lease validator、fake watchdog、地图事件恢复、容量失败和状态文案测试通过。

## Blocked by

- [31 贯通现场地图授权与事务性地图切换](31-onsite-map-authorization-transactional-switch.md)
