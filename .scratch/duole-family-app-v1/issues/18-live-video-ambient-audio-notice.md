# 贯通实时画面、环境音与机器人持续提示

Status: needs-triage

Type: HITL

User stories covered: 66–69, 80–85

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

交付单手机 Engineering V1 的第一个媒体纵向切片：已配对 Android 创建 watch session 后，
机器人先激活持续可感知提示，再通过不争抢现有 camera/microphone owner 的共享源和加密
WebRTC 向 App 提供实时 RGB 与自动开启的环境音。媒体状态、质量、故障、隐私关闭和结束均
可观察且不落盘。

## Acceptance criteria

- [ ] 技术预研记录当前相机/麦克风 owner、共享 RGB/PCM 出口、硬件编码方案、资源测量和最终选型。
- [ ] Media Gateway 不再次打开 camera device 或启动第二个 ALSA capture；HIL 证据证明现有跌倒/人员视觉与语音链持续正常。
- [ ] watch session 只有在 actor scope、visual privacy、source health、participant limit 和 robot notice 全部通过后创建。
- [ ] 媒体可消费前机器人激活持续可感知的观看提示；提示不可用或激活失败时拒绝静默直播。
- [ ] App 打开画面后同时收到 robot video 和 ambient audio；单轨故障明确降级，不显示黑屏/静音假在线。
- [ ] signaling 使用认证 WSS，媒体使用 DTLS-SRTP；长期 access token 不放 URL 或交给媒体子进程。
- [ ] App 显示 connecting、live、degraded、ended、首帧、最后帧和稳定失败原因。
- [ ] source frame age、编码队列、FPS、bitrate、RTT、jitter、loss 和最后 sample time 形成有界质量投影。
- [ ] 本地隐私锁、session/token 撤销、media process 故障和最后参与者离开会断流、清缓存并撤销提示。
- [ ] 实时音视频默认不录制、不写诊断包；App 不提供产品内截图/录屏按钮，也不声称阻止系统录制。
- [ ] 真实目标板与手机连续 30 分钟满足首帧、延迟、CPU、内存、温度和无 owner 抢占基线。
- [ ] contract、session/authorization、shared source、WebRTC、privacy integration 和 Android Live UI 测试通过。

## Blocked by

- [04 实现一次性配对、安装实例绑定与撤销](04-pairing-session-revocation.md)
- [09 实现视觉隐私远程控制及媒体与运动联动关闭](09-visual-privacy-remote-control.md)
