# Issue 33 REAL 验收包

本目录由 `tools/issue33_real_evidence_collector.py` 管理。不要手工把 stop/check 改为
`passed`，也不要手工把 `evidence_class` 改成 `REAL`。

## 当前状态

- Bundle：`issue33-real-evidence.json`
- 对象：`robot-home` / `RK3588` / `172.22.205.19`
- 状态：`PRELIMINARY_REAL`
- Stop：`1 / 11`
- Check：`5 / 12`
- 已记录 stop：`pointer_up`（`900 ms`，现场报告前进约 `8.5 cm`，自动停车、无肉眼可见后退、
  无继续滑行、最终稳定；急停可及且充电线无拉扯、缠绕或受压）。
- 已记录 check：固定 profile clamp、碰撞减速/阻断、默认 unarmed+zero、
  `MOCK_NO_MOTION` 回归、普通 teleop 独立关闭。
- capability marker：未生成。

## 操作约束

- 每个物理测试前必须由现场操作员单独确认准备完成；一次确认只授权一个明确场景。
- HIL 脚本必须先生成结构化 `stop_telemetry`，再在停车后 5 分钟内记录现场操作员观察。
- 操作员观察必须确认急停可及、机器人已停车、无肉眼可见后退、无继续滑行且最终稳定。
- 采集器默认拒绝覆盖已记录 stop/check；修复或重跑不能静默替换旧证据。
- 只有 11 个 stop 和 12 个 check 全部完成，`finalize` 才能把包改为 `REAL`；随后仍需
  独立运行 `tools/issue33_real_gate.py` 才能生成 marker。

## 状态命令

```bash
python3 tools/issue33_real_evidence_collector.py status \
  --bundle docs/evidence/issue33/20260828/real-acceptance/issue33-real-evidence.json
```

`pointer_up` 已完成并正式入包：真实轮式里程计确认
`fault_at <= zero_at <= wheels_stopped_at`，总延迟 `900 ms`。下一项人工场景是
`app_background`；必须先完成该场景专用执行器的软件验证，再单独取得现场准备确认，不能复用
`pointer_up` 的授权。

`app_background` 专用执行器为 `tools/issue33_app_background_hil.py`，板端探针为
`tools/issue33_app_background_board_probe.py`。它通过受控 navigation-board agent 建立真实
mapping operation，并调用 SHA-256 固定的
`RealManualMappingService.command_session(action="app_background")`；停车后必须得到
`terminated / unverified_saved / stop_confirmed`，同时确认旧活动地图已恢复且新地图未激活。
导航板未永久安装 Gateway 源码；执行器只把确定性 provider Python 模块包传入单次进程的系统
临时目录，模块包 SHA-256 与 `real_manual_mapping.py` SHA-256 都写入 lifecycle 结果并由本地复核。

无新 motion authorization token 时执行器不会调用 SSH。现场授权前只运行：

```bash
python3 tools/issue33_app_background_hil.py \
  --output docs/evidence/issue33/20260828/real-acceptance/pending/app-background-01-stop-telemetry.json \
  --lifecycle-output docs/evidence/issue33/20260828/real-acceptance/pending/app-background-01-lifecycle-result.json \
  --dry-run
```

真实执行约前进 `0.06 m`，固定 profile 后最高约 `0.07 m/s`；开始前要求前方扫掠走廊至少
`1.0 m`。探针持续监听 `/cmd_vel`、真实轮式里程计和激光，只有 lifecycle 命令、未验证保存、
恢复旧地图、不激活新地图、真实停车 `<=1000 ms` 以及最终服务恢复全部通过时，才会在本地写入
两个 pending 文件。

