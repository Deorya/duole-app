# PRD：多乐守护 App 与机器人端接入 V1

Status: needs-triage

Created: 2026-08-18

Product: 多乐守护（DUOLE Family）

Scope: Engineering V1 + Family Product 演进边界

## Problem Statement

DUOLE 机器人目前主要通过语音与老人交互，已经具备日程、设备状态、导航、安全、跌倒、
人员视觉和视觉隐私等领域能力，但家属无法通过一个安全、可信、低负担的移动端持续了解
机器人和照护现场，也无法远程管理日程、接收安全事件、发起音视频陪伴或执行有限控制。

从家属视角看，真正的问题不是“缺少一个遥控器”，而是缺少一条能够诚实回答以下问题的
可靠链路：现在有没有需要处理的事情、机器人当前能做什么、老人是否在画面中、日程是否
执行、远程操作是否被机器人接受，以及出现安全事件后怎样快速查看现场和联系老人。

从老人视角看，手机 App 不应增加机器人端操作负担。老人继续使用熟悉的语音交互；家属
打开现场、喊话或通话时，机器人应自动完成必要连接并持续给出可感知提示，同时尊重老人
在机器人本地设置的隐私关闭。

从工程交付视角看，当前还不存在可供 App 使用的 HTTP/WebSocket/WebRTC 接入层、设备身份
和配对系统、可补拉事件流、媒体网关或安全的手动遥控链。如果直接让手机进入 ROS 网络、
写日程数据库或发布底盘速度，会形成第二套业务真相和不可接受的运动风险；如果首版同时
建设公网账号、云通知、九方通话和全部家庭能力，又会推迟工程师获得第一款可操作 App。

因此需要同时明确两个层次：近期交付一款在受控局域网内连接真实机器人的 Android
Engineering V1；长期在同一产品模型上演进为面向单个家庭家属/主要照护者的 Family
Product。两者共享领域合同、安全原则和信息架构，但不把长期云端能力伪装成近期已交付。

## Solution

建设“多乐守护”移动 App 及机器人端可信接入边界。

Engineering V1 面向一批联调工程师，运行在机器人与 Android 手机处于同一受控局域网的
环境中。它提供设备发现与配对、真实状态和能力快照、事件与断线补拉、单手机实时画面和
环境音、互斥喊话、一对一通话、日程管理、房间导航、巡逻、回充、停止、受安全门保护的
手动遥控，以及脱敏工程诊断。Android APK 是首个验收目标；iOS 只保持架构可移植性。

Family Product 面向一户家庭中的家属和主要照护者。一户对应一台机器人和一位主要照护
对象，家庭成员人数不设上限，可有多位平权管理员。身份与功能权限分离，由管理员逐成员
配置。家庭产品在 Engineering V1 的稳定机器人合同上增加账号、公网安全接入、可靠通知、
短信兜底、多人观看和最多九端视频通话等能力，同时移除工程诊断入口。

地图能力按“多地图资料库 → 现场手动建图 → 地图语义配置 → 受监督自主建图”的顺序交付。
所有地图来自同一家庭、同一楼层和同一充电桩；App 只发送现场授权后的高层请求并展示地图
与任务结果，SLAM、探索、定位、速度安全、地图保存、评分、切换和回桩均由导航板执行。
手动建图先验证真实控制与地图闭环，自主建图随后复用同一地图资料库、充电桩锚点、停止链
和评分合同。

整体方案遵循以下产品原则：

- App 是机器人能力的可信接入层，不是新的机器人“大脑”。
- 状态必须诚实；“没有告警”不能表述为“老人一定平安”。
- 安全事件平时紧凑显示，发生时临时置顶，结束后恢复用户自定义首页布局。
- 日程、任务、安全、隐私和设备健康各自只有一个机器人端事实源。
- 本地隐私锁、安全抑制和急停优先于所有远程命令。
- 导航使用有状态任务，手动遥控使用短租约、持续按压和双 watchdog。
- 手动建图使用独立的现场授权和 mapping-scoped 控制租约；它不授予或提前开放普通远程遥控。
- 地图低分是体验提示而不是自动禁用；文件损坏、无法加载或无法满足技术合同才阻止启用。
- 断网、App 后台、媒体冻结或网关崩溃不得维持非零运动。
- 实时媒体默认不保存，并且每次远程连接都在机器人端持续可感知。
- 概率型安全信号由机器人端形成“观察中、需要关注、紧急事件”语义，App 不重算概率。
- 工程能力与家庭能力通过构建、路由和权限隔离，不依赖隐藏菜单。

## User Stories

### 连接、身份与版本

1. As an Engineering V1 engineer, I want to discover nearby DUOLE robots on the same LAN, so that I can connect without knowing ROS or the robot IP.
2. As an Engineering V1 engineer, I want to enter a robot IP and port manually, so that I can connect when multicast discovery is unavailable.
3. As an Engineering V1 engineer, I want to verify the robot's stable identity and fingerprint, so that a spoofed LAN device cannot impersonate the robot.
4. As an Engineering V1 engineer, I want to pair with a short-lived one-time code shown locally by the robot, so that remote enrollment requires physical access.
5. As an Engineering V1 engineer, I want my credential bound to this robot and this App installation, so that copying a token to another phone is insufficient.
6. As an Engineering V1 engineer, I want pairing attempts rate-limited and expired codes rejected, so that a nearby attacker cannot brute-force access.
7. As an Engineering V1 engineer, I want to see whether the robot is in `REAL` or `MOCK_NO_MOTION` mode, so that simulated results cannot be mistaken for real motion.
8. As an Engineering V1 engineer, I want incompatible API versions to disable write operations while preserving diagnostics, so that version drift fails safely.
9. As an Engineering V1 engineer, I want to revoke my current pairing, so that a lost or retired phone can no longer access the robot.
10. As an Engineering V1 administrator, I want to revoke another engineering client, so that access can be removed without resetting the whole robot.
11. As a paired user, I want revoked access to close REST, event, media and teleop sessions promptly, so that an existing connection cannot outlive authorization.
12. As a support engineer, I want to see App, gateway, media, robot runtime and interface versions, so that compatibility failures are diagnosable.

### 家庭、身份与权限

