# 实现 Schedule V2、版本化 CRUD 与启停

Status: ready-for-human

Type: HITL

User stories covered: 123–132

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

把当前轻量日程模型升级为由领域层拥有的一等 Schedule V2，并交付 Android 新增、修改、删除、
启用和停用的完整切片。App 与机器人语音必须调用同一版本化应用用例；正式 SQLite schema
migration、备份和回滚需由 Schedule owner 人工评审后执行。

## Acceptance criteria

- [x] 领域模型明确拥有 kind、title、enabled、timezone、start、once/daily/weekly recurrence、confirmation policy、typed payload、revision、actor 和时间戳。
- [x] repository migration 有版本号、完整性检查、dry-run、备份、失败回滚和旧数据兼容读取策略。
- [x] App 可创建 reminder schedule，并在机器人正式服务中生成稳定 ID/revision；发送成功不冒充落库成功。
- [x] App 可基于 If-Match/revision 修改、启用、停用和删除，响应返回新 revision 与结构化影响。
- [x] 语音端改为调用同一 Schedule V2 application use case，不维护平行 CRUD 或 revision。
- [x] App 与语音基于同一旧 revision 并发修改时只有一个成功，另一方收到可刷新 `REVISION_CONFLICT`。
- [x] recurrence V1 仅支持 once/daily/weekly；不支持规则不会写入 metadata 后假装成功。
- [x] App 修改无需老人再次确认，但可触发机器人端受控结构化告知；告知失败不回滚已经成功的业务写。
- [x] 所有写请求校验 actor、scope、TTL、idempotency 和字段白名单；重复请求返回原资源。
- [x] App UI 覆盖表单校验、保存 pending、冲突刷新、启停、删除确认和后端错误。
- [x] migration、SQLite 原子性、voice/App 并发、REST/IPC contract 与 Android consumer 测试通过。

## Blocked by

- [01 冻结最小 App 合同与兼容性工具链](01-freeze-minimal-app-contract.md)
- [10 贯通日程只读、今日摘要与执行记录](10-schedule-read-summary-history.md)


## Comments

### 2026-09-18 TDD 开发结果

Schedule V2、SQLite schema 2 → 3 离线迁移、App CRUD/启停、语音共用写用例以及 UI 已合入本地
源码工作树；未 stage/commit/push。已保留 Issue 10 及其他既有 WIP。上方勾选表示**软件验收**，
不表示正式库已迁移、服务已激活或真机验收已完成。

- 领域层持有 reminder 的 typed payload、IANA timezone、once/daily/weekly、revision、actor 和
  timestamps；confirmation policy 仅 `none`，策略扩展属于 Issue 12。
- 原 `schedule_items` 是唯一 Schedule store；同一 SQLite 事务执行 CAS 并保存幂等响应，重启
  后可重放原资源/ETag/envelope。App/voice 竞争修改只有一个成功，语音预确认携带原 revision。
  语音批量删除、日期限定取消同样版本化，任一冲突整批回滚。
- 迁移具备 dry-run、完整性检查、一致备份、旧行转换验证和事务失败回滚。保留旧来源/取消记录；
  更新同步旧语音时间投影。V2 过期定义保留供历史查询，停用项仍可管理但不触发提醒。
- Gateway 经既有 IPC 调用 owner；全部写入受 actor/scope/TTL/idempotency/白名单及安装实例签名
  约束。PATCH/DELETE 的 `If-Match` 与已签名 body revision 必须一致。
- App 表单覆盖校验、weekly 星期选择、保存 pending、冲突刷新、启停、删除确认和后端错误。
  未确认写入保留相同请求/幂等键，未知规则禁止编辑。只有 `schedule.write` 会话展示管理入口。
- 可选告知为提交后受控结构化 callback，失败不回滚，重试不重复调用。默认 runtime 没有播放
  sink，明确返回 `unavailable`，App 默认不请求告知；未宣称机器人已播报。
