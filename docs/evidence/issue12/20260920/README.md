# Issue 12 真实提醒闭环验收（2026-09-20）

本记录补充 Issue 12 的真实机器人、Android、断线补拉、提醒升级和语音结果 HIL。验收使用
Provider 隔离候选 `/tmp/duole-issue12-hil-v4-candidate`，正式产品语音入口启动，Runtime mode 为
`REAL`；导航和视觉链均未启动。

## 候选与软件验证

- Provider 基线 commit：`322b5939d64771cfbd85051ad9f0467d159ae354`
- v4 候选文件集合摘要：
  `a4e7ac3f6cda8db3487b72ff1268ded9ebb4d7c6b29666f2b6e7b43dcb3b2f74`
- 候选包含两项真实语音过程中发现并以 TDD 修复的解析缺口：中文数字“`五分钟后提醒我`”，
  以及礼貌前缀“`好的，5 分钟后再提醒我`”。
- Issue 12 相关回归：`50 passed`。
- reSpeaker/语音输入相关回归：`87 passed`，另有 2 条既有 `pkg_resources` warning。
- 板端产品会话入口回归：`54 passed`。
- 收尾时将以上测试合并重跑：`191 passed, 2 warnings`。

本轮源代码中的关键文件 SHA-256：

- `controller_skill.py`：
  `50d4394436ce8da67f38fe7a49a9c03f0bebb04c09cd36d7142e2bc05b2d9954`
- `doubao_realtime_live_audio_stream.py`：
  `4fe77d053777ce0fd905dfc2c24f43c13e1ae0be312115469b73e6ddb5b9d009`
- `start_product_voice_board_session.sh`：
  `c912228b8986339a6c44de3ff086582ccd7748b0dd3d21f8afbde7b63d2ad206`

## 真实提醒闭环

- Android 创建 `Issue12SnoozeV2`，稳定 ID
  `schedule-9f33e63d898849788b07aebe8963d84c`，revision `1`，默认需确认策略。
- 首次播报与 5 分钟确认重试各成功一次。产品会话多次重启后未重复记录已成功播报动作。
- 15 分钟仍未确认后，parent occurrence 进入 `unconfirmed`，统一 event projection 产生唯一事件；
  source retry 后仍只有一个相同 source/revision 的事件。
- 真人说“`5 分钟后再提醒我`”，机器人答复“`好的，5分钟后再提醒`”。parent 进入
  `snoozed`，生成保留 parent/child 关系的新 occurrence，主 Schedule 的 revision 和原时间未改变。
- child 在 13:06 到点只播报一次；真人说“`跳过这次`”，机器人答复“`已跳过这次提醒`”，
  child 最终进入 `skipped`。
- Android 详情页显示结构化时间、outcome、策略和 parent/child 关系，不显示原始 ASR。
- 网关断开期间产生的事件在 Android 重连后完成补拉；最终检查时 App cursor 与当时 projection
  最大序列一致。两个不同 occurrence 的升级各保留一个事件，没有 source retry 重复通知。

截图证据：

- [15 分钟未确认及完整时间线](phone-parent-unconfirmed.png)
- [parent 稍后提醒与 child 关系](phone-parent-snoozed.png)
- [child 到点后跳过](phone-child-skipped.png)

## 音频调整

- reSpeaker 左声道在进入唤醒词与云 ASR 前应用 3 倍有符号 16-bit 饱和增益；首个有效真人语音
  观测峰值约 `3600`、RMS 约 `295.7`，削波率 `0%`。真实语音结果链路通过。
- 硬件采集 mixer 已是 `60/60`、`0 dB`，因此没有继续提高硬件采集档位。
- 扬声器 `PCM` 从 `80%` 调至 `97%`（`58/60`、`-2 dB`），用户现场确认当前音量合适；
  产品语音入口已将 `97%` 固化为默认值，仍保留 `DUOLE_TTS_VOLUME_LEVEL` 覆盖能力。

## 补拉、清理与收尾

- 升级投影序列为 `1228` 和 `2781`，各自 source revision 均为 `1`；最后一次运行停止前
  projection 连续性为 `continuous`。
- 测试日程均通过正式 Schedule workflow 删除并进入 revision `2` tombstone：
  `schedule-b9de712010b54ac4b277988e2eed1b66`、
  `schedule-2855df97d48a47fcb00049148a96b2dc`、
  `schedule-9f33e63d898849788b07aebe8963d84c`。
- delivery ledger 中上述 occurrence 最终分别为 `completed`、`skipped`、`snoozed`，新 child 为
  `skipped`；待处理 occurrence 数为 `0`。
- Schedule DB、delivery ledger、projection DB 与 pairing DB 的 `quick_check` 均为 `ok`。
- Runtime 和 Gateway 已停止；`8444` 无监听，Runtime socket 无持有进程。板端 mixer 保持用户确认的
  `97%` 档位。

原始控制台日志包含真人 ASR 文本，配对记录包含认证材料，因此未复制到仓库。仓库只归档上述
结构化结论与不含凭据、原始 ASR 的 App 截图。