13. As a family administrator, I want to invite any number of family members, so that the product does not impose an artificial caregiver limit.
14. As a family administrator, I want any family member to be assignable as an administrator, so that care responsibility can be shared.
15. As a family administrator, I want multiple administrators to have equal standing, so that no hidden super-administrator becomes a single point of failure.
16. As a family administrator, I want the household to retain at least one administrator, so that the family cannot accidentally become unmanageable.
17. As a family administrator, I want to assign administrator, care-member or follow-member identity, so that the household has understandable role labels.
18. As a family administrator, I want functional permissions assigned independently of identity, so that a role name does not silently grant unrelated capabilities.
19. As a family administrator, I want to grant status, schedules, events, live viewing, talk, calls, robot jobs, teleop and stop separately, so that each member receives least privilege.
20. As a family administrator, I want administrators always to retain member and permission management, so that the household remains governable.
21. As a family member, I want an independent account rather than a shared family password, so that actions and revocation are attributable.
22. As a family administrator, I want high-risk household changes to require reauthentication, so that a stolen unlocked phone cannot unbind or delete the family.
23. As a family administrator, I want all administrators notified of high-risk household changes, so that silent account takeover is visible.
24. As a family member, I want high-risk operations recorded in an audit history, so that the family can understand who changed access or emergency contacts.

### 首页、状态与信息架构

25. As a family caregiver, I want the home page to answer whether anything needs attention, so that I can understand the situation at a glance.
26. As a family caregiver, I want the safety area compact when no event is active, so that a low-probability event does not occupy most of the screen permanently.
27. As a family caregiver, I want an active safety event temporarily pinned to the top, so that urgent information cannot be hidden by my layout.
28. As a family caregiver, I want my normal module order restored after an event closes, so that emergency presentation does not erase my preferences.
29. As a family caregiver, I want to reorder, show and hide home modules, so that the dashboard reflects what matters to my family.
30. As a family caregiver, I want to restore the default module layout, so that customization is reversible.
31. As a family caregiver, I want the wording “暂无需处理的安全事件” instead of “老人平安”, so that the App does not claim evidence it does not have.
32. As a family caregiver, I want monitoring availability, person visibility and data update time shown separately, so that I can distinguish silence from fresh evidence.
33. As a family caregiver, I want connection status and last successful synchronization visible, so that cached data is not mistaken for live data.
34. As a family caregiver, I want to see robot battery, network, microphone, camera, navigation and version state, so that I know which care capabilities are affected.
35. As a family caregiver, I want each state to include health, update time, stale status and a plain-language reason, so that a red or gray indicator is actionable.
36. As a family caregiver, I want `unknown`, `unavailable`, `disabled` and `degraded` represented differently, so that different failures are not flattened into one status.
37. As a family caregiver, I want to see current robot activity and active task, so that I know whether it is patrolling, navigating, docking or idle.
38. As a family caregiver, I want unavailable capabilities disabled with an explanation, so that buttons never imply unsupported behavior.
39. As a family caregiver, I want person-presence wording to say “检测到一人” rather than name the elder, so that vision uncertainty is not presented as identity.
40. As a family caregiver, I want the App not to build or display a daily movement history from person observations, so that routine monitoring does not become surveillance.
41. As an Engineering V1 engineer, I want a consistent snapshot with one sequence boundary, so that independently changing status sections do not produce a contradictory page.
42. As an Engineering V1 engineer, I want a force-refresh diagnostic operation to be bounded and rate-limited, so that a status screen cannot overload hardware probes.
43. As a family user, I want bottom navigation for Home, Live, Schedule, Robot and Me, so that the product remains predictable and task-oriented.

### 安全事件与通知

44. As a family caregiver, I want probability-based safety signals grouped as observing, attention and emergency, so that uncertainty is communicated without alarmist raw scores.
45. As a family caregiver, I want severity supplied by the robot workflow rather than recalculated by the App, so that every client reaches the same conclusion.
46. As a family caregiver, I want an event notification to open event details without automatically opening camera or audio, so that private media does not start unexpectedly.
47. As a family caregiver, I want event details to offer “查看现场”, so that I can assess the current situation when authorized.
48. As a family caregiver, I want event details to offer “拨打老人”, so that I can use the phone network when appropriate.
49. As a family caregiver, I want event details to offer “联系紧急联系人”, so that escalation remains available if the elder does not answer.
50. As a family caregiver, I want the App to avoid assignment, claiming and family group-chat workflows, so that family members can coordinate using ordinary phone calls.
51. As a family caregiver, I want repeated source messages deduplicated, so that one incident does not create several alarming cards.
52. As a family caregiver, I want fall events grouped by stable incident lifecycle, so that detection and recovery appear in one timeline.
53. As a family caregiver, I want closed incidents separated from active incidents, so that historical events do not look ongoing.
54. As a family caregiver, I want opening an incident recorded separately from resolution, so that “viewed” never implies the elder is safe.
55. As a family caregiver, I want events missed during a short disconnection pulled after reconnect, so that temporary Wi-Fi loss does not erase history.
56. As a family caregiver, I want duplicate and out-of-order events applied safely, so that reconnect does not duplicate cards or roll back terminal state.
57. As a family caregiver, I want a full resynchronization when the event cursor is too old or continuity is uncertain, so that the App never pretends a broken stream is complete.
58. As an Engineering V1 engineer, I want LAN event notifications only while the App connection is alive, so that V1 does not promise cloud delivery it cannot provide.
59. As a family caregiver, I want emergency events delivered through high-priority push, so that urgent incidents are noticeable outside the App.
60. As a family caregiver, I want an SMS fallback when no authorized contact opens an emergency within 60 seconds, so that push delivery failure has a second channel.
61. As a family member, I want to customize categories, sound, vibration, quiet hours and SMS fallback, so that notifications fit my responsibilities.
62. As a family administrator, I want at least one member to retain emergency notification, so that everyone cannot accidentally silence critical events.
63. As a family caregiver, I want persistent device faults that affect care to notify me, so that material loss of capability is not hidden.
64. As a family caregiver, I want transient faults and automatic recovery merged into records rather than repeatedly alerting, so that the App does not create notification fatigue.
65. As an Engineering V1 engineer, I want invalid or legacy fall messages to remain diagnostic-only, so that malformed input cannot create a false emergency.

### 实时画面、环境音、喊话与通话

