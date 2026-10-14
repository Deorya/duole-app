# 实现多地图资料库、评分、回收站与容量管理

Status: ready-for-human

Implementation: complete-2026-08-25

Acceptance: accepted-2026-08-25

REAL integration: verified-2026-10-15 — v2016 已安装；真实保存、资料库登记、评分/容量展示、图形预览及保存地图开发切换已贯通。平板当前显示已启用的“地图 1”；普通结束保存路径尚未实测。

Map switch integration: real-verified-2026-10-15 — 正式 Product/Gateway 与平板入口完成 my_map3 → “地图 1”；Nav2 当前地图与保存文件逐格一致，目录和 selector 已提交，App 重开及点击大图通过。当前定位待验证、导航不可用；在桩等条件与完整稳定性验收后补。

Type: AFK

User stories covered: 177–180, 183–184

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

贯通机器人本机地图资料库到 Android 地图管理页的第一个纵向切片。导航板以稳定
`map_id` 管理同一家庭、同一楼层、同一充电桩下的多张地图；网关只暴露版本化目录、质量、
容量和回收站操作，不暴露文件路径或原始 SLAM 文件。用户可以理解每张地图是否当前启用、
质量如何、占用多少空间，并安全地重命名、删除和恢复非当前地图。

## Acceptance criteria

- [x] 地图记录包含稳定 `map_id`、唯一显示名称、revision、创建/更新时间、状态、占用空间、充电桩锚点摘要和关联配置摘要；重命名不改变 `map_id`。
- [x] 默认名称按“地图 1、地图 2……”自动选择下一个可用编号；同一机器人拒绝重名和 revision 冲突。
- [x] 导航板返回 `0–100` 总分及覆盖完整度、地图一致性、可定位性、导航可通行性分项，并给出稳定评分原因。
- [x] 低分但可加载的地图仍可保留和后续启用；只有文件损坏、元数据非法或无法加载等技术故障标为 `unusable`。
- [x] 当前活动地图不能直接删除；有其他地图时必须先完成切换，最后一张地图经强确认后可删除并让机器人进入“未建图、导航不可用”。
- [x] 删除进入本机回收站，并连同房间、禁行区、路线和锚点关联一起恢复；保留期支持立即、1 天、7 天、30 天和无限期，默认 7 天。
- [x] 无限期条目不被磁盘压力静默清理；容量不足时显示各地图/回收站占用并拒绝新的建图任务，由用户清理或修改期限。
- [x] 地图数量不设固定上限；容量服务在开始建图前能预留临时快照、最终地图和原子提交所需空间。
- [x] 地图文件、实时图和缩略图只保存在机器人本机，不进入普通日志/诊断包；API 拒绝导入、导出、路径穿越和任意本地文件名。
- [x] Android 地图管理页展示活动、可用、低分、不可用和回收站状态，并支持重命名、删除、恢复、永久删除及容量说明。
- [x] 文件提交、回收、恢复、到期清理和进程崩溃均保持原子性；contract、adapter、存储故障、权限和 Android UI 测试通过。

## Blocked by

- [13 实现地图、机器人位姿、房间与巡逻路线只读视图](13-map-pose-rooms-routes-readonly.md)

## Comments

### 2026-10-15 v2016 部署与“地图 1”真实切换验收通过

