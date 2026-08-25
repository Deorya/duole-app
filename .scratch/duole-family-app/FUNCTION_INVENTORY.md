# DUOLE 功能盘点与 App 映射

Status: `ready-for-human`

盘点基准日期：`2026-08-17`

## 1. 状态口径

| 状态 | 含义 |
|---|---|
| `CURRENT` | 当前正式机器人入口已装配，并有对应代码/状态来源 |
| `SOFTWARE_CANDIDATE` | 软件链与测试已形成，但真机安全或长期运行未完全验收 |
| `SHADOW` | 只观测、记录或评估，不允许驱动真实运动 |
| `PLANNED` | 仅有路由、设计或接口建议，不能显示为可用功能 |
| `APP_GAP` | 机器人有能力，但没有稳定 App transport/页面接口 |
| `OUT_OF_SCOPE_E1` | 不属于 Engineering V1 |

App 必须使用机器人返回的 capability 和 health 决定按钮状态，不能把本文表格硬编码为永远
可用。版本升级、设备差异和运行故障都可能改变实际能力。

## 2. 总体能力地图

```text
用户入口
├── 机器人本地语音（当前正式入口）
└── 多乐守护 App（待开发）
    └── duole-app-gateway（待开发）
        ├── 领域服务：日程 / 设备状态 / 视觉隐私
        ├── 任务网关：导航 / 巡逻 / 回充 / 停止 / 遥控
        ├── 事件流：Safety / VisionFall / 设备 / 任务
        ├── 媒体网关：RGB / 环境音 / 喊话 / 通话
        └── 工程诊断：版本 / 健康 / 请求追踪
```

## 3. 现有工作流盘点

| 领域 | 当前能力 | 当前成熟度 | Engineering V1 复用 | App 需要新增 |
|---|---|---|---|---|
| 日程 | 创建、确认、查询、删除、跨天查询/删除、提醒 DB | `CURRENT`，业务较高；多用户、更新、完成闭环仍缺 | 正式 SQLite 与 Schedule 领域服务 | REST CRUD、版本化更新、启停、确认状态、事件投影 |
| 闲聊 | Doubao 日常交流、单次唤醒上下文 | `CURRENT`，依赖云端 | 不直接暴露 | 无；家庭 App 不展示对话记录 |
| 设备状态 | 电量、网络、麦克风、摄像头、导航、版本、能力、当前任务、人员覆盖 | `SOFTWARE_CANDIDATE` | `DeviceStatusService` 及 provider | 快照 API、状态事件、稳定错误码与 App 文案映射 |
| 导航 | 巡逻、回充、停止、位姿、房间、唤醒人导航六类 Action 映射 | `SOFTWARE_CANDIDATE`；真车安全与恢复未全部关闭 | 任务跟踪、命令状态、地图/位姿来源 | App 任务 API、取消句柄、定时巡逻、能力门 |
| 手动遥控 | 现有导航文档只有接口建议 | `PLANNED` | 运动仲裁原则、底盘接口事实 | 短租约 teleop、watchdog、固定限速、视频健康联锁 |
| Safety | 烟雾、燃气、温度、解除告警、文本求助、优先级 | `SOFTWARE_CANDIDATE`；真实上游未齐 | 结构化领域事件与 TTS 优先级 | 事件流、详情投影；E1 不新增外部呼救 provider |
| VisionFall | 强类型跌倒事件、问询、超时、观察、升级状态机 | `SOFTWARE_CANDIDATE`；全部真机分支未验收 | `incident_id` 生命周期和业务回执 | 只读事件投影、补拉与详情状态；不得重算模型概率 |
| 人员视觉 | 人数、track、覆盖、构图、链路健康 | `SHADOW`；自动运动关闭 | 只读观测和 Device Status 投影 | 当前事实卡片；不做身份归因或活动轨迹 |
| 视觉隐私 | 本地语音开关、本地锁、持久状态、审计、supervisor | `CURRENT`（本地闭环）；真实 App transport 缺失 | `VisualMonitoringService` 和控制合同 | 可信 App ingress、状态/命令 API、媒体/运动联动 |
| 通用视觉 | 路由占位 | `PLANNED` | 无 | E1 不展示物品识别入口 |
| 健康咨询 | `DOMAIN_HEALTH` 占位 | `PLANNED` | 无 | E1 与家庭产品 V1 均不展示 |
| TTS/表情 | P0-P3 仲裁、`/face/request` | `SOFTWARE_CANDIDATE` | 状态与安全抢占原则 | 喊话/通话时的音频仲裁与 UI 状态 |

## 4. App 页面与后端能力映射