66. As an authorized family caregiver, I want to open the robot camera remotely at any time permitted by current privacy policy, so that I can understand the scene without asking the elder to operate the robot.
67. As an authorized family caregiver, I want environmental audio to start with the live view, so that I immediately receive visual and audible context.
68. As the elder, I want every remote media connection to remain visibly or otherwise continuously perceptible on the robot, so that I know when family members can see or hear the room.
69. As the elder, I want a local privacy switch to end live media immediately, so that I retain physical control over observation.
70. As a family caregiver, I want the Live page to provide separate “按住喊话” and “开始通话” buttons, so that short announcements and sustained conversation are distinct actions.
71. As a family caregiver, I want push-to-talk to require continuous pressing, so that accidental background audio is not transmitted.
72. As a family caregiver, I want releasing, sliding out, backgrounding or disconnecting to mute and release talk immediately, so that a talk channel cannot remain stuck open.
73. As a family caregiver, I want push-to-talk to be mutually exclusive, so that two people cannot speak through the robot at once.
74. As a family caregiver, I want to see “某某正在喊话中” when another member holds talk, so that busy behavior is understandable.
75. As a family caregiver, I want talk ownership released automatically when the holder stops pressing, so that no takeover-request workflow is needed.
76. As a family caregiver, I want a call to connect without requiring the elder to operate the robot, so that limited mobility does not prevent communication.
77. As a family caregiver, I want a one-to-one full-duplex call in Engineering V1, so that the real speaker, microphone and echo path can be validated early.
78. As the elder, I want safety announcements to remain audible during talk or calls, so that remote audio cannot suppress urgent robot guidance.
79. As an Engineering V1 engineer, I want audio arbitration to restore wake, ASR, TTS and mixer state after normal or abnormal call exit, so that media does not break voice interaction.
80. As an Engineering V1 engineer, I want media to attach to the existing camera and microphone owners, so that App viewing does not disrupt fall detection or voice recognition.
81. As an Engineering V1 engineer, I want camera, microphone, encoder and network failures to return specific degraded states, so that a black screen is not shown as online.
82. As an Engineering V1 engineer, I want source-frame age and media quality exposed to the teleop safety gate, so that frozen video cannot authorize motion.
83. As a family caregiver, I want real-time media not recorded by default, so that remote presence does not become continuous surveillance.
84. As a family caregiver, I want no App-specific screenshot or recording feature, so that the product does not add unnecessary storage or privacy complexity.
85. As a family caregiver, I want the product to be honest that system-level screenshots and recording cannot be prevented, so that privacy claims remain accurate.
86. As a family member, I want to turn my own camera on or off in a future group call, so that I control whether my image is shared.
87. As a family member, I want my avatar displayed when my camera is off, so that participants remain identifiable without video.
88. As a family member, I want several authorized relatives to watch the robot stream concurrently in the Family Product, so that care is not limited to one viewer.
89. As a family member, I want up to nine call endpoints consisting of the robot and eight relatives, so that a family group can speak together.
90. As the elder, I want the robot screen to use two-up, four-grid or nine-grid layouts according to participant count, so that participants remain visible.
91. As a family member, I want group video to degrade to multi-party voice if the robot display path is unavailable, so that communication can continue without pretending video works.

### 手动遥控、停止与机器人任务

92. As an authorized operator, I want to enter manual teleop only when video, control, base watchdog and safety gates are healthy, so that I never drive blind or through an unsafe chain.
93. As an authorized operator, I want non-zero motion only while I continuously press the joystick, so that releasing my touch is the default stop action.
94. As an authorized operator, I want joystick displacement to control speed within a fixed safe range, so that fine motion is possible without increasing the robot limit.
95. As a safety owner, I want all real speed and acceleration limits enforced on the robot, so that a modified App cannot make the robot faster.
96. As an authorized operator, I want my control lease to exist only for the current press, so that ownership is released as soon as I let go.
97. As an authorized secondary operator, I want a clear busy response while someone else is pressing, so that concurrent control cannot merge inputs.
98. As an authorized secondary operator, I want control to become available naturally after release, so that there is no persistent ownership or takeover application.
99. As an authorized operator, I want App background, lock screen, incoming call, process death or network loss to stop the robot, so that phone lifecycle changes cannot maintain motion.
100. As an authorized operator, I want frozen or excessively delayed video to stop and lock teleop, so that stale visual feedback cannot guide movement.
101. As a safety owner, I want both the gateway and the navigation-board boundary to have independent watchdogs, so that one process failure cannot maintain motion.
102. As a safety owner, I want expired, duplicated, reordered, out-of-range and wrong-lease control packets rejected, so that network replay cannot prolong movement.
103. As a member with stop permission, I want to issue emergency stop without holding teleop control, so that safety intervention is never blocked by ownership.
104. As an operator, I want the App to show stop pending until the robot confirms stopping, so that sending a request is not mistaken for stationary wheels.
105. As a safety owner, I want touch release or connection loss to stop real wheels within one second, so that the existing system safety red line is preserved.
106. As a family caregiver, I want to send the robot to a verified room, so that I can position it without choosing arbitrary coordinates.
107. As a family caregiver, I want to start an immediate patrol with a bounded route and rounds, so that I can inspect approved areas.
108. As a family caregiver, I want to schedule automatic patrols, so that the family decides whether and how periodic inspection is used.
109. As a family caregiver, I want every scheduled patrol to recheck localization, map, battery, active task, privacy and safety gates, so that a schedule cannot bypass current conditions.
110. As a family caregiver, I want a skipped patrol to state a stable reason, so that refusal is understandable rather than shown as a generic failure.
111. As a family caregiver, I want to request docking after confirming its effect on the current task, so that the robot does not silently abandon work.
112. As a family caregiver, I want every navigation, patrol and docking request to return a stable job ID, so that I can follow progress after leaving the page.
113. As a family caregiver, I want jobs to show queued, accepted, running, succeeded, failed or canceled, so that transport success is distinct from robot completion.
114. As a family caregiver, I want to cancel supported jobs idempotently, so that retries do not create conflicting cancellation actions.
115. As a family caregiver, I want active jobs restored after App restart without resubmitting them, so that reconnect cannot duplicate movement.
116. As a family caregiver, I want safety events and local privacy to preempt remote motion, so that care and privacy outrank convenience.

### 地图、房间与巡逻路线

117. As a family caregiver, I want to see the current map, robot position, charging dock, rooms and active path, so that robot movement is understandable.
118. As a family caregiver, I want robot pose to include freshness, so that an old marker is not treated as a current location.
119. As a family caregiver, I want to rename a verified room for display, so that names match how the family refers to the home.
120. As a family caregiver, I want patrol points selected only from robot-verified candidates, so that a remote user cannot create unsafe arbitrary goals.
121. As a safety owner, I want the App unable to upload map files, move the charging dock, edit walls or change navigation parameters, so that high-risk mapping remains outside the family product.

### 日程与提醒