- OpenAPI 升为 **3.0.0**。冻结路径、capability 和必需签名操作清单变更触发现有 major gate；
  没有放宽安全/兼容检查。Dart consumer 由 provider OpenAPI 重新生成，旧主版本连接仍拒绝。

本次软件验证：

- Provider 在隔离源码与合成 SQLite 上的 Schedule/对话/提醒/runtime/Gateway/IPC/TLS/contract
  回归：`744 passed`；两条 warning 来自既有旧 TLS 版本拒绝测试。
- 合入实际源码后，V2/Gateway/模块预算回归 `95 passed`；旧语音时间投影修复后的 V2 回归
  `45 passed`。签名操作清单补齐后 provider contract `41 passed`。
- Provider contract audit/fixtures、`2.0.0 → 3.0.0` compatibility gate 及 Dart 生成一致性通过。
- Dart consumer 与 client 共 `73` 个测试入口通过；最终合同的 request metadata 与写入 fixture
  测试再次通过。
- Flutter 全量首次 `111 passed / 1 failed`，唯一失败为连接页仍期待 `API 2` 的旧显示断言；
  同步为 `API 3` 后，连接页全部 `13` 项通过。新增编辑页 `6` 项通过。
- Dart contract、client、Flutter 三个 package 静态分析均 `No issues found`；两个源码仓库
  `git diff --check` 通过。
- Android 本地 APK 构建：**未通过（环境限制）**。ARM64 主机默认 Maven AAPT2 无法启动；
  指定已有 ARM64 AAPT2 后，资源处理继续通过，但 NDK `28.2.13676358` 的
  `linux-x86_64/bin/clang` 报 `Exec format error`，阻塞 `configureCMakeDebug[arm64-v8a]`。
  未更换项目 NDK、跳过 native 检查或把旧 APK 当作本次产物；需在支持该 NDK 的构建主机重建。
- 迁移 CLI 默认 dry-run 在合成 schema 2 数据库验证通过；未读取或迁移正式 Schedule 数据。

迁移步骤、回退边界和 REST 用法见
[provider Issue 11 操作说明](../../../../duole-workspace/docs/interface_freeze/app_v1/issue_11_schedule_write.md)。

剩余人工门槛：Schedule owner 评审离线迁移和备份/回退点，并另行明确授权正式数据访问、
迁移、配套 runtime/App 部署以及 Android/语音并发写入真机验收。当前未执行设备安装、
部署、激活、selector 更新或 HIL。可选告知实际播放须接入受控 sink 后另行验收。

### 2026-09-19 正式迁移与候选结果（HIL 前）

维护者已授权继续处理此前列出的正式迁移、Runtime/App 部署和 HIL 阶段。以下记录当时完成的
不依赖真人到场工作；随后完成的 HIL 见下一条评论：

- 正式 Schedule 数据库在所有 writer 停止、文件无占用且 dry-run 通过后，从 schema 2 迁移
  至 schema 3。迁移前共有 0 条日程；一致性备份保持 schema 2，迁移后正式库及备份均重新
  通过完整性/转换预览。
- 从共享工作树隔离出纯 Issue 11 的 App/Provider 候选，完整反向移除 Issue 12 改动，合同均为
  API `3.0.0`。Provider 候选已登记但未启动，正式库装配 preflight 通过。
- ARM64 debug APK 构建成功，version `2014 / 0.1.0-issue11-schedule-v2`，ZIP、签名和 manifest
  校验通过。此前记录的本机构建限制已消除。
- 隔离 Provider 相关回归首轮 `144 passed / 13` 个环境失败；允许 Unix socket 并提供正式库
  哈希一致的候选快照后，失败相关文件重跑 `64 passed`，全部通过。
- Android 目标改以 `172.22.205.14:39321` 上线；已备份 version 2013，保留 App 数据覆盖安装
  version `2014 / 0.1.0-issue11-schedule-v2`。设备回拉 APK 与候选 SHA-256 完全一致。
- 此阶段正式产品会话和 HIL 尚待人员到场，因此当时未勾选“App 在机器人正式服务中生成稳定
  ID/revision”；该项已在下一阶段完成。

