# 实现地图级房间、禁行区与巡逻路线配置

Status: ready-for-human

Implementation: static-map editing and home-map annotation display deployed (App v2020 / Provider 3.4.0); existing 3 point markers/names confirmed on tablet; controlled point-write and motion acceptance pending

Software validation: passed-2026-10-15

REAL acceptance: PARTIAL_PASS — real map display and semantic configuration read passed; point save, arrival, keepouts, return-to-dock and moving stop latency not exercised

Type: HITL

User stories covered: 184–185, 196–199

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

让现场用户把已保存地图转成可供后续房间导航和巡逻使用的产品地图。Android 提交房间
大致中心、禁行区几何和由已验证房间组成的路线；普通点位按指定静态地图修正、校验、
版本化并持久化，无需机器人定位或启用该地图。前往时再执行真实定位与可达性检查。App 不直接写 YAML、墙体、任意导航目标或底层参数。

## Acceptance criteria

勾选项对应本次软件验证，Provider 已合入共享工作树并通过相关回归；最后一项真实设备验收待进行。

- [x] 房间、禁行区、巡逻路线和充电桩锚点全部绑定稳定 `map_id` 和 map revision；切图不会复制或混用另一地图的坐标数据。
- [x] 现场用户输入唯一房间显示名称并点选大致中心；按静态地图将其修正到空闲区域，生成稳定 room ID 和静态校验结果，不要求用户手画房间多边形。
- [x] 静态地图附近无空闲区域、地图/配置 revision 已变化时拒绝保存；未定位或未启用地图可标注。前往时另行检查活动地图、新鲜定位、实时代价和可达性。
- [x] 巡逻路线只能由当前地图的已验证房间组成，支持排序和稳定 route ID；首版不开放任意坐标巡逻点。
- [x] 用户可圈定地图级禁行区；导航板校验几何、边界和 revision 后生成版本化 keepout，不开放墙体绘制、充电锚点编辑、地图上传或导航参数修改；普通“充电桩”点位名称不等同于自动对接锚点。
- [x] 房间点位验证与新增/修改/删除要求已配对、`maps.manage` 和受控现场局域网，不要求扫码/验证码（2026-10-15 用户调整）；路线和禁行区修改保留有效现场地图管理会话。重命名地图、删除非当前地图和回收站恢复沿用原授权。
- [x] 配置写入采用 optimistic revision、request ID、TTL 和 idempotency；并发修改返回当前 revision，不静默覆盖。
- [x] 删除地图时关联语义配置一起进入回收站并可恢复；永久删除后清除配置，审计只保留必要元数据而不保留家庭平面图。
- [x] Android 在地图上区分大致输入、静态地图候选、已保存和拒绝状态；低分地图仍允许配置，但展示质量提示。
- [ ] 使用真实手动生成地图完成房间目标到达可行性、禁行区生效、路线引用、revision 冲突、切图隔离和回收恢复 HIL/REAL 验收。

## Blocked by

- [33 贯通 REAL 手动建图、TeleopGuard 与充电桩闭环](33-real-manual-mapping-teleop-guard.md)

## Comments

### 2026-10-15 点位标注开发与软件验证

- App 已接入“家庭地图 → 点位标注与导航”：大致点选、唯一名称、现场扫码、安全候选、
  保存/修改/删除、按稳定 ID 前往，以及禁行区绘制和巡逻路线排序。充电桩读取板端验证锚点。
- Provider 在 `/tmp/duole-issue34-provider` 交付 SQLite 配置与版本化接口、ROS 地图/定位/代价
  地图验证、蒙版应用与恢复、共享运动资源占用及现有产品导航/紧急停止接入。开发切图仍需
  可信定位，未把 `localization_pending` 变成可验证房间。
- 软件回归覆盖 idempotency、冲突、切图隔离、回收/恢复/永久清理、候选拒绝、网络不确定性、
  阻止带任意坐标的公开导航请求、以及 Dart/Python 浮点 JSON 签名编码一致性。
- Provider 相关 108 项通过；产品会话接入定向 17 项通过；新 Flutter 页面 10 项通过；
  既有地图/机器人页面及配对、Dart API 回归通过；Dart/Flutter analyze、合同和重生成检查通过。
- 本地 v2017 APK 已构建，最终交付与检查记录见 [开发交付](../issue34-development/README.md)。
- 后端 [任务补丁](../issue34-development/provider.patch) 的应用预检查通过。因 Provider
  `AGENTS.md:88` 明确要求触碰共享 WIP 时停止，后端尚待授权保护既有修改合入。
- 真实点位到达、禁行区生效、路线引用、切图/回收恢复、桩锚点回充及移动停车一秒基线，
  需在部署和操作员现场准备后通过正式产品链路验收；当前软件结果属于合成输入与替身验证。