122. As an authorized family caregiver, I want to list the elder's schedules, so that I can understand upcoming reminders.
123. As an authorized family caregiver, I want to create a schedule without requiring the elder to approve it again, so that caregivers can manage agreed care routines remotely.
124. As an authorized family caregiver, I want to edit a schedule, so that changed plans are reflected on the robot.
125. As an authorized family caregiver, I want to delete a schedule, so that obsolete reminders stop.
126. As an authorized family caregiver, I want to enable or disable a schedule without deleting it, so that recurring routines can be paused safely.
127. As an authorized family caregiver, I want once, daily and weekly recurrence in V1, so that common care routines are supported without an over-complex rule engine.
128. As an authorized family caregiver, I want the household timezone used for execution, so that reminders occur at the elder's local time.
129. As a traveling caregiver, I want the robot's local time shown alongside my device context, so that timezone differences do not cause editing mistakes.
130. As an authorized family caregiver, I want optimistic revision checks on update and delete, so that App changes cannot silently overwrite newer voice changes.
131. As the elder, I want schedules created by voice and family to use the same data source, so that the robot and App never disagree.
132. As the elder, I want the robot to optionally announce that a family member changed a schedule, so that remote changes are transparent.
133. As a family caregiver, I want each reminder to specify whether elder confirmation is required, so that ordinary reminders need not create unnecessary escalation.
134. As the elder, I want confirmation outcomes of completed, snoozed and skipped, so that I can respond naturally to a reminder.
135. As a family caregiver, I want an unconfirmed state when no reliable response is received, so that silence is not recorded as completion.
136. As a family caregiver, I want the default confirmed-reminder policy to retry after five minutes and notify after fifteen minutes, so that a missed important reminder has a predictable path.
137. As a family caregiver, I want each reminder to override escalation with none, immediate or custom delay, so that importance can be configured per routine.
138. As a family caregiver, I want ordinary reminders not to escalate by default, so that low-risk schedules do not create alert fatigue.
139. As a family caregiver, I want schedule occurrence history to show delivery and outcome, so that I can distinguish planned from actually delivered reminders.
140. As a family caregiver, I want the App to receive only structured schedule results, so that the elder's raw recordings and unrelated conversation are not exposed.

### 视觉隐私与数据治理

141. As the elder, I want to disable visual monitoring locally, so that physical access always provides the strongest privacy control.
142. As the elder, I want a local privacy lock to survive robot restart, so that a reboot cannot silently reopen the camera.
143. As an authorized family caregiver, I want to request visual monitoring off remotely, so that I can reduce observation when appropriate.
144. As an authorized family caregiver, I want to request visual monitoring on only when no local lock blocks it, so that remote convenience cannot override the elder.
145. As the elder, I want remote clients unable to send a force parameter or impersonate a local source, so that the privacy hierarchy cannot be bypassed.
146. As a family caregiver, I want visual disable to end media and visual-driven motion before success is reported, so that UI confirmation corresponds to real effect.
147. As a family caregiver, I want prior safety event history retained when vision is disabled, so that privacy changes do not erase already-recorded incidents.
148. As a family caregiver, I want live media to have no default recording, so that observation is ephemeral.
149. As a family caregiver, I want device-state and media-connection records retained for 30 days by default, so that recent troubleshooting is possible without indefinite history.
150. As a family caregiver, I want schedule execution and structured safety records retained for 180 days by default, so that meaningful care history remains available.
151. As a family administrator, I want permission and high-risk audit records retained for one year by default, so that security changes remain accountable.
152. As a privacy owner, I want retention configurable and deletion behavior documented before Family Product release, so that policy and implementation remain aligned.

### 诊断、可靠性与体验质量

153. As an Engineering V1 engineer, I want every command to carry a stable request ID through gateway, domain, task and result, so that cross-layer failures are traceable.
154. As an Engineering V1 engineer, I want side-effect requests to use TTL and idempotency keys, so that retries do not duplicate tasks or schedule writes.
155. As an Engineering V1 engineer, I want unknown command outcomes queried rather than automatically resubmitted, so that reconnect cannot repeat a dangerous action.
156. As an Engineering V1 engineer, I want a redacted diagnostic export containing versions, modes, IDs, stages and stable error codes, so that issues can be reproduced without collecting private media.
157. As a privacy owner, I want diagnostics to exclude tokens, pairing codes, media, raw dialogue and unnecessary personal data, so that troubleshooting does not create a second privacy risk.
158. As an Engineering V1 engineer, I want liveness, readiness, capability and freshness represented separately, so that a running process is not mistaken for a working feature.
159. As an Engineering V1 engineer, I want a gateway restart to rebuild state without replaying old writes, so that service recovery is safe.
160. As an Engineering V1 engineer, I want slow event clients disconnected and able to replay later, so that one phone cannot block robot event processing.
161. As an Engineering V1 engineer, I want projection corruption or disk exhaustion to force resynchronization, so that broken continuity is not hidden.
162. As a safety owner, I want safety workflows to continue even when App projection fails, so that notification infrastructure cannot block robot-local response.
163. As a family user, I want large text up to 200 percent, so that the App remains usable with reduced vision.
164. As a family user, I want touch targets of at least 48 by 48 logical pixels, so that critical controls are easy to operate.
165. As a family user, I want critical meaning conveyed by text and icon as well as color, so that color vision does not determine safety comprehension.
166. As a family user, I want system dark mode generally supported, so that the App fits device preferences.
167. As a family user, I want live view and teleop to use a stable immersive dark presentation, so that video and controls remain legible.
168. As a family user, I want the visual design to feel quiet and trustworthy, so that routine monitoring does not create constant anxiety.
169. As a family user, I want red reserved for an active emergency, so that urgent meaning remains strong.
170. As an App engineer, I want business logic independent of Android-specific types, so that an iOS client can be added later without redesigning the domain.
171. As an App engineer, I want client models generated from frozen contracts, so that Windows and robot teams cannot silently diverge.
172. As a robot engineer, I want the App isolated from ROS topics, actions and QoS, so that internal robotics interfaces can evolve safely.
173. As a robot engineer, I want the gateway unable to write the schedule database directly, so that voice and App share one guarded schedule domain.
174. As a robot engineer, I want media consumers unable to open a second camera or microphone owner, so that core perception and voice remain stable.
175. As a robot engineer, I want manual teleop unable to publish directly to the base velocity topic, so that lease, clamp, collision and watchdog controls cannot be bypassed.

### 地图建立、多地图管理与现场配置