第一次 `app_background` 尝试在正式 board preflight 阶段 fail closed，未进入运动、未创建租约、
未发送非零 intent、未保存地图且未创建 pending 文件。只读诊断确认 BMS 报告
`NOT_CHARGING(3)`，同时部署拓扑为
`/motion/selected_cmd_vel → collision_monitor → /cmd_vel_safe → can_driver`，但旧 preflight
只检查 `/cmd_vel`。本地最小修复和 `--repair-mapping-safety-topology` 已通过 63 项定向测试，
并已在精确授权后安装到导航板。部署 SHA-256 为
`2b72b5cdf11be28f893ed649b1112bd228f3bc91e8316a5271553716b54c2fc7`，旧版本已保存到专用修复
备份；安装没有改变服务状态。

安装后的 App 同格式 `read_mapping_safety` 已确认传感器、碰撞链、停车链、静止、存储和版本
全部健康。现场确认充电线一直连接且屏幕显示正在充电，但连续 15 秒的 10 个 BMS 样本均为
`29.3 V / 99.3% / 0.0 A / NOT_CHARGING(3)`，正式机器门仍为
`charging_confirmed=false / docked=false`。当前 `can_driver` 仅按瞬时电流生成充电状态；不能把
高电量或现场观察直接当作 BMS 连接证明，否则拔线后的满电机器人也会误通过。详细根因记录见
`source-diagnostics/app-background-01-preflight-failure.json`；在 BMS 再次产生真实正充电电流或有
等价可信机器连接信号前不得重跑，之后仍需新的单场景现场准备确认。

一次经单独准备确认的无运动充电线重插诊断证明：拔线后 BMS 为约
`-0.9～-1.0 A / DISCHARGING(2)`，重插后最高为 `1.7 A / CHARGING(1)`，共采到 10 个正充电
样本，现场屏幕同时显示正在充电；但满电截止后约 14 秒又回到
`0.0 A / NOT_CHARGING(3)`，正式 mapping safety 因而仍拒绝。没有启动 mapping 或发送运动。
根因与原始时间序列见 `source-diagnostics/full-charge-replug-diagnostic.json`。不能利用短暂窗口
抢跑 HIL；最小候选修复应在 `can_driver` 观察到正充电后，将满电零电流投影为标准 `FULL(4)`，
并在任何负电流出现时立即清除该状态。该修复需要独立开发验证和导航栈重启授权。

`full-charge state repair` 已按 TDD 形成候选并在独立现场准备确认后安装。`can_driver.py` SHA-256 为
`1338c614d939b8045097f22b67e2d89c4144917d22908bc19f53b12273830031`，升级器 SHA-256 为
`fbb33d48c731625af306e18731a2546851c032016e71a4f4add4fdecee39442b`；Provider 候选/相邻回归
`115 passed`，App 验收工具 `27 passed`，板端无硬件实例化 smoke 的状态序列为
`[3, 1, 4, 2, 3]`。三份正式运行文件现均为候选 SHA，三份专用备份均为前任 SHA
`e1544c4f86e3e2a2cf25422cd5efe037b16863900742e148dff8c2c61e317c53`；安装回执确认
`duole-navigation-stack.service` 只重启一次。重启后导航 active，三个 mapping 单元 inactive，
ROS 安全通道仍为单一 `motion_arbiter → collision_monitor → can_driver`。

本次新运行的跨重启 BMS 监视确认新进程持续得到约 `3.7～3.8 A / CHARGING(1)`，正式
`read_mapping_safety` 在电量 `88%` 时得到 `charging_confirmed=true / docked=true`，传感器、
碰撞链、停车链、静止、存储和版本也全部通过。由于安装验证时电量尚未重新充满，本次没有物理
重现“满电后电流归零 → FULL(4)”；该转换当前由 TDD 与板端 ROS import smoke 覆盖，待下次自然
充满时可补充只读实机证据。这不再阻断 `app_background` preflight，但该 HIL 尚未重跑，仍必须
取得新的单场景现场准备确认。

