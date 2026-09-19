# Issue 10 正式入口日程只读 HIL

2026-09-18，Asia/Shanghai。当前工单结论：**PARTIAL_PASS**；后续归档读取、配对凭证续期后
日程旧连接修复已完成软件验证。18:51 已覆盖安装含续期修复的 App `2013` 并校验设备包，
但未启动机器人端归档新实现或进行这两项的真机功能复验，见文末补记。17:37 的 **PASS**
仍是当时版本、当时已测场景的结论。
修复后的远期、跨午夜列表/详情、下一次提醒以及真实语音/App 对照已通过，见第三阶段。
测试提醒已删除，正式库和 IPC 为空、App 详情失效正确；列表最终刷新为空已由第四阶段补齐。
确认阶段语音截句已按用户后续决定延期，待其他功能落地后处理，不阻塞本阶段日程只读
功能验收；本轮只补齐列表刷新复验。午夜/5页同音误识别、既有唤醒卡住问题仍未根治，
不宣称整机语音稳定性或全部验收通过。文件权限隔离尚未修复，用户已明确同意延期，
不阻塞开发阶段功能验收，也不代表安全验收通过。

## 第一、二阶段对象与边界

- 正式入口：Provider `scripts/start_product_voice_board_session.sh`，reSpeaker XVF3800
  麦克风及扬声器；robot ID `rb_rk3588_01`，Runtime identity `REAL`、API `3.0.0`。
- Xiaomi `23043RP34C`，serial `41f736f9`，ADB `172.22.205.14:37301`。
- 用户确认现场就绪，授权配套 App 安装、重新配对和只读语音验收。第一阶段不增删改日程；
  随后用户另行授权通过正式语音创建一条 9 月 19 日 15:00 的测试提醒并在验收后删除该条。
- APK 安装成功：`2011 / 0.1.0-issue11-review`；SHA-256
  `5aa159c748b523526793357b16ac118993100213143447ac13d2975685ba8105`。
  API 3 来自已在共享工作树中的 Issue 11；本轮没有执行其 schema 迁移、App 写入或并发写入 HIL。
- 回退 APK `2008` 已从设备拉取至 `/tmp/issue10-hil-20260918.7cPhPh/rollback-2008.apk`，
  SHA-256 `94252a8dd321d60a838bb6afb3cdcaa06cc094657dab5a754bba97218b18ad40`。
- App 基线 `43296141f0cd2efb69a8bf895a05ca84e92977bd`，Provider 基线
  `6f7f9980e7e1a472b4cd1e43eaf1c99ba68c63ad`；实际运行其上的未提交共享工作树。
  本轮未修改产品源码或其他人的 WIP，基线 commit 不代表候选源码版本。

网关仅绑定 `172.22.205.44:8444`，禁用发现，配对仅授予 `robot.status.read`。
TLS 指纹为 `sha256:5db24e2a9c5a416776ae6d23c13fece229116747e1f712394bc94ed957a474f8`。
手机原有另一个身份 `DUOLE-RK3588-ENG-01` 占用 `8443`，其记录保持不变。
只重置 `rb_rk3588_01` 的旧信任、密文凭证和游标，原 XML 保留在 App 私有
`files/issue10-pairing-backup-20260918/`。新指纹经 UI 完整核对，正常一次性配对成功。
证书与网关状态留在 owner-only `/home/ztl/.local/share/duole-hil-state/issue10-20260918/`；
本证据不包含密钥、令牌或配对码。

## 第一阶段：空数据场景

1. 启动前 Schedule schema `2`，`quick_check=ok`，`schedule_items=0`。
   历史组件 HIL 的旧日程已经不在库中，本轮没有恢复或合成数据。
2. 正式入口使用 `--microphone-profile respeaker --no-navigation --no-visual-chain
   --no-reminder`，保持既有音频/安全阈值。既有 `--expected-formal-db-sha256` 预检模式
   同时跳过日程过期清理；正式服务的连接不冒称为 SQLite `mode=ro`。