- 用户回复“已准备好”后，保留正式 Product App-only 会话，部署板端 4 个切换相关已有文件及 1 个新模块、保留实际 ROS 定位补丁，启用显式开发模式；平板保留原配对升级至 v2016 / 0.1.0-phaseA13。部署文件的本次相关回归 39 项通过。
- 通过平板“家庭地图 → 多地图资料库 → 切换到此地图”发起唯一一次真实请求，安装签名、maps.manage 和受控局域网校验沿用。操作 map_switch_0d5f026c597241208707e887af363f5d 从 loading 到 committed，原选择 my_map3 / map_revision 2，目标 manual_mapping_83a49a89e34240b48c2fd4d8fab62d5b / “地图 1”。
- 真实资料库当前 active=1、CAS revision 2、source revision 1、technical_reason=localization_pending；active-map.json 与同 operation 的板端提交回执一致。Nav2 /map 发布 248×106、0.05m 分辨率，坐标及所有栅格与板端保存 PGM/YAML 转换结果一致；/keepout_filter_mask 同几何且全部为空白可通行蒙版。原地图文件保持可回滚。
- 真实 TLS Gateway 目录与图像读取均返回 200；当前图像 248×106 / 1262 bytes，ETag 与切换前同一 source revision 的保存预览一致，未将原始栅格或图像保存到普通证据包。
- App 实际显示“当前地图：地图 1”、保存图、“当前启用”“未回桩验证 · 已启用”和 78 分。退出并重开地图页仍正确；点击当前地图进入大图预览，状态、分项评分与保存时间一致。平板最终停留在当前地图页。
- 本轮仅验收真实加载、选择提交与展示，不执行导航或行驶指令。当前 navigation_available=false / map_localization_pending；在桩、共同桩锚、现场扫码、真实定位、导航恢复及完整重启/稳定性 HIL 继续按下条记录后补。
- 保留 Product PID 3327146、开发切换 Gateway PID 3768250，原端口 172.22.205.44:8443 与 IPC 不变；实际当前地图为“地图 1”。精确地图回滚目标 my_map3 / map_revision 2 / artifact_revision 1；板端源码、目录数据库及 selector 回滚保存于 runtime/issue33/map-switch-before-20261014T181427Z/，本地原 v2015 安装包为 activation-20261014T181427Z/tablet-before-v2015.apk。
- 本轮证据在 build/issue30-map-switch-local-20261015/activation-20261014T181427Z/：real-switch-result.json、switch-operation-observations.json、board-current-map-verification.json、gateway-current-map-verification.json、tablet-switch-committed-redacted.xml、tablet-active-map-preview-redacted.xml。本轮开发切换与展示 PASS，不把延后的完整验收称为完成。
- 用户后续要求“结束吧”：Gateway PID3768250、Product PID3327146 已按顺序正常退出，IPC socket 已清理、8443 无监听；“地图 1”目录及 selector 保留，导航板服务仍 active，建图 Runtime/Guard inactive。收尾结果为同目录 shutdown-result.json。手动建图脚本的 socket 占用已解除，脚本缺少 map-switch-development 参数的问题尚未修改。

### 2026-10-15 优先完成保存地图切换，其他条件暂缓

- 用户指定切换目标为刚保存的“地图 1”，并要求“先做切换功能，其他限制不予处理，记录下来，后期补上”。本轮范围为保存地图加载、当前地图提交、切换进度和当前地图图像展示。
- 板端直接从同一资料库读取已提交 YAML/PGM；图像及运行文件使用 source revision，目录操作使用 CAS revision。没有配置禁行区的保存地图生成同尺寸、同坐标的空 mask；已配置禁行区的地图须保留原 mask。
- 切换使用已有私有板端入口和签名 API，成功才提交目录 active 状态及 active-map.json。加载失败恢复原选择；丢回包和提交后 selector 写入失败可按同一 operation 重试，不重复递增 revision、不假报切换失败。重复保存登记和重命名不会抹掉当前选择或改变地图文件身份。
- App 通过“切换到此地图”进入进度页，查询至提交成功后刷新“当前地图：地图 1”、真实保存图和“未回桩验证 · 已启用”。定位状态明确显示“地图已加载 · 定位待验证”；不绘制旧地图位姿，不展示旧房间及路线。预览临时失败仍保留当前地图名称，可再次点击查看。
- 该路径只在显式开发模式启用：App 构建参数 DUOLE_MAP_SWITCH_DEVELOPMENT=true；Gateway --map-switch-development 使用独立操作数据库；板端须启用 state/map-switch-development.enabled。正式默认切换条件保留，现有配对签名、maps.manage 及受控局域网边界沿用。
- **后续补齐，当前不作为开发切换的前置条件**：BMS 充电/静止/任务占用检查、在桩与共同充电桩锚点验证、现场扫码 presence、切换后真实定位及导航恢复、导航读模型的位姿/房间/路线绑定、并发操作现场验收、完整切换及重启稳定性 HIL。
- 切换过程中及结束后保持运动抑制，目录 navigation_available=false / map_localization_pending。未把加载成功标成可导航，未修改移动停车 <=1s 红线或保护参数。
- 本次软件验证覆盖保存文件→typed SSH→开发切换→目录/selector 提交、失败恢复、断线重试、提交后补写、重命名和重复登记；Flutter 验证等待提交、当前图展示及图像不可用时的当前选择展示。使用隔离文件和替身 ROS，不能代替真实设备验收。
- 本次相关 Provider 回归 123 项通过，之后补充的两张保存地图往返切换通过（切换专属 11 项）；Flutter 页面 20 项通过，Flutter analyze 无问题，Provider 合同检查通过，两个仓库 diff --check 通过。v2016 / 0.1.0-phaseA13 本地 ARM64 APK 已构建并核验版本及最终界面代码，位于 build/issue30-map-switch-local-20261015/issue30-map-switch-v2016.apk（96539005 bytes）；验证摘要为同目录 software-result.json。
- 打包核对曾发现本次增量缓存未含最后界面修改；仅隔离本次生成的 kernel/stamp 并强制重新编译，最终包内代码已与页面测试版本一致。中间包均未部署，原 v2015 制品和现场服务保留。
- 本轮没有安装 v2016、启用板端 marker、替换运行 Gateway 或实际切换导航地图。此前 v2015 的保存/图像真机证据仅适用于前述已验收功能。后续真机目标为 manual_mapping_83a49a89e34240b48c2fd4d8fab62d5b / “地图 1”；需现场配合后执行。
- 板端只读核对：当前 selector 为 my_map3 / map_revision 2 / artifact_revision 1；“地图 1”目录 revision 1 / source_revision 1、loadable、unverified、未启用；开发 marker 未启用。后续真实切换的明确地图回滚目标是上述 my_map3，部署前仍须保留当时源码和 v2015 安装包。