`app_background` 第二次尝试在新的现场单项授权后执行，但在任何 mapping、租约、非零 intent、
运动或保存之前被走廊门拒绝：`app_background_preflight_corridor_below_1_0m`。没有生成新的
pending 输出，导航保持 active，三个 mapping 单元保持 inactive，本次不计入 stop 验收且没有
自动重跑。只读 `/scan_filtered` 诊断复现雷达前向最近净空 `0.908 m`，连续障碍簇位于机器人
前方偏左约 `0.22 m`；TF 证明 `laser` 相对 `base_link` 为 `180°`，探针方向无误。门槛不降低，
需清开该区域并取得新的单场景准备确认。原始诊断见
`source-diagnostics/app-background-02-preflight-corridor-failure.json`。

`app_background` 第三次尝试通过走廊预检并建立 mapping/session/lease，但第一条 intent 返回
`MANUAL_MAPPING_GUARD_UNAVAILABLE`，abort stop 同时返回 `MAPPING_GUARD_UNAVAILABLE`；没有保存
地图或生成 pending 输出，清理后导航 active、三个 mapping 单元 inactive。该时段 18 个真实
`can_driver` 编码器样本首尾完全一致，确认机器人未运动，本次不计入 stop 验收且没有自动重跑。

根因不是现场或 Guard 参数：正式 Gateway 每个 `arm/intent/stop` 都新启动一次板端 Python agent，
实测最小空请求进程耗时 `0.709～0.791 s`，确定性超过 `400 ms` base watchdog 和 `200 ms` intent
TTL。未放宽任何时限或安全门；TDD 候选改为在 manual mapping 开始前建立带固定 ready 握手的
JSON Lines session，并在同一认证进程复用全部 `manual_mapping_*` 请求，精确 stop ACK 后关闭。
失败清理还会尝试 abandon，恢复旧活动地图并清除临时会话。Provider 定向/相邻回归
`198 passed`，App Issue 33 工具 `27 passed`。候选已在精确授权后上传并安装；安装后只读核验确认
CLI 与 wrapper 分别为上述候选 SHA，前任 SHA
`cbfd46e7d96955e0c665a2b2f7c39091a3791f754b5afa244b528bc25576845f` 和
`790f834683771aaab06e0a0f48beb2875ca4573266c9fd82883bbbb5f001aba9` 已保存为 `root:root`
专用备份。导航保持 active，三个 mapping 单元保持 inactive，没有活动持久 session；安装没有重启或
切换服务。随后经独立无运动授权验证：一次 SSH/单一远端 Python PID 完成 ready 后连续处理 5 个
fail-closed 探测请求，往返 `12.965～28.046 ms`，均低于 `200 ms` intent TTL 和 `400 ms` base
watchdog；stdin 关闭后进程以 `0` 退出、无 stderr、无残留，服务状态前后不变。该验证没有发送
运动或状态变更 action。遗留 `active/revision 0` SLAM 恢复、真实 arm/intent/stop 和
`app_background` HIL 尚未验证。详细记录见
`source-diagnostics/app-background-03-guard-unavailable.json` 与
`source-diagnostics/persistent-board-session-no-motion-verification.json`。

第四次 `app_background` 在新的单场景准备确认后执行。走廊预检通过，遗留 SLAM 状态完成恢复，
manual mapping/runtime 启动并建立新的 SLAM session；但在任何已接受运动 intent 之前远端探针非零
退出，两个 pending 文件均未生成。调用超过首个 30 秒工具输出窗口后，原始 stderr 没有被调用层
保留，因此当前只把失败定位到“session begin 之后、首个 accepted intent 之前”，不猜测更具体根因。
该窗口 12 个真实 `can_driver` 编码器样本均为
`L=-1528681 / R=1608814`，SLAM 位姿变化约 `0.1 mm`，确认无真实运动。清理结果为新 session
`abandoned`、operation stopped、旧活动地图 `my_map3` 保持不变、导航 active、三个 mapping 单元
inactive，且无残留 persistent session。本次不计入 stop 验收，没有自动重跑。下一最小动作是经新
授权执行一次带分阶段输出的无运动 `arm → zero intent → stop` 诊断，再决定修复，详细记录见
`source-diagnostics/app-background-04-control-failure.json`。
现场操作员 `ztl-onsite` 随后确认机器人全程没有移动、车轮无抖动或瞬间转动、当前完全停稳，
充电线无拉扯或缠绕且硬件急停始终可及；该观察与编码器证据一致，但不把失败尝试计为 stop 通过。