3. 同一 Runtime IPC `getSchedules(date=2026-09-03)` 返回 `items=[]`、
   `timezone=Asia/Shanghai`、`stale=false`，history availability `available`。
4. Android 今日及日期选择器选择 9 月 3 日均显示“这一天没有日程”，无管理入口。
   [真实设备截图](schedule-empty.png)。
5. 15:34:28 成功轮次：ASR 文本“9 月 3 号有什么日程？”，回答“没有找到相关日程。”
   用户确认实际听到“我在”和查询回答。指标为 `accepted=true`、`error=null`、
   `wakeword_detected=true`、`wakeword_ack_succeeded=true`、`asr_used=true`、
   `tts_hardware_used=true`、`dialogue_status=read_ready`、`wrote_db=false`、
   `wrote_formal_db=false`、`audio_retained=false`。ASR 文本没有年份，不将空结果视为
   同一非空 ID 或完整日期解析一致性的证据。
6. 会话按 600 秒上限自动结束，`turns=1`、board report `ok=true`。网关随后主动停止；
   `8443/8444` 不再监听，Runtime socket 已移除。

仅第一阶段前后业务库 SHA-256 相同：

| 文件 | SHA-256 |
| --- | --- |
| `schedule.sqlite3` | `57281c165c97e2bf70a09e3bce1818f177e51ab3020bb8a08aa43ff4dc4c1249` |
| `schedule.reminder-deliveries.sqlite3` | `f012211a6b964496f4b623d651a050bbc8cfd64257f723a06814d3bd039a307b` |

## 第二阶段：非空日程、语音对照与清理

继续使用相同正式入口、目标设备、TLS 身份和仅 `robot.status.read` 的 App 会话。
开启现有正式语音写入用于用户授权的单条测试数据准备/清理，不传第一阶段的 DB hash 预检参数；
保持 `--no-navigation --no-visual-chain --no-reminder`，没有迁移数据库或开放 App 写权限。

1. 15:41:59，用户通过 reSpeaker 麦克风对话并说“确认保存”，正式服务保存测试提醒。
   实际标题是“19号做验收测试”；不为匹配预期措辞而改名。
2. 同一 Runtime 的 `getSchedules(date=2026-09-19)` 与
   `getSchedules(start_date=2026-09-18, end_date=2026-09-20)` 均只返回这一条。
   `getSchedule` 和 Android 列表/详情具有以下相同字段：

   | 字段 | 实测值 |
   | --- | --- |
   | schedule ID | `schedule-dialogue-1789717176465-1` |
   | title | `19号做验收测试` |
   | scheduled_at | `2026-09-19T15:00:00+08:00` |
   | timezone / source | `Asia/Shanghai` / `voice` |
   | next occurrence ID | `schedule-dialogue-1789717176465-1` |
   | next occurrence time | `2026-09-19T15:00:00+08:00` |
   | availability / stale | `available` / `false` |
   | history | `available`，`occurrences=[]`；UI 为“暂无执行记录” |

   截图：[非空列表](schedule-positive-list.png)、[非空详情](schedule-positive-detail.png)。
   提醒循环关闭，不通过制造投递记录来满足详情验收。
3. 15:43:36 后第一次非空会话停止更新等待唤醒日志，用户报告无法唤醒。
   15:47 检查时进程仍在、主线程等待 `poll`，麦克风数据指针没有正常推进；
   支持采集/唤醒等待卡住的判断，但未定位完整根因。用户明确回复“重启”后，仅重启语音会话。
   15:48:23 新会话开始监听，采集指针与 30 秒等待日志恢复更新。
   网关、配对、测试记录保持不变，重启前后业务库 hash 相同。
