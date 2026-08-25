# 实现 Schedule V2、版本化 CRUD 与启停

Status: needs-triage

Type: HITL

User stories covered: 123–132

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

把当前轻量日程模型升级为由领域层拥有的一等 Schedule V2，并交付 Android 新增、修改、删除、
启用和停用的完整切片。App 与机器人语音必须调用同一版本化应用用例；正式 SQLite schema
migration、备份和回滚需由 Schedule owner 人工评审后执行。

## Acceptance criteria

- [ ] 领域模型明确拥有 kind、title、enabled、timezone、start、once/daily/weekly recurrence、confirmation policy、typed payload、revision、actor 和时间戳。
- [ ] repository migration 有版本号、完整性检查、dry-run、备份、失败回滚和旧数据兼容读取策略。
- [ ] App 可创建 reminder schedule，并在机器人正式服务中生成稳定 ID/revision；发送成功不冒充落库成功。
- [ ] App 可基于 If-Match/revision 修改、启用、停用和删除，响应返回新 revision 与结构化影响。
- [ ] 语音端改为调用同一 Schedule V2 application use case，不维护平行 CRUD 或 revision。
- [ ] App 与语音基于同一旧 revision 并发修改时只有一个成功，另一方收到可刷新 `REVISION_CONFLICT`。
- [ ] recurrence V1 仅支持 once/daily/weekly；不支持规则不会写入 metadata 后假装成功。
- [ ] App 修改无需老人再次确认，但可触发机器人端受控结构化告知；告知失败不回滚已经成功的业务写。
- [ ] 所有写请求校验 actor、scope、TTL、idempotency 和字段白名单；重复请求返回原资源。
- [ ] App UI 覆盖表单校验、保存 pending、冲突刷新、启停、删除确认和后端错误。
- [ ] migration、SQLite 原子性、voice/App 并发、REST/IPC contract 与 Android consumer 测试通过。

## Blocked by

- [01 冻结最小 App 合同与兼容性工具链](01-freeze-minimal-app-contract.md)
- [10 贯通日程只读、今日摘要与执行记录](10-schedule-read-summary-history.md)
