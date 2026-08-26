# 贯通现场地图授权与事务性地图切换

Status: ready-for-human

Type: HITL

User stories covered: 176, 181–182, 185–187, 199

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

建立地图高风险写操作的现场证明，并交付一条真实、可回滚的地图切换纵向切片。机器人屏幕
显示短时动态二维码；Android 扫描后取得与 actor、robot、installation 和 nonce 绑定的现场
授权。开始建图每次消费独立授权，地图切换和语义编辑使用 15 分钟现场地图管理会话。地图
切换只在机器人位于共同充电桩且无活动运动任务时执行，由导航板完成加载、定位、提交或回滚。

## Acceptance criteria

- [ ] 每次建图使用独立、短时、单次消费的 `mapping_authorization`；它不复用账号登录态或旧配对码，也不授予普通 teleop。
- [ ] 机器人屏幕显示动态二维码并提供 6 位短码备用；普通用户在屏幕不可用时不能降级启动，工程维护模式才可从机器人本机终端生成受审计短码。
- [ ] 一次现场验证可建立最长 15 分钟的 `map_management_presence` 会话，用于切图、房间目标、巡逻路线和禁行区编辑；超时、App 后台、token 撤销或离开受控 LAN 后失效。
- [ ] 地图写操作要求 `maps.manage`；开始建图、切图、房间目标、巡逻路线和禁行区修改必须现场，重命名、非当前地图删除和回收站恢复可远程执行。
- [ ] 自主/手动建图主按钮始终可见可点；准备页逐项展示回桩、电量、任务、传感器、存储和版本等未满足条件及可执行引导，不提供绕过预检。
- [ ] 地图切换只在 BMS 新鲜且确认充电、底盘静止、无导航/巡逻/回充/遥控/建图任务时接受；有任务时要求用户先停止，不静默取消。
- [ ] 导航板加载目标地图并在共同充电桩锚点完成可信定位后才原子提交活动地图；加载或定位失败恢复原地图和原 revision。
- [ ] 机器人重启只恢复上次明确启用的地图，并且仍需在充电桩完成锚点定位；不按最新时间或最高评分自动选图。
- [ ] 一个机器人同一时刻只有一个地图管理操作者；其他用户只看到“另一位用户正在建图/管理地图”，不接收进度或操作权，已有全局 `robot.stop` 仍有效。
- [ ] 切换、授权、失败回滚和会话失效均通过稳定 operation/event 恢复，携带 actor、request ID、TTL、idempotency key 和审计摘要。
- [ ] 使用至少两张真实地图完成屏幕扫码、在桩切换、重启恢复、故障回滚和并发手机 HITL/HIL 验收。

## Blocked by

- [04 实现一次性配对、安装实例绑定与撤销](04-pairing-session-revocation.md)
- [06 实现持久事件投影、WebSocket 补拉与重同步](06-event-projection-replay-resync.md)
- [14 实现独立紧急停止与机器人停止确认](14-emergency-stop-confirmation.md)
- [30 实现多地图资料库、评分、回收站与容量管理](30-multi-map-catalog-quality-trash.md)

## Comments

### 2026-08-26 软件验收证据

- 已按 TDD 完成 App、App Gateway、OpenAPI/生成合同、一次性授权、15 分钟现场会话、六项建图预检、事务性切图状态机、回滚/重启恢复、稳定 operation/event 与受控 LAN 证明的软件纵向切片。
- `run_issue_31_validation.py` 一键门禁通过：Python 266 项、合同消费者 24 个入口、工程客户端 35 个入口、Flutter 46 项；三个 Dart/Flutter 包静态检查均无问题。
- `duole-workspace` 全仓回归通过：`2944 passed, 1 skipped, 4 warnings`；跳过项为既有硬件依赖测试。
- arm64 目标调试 APK 已生成：`flutter/duole_engineering_app/build/app/outputs/flutter-apk/app-debug.apk`，111,752,466 bytes，SHA-256 `0307fa8c73bd1b93674261d14dc9076c8f4c6367f7f49334ae85139e70abafc2`。
- 当前授权范围内没有机器人屏幕的生产接线，也没有导航板真实 SLAM/地图加载/桩锚定位适配器；Gateway 对这两条生产路径保持 fail-closed，测试 fake 不能冒充 HIL。
- 转为 `ready-for-human`：仍需授权修改 `/home/ztl/duole-qt-runtime`（机器人屏幕二维码/6 位码），并提供或授权导航板源码/部署仓库或正式接口；随后连接两台 Android 手机、两张真实地图和安全在桩窗口，执行本工单最后一条 HIL 及前十条的实物确认。完成前不勾选验收项。