4. 15:50:30.866，真实 ASR 为“明天有什么日程？”，正式服务回答
   “查到日程：明天下午3点 19号做验收测试。”用户确认唤醒成功并听到下午 3 点的测试提醒。
   此时库中唯一项目与 App 的上述 ID、标题、时间一致；不声称语音播报包含 ID。
   该查询轮次 `accepted=true`、`error=null`、`wakeword_detected=true`、
   `wakeword_ack_succeeded=true`、`asr_used=true`、`tts_hardware_used=true`、
   `dialogue_status=read_ready`、`wrote_db=false`、`wrote_formal_db=false`、
   `audio_retained=false`。重启及只读查询前后 Schedule DB hash 均为
   `c3a3f86df5f552c7cefb291099c66e00026f707acb47f4a7d2d5612432958a56`。
5. 用户发出删除测试提醒的语音命令，机器人逐条复述目标后，用户说“确认”。
   15:51:48.665 确认轮次为 `confirmation_accepted`、`wrote_formal_db=true`、
   `audio_retained=false`；回答“已删除明天下午3点19号做验收测试的日程。”用户确认“已删除”。
   没有通过直接 SQL 修改业务数据。
6. 15:52:16，单日及 9 月 18–20 日范围 IPC 查询均返回 `items=[]`、`stale=false`，
   原 ID 的详情查询返回 `schedule_not_found`。只读检查确认 `schedule_items=0`、
   `quick_check=ok`、schema 仍为 `2`。App 手动刷新后列表为空、详情显示“这条日程已不存在”；
   机器人状态页的今日日程为“共 0 项 · Asia/Shanghai”。
   截图：[清理后的列表](schedule-cleanup-list.png)、[原详情失效](schedule-deleted-detail.png)、
   [今日摘要](schedule-cleanup-summary.png)。
7. 15:54:01 停止后的检查：本次语音进程和网关已退出，`8443/8444` 无监听，Runtime socket
   已移除，reSpeaker 采集/播放设备均为 `closed`。App、配对状态及无关机器人记录保留。

本阶段有用户授权的创建和删除，不宣称 Schedule DB 字节不变。清理后 SHA-256 为
`920801806b0e1a502273df4b4c345bd3fb888c71e85f3ee6340c7de67f02ab5b`；提醒账本始终为上表 hash。
只删除上述测试日程，未保留该条记录的恢复备份；如需再次测试，可按上述标题和时间重新创建。

## 诊断与局限

- 第一次启动被 `app_emergency_stop_navigation_boundary_required` 拦截。纯预检复现，
  移除本次无导航场景不需要的急停 Runtime 参数后预检为空、正式启动成功；安全检查未修改。
- 第一次唤醒后没有有效查询音频，自动回到等待；后续查询成功，未调低音频阈值。
- 启动前相关软件检查 `41 passed / 1 failed`；失败是导航 worker 的 preparation=pending
  停止测试 3 秒超时。本次 `--no-navigation` 不创建该 worker；reSpeaker/no-navigation
  入口测试通过。不宣称全套回归通过，未修改导航 WIP。
- Gradle 构建通过：使用已有 ARM64 AAPT2 和 Flutter 已安装 NDK 参数，避免下载 NDK 用的
  空 CMake 工程调用 x86 clang；未跳过产品 native 编译检查。
- 原始日志、指标和回退 APK 位于 `/tmp/issue10-hil-20260918.7cPhPh/`，不保证跨重启保留。
  非空阶段日志为 `board-session-positive.log`、`asr-positive.jsonl`，重启后为
  `board-session-positive-restart1.log`、`asr-positive-restart1.jsonl`。
- 唤醒卡住是独立的运行稳定性待办。本轮只按授权重启恢复，没有修改 ASR/VAD/endpoint
  阈值、采集实现或安全参数，不能将此次功能 PASS 解释为该问题已根治或长稳验收通过。
- 本轮仅改变设备运行状态、创建/删除获准测试数据并补充证据，没有修改产品源码；既有软件
  测试结果只适用于各自记录的版本和范围，没有为纯证据更新重跑或宣称全套测试通过。

