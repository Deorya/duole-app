# Issue 33 接手记录（2026-10-08）

## 最新续接状态：2026-10-14，v2012已部署，近路由器复测操控中地图/位姿更新，用户结束测试

- 用户同意修复并部署测试。App v2012 / phaseA9恢复按压期间500ms地图/状态轮询，
  终态关闭控制通道并退出重连；开发模式静止握手窗口和传输等待为5000ms，首条运动输入后
  Gateway/板端无输入watchdog仍1000ms。过期arm转为停车状态，确认后须新的按压才能重试。
  Provider相关232项通过，新增贯穿typed SSH→CLI factory→实际IPC→Guard用例通过；
  含新增用例的session control共12项通过，页面38项、分析及APK构建通过。
- 对当前板端实际文件派生的128项通过后，只替换manual_mapping_guard.py与agent.py，
  保留ROS/QoS、Runtime/CLI及开发配置；未改selector。平板14:35581安装核验v2012。
  精确板端回滚：`runtime/issue33/map-refresh-handshake-before-20261014/`（两个原文件）；
  实际已安装v2011 APK保存于task-local `map-refresh-handshake-deployment-20261014/tablet-before-v2011.apk`。
- 用户新确认“已准备好，靠近路由器”后，经正式Product App-only入口启动会话
  `manual_mapping_5dc5587537f74588bfefbd296fb51828`，operation
  `mapping_569167e61b5d49449ad19bdea3475933`；预检76%、静止、无占用，hello为session_development。
  UTC13:28:26.024938开始。用户在监控就绪前自行开始操作，首条Gateway输入13:29:20.719631，
  monitor到13:30:39.871981才启动，首段缺少实时监控，不能称完整覆盖。
- 5轮控制共986条全部applied，无板端失败；最长epoch1为49.663173s。
  后续按压期间观察到18个map_progress样本，其中epoch5地图投影r80→r91且位姿持续变化。
  这证明操控中数据投影在刷新，尚无用户对实际屏幕体验的验收反馈；本轮未复现>1s握手或确认
  碰撞恢复。SSH最长1287.162ms，不等同于arm等待。留存5组板端停车609.184–839.212ms；
  monitor没有中止或超限事件，但首轮监控缺口使本轮不能替代完整安全验收。
- UTC13:31:24.157886终态abandoned/stopped/user_abandoned，地图投影r94；本轮没有保存验收。
  终态后还有一次RECONNECT_NOT_ALLOWED，不能宣称零重连。随后用户明确“结束本次测试”。
  monitor（41049）、Gateway（70471）、Product（38440）均exit0，8443/Runtime IPC/Guard socket
  已关闭；导航active、建图/Guard inactive，收尾读取76%、静止、无占用。保留部署，无自动回滚或再测。
- 回答刷新周期时核对：App轮询500ms；当前launch引用的slam.yaml配置map_update_interval=5.0，
  因此连续轮询可能读到同一张地图。未修改SLAM发布参数；本轮仍PARTIAL_HIL。
  原始日志、map_progress、timing-summary、hil-result、final-session与cleanup-preflight在
  `session-20260929/map-refresh-handshake-hil-20261014/`；本地软件及APK在
  `map-refresh-handshake-local-20261014/`，精确板端派生/验证/部署文件在deployment目录。

## 最新续接状态：2026-10-14，近路由器复测暴露按压期间地图停刷及获取控制 ACK 过期

- 用户明确要求重新安排手动遥控建图测试，并确认“已准备好，靠近路由器”。沿用v2011/
  phaseA8与session_development，未改代码、安装包或运行配置；新鲜预检82%、静止、无占用。
  正式Product App-only入口启动，会话 `manual_mapping_0f6abb80ba744a6ab078c913fc6e0ef7`，
  operation `mapping_1ec02eca736f491988480f2d761f4e18`，UTC `11:26:58.294485` 开始。
- 控制页已确认，monitor于UTC `11:27:41.833372` 启动；首条运动输入在 `11:29:44.007086`，
  本轮没有前轮的首轮监控缺口。真人自行操作，没有注入摇杆动作。
  epoch1–6共644条Gateway/SSH/板端记录，全部applied，无板端lease失配、discarded或blocked。
  最长一轮epoch2共367条，板端接收跨度36.657170s；SSH最大681.741ms。
- 用户反馈两个问题：“地图不会随着移动实时更新，而是在松手的时候将之前记录的一起更新完”；
  “碰撞之后就不能再控制了，可以参考最后一下失败”。本轮操作体验为FAIL，不沿用上一轮流畅反馈。
- **地图直接原因确定在App刷新门：** `manual_mapping_page.dart` 的 `_refreshStatus`、
  `_refreshVisualization` 在 `_controlHasRefreshPriority` 为true时既不发起读取，也不应用已返回数据；
  该条件就是有效摇杆按压且未等待停车。现有测试
  `active gesture pauses reads during acquisition and control, then resumes` 明确锁定这一行为。
  epoch2持续控制时会话地图停在r94，松手确认后跳到r114，与用户现象一致。
  本轮证明的是App/投影刷新被暂停，不是SLAM只在松手后开始处理。
- **末次失败直接错误确定为获取控制ACK过期：** UTC `11:31:05.492230`，acquire总耗时
  1487.787ms，返回MANUAL_MAPPING_GUARD_ACK_EXPIRED。`mock_manual_mapping.acquire_control`
  仍按每次arm实际耗时扣减1000ms窗口，剩余<=0时请求arm_ack_expired停车并报错；
  这条获取控制握手门在session_development也仍生效，取消逐条运动ACK续期未取消它。
  App把error按通道故障关闭并进入重连。日志不能把此次握手延迟唯一归因于碰撞。
- 监控先于末次acquire错误，在UTC `11:30:57.021416` 对epoch5停车记录
  STOP_LIMIT_EXCEEDED（host pending1057ms），随后仍观测到epoch6的20条运动全applied。
  monitor的UI操作最终在 `11:31:08.553528` 点击立即停止保存，
  `11:31:08.669644` 会话terminated/stopped/immediate_stop_saved，地图投影r136。
  `11:31:13.186145` 再按下返回PHASE_NOT_CONTROLLABLE，之后11次重连被拒绝。
  不能把监控停止保存造成的不可控说成已证明的“碰撞后永久锁死”。
- 本轮没有捕获epoch5被中止停车的完整板端请求/确认时间对，后续停车和重连覆盖了字段；
  最终重连写入的request==confirmation、0ms不是独立物理停车测量。
  只能保留监控等待门FAIL和时序证据，不编造精确车轮停止耗时或判为通过。
  当前仍有no-native-collision开发drop-in，644条上游applied也不证明真实轮速或没有接触障碍。
- 板端map.pgm/map.yaml/metadata.json已核实；未回桩验证、未自动启用、immediate_stop保存。
  monitor（53774）、Gateway（65096）、Product（76110）均exit0；导航active、建图/Guard
  inactive，8443无监听、Runtime IPC/Guard socket消失；收尾新鲜读取82%、静止、无占用。
  独立证据目录 `session-20260929/session-control-retest-20261014/` 保存原始日志、final-session、
  timing-summary、hil-result、cleanup-preflight与test-plan；没有自动再测或回滚。
- 本轮用户反馈按只读诊断处理，尚未修改产品代码。最小修复建议：恢复按压期间的地图/状态刷新，
  继续复用已有独立数据通道和防重入；把可恢复的获取控制ACK过期处理为停车后可重新尝试，
  避免错误触发通道关闭及终态重连循环。保留1000ms输入watchdog与原停车验收基线。
  碰撞与握手延迟的因果仍需对应现场证据，不能宣称碰撞恢复已修好。

## 最新续接状态：2026-10-14，v2011 REAL 操作反馈流畅、无崩溃；停车超时与结束后重连仍待处理

- IPC profile 补丁部署后，用户重新明确“已准备好”，经正式 Product App-only 入口启动新一轮。
  平板仍为 `172.22.205.14:35581`、v2011 / `0.1.0-phaseA8`，没有再次改包或配对。
  预检电量84%、静止、离桩、无占用；hello 明确返回 `control_mode: session_development`。
