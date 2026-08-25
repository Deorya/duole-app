# 实现细粒度权限、高风险再认证与管理员审计

Status: needs-triage

Type: HITL

User stories covered: 19–24

## Parent

[多乐守护 App 与机器人端接入 V1 PRD](../PRD.md)

## What to build

在家庭成员模型上交付与身份分离的细粒度权限系统，并把远程家庭授权映射到机器人现有
scopes/capabilities。管理员可逐成员授予状态、日程、事件、音视频、发声、任务、遥控和停止；
解绑、删除家庭、移除照护对象、紧急联系人等高风险动作需要再认证、全管理员通知和审计。

## Acceptance criteria

- [ ] 权限键覆盖 status、schedule read/write、events、live view、talk、call、jobs、teleop、stop、privacy 和家庭管理，并有版本化语义。
- [ ] 身份标签与功能权限独立；除管理员必须保留家庭管理外，不因身份自动扩大业务权限。
- [ ] 管理员可查看和修改每位成员权限，变更采用 revision/optimistic concurrency，避免并发静默覆盖。
- [ ] 云端授权在机器人入口映射为 canonical actor 和最小 scopes；App 显示名不能参与授权。
- [ ] 权限撤销及时关闭对应 REST/WS/media/PTT/call/teleop session；撤销 teleop 触发停车。
- [ ] stop 与 teleop 分权；拥有 stop 权限的成员无需控制租约即可停止。
- [ ] 高风险家庭操作要求近期再认证/生物识别或批准的等价证明，不仅依赖已登录 session。
- [ ] 高风险操作通知所有管理员并写入不可被普通成员修改的结构化审计。
- [ ] 至少一位管理员和至少一位紧急通知接收者的家庭约束在所有并发路径保持成立。
- [ ] App 权限矩阵、无权限页面/按钮、权限变化中的 session 行为和稳定错误提示完整。
- [ ] 针对每个 scope 的 allow/deny、管理员并发、stale token/cache、撤销传播和审计完整性测试通过。
- [ ] 权限/再认证/审计方案完成产品、隐私和安全 owner 联合评审。

## Blocked by

- [25 实现家庭账号、成员、三级身份与多管理员](25-household-accounts-roles-admins.md)