详细路径、哈希、迁移结果和验证边界见
[2026-09-19 证据](../../../docs/evidence/issue11/20260919/README.md)。

### 2026-09-19 正式 HIL 完成

人员到场后已从正式板端入口启动纯 Issue 11 候选，机器人运动、导航、视觉链和提醒执行保持
关闭。Android 新配对会话获得 `robot.status.read` 与 `schedule.write`，完成如下真实链路：

- App 创建 `Issue11HIL`，正式服务返回稳定 ID
  `schedule-66f0a3a375bf4f589dc6ba4ff46ef224` 和 revision `1`。
- App 保持 revision `1` 编辑快照时，真人经 reSpeaker 把同一日程从 `10:30` 改到 `11:00`
  并语音确认；刷新后资源为 revision `2`。
- App 随后提交旧 revision `1`，收到可刷新的冲突提示且不能覆盖；刷新准确载入 revision `2`
  及语音写入的 `11:00`。
- App 基于 revision `2` 更新标题，重新进入页面确认 revision `3`，随后确认删除。最终正式库
  schema 为 `3`、生效日程数为 `0`；Runtime/Gateway 已退出，端口和 socket 均清理。

至此所有 acceptance criteria 均有软件验证或真实设备证据。仓库状态词表没有 `done/closed`，
因此保留 `ready-for-human` 字面状态，不将已完成工单误标为 `wontfix`；本工单已无剩余人工门槛。
完整运行参数、候选/数据库哈希和语音记录见上方证据链接。

### 2026-09-19 Issue 10/11 合并代码提交归档

Issue 10 与 Issue 11 的共享 API `3.0.0`、生成 consumer、Runtime facade 和 Schedule V2 投影
按一个原子代码快照提交：App 为 `04aed9da2aac1812f77a73bdc9f2d638b9b37058`，Provider 为
`a10846139f591a73daa2325e0b6acf7c0ee94f33`。证据与工单记录另行提交，未夹带 Issue 12、
Issue 33 或其他工作区改动。本次提交整理没有再次部署、迁移正式库或执行 HIL；上方既有
Issue 11 真机 PASS 仍是对应候选的验收依据。

### 2026-09-19 代码审查延期决定

对 App `04aed9da2aac1812f77a73bdc9f2d638b9b37058` 与 Provider
`a10846139f591a73daa2325e0b6acf7c0ee94f33` 的 Issue 11 代码审查未发现 P0。维护者决定将以下
2 个 P1、3 个 P2 记录为后续缺陷，暂缓修复，不重新打开或阻塞 Issue 11：

- **P1**：大量已过期的 V2 定义可能占满提醒扫描上限，使 ID 排序靠后的到期提醒被静默漏扫；
  位置：`duole_central/skills/schedule/services/service.py`。
- **P1**：已投递的一次性提醒改期后沿用原 occurrence key，delivery ledger 可能把新时间的提醒
  判为已投递而不再触发；位置：`duole_central/skills/schedule/application/occurrence_projection.py`。
- **P2**：旧数据中“每周某日晚上十二点”迁移到次日 `00:00` 后仍保留原 weekday，首次周实例
  会偏移；位置：`duole_central/skills/schedule/infrastructure/sqlite_repository.py`。
- **P2**：语音把 recurring 日程改为具体日期时可能保留旧 recurrence，导致次日继续生成实例；
  位置：`duole_central/skills/schedule/application/service.py`。
- **P2**：日程页打开期间会话自动刷新后，读取会切到新连接，但写入 manager 仍引用已关闭的旧
  transport，当前页面的修改可能持续失败；位置：`lib/features/connection/connection_page.dart`。

上述问题均不改变本工单既定验收范围及已经完成的软件验证和 HIL 结果。Issue 11 按维护者设定的
“无 P0 即可完成”门槛视为完成；由于仓库状态词表没有 `done/closed`，字面状态继续保留
`ready-for-human`。后续排期修复时应拆为独立缺陷工单，并为对应复现场景补充回归测试。