### 2026-10-15 保存地图点击预览补齐，v2015真机验证

- 用户反馈“无法点击预览”。此前只完成资料库摘要，条目没有点击事件且保存地图没有图像
  数据源。现增加“点击预览地图”和详情页，显示保存地图、评分/状态/时间，支持双指缩放及拖动。
- 复用既有认证地图图像接口。板端从SQLite中提交的PGM生成有界PNG，原文件保持不变；
  目录新增可选source_revision，重命名只改变目录revision，仍读取同一图像。回收站地图不可预览。
- v2014真机暴露配对HTTP通道把PNG当UTF-8读取；修复为保留字节，仅既有PNG图像资源
  放行至2MiB，普通JSON响应保留64KiB上限、证书指纹绑定与原超时规则。最终安装v2015/phaseA12。
- 64项目录/保存/图像回归通过，新增无效回包3项也通过；预览专属14项、Flutter页面18项通过，
  实际设备密钥绑定TLS通道的PNG、较大图像、JSON大小限位回归通过，Dart/Flutter analyze无问题，
  Provider合同检查通过。SSH额外32项通过，3项已有日志捕获失败在修改前模块同样复现，未改其共享WIP。
- 真实板端与Gateway图像读取200、248×106、1262bytes，平板点击“地图1”后已实际显示
  已保存的黑白灰平面图；图片与78分、未回桩验证/未启用、保存时间在同页。曾出现一次读取503，
  点击重试后恢复，不宣称重复读取稳定性已验收。未启动新建图或运动，本轮无新增保存尝试。
- 保留当前Product/Gateway读图服务供查看；导航active，建图/Runtime inactive。
  进程与证据：`session-20260929/issue30-33-preview-check-20261014T163859Z/`的
  `processes.json`、`gateway-preview-verification.json`、`preview-ui-v2015-redacted.xml`、`preview-result.json`。
  本地APK：`build/issue30-33-preview-local-20261015/issue30-33-map-preview-v2015.apk`；
  板端回滚：`runtime/issue33/map-preview-before-20261014T163710Z/`，原v2013安装包保留。

### 2026-08-25 implementation and acceptance

- 已交付机器人本机 SQLite 多地图资料库、独立 source/catalog revision、质量与技术故障语义、
  完整配置回收/恢复、期限清理、容量明细及建图空间预留；地图数量只受容量限制。
- 已冻结读取、重命名、回收、恢复、改期和永久删除合同；写操作要求安装实例签名与
  `maps.manage`，公共 DTO、日志和诊断面不包含地图 BLOB、缩略图或本地路径。