176. As a family user, I want the manual and autonomous mapping buttons always discoverable and able to guide me through unmet prerequisites, so that unavailable conditions do not hide the feature.
177. As a family user, I want several robot-generated maps with stable IDs and unique editable names, so that I can compare attempts without overwriting an existing map.
178. As a family user, I want an overall map score with coverage, consistency, localizability and navigability details, so that I can choose a map while still being allowed to use a technically valid low-score result.
179. As a family user, I want deleted maps and their associated configuration recoverable for a duration I choose, including indefinite retention, so that accidental deletion is reversible.
180. As a family user, I want map count governed by available storage rather than an arbitrary fixed limit, so that I can keep useful attempts while understanding what blocks a new build.
181. As a safety owner, I want map switching accepted only while the robot is stationary and charging at the shared dock, with automatic rollback on load or localization failure, so that a failed switch cannot strand navigation between maps.
182. As a family user, I want robot restart to restore only the map I explicitly activated and only after dock-anchor localization succeeds, so that restart cannot select an unexpected map.
183. As a privacy owner, I want raw maps and thumbnails kept on the robot and unavailable to ordinary diagnostics, import or export, so that the household floor plan does not spread through unmanaged files.
184. As a family user, I want rooms, keepout zones, patrol routes and the dock anchor bound to one map ID, so that coordinates from different mapping attempts cannot be mixed.
185. As a family administrator, I want map writes protected by `maps.manage` and physical-presence rules appropriate to their risk, so that remote convenience cannot silently change future robot motion.
186. As a family user, I want other phones to see only that mapping is busy while the active operator retains the mapping session, without weakening the independent global stop permission.

### 现场手动建图

187. As an authorized onsite user, I want each mapping start authorized by a short-lived dynamic QR code shown by the robot, so that a remote account cannot start physical mapping motion.
188. As an onsite user, I want manual mapping to start from a charging, stationary robot with at least 50 percent battery and healthy sensors, storage, collision protection and stop boundaries, so that the session begins from a trusted dock anchor.
189. As an onsite user, I want a press-and-hold analog joystick with symmetric forward/reverse and left/right limits, so that I can drive precisely while release always stops motion.
190. As a safety owner, I want manual mapping to use a mapping-scoped TeleopGuard, independent gateway/base watchdogs and the final collision path without enabling ordinary teleop, so that the first App-controlled wheels remain narrowly bounded.
191. As an onsite user, I want the mapping page to show the incremental map, robot pose, explored area, battery, phase and elapsed time without requiring live video or a misleading exact percentage, so that I can supervise the map directly.
192. As an onsite user, I want up to 30 minutes to collect a manual map and a separate five-minute manual docking phase, so that the robot can finish at the same physical anchor where it started.
193. As a safety owner, I want link loss to stop real wheels within one second, allow at most three seconds for a stationary reconnect and then end the session, so that a disconnected phone cannot maintain control.
194. As an onsite user, I want normal dock-verified completion, unverified save, immediate stop and abandon to have distinct outcomes, so that stopping motion never ambiguously deletes or approves a map.
195. As an onsite user, I want an atomic crash snapshot saved as an interrupted map without restoring an old control lease, so that a process failure preserves useful evidence but cannot resume motion.

### 地图语义与受监督自主建图

196. As an onsite map manager, I want to mark a rough room center and have the navigation board derive and validate a safe target region, so that I do not need to draw polygons or write coordinates.
197. As an onsite map manager, I want patrol routes composed from ordered verified rooms, so that a route cannot contain arbitrary unvalidated points.
198. As an onsite map manager, I want to add, modify and remove map-specific keepout zones while wall geometry and navigation parameters remain closed, so that household restrictions are explicit without exposing low-level tuning.
199. As an onsite map manager, I want one QR verification to create a 15-minute map-management presence session, so that several room, route or keepout edits do not require repeated scans.
200. As an authorized onsite user, I want autonomous mapping to record the dock anchor, leave the dock automatically and explore under navigation-board control, so that the App never implements SLAM or velocity output.
201. As a safety owner, I want autonomous mapping supervised in the foreground, isolated from every other motion owner and limited by a fixed low-speed profile, so that it cannot become unattended or parameterized remote roaming.
202. As an onsite user, I want autonomous exploration to finish when frontiers are exhausted or after at most ten minutes, while allowing an early save but no pause, resume or guided target selection, so that the first workflow remains bounded.
203. As an onsite user, I want a completed autonomous map saved and scored before one automatic docking attempt, with clear manual-recovery guidance if docking fails, so that failure does not erase the map or trigger endless retries.
204. As a safety owner, I want App backgrounding, a connection loss over three seconds, critical BMS state, hardware failure or process crash to stop exploration and preserve the last readable snapshot without resuming it, so that supervision and failure semantics are deterministic.
205. As a family user, I want every new map left inactive until I explicitly activate it at the dock, so that a build attempt never silently replaces the map used for normal navigation.

## Implementation Decisions

### Product and release structure

- The product is named “多乐守护”, with “DUOLE Family” as the English identifier.
- The product has two explicit layers: Engineering V1 for controlled LAN integration and Family Product for household use over a future secure remote path.
- Engineering V1 targets an Android APK built by the Windows team. iOS compatibility is preserved in architecture but is not an Engineering V1 acceptance target.
- Engineering V1 supports one robot and one phone for media. Family Product extends the same session model to concurrent viewing and at most nine call endpoints.
- The robot continues to be the elder's primary interface. The App is optimized for family members, caregivers and engineering users.
- Engineering and family builds share a codebase but use separate build capabilities. Engineering diagnostics are removed at compile/router level from the family build.

### Household and permission model

- A household contains one robot, one primary care recipient and an unbounded set of family members.
- Administrator, care-member and follow-member remain understandable identity labels, but feature authorization is independent from identity.
- All members may be administrators; administrator count has no upper bound and administrators are peers.
- Administrators always retain member and permission management; at least one administrator must remain.
- High-risk household changes require reauthentication, all-administrator notification and an audit record.
- Family Product emergency notification settings remain customizable per member, while at least one member must retain emergency delivery.

### App information architecture

- Primary navigation is Home, Live, Schedule, Robot and Me.
- Home modules are reorderable, hideable and resettable.
- The inactive safety module is compact. An active event overrides layout temporarily and is pinned above user modules.
- Safety language reports evidence and freshness without claiming the elder is safe.
- The App never labels a detected person as the care recipient unless a future identity capability is explicitly introduced and accepted.

### Deep modules

