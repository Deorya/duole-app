# 多乐守护 App API 建议合同

Status: `minimal-read-only-slice-frozen-v1; remaining-sections-proposal`

Contract state: `mixed`

Minimal read-only slice scope: `frozen-2026-08-18`

版本：`app-api-v1-mixed`

> 重要：本文件仍是范围说明和后续接口建议，不是机器可读字段来源。已冻结的最小只读切片以
> API 提供方发布的 `docs/interface_freeze/app_v1/openapi.json` 为唯一事实源；App 构建应消费
> 版本化发布件，本文其余章节不得被客户端当作已部署合同。

> 已冻结的是首个只读切片的范围与语义决策：通用 envelope、request ID、server time、TTL、
> 幂等与 revision 规则，`REAL`/`MOCK_NO_MOTION`，机器人身份/版本、能力表达及一项真实
> Device Status。其机器可读合同、fixture、Python/Dart 验证和兼容性测试已由实施工单 01
> 交付；本文件其余事件、媒体、日程写、导航和遥控章节继续保持建议状态。

## 1. 目标与协议

| 通道 | 建议地址 | 用途 |
|---|---|---|
| REST | `https://{robot-host}:{port}/api/v1` | 快照、资源查询、低频写操作、任务创建 |
| Events WS | `wss://{robot-host}:{port}/api/v1/events/ws` | 状态、事件和任务增量及断线补拉 |
| Media signaling WS | `wss://.../api/v1/media/sessions/{id}/signaling` | WebRTC SDP/ICE、喊话与会话控制 |
| Teleop WS | `wss://.../api/v1/teleop/sessions/{id}/stream` | 短租约、保活、有序遥控意图和停止确认 |
| WebRTC | 协商所得 P2P 连接 | E1 单手机加密音视频 |

- JSON 字段使用 `snake_case`，UTF-8。
- 时间使用 RFC 3339 并包含时区偏移；持续时间使用以 `_ms` 结尾的整数。
- ID 是不透明字符串，建议 ULID/UUID；客户端不得解析其中业务含义。
- REST 基路径 major 版本化；事件消息含 `schema_version`。
- OpenAPI 3.1 建议由 `/api/v1/openapi.json` 提供给工程构建，家庭构建不必暴露交互文档。
- E1 只允许经配对的受控局域网客户端；不得降级明文 HTTP/WS 传 token 或控制命令。

## 2. 范围标记

| 标记 | 含义 |
|---|---|
| `E1-P0` | Engineering V1 必须实现并验收 |
| `E1-P1` | Engineering V1 可在 P0 后实现 |
| `FUTURE` | Family Product 预留，不属于 E1 完成条件 |

接口可以预留扩展字段，但 E1 实现不能返回假数据冒充 FUTURE 能力。

## 3. 通用请求

已配对请求头：

```http
Authorization: Bearer <device-binding-token>
X-Request-ID: req_01...
X-Client-Version: android-engineering/0.1.0
X-Sent-At: 2026-08-18T10:42:12.238+08:00
X-TTL-Ms: 5000
Idempotency-Key: idem_01...   # 所有有副作用 POST 必填
```

- `X-Request-ID` 用于追踪，不承担幂等。
- `Idempotency-Key` 在同一机器人、操作者和接口范围内去重；同 key 不同 body 返回冲突。
- 网关拒绝时钟偏差过大或已过 TTL 的控制命令。
- 查询请求不需要 `Idempotency-Key`；版本化更新使用 `If-Match` 或明确 `revision`。
- 客户端不得在 query string 传 token、配对码或个人信息。

### 3.1 成功 envelope

```json
{
  "schema_version": "1.0",
  "request_id": "req_01...",
  "server_time": "2026-08-18T10:42:12.301+08:00",
  "data": {}
}
```

创建异步任务使用 `202 Accepted`；资源创建完成使用 `201 Created`；幂等重试返回相同资源与
原始结果，并可加 `Idempotent-Replayed: true`。

### 3.2 错误 envelope

