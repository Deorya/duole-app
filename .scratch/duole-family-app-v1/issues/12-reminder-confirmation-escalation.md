# 实现提醒确认、稍后、跳过与升级结果

Status: ready-for-human

Implementation: paused-after-snooze-fix-2026-09-20

Acceptance: PARTIAL_HIL — 完成确认链路已通过真实机器人和 Android 验收；自然语言稍后提醒缺陷已完成软件修复，尚待重新 HIL。

Type: AFK

User stories covered: 133–140

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

在 Schedule V2 上交付 reminder occurrence 生命周期：机器人到点播报后记录 delivered，并接受
completed、snoozed、skipped 或 unconfirmed 结构化结果；需要确认的提醒按照默认或单项策略
重试和通知。Android 可查看同一结果和策略，但不读取原始语音。

## Acceptance criteria

- [x] 每次 reminder occurrence 有稳定 identity、schedule revision、计划/实际时间和状态时间线。
- [x] 状态至少覆盖 scheduled、delivered、snoozed、completed、skipped、unconfirmed 和 delivery_failed。
- [x] 需要确认的默认策略为到点播报、5 分钟未确认重试一次、15 分钟仍未确认形成家属通知事件。
- [x] 单项策略支持不通知、立即通知和自定义等待时间；普通提醒默认不升级。
- [x] 老人语音结果通过正式 workflow 写入同一 occurrence；重复识别/重试按稳定 identity 幂等。
- [x] App 只读取结构化 outcome、时间和原因，不暴露原始录音、ASR 全文或闲聊内容。
- [x] 机器人进程重启不会重复记录已成功播报 occurrence；失败播报按明确 retry policy 处理。
- [x] snooze 生成明确的新计划时间并保留原 occurrence 关系，不能静默修改主 schedule。
- [x] 升级事件进入统一 event projection，断线可补拉且不会因 source retry 重复通知。
- [x] Android occurrence/history UI、Schedule workflow、delivery ledger、event integration 和时间推进测试通过。

## Blocked by

- [06 实现持久事件投影、WebSocket 补拉与重同步](06-event-projection-replay-resync.md)
- [11 实现 Schedule V2、版本化 CRUD 与启停](11-schedule-v2-versioned-crud.md)

## Comments

### 2026-09-18 TDD 开发结果

Issue 12 的本地实现与软件验证完成，状态交由维护者确认；上方勾选均指软件验收，
不表示正式机器人或 Android 已部署、激活或通过 HIL。代码保留在两个源码工作树，
没有 stage、commit 或 push，既有 Issue 10/11 及其他 WIP 保留。

- Schedule V2 支持普通、默认需确认、不通知、立即通知和自定义等待策略。
  默认从首次成功送达起 5 分钟重试一次、15 分钟形成未确认通知；普通提醒保持原提前量且不升级。
- 原 delivery ledger 保存 revision 绑定的 occurrence、计划/实际时间、状态时间线及结构化原因。
  完成、跳过、稍后结果持久化并发幂等；稍后生成关联的新计划，不修改主 Schedule。
- 正式提醒 tick 和已有 Schedule Skill 共用同一 workflow。需要确认的提醒到点播报；
  多条待确认时不猜测目标，可用精确标题加结果选择。未知或无可靠回复不当作完成。
- 已成功落账的播放跨重启不重复；失败按 30 秒间隔、每个动作最多 3 次尝试，
  中断播放按 120 秒租约恢复并记录明确原因；迟到回调不能覆盖新 attempt。
- 日程停用、改期或删除会停止旧 revision 的未完成执行；迟到回复保留超时通知事实。
  UTC 语音上下文下的稍后计划和 App 历史统一按机器人当地时间呈现。
- 通知事实与到期结果同事务保存，投影线程写入现有 event projection，按稳定 source identity
  去重；Dart 复用既有事件补拉和 sequence 去重。未引入云推送或短信。
- OpenAPI 兼容 minor 升为 `3.1.0`，Dart consumer 重新生成；App 可编辑确认策略并查看
  当次策略、版本、实际送达、稍后关系及时间线。响应只使用结构化字段白名单。

