# Issue 33 current-baseline REAL acceptance

本目录是安装 SLAM snapshot control path repair 后的新验收包。旧包保留为历史证据，不修改其
Runtime/SLAM 版本绑定，也不把旧 `pointer_up` 停车结果重绑到当前代码。

三项 HIL 安全检查仅在其行为所有者 `manual_mapping_guard.py`、
`ros_manual_mapping_runtime.py`、`duole-mapping-manual.service` 和固定安全 profile 逐字节未变的前提下
带来源哈希迁移。`mock_no_motion_regression` 与 `ordinary_teleop_remains_unavailable` 已在当前代码重新
运行。所有 stop 场景均从 pending 开始。

应用层双零诊断已在当前部署基线通过，但它没有非零运动，不计作 11 个 stop 场景；其结果仍保存在
旧目录的 `source-diagnostics/persistent-session-application-control-no-motion-03.json` 与分析文件中。

当前包状态为 `PRELIMINARY_REAL`：stop `2/11`、check `7/12`，即验收表 `9/23`
（约 `39%`）；还有 9 个 stop 和 5 个 check，共 14 项未完成。当前没有 capability
marker，不得 finalize 或开放 REAL 能力。

当前基线 `app_background` 已通过：机器遥测停车延迟 `921 ms`，未验证保存成功，
原活动地图已恢复且未激活新地图。现场操作员 `ztl-onsite` 观察到约 `8 cm`
前进，后台事件后自动平稳停车，无可见延迟、后退或继续滑行，无障碍物接触，充电线安全，
急停可及且屏幕仍显示正在充电。

当前基线 `pointer_up` 板端 HIL 已通过：机器遥测停车延迟 `992 ms`，现场操作员
`ztl-onsite` 观察到约 `8 cm` 前进后自动平稳停车，无可见延迟、后退或继续滑行，
无障碍物接触，充电线安全、急停可及且屏幕仍显示正在充电。该场景的触发源是
`navigation_board_guard_ipc_hil_probe`，不是 Flutter App；它只计作板端真实停车证据，
不声称 App 摇杆用户体验或 App 端到端链路已通过。

## App 端到端缺口

原始 Issue 33 要求用户使用 App 摇杆驶离、覆盖和回桩。当前 Flutter 源码已包含摇杆、WSS
控制、`pointer_up` 与 App lifecycle 映射，但本轮真车结果都由 SSH/HIL 探针触发；操作员尚未
使用 App。现已完成本地 App REAL 候选准备：REAL 页面明确提示摇杆会驱动实体机器人，REAL
触摸特征测试确认 `acquire → intent → pointer_up release`，静态检查无问题且完整 Flutter 测试
`65/65` 通过。当前 debug 候选 APK SHA-256 为
`c7a17a49e3e69e8b03cb6d06fab4ba767eac0d767f0a2687ff2e423acf402bae`；源码、工具链、包信息、
签名和授权边界见 `source-runs/app-real-candidate-manifest.json`。

本阶段没有安装 APK、没有切换服务、没有连接 App 到真实 Gateway，也没有执行机器人运动；所以
`real_depart_cover_manual_dock` 和 `normal_dock_verified_save` 仍为 pending，正式包仍为
`PRELIMINARY_REAL`，进度保持 `9/23`（约 `39%`）。下一步必须取得“安装此精确 SHA 候选”的
单独授权；安装与无运动配对/状态检查通过后，再取得现场 App REAL 低速运动授权。

构建过程中 Flutter 虽接受独立 `build-dir` 配置，Android Gradle 仍写入被忽略的默认
`build/app/.../app-debug.apk`，替换了该路径下 Issue 32 的本地历史二进制。Issue 32 源码与历史
文档未修改，原 SHA `d4e1d472…7600` 的记录仍保留；干净 `HEAD` 重建未复现该二进制 SHA，故没有
以不等价文件冒充恢复。Issue 33 候选已复制到独立命名路径并由清单绑定。

## App REAL 安装检查点

候选已通过无线 ADB 安装到 OnePlus `PHK110`（Android 16），安装后从设备拉回的
`base.apk` 与候选逐字节一致，SHA-256 均为
`c7a17a49e3e69e8b03cb6d06fab4ba767eac0d767f0a2687ff2e423acf402bae`。签名一致，使用
`adb install -r` 保留了既有 App 数据；首次安装时间未变化。

App 无运动启动后停在“连接机器人”，mDNS 返回“未发现候选机器人”。历史正式目标
`172.22.205.44:8443` 当前没有监听；正式产品 Runtime/ROS 投影和 TLS Gateway 均未运行。
因此配对恢复、REAL 页面、当前地图/pose 与 capability 检查尚未执行。App 已再次 force-stop，
没有切换机器人服务或执行运动。安装证据见 `source-runs/app-real-installation.json`；启动正式
Runtime/Gateway 属于下一独立授权门，不能用历史数据库或 MOCK 投影替代。

## App REAL 无运动运行时检查

经单独运行时授权，在 `172.22.205.44` 临时启动当前 Issue 33 REAL Runtime/ROS 投影和 TLS
Gateway。OnePlus App 通过手动地址发现目标并恢复既有配对会话；“真实设备状态”显示正确机器人
ID、`REAL`、100% 新鲜电量，以及本页运动能力禁用。App 快照连续，`battery_status` capability
为 `ok/capability_ready` 且不可写。

地图/pose 检查没有通过：当前投影为 `navigation_not_configured`，地图视图为
`navigation_pose_missing`，`map`、`robot_pose`、`dock_pose` 均为空，App 显示“当前没有可展示的
地图”；资料库中的“现场地图 2”仅作为可用目录项显示。进入手动建图准备页只执行只读 preflight，
结果为“建图准备状态暂时不可用”，没有继续启动。

检查结束后 App 已 force-stop，Gateway 与 Runtime 已正常退出，`8443` 无监听且 IPC socket 已清理。
临时数据库证明 mapping operation、manual session、mapping authorization 和 map switch 均为 0。
导航板四个 systemd 单元的 PID、状态及激活时间戳前后完全一致。完整本次运行证据见
`source-runs/app-real-readonly-runtime-check.json`。这只关闭配对恢复、REAL 页面和只读 capability
接线检查，不满足地图/pose 门，也不替代 App 摇杆运动验收；正式进度仍为 `9/23`（约 `39%`）。