为避免再次盲跑物理场景，已按 TDD 新增一次性无运动 persistent-session 控制诊断器及板端探针。
编排器 SHA-256 为
`c9dbacb9e88f77d6da2bad975784646e16c71064b20b34b45f4c5184ca469b44`，探针 SHA-256 为
`4ea6fe9bc5fc0a3d5623a5d82de44cf16e8bac27dab060e68e29e9ae3f56e279`。探针只允许硬编码
`linear=0.0 / angular=0.0`，依次记录 mapping start、runtime ready、SLAM begin、arm、zero
intent、stop confirmed、abandon 和 mapping stop；成功或失败都输出结构化阶段结果，最终服务不恢复
则拒绝落盘。新增及相邻 Issue 33 工具回归 `34 passed`，Python 编译和无 SSH dry-run 通过。
尚未真实执行；该诊断会切换一次导航/mapping 服务，必须取得新的精确授权。

经新的精确授权已执行一次无运动 persistent-session 控制诊断，8 个阶段全部通过：mapping start、
runtime ready、SLAM begin、guard arm、固定双零 intent applied、stop confirmed、SLAM abandon 和
mapping stop。唯一 accepted seq 为 `1`，无 cleanup error；provider bundle SHA 仍为
`30b5a293579b75c56516a02c43ec79837504db5afe2ff9a9a79860656d9192b0`。运行窗口内 11 个真实
编码器样本全部固定为 `L=-1528681 / R=1608813`，确认没有车轮运动；结束后导航 active、三个
mapping 单元 inactive、无残留 session。该结果证明 persistent transport 与板端
`begin/arm/zero-intent/stop` 链正常，但没有覆盖 `RealManualMappingService.acquire_control` 或非零
intent，不能据此把第四次失败判定为已修复，也没有重跑 `app_background`。结构化结果见
`source-diagnostics/persistent-session-control-no-motion-01.json`。现场操作员 `ztl-onsite` 确认机器人
全程未移动、车轮无抖动或瞬间转动、当前完全停稳，充电线安全且急停始终可及，与机器证据一致。

基于上述分层结果，已按 TDD 将诊断器升级为应用层双零候选：它使用实际
`RealManualMappingService` 依次执行 `start_session`、`acquire_control`、固定双零
`apply_intent`、`release_control(reason="terminal_abandon")` 和 `command_session(action="abandon")`，
从而覆盖第四次 HIL 尚未隔离的应用层路径，同时不发送非零速度、不保存地图。编排器、板端探针和
测试的 SHA-256 分别为
`89eb416b9b657d423809d455c22097c9c412f2d11ee3aed7d18fe42baa422eee`、
`297a44d52404e55ec7819c62fde58967e6d15150f24a110fd6777950b8844506`、
`aa9a1d7f63dc160c7896f65e5e7231b3178727d8fcdc1bc8ea45101830897f2f`；provider bundle SHA-256
保持 `30b5a293579b75c56516a02c43ec79837504db5afe2ff9a9a79860656d9192b0`。红灯测试先因应用层入口
不存在而失败，绿灯后全部 Issue 33 工具回归 `34 passed`，`pyflakes`、Python 编译和无 SSH
dry-run 通过。该候选尚未在机器人上执行；它会切换一次导航/mapping 服务，必须取得新的精确授权，
其结果也不计为 stop 场景验收。

