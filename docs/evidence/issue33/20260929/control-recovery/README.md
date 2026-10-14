# Issue 33：方向、碰撞开发配置与控制通道恢复（2026-09-29）

本次状态为软件修复及设备安装完成，修复后的持续真车操控尚待现场复测。不是完整 Issue 33 验收。

用户通过实际 App 开始会话并操控机器人，确认初段流畅、页面出现行驶轨迹；随后报告左右
反向、靠近桌子仍减速及控制通道错误，无法再次遥控。页面当时显示地图 r42、轨迹 13 点。
故障会话已通过 App“立即停止并保存”结束，数据库结果为 immediate_stop_saved。

## 依据与修复

- App 先前将右移摇杆映射为正 angular；ROS 正角速度对应左转。本次改为负 dx，
  视觉摇杆位置及前后方向保持一致。页面测试覆盖触摸、发送和显示的角速度符号。
- 此次停止记录为 1131 ms。用实际会话 DTO 运行 Dart 合同解析器，得到
  `FormatException: $.stop_latency_ms must be at most 1000`。App 解析失败后关闭通道；
  重读同一会话仍会失败。未捕获原始 WebSocket 异常堆栈，不把这个条件扩展为所有中断的唯一原因。
- 前一修复只传递板端时间；本次发现板端也在轮询 stop_status 时才记录确认时间。
  回归复现中轮速 550 ms 已稳定停车，1500 ms 查询却报告 1500 ms。
  现在保存首次连续 250 ms 满足既有轮速阈值的原始轮速样本时刻，并传给 Gateway。
  Gateway 连接中断分支也使用该时间。真实超时值不会截断，合同的 1000 ms 上限未放宽。
- 当前失败会话的真实轮速停止耗时不能从旧记录还原；1131 ms 不作为真实车轮超时结论。
- 按用户指令，开发阶段关闭 guard 的碰撞减速/阻断过滤。板端默认仍保持保护，
  显式 CLI 选项或现有 owner-local 状态目录的开发标记才关闭过滤。
  当前标记为 `/home/ztl/duole-issue31-nav-ws/state/manual-mapping-collision-development.disabled`，
  内容 `enabled`（末尾换行），owner ztl、权限 600；下次手动会话生效。
  松手停车、轮速确认、400 ms 看门狗、原有速度上限 0.20 m/s / 0.90 rad/s 均保留。

## 本次软件验证与安装

- Provider 相关回归：111 passed。后续 owner-local 配置由最终板端回归覆盖。
- 实际待安装板端模块回归：53 passed；运行前断言 import 路径，覆盖 ROS/guard 停车、
  显式碰撞选项及默认开启保护、看门狗、IPC。保留板端已有的看门狗停车上下文和 TF QoS 修复。
- App 页面：32 passed。首次测试受本机代理影响，清除代理后执行；两个旧方向显示断言随后修正，最终全通过。
- APK 离线 Gradle 构建通过。使用原缓存和 arm64 aapt2；Flutter 的空 NDK 下载占位
  CMake 任务因 x86 编译器无法在当前 arm64 主机运行而跳过，实际 Dart/插件依赖正常打包。
- APK v2005 / 0.1.0-phaseA2：已验证调试 kernel 含正确方向源码，arm64 Flutter 引擎与
  原 v2004 完全相同，ADB install 返回 Success，启动 MainActivity 成功。
  SHA256 `1f569d8f34d4a36f0253a77963c382f92a92fd10f79743b66421c74d3f4ed683`。
- 新 APK 本地路径：
  `flutter/duole_engineering_app/build/issue33-phaseA-local-20260927/session-20260929/duole-engineering-app-controls-v2005.apk`。
  App 回滚：同目录上一级 `duole-engineering-app-debug-arm64.apk`（v2004）。
- 已安装三项最小板端补丁；精确回滚原文件在导航板
  `/home/ztl/duole-issue31-nav-ws/backups/issue33-controls-20260929/`。
  恢复碰撞过滤时移除上述开发标记；root systemd drop-in 未安装。
- 主机重启清空先前 /tmp 联调状态；新的开发数据库、证书和脚本改放 App 忽略的 build
  目录下，IPC 仍用当前用户专属 `/tmp/issue33-session/app-read.sock`。
  使用原设备密钥重新签发证书并恢复正式配对，没有生成 REAL 验收 marker。
- 故障建图/guard 均已停止，导航服务恢复；本任务 Gateway 已关闭，App-only Runtime 已退出。

下一步需要操作者在机器人旁、周围留出空地且可立即急停，确认准备好后，通过正式
App-only 开发入口启动新会话，验证左/右转向、无碰撞减速、松手后重按及持续控制。
地图保存与资料库闭环、完整停止矩阵、正式发布验收仍未完成。
