# 实现一次性配对、安装实例绑定与撤销

Status: ready-for-human

Implementation: complete-2026-08-23

Acceptance: accepted-2026-08-24

Type: AFK

User stories covered: 4–11

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

交付完整的 Engineering V1 本地身份闭环：机器人本地创建短期配对 session，Android 在核对
设备指纹后用一次性 code 和 installation public key 换取最小权限会话，随后可以刷新、查询和
撤销；撤销会关闭该客户端派生的事件、媒体和遥控连接。

## Acceptance criteria

- [x] 配对 session 只能通过机器人本地受控动作创建，并显示 session、短期 code、指纹和过期时间。
- [x] code 一次性消费、短时有效、严格限速；错误、过期、已用和并发兑换返回稳定错误。
- [x] Android 在安全存储中生成/保存 installation key 与访问凭据，源码、普通偏好、日志和崩溃报告均无 secret。
- [x] 服务端只保存访问 secret 的强 hash，并将会话绑定 robot、installation public key、scope、auth revision 和 expiry。
- [x] 会话刷新需要 installation 持有证明；复制 token 到另一安装实例不能续期或执行写操作。
- [x] 当前会话和已配对客户端列表只返回必要的掩码身份、scope、过期时间和最后活动信息。
- [x] 撤销当前或指定客户端后，其 REST、Events WS、媒体、PTT、通话和 teleop 派生会话及时失效。
- [x] 撤销 teleop 客户端会触发停止方向；撤销不会删除其已创建的非运动日程业务数据。
- [x] 包含 code 暴力尝试、token 重放、installation 复制、auth cache 延迟和日志 secret scan 测试。
- [x] App 可独立演示从未配对、配对成功、刷新到撤销后重新需要配对的完整流程。

## Blocked by

- [03 实现局域网发现、手动 IP 与设备指纹验证](03-lan-discovery-device-identity.md)

## Comments

### 2026-08-23 implementation evidence

- 已交付机器人本地一次性配对 CLI、SQLite 会话存储、P-256 challenge/refresh、
  installation command proof、凭据轮换、当前/指定客户端撤销和派生会话协调器。
- Android Keystore 只在原生侧持有 installation private key；凭据加密保存，Dart
  只请求 public key 或签名。App 已覆盖服务端验证恢复、刷新、主动撤销和事件撤销回配对页。
- 共享 04–06 软件门为 141 passed、1 个条件性 skipped；合同生成/fixtures 全绿，
  26 个 Dart 入口、24 个 Flutter 测试、Dart/Flutter analyze 和 Android 离线
  `compileDebugKotlin` 全部通过。
- 完整信任边界、操作命令、自动化证据和实机剩余项见
  `docs/interface_freeze/app_v1/issue_04_pairing_session_revocation.md`。

### Human acceptance boundary

- 在目标 Android/机器人上验证 Keystore 重启保持、第二安装实例复制 token 失败、真实
  refresh/revoke，以及真实媒体/teleop 后续接入同一协调器后的停机与连接关闭顺序。
- 本次没有修改板端或主机网络配置；测试只对单个 Flutter 进程设置 localhost 直连。

### 2026-08-24 Physical Android/robot acceptance

- 最终 APK 通过无线 ADB 安装到 OnePlus PHK110，并针对真实
  `172.22.205.44:8443` Gateway 完成一次性安全配对、刷新与撤销闭环。
- Android Keystore 绑定凭据在 App 进程重启和手机整机重启后均恢复同一
  device session；不需要重新确认 TLS 指纹或输入配对码。
- 真实 HIL 验证一次性 code 重用返回 `PAIRING_CODE_USED`，复制凭据在另一
  installation 上刷新返回 `INSTALLATION_PROOF_INVALID`，原 installation 仍可正常读取。
- 正式 Gateway 撤销当前选中的手机会话后，打开的机器人状态子页无需 Back 即自动退回
  安全配对页并显示 `session_revoked`。
- App 专属 `logcat` 与板端正式服务日志的 secret scan 均为零命中；证据、最终 APK
  哈希和测试矩阵见 `docs/evidence/app_gateway/20260824/README.md`。
- 为保留用户数据，本次未执行破坏性的 `pm clear`；包数据移除后的密钥不可用行为由
  Android package-scoped Keystore/存储自动化覆盖。尚未交付的真实 media/teleop slice
  将复用已验收的 `DerivedSessionCoordinator`，不属于本 Issue 当前实机闭环。

Issue 04 的当前交付范围已正式验收完成。
