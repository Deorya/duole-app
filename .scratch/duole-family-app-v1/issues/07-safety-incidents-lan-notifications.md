# 实现安全事故时间线与局域网通知

Status: needs-triage

Type: AFK

User stories covered: 44–65

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

把现有 Safety、VisionFall 和 care-affecting device facts 投影成 App 可理解的事故生命周期，
并在 Android 中交付活动事故列表、详情时间线、查看现场/拨号/联系人动作以及 Engineering V1
在线局域网通知。App 使用机器人端给出的 observing、attention、emergency 语义，不读取原始
概率重新判定。

## Acceptance criteria

- [ ] valid safety/fall source 能创建、更新和关闭稳定 incident；fall v2 detection/recovery 保留 incident identity/revision。
- [ ] observing、attention、emergency 由机器人 workflow/projector 产出，App 不包含阈值或 raw-score 决策逻辑。
- [ ] invalid/legacy fall 只产生受限 diagnostic notice，不能创建活动紧急事故。
- [ ] Android 展示活动/历史事故、发生时间、最新状态、证据新鲜度和完整结构化时间线。
- [ ] 点击通知先进入事故详情，不自动启动摄像头或环境音。
- [ ] 详情提供查看现场、拨打老人和联系紧急联系人入口；不可用能力有稳定原因。
- [ ] “已查看”与“已关闭/已处置”严格分离；V1 不实现事故认领、家庭分工或群聊。
- [ ] Engineering V1 仅在 App/event channel 在线时尽力触发本地 Android 通知，并在 UI 明确不保证离网送达。
- [ ] 影响照护能力的持久设备故障可形成合并通知；短暂故障和自动恢复进入记录而不反复打扰。
- [ ] 重复、乱序、断线补拉和 App 重启不会重复通知同一 source revision 或让 closed incident 重新 active。
- [ ] 覆盖 safety/fall adapter、incident projector、REST/WS、Android UI 与通知 consumer 的端到端测试。

## Blocked by

- [06 实现持久事件投影、WebSocket 补拉与重同步](06-event-projection-replay-resync.md)
