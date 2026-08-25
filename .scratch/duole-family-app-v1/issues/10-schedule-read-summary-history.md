# 贯通日程只读、今日摘要与执行记录

Status: needs-triage

Type: AFK

User stories covered: 122, 128–129, 131, 139–140

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

交付第一个 Schedule 纵向只读切片：Android 日程页通过网关和正式运行时门面读取现有正式
Schedule 服务，显示照护对象时区下的今日/范围列表、下一次提醒、来源和已有执行记录。网关
不得直接读取 SQLite，也不暴露原始语音录音或闲聊文本。

## Acceptance criteria

- [ ] App 能读取今日、指定日期和受控范围内的真实日程，并显示稳定 schedule ID、标题、时间、来源和下一次 occurrence。
- [ ] 首页今日摘要与日程页来自同一正式 Schedule 应用边界和持久化事实。
- [ ] 网关/公网关进程没有正式 DB 文件权限或 repository 直连；所有读取经 in-runtime domain facade。
- [ ] 时间统一使用照护对象时区，并在异地设备上明确机器人当地时间语义。
- [ ] 已有 reminder delivery ledger/occurrence 信息通过结构化 DTO 呈现；缺失能力明确标记而不造数据。
- [ ] 响应不包含原始录音、ASR 全文、闲聊内容、内部 DB path 或不受控 metadata。
- [ ] 空列表、无效日期、时区边界、陈旧投影、服务超时和 formal DB 不可用都有稳定 UI/error 状态。
- [ ] 语音查询和 App 查询在相同时间条件下看到同一组 schedule identity。
- [ ] 覆盖 Schedule service adapter、IPC、REST contract、projection summary 和 Android list/detail 测试。

## Blocked by

- [04 实现一次性配对、安装实例绑定与撤销](04-pairing-session-revocation.md)
- [05 实现一致能力快照与机器人状态页面](05-capability-snapshot-robot-status.md)