- 会话 `manual_mapping_03089325195f4a6a963fc3d8dc55b692`，operation
  `mapping_c8cbbba7fbcc495bab456d0b79473121`；UTC `10:55:07.062252` 开始，
  `10:58:34.257548` 结束，终态 terminated / stopped / immediate_stop_saved，地图投影 r105。
  用户反馈原文：“已经停止保存，此次建图过程流畅，没有崩溃”。本轮路由器距离未确认，
  不能称为远处对照通过，也没有单独确认全程无变灰或所有方向均完成。
- 用户自行操控，未注入摇杆运动。共9个控制 epoch，Gateway收到1460条 intent，
  SSH提交/完成及板端接收均1459条，1445 applied、14条板端 lease mismatch。
  epoch3的580条全部 applied，接收跨度57.938307s；epoch6的447条全部 applied，44.643549s。
  其余轮次也成功取得控制。14条失配均在epoch1，seq140–153；本轮最大SSH等待1266.446ms。
  用户体验改善成立，但不能宣称日志无中断、无错误或整条链已稳定。
- 停车监控UTC `10:56:52.448633` 才启动，首轮操作已在此前发生；该段只有Gateway/板端
  时序日志，缺少实时红线监控。`watchdog` trace 中的8条 control_stopped 均处于后续松手
  停车确认路径，不能仅凭事件名推断8次超时；epoch1失配的触发源本轮未继续诊断。
- 已留存8组板端停车请求/确认时间，前7组664.292–836.726ms；最后一组
  `10:58:26.471584` → `10:58:27.495135` 为 **1023.551ms**，超过原1000ms验收基线。
  monitor 在 `10:58:27.473971` 记录 STOP_LIMIT_EXCEEDED，并于 `10:58:34.199660`
  点击“立即停止并保存”，最终 round_aborted=true。用户也反馈已停止保存，不能将最终保存
  唯一归因于用户点击；保存沿用epoch9停车确认，不算额外停车样本。
- 板端本会话目录的 `map.pgm`、`map.yaml`、`metadata.json` 已生成；metadata确认
  dock_verified=false、new_map_activated=false、save_kind=immediate_stop。
  但本机 `navigation-map.sqlite3` 的 map_catalog 仍为空，mapping_operations 行仍为started，
  与手动会话终态不同。**板端保存已核实，App地图资料库登记/读取及完整状态一致性尚未验收。**
- 会话结束后UTC `10:58:40.555356` 至 `11:02:26.470775`，记录1153次
  MANUAL_MAPPING_RECONNECT_NOT_ALLOWED，均在终态之后。结束页的重连退出行为仍有缺陷，
  不能用“无崩溃”推断退出后无残留；本轮仅登记证据，未扩大到新的修复或再测。
- 本轮体验结论为 **PARTIAL_PASS_OPERATOR_FEEDBACK**，原停车门为
  **FAIL_STOP_LIMIT_EXCEEDED**；阶段A完整闭环、重复稳定性与Issue33完整发布验收仍未通过。
  保留原停车阈值，停车保障列为后续事项；体验主线还需解决结束后重连和资料库闭环。
- monitor（54074）、Gateway（25234）、Product（63207）均exit0；再次只读收尾确认
  8443无监听、Runtime IPC不存在，导航active、建图/Guard inactive，实际Guard socket消失。
  新鲜设备读取电量83%、底盘静止、无任务占用。保留已部署开发配置与v2011，没有自动回滚、
  启动新HIL、调整selector或写正式能力标记。
- 独立证据目录为 ignored task-local
  `session-20260929/session-control-retry-20261014/`：包含原始Gateway/板端/monitor日志、
  `final-session.json`、`timing-summary.json`、`hil-result.json`、`board-saved-metadata.json`、
  `saved-map-catalog.json` 和 `cleanup-preflight.json`。历史首次profile失败记录保留在下节。

## 最新续接状态：2026-10-14，体验开发版 v2011 已部署，首次控制被 IPC profile 漏接阻断，补齐后待新现场确认

- 用户要求“先完成顺畅控制，等体验没什么问题了，再考虑对应保障”，并明确同意部署和测试。
  新增显式 `session_development` 模式：持续发送不等 ACK，App 不再用回包校时生成运动时间戳，
  Gateway 和板端不按跨设备时间戳/200ms TTL 判定运动帧龄；报文字段保留兼容。
  控制身份在建图会话内保留，松手/无输入停车后每次按下只开启新 epoch；晚 ACK 不恢复旧轮次。
  无输入 watchdog 仍为 1000ms，速度仍为 0.20m/s / 0.90rad/s；正式模式默认行为保留。
  开发模式已放弃延迟运动帧的时间新鲜度保障，不能把其软件通过当作正式安全验收。
- Gateway 启动参数为 `--manual-mapping-session-control-development`；板端配置为
  `/home/ztl/duole-issue31-nav-ws/state/manual-mapping-session-control-development.enabled`，
  内容 `enabled\n`。Runtime 和转发器必须共同使用 profile
  `manual_mapping_session_control_development_v1`。App 从 hello 的可选 `control_mode` 识别模式。
- 平板 `172.22.205.14:35581` 已安装并核验 **v2011 / 0.1.0-phaseA8**，保留原配对。
  软件验证包含持续无 ACK、350ms 偏旧/2h 偏快手机时钟、松手重按、上下游分别超时、晚 ACK、
  断线重连和结束会话；WSS 测试、37 项页面回归及相关静态检查通过，APK 构建成功。
  App 停车后恢复无需重启，自动重连尝试结束后有原页“重新连接控制”入口。
- 首次板端只替换 guard/runtime CLI 两个派生文件，保留现有 ROS/tf_static QoS 热修。
  离线 143 项通过，但当时漏掉真实转发器构造的 profile 配置；**143 项不证明整条控制链通过**。
  Gateway/板端真实启动仍经正式 Product App-only 入口，未改 selector。
- 用户再次“已准备好”后，预检电量85%、静止、离桩、无任务占用，会话
  `manual_mapping_d2608707855a43ffb4fd4dbccf0d3842` 于 UTC `10:19:32.357273` 开始。
  用户反馈“无法操控，不断地显示连接恢复中”。日志显示 acquire 反复
  `MANUAL_MAPPING_GUARD_UNAVAILABLE`、reconnect 成功；始终 **epoch0 / seq0，无运动指令接收执行**。
  未启动300秒运动监测窗口。本次真实控制启动为 **FAIL_SETUP_PROFILE_MISMATCH**，不是移动验收成功。
- 根因：`navigation_board.cli._build_agent` 原来构造默认旧 profile 的 `ManualMappingGuardIpcClient`，
  Runtime 已返回新 profile，因此 IPC arm 校验拒绝，Gateway 转换为 Guard 不可用，App 再重连。
  已新增“真实 CLI factory → IPC → 板端 Guard”回归；旧实现正式模式通过、开发模式失败，
  修复后两种模式均通过。Provider 相关 **35 passed**，明确预载板端派生模块的同组 **35 passed**。
  已将最小 `navigation_board/cli.py` 补丁部署到板端；APK未再改动或重装。
- 已通过实际页面的“立即停止并保存”结束会话，UTC `10:23:31.899918` 为
  immediate_stop_saved / stopped。没有运动输入，不提供本轮物理停车延迟测量。
  Gateway（43691）、Product（19864）均 exit0，8443 与 Runtime IPC 已关闭；导航 active，
  建图/Guard inactive、Guard socket 消失；再次只读核验底盘静止、无任务占用、电量85%。
- 精确板端回滚目录为
  `/home/ztl/duole-issue31-nav-ws/runtime/issue33/session-control-before-20261014/`，包含
  `manual_mapping_guard.py`、`manual_mapping_runtime_cli.py`、`cli.py` 三个原文件；上述新 marker 原先不存在。
  平板原 v2010 APK 已从实际已安装包保存为本轮目录的 `tablet-before-v2010.apk`。
  目录位于 ignored task-local `session-20260929/session-control-local-20261014/`，包含构建包、
  deployment-result、profile-fix-deployment-result、gateway/board 日志、hil-result 和收尾预检。
- **补丁软件验证与部署完成，补丁后的真实控制尚未复测。** 没有自动重跑 HIL，阶段 A 仍未通过。
  下一步等待新的明确“已准备好，重新测试”；启动新测试时使用独立日志目录，恢复 App 新准备页，
  保留既有配对，避免从旧结果页返回已经关闭的 HTTP client；监测窗口从控制页可用后开始计时。

## 最新续接状态：2026-10-14，1000ms watchdog 与输入续期已部署，远处 REAL 复测仍 FAIL