- `ConnectionIdentity` encapsulates mDNS candidate discovery, manual addressing, robot identity verification, pairing, token lifecycle and revocation behind a small connection/session interface.
- `AuthorizationPolicy` converts authenticated installations into canonical actors and fine-grained scopes. Display names are presentation data, not authorization keys.
- `AppGatewayDomainFacade` is assembled inside the formal robot runtime and exposes transport-neutral queries and commands over the exact existing domain object graph.
- `CapabilityStateProjection` produces a consistent snapshot from robot-owned facts, including explicit freshness and unavailable reasons.
- `EventProjectionOutbox` assigns stable event IDs and monotonic robot-local sequence numbers, maintains bounded replay and provides snapshot/resynchronization semantics without becoming a business fact owner.
- `JobGateway` maps App jobs to the shared whole-robot task coordinator and formal navigation adapters while preserving stable job, command and goal identities.
- `ScheduleApplicationV2` owns versioned schedule CRUD, enable/disable, recurrence, confirmation policy and occurrence outcomes for both voice and App consumers.
- `VisualPrivacyAdapter` maps canonical App commands to the existing visual monitoring policy while preserving local-lock priority and stop ordering.
- `MediaCoordinator` owns media authorization, session state, robot notice and quality; `AudioModeArbiter` encapsulates environment listening, push-to-talk, full-duplex call, safety override and voice restoration.
- `TeleopControl` owns session, press-scoped lease, sequence/TTL validation and gate state; a navigation-board `TeleopGuard` independently owns robot-side clamps, velocity arbitration and the base watchdog.
- `MapCatalog` owns stable map identity, display names, quality, active selection, map-bound semantic references, capacity and recoverable deletion without exposing raw filesystem paths.
- `MappingControl` owns manual/autonomous mapping jobs, dock-anchor preflight, onsite authorization, incremental map projection and terminal result semantics while delegating SLAM, exploration and localization to the navigation board.
- `DiagnosticsProjection` exposes bounded, redacted versions, request correlations, health and performance summaries without exporting raw internals.

### Robot-side architecture

- The public gateway is a network process responsible for TLS, authentication, request policy, external REST/WebSocket mapping and replay delivery.
- The formal robot runtime creates a single domain facade that reuses the same device-status service, schedule application, whole-robot task coordinator and visual-monitoring service as voice interaction.
- Public gateway and in-runtime facade communicate through an owner-only local IPC boundary with peer credentials, framed messages, size limits, schema version and deadlines.
- The gateway never instantiates a second whole-robot task coordinator, builds a parallel device-status cache or owns a separate schedule database.
- The App event projection is a delivery/read model. Safety, schedules, tasks, privacy and device health remain owned by their existing domains.
- The unique product runtime entry supervises gateway, media and facade lifecycles. Independent manually started services are not accepted as production deployment.
- Failure of App services may leave local voice and safety workflows operational, but App capability and freshness must become unavailable rather than stale-green.

### External contracts

- Low-frequency queries and commands use versioned HTTPS REST; events, media signaling and teleop use authenticated WSS; media uses encrypted WebRTC.
- mDNS is discovery-only and cannot establish trust. Manual IP uses the same TLS and identity checks.
- Every write carries a request ID, canonical actor, sent time, TTL and idempotency key. Versioned resources use optimistic revision checks.
- Accepted asynchronous work returns an operation or job identity. Transport acceptance is never presented as robot completion.
- Unknown enum values map to unknown and disable unsafe writes rather than being coerced to a known safe state.
- External OpenAPI, event schemas, media signaling schemas, teleop schemas, capability keys and error codes are jointly frozen before independent client/server implementation proceeds.

### State and event consistency

- A snapshot has one high-water sequence. The App starts event consumption after that sequence.
- A single projection writer assigns sequence numbers and transactionally updates events and affected read models.
- Source retry deduplication uses stable source identity and revision. Sequence order represents publication order, not necessarily physical occurrence time.
- Reconnect replays from the last successfully applied sequence. Cursor expiry, a detected gap or projection corruption requires a full snapshot.
- App clients never automatically repeat a write whose outcome is unknown; they query by idempotency/request/operation identity.
- Invalid fall input remains diagnostic-only and cannot enter the active incident workflow.

### Schedule model

- Schedule fields become first-class domain values: kind, title, enabled, timezone, start, recurrence, confirmation policy, typed payload, revision, actor and timestamps.
- Engineering V1 recurrence supports once, daily and weekly. More complex rules are advertised only after real domain support exists.
- App and voice use the same versioned application use cases and formal persistence.
- Update, enable, disable and delete use compare-and-swap revision semantics; conflicting edits return the current revision rather than silently overwriting.
- Confirmation outcomes include delivered, completed, snoozed, skipped, unconfirmed and delivery failure as appropriate.
- Scheduled patrol is represented as a schedule kind but only creates a task intent at due time; current robot safety and capability gates still decide execution.

### Navigation, stop and teleop

- Room navigation, immediate patrol and docking are product jobs with stable lifecycle and a restricted target whitelist.
- Arbitrary coordinates, arbitrary ROS actions and low-level navigation parameters are not exposed to ordinary App clients.
- Maps belong to one household floor and one physical charging dock. Switching is transactional, occurs only while charging and commits only after navigation-board localization succeeds.
- Manual mapping uses a separate onsite `manual_mapping` owner and mapping-scoped TeleopGuard without media. Its successful REAL acceptance does not make ordinary `teleop.available` true.
- Autonomous mapping uses an onsite `autonomous_mapping` owner; the navigation board alone starts SLAM/exploration, applies fixed low-speed safety and saves or scores maps.
- Manual mapping is delivered before autonomous mapping so the latter reuses an accepted map catalog, dock anchor, stop path and real-wheel boundary.
- Manual teleop acquires exclusive motion only for one continuous joystick press. Releasing confirms stop before a new lease is granted.
- Concurrent teleop returns busy; no takeover-request or persistent controller ownership exists.
- App control values are normalized. Real speed, acceleration and collision constraints remain on the robot.
- Gateway and navigation-board watchdogs are independent. Either timeout forces zero and revocation.
- Video freshness is a server-side gate. A candidate 800 ms latency limit and 300–500 ms lease require HIL measurement before freezing.
- Independent emergency stop does not require a teleop lease and remains idempotent and high priority.
- The system-level requirement from touch release or link loss to real wheel stop remains no more than one second.

### Media and audio

- Opening live view starts robot video and environment audio together when both are available.
- Media attaches to the existing camera and microphone owners; no second hardware capture path is allowed.
- A persistent robot-side indicator is activated before media becomes consumable. Failure to provide an approved persistent indication blocks a new media session.
- Push-to-talk and call are separate actions. PTT uses a renewable exclusive lease and locally mutes before release completes.
- Engineering V1 call is one-to-one full duplex. Audio focus, echo cancellation, ASR/TTS suppression and restoration are explicit states.
- Safety audio can preempt or duck remote playback and reports the reason to the App.
- Real-time media is not recorded by default. Diagnostics contain only bounded quality summaries.
- Family Product can extend session participants, cameras, avatars and robot layouts without changing robot-local privacy priority.

### Security and privacy