### 2026-10-15 授权合入 Provider

- 用户批准后将 21 个任务文件合入 `/home/ztl/duole-workspace`；与已验证隔离副本一致，
  无关 WIP 状态未变，未暂存或提交。
- 在共享仓库重跑点位、禁行区、语义导航、地图资料库/切换和产品 App 会话相关回归，
  `108 passed in 16.06s`。先前 Dart/Flutter、合同、APK 验证继续适用于未变更的 App 源码。
- 开发与软件集成完成，工单保留 `ready-for-human`，等待真实地图 HIL/REAL；未部署、
  安装到真实设备、启动 ROS 或指令机器人运动。

### 2026-10-15 授权部署，等待现场准备

- 用户明确同意部署并测试。基于板端当前文件应用 6 个语义配置相关文件，保留现有热修，
  安装内容与软件验证源一致；板端 CLI 导入及参数解析通过，没有启动新的 ROS 节点。
- 平板 `172.22.205.14:35581` 保留应用数据升级至 v2017 / `0.1.0-issue34-dev`，安装成功并核验版本。
- 精确板端回退目录为 `/home/ztl/duole-issue31-nav-ws/runtime/issue34/before-20261014T203909Z`；
  平板原 v2016 APK 和部署结果保存在 App `build/issue34-local/deployment-20261014T203909Z/`。
- 现有 Product/Gateway 尚未重启加载新源码，REAL 测试未开始。按 Provider `AGENTS.md` 的
  真人到场确认要求，停在重启及测试前，等待操作员明确回复“已准备好”。地图定位与导航
  就绪条件仍须实测，不绕过不可信定位或停车一秒基线。

### 2026-10-15 现场准备后加载与真实读图验证

- 操作员确认“已准备好”。实际预检：电量 57%、未充电、静止、无运动占用；传感器、
  碰撞保护与停止链就绪。通过正式 Product App-only 入口重启加载新 Provider，API 版本 3.2.0。
- 真实 TLS 版本、地图资料库、语义配置接口均返回 200；当前地图 source revision 1、
  语义 revision 1，点位/禁行区/路线均为空。平板保留配对恢复并进入标注页，实际地图渲染通过。
- 当前地图目录仍为 `localization_pending`，桩锚点未验证。已有切换实现写入该状态，
  尚无正式定位成功后清除它的产品闭环；点位验证和保存按既有约束拒绝该状态。
- 当前配对仅有 `maps.manage`、`robot.status.read`、`robot.stop`，App 如实显示没有导航权限，
  未验证桩的回充按钮禁用。没有直接更改权限数据库或地图可信状态。
- 本轮未保存语义配置、未发运动请求，点位到达、禁行区、回充及移动停车验收均未执行。
  Product PID 283702、Gateway PID 284200 保留运行用于读图，导航 readiness 为 disabled。
- 结果保存在 `build/issue34-local/deployment-20261014T203909Z/real-result.json`，
  临时地图截图已删除。下一步需先补齐 Issue 30 切图后的真实定位闭环，并通过正常配对
  授予导航权限，才能继续当前地图上的点位正向验证与运动验收。

### 2026-10-15 按用户要求关闭服务，提供 sh 启动入口

- Product 已退出；本轮 Gateway 正常关闭，8443 无监听、Runtime IPC 已清理。
- 新增 `script/start-map-semantics.sh`，沿用当前配对与数据库，一次启动 Product/Gateway，
  `Ctrl+C` 关闭，任一服务退出时收尾。`--check` 仅检查配置，`--help` 查看可配置路径与地址。
- 保留当前导航未放行状态；未继续定位开发或真实运动测试。语法、本机配置和隔离替身
  进程收尾验证通过，真实服务保持关闭。
- 收尾后出现另一个新会话（Product PID 300191、Gateway PID 300335）占用原 IPC 与 8443；
  不是本轮启动的进程，未接管或关闭。启动脚本已验证会拒绝该占用，避免重复启动。

### 2026-10-15 按用户决定取消房间点位验证码

- 点位验证、保存、修改、删除不再要求扫码/验证码；前端不会请求现场挑战或打开扫码器，
  后端允许这些命令省略 `presence_token`。禁行区、路线沿用现场授权。
- 保留配对权限、受控 LAN、安装绑定签名、TTL、幂等、revision、运动资源与可信定位检查；
  API 3.3.0，Dart contract 已重新生成。旧客户端携带的 presence 字段继续兼容。
- 本次 Provider 相关回归 57 项、Flutter 页面 11 项通过，Dart API、静态检查、合同审计和
  确定性生成通过。v2018 / `0.1.0-issue34-nocode` APK 已完成本地构建。