```json
{
  "schema_version": "1.0",
  "request_id": "req_01...",
  "server_time": "2026-08-18T10:42:12.301+08:00",
  "error": {
    "code": "LOCAL_PRIVACY_LOCKED",
    "message": "机器人本地已开启隐私锁",
    "retriable": false,
    "remediation": "请在机器人本地解除隐私锁后重试",
    "details": {
      "gate": "local_privacy_lock"
    }
  }
}
```

客户端以 `code` 决定稳定交互，以 `message` 作为可替换服务端文案；不能解析 message 做逻辑。
`details` 不得包含 traceback、token 或内部文件路径，工程细节通过授权诊断接口关联 request ID。

## 4. 分页、revision 与枚举

列表使用游标：

```json
{
  "items": [],
  "next_cursor": "opaque-or-null",
  "has_more": false
}
```

- 默认稳定排序必须写入接口定义，例如事件按 `(occurred_at desc, event_id desc)`。
- 可修改资源返回整数 `revision` 与 `etag`。更新请求携带 `If-Match: \"rev-7\"`；不匹配返回
  `409 REVISION_CONFLICT` 并可附当前资源摘要。
- 未识别的枚举不能映射为某个已知安全状态。客户端显示 `unknown` 并禁用相关写操作。

## 5. 发现、身份与配对

### 5.1 mDNS（E1-P0）

服务类型建议 `_duole-app._tcp.local`。TXT 仅作候选提示：

```text
robot_id_hint=rb_ab12
display_name=工程机01
api_major=1
gateway_version=0.1.0
mode=REAL
tls_required=1
```

发现信息不可信；所有字段在 TLS 身份端点重新核对。

### 5.2 未配对设备身份（E1-P0）

`GET /.well-known/duole-app`

```json
{
  "robot_id": "rb_01...",
  "display_name": "工程机 01",
  "gateway_version": "0.1.0",
  "api_versions": ["1.0"],
  "mode": "REAL",
  "device_key_fingerprint": "sha256:AB:CD:...",
  "pairing": {
    "available": true,
    "method": "local_code_and_fingerprint"
  }
}
```

该端点不得泄漏家庭成员、状态、事件、地图或日志。

### 5.3 换取绑定令牌（E1-P0）

`POST /api/v1/pairing/exchange`

```json
{
  "pairing_session_id": "pair_01...",
  "code": "482913",
  "installation_id": "ins_01...",
  "installation_public_key": "base64url...",
  "engineer_display_name": "张工",
  "verified_device_fingerprint": "sha256:AB:CD:..."
}
```

成功 `201`：

```json
{
  "schema_version": "1.0",
  "request_id": "req_01...",
  "server_time": "2026-08-18T10:42:12+08:00",
  "data": {
    "robot": {"robot_id": "rb_01...", "display_name": "工程机 01"},
    "device_session_id": "dvs_01...",
    "access_token": "opaque-secret-returned-once",
    "expires_at": "2026-09-17T10:42:12+08:00",
    "scopes": ["status.read", "live.view", "robot.stop"]
  }
}
```

错误至少包括 `PAIRING_CODE_INVALID`、`PAIRING_CODE_EXPIRED`、`PAIRING_RATE_LIMITED`、
`DEVICE_IDENTITY_MISMATCH`。成功后 code 立即失效。

### 5.4 当前会话（E1-P0）

- `GET /session`：当前设备会话、scopes、过期时间、机器人身份。
- `POST /session/refresh`：用安装实例密钥证明轮换短期 token；已撤销会话不得续期。
- `DELETE /session`：撤销当前会话并结束其媒体/遥控租约；不自动停止非运动类长期日程。
- `GET /paired-clients`：工程模式列出显示名、安装实例掩码、最后活动。
- `DELETE /paired-clients/{device_session_id}`：撤销指定工程客户端。

Family Product 将这些端点替换/扩展为账号和家庭会话，但 scopes 结构保持。

## 6. 能力、快照与状态

### 6.1 能力（E1-P0）

`GET /capabilities`