- 用户明确要求“先放宽到1000ms，同时让控制权不再依赖每条ack续期”。本轮将手动建图
  watchdog/握手窗口统一为 **1000ms**，Gateway 在合法、新鲜输入提交时维护本地期限；
  ACK 完成不再延长期限。TTL 保持 **200ms**，过期帧、旧 lease/epoch/seq、松手、
  断线与停止确认保护保留。此前记录的 400ms 是历史配置，本轮用户明确覆盖该开发参数；
  未宣称满足原正式断联后 <=1s 停稳要求。
- Provider 本次增量为 6 个源文件和 7 个测试文件；新增回归先在旧实现失败，再证明
  1.6 秒无 ACK 但输入持续到达时仍可控制，晚 ACK 不延长已停止输入的期限。相关回归
  **223 passed**（2 条旧 TLS deprecation warnings）。板端当前文件派生的三个修改模块，
  与未修改的现有 ROS/QoS 热修依赖一起离线验证 **173 passed**；有效结果文件为
  `watchdog-input-lease-20261014/board-artifact-validation-final.txt`，不要使用中间 overlay
  的结果替代最终板端派生版本验证。语法与 `git diff --check` 通过，未提交共享 WIP。
- 用户确认“已准备好，14:35581”后，连接平板 `172.22.205.14:35581`，APK 保持 v2010 /
  `0.1.0-phaseA7`。预检电量 98%、静止、离桩、无任务占用。只替换板端
  `runtime/duole_central/navigation_board/{manual_mapping_guard.py,agent.py,manual_mapping_runtime_cli.py}`
  的最小派生改动；保留 ROS/QoS 与其他现有热修，未改 selector、APK、速度或碰撞配置。
  精确板端回滚目录：
  `/home/ztl/duole-issue31-nav-ws/runtime/issue33/watchdog-input-lease-before-20261014/`。
- 经正式 `./scripts/start_product_voice_board_session.sh` 启动 Product App-only Runtime，
  Gateway 直接加载本机修复。首次会话 `manual_mapping_8eb6c3b053114e59935f11237db66a33`
  五分钟窗口内始终 epoch0/seq0，没有收到 acquire/intent；窗口到期后监控停止并保存。
  该轮 **NO_CONTROL_INPUT**，不是移动验收成功。用户随后反馈不能操作，确认是已结束旧页；
  重开 App 并恢复准备页后，等待新的现场准备确认，没有自行重跑。
- 用户再次明确“已准备好”，本轮日志独立放在
  `session-20260929/watchdog-input-lease-retry-20261014/`；重新核验电量 **91%**、
  静止、离桩、无占用。会话 `manual_mapping_1cbbb19309fe453a8163867bbd9c57ca` 开始于
  UTC `08:21:40.681489`，控制页可用后监控从 `08:23:34.256410` 开始 300 秒窗口。
  用户亲自操控，助手没有注入摇杆动作。用户反馈：
  “已经操作完毕，距离较远的时候出现控制不稳定，然后摇杆灰了”。
- epoch1：**226 条全部 applied**，板端接收跨度 **22.530593s**；松手停车请求
  `08:24:50.502891` → 确认 `08:24:51.134561`，**631.670ms**，再次获取控制成功。
  epoch2：Gateway 收到 511 条、向 SSH 提交 485 条，板端 458 applied / 27 discarded，
  接收跨度 **50.112597s**；其余包括 21 条 Gateway 本地 discarded 与末尾 5 条失配错误。
  本轮共 711 条板端记录，与 SSH 提交/完成数量一致；回包最大 **450.512ms**，
  epoch2 板端处理最大 **70.857ms**。不能把全部 SSH 差额或本轮位置关联唯一归因于 Wi-Fi。
- 中断直接链路：板端最后 applied 是 epoch2 seq498，接收时间 `08:25:41.721255`。
  seq499 在 Gateway `08:25:41.724661` 收到并提交，板端 `08:25:42.029224` 收到后因
  TTL 过期 discarded，SSH 总等待 **419.467ms**。seq500–506 虽继续到达 Gateway，
  但已在那里过期、本地 discarded，没有 SSH 提交；不是有效输入持续到达却只等 ACK
  续期的旧故障。新鲜输入失活约 1s 后 `control_lease_expired`，seq507–511 失配；
  监控 `08:25:43.154380` 因 CONTROL_FAILURE_ABORT 中止，**非五分钟到时**。
- 中断停车请求 `08:25:42.741955` → 确认 `08:25:42.985651`，**243.696ms**。
  从板端最后有效指令接收至停车确认为 **1264.396ms**；不能只拿 244ms 声称断联后一秒内
  停稳。监控 `08:25:46.816457` 点击立即停止并保存，`08:25:46.878244` 结束，地图 r133；
  最终保存沿用同一次中断停车确认，不是独立第三次停车测量。**重复控制 HIL FAIL，阶段 A 未通过。**
- 发现待验证的 App 时钟校准风险：
  `dart/duole_engineering_client/lib/manual_mapping_control.dart:223` 每条服务端帧都用
  `server_time - local_receipt_time` 覆盖 offset。固定实际时差为 0、回包延迟 350ms 的纯
  计算示例，会使下一条即时发送/即时到达的指令呈现 350ms 帧龄，超过 200ms TTL。
  此示例是代码计算复现，不是现场单向延迟测量；本轮未记录 App offset、原 sent_at 与
  Gateway 判定帧龄，不能确定七条本地丢弃全部源于时钟偏差还是实际传输/调度延迟。
  下一步优先区分 App↔Gateway 帧龄、时间校准与传输队列，暂不继续放宽 TTL/watchdog。
- 收尾实测：本轮 Gateway、Product、monitor 均 exit0，8443 无监听、Runtime IPC 消失；
  `duole-navigation-stack.service` active，建图/Guard inactive、Guard socket 不存在。
  已部署 1000ms 参数保留，没有自动回滚、再次 HIL 或修改 App 时钟代码。
  `parsed-timing.json`、`timing-summary.json`、`hil-result.json`、`final-session.json` 与
  `clock-calibration-example.json` 留在本轮目录。再次设备测试需要新的现场准备确认。

## 最新续接状态：2026-10-14，用户确认前轮在路由器附近，远处对照测到 ICMP 427/601 ms 尖峰

- 用户澄清刚才 90 秒测试已在路由器附近，并已移到较远位置，明确要求重新测试。
  本轮把 `ssh-network-diagnosis-20261014/` 标为用户确认的近处基线；远处用逐字节相同
  harness、相同 90 秒/约 100 ms SSH 间隔/两条 450 次 ping。只做网络诊断，没有运动、
  建图、配置变更或产品代码修改，也没有重测真人 HIL。
- 两端仍关联同一个 AP、5.805 GHz、Power Management off。驱动信号评分：近处
  本机约 42→40/100、导航板 45→47/100；远处本机 28→27/100、导航板 29→28/100。
  不把评分当作 dBm，也未独立确认两个设备的物理安装关系。
- 两轮 SSH 都 **901 发 / 901 收、exit0**：近 → 远，中位 **3.768 → 5.832 ms**，
  p95 **12.995 → 26.029 ms**，最大 **150.782 → 188.824 ms**。>100 ms 次数反而
  **6 → 3**，因此不能说所有尖峰频率都增加；两轮都没有 SSH >200 ms。
- 同步本机 → 网关 ping：近 450/450、均值 2.932 ms、最大 134.582 ms；远
  450/449、1 个无回复（0.222%）、均值 4.464 ms、最大 **426.632 ms**。
  本机 → 导航板：近 450/450、均值 4.467 ms、最大 138.371 ms；远也 450/450，
  均值 6.686 ms、最大 **601.454 ms**。不能把这两个 ICMP 尖峰冒充 SSH 回包耗时。
- 远处 echo 自身处理最大 386.466 μs、本机 pipe read 最大 2.319 ms，心跳未记录
  >50 ms Python 调度空档。`CONFIG_INET_DIAG` / 重传统计限制与前轮相同。
  结果支持较远位置的网络质量变差，但两轮分时测试仍有干扰/负载等变量；近处也有尖峰，
  距离不是已证明的唯一原因。原 HIL 400–578 ms SSH 回包等待仍未在这两轮 echo 复现。
