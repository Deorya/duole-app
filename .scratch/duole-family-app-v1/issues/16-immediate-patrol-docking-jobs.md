# 贯通即时巡逻与回充 Job

Status: needs-triage

Type: HITL

User stories covered: 107, 111–116

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

在已验证的 JobGateway 上增加即时有限轮次巡逻和主动回充两个完整产品任务。Android 只允许
选择已验证路线和合理轮次；回充明确展示会取消/替换当前运动任务并要求确认。两个任务复用
同一 motion owner、状态投影、取消和恢复机制。

## Acceptance criteria

- [ ] App 可从 verified patrol route 创建有限轮次 patrol job，rounds 有服务端上限且不开放无限循环。
- [ ] patrol 在创建前检查 map/localization、路线、battery、motion owner、privacy 和 safety gates。
- [ ] App 可创建 dock job，但必须先展示其对当前任务的影响并提交结构化确认。
- [ ] dock 不因命令发送成功显示完成；只有真实 docking Action 终态才映射 succeeded。
- [ ] patrol/dock 使用共享 TaskCoordinator 和正式 navigation adapters，job/request/command/goal identity 可追踪。
- [ ] 两类任务支持查询、事件恢复和幂等取消，终态不回退；App 重启不重复创建。
- [ ] capability 不满足时按钮禁用并显示稳定 gate reason，不创建假 job。
- [ ] safety、local privacy、stop 和更高优先级任务可以抢占，并给 App 可解释终态。
- [ ] Android 确认/进度/失败 UI、job contract、TaskCoordinator integration 和 wrapper/Action 测试通过。
- [ ] HIL/REAL 分别验证路线巡逻、主动回充、取消、抢占、低电量拒绝和真实终态。

## Blocked by

- [15 贯通房间导航 Job 创建、恢复、取消与终态](15-room-navigation-job-lifecycle.md)