```json
{
  "schema_version": "1.0",
  "request_id": "req_...",
  "server_time": "2026-08-18T10:42:12+08:00",
  "data": {
    "robot_id": "rb_...",
    "mode": "REAL",
    "capability_revision": 12,
    "items": [
      {
        "key": "teleop",
        "available": false,
        "reason_code": "video_latency_high",
        "depends_on": ["live_video", "motion_owner", "base_watchdog"],
        "limits": {
          "intent_range": [-1.0, 1.0],
          "max_video_latency_ms": 800
        }
      }
    ]
  }
}
```

`mode` 仅允许机器人端决定的 `REAL|MOCK_NO_MOTION`。未知模式禁止运动写操作。

### 6.2 一致快照（E1-P0）

`GET /snapshot`

返回：`snapshot_seq`、`server_time`、机器人身份/模式、capabilities、设备状态、活动 incidents、
活动 jobs、今日日程摘要、隐私和媒体摘要。所有部分都包含自己的更新时间/陈旧阈值。

```json
{
  "snapshot_seq": 18422,
  "earliest_available_seq": 17001,
  "robot": {"robot_id": "rb_...", "display_name": "工程机 01", "mode": "REAL"},
  "states": [
    {
      "key": "visual_monitoring",
      "health": "ok",
      "summary": "视觉监护已开启",
      "reason_code": "ready",
      "updated_at": "2026-08-18T10:42:10+08:00",
      "stale_after_ms": 5000,
      "affected_capabilities": []
    }
  ],
  "active_incidents": [],
  "active_jobs": [],
  "today_schedule_summary": {"total": 2, "next_occurrence_at": "2026-08-18T14:30:00+08:00"}
}
```

### 6.3 状态查询（E1-P0）

- `GET /states`：全部产品状态项。
- `GET /states/{key}`：单项及依赖证据摘要。
- `GET /versions`：App 可见的网关、领域接口、媒体和导航合同版本。

状态健康枚举：`ok|degraded|unavailable|disabled|unknown`。`stale` 建议由 App 根据服务器时间与
`stale_after_ms` 计算，同时接受服务端显式标记。

## 7. 事件、事故与重连

### 7.1 事件 envelope（E1-P0）

```json
{
  "schema_version": "1.0",
  "seq": 18423,
  "event_id": "evt_01...",
  "type": "incident.updated",
  "occurred_at": "2026-08-18T10:42:12.238+08:00",
  "published_at": "2026-08-18T10:42:12.301+08:00",
  "source": "vision_fall",
  "source_event_id": "source-stable-id",
  "correlation": {
    "incident_id": "inc_01...",
    "request_id": null,
    "job_id": null
  },
  "payload": {}
}
```

- `seq` 在单机器人事件流中单调递增；`event_id` 全局稳定。
- 同一来源重试不生成新的产品事件 ID。
- `occurred_at` 是事实发生时间，`published_at` 是进入 App 流时间。
- 客户端按 `event_id` 去重、按 `seq` 检测缺口，不按到达顺序猜测。

### 7.2 WebSocket 握手（E1-P0）

连接：`GET /events/ws?after_seq=18422`，认证放在安全 header 或经平台限制认可的一次性 WS
ticket 中，不能把长期 token 放 URL。

服务器首条消息：

```json
{
  "type": "connection.hello",
  "schema_version": "1.0",
  "connection_id": "con_01...",
  "latest_seq": 18440,
  "earliest_available_seq": 17001,
  "heartbeat_interval_ms": 15000,
  "server_time": "2026-08-18T10:43:00+08:00"
}
```

补发完成：

```json
{"type":"sync.complete","through_seq":18440}
```

若 `after_seq` 太旧：

```json
{"type":"sync.resync_required","earliest_available_seq":17001,"latest_seq":18440}
```

App 此时重新获取完整快照。心跳超时视为断线，不能继续显示实时状态。

### 7.3 历史查询（E1-P0）

- `GET /events?after_seq={n}&limit={1..500}`：增量补拉。
- `GET /incidents?status=active|closed&cursor=...`：事故列表。
- `GET /incidents/{incident_id}`：产品级事实、等级和时间线。
- `POST /incidents/{incident_id}/viewed`：`FUTURE/E1-P1`，仅记录某成员已打开详情，不关闭
  事故、不表示已处置、不认领任务。

