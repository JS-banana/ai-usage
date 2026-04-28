# AiUsage

一个为 macOS 设计的、**纯本地**的 AI coding usage 可视化应用工程，目标是统一查看 Claude Code、Codex CLI、OpenCode、Gemini CLI 的本地使用情况。

## 当前状态

当前仓库已完成：

- 深度研究与方案文档
- 原生 Swift app 原型
- P0 工程纠偏的第一轮改造
- P1 边界骨架落地：`Persistence` / `Ingestion` / `Query`
- 基础模块拆分：`Domain` / `Support` / `ParserCore`
- 四个首批 parser 原型迁移到 `ParserCore`
- 稳定 ID 与基础 diagnostics 支撑
- parser contract 测试基础

## 产品原则

- 纯本地，不上传
- 原生 Swift/SwiftUI
- parser-first 架构
- SQLite-first（下一步接入）
- 手动刷新优先，后续再加自动监听

## 当前工程结构

- `App/` — app shell 与界面原型
- `Packages/Domain` — 核心领域模型
- `Packages/Support` — 稳定 ID、时间解析、parser 支撑工具
- `Packages/ParserCore` — 解析器协议与首批 source adapters
- `Packages/Persistence` — 持久化边界骨架
- `Packages/Ingestion` — 导入协调层骨架
- `Packages/Query` — 查询服务层骨架
- `Packages/ParserCore/Tests/ParserCoreTests/Resources` — 正式 parser 测试资源
- `docs/` — 研究、执行日志、任务板、实施方案与本地验证指南

## 已完成的工程推进

### P0
- 用稳定 SHA256 代替 `hashValue`
- 不再使用 `.distantPast` 作为非法时间兜底
- parser 返回 `diagnostics` 和 `skippedRecords`
- parser 测试迁移到独立 `ParserCoreTests`
- fixture 已迁移到 test target 内部资源目录，供 `Bundle.module` 访问

### P1 Skeleton
- 增加 `Persistence` package skeleton
- 增加 `Ingestion` package skeleton
- 增加 `Query` package skeleton
- 在 `Domain` 中补充 `ImportRun` / `SourceDescriptor` / `TrackedSourceFile`

## 下一步优先级

1. 在本地 Mac 接入 GRDB 并验证 SwiftPM targets
2. 为 `Persistence` 写 migrations / DatabaseManager
3. 让 `ImportCoordinator` 真正落库
4. 让 Query 层替代 App 内存聚合逻辑
5. 升级为正式 Xcode macOS app 工程
6. 打磨 dashboard、source health、settings 与错误状态

## 本地验证

请优先参考：
- `docs/local-mac-validation-guide.md`

## 注意

当前执行环境不是 macOS，且本机未安装 Swift toolchain，因此**无法在此环境完成实际构建与运行验证**。

你在本地 Mac 拉取后，建议优先：
- 用 Xcode 打开/导入工程
- 校验 package 依赖与 target 构建
- 跑 tests
- 再继续接 Persistence 与 AppShell 产品化工作