- 远处样本及 comparison.json 位于 ignored task-local
  `session-20260929/ssh-network-diagnosis-far-20261014/`；没有覆盖近处或历史结果。
  SSH/ping 均已退出，板端只读收尾：导航 active、建图/Guard inactive。
  Gateway 本地租约按确认续期的问题仍待修复；原 TTL、独立 watchdog 与停车红线未变。

## 最新续接状态：2026-10-14，只读 SSH/网络诊断复现 100–151 ms 尖峰，距离对照待现场移动

- 用户同意并要求开始上一条网络诊断计划，本轮只做当前位置 SSH echo、ICMP 与系统只读
  统计；未启动建图、运动或修改 App/Provider/板端代码及网络配置。最近真人 HIL 仍为
  下方 10 月 13 日 FAIL，阶段 A 状态未变。
- 90 秒固定约 100 ms 间隔的持久 OpenSSH 管道，共 **901 发 / 901 收**、SSH exit0；
  RTT 中位 **3.768 ms**、p95 **12.995 ms**、最大 **150.782 ms**，6 次 >100 ms，
  没有 >200 ms。echo 线程处理最大 **447.138 μs**；本机 pipe read 最大 **0.907 ms**，
  10 ms 心跳采样未记录 >50 ms 的本机 Python 调度间隔。返回的 seq 全部匹配。
- 同时本机 → 网关 `172.22.205.254`：450/450、0% ping 丢包，平均 **2.932 ms**、
  最大 **134.582 ms**；本机 → 导航板：450/450、0% ping 丢包，平均 **4.467 ms**、
  最大 **138.371 ms**。因此短时间低平均 ping 不能排除间歇尖峰；独立 echo/ICMP 都
  有尖峰，不能只归因于 Gateway 业务处理。
- 两端同一个 5GHz AP；测试开始驱动信号评分本机约 42/100、导航板约 45/100，结束
  约 40/100、47/100，Power Management 都 off。评分不是 dBm，也不能仅凭它断定距离。
- 分段仅为跨时钟估计：早/晚低 RTT 样本的 offset 估计相差约 2.7 ms。最大样本上行段
  估计约 146 ms，另有回程段约 127/124/117 ms 的样本，支持双向传输/SSH 接收路径
  的偶发延迟；单向数字不是内核抓包时间，不能把 SSH 子进程或内核/驱动调度排除。
- **重传证据缺失，不能说无重传。** 内核 `CONFIG_INET_DIAG` 未启用，ss 回退信息没有
  完整的单连接 TCP 重传计数；tcpdump 不在当前环境，sudo -n 需要密码。没有尝试安装、
  加载内核模块或改权限；没有把全机 RetransSegs 当作本条 SSH 连接的重传证据。
- 这轮未复现原 HIL 的 400–578 ms，也未加载 SLAM/持续控制负载。故只能确定只读
  网络路径本身可有较小尖峰，尚不能唯一确定无线距离、干扰、重传或 SSH/内核调度。
  下一步是路由器附近的位置对照；该步骤涉及真人移动设备，需要独立的现场完成确认。
  还需确认 Gateway 主机 .44 是否与导航板 .19 在同一机器人上，避免错误声称只改了某一端距离。
- 原始样本、两端 TCP 队列快照、ping 输出、临时只读 harness、analysis.json 放在
  ignored task-local `session-20260929/ssh-network-diagnosis-20261014/`，没有覆盖旧探针。
  SSH 与 ping 已退出，板端收尾只读核验导航 active、建图/Guard inactive。

## 最新续接状态：2026-10-13，流水线 REAL 复测仍 FAIL，已确认回包侧租约判定问题

- 用户已明确授权部署并测试，并于本轮回复“已准备好，14:44529”。平板
  `172.22.205.14:44529` 已连接，APK 仍为 v2010 / `0.1.0-phaseA7`，无需重新安装。
  实时预检电量 **65%**、未充电、离桩、静止、无任务占用，传感器/停止链/版本检查通过。
  导航 active、建图/Guard inactive，开发 drop-in 与 marker 实测保留。
- 经正式 `./scripts/start_product_voice_board_session.sh` 的 App-only 入口启动 Runtime，
  加载 Provider 流水线修复和新的异步探针。未替换板端文件、APK 或 selector。
  5 个 Gateway 源文件与 139 项回归通过时一致，复用该历史软件结果；异步探针上一轮
  5 项本机回归通过。本轮 helper 仅更新日期目录及平板端口。
- 本轮 ignored task-local 目录为 `session-20260929/gateway-pipeline-hil-20261013/`；
  已适配 `submit_frame`、ordered completions、SSH submit/future 完成和 WSS 写回计时。
  `ws_write_complete` 只证明服务端写回完成，不等于 App 已收到。旧同步探针没有加载。
  新 monitor 保持 300 秒及 1000 ms 红线，错误词汇与新探针兼容。
- App 审计备用码启动会话 `manual_mapping_99c6c3122ec64c46b226283567400191`，UTC
  `13:24:44.640115` 开始。控制页实测可用后，监控于 `13:27:56.052397` 绑定本会话
  启动 300 秒窗口，准备阶段未计入窗口。用户亲自操控，助手未注入摇杆动作。
- 用户确认：“持续控制正常，松手后可再次使用，再次使用过程中出现中断，然后等待停止确认”。
  epoch1 板端 seq1–365 全 applied，接收跨度 **36.401386 秒**。正常松手 release
  `13:29:24.877792` 返回 stop_pending；板端停车 `13:29:24.853767` →
  `13:29:25.534013`，**680.246 ms**。epoch2 acquire `13:29:26.124250` 成功，
  板端 seq1–76 也全 applied，接收跨度 **7.607959 秒**。
- 流水线现场生效：epoch1 seq66 在 seq65 的 199.530 ms SSH 回包前已经 submit；
  epoch2 seq73 等回包期间 seq74/75/76 继续 submit，最多 4 条 pending，并全部在板端
  应用。故本轮剩余故障不是“前条未确认，后条无法发出”。
- epoch2 seq73/74/75/76 的 SSH 总等待分别 **402.609 / 577.643 / 479.539 / 383.161 ms**；
  对应板端处理仅 **4.798 / 2.667 / 2.753 / 2.385 ms**，四条均 applied。
  seq77 在 `13:29:33.775869` 被 Gateway 收到，校验触发本地 lease 到期/stop；
  `13:29:34.072321` 返回 LEASE_MISMATCH，随后 pending seq73–76 也返回失配。
  数据库 last_seq 因此停在 72，不能把它误说成板端只应用到 72。
  **直接阻断关系：Gateway 本地期限仍在 complete_intent 收到确认后更新；返回侧长延迟
  会被当作租约失活，即使新鲜指令已持续转发并在板端应用。** SSH 尖峰的具体网络或
  线程调度原因仍未唯一确定；不能将全部差额断言为 Wi-Fi 丢包。
- monitor `13:29:34.213922` 因 CONTROL_FAILURE_ABORT 中止，非窗口到期，
  `13:29:37.258457` 点击立即停止并保存。中断停车确认 `13:29:33.794092` →
  `13:29:34.583145`，**789.053 ms**。最终保存沿用该次停车确认，不能把它算成独立
  第三次实测停车。`13:29:37.320477` 终态 immediate_stop_saved / user_immediate_stop，
  地图 r161。本轮全部 441 条板端 intent 均 applied，但重复控制仍中断，**阶段 A 未通过**。
- 收尾本轮实测：Gateway、Product SIGINT 后均 exit0，monitor exit0；任务进程均消失、
  8443 无监听、Runtime IPC 消失；导航 active，建图与 `duole-manual-mapping-runtime.service`
  inactive，Guard socket 不存在。原始日志、`final-session.json`、`parsed-pipeline.json`、
  `hil-result.json` 留在本轮目录。日志存在并发 print 的相邻 JSON/文本拼接，已按固定
  prefix + JSON raw_decode 恢复全部 441 条 SSH 完成记录，未因此遗漏尾部响应。
- 下一步建议修正 Gateway 对“输入活性”和“板端确认”的租约语义，覆盖“返回侧停顿
  >400 ms、输入仍持续到达并被板端应用”的软件复现；保留原 200 ms TTL、板端独立
  400 ms watchdog、松手停车及 <=1000 ms 真实停车基线，不直接放宽阈值。
  本轮仅完成已授权部署/HIL 及日志定位，未继续修改产品代码或自动重测。
  再次真人 HIL 必须新的现场准备确认。