以上为早期阶段的证据；最新复验见下节。Issue 11 迁移、App/语音并发写入验收以及
语音稳定性修复均不自动进入下一阶段。

## 第三阶段：修复后的远期午夜复验

### 对象、软件基线与运行边界

- 沿用 `rb_rk3588_01`、Xiaomi `23043RP34C`、ADB `172.22.205.14:37301`、原 TLS 指纹
  和仅 `robot.status.read` 的 App 配对会话，没有重新配对或扩大网络暴露。
- 已获用户授权安装 App `2012 / 0.1.0-issue10-retest`；本轮启动前核对仍为该版本，未再次
  安装。构建时 APK SHA-256 为
  `447812e08f4fc56d746165a10501a280946bbf420fd622b9769c94154fae353a`。
  精确旧 App `2011` 的回退 APK 位于 `/tmp/issue10-retest-20260918.UkGRWt/rollback-2011.apk`。
- 运行的是上述 Provider HEAD 上的共享未提交修复，不把 HEAD 冒称完整候选版本。修复包括
  去除 next occurrence 的一年上限、详情午夜时间、App 完整年份、V2 历史时区，以及现场
  暴露后经用户授权修复的完整年月日解析、补充回答、跨午夜查询和播报。
- 首次 `2012` 会话因无法识别完整年月日而持续追问，未保存测试数据；失败日志保留在
  `/tmp/issue10-retest-20260918.UkGRWt/`。后续 TDD 分别观察到日期/午夜回归 RED 再 GREEN。
  最终软件验证为 `412 passed in 31.14s`，覆盖领域、对话、临时 SQLite、Runtime、提醒、
  IPC/App 读取和架构边界；这是本轮启动前的开发阶段结果，本次清理没有重复运行测试。
  App 日期显示相关的 14 项 widget 测试及 Dart 静态分析在前次构建前通过，App 源码此后未改。
- V2 历史跨时区只有临时数据软件证据；正式库保持 schema `2`，没有 Issue 11 migration、
  App 写入 HIL 或历史投递数据注入。
- 用户另行确认“已准备好”后于 17:09 启动正式入口，使用
  `--microphone-profile respeaker --no-navigation --no-visual-chain --no-reminder`，
  Runtime IPC 为 `/tmp/issue10-midnight-retest-20260918.1RuwHH/runtime.sock`，会话上限
  1200 秒。17:29 前主动 Ctrl+C 结束。没有修改 ASR/VAD/endpoint、安全阈值或运行 selector。

### 实测结果

1. 启动前正式日程库 `schedule_items=0`、schema `2`、`quick_check=ok`；创建一致性备份
   `schedule-before.sqlite3`（为空库，不包含后来创建的测试提醒）。
2. 17:10 第一遍 ASR 包含完整“二零二八年 1 月 1 号晚上 12 点，提醒我做午夜远期测试”，
   进入保存前确认，不再循环追问日期。但确认阶段重复长句被识别为“做午夜圆”和“做午夜”，
   替换待确认标题；最后用户说“保存”，17:11:32 正式写入的标题为“做午夜”。没有手动改名。
3. Runtime 单日查询 2028-01-01 为空，2028-01-02 的列表与详情、真实 Android 列表/详情
   均包含以下唯一记录：

   | 字段 | 实测值 |
   | --- | --- |
   | schedule ID / next occurrence ID | `schedule-dialogue-1789722574797-1` |
   | title | `做午夜` |
   | scheduled_at / next occurrence time | `2028-01-02T00:00:00+08:00` |
   | timezone / source | `Asia/Shanghai` / `voice` |
   | history | `available`、`occurrences=[]`；UI“暂无执行记录” |

   [远期午夜列表](midnight-list.png)、[详情和下一次提醒](midnight-detail.png)显示
   `2028年01月02日 00:00`，不是遗漏年份或再偏移一天。
