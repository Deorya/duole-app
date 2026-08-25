# 实现提醒确认、稍后、跳过与升级结果

Status: needs-triage

Type: AFK

User stories covered: 133–140

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

在 Schedule V2 上交付 reminder occurrence 生命周期：机器人到点播报后记录 delivered，并接受
completed、snoozed、skipped 或 unconfirmed 结构化结果；需要确认的提醒按照默认或单项策略
重试和通知。Android 可查看同一结果和策略，但不读取原始语音。

## Acceptance criteria

- [ ] 每次 reminder occurrence 有稳定 identity、schedule revision、计划/实际时间和状态时间线。
- [ ] 状态至少覆盖 scheduled、delivered、snoozed、completed、skipped、unconfirmed 和 delivery_failed。
- [ ] 需要确认的默认策略为到点播报、5 分钟未确认重试一次、15 分钟仍未确认形成家属通知事件。
- [ ] 单项策略支持不通知、立即通知和自定义等待时间；普通提醒默认不升级。
- [ ] 老人语音结果通过正式 workflow 写入同一 occurrence；重复识别/重试按稳定 identity 幂等。
- [ ] App 只读取结构化 outcome、时间和原因，不暴露原始录音、ASR 全文或闲聊内容。
- [ ] 机器人进程重启不会重复记录已成功播报 occurrence；失败播报按明确 retry policy 处理。
- [ ] snooze 生成明确的新计划时间并保留原 occurrence 关系，不能静默修改主 schedule。
- [ ] 升级事件进入统一 event projection，断线可补拉且不会因 source retry 重复通知。
- [ ] Android occurrence/history UI、Schedule workflow、delivery ledger、event integration 和时间推进测试通过。

## Blocked by

- [06 实现持久事件投影、WebSocket 补拉与重同步](06-event-projection-replay-resync.md)
- [11 实现 Schedule V2、版本化 CRUD 与启停](11-schedule-v2-versioned-crud.md)