## 最新续接状态：2026-10-11，Gateway 转发流水线已本地修复，尚未现场复测

- 用户对上一轮建议回复“同意”，本轮完成 Gateway 同步阻塞的本地实现及软件验证。
  Provider 写入已通过当前沙箱权限申请；仅更新 5 个源文件与 3 个测试文件的本次增量，
  保留两处共享工作树原有 WIP，未提交、安装 APK、部署、更新 selector 或启动机器人/ROS/HIL。
- 本机回归覆盖 TLS → REAL service → SSH stdio → 实际板端 TTL guard：首条处理/回包
  延迟 250 ms，原实现第二条必须等首条回包，测试按预期失败。修复后第二条及松手 stop
  在首条回包前已到达 agent 的 stdin；旧帧 discarded 后同 lease 的新鲜 seq2/3 可应用。
  测试使用本地子进程模拟传输延迟，不是一次真实 Wi-Fi/SSH 或车轮验收。
- 修复文件位于 Provider `duole_central/app_gateway/`：`navigation_board_ssh.py` 增加有界
  FIFO 请求流水线和单一响应读取线程，合并响应按序匹配，超时/EOF/坏 JSON 关闭通道并
  使所有 pending 失败；`real_manual_mapping.py` 转换异步板端结果，保留原 clock calibration；
  `mock_manual_mapping.py` 将 begin/complete 分开，等回包时不持有 SQLite 写事务，确认时
  重新核对 lease/epoch/seq 和截止时间；`gateway.py` / `tls.py` 持续收包，按序确认结果，
  release/watchdog/断线后取消旧确认资格，旧回包不能恢复已停止或新租约的控制状态。
- 原同步 `handle_frame`、`apply_intent`、板端 client `apply_manual_mapping_intent` 入口保留；
  stdio 的文本 stdin/stderr 也保留，以兼容现有同步调用和现场诊断包装器。
  **旧 intent 分段探针挂在同步 invoke/_read_response 上，不能直接当成新流水线的计时证据。**
  下一轮运行前须适配 submit/完成回调与 WebSocket 写回的探针和监控；不要把提交返回当作
  applied 或 App 已收到 ack，也不要复用旧 select 等待时间解释新链路。
- 保留原时间戳、200 ms TTL、400 ms base watchdog、0.20 m/s / 0.90 rad/s 和 <=1000 ms
  真实停车基线；discarded 只消费 seq，不续期、不输出、不推进地图。软件回归还覆盖
  无输入时 watchdog 停车、等待回包期间松手、断线、凭据撤销及重获租约后旧 ack 被拒绝。
- 最终在实际 Provider 工作树运行 6 个相关测试文件：**139 passed，2 条旧 TLS 版本测试的
  deprecation warnings**；8 个修改文件语法检查、`git diff --check` 通过。
  测试文件为 `test_mock_manual_mapping.py`、`test_real_manual_mapping.py`、
  `test_navigation_board_ssh.py`、`test_tls_policy.py`、`test_teleop_websocket_flow.py`、
  `test_event_websocket_flow.py`。普通遥控与事件 WebSocket 回归也通过。
- 本轮本地增量补丁、命令与结果保存在 ignored task-local
  `session-20260929/gateway-pipeline-20261011/{gateway-pipeline.patch,software-validation.txt,final-software-tests.txt}`。
  隔离开发副本在 `/tmp/issue33-gateway-pipeline-20261011`；产品代码已经写回 Provider。
- **阶段 A 仍未通过，最新真人 HIL 仍是下方 10 月 10 日 FAIL。** SSH 尖峰的具体网络/调度
  原因尚未确定；本轮消除了回包等待对后续转发的阻塞，不宣称尖峰消失或摇杆稳定已验收。
  下一步是适配现场诊断入口、在明确的运行/部署授权内加载本地修复，并在新的现场准备
  确认后由用户操控复测。未做 10 月 11 日机器人运行状态核验，不把 10 月 10 日收尾状态
  当作实时状态；不自动重跑。epoch2 是否由用户再次按压触发仍待确认。

## 最新续接状态：2026-10-10 16:43，去掉 App ack 门控后仍中断，SSH 分段已捕获

- 用户要求去掉“上一条未确认就暂停发送”后，已移除 App `_intentInFlight` 门控；持续按住
  时每 100 ms 发送当前输入。保留最新一条 discarded 的即时补发、旧 discarded 不额外补发、
  松手/断线停止发送。先验证新回归在原实现失败，再通过页面 35 项测试及两文件 analyze。
  首次 Flutter 测试启动被本机 HTTP 代理干扰，取消测试进程代理后正常执行。
- 用户明确授权安装并测试，已构建并安装 v2010 / `0.1.0-phaseA7`，设备版本与启动界面
  核验通过；原 v2009 APK 保存在本轮目录 `app-debug-before-no-ack-gate-v2009.apk`。
  本轮目录为 ignored task-local `session-20260929/no-ack-gate-hil-20261010/`。
- 用户重新确认“已准备好”后实测电量 62%、静止、离桩且未充电，无任务占用；经正式
  App-only 入口启动会话 `manual_mapping_6d080760009f4b16ad7f09ed06c4a30e`。
  控制页就绪后于 UTC `08:42:35.367029` 启动绑定该会话的 300 秒监控，没有窗口超时。
  用户报告控制两三秒后变灰且无法再用。**连续控制 HIL FAIL，阶段 A 未通过。**
- 首个租约 seq1–26 applied，板端首次到末次有效接收跨度 2.487111 秒。seq27 为
  **discarded**，不是 applied：Gateway handle_frame 268 ms，SSH 252.190 ms，其中
  select 等待 249.931 ms；板端收到后处理仅 6.968 ms，IPC 6.486 ms。
  `08:43:01.429839` 返回 discarded，`08:43:01.472000` watchdog stop_pending，
  随后 seq28–30 为 MANUAL_MAPPING_LEASE_MISMATCH，监控 `08:43:01.531982` 中止。
  App 门控去掉后，Gateway 仍在同一 WSS 收包线程同步等待 SSH；后续输入不能及时转发，
  discarded 又不续 watchdog，因而仍会到期。SSH 等待与板端执行耗时的差额缩小了延迟
  范围，但不足以唯一断言网络丢包或收到请求前的具体调度原因。
- 日志另记录 epoch2 acquire 与 43 条 applied（约 4.221 秒），发生在监控中止与实际点击
  保存之间；正在向用户核对是否再次按压，不据此认定为自动恢复或另一轮 HIL 通过。
  监控 `08:43:08.768134` 点击立即停止并保存，`08:43:09.620446` 结束，地图 r51。
  **最终保存**停车确认 745.519 ms；首个租约的精确停车确认时间未保留，不用最终保存
  的耗时替代，也不宣称完整停止矩阵通过。当前会话已结束，因此摇杆无法继续使用。
- 已收尾实测：导航 active，`duole-mapping-manual.service` 和
  `duole-manual-mapping-runtime.service` inactive，Guard IPC socket 不存在；任务 Gateway
  exit0、Product 在 SIGINT 收尾后 exit143，均已退出，8443 无监听、Runtime IPC 已移除。
  注意 Guard 所在单元为 `duole-manual-mapping-runtime.service`，
  `duole-manual-mapping-guard.service` 并不存在，不能只用后者的 inactive 判断。
  本轮没有板端替换或 selector 更新，TTL/watchdog/速度/停车阈值未变；不自动重跑。
  下一步应处理 Gateway 同步转发阻塞及 SSH 尾延迟，真车复测须重新确认现场准备。

## 最新续接状态：2026-10-10 15:55，第二轮真实控制仍中断，已获得分段证据

- 用户重新“已准备好”，实测电量 63%、静止、已离桩；正式产品链路启动第二轮会话
  `manual_mapping_fe037b268c774da0a8ffe374543e8e5e`，UTC `07:54:44.045131` 开始。
  用户确认机器人已移动一段距离，并确认变灰前一直按住摇杆。**连续控制 HIL FAIL，
  阶段 A 未通过**；本轮证据在 `session-20260929/control-phase-hil-20261010-retry2/`。
- 板端 seq1–172 全部 applied，同一租约从 `07:55:16.066079` 到 `07:55:33.654030`，
  约 17.588 秒；用户在控制页就绪、监控启动前已经开始操控。监控在控制页就绪后
  `07:55:32.416574` 正常绑定本轮启动 300 秒窗口，本次没有窗口到期或失焦保存。