| App 功能 | 机器人已有来源 | 缺口类别 | E1 结论 |
|---|---|---|---|
| 首页状态 | Device Status、任务协调器、日程、事件桥 | App 聚合 API | P0 |
| 事件列表/详情 | Safety/VisionFall/设备/任务事件 | 持久事件游标与投影 | P0 |
| 实时画面 | HP60C/视觉运行时的 RGB 链 | WebRTC 编码、信令、健康门 | P0，先单手机 |
| 环境音 | XFM-DP 麦克风链 | 共享采集与 ASR 仲裁 | P0，需 spike |
| 按住喊话 | TTS/扬声器硬件 | 实时上行、互斥权、回声抑制 | P0 |
| 全双工通话 | 麦克风与扬声器 | WebRTC audio、AEC、ASR 暂停/恢复 | P0，先一对一 |
| 手动遥控 | 底盘速度源与运动仲裁候选 | App teleop 网关、短租约和 watchdog | P0，真车门槛高 |
| 房间导航 | `/navigate_to_room` | REST 任务适配与结果投影 | P0，按 capability 开放 |
| 巡逻 | `/patrol` | 任务 API、定时器、检查点合同 | P0；定时执行仍受安全门 |
| 回充 | `/auto_dock` | 任务 API、二次确认、反馈投影 | P0 |
| 停止 | `/stop_actions` 及 App 持有 goal 的取消 | 统一幂等停止入口 | P0，始终可用 |
| 地图 | `/map`、`/amcl_pose`、导航任务反馈 | 栅格转换、版本、房间目录 | P0 |
| 日程管理 | Schedule 领域服务与正式 DB | 更新/启停/确认状态 API | P0 |
| 视觉开关 | Visual Monitoring 应用服务 | App ingress | P0 |
| 工程诊断 | 多个 runtime health snapshot 与日志 | 脱敏聚合、导出格式 | P0，仅工程构建 |
| 家庭账号/权限 | 只有可信 actor 边界 | 完整账号、邀请、权限服务 | 家庭产品目标 |
| 公网通知/SMS | 无 | 云端推送与短信 provider | 家庭产品目标 |
| 九方视频 | 无 | SFU/房间服务、机器人屏幕客户端 | 家庭产品目标 |

## 5. 导航与运动接口事实

### 5.1 当前正式命令链

```text
NavigationSkill
  -> SkillResponse.metadata
  -> /duole/navigation_command
  -> navigation command action wrapper
  -> ROS Action
  -> /duole/navigation_command_status
  -> TaskCoordinator / DeviceStatus
```

Engineering V1 网关应接入产品级任务边界或等价的受控适配器，不应让 App 直接发布
`/duole/navigation_command`，更不能直接发布 `/cmd_vel`。

### 5.2 已知任务类型

| App 语义 | 当前 ROS/产品语义 | 备注 |
|---|---|---|
| `navigate_to_room` | `/navigate_to_room` | 使用稳定 room ID，不以中文显示名作为主键 |
| `navigate_to_pose` | Nav2 `/navigate_to_pose` | E1 不向普通页面开放任意坐标入口 |
| `patrol` | `/patrol` | 默认有限轮次；定时巡逻是新应用服务 |
| `dock` | `/auto_dock` | 二次确认，展示对接阶段 |
| `stop` | goal cancel + `/stop_actions` | 幂等、高优先级 |
| `come_here` | 遗留 `/navigate_to_wake_person` | 不作为 E1 普通按钮；新人员 Action 仍未产品开放 |
| `teleop` | 待新增受控速度源 | 必须经唯一运动 owner、watchdog 与安全上限 |

### 5.3 不得误报的能力

- mock Action 接受不代表真车移动；工程 UI 必须显示 `MOCK_NO_MOTION`。
- 命令发出不代表 goal 被接受；接受不代表执行成功。
- 地图 pose 陈旧时不得显示实时位置。
- 新 `/navigate_to_person`、自动靠近和重捕获当前保持关闭，不能提供“找人”按钮。
- 视觉可见不等于运动坐标可用；`tf_ready=false` 时仍必须禁止靠近。

## 6. 状态投影要求

App 不展示未经解释的原始 provider JSON。每项状态至少包含：

```json
{
  "key": "visual_monitoring",
  "health": "ok|degraded|unavailable|disabled|unknown",
  "summary": "视觉监护已开启",
  "reason_code": "ready",
  "updated_at": "2026-08-17T10:00:00+08:00",
  "stale": false,
  "affected_capabilities": []
}
```

人员视觉状态使用现有产品语义：

- `interface_not_deployed`
- `chain_fault`
- `no_user_visible`
- `coverage_degraded`
- `coverage_normal`

前端显示“画面中检测到一人”等事实，不改写为“老人正在客厅”或“老人平安”。

## 7. 当前明确不存在的基础设施

以下均需 Windows/App 与机器人端团队协作开发：

- App 可调用的 HTTP/OpenAPI 服务；
- 稳定 WebSocket 事件出口与事件补拉存储；
- mDNS 发现和本地配对服务；
- App 身份令牌；
- WebRTC 相机/音频媒体网关；
- 手动遥控租约和安全 watchdog；
- 日程 update/enable/confirmation 的 App 用例；
- Android App 工程；
- 家庭产品的云端账号、推送、短信和九方通话服务。

## 8. 实施时必须继续查阅的合同

- `docs/navigation_readme.md`
- `docs/interface_freeze/visual_monitoring_control_contract.md`
- `docs/interface_freeze/fall_event_contract.md`
- `docs/interface_freeze/person_presence_contract.md`
- `docs/interface_freeze/safety_alert_event_contract.md`
- `docs/interface_freeze/tts_face_output_contract.md`
- `docs/design/device_status_product_architecture.md`
- `docs/design/home_care_vision_product_architecture.md`
- `docs/SKILL_SDK.md`