### 2026-08-26 屏幕接入与 HIL 门禁增量证据

- 已获授权修改 `/home/ztl/duole-qt-runtime`，并在改动前保存可恢复备份到
  `backups/issue31-map-challenge-before-20260826/`。机器人屏幕现可显示严格校验的动态
  二维码、6 位备用码、用途和倒计时；只有 QML 图片加载完成并返回匹配 request ID 的
  `presented` ACK，Gateway 才返回 201。无屏幕、ACK 超时、篡改或过期消息均失败关闭。
- Qt 实际部署目录复验通过：协议 3 项、中继真实 WebSocket 5 项、QML 离屏 1 项，
  `qmllint` 通过；真实 Gateway 客户端到真实 Qt 中继再到模拟 QML ACK 的跨仓库回环通过。
  正式 QML/bridge 进程仍是 8 月 22 日启动的旧进程，尚未在安全窗口重载，因此这些证据
  不能替代实体屏幕确认。
- App 在手动建图、自主建图和地图切换扫码前都会先请求机器人屏幕展示挑战；新增请求
  只返回 robot、purpose、expiry、request ID 和 idempotency key，不向 App 泄露 proof
  或 6 位码。一键软件门禁更新为 Python 275 项、Dart 合同 25 个入口、工程客户端 36 个
  入口、Flutter 47 项，全部通过且三个包静态分析无问题。
- 新 arm64 APK 为
  `flutter/duole_engineering_app/build/app/outputs/flutter-apk/app-debug.apk`，
  111,760,318 bytes，SHA-256
  `c9a4be3d2b6829fd1f8031ba34ff3eb327b90af53f42df89c7236df39cdac2d8`。
- 新增 `tools/issue31_hil_gate.py`、13 项单元测试和可填写证据模板。门禁绑定 APK 哈希、
  robot、两台在线 Android 手机、两张不同地图、会话时间、17 项检查、真实制品 SHA-256
  以及 operation/event ID，并拒绝未脱敏 token、proof、短码、二维码载荷和私钥。当前实机
  执行正确保持红灯：`found 0, need at least 2`。
- 已只读定位导航板：`ztl@172.22.205.19`（hostname `RK3588`），正式工作区
  `/home/ztl/elderbot_ws`，存在 `my_map2` 和 `my_map3`。远端是带大量既有未提交改动的共享
  工作树；当前桩锚仅绑定 `my_map3` 且状态为 `candidate`，没有 `my_map2` 的已验证共同桩锚。
  在明确授权导航板改动和确认安全在桩窗口前，不修改、不构建、不重启该工作区。
- 因仍缺两台 Android 手机、导航板改动授权、两图共同桩锚批准和安全在桩窗口，Issue 31
  继续保持 `ready-for-human`，所有验收勾选仍为空，避免把软件 fake/回环误报为 HIL。

### 2026-08-26 实体 Android 与隔离导航板接入证据

- 两台真实 Android 手机均已通过无线 ADB 完成身份检查，设备型号分别为 `PHK110` 和
  `2211133C`，SDK 均为 36；HIL 门禁已强化为拒绝模拟器、非 Android 传输以及畸形 UTF-8
  设备元数据，并要求每台手机安装目标 SHA-256 的 APK 且相机 AppOps 为可用；对应单元测试
  17 项通过。