- seq172 板端处理 3.331 ms（IPC 2.693 ms），Gateway handle_frame 共 18 ms，
  `07:55:33.678248` 打印 applied。seq173 在 `07:55:34.311362` 打印错误，处理 9 ms；
  因而前条 handle_frame 完成到后条开始约 **624 ms**（按毫秒级四舍五入耗时反推）。
  Gateway 先记录 control_lease_expired / watchdog stop_pending，随后 seq173 为
  MANUAL_MAPPING_LEASE_MISMATCH；监控 `07:55:34.433043` 因控制错误中止。
- 新探针已实际捕获：172 条板端分段记录，最大板端总耗时 49.184 ms；seq44/88
  SSH 为 112.362/122.523 ms，select 等待分别 111.300/121.616 ms。触发中断前的
  seq172 没有长 SSH 等待，本轮没有复现历史 2.1 秒。当前空档尚不能唯一归因于 App
  调度、ack 到达、WebSocket 传输或 Gateway 循环调度；现有 trace 在 WebSocket 写回前
  打印 handle_frame 完成，不能把它当作 App 已收到 ack。下一步应补齐这一段的收发时间证据，
  不通过放宽 TTL/watchdog 或停车阈值掩盖中断，不盲目重复试车。
- 本轮停车 `07:55:34.089695` → `07:55:34.885741`，**796.046 ms**；监控
  `07:55:37.819122` 点击立即停止并保存，`07:55:37.881314` 结束，地图 r27，终态
  immediate_stop_saved / user_immediate_stop。该次停车确认低于 1000 ms，不能替代完整停止矩阵。
- 已收尾：导航 active、建图/Guard inactive，任务 Gateway/Runtime 正常退出，8443
  无监听，IPC socket 不存在；本轮没有新产品代码修改、板端替换或 APK 安装。
  修正监控复用前一轮同文件的 4 项软件回归，分段探针复用对应历史软件验证；真人控制中断
  尚未修复，下一次 HIL 必须取得新的现场准备确认。

## 最新续接状态：2026-10-10，监控计时已修正，复测被失焦保存中断

- 新平板 ADB `172.22.205.14:37893` 已连接，APK 仍为 v2009；上一轮开发 drop-in 和
  Guard marker 实测仍有效。首次预检电量 38% 未启动，用户再次“已准备好”后电量
  64%、静止、未充电、已离桩，无任务占用，经正式 App-only 入口启动。
- 新 ignored task-local 目录 `session-20260929/control-phase-hil-20261010/` 保留本轮日志。
  `watch-stop.py` 改为显式绑定 `--session-id`，由调用方在控制页就绪后才启动 300 秒
  窗口，不依赖“会话开始时间晚于监控启动时间”，不再让准备过程耗掉窗口。
  本轮纯软件 4 项回归通过，覆盖已开始会话、窗口到期保存、控制错误与停车超标中止、
  已结束会话不重复点击；全部使用临时 SQLite 和替代 ADB，没有运动请求。
- 会话 `manual_mapping_65ad129355864def826e14540da20426` 于 UTC `07:42:36.766452`
  开始，`07:42:54.037702` 以 `unverified_saved` / `screen_locked` 结束，地图 r6；
  `lease_epoch=0` / `last_seq=0`，无 intent 分段日志，监控尚未启动。
  **控制测试 NOT_EXERCISED，历史长等待仍未定位，监控修正尚无完整真人复测结论。**
- Android 记录 `15:42:56.148` 焦点移至 `control_center`，`15:42:56.701` 返回 App。
  随后测得平板比主机快约 2.29 秒；换算后的失焦时间约 `15:42:53.86`，与保存结束吻合。
  App `didChangeAppLifecycleState` 将 inactive 映射为 screenLocked，支持系统控制中心
  抢焦点触发保存的解释；不能把 reason 名称直接当作实际锁屏，也未确定是谁打开控制中心。
- 已停止本次尝试，无自动重跑。收尾实测导航 active、建图/Guard inactive，任务
  Gateway/Runtime 正常退出，8443 无监听、IPC socket 不存在。下一轮需保持 App 前台、
  关闭系统浮层并取得新的现场准备确认；仍由用户操控摇杆，保护阈值不变。

## 最新续接状态：2026-10-09，诊断入口已部署，本轮控制未执行

- 长等待只读诊断确认：App 等上一条 ack 才发送下一条，Gateway 同一控制连接同步等待
  SSH 回包；延迟 ack 的纯软件复现能触发独立 watchdog 停车并使后续旧租约失败。
  尚不能将历史 2.1 秒唯一归因于网络或板端处理。10 月 9 日无 ROS/运动的 SSH echo
  200 样本最大约 12.9 ms，没有复现历史尖峰。
- 已经用户授权部署独立板端入口
  `/home/ztl/duole-issue31-nav-ws/bin/issue33-board-control-phases-20261009`，记录收到请求、
  IPC 前后和 stdout flush 后时间；Gateway 记录 select 等待及读取阶段。原正式入口未改，
  回滚选择 `issue31-navigation-board-agent`。探针定向测试 12 项通过、启用探针的 CLI
  测试 12 项通过；SSH 回归 26 项通过，另 3 项日志捕获测试在不启用探针的基线也失败。
- 用户明确要求恢复上一轮开发配置后，已由用户在机器人 `.19` 执行 sudo install / daemon-reload，
  实测 `/run` 下手动建图 drop-in 生效，指向 `slam-no-collision.launch.py`；Guard 开发 marker
  仍为 enabled。开发机 `.44` 与机器人 `.19` 都叫 RK3588，不能只凭 shell hostname 判断。
- 用户重新确认现场可以测试后，经正式 App-only 产品入口启动；电量实测 66%、底盘静止。
  新会话 `manual_mapping_b7b6b47188494c7cb967fc514561d5db` 于 UTC `08:43:00.898055`
  开始，控制页就绪，但最终数据库 `lease_epoch=0` / `last_seq=0`、Gateway 无控制日志、
  板端无 intent 分段日志，**本轮控制 NOT_EXERCISED，不能据此定位历史长等待或判断停车延迟**。
- 用户询问摇杆变灰原因：监控从 UTC `08:36:54.899852` 提前开始计入 600 秒准备窗口，
  启动和备用码页面导航消耗了大部分窗口；`08:46:55.058362` 超时，监控于
  `08:46:58.680747` 点击立即停止并保存，`08:46:58.754248` 会话结束，地图 r130。
  这是本轮摇杆变灰的直接原因。监控计时尚未修正；下一轮应在控制页就绪后启动有界操作窗口，
  先消除准备过程消耗窗口的问题，再取得新的现场准备确认，不自动重跑。
- 收尾实测导航 active、建图和 Guard inactive，任务 Gateway/Runtime 已正常退出，8443
  无监听、IPC socket 不存在。证据在 ignored task-local
  `session-20260929/control-phase-diagnostics-20261009/` 的日志、`final-session.json`、
  `hil-result.json`；速度、TTL、watchdog 和停车红线未调整，阶段 A 仍未通过。

## 最新续接状态：2026-10-08 16:26，过期帧丢弃已实测

- 用户授权“按这个方式修改看看”、同意部署并再次确认“已准备好”后，已部署过期帧
  `discarded` 行为并安装 APK v2009 / `0.1.0-phaseA6`。Gateway 本地或 Guard 丢弃过期
  指令时消费序号，保持上次有效速度，不更新租约或 watchdog；App 收到 `intent_discarded`
  后立即发送当前摇杆位置。Guard 允许递增序号有间隔，仍拒绝重放/乱序。
  `200 ms` TTL、`400 ms` base watchdog、`<=1000 ms` 停车上限和速度上限未调整。
- 软件验证在部署前通过：Provider 定向 175 项、实际板端原件衍生补丁的 Guard/IPC/REAL
  87 项、Flutter 页面 35 项、页面 analyze、Dart 合同与超标停车恢复回归、生成合同一致性。
  本轮 HIL 复用这些对应输入未改变的结果；未把软件通过计作整机验收。
