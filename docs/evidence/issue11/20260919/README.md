# Issue 11 正式迁移与候选证据（2026-09-19）

本记录补充 Issue 11 的正式数据库迁移、隔离候选构建、Android 安装及真实机器人 HIL。软件
候选刻意反向移除 Issue 12 改动，Provider/App 均保持 API `3.0.0`。

## Schedule 正式数据库迁移

- 正式数据库：`/home/ztl/duole-workspace/data/schedule.sqlite3`
- 时区：`Asia/Shanghai`
- 迁移前 dry-run：`from_version=2`、`to_version=3`、`count=0`、`dry_run=true`
- 提升权限后的文件占用检查没有发现持有数据库、WAL 或 SHM 的进程。
- 正式迁移：`from_version=2`、`to_version=3`、`count=0`、`dry_run=false`
- 迁移后 dry-run：`from_version=3`、`to_version=3`、`count=0`、`dry_run=true`
- 迁移后数据库 SHA-256：
  `44ca69a30be45cc1ce3a6cfb6f6e7510cf8fce3b6fb4619c9ac809f55412d3a2`
- schema 2 一致性备份：
  `/home/ztl/duole-workspace/backups/schedule-v2-before-20260919.sqlite3`
- 备份 SHA-256：
  `e5f733fbe56d47393ef9bbc68e593860452fbc41c539d7dda6bd4a1897417c24`
- 迁移后正式库与备份均重新执行完整性及转换预览；正式库报告 schema 3，备份保持 schema 2。

正式库原有 0 条 Schedule，因此没有旧规则、标题、时间或提前量需要人工裁决，也没有发生
业务行转换。回退仍须保持所有 writer 停止，并按 Issue 11 操作说明使用 SQLite backup API。

## Android 候选

- 隔离源码：当前 App 共享工作树反向移除完整 Issue 12 补丁；生成合同为 API `3.0.0`。
- Flutter：`3.47.0`
- 目标：debug、`android-arm64`
- 包名：`com.duole.engineering.duole_engineering_app`
- `versionCode`：`2014`
- `versionName`：`0.1.0-issue11-schedule-v2`
- APK：
  `flutter/duole_engineering_app/build/issue11-schedule-v2-candidate/duole-engineering-app-issue11-schedule-v2-2014-debug.apk`
- 大小：`96508001` bytes
- SHA-256：
  `fb80bc4012a91b8f8893a617241c00421640178306cc6d45f52831d26cbb3462`
- ZIP 完整性通过；APK Signature Scheme v2 验证通过。
- 签名证书 SHA-256：
  `fa9601d8d671b83f6d167dbd16001f2224b1f0e78fa35c2468da44b260cf3c0f`
- 包内含 `arm64-v8a` Flutter runtime；ML Kit 依赖还携带 `armeabi-v7a` 和 `x86_64` 预编译库。

构建成功。`mobile_scanner` 的 Kotlin Gradle Plugin 未来兼容性提示，以及非目标 x86 预编译库
无法由宿主 NDK strip 的提示，没有使 Gradle 失败。

目标 Android 以新地址 `172.22.205.14:39321` 上线，型号仍为 Xiaomi `23043RP34C`。
覆盖安装前的 version `2013 / 0.1.0-issue10-session-refresh` 已备份到
`/tmp/issue11-app-install-20260919/rollback-2013.apk`，SHA-256 为
`390212fe6f5e225bb3fccdfb101e9a1e0b7a3946e28305ed9d40a84ee91f633d`；新旧 APK 的签名
证书一致。`adb install -r --no-incremental` 返回 `Success`，没有卸载或清除 App 数据。
`dumpsys package` 确认设备现为 version `2014 / 0.1.0-issue11-schedule-v2`，首次安装时间保持
`2026-08-27 00:19:23`，更新时间为 `2026-09-19 09:53:25`。从设备回拉的新 `base.apk`
SHA-256 与候选完全一致：
`fb80bc4012a91b8f8893a617241c00421640178306cc6d45f52831d26cbb3462`。

## Provider 候选

- 隔离源码：当前 Provider 共享工作树反向移除完整 Issue 12 补丁。
- 登记路径：
  `/home/ztl/duole-workspace/deploy/runtime/issue11-schedule-v2-20260919`
