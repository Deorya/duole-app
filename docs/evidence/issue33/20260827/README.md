# Issue 33 软件证据与 REAL 验收检查点

## 软件纵向切片

- 正式 Runtime 复用同一个 `TaskCoordinator`，以 `manual_mapping` 独占
  `motion`；普通 `teleop` capability 保持独立关闭。
- Gateway 仅发送 session/lease/epoch/seq/TTL 归一化意图。导航板持久进程
  独占固定低速 profile、加速度限制、ROS 碰撞门、400 ms base watchdog、
  独立里程计停稳确认与唯一 `/cmd_vel` 出口。
- REAL SLAM 进度通过有界 DTO 投影；共同充电桩锚点、播报、指示灯、30+5
  分钟阶段、四种保存结果、原子快照、异常恢复、放弃删除和恢复原活动地图均
  由板端生命周期实现。
- 所有 REAL 终态先确认真实轮速停止，再保存/删除地图、停止建图服务、恢复
  导航，最后释放 Runtime motion owner。
- `duole-manual-mapping-runtime.service` 随手动建图 unit 启停；启动要等 ROS
  里程计、激光、地图及 BMS 新鲜就绪，崩溃/重启默认 unarmed+zero，且不恢复
  旧 lease。
- OpenAPI 已升至 `1.7.0`，App 合同兼容 `REAL` 与 `MOCK_NO_MOTION`；REAL
  capability 只有在 Issue 33 REAL 门禁生成只读验收标记后才开放。

## 自动验证

- Provider Issue 33/相关模块定向回归：`176 passed`。
- Provider 全仓最终回归：`3213 passed, 1 skipped, 4 warnings`。
- Issue 31/33 Python 验收门禁：`19 passed`。
- Dart 合同从 Provider OpenAPI 重新生成后逐字节一致。
- 当前执行环境没有 Dart、Flutter 或 ADB 可执行文件，因此没有把新增移动端测试
  误报为已运行；测试源码和 REAL 模式 UI/解析覆盖已提交到工作树。

## Fail-closed REAL 门

`tools/issue33_real_gate.py` 要求 11 个停止场景逐项记录 lease、最后 seq、故障、
归零和真实车轮停止时间，并要求最差延迟 `<=1000 ms`。每个 stop 必须绑定经 SHA-256
校验的外部视频，或绑定同场景机器日志的结构化现场操作员观察；还要求 HIL
profile clamp、碰撞减速/阻断、默认 unarmed+zero、真实离桩/覆盖/手动回桩、
四种终态、快照恢复、旧地图恢复、MOCK 回归和普通 teleop 独立关闭。模板见
`tools/issue33_real_evidence.template.json`、
`tools/issue33_stop_telemetry.template.json` 和
`tools/issue33_operator_observation.template.json`。操作员观察只接受故障后、停车后 5 分钟内
记录的现场直接观察；绑定 telemetry 必须与顶层 stop 逐字段一致。未通过时不会生成
capability 标记。

## 当前人工检查点

- 导航板 `ztl@172.22.205.19` 的专用 SSH 公钥已安装，BatchMode 只读连接成功；
  板端存在 `/home/ztl/duole-issue31-nav-ws`，正式导航栈运行中，Issue 33 companion
  unit 尚未安装。
- 首次只读实时采样得到电量约 `75.5%`、里程计线/角速度全零，但 BMS 状态为
  `DISCHARGING`。操作员重新确认停桩并抬起驱动轮后复验：BMS 为 `CHARGING`、
  电量约 `75.6%`、里程计近零、motion inhibit 为 `true`，手动/自主建图服务均
  未运行；充电与静止只读前置条件已满足。
- 本机仍没有 Dart/Flutter SDK 或 ADB；驱动轮已由操作员抬起，但硬件急停操作员、
  外部录像和清空低速区域窗口尚未确认，因此不能安装板端运行时、连接两台 Android
  或执行 HIL/REAL。
- 尚未安装/重启任何 systemd unit，尚未向真实 `/cmd_vel` 发送非零值，也没有
  生成 REAL capability 标记。