- Android 页面已覆盖活动、可用、低分、不可用、回收站、容量说明及全部管理动作；最后一张
  地图和永久删除使用 map/revision 绑定强确认。
- 原子性覆盖提交、回收、恢复、批量到期清理、容量预留消费、故障回滚与进程重启；导航板
  同版本重放不会覆盖用户名称或复活回收站条目。
- 最终自动化结果：Python 全仓 `2900 passed, 2 skipped`；Dart contract/provider/consumer 全通过，
  两个 Dart 包 analyze 零问题；Flutter analyze 零问题、全套 `42 passed`。
  冻结边界见 `docs/interface_freeze/app_v1/issue_30_multi_map_catalog_quality_trash.md`。

Issue 30 的 AFK 验收条件已全部关闭。

### 2026-10-14 issue 30 / 33 真实保存联动的软件交付

- 定位到 REAL 保存仅完成文件落盘，Gateway CLI 的资料库没有板端数据源。现已由板端
  `BoardManualMappingMapStore` 将真实 YAML/PGM 与元数据提交到同一板端 SQLite 资料库；
  目录使用会话绑定的稳定 `map_id`，名称沿用“地图 N”，保留真实评分，标为未回桩验证且不自动启用。
- REAL Gateway 改为读取板端目录摘要，管理命令沿用既有签名、权限、revision 和强确认入口。
  地图文件和目录 BLOB 留在板端，公共 API 不传文件路径或原始地图。
- App 保存成功后提供“返回地图资料库”，返回时重新读取目录，并显示“未回桩验证 · 未启用”。
- 本次 Provider 相关回归 `192 passed`，两个 Flutter 页面 `54 passed`，Flutter analyze 零问题。
  本地 ARM64 APK v2013 / `0.1.0-phaseA10` 已构建并核实包内版本、新增界面。
  覆盖真实文件入库、板端 SLAM→typed SSH→REAL 会话→Gateway 目录读取、重复回包、重启读取、
  重命名/回收/恢复、存储故障及文件访问拒绝。软件验证使用隔离测试文件和替身，不等于真机验收。
- Provider 的任务补丁已应用且与隔离验证副本一致；共享既有修改保留，未提交、未部署板端、
  未安装 APK、未运行新的 HIL。真实验收还需操作员正常结束保存，并在 App 资料库看到同一地图。

### 2026-10-15 issue 30 / 33 部署与真实保存、登记、展示验收

- 用户授权“部署并测试”并确认“已准备好”。按板端实际源码派生最小补丁，相关67项测试
  通过后部署4个已有文件和3个新资料库文件；平板保留配对数据升级并核验v2013/phaseA10。
- 正式Product App-only入口完成`manual_mapping_83a49a89e34240b48c2fd4d8fab62d5b`。
  真人操控，109条板端意图全部applied，接收跨度10.812秒，监控在首输入前就绪，
  本轮松手停车确认725ms，无监控中止。终态为`immediate_stop_saved`。
- 真实YAML/PGM/metadata与SQLite文件包逐字节一致；map_id等于session_id、revision1，
  名称“地图1”、总分78、分项19/100/100/93、27108bytes。临时快照已清理，
  原活动选择恢复，新地图未回桩验证且未启用。
- 新进程板端目录读取成功，真实TLS Gateway目录API返回200；App资料库显示同一名称、
  评分、27.1KB及“未回桩验证 · 未启用”。用户确认“保存成功，我已经点进地图信息页面”。
  本次保存、登记、资料库摘要展示联动PASS；没有新增保存地图大图预览。
- 本轮实际走立即停止保存，普通“结束并保存未验证地图”尚未实测；issue33的重复稳定性、
  碰撞恢复与完整安全矩阵仍未通过。未修改selector或既有开发配置、保护参数。
- Product/Gateway/monitor停止，8443/Runtime IPC/Guard socket关闭；导航active，
  建图/Runtime/Guard inactive，底盘静止、无占用，收尾电量70%。保留部署与地图。
- 板端精确回滚：`runtime/issue33/map-catalog-before-20261014T154528Z/`；原v2012 APK：
  本地`build/issue30-33-local-20261014/deployment/tablet-before-v2012.apk`。
  原始证据：`build/issue33-phaseA-local-20260927/session-20260929/issue30-33-linkage-hil-20261014T1549Z/`。
