# Issue 34 开发交付

本轮完成 App 实现，以及机器人端接口、持久化、安全验证和正式产品导航接入。
Provider 已获授权合入 `/home/ztl/duole-workspace`，共享仓库相关回归通过，真实设备验收待进行。

## 使用流程

“家庭地图 → 点位标注与导航”打开当前地图，也可从资料库每张可加载地图旁的标注按钮进入。
点击大致位置，输入“厨房”等唯一名称，按静态地图校验候选，确认后保存。
房间点位的验证、保存、修改和删除不要求扫码/验证码，也不依赖地图已启用、ROS 定位或实时代价地图。
编辑服务仍需可连接；此处的离线标注指不依赖机器人定位与导航进程，并非平板断网后的本地缓存编辑。

静态检查包含地图/配置版本、边界、障碍物、未知栅格及持久化禁行区；候选为输入附近一米内最近的
空闲栅格中心。页面显示“已保存点位”，不把静态校验结果描述为实际可达。
点击前往时再检查当前地图、可信定位、新鲜代价地图、目标自身可通行及与机器人位置连通。
未启用地图的前往按钮禁用，`localization_pending` 仍拒绝导航；标注不会修改定位可信状态。
普通名称“充电桩”按普通点位保存；独立“回充”入口仍仅使用板端已验证锚点。

禁行区和路线修改沿用既有现场会话与运行时检查。`navigation.execute` 用于前往，`maps.manage`
用于管理配置；既有共享运动资源、导航就绪和 App 运动抑制检查继续执行。

## 文件与集成

- App 修改位于本仓库的 Dart client、生成 contract、地图编辑页面及配对/机器人页面入口。
- Provider 隔离副本：`/tmp/duole-issue34-provider`。
- 本目录的 `provider.patch` 对照接管时的 Provider 工作树生成；现有 WIP 保留，
  21 个任务相关文件已合入，并核对与已验证隔离副本一致；无关 WIP 状态未变。
- `provider-files.json` 列出精确合入对象。
- 本地 APK：`flutter/duole_engineering_app/build/issue34-local/duole-app-issue34-dev-v2017-arm64.apk`。
  versionCode `2017`，versionName `0.1.0-issue34-dev`。
- 本地构建沿用现有离线缓存及 ARM64 `aapt2`。Flutter 的空 CMake NDK 下载引导任务
  按仓库上一版本构建脚本排除；Dart 编译、Android 资源、APK 组装及签名检查实际执行。
  APK 沿用此前地图切换开发构建开关；语义配置独立执行可信定位与现场会话检查。

## 本次验证

- Provider 相关回归 `108 passed`：点位修正、拒绝不可信定位、版本/名称冲突、稳定 ID、
  idempotency、地图隔离、路线引用与排序、禁行区加载失败/存储故障/恢复、回收/永久清理，
  以及保存地图切换、现有资料库和产品 App 会话。
  授权合入后在共享仓库重跑同一相关回归，`108 passed in 16.06s`。
- 修改产品会话接入后的定向回归 `17 passed`，覆盖现有 App 会话和导航就绪接入。
- Flutter 新页面 `10 passed`：坐标旋转、点位验证保存、导航 ID、拒绝与修改候选、
  冲突刷新、原请求重试、后台失效、失效视图、禁行区绘制和路线排序。
- 既有地图页 20 项、机器人页 8 项在本轮回归通过。配对脚本通过。
- Dart 语义 API 可执行回归通过，包含 Python 对 Dart 浮点坐标请求体的实际编码校验。
- OpenAPI audit、contract 重生成一致性、Dart/Flutter analyze 和 scoped diff 检查通过。
- APK 核对包版本、ZIP 完整性、debug 签名、ARM64 Flutter engine 及最终功能源码标识。

软件证据使用合成地图、隔离数据库和替身 ROS。实际地图点位到达、禁行区生效、桩锚点回充、
切图隔离与回收恢复、启动/运动中的停车时间，等待通过正式产品入口完成 HIL/REAL。
移动停车 `<= 1 s` 验收基线沿用。

## 当前停止边界

用户已明确授权保护既有修改合入 Provider 共享工作树；该动作已完成，未暂存或提交。
本轮开发及软件集成完成。部署、真实设备安装及 HIL/REAL 仍沿用各自授权边界，
本轮未改变机器人或 ROS 运行状态。