4. 17:16 两次和 17:27:52 的真实语音查询“2028 年 1 月 2 号有什么日程”均回答
   “查到日程：1月2日凌晨0点 做午夜。”用户确认听到该回答，且已确认保存时也播报凌晨0点。
   查询轮次 `read_ready`、`wrote_db=false`、`wrote_formal_db=false`、
   `tts_hardware_used=true`、`audio_retained=false`、`error=null`。
5. 17:17–17:18 两次按标题删除被 ASR 转为“删除做 5 页的提醒”，返回
   `delete_no_matching_items`，没有写入。真实存储标题是“做午夜”，这是同音误识别，
   不是查询/删除两套库或数据消失。本次没有开启同音模糊删除。
6. 临时数据库先验证“按日期查询 → 删除这条 → 确认”的公共对话流程；之后用户在同一
   真机会话实际执行。17:28:01 系统明确复述唯一目标“1月2日凌晨0点做午夜”，未提前写入；
   17:28:08 用户说“确认”，`confirmation_accepted`、`wrote_formal_db=true`、
   `audio_retained=false`，回答“已删除1月2日凌晨0点做午夜的日程”，用户确认听到。
7. 17:28:36，只读 IPC 检查：2028-01-02 单日和 2028-01-01 至 2028-01-03 范围均
   `items=[]`、`stale=false`，原 ID 详情为 `schedule_not_found`。正式库为零条，
   `quick_check=ok`、schema 仍为 `2`，没有直接 SQL 修改业务数据。
8. App 刷新详情显示[这条日程已不存在](midnight-deleted-detail.png)。返回列表时捕获的
   [画面仍是旧缓存](midnight-list-still-cached.png)；代理在取得列表成功刷新为空的结果前
   停止了服务，未完成该检查。不能把此图标为清空成功，也不能据此认定数据库没有删除。
   后续需要在在线会话中单独完成一次列表刷新确认，不用早期截图代替本轮证据。
9. 17:29:07 停止检查：本次语音、网关进程均退出，8444 无监听，Runtime socket 已移除，
   reSpeaker `/proc/asound/card4/pcm0c/sub0/status` 和播放对应状态均为 `closed`。
   App 安装和配对保留。只删除本条受控测试提醒，未保留含该条记录的库备份；可依据本节
   标题和时间重新创建，不宣称可以直接恢复原 ID。

有创建和删除，日程库字节正常变化：

| 文件 | 启动前 SHA-256 | 清理后 SHA-256 |
| --- | --- | --- |
| `schedule.sqlite3` | `920801806b0e1a502273df4b4c345bd3fb888c71e85f3ee6340c7de67f02ab5b` | `1499d796354e1774b771e5c3275c1d6f7e385751e65fa42989f178eaa168e373` |
| 提醒账本 | `f012211a6b964496f4b623d651a050bbc8cfd64257f723a06814d3bd039a307b` | 不变 |

### 仍未解决的风险与证据限度

- 确认阶段的两次长句在约 5.46 / 5.37 秒采用 `server_stable_451` 结束；
  `local_endpoint_reason=null`，本地尾静音为 0。支持云端结束信号过早截句的怀疑，但没有
  保留原始音频，尚不能排除其他采集/识别因素；没有修改或修复这条语音链路。
- “午夜”与“5页”同音误识别已确认；“删除这条”只完成了受控数据清理，不算识别问题修复。
- 第三阶段未取得列表清理后成功刷新为空的最终画面，当时清理证据以正式库、IPC 和 App
  详情失效为准；此缺口现已由第四阶段补齐。标题完整识别、整机长稳、延期安全隔离和
  V2 真机迁移均不冒称通过。
- 原始 `board-session.log`、`asr.jsonl`、`gateway.log` 位于
  `/tmp/issue10-midnight-retest-20260918.1RuwHH/`，不保证跨重启保留。持久证据只收录本轮
  受控日程截图及上述必要摘要，不复制认证令牌、密钥、配对状态或原始音频。