经操作员 `ztl-onsite` 新的现场准备确认与单次服务切换授权，应用层双零诊断已执行一次且没有重跑。
`start_session`、`acquire_control` 和唯一 `linear=0.0 / angular=0.0` intent 均成功，
`accepted_seq=1`；随后 `release_control` 在 `application_stop_confirmed` 阶段失败，错误链为
`MANUAL_MAPPING_GUARD_UNAVAILABLE <- 'stop_requested_at'`。外层恢复门确认导航 active、三个 mapping
单元 inactive、持久 agent 不存在、operation stopped；由于应用层 abandon 被同一停车错误阻断，
SLAM 状态保留为 `active/revision 1`，没有运行时或控制租约，下次授权启动时由既有 interrupted
恢复逻辑处理。本次不计 stop 验收。操作员 `ztl-onsite` 直接观察确认机器人全程未移动、车轮无
抖动或瞬间转动、机器人最终完全停稳、充电线安全且急停始终可及；该观察证明本次失败是安全的，
不把功能失败改为通过。

实机失败与确定性 500 ms 慢快照回归共同确认：首个应用层 intent 在已启动固定 400 ms watchdog 后
同步读取真实 SLAM 并原子写快照，返回时租约已被板端自动撤销；stop 错误响应又因 Gateway 解析器
先读取 `stop_requested_at` 而泄漏 `KeyError`。修复没有延长 watchdog/TTL：首次快照移到 acquire
之前，控制期间返回缓存进度，后续重快照由独立运行时线程完成；错误响应先校验 schema。导航板
`manual_mapping_runtime_cli.py`、`manual_mapping_slam_runtime.py`、Gateway
`navigation_board_ssh.py` 和升级器 SHA-256 分别为
`dbdd293756ccba256f24e10f12f6f96db17290ce41dd12a46ff2aef45fb30853`、
`4f52ea32d5bae70339c5ddb11a2dc58d8d66cb3b8dbfe45f4341d1015785578d`、
`ca97af905cd72e22f821e110094df14e059dd361f68add016707f15428e6debe`、
`320db6f7865484d472c47fafc71756ed4e778ffd210aeb595f8ffeba22b0b7f1`；新 provider bundle SHA 为
`c648fe4b5948480a5166e99b2eb71ef1e4dcc39a508e9b09c980698966bd455d`。Provider 相关回归
`134 passed`，App Issue 33 工具 `34 passed`。

经精确授权上传并安装 `--repair-slam-snapshot-control-path`。初版升级器在写运行文件前正确拒绝，
因为它没有把已安装的 persistent-session `cli.py` SHA `306097da…` 纳入组合态校验；当时未创建
repair 备份，运行哈希和服务状态均未改变。新增回归先失败，再只为该组合态固定精确 CLI SHA，
未知 SHA 仍拒绝，相关回归 `50 passed`。最终运行文件 SHA 为 `dbdd2937…` 与 `4f52ea32…`，前任
`2159bdbe…` 与 `b57f2e5a…` 已保存到 `root:root` 专用备份。导航 PID `726045` 和 active 时间戳
`535912251221` 安装前后相同，三个 mapping 单元始终 inactive，确认没有重启或服务切换。该代码
仅安装到磁盘，尚未启动或经过新一轮应用层双零诊断。原始结果、分析和部署证据分别见
`source-diagnostics/persistent-session-application-control-no-motion-01.json` 与
`source-diagnostics/persistent-session-application-control-no-motion-01-analysis.json`、
`source-diagnostics/slam-snapshot-control-path-repair-install.json`。

新的现场准备与单次服务切换授权后，应用层双零复测在 `mapping_started` 前被板端安全门拒绝；导航
PID `726045` 和 active 时间戳未变，两个 mapping 单元无 journal，编码器持续为
`L=-1528681 / R=1608813`，所以没有发生服务切换、session 建立或零 intent 发送。正式安全快照除
电量 `100%` 外均健康，但当前导航进程未观察到正充电电流，故
`charging_confirmed=false / docked=false`，`start_mapping` 按设计 fail-closed。

