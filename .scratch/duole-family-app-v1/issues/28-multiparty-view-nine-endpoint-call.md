# 实现多人观看、九端通话、头像与机器人宫格布局

Status: needs-triage

Type: HITL

User stories covered: 86–91

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

把一对一媒体 session 演进为 Family Product 多参与者能力：多位有权限家属可同时观看，机器人
加最多八位家属进入九端通话；每位家属可独立开关摄像头，关闭后显示头像；机器人屏幕按
参与人数选择双格、四宫格或九宫格，屏幕链不可用时自动降级为多人语音。PTT 仍保持互斥，
通话允许多人同时发声。

## Acceptance criteria

- [ ] 选定并评审适合公网多参与者的 SFU/媒体架构，不改变机器人本地 privacy/notice/audio safety owner。
- [ ] 多位具有 live-view scope 的成员可同时观看 robot video/audio，participant join/leave 有稳定 identity/event。
- [ ] 通话最多九个 endpoint：机器人加最多八位家属；达到上限返回稳定错误，不静默挤出参与者。
- [ ] 每位家属可独立 camera on/off 和 mute；camera off 时向其他端和机器人显示授权头像/名称。
- [ ] 机器人 screen 根据 active video participant 自动使用双格、四宫格或九宫格，并避免频繁抖动切换。
- [ ] screen/render path 不可用时通话自动降级多人语音，并向所有参与者显示明确原因。
- [ ] group call 允许多人同时发声，真实 AEC/mix/latency 不破坏机器人 safety output 优先级。
- [ ] PTT 在多人观看时仍为单 holder；竞争者看到 holder busy，松手/断线自动释放，无接管申请。
- [ ] 本地 privacy off、机器人离线、家庭权限撤销和高风险安全状态按策略结束/降级所有参与者。
- [ ] participant camera/media 不默认录制；SFU 日志和诊断不保存媒体内容或无关家庭隐私。
- [ ] App、机器人屏幕、SFU、权限、会话恢复、网络降级和九端压力/长稳测试通过。
- [ ] 完成真实多手机、远程网络、机器人扬声器/屏幕及安全抢占 HIL/产品验收。

## Blocked by

- [18 贯通实时画面、环境音与机器人持续提示](18-live-video-ambient-audio-notice.md)
- [20 实现一对一全双工通话与音频仲裁](20-one-to-one-full-duplex-call.md)
- [25 实现家庭账号、成员、三级身份与多管理员](25-household-accounts-roles-admins.md)
- [27 实现安全远程接入、可靠推送与短信兜底](27-secure-remote-notification-sms.md)
