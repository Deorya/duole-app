# Issue 10 Android ↔ RK3588 只读日程 HIL

日期：2026-09-12（Asia/Shanghai）

结论（2026-09-15 审查更正）：组件 HIL 通过，正式产品入口验收尚未完成。
当时使用独立的只读 Runtime，未经过 `scripts/start_product_voice_board_session.sh`；
下列真实设备结果不能替代正式产品链验收。真实 Android 经受信 TLS、一次性配对、RK3588 Gateway 和 Runtime IPC，
读取了 RK3588 当前本地业务库中的日程列表与详情。过程中发现并以 TDD 修复了“历史一次性
日程详情丢失计划时间”的缺陷。未启用导航、建图、teleop、麦克风或提醒循环，两个业务库
在运行前后字节哈希、大小和 mtime 均未变化。

## 对象与授权边界

- 机器人目标：当前主机 `RK3588`；HIL robot ID `rb_rk3588_01`。
- 机器人 App LAN：`wlan1`，`172.22.205.44:8443`。
- Gateway TLS 设备密钥指纹：
  `sha256:a335cd1f6ed9ff161102a000e78f2f41adef4eb6e08a91404379eea28f404e7b`。
- Android：Xiaomi `23043RP34C`，Android 14 / API 34，硬件 serial `41f736f9`，
  ADB transport `172.22.205.14:41803`。
- 用户在本次会话中明确授权该 Android、RK3588、候选 APK、Gateway/Runtime 激活及直接读取
  RK3588 当前业务库。授权不包括运动、导航、建图或写入日程。
- 仓库中所谓 `FORMAL_SCHEDULE_DB_PATH` 实际是机器人本地 runtime SQLite，不是远端生产
  数据库；本证据称其为“当前本地业务库”。

## 候选制品

- package：`com.duole.engineering.duole_engineering_app`
- versionCode：`2007`
- versionName：`0.1.0-issue10-hil`
- APK SHA-256：
  `fa148ec375a96cf7d453e57ca35630edd8e86732c746f080c7fc551ec6e8ae6e`
- 安装结果：`Success`；设备报告 `lastUpdateTime=2026-09-12 14:52:21`。
- App 仓库基线 HEAD：`43296141f0cd2efb69a8bf895a05ca84e92977bd`；候选是该基线上的
  未提交 Issue 10 工作树，以 APK 哈希作为 Android 侧精确制品身份。
- Provider 仓库基线 HEAD：`6f7f9980e7e1a472b4cd1e43eaf1c99ba68c63ad`；HIL 实际载入的
  `read_projection.py` SHA-256 为
  `e54238bee954fe14d841e1f1aa2dc8248762e58a16d98874cf75b7a15b3b0a49`。Provider
  工作树也未提交，因此不能把基线 commit 冒充为候选 commit。

## 数据库基线与终态

只读预检的 `PRAGMA quick_check` 均为 `ok`。

| 文件 | 基线记录数 | SHA-256（运行前后相同） | mtime（运行前后相同） |
| --- | ---: | --- | --- |
| `/home/ztl/duole-workspace/data/schedule.sqlite3` | `schedule_items=1`，`schedule_item_history=18` | `ea475f4add5fdbedaa961e74ba68d8b0dd81ab28b0301b0911e23a948b075455` | `2026-09-02 21:47:43.461242402 +0800` |
| `/home/ztl/duole-workspace/data/schedule.reminder-deliveries.sqlite3` | `deliveries=1`，`state=8` | `f012211a6b964496f4b623d651a050bbc8cfd64257f723a06814d3bd039a307b` | `2026-08-04 22:40:00.294400738 +0800` |

Runtime 使用仓库已有的只读 Schedule repository；日程与提醒账本连接均使用 SQLite
`mode=ro`。Gateway 进程不导入 Schedule repository，也没有日程 DB 路径。

## 本次新运行的验证

1. Runtime IPC：指定日期 `2026-09-03` 返回 1 条日程，时区 `Asia/Shanghai`，来源
   `voice`，提醒历史 availability 为 `available`。
2. TLS/REST：`/.well-known/duole-app`、`GET /api/v1/schedules?date=2026-09-03`
   和详情接口均为 HTTP 200；递归隐私禁字段扫描命中数为 0。
3. Android：完整核对 TLS 设备密钥指纹，只授予 `robot.status.read`，一次性配对成功；
   日期选择器读取到稳定 schedule ID、标题、计划时间、来源、可用性和无后续 occurrence。
4. Android 进程强制停止并重启后，重新选择同一机器人可直接恢复已配对会话，无需再次输入
   指纹或配对码；重新发起日期查询仍返回同一条日程。
5. Android 目标进程日志扫描：fatal/ANR 命中 `0`，配对码/Session/token 模式命中 `0`，
   TLS/connect/timeout 异常命中 `0`。
6. HIL 结束后 Gateway `8443` 与 Runtime socket 均已停止监听。

## HIL 发现的 RED → GREEN

初次进入详情页时，列表的 `09月03日 15:00` 在详情中错误显示为“时间待确认”。根因是
`ScheduleAppReadService.get_detail` 将计划 occurrence 与未来 next occurrence 复用；已过期
的一次性日程没有 next occurrence，因而连计划时间也被清空。

- RED：新增 `test_past_one_off_schedule_detail_keeps_its_planned_time`，实际
  `scheduled_at=None`，测试失败。
- GREEN：详情分别计算原始计划 occurrence 和未来 next occurrence；回归测试通过。
- 设备复验：详情显示 `09月03日 15:00`，同时 next occurrence 仍为空，执行记录仍按真实
  ledger 显示“暂无执行记录”，未合成历史。

本次修复后的相关 Python 回归：`1190 passed, 1 skipped`；两条 warning 都来自测试旧
TLS 1.0/1.1 拒绝策略时 Python 标记这些枚举 deprecated。

## 屏幕证据

- [schedule-list.png](schedule-list.png)：真实 Android 指定日期列表，SHA-256
  `24ea1901d18989827c0c9193f778b4422ac85569b71326bedc3098f8bb0b3e05`。
- [schedule-detail.png](schedule-detail.png)：首次 HIL 的 RED，详情错误显示“时间待确认”，
  SHA-256 `d8d051612238d01ba56d639fed9d4d48fe191d0ac89cdd332e29def64bc6e9c4`。
- [schedule-detail-green.png](schedule-detail-green.png)：修复后的真实 Android 详情，
  SHA-256 `0f6f69424735785622f491ccb37ebf454423becdd10a17337730f54b25b572d8`。

## 历史记录的证据

Issue 文件此前记录的软件验证为：Schedule 领域/对话 `496 passed`，Runtime/提醒装配
`101 passed`，Gateway/IPC/TLS/投影 `38 passed`，Dart client `43 passed`，Flutter
`103 passed`，以及合同生成确定性校验。这些是本次 HIL 之前的历史记录；本次没有把它们
冒充为新运行。上面的 `1190 passed, 1 skipped`、真实设备交互、日志扫描和数据库终态哈希
才是本次新运行证据。

## 留存状态

临时 HIL 的证书、Gateway 状态库和配对状态保留在
`/tmp/duole-issue10-hil.8vCmBa`，目录为 owner-only，用于本轮短期追溯；Gateway 和 Runtime
均已停止。该目录不属于候选制品，也不包含正式日程库副本。

2026-09-15 复查：上述临时目录已不存在，后续验收需要重新建立并核对 Gateway 身份。