本地诊断器随后把该合法的启动前失败二次判为 `result_invalid`，没有写正式结果；根因是校验器无条件
要求 `session_process_reused=true`。确定性回归先失败，再把该字段固定为必须与
`mapping_started in completed_stages` 精确一致，Issue 33 工具本次新运行 `35 passed`。没有自动重跑；
本次不计任何 stop 或双零通过。操作员 `ztl-onsite` 直接观察确认机器人全程未移动、车轮无抖动或
瞬间转动、最终完全停稳、充电线安全且急停始终可及；随后已重插充电线，屏幕显示正在充电。详细记录见
`source-diagnostics/persistent-session-application-control-no-motion-02-preflight-failure.json`。

操作员随后重插充电线且屏幕显示正在充电，但第三次诊断前的正式只读快照仍为
`battery_percent=100 / charging_confirmed=false / docked=false`；满电充电器没有产生当前进程可观察的
正电流。其余安全项全部通过。第三次诊断命令尚未执行，未发生服务切换或 intent，新的单次授权尚未
消耗；不以屏幕观察替代机器充电门。下一步需在现场看护下暂时拔线，让电量降到非满电后再重插并复查。
记录见 `source-diagnostics/persistent-session-application-control-no-motion-03-charging-refresh-preflight.json`。

现场拔线后正式快照降至 `90%`；重插后 12 个原始 BMS 样本连续为 `present=true`、
`CHARGING(1)`、约 `26.7～26.8 V / +3.7～3.8 A`。随后完整正式快照通过
`charging_confirmed=true / docked=true`，机器人静止且其余安全项全部健康。第三次诊断仍未执行，
等待新的现场准备与单次服务切换授权。

经新的现场准备与单次服务切换授权，第三次应用层双零诊断八阶段全部通过：唯一
`linear=0 / angular=0` intent 为 `applied / accepted_seq=1`，stop confirmed，session 与 SLAM 均
`abandoned`，无 cleanup error。导航恢复 active，三个 mapping 单元 inactive，无持久 session，
operation stopped，原活动地图 `my_map3` 已恢复。mapping 窗口编码器持续
`L=-1578180 / R=1652334`，导航恢复后持续 `L=-1578179 / R=1652334`；跨服务的单计数量化差异不代表
持续运动。操作员 `ztl-onsite` 直接观察确认机器人全程未移动、车轮无抖动或瞬间转动、最终完全
停稳、充电线安全、急停始终可及且屏幕仍显示正在充电。该诊断证明安装后的应用控制路径通过，但不计为
非零运动 stop 场景。
结果和分析见 `source-diagnostics/persistent-session-application-control-no-motion-03.json` 与
`source-diagnostics/persistent-session-application-control-no-motion-03-analysis.json`。

已使用的专用执行器为 `tools/issue33_pointer_up_hil.py`，板端探针为
`tools/issue33_pointer_up_board_probe.py`。执行器固定目标
`ztl@172.22.205.19`，无一次性 motion authorization token 时不会调用 SSH。该执行器的无运动
dry-run 命令为：

```bash
python3 tools/issue33_pointer_up_hil.py \
  --output docs/evidence/issue33/20260828/real-acceptance/pending/pointer-up-01-stop-telemetry.json \
  --dry-run
```

真实执行约前进 `0.06 m`，归一化线速度 `0.7`，固定 profile 后最高约 `0.07 m/s`；板端先要求
前方扫掠走廊至少 `1.0 m`，运行中保持雷达/轮式里程计新鲜且 Guard 必须返回 `applied`。
结束后只有手动服务/runtime 均 inactive、导航 active，且结构化 telemetry 通过同一正式校验时，
本地 pending 文件才会原子写入。
