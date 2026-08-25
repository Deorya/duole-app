# 贯通房间导航 Job 创建、恢复、取消与终态

Status: needs-triage

Type: HITL

User stories covered: 106, 112–116

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

让 Android 从已验证房间选择目标并创建一个产品级 navigation job，经正式运行时内同一个
TaskCoordinator 申请 motion、调用现有导航 command/action adapter，再把接受、反馈、取消和
真实终态投影回 App。页面离开或 App 重启后按 job ID 恢复，不重新提交动作。

## Acceptance criteria

- [ ] App 只能从当前 map revision 的 verified room ID 创建 `navigate_to_room` job，不接受任意 pose/Action/ROS 参数。
- [ ] 创建请求校验 scope、TTL、idempotency、capability revision 和当前定位/地图/安全门。
- [ ] motion claim 必须进入正式运行时共享 TaskCoordinator；测试证明没有第二个 owner/state machine。
- [ ] 接受后立即返回稳定 job ID，并保存 request、actor、task、navigation command 和 goal identity 映射。
- [ ] job 状态覆盖 queued、accepted、running、succeeded、failed、canceled，终态不能回退。
- [ ] wrapper/Action status 只有 command identity 匹配时才能更新 job；旧结果不能清除替代任务。
- [ ] motion busy、runtime external/stale、定位陈旧、地图不匹配和 safety inhibit 在创建前稳定拒绝，不生成永久 queued job。
- [ ] App 可幂等取消 job，并区分 cancel accepted、canceling 和真实 canceled/failed 终态。
- [ ] App 页面离开、进程重启和事件断线后按 job ID 恢复活动状态，不重复创建目标。
- [ ] 本地安全/隐私/stop 抢占时 job 收到稳定 canceled/failed reason，UI 不显示成功。
- [ ] SIM、HIL 和低速 REAL 验证真实房间到达、拒绝、取消、重连和陈旧 status 场景。

## Blocked by

- [13 实现地图、机器人位姿、房间与巡逻路线只读视图](13-map-pose-rooms-routes-readonly.md)
- [14 实现独立紧急停止与机器人停止确认](14-emergency-stop-confirmation.md)
- [35 贯通受监督自主探索建图与自动回桩](35-supervised-autonomous-mapping-docking.md)