本次验证（全部为软件证据）：

- 最终 Provider 相关回归：`367 passed`，涵盖 Schedule V2、时间推进、
  Runtime 装配、语音分派、旧提醒账本、IPC/HTTP、事件投影和合同；使用合成 SQLite。
- Provider contract audit、全部共享 fixtures 和 `3.0.0 → 3.1.0` compatibility gate 通过。
- Dart contract `30` 个测试入口、client `44` 个测试入口通过，合计 `74` 个。
- Flutter 全量 `119 passed`；随后仅增加冲突刷新行为覆盖及原因文案，最终日程页/编辑页
  `23 passed`。两组有重叠，不相加为用例总数。
- Dart contract、client 和 Flutter 静态分析均 `No issues found`；本次增量空白检查通过。

实现、策略值、恢复语义和协议说明见
[provider Issue 12 说明](../../../../duole-workspace/docs/interface_freeze/app_v1/issue_12_reminder_confirmation.md)。

验收边界：未访问或迁移正式业务数据，未构建/登记/安装候选、部署、启动产品会话或更新 selector。
真实 TTS、语音识别、设备重启与 Android 补拉仍需在 Issue 11 正式迁移及相应授权后，经正式板端
入口另行验收。播放器已发声但成功事实尚未落账就崩溃时，按明确的未知播放重试策略处理；
软件结果不代表物理播放 exactly-once。Issue 10 已延期的问题不在本轮扩展处理。

### 2026-09-20 暂停点与恢复说明

本轮已将 Issue 12 候选安装到 Android，并通过正式板端入口连接真实机器人。到点播报、
5 分钟自动重试、老人回复“我完成了”、机器人回复“已记录完成”以及 App 结构化历史均已通过；
同一 occurrence 保持稳定 identity，App 未显示原始 ASR 文本。

真实稍后提醒验收发现自然表达缺口：存在唯一待确认提醒时，“5分钟后提醒我”和
“稍后 5 分钟再提醒我一下”未被识别为当前提醒的 snooze，而是落入新建提醒对话并再次询问内容。
TDD 已先复现 `owns_pending=False` 的失败，再扩展结果解析：忽略语句内空白，接受“分钟后”、
可选“再”和“提醒我一下”。修复只在 reminder workflow 存在待确认 occurrence 时取得对话所有权，
不改变无待确认上下文中的普通新建提醒语义。

修复后的 Provider 验证：`tests/runtime/test_reminder_occurrence_integration.py` 为 `13 passed`；
`tests/runtime/test_schedule_voice_runtime_text_bridge.py` 与
`tests/skills/test_reminder_confirmation.py` 合计 `35 passed`。本次暂停前没有把修复重新装入候选，
因此不得将自然语言稍后、child occurrence 再次播报、跳过、未确认升级或事件补拉称为 HIL 通过。

恢复开发时从以下门槛继续：

1. 从已提交 Provider 修复构建新的不可变 HIL 候选，并记录源码与候选 SHA-256。
2. 在唯一待确认提醒上用真实语音说“5分钟后提醒我”，确认机器人不询问内容，原 occurrence
   写入 `snoozed`，并生成保留 parent/child 关系且不修改主 Schedule 的 5 分钟计划。
3. 验证 child 到点播报及“跳过这次”；验证进程重启不重复播报已经成功落账的动作。
4. 验证 `unconfirmed` 升级进入 event projection，Android 断线后可补拉且 source retry 不重复通知。
5. 清理本轮测试日程，归档脱敏日志、App 截图、版本和哈希，再决定是否关闭 Issue 12。

暂停时产品语音会话和 App Gateway 均已停止。Android 上仍是本轮 HIL APK；正式 Schedule 数据库中
保留测试日程 `schedule-b9de712010b54ac4b277988e2eed1b66`（完成路径）与
`schedule-2855df97d48a47fcb00049148a96b2dc`（稍后路径），恢复时需先核对实际 occurrence 状态再处理，
不得假定停机期间发生过重试或升级。
