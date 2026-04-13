# AI Usage Local

一个为 macOS 设计的、**纯本地**的 AI coding usage 可视化应用原型，目标是统一查看 Claude Code、Codex CLI、OpenCode、Gemini CLI 的本地使用情况。

## 当前状态

当前仓库已完成第一阶段的：

- 深度研究与方案文档
- Swift 原生应用骨架
- 四个首批 parser 原型：Claude / Codex / OpenCode / Gemini
- Dashboard 原型 UI
- Parser fixture tests

## 产品原则

- 纯本地，不上传
- 原生 Swift/SwiftUI
- parser-first 架构
- SQLite-first（下一步接入）
- 手动刷新优先，后续再加自动监听

## 目录结构

- `docs/research.md` — 深入研究与最佳方案结论
- `docs/plan.md` — 实施路线图
- `App/Sources/AIUsageLocal` — Swift 源码
- `App/Tests/AIUsageLocalTests` — 测试
- `Fixtures` — parser 样例文件

## 当前实现说明

### UI
- Root dashboard
- Overview 指标卡片
- Trends 趋势图
- Breakdown 分布图
- Sessions 最近会话
- Sources & Health 数据源健康状态
- Settings 页面

### Parsers
- `ClaudeCodeParser`
- `CodexParser`
- `OpenCodeParser`
- `GeminiParser`

### Ingestion
- 自动发现默认路径
- 解析后汇总成统一的 events / sessions 数据模型
- 驱动 dashboard 展示

## 下一步优先级

1. 接入 SQLite 持久化与 migrations
2. 做 parser 去重与 import runs
3. 增强真实样本兼容性
4. 完成 macOS 原生 Xcode App 工程
5. 加入更精致的空状态、错误状态与设置项
6. 未来增加菜单栏模式和自动监听

## 注意

当前执行环境不是 macOS，且本机未安装 Swift toolchain，因此**无法在此环境完成实际构建与运行验证**。但代码结构、研究、仓库、测试样例与后续路线已经搭好，可在 macOS 开发机继续推进。
