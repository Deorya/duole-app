# 实现地图、机器人位姿、房间与巡逻路线只读视图

Status: ready-for-human

Implementation: complete-2026-08-24

Acceptance: accepted-2026-08-24

Type: AFK

User stories covered: 117–121

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

建立受控导航 read model，让 Android 机器人页显示当前版本化地图、机器人 pose、充电桩、
已验证房间和巡逻路线。公网关只获得稳定 DTO 和受认证图像资源，不暴露导航板文件路径、任意
坐标或底层参数写入口。

## Acceptance criteria

- [x] 网关返回稳定 map ID/revision/hash、尺寸、分辨率、origin、更新时间和受认证图像资源。
- [x] robot pose 包含 map frame、位置、朝向、观测时间和 stale threshold；陈旧定位不能显示为实时。
- [x] 充电桩 pose 为只读；App 不提供移动、重设或写入接口。
- [x] rooms 返回稳定 room ID、display name、目标验证状态和当前可用性，不返回任意坐标。
- [x] patrol routes 返回稳定 route ID、点位摘要、验证状态和不可用原因。
- [x] App 地图页展示机器人、充电桩、房间和活动路径，并在地图/定位版本不匹配时禁用任务入口。
- [x] 房间展示名修改若纳入 E1，只写独立版本化产品 metadata，不改变地图几何或导航目标。
- [x] 本只读切片不支持地图上传、墙体/禁行区编辑、任意巡逻点、导航参数或本地 path traversal；后续禁行区写入只能走独立版本化地图管理合同。
- [x] adapter 对导航板缺失、定位陈旧、图像损坏和 map revision 变化返回稳定状态。
- [x] contract、资源授权、path traversal、安全缓存和 Android map/room UI 测试通过。

## Blocked by

- [04 实现一次性配对、安装实例绑定与撤销](04-pairing-session-revocation.md)
- [05 实现一致能力快照与机器人状态页面](05-capability-snapshot-robot-status.md)

## Comments

### 2026-08-24 implementation and acceptance

- 已交付持久导航 read model、受认证 revision-bound PNG、ETag/304、安全精确路径解析、
  真实 ROS `/map`/`/amcl_pose` adapter，以及 Android 地图/房间/路线/活动路径只读页。
- 实板 `map_server` 返回 471×431、0.05 m/px 地图；AMCL 在有界探针中没有可用 durable
  pose，adapter 正确返回 `navigation_pose_missing`，没有伪造机器人位置。
- 合同、授权、缓存、path traversal、缺失/陈旧/损坏/revision 变化、ROS QoS、Dart
  byte transport 和 Flutter UI/task gate 全部通过。详细冻结边界见
  `docs/interface_freeze/app_v1/issue_13_map_pose_rooms_routes_readonly.md`。

Issue 13 的 AFK 验收条件已全部关闭。