- Robot identity uses a stable random robot ID and device key fingerprint; IP, MAC address and mDNS names are not identity.
- Pairing requires a locally initiated short-lived session, fingerprint verification, rate limiting and one-time code consumption.
- Access credentials are high-entropy, stored hashed on the robot and protected by Android secure storage on the phone; refresh is bound to an installation key.
- Token or session revocation cascades to event, media, PTT, call and teleop sessions.
- The public gateway uses least OS privilege and does not own camera, microphone, base or schedule database access.
- App visual commands always have canonical source `app`; clients cannot impersonate local voice/UI or use a force override.
- Local privacy disable persists across restart, closes media and visual-driven motion, and cannot erase existing event history.
- Engineering diagnostics are allowlisted and exclude credentials, pairing codes, media, raw dialogue, full environment dumps and private database content.

### Notification and retention

- Engineering V1 provides best-effort local notification only while the LAN App/event channel is alive.
- Family Product adds reliable high-priority push and a 60-second unopened-emergency SMS fallback.
- Device faults notify only when persistent and care-affecting; transient faults and recovery are grouped.
- Default structured retention is 30 days for device/media connection records, 180 days for schedule executions and safety events, and one year for permission/high-risk audits.
- Event replay retention and long-term product record retention are separate policies and must not be conflated.

## Testing Decisions

- Good tests assert externally visible behavior, stable contracts, safety outcomes and persisted state transitions. They do not assert private helper calls, thread names, framework internals or incidental implementation structure.
- All listed deep modules are tested in isolation through their public interfaces. Media, privacy, jobs and teleop additionally receive cross-process and hardware-in-the-loop coverage.
- Contract tests validate OpenAPI, event, media and teleop examples, generated Python/Dart models, unknown fields, unknown event types and incompatible versions.
- `ConnectionIdentity` tests cover spoofed discovery, fingerprint mismatch, wrong/expired/reused codes, rate limits, installation binding, refresh and cascading revocation.
- `AuthorizationPolicy` tests cover every scope independently, actor canonicalization, expired requests, replay, idempotency conflict and the rule that display names do not authorize.
- `AppGatewayDomainFacade` tests prove injected existing services are reused and that a second task coordinator, schedule store or device-status provider graph is never created.
- Local IPC tests cover owner/mode/symlink checks, peer credentials, oversized/deep/malformed frames, protocol versions, deadlines, slow clients and clean shutdown.
- `CapabilityStateProjection` tests cover consistent snapshot sequence, provider timeout isolation, stale transitions and distinct unknown/unavailable/degraded/disabled semantics.
- `EventProjectionOutbox` tests cover concurrent duplicate source events, monotonic sequence, atomic event/read-model commits, snapshot/replay barriers, cursor expiry, gaps, corruption, retention and slow WebSocket consumers.
- Incident tests cover valid fall lifecycle, recovery revisions, invalid fall isolation, observing/attention/emergency mapping and the distinction between viewed and resolved.
- `ScheduleApplicationV2` tests cover migration, versioned CRUD, App/voice concurrent conflict, enable/disable, timezone and DST, once/daily/weekly recurrence, confirmation outcomes, reminder retry and scheduled-patrol gating.
- `JobGateway` tests cover idempotent creation, target whitelist, motion-owner conflict, stale/external runtime, command/status correlation, stale result rejection, cancel, restart recovery and terminal-state monotonicity.
- `VisualPrivacyAdapter` tests extend existing privacy coverage with canonical App source, actor/time validation, duplicate correlation, concurrent serialization, local-lock rejection and media/teleop revocation.
- `MediaCoordinator` tests cover source ownership, authorization, persistent indication, session lifecycle, track degradation, privacy cutoff and the guarantee that cached frames are not available after disable.
- `AudioModeArbiter` tests cover environment listening, PTT lease, busy response, full-duplex mode, safety override, echo-trigger prevention and restoration after normal exit, network loss and process failure.
- `TeleopControl` tests cover press-scoped epochs, sequence and TTL, duplicate/out-of-order/NaN/range/rate rejection, concurrent clients, every App lifecycle stop trigger and video freshness changes.
- `TeleopGuard` HIL tests cover gateway loss, AP loss, half-open transport, gateway/media/navigation-board restart, robot-only clamps, collision path and default unarmed-zero behavior.
- `MapCatalog` tests cover stable identity, unique naming, low-score usability, corrupt-map rejection, active-map deletion rules, configurable/infinite trash retention, capacity reservation, atomic restore and path traversal.
- Manual-mapping contract/SIM tests cover dynamic onsite authorization, preflight guidance, mapping-scoped leases, symmetric analog intent, release/connection stops, incremental maps and every save/discard outcome without real wheel output.
- Manual-mapping HIL/REAL tests cover a charging-dock start, real SLAM, fixed TeleopGuard profile, collision overrides, 30-minute collection, five-minute manual return, BMS completion and every one-second stop trigger.
- Autonomous-mapping HIL/REAL tests cover automatic undock, fixed low-speed exploration, ten-minute maximum, foreground/link-loss termination, snapshots, scoring, one docking attempt and explicit activation.
- Map-semantics tests cover navigation-board room correction, map-bound keepouts, verified-room routes, presence-session expiry, revision conflicts and isolation across map switches.
- Real-motion acceptance starts on a lifted-wheel or isolated rig, then moves to a cleared low-speed area with reachable hardware emergency stop. Every stop trigger is measured from phone/fault onset to actual wheel stop; the worst result must be no more than one second.
- Media HIL acceptance proves one camera/microphone owner, 30-minute stability, first-frame and latency targets, CPU/memory/temperature bounds, real acoustic echo cancellation and no regression to fall detection or voice interaction.
- Security acceptance includes packet capture, token/secret scanning, malformed-input fuzzing, resource limits and the inability of a compromised App request to raise speed or override local privacy.
- Accessibility tests cover 200 percent text scaling, 48-by-48 touch targets, non-color-only meaning, screen sizes and lifecycle behavior during live/teleop pages.
- Long-running tests cover gateway/projection/media resource growth, log rotation, disk pressure, network churn and restart without duplicate writes.
- Existing codebase prior art includes fault-isolated device-status provider tests, product runtime composition tests, task-coordinator stale-status and inhibitor tests, visual privacy lock and idempotency tests, schedule SQLite/guard/backup tests, event adapter validation and TTS priority/preemption tests.
- Evidence is classified as SCHEMA, SIM, HIL or REAL. Mock evidence can validate UI and orchestration but cannot close media ownership, real navigation or real wheel-stop requirements.
- A release record captures App, gateway, media, runtime, navigation-board, schema and hardware versions together with phone, router, test IDs and redacted evidence.