## 后续决定与列表刷新补验边界

用户明确要求语音截句先记录、待其他功能落地后再处理。本轮不修改语音识别或待确认标题
更新逻辑，不将延期写成修复完成；午夜/5页误识别及唤醒稳定性风险也保持原结论。

本次只补验 App `2012` 在正式在线链路中刷新 `2028-01-02` 列表为空，核对被删除的
`schedule-dialogue-1789722574797-1` 仍不存在，并检查业务库前后未变化；不增删日程、
不迁移数据库、不要求用户说话。启动前网关 8444 无监听，Android ADB 仍在线；取得用户
独立的“已准备好”回复后才启动正式会话，没有复用旧截图宣称本次通过。

## 第四阶段：列表刷新补验：PASS

### 运行对象与边界

- 沿用同一 RK3588、reSpeaker、Android `172.22.205.14:37301`，启动前核对 App 为
  `2012 / 0.1.0-issue10-retest`；未重新安装、配对或改变原有 `robot.status.read` 权限。
- 经 `scripts/start_product_voice_board_session.sh` 正式入口，保持
  `--microphone-profile respeaker --no-navigation --no-visual-chain --no-reminder`。
  加入现有 `--expected-formal-db-sha256` 参数，其值为下表日程库 hash，启用既有正式写入
  dry-run 与跳过过期清理行为；读取仍使用同一正式 Runtime Schedule 服务，并非替身数据库，
  也不冒称 Runtime 的 SQLite 连接是 `mode=ro`。
- Runtime IPC 为 `/tmp/issue10-list-refresh-20260918.wthMRh/runtime.sock`；网关沿用
  `172.22.205.44:8444`、`rb_rk3588_01`、原证书与配对状态，禁用发现，不扩大网络暴露。
  会话上限 300 秒，实际在完成检查后主动停止。没有调用语音写入、导航或提醒执行链路。

### 本次实测

1. 17:36:31，IPC 单日 `2028-01-02` 与范围 `2028-01-01` 至 `2028-01-03` 均返回
   `items=[]`、`stale=false`、`timezone=Asia/Shanghai`；原 ID
   `schedule-dialogue-1789722574797-1` 返回 `schedule_not_found`。
2. 启动前 App 为服务离线的“日程暂不可用”，在线后点击刷新即恢复为空列表。为明确本次
   查询日期，再通过日期输入填入 `01/02/2028` 并点击 OK，等待列表稳定后再次点击右上角
   “刷新日程”。17:37:25 UI dump 与实际截图均显示“这一天没有日程”，无旧日程或错误。
   [本次日期输入](midnight-empty-query-date.png)、[最终刷新后的空列表](midnight-list-refreshed-empty.png)。
   空列表本身不显示选中日期，因此保留日期输入证据与上述操作顺序，不用单张空图推断日期。
3. 正式日程库通过独立 `mode=ro` 检查：`schedule_items=0`、schema `2`、`quick_check=ok`；
   提醒账本 schema `0`、`quick_check=ok`。两库启动前、查询后、停止后 hash 均一致：

   | 文件 | 本次前后 SHA-256 |
   | --- | --- |
   | `schedule.sqlite3` | `1499d796354e1774b771e5c3275c1d6f7e385751e65fa42989f178eaa168e373` |
   | `schedule.reminder-deliveries.sqlite3` | `f012211a6b964496f4b623d651a050bbc8cfd64257f723a06814d3bd039a307b` |

4. 本次没有真人语音输入，等待日志未检测到唤醒；未增删日程、迁移数据库或修改产品源码。
   主动 Ctrl+C 停止两进程后，17:37:42 确认 8444 无监听、Runtime socket 已移除、reSpeaker
   采集/播放均 `closed`。保留 App 安装、配对及无关 WIP。

### 结论与证据限度

