# 贯通定时巡逻、执行门禁与跳过结果

Status: needs-triage

Type: HITL

User stories covered: 108–110, 139

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

把定时自动巡逻作为 Schedule V2 的 `patrol` kind 交付完整闭环：用户在 Android 选择路线、
日期、时间、重复、轮次和启停；到点只生成 execution intent，再按当时机器人状态经过全部
安全门创建 patrol job，或记录带稳定原因的 `skipped_by_gate` occurrence。

## Acceptance criteria

- [ ] App 可创建、修改、启停和删除 once/daily/weekly 的 patrol schedule，并使用 Schedule revision 冲突保护。
- [ ] payload 只接受 verified route ID 和受限 rounds，不允许任意点位、坐标或导航参数。
- [ ] 到点执行前重新检查 map/localization、battery、motion owner、privacy、safety 和巡逻 capability。
- [ ] gate 通过时创建一个可追踪 patrol job，并在 occurrence 保存 job identity；失败不重复创建。
- [ ] gate 不通过时 occurrence 终态为 `skipped_by_gate`，包含稳定 reason，HTTP/调度器不把它当系统异常。
- [ ] schedule disabled、revision changed、机器人重启和时钟/时区边界不会执行旧 occurrence。
- [ ] 重复 scheduler tick、进程重启和事件重放保持幂等，不创建双份 patrol job。
- [ ] App 展示下一次执行、启停状态、最近 occurrence、skip reason 和关联 job 结果。
- [ ] 本地 stop/safety 在 patrol 启动后仍可抢占，scheduled 来源不获得更高 motion 优先级。
- [ ] 时间推进、DST/时区、scheduler restart、gate matrix、job integration、Android UI 和 HIL 测试通过。

## Blocked by

- [11 实现 Schedule V2、版本化 CRUD 与启停](11-schedule-v2-versioned-crud.md)
- [16 贯通即时巡逻与回充 Job](16-immediate-patrol-docking-jobs.md)