- `duole_central`、`scripts`、`config` 文件集合摘要：
  `278a96c110dfa7237fcddafaa0cb80b62f3faf0168cdcf610db444f537dece17`
- `data` 和 `models` 分别明确链接到 Provider 正式目录；未更新 selector。
- 候选 preflight：API `3.0.0`，正式数据库 dry-run 报告 schema `3`。

隔离回归首轮为 `144 passed / 13 failed`。13 个失败中，9 个来自沙箱禁止 Unix socket，4 个
来自候选最初刻意未复制 `data/schedule.sqlite3`。给候选放入正式库哈希一致的测试快照并允许
本地 Unix socket 后，对失败相关文件重跑为 `64 passed`；没有业务断言失败。

候选第一次启动 Gateway 前发现部署目录缺少冻结 OpenAPI 文档，因而在监听端口前安全失败；补入
纯 Issue 11 的 `docs/interface_freeze/app_v1` 后启动成功。文档中的 OpenAPI 版本为 `3.0.0`，
SHA-256 为 `f97fc4c5d26fecd47e20f3c1d38cb86d6c59962658bfd2c84fa16897919f8a71`。

## 正式产品会话与真实机器人 HIL

- Runtime 从正式入口 `scripts/start_product_voice_board_session.sh` 启动，使用正式 Schedule DB、
  reSpeaker 麦克风及 API `3.0.0`；导航、视觉链、提醒执行和机器人运动均关闭。
- Runtime socket：`/tmp/issue11-hil-20260919/runtime.sock`；Gateway 绑定
  `172.22.205.44:8444`，设备公钥指纹为
  `sha256:5db24e2a9c5a416776ae6d23c13fece229116747e1f712394bc94ed957a474f8`。
- 证据目录最初权限为 `0755`，正式入口在启动业务前拒绝继续；修正为 `0700` 后启动通过。
- Android 在撤销旧的只读会话后重新配对。新会话明确授予
  `robot.status.read`、`schedule.write`，App 随即显示日程管理入口。
- App 创建 `Issue11HIL`：稳定 ID
  `schedule-66f0a3a375bf4f589dc6ba4ff46ef224`，时间 `2026-09-20 10:30`，revision `1`。
- App 保持 revision `1` 的编辑页；真人通过 reSpeaker 说“把明天上午 10:30 的日程改到上午
  11 点”并在机器人询问后说“确认”。机器人回答“已更新：明天11:00 issue11hil”，同一资源
  进入 revision `2`。
- 随后 App 提交仍基于 revision `1` 的标题修改。服务端拒绝覆盖，App 显示“日程已被其他人修改，
  请刷新后重新编辑”，保存和删除均被禁用；点击“刷新最新日程”后显示 revision `2`、原标题
  `Issue11HIL` 和语音写入的 `11:00`。
- App 使用 revision `2` 把标题更新为 `Issue11AppUpdated`，返回列表后重新进入编辑页确认
  revision `3`；再经删除确认完成删除，目标日期列表恢复“这一天没有日程”。
- 语音会话原始控制台日志位于 `/tmp/issue11-hil-20260919/board-session-retry1.log`，SHA-256：
  `2bc20e73549fd273bf6f67caddeedb63b54c4ed253591d642f4b6ee1ce76ec66`。ASR JSONL 的 SHA-256：
  `d3eb9f829975453891a5c895eac2a214995746180cf9d1f7b6dad14787bb7ab6`。关键语音往返另保存为
  [HIL 语音摘录](hil-voice-transcript.log)。

## 收尾核对

- Gateway 与 Runtime 均通过前台会话中断退出；`8444` 不再监听，Runtime socket 已移除，未发现
  遗留产品会话进程。
- 迁移工具再次以只读 dry-run 检查正式库：`from_version=3`、`to_version=3`、`count=1`、
  `dry_run=true`。`count=1` 是本次已删除资源的 tombstone，不是仍生效的提醒。
- Schedule repository 只读核对为 schema `3`、`active_count=0`；正式库最终 SHA-256：
  `ef49ca6c20c64e85e3af0f78b8eafca3bb8636fe031bd7915cf87560f0d2a052`。

Issue 11 的正式迁移、候选安装、App CRUD、真实语音更新、旧 revision 冲突拒绝、刷新恢复及
验收数据清理均已完成。selector 未更新，候选目录仍保留以便审计；这不影响本次限定 HIL 的
验收结论。