事故 severity：`observing|attention|emergency`。产品字段不得要求 App 根据 raw probability
推导 severity。工程诊断扩展可受控返回原始分数，并明确标识 `diagnostic_only: true`。

### 7.4 主要事件类型（E1-P0）

```text
state.changed
capability.changed
incident.created
incident.updated
incident.closed
job.created
job.updated
schedule.changed
schedule.occurrence.updated
privacy.changed
media.session.updated
teleop.revoked
diagnostic.notice
```

新增未知事件类型必须可安全忽略，同时保持 seq 前进和记录工程诊断。

## 8. 媒体与信令

### 8.1 可用性（E1-P0）

`GET /media/availability`

```json
{
  "available": true,
  "video": {"available": true, "reason_code": "ready"},
  "ambient_audio": {"available": true, "reason_code": "ready"},
  "talk": {"available": true, "reason_code": "ready"},
  "call": {"available": true, "reason_code": "ready"},
  "local_privacy_locked": false,
  "robot_notice": {"available": true, "method": "screen_indicator"},
  "max_app_participants": 1
}
```

### 8.2 创建观看/通话会话（E1-P0）

`POST /media/sessions`

```json
{
  "purpose": "watch",
  "requested_tracks": ["robot_video", "robot_ambient_audio"],
  "client_media": {
    "audio_codecs": ["opus"],
    "video_codecs": ["h264", "vp8"]
  }
}
```

`purpose`：E1 为 `watch|call`。成功 `201`：

```json
{
  "media_session_id": "med_01...",
  "state": "signaling",
  "purpose": "watch",
  "signaling_path": "/api/v1/media/sessions/med_01/signaling",
  "expires_if_unconnected_at": "2026-08-18T10:43:30+08:00",
  "robot_notice_state": "active",
  "limits": {"max_app_participants": 1}
}
```

- `GET /media/sessions/{id}`：会话、tracks、健康、质量和降级原因。
- `DELETE /media/sessions/{id}`：幂等结束会话并释放 talk lease。
- 同一 E1 机器人已有手机媒体会话时返回 `MEDIA_SESSION_BUSY`，而非暗中替换。

### 8.3 信令消息（E1-P0）

标准控制 envelope：

```json
{
  "type": "webrtc.offer",
  "message_id": "msg_01...",
  "sent_at": "2026-08-18T10:42:12+08:00",
  "payload": {"sdp": "..."}
}
```

最低消息集：`webrtc.offer`、`webrtc.answer`、`webrtc.ice_candidate`、`webrtc.renegotiate`、
`media.quality`、`media.degraded`、`session.ended`、`ping/pong`。

### 8.4 按住喊话控制（E1-P0）

在观看会话的 signaling WS 发送：

```json
{"type":"talk.acquire","message_id":"msg_...","payload":{"lease_ttl_ms":1500}}
```

服务器响应之一：

```json
{"type":"talk.granted","payload":{"talk_lease_id":"tlk_...","expires_at":"..."}}
```

```json
{
  "type":"talk.busy",
  "payload":{"holder_display_name":"另一客户端","retry_after_ms":500}
}
```

取得 `talk.granted` 后才允许启用 App 上行音轨。持有期间发送 `talk.heartbeat`，松手发送
`talk.release` 并立即静音本地轨；连接中断或租约到期服务端自动释放。

### 8.5 通话（E1-P0/FUTURE）

E1 使用 `purpose=call` 的单手机全双工音频，创建成功后机器人自动接通并开启本地提示。媒体
状态需要返回 `audio_arbiter_mode=full_duplex_call` 与 AEC/降级信息。

Family Product 扩展会话为最多 9 端点（机器人 + 8 家属），增加 participant join/leave、
camera on/off、avatar、mute 和机器人屏幕布局事件；E1 不实现这些接口，也不显示九宫格按钮。

## 9. 手动遥控与停止

### 9.1 创建遥控会话（E1-P0）

`POST /teleop/sessions`

```json
{
  "media_session_id": "med_01...",
  "expected_capability_revision": 12
}
```