- `PHK110` 已通过无线 ADB 安装目标 APK；`2211133C` 因 HyperOS 在无 SIM 卡时禁止开启
  “USB 安装”，改为先经无线 ADB 推送到下载目录、核对 SHA-256，再由用户从系统文件管理器
  手动安装。安装后已通过 ADB 确认包名
  `com.duole.engineering.duole_engineering_app`、版本 `0.1.0`、`versionCode=1` 和
  `targetSdk=36`。两台手机现已同时通过无线 ADB 在线，`ro.kernel.qemu` 均为空，AppOps
  显示相机权限为 `foreground`；第一台动态端口变化后也已重新连接成功。
- 使用目标 APK 和证据模板重新运行实体门禁，已通过 APK SHA-256、两台真实 Android、两台
  已安装 APK 哈希与相机权限绑定，以及 evidence schema 四个阶段；当前预期停在
  `FAIL evidence.apk_sha256: does not match tested APK`，说明双机前置条件已解除，而尚未填写
  的两图在桩 HIL 模板仍按设计失败关闭。
- 已按授权在导航板建立独立工作区 `/home/ztl/duole-issue31-nav-ws`，未修改共享源码工作区
  `/home/ztl/elderbot_ws`，也未注册系统服务或重启导航运行时。隔离工作区已部署严格单请求
  JSON CLI、固定 SSH 边界、ROS 安全快照、主地图与禁行区成对加载、共同桩锚定位、原子提交、
  故障回滚和显式活动地图重启恢复实现；本地与远端部署模块 SHA-256 已逐文件一致。
- Gateway 已正式接入固定 SSH 导航板客户端、持久切图执行器及重启恢复流程。导航板在提交前
  重新检查 BMS 新鲜且充电、底盘静止和所有运动 owner 空闲；隔离板端最新只读快照确认底盘
  静止且无活动 owner，但 `charging_confirmed=false`，因此真实切图继续失败关闭。
- 增量软件回归通过：导航板/Gateway 定向测试 48 项、切图事务测试 9 项、Issue 31 Python
  门禁 312 项；工作区 Python 全量回归为 `2990 passed, 1 skipped, 4 warnings`。本机当前没有
  Dart/Flutter SDK，未宣称重新执行 Dart/Flutter；保留上一次同一 APK 的通过证据。
- 当前仍不能勾选验收：需要第二张真实地图、两图相同且经现场批准为 `verified` 的共同充电桩
  锚点、机器人确认充电的安全窗口、两台手机同时在线并完成扫码/并发验收，以及导航板正式
  建图启动接口。完成在桩切换、重启恢复、注入故障回滚和双机竞争之前，Issue 31 保持
  `ready-for-human`。

### 2026-08-26 两张真实地图候选接入证据

- 用户确认导航板共享目录中的 `my_map2` 与 `my_map3` 来自同一现场并共用同一个实体充电桩。
  两图均有主 YAML/PGM 与 keepout YAML/PGM；`my_map2` 为 `531 x 621`、原点
  `[-17, -7.29, 0]`，`my_map3` 为 `471 x 431`、原点 `[-19.7, -13.9, 0]`，分辨率均为
  `0.05`。格式、YAML 引用、主图/keepout 尺寸和 SHA-256 均已复核，视觉检查确认不是空图。
- 已把 `my_map2` 四个制品从共享源码目录只读复制到授权隔离工作区
  `/home/ztl/duole-issue31-nav-ws/maps`，没有修改共享目录。隔离副本哈希与源文件逐项一致。
- 两图离线特征配准得到约 103 个候选匹配、14 个 RANSAC 内点、尺度 `0.985766`、图像旋转
  `1.422861 rad`；将 `my_map3` 已记录桩位投影到 `my_map2` 得到候选
  `(-0.4844, 1.1795, -0.7272)`。该值仅用于现场标定起点，不作为充电桩物理证明。
- 部署候选清单现包含两图，并使用共同 anchor ID `dock_shared_my_map2_my_map3`；两图状态均
  保持 `candidate`，因此事务实现会在运动抑制和地图加载前拒绝切换。新增部署清单合同测试，
  与导航代理/地图运行时定向测试共 16 项通过。
- 两图清单已原子部署到隔离工作区，远端与本地 SHA-256 均为
  `24e84b5a7ab0a87a8e8ff1b3e651ae39a8d0ca824dc80ddc8019e4a9ad9daa8b`；旧的一图清单保存在
  `config/maps.json.bak-before-map2-20260826`，没有注册服务或重启导航运行时。