- 源码与本地 APK 更新完成，尚未安装到平板、替换板端文件或重启真实服务；不追加真实
  点位到达等验收结论。部署后当前地图仍须通过真实定位检查。

### 2026-10-15 无验证码版本已部署，服务保持停止

- 用户授权后平板保留配对数据升级到 v2018 / `0.1.0-issue34-nocode` 并核验；板端只更新
  `navigation_board/map_semantics.py`，安装源码及回退原文件核对通过，板端 CLI 导入通过。
- 主控 Provider API 3.3.0 已在当前源码中，下次运行 `script/start-map-semantics.sh` 加载。
  启动脚本配置检查通过；本轮未启动 Product/Gateway、ROS 节点或发送运动指令。
- 精确板端回退为 `runtime/issue34/nocode-before-20261014T211817Z/map_semantics.py`；
  原 v2017 APK 和部署结果在 `build/issue34-nocode-local/deployment-20261014T211817Z/`。
- 取消验证码的部署完成；定位待验证状态与真实到点、禁行区、回充和停车验收缺口未改变。


### 2026-10-15 按用户方案解耦点位标注与机器人定位

- 点位验证/保存/修改/删除只依赖所选已保存地图；未启用地图和定位待验证状态允许标注，
  不访问 ROS 定位、实时代价地图或重新定位。静态障碍物、未知区域、禁行区、版本和名称检查保留。
- 资料库逐张地图提供标注入口；界面显示已保存点位及静态校验说明，未启用地图禁用前往。
  普通“充电桩”点位与独立自动回充锚点分开处理。
- 发起导航仍检查活动地图、定位可信与新鲜度、地图版本、目标自身代价和真实可达性；
  不清除 `localization_pending` 或禁行区 pending，不伪造就绪。禁行区/路线行为沿用既有规则。
- Provider API 3.4.0，直接相关 66 项回归通过；Flutter 点位 11 项及地图页 21 项通过；
  Dart API、静态分析、合同审计和确定性生成通过。新增失败均为测试输入/控件查找问题，已修正复验。
- 当前仅源码与本地构建；设备仍为已部署 v2018 / 无验证码板端代码。新版本未部署，未启动 HIL。


### 2026-10-15 用户要求直接部署静态点位标注版本

- v2019 / `0.1.0-issue34-static` APK 构建成功，包版本、签名、ZIP 与最终界面源码标识通过；
  保留应用数据安装并核验，已重新打开 App。
- 板端仅替换 `navigation_board/map_semantics.py`，替换前与上次已部署内容一致，原文件同目录备份，
  原子安装及 CLI 导入检查通过。只正常停止原点位服务会话，未停止其他产品/ROS 服务。
- 通过 `script/start-map-semantics.sh` 重启，TLS `/versions` 返回 API 3.4.0；地图资料库和当前
  地图语义配置均返回 200。当前地图仍为 `localization_pending`，readiness 为 disabled。
- 本次没有写真实点位、加载禁行区、重定位或发运动指令。真实点位保存与导航验收仍未执行。
- 部署记录：`build/issue34-static-local/deployment-20261014T214009Z/deployment-result.json`；
  精确板端回退：`runtime/issue34/static-before-20261014T214009Z/map_semantics.py`，
  平板回退为同部署目录的 `tablet-before-v2018.apk`。


### 2026-10-15 修复家庭地图未同步显示点位

- 只读诊断确认板端已保存 3 个点位，配置 revision 4；家庭地图只刷新底图和资料库，未读取或绘制语义点位。
- 家庭地图加载时读取对应地图语义配置；退出编辑页后刷新。普通地图和定位待验证的已保存地图
  共用点位绘制逻辑，显示标记与名称，并提供点位无障碍标签。校验地图 ID/source revision，
  读取失败或版本不匹配时移除旧叠加并提示刷新。
- 新增显示、保存返回、错误版本和读取失败回归；相关 38 个用例在定向/组合运行中通过，
  Flutter analyze 与 scoped diff 检查通过。保存返回测试修正了帧等待及滚动位置后单独通过。
- 已沿用部署授权，保留数据升级至 v2020 / `0.1.0-issue34-overlay`。APK 包版本、签名、ZIP
  和最新源码标识通过。仅更新 App，Provider API 3.4.0 和现有服务未重启。
- 已在真实平板进入家庭地图，确认原 3 个点位的标记与名称可见，没有同步失败提示；
  map revision 1、semantic revision 4，数据未更改。本次未写真实点位或发运动指令。
- 部署与显示记录：`flutter/duole_engineering_app/build/issue34-overlay-local/deployment-20261014T220105Z/deployment-result.json`；回退 APK 为 `build/issue34-static-local/duole-app-issue34-static-v2019-arm64.apk`。