成功 `201`：

```json
{
  "teleop_session_id": "top_01...",
  "state": "armed",
  "stream_path": "/api/v1/teleop/sessions/top_01/stream",
  "lease_ttl_ms": 400,
  "heartbeat_interval_ms": 100,
  "intent_rate_hz": 15,
  "intent_range": [-1.0, 1.0],
  "video_latency_limit_ms": 800,
  "server_enforced_profile": "family_safe_low_speed_v1",
  "gates": [
    {"key":"video_fresh","passed":true},
    {"key":"motion_owner_available","passed":true}
  ]
}
```

具体租约/频率由技术预研冻结；客户端使用服务端返回值，不硬编码。响应不能返回可被 App
提高的真实速度上限。

### 9.2 遥控 WS（E1-P0）

按住开始：

```json
{
  "type": "control.acquire",
  "message_id": "msg_...",
  "sent_at": "2026-08-18T10:42:12.100+08:00"
}
```

获得租约：

```json
{
  "type":"control.granted",
  "payload":{"control_lease_id":"ctl_...","lease_ttl_ms":400,"next_seq":1}
}
```

持续意图：

```json
{
  "type": "control.intent",
  "control_lease_id": "ctl_...",
  "seq": 1,
  "sent_at": "2026-08-18T10:42:12.150+08:00",
  "ttl_ms": 200,
  "payload": {
    "linear": 0.42,
    "angular": -0.18
  }
}
```

`linear`、`angular` 必须在 `[-1,1]`。服务器丢弃超范围、过期、重复、乱序或租约不匹配消息。

松手：

```json
{
  "type":"control.release",
  "control_lease_id":"ctl_...",
  "seq":42,
  "payload":{"reason":"pointer_up"}
}
```

服务端必须回：

```json
{
  "type":"control.stopped",
  "payload":{"control_lease_id":"ctl_...","stop_confirmed_at":"...","reason":"released"}
}
```

服务端主动消息还包括 `control.ack`、`control.gate_changed`、`control.revoked`、
`control.stop_pending`、`control.stopped`。App 不能仅凭已发送 release 显示停止确认。

### 9.3 独立停止（E1-P0）

`POST /motion/stop`

```json
{
  "reason": "user_emergency_stop",
  "cancel_app_owned_jobs": true
}
```

该接口不要求持有遥控租约，但需要 `robot.stop` scope；幂等、高优先级。返回 `202` 与
`stop_operation_id`，随后通过事件或 `GET /motion/stop-operations/{id}` 获得机器人确认。
无法确认停止返回 `STOP_UNCONFIRMED` 并要求现场核查。

### 9.4 结束遥控会话（E1-P0）

`DELETE /teleop/sessions/{id}`：先释放租约并确认停止，再结束会话。连接直接消失时机器人端
watchdog 自动归零；DELETE 不是唯一安全路径。

## 10. 导航、巡逻和回充任务

### 10.1 创建任务（E1-P0）

`POST /jobs`

前往房间：

```json
{
  "type": "navigate_to_room",
  "target": {"room_id": "room_living"},
  "confirmation": null
}
```

立即巡逻：

```json
{
  "type": "patrol",
  "target": {"route_id": "route_daily", "rounds": 1},
  "confirmation": null
}
```

回充：

```json
{
  "type": "dock",
  "target": {},
  "confirmation": {
    "acknowledged_effect": "cancel_current_job_and_start_docking",
    "confirmed_at": "2026-08-18T10:42:12+08:00"
  }
}
```

成功 `202`：

```json
{
  "job_id": "job_01...",
  "type": "dock",
  "state": "queued",
  "created_at": "2026-08-18T10:42:12+08:00",
  "request_id": "req_01..."
}
```

E1 不开放 `navigate_to_pose`、`come_here`、找人、任意 ROS Action 或任意参数接口。

### 10.2 查询与取消（E1-P0）

- `GET /jobs?state=active&cursor=...`
- `GET /jobs/{job_id}`
- `POST /jobs/{job_id}/cancel`，幂等，返回取消操作状态。