- 当前 ROS 2 CLI daemon 返回 `rclpy.ok()` 故障；未重启共享 daemon，而是以无 daemon 模式
  只读取得 BMS 消息。结果为 `power_supply_status=2`、电流约 `-0.7 A`，确认机器人正在放电，
  不是安全在桩窗口，因此没有进行地图加载、锚点验证或任何运动相关操作。
- 隔离代理最初返回通用错误，经 `diagnose` 反馈循环确认 ROS collector 本身正常；第一次手工
  请求遗漏 `observed_at`，第二次使用了板端 Python 3.10 原先不接受的 RFC 3339 `Z` 尾缀。
  已先增加失败测试，再集中规范化末尾 `Z` 为 `+00:00`。板端 agent/CLI/清单及相关切图测试
  50 项通过，隔离运行时与本地 `agent.py` SHA-256 均为
  `16bb80bd9a3b45d07fbb32460895b4625b74693f412c1d33094ba0c7787fea95`；真实 `Z` 请求随后成功
  返回 `charging_confirmed=false`、底盘静止、无活动 owner。一次性探针和调试标记已清理。

### 2026-08-26 导航板正式建图启动接口增量证据

- 已按 TDD 在 Issue 31 隔离分支接入导航板正式建图边界：真实 ROS 预检同时检查回桩、电量、
  活动任务、激光雷达、深度相机、存储和安装版本；Gateway 和导航板都会在启动前重新检查，
  任一条件失败均不会调用 systemd。Gateway 使用同一固定 SSH 主机密钥边界完成预检、建图
  启动和事务性切图，正式 CLI 新增独立建图数据库；提交为 `e8382d1`。
- 新增手动/自主两个按需 systemd unit，二者互斥，并与正式导航栈和独立电池服务互斥；
  `ExecStopPost` 通过非阻塞命令恢复正式导航栈，两个 unit 均无 `[Install]`，不能开机启用。
  sudoers 只允许 `ztl` 执行精确的两个建图 unit 启停和正式导航栈启动命令，无通配符或 shell。
  本地与导航板隔离工作区均通过 `systemd-analyze verify` 和 `visudo -cf`。
- 已把 4 个导航板 Python 模块、2 个 unit 和 1 个 sudoers 文件部署到
  `/home/ztl/duole-issue31-nav-ws`，逐文件 SHA-256 一致；旧 `agent.py`/`cli.py` 备份在
  `backups/mapping-interface-before-20260826-v1/`。正式 `/etc/systemd/system` 和
  `/etc/sudoers.d` 尚未写入，因为导航板 `sudo` 需要操作员交互式密码；没有执行
  `daemon-reload`，也没有启停任何服务。另已提交并部署只安装、不启动的固定安装器
  `/home/ztl/duole-issue31-nav-ws/bin/install-issue31-navigation-board-mapping-services`
  （提交 `e26043f`）；它先验证服务状态、unit 和 sudoers，拒绝覆盖不同的既有文件。
- 新协议的真实只读预检返回电量 `77%`、可用存储约 `61 GiB`、版本匹配、无活动任务，
  同时正确返回 `docked=false`、`sensors_ready=false`。只读诊断确认深度图仍有新鲜数据，
  但 `/scan` 与 `/scan_filtered` 已约两小时没有消息；雷达进程和设备节点仍存在，属于进程
  存活但数据流中断。在机器人未确认充电前未重启导航栈，避免越过安全窗口。
- 增量定向测试 57 项、Issue 31 Python 门禁 335 项、全仓 Python 回归
  `3018 passed, 1 skipped, 4 warnings`；本机仍无 Dart/Flutter SDK，因此保留同一 APK 的既有
  移动端通过证据，没有伪称重跑。当前仍需操作员安装 systemd/sudoers、确认机器人充电、
  恢复新鲜雷达数据并完成两图共同桩锚物理验证、切换/重启/故障回滚和双手机 HIL；所有验收
  勾选继续保持为空。
