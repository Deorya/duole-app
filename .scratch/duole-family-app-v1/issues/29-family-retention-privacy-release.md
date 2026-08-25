# 完成家庭构建隔离、数据留存与隐私发布验收

Status: needs-triage

Type: HITL

User stories covered: 149–152, 157

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

完成 Family Product 发布前的最终隐私与数据治理闭环：家庭构建彻底移除工程诊断和危险测试
能力，结构化记录按批准的默认期限留存、可查询和删除，实时媒体继续默认不保存；账号、远程
通知、多人媒体和机器人本地审计形成清晰的数据 owner、访问、导出和删除策略，并完成法律、
隐私、安全和发布验收。

## Acceptance criteria

- [ ] Family build 在编译、路由和服务端 capability 层移除工程诊断、危险测试、raw score 和内部拓扑入口。
- [ ] 默认保留策略实现为：设备状态/媒体连接记录 30 天，日程执行/结构化安全事件 180 天，权限/高风险审计 1 年。
- [ ] event replay 窗口与长期业务记录保留分开配置和说明，裁剪 replay 不删除活动事故或业务事实。
- [ ] 实时视频、环境音、PTT 和通话默认不落盘；任何未来录制必须另行产品授权和 PRD。
- [ ] 用户可查看适用的留存说明、导出范围和删除/解绑后果；删除流程处理云端、机器人和备份生命周期。
- [ ] 法定/安全审计保留与用户删除请求冲突时使用明确政策和最小化字段，不静默无限保留。
- [ ] 诊断、crash、analytics、push、SMS、SFU 和 robot logs 均有字段 allowlist、owner、region/传输和 retention。
- [ ] 高风险导出/删除/解绑要求再认证、通知全部管理员并形成不可篡改审计。
- [ ] 家庭 App 不显示 ROS、进程名、模型 raw score 或 Engineering flavor 水印/入口。
- [ ] 完成 secret/PII scan、权限矩阵、留存时间推进、删除传播、备份恢复和越权访问测试。
- [ ] 隐私政策、用户提示、机器人持续媒体提示和本地 privacy 优先级与实际行为一致。
- [ ] 产品、法律/隐私、安全、机器人、App、云端和 QA owner 完成 Family Product 发布签字。

## Blocked by

- [26 实现细粒度权限、高风险再认证与管理员审计](26-fine-grained-permissions-high-risk-audit.md)
- [27 实现安全远程接入、可靠推送与短信兜底](27-secure-remote-notification-sms.md)
- [28 实现多人观看、九端通话、头像与机器人宫格布局](28-multiparty-view-nine-endpoint-call.md)
