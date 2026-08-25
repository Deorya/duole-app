# 多乐守护 App 开发交接包

Status: `ready-for-human`

需求冻结日期：`2026-08-17`

适用仓库：`/home/ztl/duole-app`

## 1. 这套文档解决什么问题

本目录是独立 App 仓库中的产品需求与设计上下文。App 源码位于同仓库的 `dart/` 与
`flutter/`；本目录不包含 APK、机器人运行配置或云端实现。

文档明确区分两个层次：

| 层次 | 使用者 | 网络范围 | 目的 |
|---|---|---|---|
| `Engineering V1` | 一批工程师 | 与机器人同一局域网 | 尽快获得可操作、可诊断的 Android App |
| `Family Product` | 单个家庭的家属/主要照护者 | 后续公网安全接入 | 完整的家庭照护、通知、权限和远程陪伴产品 |

`Engineering V1` 是近期实施范围；`Family Product` 是产品目标，不得被写成当前已交付能力。

## 2. 阅读顺序

1. [PRD.md](PRD.md)：产品目标、范围、需求和非目标。
2. [FUNCTION_INVENTORY.md](FUNCTION_INVENTORY.md)：机器人现有功能、成熟度与 App 缺口。
3. [INFORMATION_ARCHITECTURE.md](INFORMATION_ARCHITECTURE.md)：导航结构、页面清单和页面级规格。
4. [UX_FLOWS.md](UX_FLOWS.md)：配对、直播、遥控、导航、日程和事件流程。
5. [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)：多乐守护的颜色、字体、组件和文案规则。
6. [DATA_PRIVACY_PERMISSIONS.md](DATA_PRIVACY_PERMISSIONS.md)：家庭模型、细粒度权限、隐私和留存。
7. [ENGINEERING_V1_ARCHITECTURE.md](ENGINEERING_V1_ARCHITECTURE.md)：本地网关、数据流、媒体和运动安全架构。
8. [API_CONTRACT.md](API_CONTRACT.md)：建议的 REST、WebSocket 和 WebRTC 接口合同。
9. [ACCEPTANCE_AND_HANDOFF.md](ACCEPTANCE_AND_HANDOFF.md)：Windows 交接、验收矩阵与技术预研。
10. [DECISION_LOG.md](DECISION_LOG.md)：本轮访谈中已经确认的产品决策。

## 3. 权威顺序

发生冲突时按以下顺序处理：

1. 当前 App 代码与自动化测试；
2. API 提供方发布的机器可读 OpenAPI、fixture 和版本策略；
3. 本目录中的 App 产品需求、交互设计和客户端架构；
4. 标记为 proposal 的建议接口与未来范围。

本交接包可以提出新接口，但不能静默覆盖既有的隐私锁、运动仲裁、事件身份或正式 ROS
合同。发现冲突时，Windows 团队应先记录差异，再由机器人端负责人确认。

## 4. 交接方式

克隆独立 App 仓库即可获得本目录和 App 源码，不再从机器人仓库手工复制。开发团队仍需从
API 提供方以只读方式获取下列机器人端事实源：

- `README.md`
- `development_progress.md`
- `docs/navigation_readme.md`
- `docs/design/home_care_vision_product_architecture.md`
- `docs/design/device_status_product_architecture.md`
- `docs/interface_freeze/visual_monitoring_control_contract.md`
- `docs/interface_freeze/fall_event_contract.md`
- `docs/interface_freeze/person_presence_contract.md`
- `docs/SKILL_SDK.md`

## 5. 核心术语

| 术语 | 含义 |
|---|---|
| 机器人端 | RK3588 语音/视觉板、导航板及其现有 ROS/业务运行时 |
| App 网关 | 部署在机器人端、面向 App 的本地 HTTP/WebSocket/WebRTC 边界 |
| 任务 | 有稳定 `job_id`、状态、结果和取消语义的导航或巡逻操作 |
| 事件 | 有稳定 `event_id`/`incident_id`、来源和状态的安全或设备事实 |
| 监护状态 | 相机、视觉链、人员覆盖和隐私策略的诚实投影，不等于“老人一定平安” |
| 工程模式 | 仅工程构建可见的诊断界面；家庭产品构建必须隐藏 |
