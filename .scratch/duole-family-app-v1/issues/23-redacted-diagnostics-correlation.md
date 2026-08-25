# 实现脱敏诊断导出与跨层关联追踪

Status: needs-triage

Type: AFK

User stories covered: 12, 153–162

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

为 Engineering build 交付可独立使用的诊断页和异步导出：从 App request ID 关联到网关、领域
operation/job、projection event、导航/媒体状态和最终结果；导出仅使用字段白名单，能定位
常见连接、重连、媒体和任务故障，但不包含凭据、音视频或原始对话。

## Acceptance criteria

- [ ] 诊断页展示 App、gateway、media、runtime、schema、navigation adapter 和 mode 版本。
- [ ] 每个跨层请求可按 request/operation/job/session/lease/event ID 查看稳定阶段、结果码和有界延迟摘要。
- [ ] 健康信息区分 process liveness、service readiness、business capability 和 data freshness。
- [ ] 事件诊断包含 high-water、earliest seq、continuity/rebuild、WS reconnect、gap 和 slow-client 计数。
- [ ] 媒体诊断包含首帧、FPS、frame age、jitter/loss、audio mode/AEC 摘要，不包含 frame、PCM 或完整 SDP。
- [ ] teleop 诊断包含 lease/epoch、最后 accepted seq、watchdog、zero/stop 时间和稳定结束原因，不保存长期完整摇杆轨迹。
- [ ] 异步导出有 scope、rate/size/retention 限制，完成后返回受认证短期资源或稳定失败。
- [ ] allowlist 明确排除 token、pairing code、private key、Authorization、媒体、raw ASR/chat、完整环境变量、DB 副本和内部 secret path。
- [ ] gateway/runtime restart、projection degraded 和结果不明请求仍可用已有 ID 诊断，且不会触发动作重放。
- [ ] Family build 在编译和路由层不存在工程诊断入口，不仅是隐藏菜单。
- [ ] 自动 secret fixtures、oversized diagnostics、exception redaction、export lifecycle 和 Android UI 测试通过。

## Blocked by

- [05 实现一致能力快照与机器人状态页面](05-capability-snapshot-robot-status.md)
- [06 实现持久事件投影、WebSocket 补拉与重同步](06-event-projection-replay-resync.md)
