# 完成正式生命周期、长稳、无障碍与 Engineering APK 验收

Status: needs-triage

Type: HITL

User stories covered: 156–175

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

把所有 Engineering V1 纵向能力纳入唯一正式产品生命周期，完成配置、启动/停止、升级、
回滚、长稳、性能、无障碍、安全和版本矩阵验收，并交付可在 Windows 重复构建的 Android
Engineering APK。该工单不新增业务功能；它把前序切片从独立演示提升为一套可交付工程版本。

## Acceptance criteria

- [ ] 唯一正式产品入口显式装配/监督 domain facade、projection、public gateway 和启用的 media child，无独立重复产品入口。
- [ ] 启动顺序确保 identity/IPC/projection ready 后才监听业务和发布 mDNS；失败 capability 诚实 unavailable，语音/安全按批准策略继续。
- [ ] 停止顺序先拒绝新写、撤销 teleop/PTT/call/media、触发并确认停止，再 flush projection 和清理精确 child/socket。
- [ ] 新功能默认 disabled；Engineering 配置、identity/state/runtime path 的 owner、mode、symlink 和磁盘余量检查 fail closed。
- [ ] gateway/media crash、runtime restart、网络抖动、磁盘压力和 schema mismatch 不重放旧写、不留下 lease、媒体提示或孤儿进程。
- [ ] 完成 8 小时及批准的 24 小时长稳，记录 API、event、media、memory/thread/fd、temperature、log rotation 和 projection growth。
- [ ] Android 支持 200% 字体、至少 48×48 触点、非颜色单一语义、常见小屏/横竖屏和系统暗色；Live/Teleop 保持安全生命周期。
- [ ] Engineering 与 Family build capability/route 分离；Engineering APK 有醒目标识，Family build 不含诊断和危险测试入口。
- [ ] Windows clean build 可重复，依赖锁定，release APK 有版本、签名策略、SHA-256 和安装/回滚说明。
- [ ] 运行时升级先做 config/schema migration dry-run；Schedule/identity/projection 各自具有正确备份或 generation/revoke 策略。
- [ ] 安全审查覆盖 TLS、secret scan、依赖/SBOM、最小 OS 权限、输入/资源限制和诊断隐私。
- [ ] 验收记录绑定 App、gateway、media、runtime、navigation-board、schema、手机、路由器和机器人硬件版本。
- [ ] 所有 P0 SCHEMA/SIM/HIL/REAL 证据齐全；缺少 REAL teleop 证据时允许发布其他能力，但 REAL teleop 必须保持关闭。
- [ ] App、Gateway、Runtime、Schedule、Media、Motion Safety、Privacy/Security 和 QA owner 完成最终签字。

## Blocked by

- [07 实现安全事故时间线与局域网通知](07-safety-incidents-lan-notifications.md)
- [08 实现可定制首页与活动事件动态置顶](08-custom-home-active-event-priority.md)
- [09 实现视觉隐私远程控制及媒体与运动联动关闭](09-visual-privacy-remote-control.md)
- [10 贯通日程只读、今日摘要与执行记录](10-schedule-read-summary-history.md)
- [11 实现 Schedule V2、版本化 CRUD 与启停](11-schedule-v2-versioned-crud.md)
- [12 实现提醒确认、稍后、跳过与升级结果](12-reminder-confirmation-escalation.md)
- [13 实现地图、机器人位姿、房间与巡逻路线只读视图](13-map-pose-rooms-routes-readonly.md)
- [14 实现独立紧急停止与机器人停止确认](14-emergency-stop-confirmation.md)
- [15 贯通房间导航 Job 创建、恢复、取消与终态](15-room-navigation-job-lifecycle.md)
- [16 贯通即时巡逻与回充 Job](16-immediate-patrol-docking-jobs.md)
- [17 贯通定时巡逻、执行门禁与跳过结果](17-scheduled-patrol-gates.md)
- [18 贯通实时画面、环境音与机器人持续提示](18-live-video-ambient-audio-notice.md)
- [19 实现互斥按住喊话及音频恢复](19-exclusive-push-to-talk.md)
- [20 实现一对一全双工通话与音频仲裁](20-one-to-one-full-duplex-call.md)
- [21 贯通 MOCK_NO_MOTION 遥控会话、按压租约与视频门](21-mock-teleop-lease-video-gate.md)
- [22 实现导航板 TeleopGuard、双 watchdog 与真车遥控](22-real-teleop-guard-watchdogs.md)
- [23 实现脱敏诊断导出与跨层关联追踪](23-redacted-diagnostics-correlation.md)