本阶段补齐了第三阶段唯一缺失的 App 列表刷新画面，用户约定的 Issue 10 开发阶段日程只读
功能验收为 PASS。软件实现与先前针对该实现的软件回归结果未变，本次不重复运行或冒称
全量回归；语音截句、安全权限隔离延期，午夜/5页误识别和唤醒稳定性风险保持未解决。
不代表标题完整识别、整机长稳、安全验收或 V2 正式迁移通过，也未进入 Issue 11。

本次原始板端、网关日志和截图在 `/tmp/issue10-list-refresh-20260918.wthMRh/`，不保证
跨重启保留；上述两张真实截图已复制到本证据目录。未保存认证材料或原始语音。

## 后续补记：归档执行记录读取修复（软件证据，不是 HIL）

用户明确只修复“普通提醒归档后，App 查不到日程及执行记录”，不修登录续期后旧页面连接
失效。此前跨午夜重复取消、时段筛选与无具体时间旧日程漏显均按用户决定延期，语音截句与
安全隔离延期决定不变。

正式 Schedule 服务现在可通过原 repository 读取 `expired_one_off_schedule` 归档快照：
详情按 ID 查询，列表按查询日期范围合并，今日摘要与列表一致。保留原活动集合、15 分钟
过期宽限及清理策略，不恢复已归档日程为可提醒对象，不通过账本恢复用户主动删除的项目。
REST DTO 未变化，继续通过 Runtime/IPC 向 App 返回允许公开的字段。

临时数据库的 TDD 证据：归档详情先返回 404、修复后返回原 ID 与真实已送达记录；今日、
单日和范围列表先漏掉归档项、修复后均保留它且 `next_occurrence=null`，未来提醒不受影响。
相关回归 195 项通过；随后补充主动删除不复活用例，归档/删除定向 5 项通过，其中 4 项重复；
正式 Runtime 装配 2 项通过，合计 198 个不同用例。没有重新运行或宣称 Flutter/全仓回归。

没有访问正式业务数据库、部署或启动设备，也没有新的真实 App 截图。前四阶段证据保留为
历史记录，不能替代本次改动上线后的归档读取真机复验。

## 后续补记：保留配对凭证，修复日程续期旧连接（软件证据，不是 HIL）

用户后续另行授权此项修复；上一节“不修续期”的表述仅记录当时范围。保留现有安装实例配对
凭证、续期时间、TLS 固定与权限检查，不引入个人账号登录。

日程列表和嵌套详情不再固定使用开页时的 reader，而是在每次请求时使用当前活动配对会话的
reader。页面状态不重置，日期/范围与详情 ID 保留；没有活动 reader 时失败关闭，不回退旧
连接。变更仅针对 Issue 10 的 `ScheduleReader`，不修改 Issue 11 的 `ScheduleManager`
或其他控制页面，不改变任何写命令的重试/幂等语义。

测试 `flutter/duole_engineering_app/test/paired_schedule_refresh_test.dart` 使用真实配对
网关、续期流程、HTTP transport 生命周期、API 解码与 UI，仅替换机器人 HTTP 端点和平台
凭证存储。先复现自动续期后原页面读取失败，再验证原列表刷新、续期前/后打开的详情、
详情失败重试、指定日期/范围跨续期后的重试；只读会话仍不显示写入口。软件测试的时间推进
不是手机驻留一小时的真实设备证据。

本轮 Flutter 全量 `117 passed`，其中新增续期 widget 用例 4 项；静态分析为
`No issues found`，本轮文件 `git diff --check` 通过。工具链 Flutter 3.47.0，工作目录
`flutter/duole_engineering_app`，命令为 `flutter test --no-pub --reporter expanded` 与
`flutter analyze --no-pub`；运行时仅为本机测试临时清除 HTTP/HTTPS/ALL_PROXY 并设置
`NO_PROXY=127.0.0.1,localhost`。上一轮 provider 的 198 项证据单独保留，不计入本轮 117 项。

