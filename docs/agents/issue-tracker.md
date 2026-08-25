# 问题跟踪：本地 Markdown

本仓库的问题和 PRD 以 Markdown 文件形式保存在 `.scratch/` 中。

## 约定

- 每项功能使用一个目录：`.scratch/<feature-slug>/`
- PRD 路径为 `.scratch/<feature-slug>/PRD.md`
- 实施工单路径为 `.scratch/<feature-slug>/issues/<NN>-<slug>.md`，从 `01` 开始编号
- 工单状态记录在文件顶部附近的 `Status:` 行中
- 状态名称参见 `triage-labels.md`
- 评论和讨论记录追加到文件底部的 `## Comments` 小节

## 当技能要求“发布到问题跟踪器”时

在 `.scratch/<feature-slug>/` 下创建新文件；目录不存在时一并创建。

## 当技能要求“获取相关工单”时

读取引用路径对应的文件。用户通常会直接提供文件路径或工单编号。