## Out of Scope

- Institution operations, fleet management, call-center workbench and developer diagnostics inside the Family Product UI.
- Public-internet connectivity, cloud accounts, cloud notification and SMS implementation in Engineering V1.
- Family Product account backend, secure relay and multi-party SFU implementation in the first LAN engineering delivery.
- iOS build, signing and real-device acceptance in Engineering V1; architecture compatibility remains required.
- More than one robot or more than one primary care recipient per household.
- Reliable visual identity recognition of the elder or attribution of observations to a named person.
- Medical diagnosis, vital-sign monitoring, health consultation or medication compliance claims.
- Family text chat, voice messages, care-task assignment, incident claiming or in-App family coordination.
- Continuous RGB/depth recording, event video history, App-native screenshot/record controls or claims that system recording can be blocked.
- Advertising, membership, subscriptions, marketplace or payment functions.
- Arbitrary pose navigation, “find person” motion, unrestricted ROS topic/action access or developer parameter consoles in the normal App.
- Manual wall geometry editing, App-selected charging-dock relocation, map import/export/upload, multi-floor maps or low-level navigation tuning.
- Automatic motion from the current person-presence shadow capability until that independent product gate is accepted.
- A teleop implementation that directly publishes base velocity, relies only on the phone watchdog or lacks real-wheel evidence.
- A parallel App schedule database, a parallel task coordinator or any App-side recomputation of safety probability.
- Full remote family release before legal/privacy, security, long-term notification and operations reviews are complete.

## Implementation Grouping and Delivery Waves

> *This was generated by AI during triage.*

Updated: 2026-08-24

本节是 Issue 04–35 的实施分组与交付顺序记录。Epic 只用于归属、排期和 owner 协调，不合并
现有工单，也不替代各工单自己的依赖、验收条件和证据。Issue 01–06 已完成正式验收；下表
保留 04–29 原始分组并加入 30–35，不能把 04–06 重新计入待开发范围。

### Epic 分组

| Epic | Issues | 数量 | 主要边界 |
| --- | --- | ---: | --- |
| 基础信任与状态同步 | 04–06 | 3 | 配对与撤销、能力快照、持久事件与重同步 |
| 安全事件与首页 | 07–08 | 2 | 安全事故时间线、局域网通知、首页动态置顶 |
| 视觉隐私与音视频 | 09、18–20 | 4 | 隐私控制、实时视听、喊话、一对一通话 |
| 日程管理 | 10–12 | 3 | 日程读取、版本化 CRUD、提醒确认与升级结果 |
| 地图、导航与遥控安全 | 13–17、21–22、30–35 | 13 | 多地图、先手动后自主建图、地图语义、停止、导航/巡逻 Job、TeleopGuard |
| 诊断与 Engineering V1 发布 | 23–24 | 2 | 脱敏诊断、跨层追踪、集成与发布验收 |
| Family Product | 25–29 | 5 | 家庭账号权限、公网通知、多人通话、隐私发布 |
| **合计** | **04–35** | **32** | Engineering V1 27 条，Family Product 5 条 |

### 交付波次

1. **基础关键链：** `04 → 05 → 06`，已于 2026-08-24 正式验收完成。
2. **第一并行波：** 完成 Issue 06 后，并行推进 `07、09、10、13、14、23`。
3. **地图与建图关键链：** `13 → 30`，再由 `04 + 06 + 14 + 30 → 31 → 32 → 33 → 34 → 35`；
   先验收无运动合同，再开放真实手动建图，最后复用同一边界交付自主建图。
4. **地图导航能力：** `35 → 15 → 16`；Issue 17 仍需同时满足 Issue 11 和 Issue 16。
5. **其余并行能力：** 在各自前置项关闭后推进 `08、11、12、18–22`；Issue 33 的
   mapping-scoped TeleopGuard 不替代 Issue 21–22 的媒体联锁普通遥控验收。
6. **Engineering V1 发布门：** Issue 24 汇总所有 Engineering V1 能力的正式生命周期、长稳、
   无障碍和 APK 验收；它不是普通功能开发工单。
7. **Family Product 独立阶段：** `25 → 26 → 27 → 28 → 29`，不得混入 Engineering V1
   发布范围或用 LAN 工程版证据替代家庭产品验收。

### 执行约束

- 分组与波次是两个维度：同一 Epic 内的工单可以跨波次，不得绕过工单自己的 `Blocked by`。
- 每个 Issue 继续作为最小独立开发和验收单元，代码、测试和证据回写对应 Issue。
- Issue 04–06 的已列前置项和验收均已关闭；后续工单在其余依赖满足且 Agent Brief 完整后
  再转为 `ready-for-agent` 或 `ready-for-human`。
- App、Gateway、Runtime、Schedule、Media/Audio、Navigation/Motion Safety、Privacy/Security
  和 QA owner 应按 Epic 明确，但实现仍采用客户端到机器人事实源的纵向切片。
- 任何涉及真实运动、网络暴露、正式数据迁移或系统服务安装的波次，仍需对应实施评审与操作
  批准；本分组不构成这些动作的授权。

## Further Notes

- The Engineering V1 App gateway, device identity, pairing/installation proof,
  capability snapshot, and persistent event replay for Issues 01–06 are
  implemented and physically accepted. Media, teleop, family accounts, and
  later write slices remain outside that completed boundary.
- The App v1/compatible 1.2 contract used by Issues 01–06 is frozen. Later issue
  contracts still require their own review before client and gateway teams
  implement them independently.
- The real Android-to-TLS-to-local-IPC-to-runtime Device Status tracer bullet is
  complete; static success JSON was not used as acceptance evidence.
- Media, audio write paths, teleop, and schedule migration still require their
  issue-specific spikes and frozen contracts. Device identity and event
  persistence no longer belong in that pending list.
- Ordinary media-gated teleop remains the last general control capability enabled. Issue 33 may enable only the onsite mapping-scoped control after its own one-second stop gate; it cannot make `teleop.available` true.
- The product visual tone is “安静可信，不制造焦虑；真正需要家属时绝不含糊”. Warm white, deep pine green and restrained semantic colors are preferred; red is reserved for an active emergency.
- The full detailed handoff remains split between a Windows App package and a robot-side gateway package. This PRD is the tracker-level source for triage and scope; detailed designs remain supporting material rather than alternative product truth.
- Triage should assign explicit owners for App, gateway, runtime composition, Schedule, media/audio, navigation safety, privacy/security and QA before implementation issues are cut.
- No product decision in this PRD authorizes installing system services, enabling real movement, changing network exposure or migrating formal schedule data without the corresponding implementation review and operator approval.