## 2026-10-15 部署进展

用户随后授权部署并测试。板端 6 个任务文件已安装，CLI 导入检查通过；平板保留数据升级至
v2017 并核验版本。精确回退目录为
`/home/ztl/duole-issue31-nav-ws/runtime/issue34/before-20261014T203909Z`，原 v2016 APK 和部署记录
在 `flutter/duole_engineering_app/build/issue34-local/deployment-20261014T203909Z/`。
现有 Product/Gateway 未重启，新后端尚未加载，REAL 测试未开始；等待操作员明确确认到场准备。

## 现场准备后的当前结果

操作员确认后已通过正式 Product App-only 入口加载新服务。真实 TLS 读接口返回 200，
平板显示当前地图与点位标注页，保留配对与权限说明。当前地图仍为 `localization_pending`，
已有配对缺少 `navigation.execute`，桩锚点未验证；本轮未保存配置或发出运动请求。
这属于真实读图/配置读取 `PARTIAL_PASS`，不代表点位保存、到达、禁行区、回充或停车验收通过。
结果见 `build/issue34-local/deployment-20261014T203909Z/real-result.json`。
Product PID 283702、Gateway PID 284200 保留用于读图，导航 readiness 保持 disabled。

## 服务关闭与后续启动

用户要求结束服务后，已确认 Product 退出，正常关闭 Gateway；8443 无监听、Runtime IPC
已清理，未停止原导航板服务。上述“保留运行”记录是关闭前的状态。

启动入口为仓库的 `script/start-map-semantics.sh`，统一启动正式 Product App Runtime 和 Gateway，
沿用现有配对、证书及数据库，并保持当前导航未放行配置。保持终端开启，按 `Ctrl+C` 收尾。

```bash
./script/start-map-semantics.sh --check
./script/start-map-semantics.sh
```

`--help` 查看路径、地址和端口环境变量。脚本语法与本机配置检查通过；隔离替身验证了
`--check` 无启动副作用、`Ctrl+C` 关闭两进程、Gateway 启动失败时关闭 Product。
本次脚本验证未重新启动真实服务。

收尾后的复查发现另一个新会话（Product PID 300191、Gateway PID 300335）占用同一
IPC 与 8443；这两个进程不属于本轮，未接管或关闭。本轮进程已结束的结论不代表该新会话
已关闭。脚本的配置检查会报告已有 IPC，并拒绝重复启动。

## 2026-10-15 取消房间点位验证码

用户授权后，房间点位验证、保存、修改和删除均跳过扫码/验证码。配对的 `maps.manage` 权限、
受控局域网、安装签名、TTL、幂等、版本冲突和板端可信地图/定位检查保留；禁行区与路线
继续要求现场会话。API 更新为向后兼容的 3.3.0，旧客户端的 presence 字段仍接受。

本次 Provider 相关回归 57 项、Flutter 页面 11 项、Dart API 与 Dart/Flutter analyze、合同审计和
确定性生成检查通过。Flutter 测试首次因本机代理导致 loopback HTTP 连接失败；清除测试进程
代理环境后 11 项通过。v2018 APK 已构建，版本为 `0.1.0-issue34-nocode`，位于
`flutter/duole_engineering_app/build/issue34-nocode-local/duole-app-issue34-nocode-v2018-arm64.apk`。

本次只更新源码和本地 APK，没有替换平板或板端文件、重启真实服务或执行 HIL。生效需要
更新 APK、Provider 与板端 `duole_central/navigation_board/map_semantics.py` 后重新启动服务。
原 `provider.patch` 属于 API 3.2.0 初次交付记录；本节变更以当前仓库源码为准。
当前地图的 `localization_pending` 仍会拒绝点位保存及导航。

## 2026-10-15 无验证码版本部署完成

用户明确授权部署后，平板保留数据升级并核验 v2018 / `0.1.0-issue34-nocode`；板端仅替换
`duole_central/navigation_board/map_semantics.py`，安装内容与已验证源码一致，CLI 导入检查通过。
主控 Provider 已为 API 3.3.0，下次通过 `script/start-map-semantics.sh` 启动时加载。

