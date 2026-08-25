# 实现安全远程接入、可靠推送与短信兜底

Status: needs-triage

Type: HITL

User stories covered: 58–64

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

把 Engineering V1 的局域网事件与机器人 API 安全地扩展到公网家庭场景：通过受认证远程
relay/proxy 建立设备连接和事件投递，向有权限成员发送可靠高优先级 push；若紧急事故在
60 秒内没有任何授权联系人打开详情，则按家庭策略发送短信兜底。App 不承担家属协调或事故
认领。

## Acceptance criteria

- [ ] 远程路径不直接暴露机器人 LAN listener/DDS，使用设备主动建立或经批准的安全 relay 与双向身份。
- [ ] 云端账号、家庭授权、robot identity 和本地 safety/privacy gates 在每次请求中完整校验。
- [ ] 远程请求保留 request/idempotency/job/event identity，断线和重连不重复执行机器人写动作。
- [ ] active emergency 生成高优先级 push；observing/attention 和设备故障遵守各自通知等级。
- [ ] 60 秒计时基于任何授权联系人成功打开事故详情，而不是 push provider 的 delivered/open 猜测。
- [ ] 到期仍无人打开时向配置成员发送短信；push 与 SMS 各自记录 requested/delivered/failed，不互相阻塞。
- [ ] 每位成员可配置类别、声音、振动、免打扰和短信兜底，但家庭约束保证至少一位紧急接收者。
- [ ] 持久 care-affecting device fault 可主动通知；短暂故障和自动恢复合并，避免告警风暴。
- [ ] App 点击 push/SMS deep link 先进入认证后的事故详情，不自动打开现场音视频。
- [ ] 重复事件、provider retry、成员权限变化、手机号变化、跨时区和计时服务重启保持幂等。
- [ ] 云端不存储不必要媒体或原始机器人对话；通知 payload 使用最小个人信息。
- [ ] 完成 relay threat model、provider privacy/legal review、离线/故障注入和端到端手机网络验收。

## Blocked by

- [07 实现安全事故时间线与局域网通知](07-safety-incidents-lan-notifications.md)
- [25 实现家庭账号、成员、三级身份与多管理员](25-household-accounts-roles-admins.md)
- [26 实现细粒度权限、高风险再认证与管理员审计](26-fine-grained-permissions-high-risk-audit.md)