任务状态：`queued|accepted|running|succeeded|failed|canceled`。终态不得退回运行态。对象包含
`progress`、`stage`、`failure_code`、`created_by` 和阶段时间线。

门禁拒绝使用稳定码，如 `LOCALIZATION_STALE`、`MAP_MISMATCH`、`BATTERY_TOO_LOW`、
`MOTION_OWNER_BUSY`、`SAFETY_GATE_BLOCKED`，不能创建一个永远停在 queued 的假任务。

## 11. 地图、房间和路线

### 11.1 当前地图（E1-P0）

- `GET /maps/current`：`map_id`、`revision`、尺寸、分辨率、origin、更新时间、图像资源 URL、
  机器人 pose、充电桩只读 pose、定位 freshness。
- `GET /maps/{map_id}/image`：受认证的栅格图资源，支持 ETag；不返回本地文件路径。
- `GET /rooms`：已验证 `room_id`、展示名、只读目标状态。
- `GET /patrol-routes`：已验证路线、点位摘要和可用性。

机器人 pose 示例：

```json
{
  "x_m": 1.24,
  "y_m": -0.52,
  "yaw_rad": 1.57,
  "frame": "map",
  "updated_at": "2026-08-18T10:42:11.8+08:00",
  "stale_after_ms": 1000
}
```

### 11.2 允许编辑（E1-P1）

`PATCH /rooms/{room_id}` + `If-Match`，只允许：

```json
{"display_name":"客厅"}
```

巡逻点只能从机器人端已验证候选中选择。API 不提供地图文件上传、墙体/禁行区、充电桩
pose、任意坐标和导航参数写入。

## 12. 日程与定时巡逻

### 12.1 统一资源（E1-P0）

`GET /schedules?from=...&to=...&kind=reminder|patrol&cursor=...`

日程基础模型：

```json
{
  "schedule_id": "sch_01...",
  "kind": "reminder",
  "title": "服药提醒",
  "enabled": true,
  "timezone": "Asia/Shanghai",
  "start_at": "2026-08-18T09:00:00+08:00",
  "recurrence": {
    "frequency": "weekly",
    "interval": 1,
    "weekdays": [1, 3, 5],
    "ends_at": null
  },
  "confirmation_policy": {
    "required": true,
    "retry_after_minutes": 5,
    "notify_after_minutes": 15
  },
  "payload": {"spoken_text": "该吃药了"},
  "revision": 7,
  "source": {"type":"app", "display_name":"张工"},
  "next_occurrence_at": "2026-08-19T09:00:00+08:00"
}
```

E1 最低 recurrence 支持 `once|daily|weekly`；月度和复杂例外规则只有后端真正支持时才公布
capability。日期星期建议 ISO 8601：周一为 1，周日为 7。

### 12.2 CRUD（E1-P0）

- `POST /schedules`：创建，返回 `201`、`schedule_id`、`revision`。
- `GET /schedules/{id}`：详情与下一次执行。
- `PATCH /schedules/{id}` + `If-Match`：修改允许字段。
- `POST /schedules/{id}/enable` / `disable` + `If-Match`：显式启停。
- `DELETE /schedules/{id}` + `If-Match`：删除并返回影响范围。

全部调用正式 Schedule 领域服务，不允许网关或 App 直写数据库。

### 12.3 定时巡逻（E1-P0）

同一 `/schedules` 资源使用 `kind=patrol`：

```json
{
  "kind": "patrol",
  "title": "晚间一层巡逻",
  "enabled": true,
  "timezone": "Asia/Shanghai",
  "start_at": "2026-08-18T20:00:00+08:00",
  "recurrence": {"frequency":"daily","interval":1,"weekdays":[],"ends_at":null},
  "confirmation_policy": {"required":false},
  "payload": {"route_id":"route_floor_1","rounds":1}
}
```

到点执行前重新过门禁。跳过不是 API 故障，occurrence 终态为 `skipped_by_gate` 并包含稳定
原因。不能因是定时任务绕过定位、隐私、电量、活动任务或安全条件。

### 12.4 执行记录与确认（E1-P0）