精确板端回退文件位于
`/home/ztl/duole-issue31-nav-ws/runtime/issue34/nocode-before-20261014T211817Z/map_semantics.py`；
平板原 v2017 APK 和部署记录在
`flutter/duole_engineering_app/build/issue34-nocode-local/deployment-20261014T211817Z/`。
Product/Gateway 保持停止，未启动 HIL 或请求运动；地图定位条件与 REAL 验收缺口继续保留。


## 2026-10-15 静态地图点位编辑

用户明确同意按“先标注地图、机器人使用时再定位”的方案修改。Provider API 3.4.0 已实现
`validate_room` / `room_upsert` / `room_delete` 与 ROS 观察解耦；未启用地图和
`localization_pending` 均可编辑。静态候选检查所选地图的边界、空闲栅格、未知区域和持久化
禁行区，保留 revision、签名、受控 LAN、幂等及运动资源协调。普通“充电桩”名称可保存，
不生成自动回充锚点。编辑不清除定位或禁行区待确认状态。

App 新增资料库逐图标注入口，未启用地图可保存、修改和删除普通点位，前往按钮禁用。
界面明确静态校验与实际导航的区别。前往仍需活动地图、可信且新鲜的定位/代价地图和真实连通性，
新增回归确认目标自身被障碍物占据时拒绝导航，即使相邻栅格空闲。禁行区和路线继续沿用原流程。

本次软件验证：Provider 直接相关 66 项通过；Flutter 页面 11 项与地图页 21 项通过；
Dart API 可执行回归、Dart/Flutter 静态分析、OpenAPI audit、确定性生成和 scoped diff 检查通过。
首轮新增测试分别遇到重复名称及 Flutter Tooltip 查找类型错误，修正测试输入/查找方式后复验通过。
全部验证使用合成地图、隔离数据库和替身，无真实地图写入或运动验收。

本节源码尚未部署。此前平板 v2018 和板端无验证码版本不包含本次静态标注修改；
本轮未重启 Product/Gateway、ROS 或改变真实设备运行状态。


## 2026-10-15 静态点位标注版本已部署

用户明确要求直接部署后，已构建、验证并保留数据安装 v2019 / `0.1.0-issue34-static`。
APK 位于 `flutter/duole_engineering_app/build/issue34-static-local/duole-app-issue34-static-v2019-arm64.apk`。
板端只更新点位模块并通过导入检查。正常关闭原点位会话，经 `script/start-map-semantics.sh`
启动新会话，launcher PID 455355，真实 TLS 版本接口确认 API 3.4.0，地图/语义配置读取返回 200。
App 已重新打开。日志目录为 `session-20260929/map-semantics-runs/20261014T214235Z-BsJQvO`。

当前地图仍为 `localization_pending`，本次没有更改定位状态、导航 readiness 或发出运动。
未进行真实点位保存、到达或回充验收。部署记录和原 v2018 APK 位于
`build/issue34-static-local/deployment-20261014T214009Z/`；板端精确回退为
`/home/ztl/duole-issue31-nav-ws/runtime/issue34/static-before-20261014T214009Z/map_semantics.py`。
本节覆盖上一节的“尚未部署”状态，历史交付记录继续保留。


## 2026-10-15 家庭地图点位显示已修复并部署

根因是家庭地图未读取/绘制已持久化的语义点位。现已在主页面加载与编辑返回刷新时读取配置，
为普通地图和定位待验证地图绘制点位、名称与禁行区，校验地图版本，异常时清除旧叠加并提示刷新。
新增 6 个回归覆盖真实页面调用链和版本/读取失败；与既有页面用例合计 38 项在相关运行中通过，
最终保存返回场景修正测试帧等待和滚动位置后单独通过。静态分析与 scoped diff 检查通过。

平板已保留数据更新为 v2020 / `0.1.0-issue34-overlay`，在家庭地图实际确认已有 3 个点位的
标记与名称可见，无同步失败提示。仅升级 App；后端、定位状态及服务保持原状，没有写点位或运动。
APK 为 `build/issue34-overlay-local/duole-app-issue34-overlay-v2020-arm64.apk`；
回退 APK 为 `build/issue34-static-local/duole-app-issue34-static-v2019-arm64.apk`。
部署结果：`/home/ztl/duole-app/flutter/duole_engineering_app/build/issue34-overlay-local/deployment-20261014T220105Z/deployment-result.json`。