没有访问正式数据库、构建/登记候选、安装或激活设备，没有新增 HIL 截图。需要在实际设备
更新后补验本次续期修复，以及上一轮归档读取修复；不能将前四阶段 PASS 移用于本次实现。

## 后续补记：18:51 App 2013 覆盖安装（安装 PASS，不是功能 HIL）

用户明确授权“安装吧”。本轮只操作原 Android 的目标应用，未启动机器人/ROS/语音服务，
未访问正式业务库或 App 私有凭证，未启动 App 进行配对恢复或日程请求。

- 目标：Xiaomi `23043RP34C`，serial `41f736f9`，ADB `172.22.205.14:37301`。
- 包名：`com.duole.engineering.duole_engineering_app`；原版本 `2012`，新版本
  `2013 / 0.1.0-issue10-session-refresh`，API 合同继续为 `3.0.0`。
- 原 APK 备份：`/tmp/issue10-app-install-20260918.xy4sml/rollback-2012.apk`，SHA-256
  `447812e08f4fc56d746165a10501a280946bbf420fd622b9769c94154fae353a`，与历史记录一致。
- 新 APK：`/tmp/issue10-app-install-20260918.xy4sml/duole-issue10-session-refresh-2013.apk`，
  SHA-256 `390212fe6f5e225bb3fccdfb101e9a1e0b7a3946e28305ed9d40a84ee91f633d`。
- `apksigner verify --print-certs` 验证成功，新旧签名证书 SHA-256 相同：
  `fa9601d8d671b83f6d167dbd16001f2224b1f0e78fa35c2468da44b260cf3c0f`。
  这是 APK 签名证书摘要，不是机器人的 TLS 指纹。
- `adb -s 172.22.205.14:37301 install -r --no-incremental <新 APK>` 返回 `Success`。
  `dumpsys package` 确认 versionCode `2013`、versionName 匹配、lastUpdateTime
  `2026-09-18 18:51:05`；firstInstallTime 仍为 `2026-08-27 00:19:23`。
  随后对 `pm path` 返回的已安装 `base.apk` 做 SHA-256，结果与新 APK 完全一致。
  未执行卸载、清数据、重新配对或权限提升。

构建使用 Flutter 3.47.0、已有 JDK17/Android SDK/Gradle 缓存、ARM64 AAPT2 和已安装
NDK `28.2.13676358`。命令核心参数为：

```text
flutter build apk --debug --no-pub --target-platform android-arm64
  --build-number 2013 --build-name 0.1.0-issue10-session-refresh
  --dart-define=DUOLE_APP_VERSION=0.1.0-issue10-session-refresh
  -Pandroid.aapt2FromMavenOverride=/home/ztl/.local/share/duole-hil-toolchain/android-sdk-tools-arm64/build-tools/aapt2
  -Pflutter.androidSdkRoot=/home/ztl/.local/share/duole-hil-toolchain/android-sdk
  -Pflutter.installedNdkVersions=28.2.13676358
```

Gradle `assembleDebug` 成功（34.2 秒）；有既有 `mobile_scanner` Kotlin Gradle Plugin
兼容性预警，不影响本次构建，未在本轮更改依赖。源码为 HEAD
`43296141f0cd2efb69a8bf895a05ca84e92977bd` 上的共享未提交工作树，不将 HEAD 冒称完整产物版本。
核心修改 `lib/connection_page.dart` 构建前后 SHA-256 均为
`0d7960f9623c37024383a1c872b9a052aeb9ea2d5ac0e55cd6ef4c98c0473e0f`。
复用上一轮该源码的 Flutter 117 项与静态检查结果；本轮未重跑无变化的软件回归。

构建和安装日志保存在上述临时目录的 `build.log`、`install.log`，临时文件不保证跨重启保留。
本轮只证明新 APP 已安装，不证明自动续期实际驻留复验通过，也不激活机器人端归档读取
修复。尚需后续正式在线链路的针对性功能复验，故工单验收结论不提升为完整 PASS。
