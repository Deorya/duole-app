# Issue 33：修复版真车复测预检（2026-09-30）

用户确认在机器人旁、周围留出空地且可立即急停后，以正式 `--app-only
--app-manual-mapping-development` 入口启动 REAL Runtime 与 Gateway。平板通过新 ADB 地址
`172.22.205.14:42603` 连接，v2005 App 成功验证 Gateway 地址并恢复既有配对，进入“手动建图准备”。

准备页显示底盘静止、传感器、防碰撞保护、停止链路、存储空间、运动控制权和软件版本均满足；
电量项显示“请充电至 50% 后重试”，开始按钮禁用。按导航板实际 `ROS_DOMAIN_ID=42`
只读查询 `/battery_state`，单次 BMS 样本为 `percentage=0.13199999928474426`（约 13%）、
`power_supply_status=1`（CHARGING）、`current=4.0 A`，与电量门拒绝一致。

没有创建建图操作、发送摇杆运动或绕过 50% 门。已停止 Gateway 与 App-only Runtime，Runtime
报告 `ok=true`、`stopped_by=stop_requested`。退出后只读确认
`duole-navigation-stack.service=active`、`duole-mapping-manual.service=inactive`、
`duole-manual-mapping-runtime.service=inactive`。开发阶段碰撞过滤停用标记仍为 owner `ztl`、权限
`600`；由于未开始建图，本轮没有验证新版左右方向、碰撞过滤效果、停车确认或控制通道恢复。

待 BMS 新鲜电量达到至少 50% 后，在现场看护下重新执行正式 App-only 流程并完成上述复测。