- **目标行为 PARTIAL_PASS，连续控制 HIL FAIL，阶段 A 未完成。** 正式链路会话
  `manual_mapping_b1796a8ec0b841e9b097eb8d5e0d2d53`，UTC `08:22:25.934676` 开始；
  实测电量 57%，页面 80% 未作为预检依据。首个租约 `seq=9` SSH 总耗时 2084.906 ms，
  其中发送前 0.150 ms、回包等待 2084.756 ms，最终回包仍为 `intent_applied`；
  随后 `seq=10` 于 `08:26:22.635761` 为 `MANUAL_MAPPING_LEASE_MISMATCH`。
  App 单指令等待回包的机制会在这段长等待内阻止后续发送，符合 watchdog 失去新鲜
  指令而停车的解释；未捕获板端该次停车原因日志，不能断言网络丢包或唯一底层原因。
- 重连后第二个租约 `seq=6` 于 `08:26:24.497241` 返回 `intent_discarded`，
  `seq=7` 于 `08:26:24.566531` 返回 `intent_applied`，同租约后续接受到 `seq=30`。
  这直接证实“过期帧丢弃后，下一条新鲜指令可继续”已生效；没有完成 20 秒连续控制。
- 监控在首次 intent 错误后中止本轮并点击“立即停止并保存”，不是五分钟窗口超时。
  首次停车记录 `08:26:20.852085` → `08:26:21.525557`，673.472 ms；
  最终保存停车 `08:26:26.922095` → `08:26:27.622360`，700.265 ms，均未超标。
  终态 `immediate_stop_saved` / `user_immediate_stop`，地图 r130，
  `08:26:27.663397` 结束。用户随后确认“已停止”。
- 收尾实测导航 active、建图和 Guard inactive，Gateway/正式 Runtime 已正常退出，8443
  无监听，`/tmp/issue33-session/app-read.sock` 不存在。本轮只替换板端
  `manual_mapping_guard.py`，未替换 CLI/IPC/ROS 文件或 selector；精确回滚对象为
  `/home/ztl/duole-issue31-nav-ws/runtime/issue33/manual_mapping_guard.before-stale-discard-20261008.py`。
  v2008 回滚 APK 与部署记录、原始日志、`final-session.json`、`hil-result.json` 留在
  ignored task-local `session-20260929/stale-intent-discard-20261008/`。
- 下一步主线是定位 SSH 回包长等待与等待期间后续控制无法发送的具体原因，不放宽
  watchdog 或停车红线。再次真人 HIL 必须重新确认现场准备；不自动重跑。

## 最新续接状态：2026-10-08 15:16（优先于下方 10 月 7 日历史）

- **最新 REAL 复测 FAIL，已停止并保存；阶段 A 未完成。** 本日先补板端固定错误码透传，
  复测捕获 `seq=23` 过期拒绝（SSH 3 ms）。只读测得板端时钟慢约 13 ms，真实 Guard
  回归证实跨时钟域原样转发指令时间存在误拒绝和误接受；Gateway 已实施每 lease 的保守
  时间戳换算，不重打指令时间、不续 200 ms TTL。155 项软件回归通过，本轮复用该结果。
- 用户再次“已准备好”后，本轮通过正式 App-only 入口加载 Gateway 修复，未再次替换板端或 APK。
  电量实测 59%，会话 `manual_mapping_e915f71455994e918febe9927f5c090f`，UTC
  `07:15:39.657015` 开始，`seq=1..129` 接受约 13 秒，`seq=130` 因过期被拒绝，SSH 203 ms。
  拒绝归零时间 `07:16:35.891257`，轮速确认 `07:16:36.591622`，差 **700.365 ms**；
  最终 `07:16:42.791482` 为 `immediate_stop_saved` / `user_immediate_stop`，地图修订 32。
  本日首轮最终保存停车约 807 ms，与本轮 700 ms 分开；首轮首次故障停车耗时缺失。
- 本轮收尾核验：导航 active，建图和 Guard inactive，Gateway/Runtime 正常退出，8443 无监听、
  `/tmp/issue33-session/app-read.sock` 不存在。此为本轮收尾实测，下次仍须重新只读核验。
- 本日板端诊断补丁保留在 `/home/ztl/duole-issue31-nav-ws/runtime/duole_central/navigation_board/`
  的 `manual_mapping_guard.py`、`cli.py`；仅增固定码透传，未覆盖原有恢复热修。
  精确回滚文件在 runtime 的 `issue33/manual_mapping_guard.before-control-diagnostics-20261008.py`
  和 `issue33/cli.before-control-diagnostics-20261008.py`。不要把板端既有恢复热修误说成本日新部署修复。
- 当前 Gateway 换算实现位于 Provider `duole_central/app_gateway/real_manual_mapping.py`；精确
  回滚副本为旧 `session-20260929/control-diagnostics-20261008/real_manual_mapping.before-clock-calibration-20261008.py`。
  Provider 原有共享 WIP 全部保留，未提交、未整树替换。当前环境已允许 Provider 本地编辑。
- 只读 SSH echo（无 ROS/运动请求）200 样本复现一次 **210.55 ms** 尖峰；后续 200/600
  样本最大 22.82/102.052 ms。两端路由为 Wi-Fi，地图/控制 SSH 与 SLAM/Guard 锁分离在
  实际板端已存在。尚不能将 203 ms 唯一归因于丢包、无线省电或板端 CPU。
- 下一轮直接使用已准备的本地诊断入口
  `session-20260929/clock-calibration-hil-20261008/run-gateway-latency.sh`，仍配合同目录上级
  `run-product.sh` 的正式入口；记录发送前耗时、回包等待、板端拒绝归零时指令年龄。
  `trace-control-latency.py` 已离线检查原结果/异常不变、单次调用、年龄仅记录一次和不打印秘密。
  **尚未加载新诊断入口，不需要再次替换板端或 APK。须新的现场准备确认后才运行 HIL。**
- 本轮原始证据目录（ignored task-local）为
  `/home/ztl/duole-app/flutter/duole_engineering_app/build/issue33-phaseA-local-20260927/session-20260929/clock-calibration-hil-20261008/`，
  包含 `gateway.log`、`stop-monitor.jsonl`、`final-session.json`、`preflight.json` 和只读 SSH 测量。
  继续禁止打印凭据、备用码或 ADB 注入摇杆；控制页只能在 `x=10` 的摇杆外边距滑动导航。
  开发碰撞保护仍不完整，速度、watchdog、停车红线与正式验收门均未调整。

## 先读：当前状态与接手边界

- **阶段 A 尚未完成，完整 Issue 33 更未验收。** REAL 手动建图可由 App 启动，机器人会按摇杆方向移动，地图和轨迹会更新，也能立即停止并保存未验证地图；持续按住摇杆仍会突然停车，重按才能继续，有时出现“等待停止确认”或控制通道错误。
- 2026-10-07 最后一轮现场复测已因 **1078 ms 停车确认超过 1000 ms 安全上限**结束。用户明确说“停车确认超时，保存好，今天的工作到此结束”。该轮地图已通过 App 的“立即停止并保存”结束，数据库终态为 `immediate_stop_saved` / `user_immediate_stop`，地图修订号 52。**当天不再试车；新聊天须重新取得对应部署/HIL 授权与操作员到场准备确认。**
- 最后核验：导航板 `duole-navigation-stack.service=active`，`duole-mapping-manual.service=inactive`，`duole-manual-mapping-runtime.service=inactive`；本机 Gateway 8443 无监听，App-only Product Runtime 与 Gateway 测试会话均已退出。以上是 **10 月 7 日收尾时的状态**，下一轮先只读重新确认，不把它当作实时状态。
- 用户亲自操控摇杆；助手只做配对、页面导航、备用码启动、监控和必要的停止/保存。此前用户明确要求“你只要配对好就行了，我来操控”。不要用 ADB 注入摇杆动作。
- 两处工作树均有大量共享 WIP。`/home/ztl/duole-app` 是 App 仓库，`/home/ztl/duole-workspace` 是 Provider 仓库；遵守各自 `AGENTS.md`，保持无关修改原样。当前会话环境只允许写 `/home/ztl/duole-app` 和 `/tmp`，Provider/板端改动要按届时权限执行。

## 下一轮推进顺序