- `GET /schedule-occurrences?schedule_id=...&from=...&to=...`
- occurrence 状态：
  `scheduled|delivered|snoozed|completed|skipped|unconfirmed|delivery_failed|skipped_by_gate`。
- `POST /schedule-occurrences/{id}/outcomes`：可信端提交 `completed|snoozed|skipped`；每次提交
  带 actor 和幂等键。若 E1 只由机器人语音提交，App 仍通过只读接口看到同一结果。

Family Product 获授权家属编辑后立即生效，无需照护对象确认；机器人可播报变更。

## 13. 视觉隐私

### 13.1 查询（E1-P0）

`GET /privacy/visual`

```json
{
  "desired_state": "on",
  "effective_state": "on",
  "local_privacy_locked": false,
  "reason_code": "ready",
  "revision": 5,
  "affected_capabilities": [],
  "updated_at": "2026-08-18T10:42:12+08:00"
}
```

`desired_state` 与 `effective_state` 分开，避免“请求成功”冒充实际关闭。

### 13.2 请求切换（E1-P0）

`POST /privacy/visual/operations`

```json
{
  "desired_state": "off",
  "expected_revision": 5,
  "reason": "engineer_requested"
}
```

返回 `202` + `operation_id`。关闭顺序为 teleop 停止、媒体结束、视觉驱动任务结束、资源停止
确认，再发布 `effective_state=off`。开启时若本地锁存在，返回 `423 LOCAL_PRIVACY_LOCKED`。

- `GET /privacy/visual/operations/{id}`：`pending|running|succeeded|failed`。
- 不提供 `force=true`、绕过本地锁或直接启动相机 owner 的参数。

## 14. 工程诊断（Engineering build only）

### 14.1 只读信息（E1-P0）

- `GET /diagnostics/summary`：版本、模式、连接、事件游标、媒体/任务/状态健康摘要。
- `GET /diagnostics/requests/{request_id}`：白名单化阶段时间线。
- `GET /diagnostics/jobs/{job_id}`：任务适配和终态摘要。
- `GET /diagnostics/media/{media_session_id}`：首帧、帧率、丢包、抖动、延迟和音频模式。
- `GET /diagnostics/teleop/{teleop_session_id}`：租约、最后 seq、watchdog 与停止确认。

不提供任意日志文件路径、shell、SQL、ROS Topic 发布或任意动作调用。

### 14.2 导出（E1-P0）

`POST /diagnostics/exports`

```json
{
  "from": "2026-08-18T10:30:00+08:00",
  "to": "2026-08-18T10:45:00+08:00",
  "correlation_ids": ["req_01...", "job_01..."],
  "format": "json_zip"
}
```

返回导出任务 ID；完成后提供短时、单次授权下载。导出 manifest 列明字段、脱敏版本和时间
范围。服务端白名单禁止 token、配对码、音视频、原始语音/转写和无关个人信息。

## 15. Family Product 预留接口（FUTURE）

E1 不实现，但领域模型需保留：

- `/households/{id}/members` 与逐成员 grants；
- 设备登录、邀请、手机号验证、生物识别后的再认证凭据；
- 每成员通知偏好和“至少一名紧急接收者”约束；
- 可靠 push delivery/open 回执与 60 秒 SMS escalation；
- 最多 9 端点媒体房间、participant/camera/avatar/layout 状态；
- 权限与高风险操作审计查询；
- 公网安全 relay，不直接把机器人局域网端口暴露到互联网。

机构运维、批量设备、开发诊断另建管理端，不扩展家庭 App API 为通用运维后门。

## 16. 稳定错误码

