# 贯通 REAL 手动建图、TeleopGuard 与充电桩闭环

Status: needs-triage

Type: HITL

User stories covered: 187–195

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

把已验收的手动建图 MOCK 合同接入导航板真实 SLAM 和专用 `manual_mapping` TeleopGuard。
用户在现场从共同充电桩开始，以固定安全配置手动驶离、覆盖家庭区域并手动回桩。导航板是
SLAM、速度限制、碰撞保护、地图保存、评分和车轮停车的唯一执行者；该切片不开放普通远程
遥控，也不依赖实时视频。

## Acceptance criteria

- [ ] 正式运行时以共享 TaskCoordinator 的独占 `manual_mapping` motion owner 启停 SLAM；网关和 App 不直接启动脚本、写地图文件或发布任何 `/cmd_vel`。
- [ ] 导航板 TeleopGuard 接受 mapping-scoped lease/epoch/seq/TTL 归一化意图，应用固定对称线/角速度、加速度限制、唯一 velocity mux 和最终 collision monitor 路径。
- [ ] gateway watchdog 与 base-side watchdog 独立；松手、App 后台、锁屏、进程死亡、3 秒重连超时、AP/Wi-Fi/IPC 故障或 guard 重启都在一秒内确认真实车轮停止。
- [ ] 开始只在机器人 BMS 新鲜且确认充电、底盘静止、电量 `>=50%`、里程计/激光/深度/碰撞保护/停止链/存储健康时通过，且由导航板记录共同充电桩锚点。
- [ ] 首次手动离桩前机器人语音播报并持续以屏幕或指示灯提示“正在建图”；用户用摇杆驶离，不自动离桩。
- [ ] SLAM 增量地图和机器人 pose 通过受控 DTO/资源流投影到 App，不暴露 ROS QoS、原始文件路径或任意控制参数。
- [ ] 正常完成要求用户在 30 分钟采集期后、最长 5 分钟内手动回桩，并以真实 BMS 充电确认保存和回桩验证结果。
- [ ] 无法回桩时允许停车并保存“未通过回桩验证”的低分地图；立即停止先停车后保存未完整地图；放弃先停车、删除临时地图并要求人工放回充电桩。
- [ ] 导航板周期性原子保存临时快照；进程崩溃或掉电后可登记最后可读快照为异常中止地图，但不得恢复旧控制 lease 或继续本次建图。
- [ ] 新地图保存后不自动启用；导航板恢复建图前的活动地图，若原本无活动地图则保持未选择状态。
- [ ] `manual_mapping.available` 与普通 `teleop.available` 独立；本工单通过不能使无视频普通遥控变为可用。
- [ ] 先在抬轮架/HIL 验证全部停止触发，再在清空低速区域完成真实离桩、覆盖、手动回桩、异常保存、断网和最差停车延迟 `<=1 s` 的 REAL 证据。

## Blocked by

- [32 贯通 MOCK_NO_MOTION 手动建图与 App 摇杆](32-mock-manual-mapping-joystick.md)