1. 先在**纯软件侧**定位 `MANUAL_MAPPING_GUARD_UNAVAILABLE` 的底层异常及 1078 ms 停车确认的时间构成。该 Gateway 错误是多种板端/IPC/传输异常的统一包装，现有 trace 还不能证明唯一根因。优先读 `duole_central/app_gateway/real_manual_mapping.py`、`navigation_board_ssh.py`、`duole_central/navigation_board/manual_mapping_guard_ipc.py`、`manual_mapping_runtime_cli.py`、`ros_manual_mapping_runtime.py`，结合下方最后一轮日志和数据库时间戳。当前服务已停止，可以离线分析，无需启动真车。
2. 只实施当前阻断点所需的最小修复，保持 `400 ms` base watchdog、`<=1000 ms` 停车红线、`0.20 m/s` / `0.90 rad/s` 上限和松手停车链；做直接覆盖缺陷的回归。不要通过把 1 秒改成 2 秒掩盖中断。地图编码优化已减少一项耗时，但现场仍失败，后续需查其余热点和真正的错误链。
3. 纯软件结论明确后，再提出**具体可审查的板端替换对象、回滚目标与复测内容**，按新一轮授权启动正式产品链路和现场 HIL。先确认操作员在机器人旁、急停可及、空旷区域可测、机器人电量和静止等预检；任一停车超标即停止并保存，不宣称阶段 A 通过。每次失败 HIL 后重新取得现场准备确认才重跑。
4. 连续控制稳定后，再验证重复按压、正常保存和地图资料库读取。系统弹窗抢焦点曾导致 App 以 `screen_locked` 自动保存，此现象与控制中断分开处理。完整安全矩阵、碰撞保护恢复及正式 REAL capability 属阶段 B，不以阶段 A 结果代替。

## 10 月 7 日最后一轮证据（本轮实测）

- 本机 trace：`/home/ztl/duole-app/flutter/duole_engineering_app/build/issue33-phaseA-local-20260927/session-20260929/gateway-fastpath-hil-20261007.log`。UTC `15:22:03.780`、`15:22:08.077`、`15:22:12.334` 共 3 次 `MANUAL_MAPPING_GUARD_UNAVAILABLE`，分别在 intent `seq=1,4,25`；其间有正常 `intent_applied`，随后又可恢复。后续日志还有 `MANUAL_MAPPING_INTENT_EXPIRED`、`stop_pending`、`MANUAL_MAPPING_RECONNECT_NOT_ALLOWED`，并非单一故障码。
- 本轮会话数据库：同目录 `mapping.manual.sqlite3` 的 `mock_manual_mapping_sessions` 最新行，`session_id=manual_mapping_41a50b28c8f342439f9c38225c845291`，`phase=terminated`、`control_state=stopped`、`outcome=immediate_stop_saved`、`transition_reason=user_immediate_stop`；开始 `2026-10-07T15:21:41.428088+00:00`，结束 `15:23:25.485738+00:00`。UI 曾显示“停车确认耗时 1078 ms，超过 1000 ms 安全上限”，数据库记录 `stop_requested_at=15:22:43.402424+00:00`、`stop_confirmed_at=15:22:44.480687+00:00`，差约 1078 ms。**这是告警对应的一次停车记录，不能将它误说成 15:23:25 最终“立即停止并保存”动作的耗时。**
- 平板最终显示“已立即停止并保存未验证地图”，地图 `r52`、轨迹 18 点；最后核验板端两个建图服务 inactive，导航 active。操控中地图轨迹增长、机器人运动；因此起步与投影真实可见，但连续控制和停车红线不通过。
- 现场 Guard 进程在出错时仍 `active`，`NRestarts=0`（上一轮也观察到），最后一次观察约 88 秒运行时 CPU 45.7%。CPU 竞争只是待验证假设；不能把它写为已证实根因。

## 已实施的变更与运行时差异

- Provider 工作树 `/home/ztl/duole-workspace/duole_central/navigation_board/ros_manual_mapping_runtime.py` 增加 `stride == 1` 的地图预览编码快路径；其余 downsample 路径保留。板端实际文件 `/home/ztl/duole-issue31-nav-ws/runtime/duole_central/navigation_board/ros_manual_mapping_runtime.py` 已用**基于板端原版衍生**的补丁替换，SHA-256 `c91ff2051b0b7f3ab99ed68a62c1527c23ba19a125da15b6ab8be372af383597`。板端原版和精确回滚备份 `/home/ztl/duole-issue31-nav-ws/runtime/issue33/ros-manual-mapping-runtime.before-snapshot-fastpath.py` 的 SHA-256 为 `7644416961c3bfd24e345755ecf3ac494b4ad54450835d257114f9679f532def`；待部署文件在同目录 `ros-manual-mapping-snapshot-fastpath.py`。本机对应副本在上述 session 目录的 `board-current-ros-manual-mapping-runtime.py`、`board-snapshot-fastpath.py`。Provider 文件还含既有共享 WIP；板端文件另有独立 `tf_static_qos_profile` 热修，后续不能盲目用 Provider 整文件覆盖板端。
- 快路径的纯软件验证：Provider 定向 41 项 pytest 通过，`py_compile` 与 `git diff --check` 通过；板端离线导入对一张 358×385 合成地图的编码结果与旧版一致，旧版中位耗时约 136.7 ms，新版约 32.7 ms。**现场复测仍失败，不能把性能改善等同控制问题修复。**
- 为按用户要求在功能阶段取消碰撞减速，板端使用独立的手动建图 launch：`/home/ztl/duole-issue31-nav-ws/runtime/issue33/slam-no-collision.launch.py`，由 `/run/systemd/system/duole-mapping-manual.service.d/issue33-no-native-collision.conf` 将 `duole-mapping-manual.service` 的 ExecStart 指向该 launch；`/cmd_vel` 在手动建图期间直接由 runtime 到 `can_driver`，不经过 native collision monitor。另有 state marker `manual-mapping-collision-development.disabled` 关闭 Guard 碰撞过滤。**这仅是阶段 A 受控开发配置，碰撞保护当前不完整；不要据 App 准备页“防碰撞保护已满足”断言正式保护已启用。** `/run` drop-in 重启后可能消失，下一轮先核验，不自动恢复。原正常导航 launch 未修改。
- App 当前现场 APK 是 v2008 `0.1.0-phaseA5`；最后一轮平板 ADB 为 `172.22.205.14:41625`，端口会变化。板端 SSH 为 `ztl@172.22.205.19`，专用 identity `/home/ztl/.ssh/id_ed25519_duole_nav_172_22_205_19`；本机 Gateway 使用 `172.22.205.44:8443`。以上地址只供定位历史环境，重新连接前先核验当前地址。
- 正式现场 App-only Runtime 脚本在 session 目录的 `run-product.sh`，Gateway 诊断脚本 `run-gateway-trace.sh`，平板页面导航工具 `tablet-ui.py`、`fill-address.py`、`prepare-map.py`、`start-map.py`。正式 Runtime 脚本调用 `./scripts/start_product_voice_board_session.sh`；备用码脚本会生成带审计的短码并关闭临时维护 marker。**不要复制或输出 `engineering.token`、配对 secret、备用码或私钥。** 脚本仅是历史工具，下一轮先审查当前内容和状态再用。

## 验收与文档位置

- Issue 33 权威工单：[33-real-manual-mapping-teleop-guard.md](issues/33-real-manual-mapping-teleop-guard.md)，顶部为 2026-09-27 阶段 A/B 顺序，末尾历史评论目前只更新到 2026-10-01；其 `Implementation` 文案已经落后于 10 月 7 日实测，接手以本记录和原始证据为准，后续再整理工单。
- 当前仍可确认的阶段 A 部分结果：App 启动 REAL 建图成功；摇杆方向经修正后符合用户操作；地图/轨迹显示有实测；立即停止后未验证地图保存成功。**尚未通过：长按连续控制、松手再按的稳定性、`<=1 s` 停车、正常保存及资料库读取、重复完整流程。**
- 历史现场证据和更早修复：[2026-09-29 控制恢复](../../docs/evidence/issue33/20260929/control-recovery/README.md)、[2026-09-30 电量预检](../../docs/evidence/issue33/20260930/phaseA-preflight/README.md)。10 月 7 日完整原始 trace 与数据库留在上面的 ignored task-local session 目录；本文件不包含密钥或地图 JSON。
- 2026-10-07 上一轮（本次优化前）也记录长按摇杆会突然停止，`MANUAL_MAPPING_GUARD_UNAVAILABLE` 与确认停车；另一次 App 自动保存的 `transition_reason=screen_locked` 经用户确认是系统弹窗抢焦点。该问题需要独立排查，不能混入 Guard 超时根因。