| HTTP | code | 典型含义 |
|---:|---|---|
| 400 | `INVALID_ARGUMENT` | 字段/范围/重复规则无效 |
| 400 | `COMMAND_EXPIRED` | TTL 或客户端时间无效 |
| 401 | `AUTH_REQUIRED` | 未配对或 access token 无效 |
| 403 | `PERMISSION_DENIED` | scope 不允许 |
| 404 | `RESOURCE_NOT_FOUND` | ID 不存在或无权获知 |
| 409 | `REVISION_CONFLICT` | 资源已被语音端或其他客户端修改 |
| 409 | `IDEMPOTENCY_CONFLICT` | 同幂等键 body 不一致 |
| 409 | `MOTION_OWNER_BUSY` | 另一运动 owner 活跃 |
| 409 | `TALK_BUSY` | 另一参与者持有喊话权 |
| 409 | `MEDIA_SESSION_BUSY` | E1 已有手机媒体会话 |
| 410 | `EVENT_CURSOR_EXPIRED` | 增量历史已轮转，需完整同步 |
| 423 | `LOCAL_PRIVACY_LOCKED` | 机器人本地锁阻止远程开启 |
| 423 | `SAFETY_GATE_BLOCKED` | 当前安全条件拒绝动作 |
| 424 | `DEPENDENCY_UNAVAILABLE` | 相机/导航/音频等依赖不可用 |
| 429 | `RATE_LIMITED` | 配对或命令频率过高 |
| 503 | `CAPABILITY_UNAVAILABLE` | 当前版本或健康不支持 |
| 503 | `VIDEO_STALE` | 视频新鲜度不满足遥控 |
| 503 | `STOP_UNCONFIRMED` | 已请求停止但机器人未确认 |
| 503 | `MOCK_NO_MOTION` | 当前模式不允许真实运动 |
| 426 | `API_VERSION_UNSUPPORTED` | major 不兼容，禁止写操作 |

领域具体错误（定位陈旧、地图不匹配、电量过低等）在此基础上扩展，并保持稳定文档。

## 17. WebSocket 关闭与生命周期

建议应用级关闭原因：

| 原因 | 客户端行为 |
|---|---|
| `AUTH_REVOKED` | 清除会话并回到配对，不自动重试旧 token |
| `API_INCOMPATIBLE` | 停止写操作，显示版本诊断 |
| `SERVER_RESTARTING` | 退避重连，未知命令按 ID 查询 |
| `LOCAL_PRIVACY_LOCKED` | 结束媒体和遥控，进入隐私阻断页 |
| `SAFETY_PREEMPTED` | 立即回中，等待停止确认，展示抢占事件 |
| `HEARTBEAT_TIMEOUT` | 断开并重连；遥控由机器人 watchdog 停止 |

网络断开不一定能收到 close frame，所以全部安全释放必须也由租约/heartbeat 超时保证。

## 18. 契约测试要求

接口冻结前至少覆盖：

1. OpenAPI 能生成可编译 Dart client，nullable/enum/oneOf 行为明确。
2. 同幂等键同 body 返回同一任务；不同 body 返回冲突。
3. revision 冲突不会覆盖机器人语音端的更新。
4. WS 断线、重复、乱序、seq 缺口和游标过期可恢复。
5. 未知枚举、未知事件和新增字段不会崩溃或错误开放控制。
6. token 撤销立即终止对应媒体和遥控租约。
7. 本地隐私锁拒绝开启，并终止既有媒体/遥控。
8. teleop 过期/乱序包不维持非零速度；断链由机器人侧归零。
9. STOP 幂等且不依赖遥控权。
10. `MOCK_NO_MOTION` 不返回真实运动成功。
11. 诊断接口/导出不包含凭据、原始音视频或对话。
12. API/WS schema 版本与 APK 内声明一致。

## 19. 冻结清单

联合评审必须明确并记录：

- 实际 REST/WS 端口、TLS 和设备身份方案；
- pairing code 生命周期、限速与撤销；
- capability key、状态 freshness 和所有错误码；
- event seq 持久化边界与保留窗口；
- WebRTC codec、信令方向、硬件编码和音频模式；
- teleop 租约、发送频率、TTL、视频延迟阈值与机器人侧 watchdog；
- 任务状态到现有 Action/TaskCoordinator 的映射；
- 日程 recurrence、revision、确认结果与正式数据库适配；
- OpenAPI/JSON Schema 文件位置、兼容策略和契约测试 owner。

最小只读切片已经冻结并由上述 OpenAPI 文件约束；其余章节完成各自联合评审和机器可读固化
前，客户端仍不得把本文示例 JSON 当成已部署事实。
