# DUOLE App 开发上下文索引

Status: `ready-for-agent`

## 本仓库上下文

| 目录 | 内容 |
|---|---|
| [duole-family-app/](duole-family-app/README.md) | 产品需求、页面/交互、设计系统、客户端架构、建议 API 与 App 验收 |
| [duole-family-app-v1/](duole-family-app-v1/PRD.md) | Engineering V1 与 Family Product 的产品 PRD、本地问题和历史验收记录 |

## 仓库边界

- 本仓库拥有 Dart consumer、Dart client、Flutter App，以及 App 产品和客户端 backlog。
- `duole-workspace` 拥有机器人 runtime、public gateway、provider contract、设备与 HIL 实现。
- 文档中的 `docs/interface_freeze/...` 路径指 API 提供方仓库的机器可读合同或历史证据，
  不是本仓库内的相对路径。
- 跨端功能在本仓库保留产品/客户端工单；机器人实现应在 provider 仓库建立对应工单，
  两端通过版本化 OpenAPI、fixture、版本号和验收证据协作，不共享源码目录。

## 本地问题跟踪

功能 PRD 放在 `.scratch/<feature-slug>/PRD.md`，实施工单放在
`.scratch/<feature-slug>/issues/<NN>-<slug>.md`。状态使用 `needs-triage`、`needs-info`、
`ready-for-agent`、`ready-for-human` 或 `wontfix`。
