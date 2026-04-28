# AiUsage 深度研究与方案结论

## 1. 目标与约束

目标：构建一款**纯本地、原生 Swift/SwiftUI 的 macOS AI usage 可视化应用**，第一阶段支持：

- Claude Code
- Codex CLI
- OpenCode
- Gemini CLI

约束：

- 不上传数据
- 不依赖服务端
- 追求较好 UI/UX
- 第一阶段重视可验证性、稳定性与可扩展性

---

## 2. 纵向研究：现有方案架构分型

### A. 本地日志/数据库解析型
代表：
- Vibe Usage
- VibeCodingTracker
- Claude-Code-Usage-Tracker
- claude-usage-tracker

共同特征：
- 直接读取本地 JSON / JSONL / SQLite
- 统一抽取 token、session、project、model 等字段
- 本地聚合后做展示或同步

优点：
- 隐私最佳
- 离线可用
- 可控性强
- 无需对接不稳定远端接口

缺点：
- 需要持续适配各工具本地格式变化
- 有些 usage 只能推导，不能拿到官方 quota

结论：**这是最适合我们的主路线。**

### B. OAuth / Cookie / Web API 抓取型
代表：
- CodexBar 的部分 provider 能力

优点：
- 某些场景可拿到更接近真实订阅/quota/reset 信息

缺点：
- 涉及 Keychain、Cookie、浏览器、本地权限
- 安全面扩大
- 维护成本高
- 易被上游接口变动破坏

结论：**不适合第一阶段。可作为二期增强。**

### C. CLI 输出抓取型
代表：
- 一些 usage monitor 工具对 `/usage` 等命令的解析

优点：
- 原型开发快

缺点：
- 输出格式脆弱
- 易受 rate limit、终端环境、语言环境影响
- 长期不可维护

结论：**仅可作为 fallback，不应作为主方案。**

---

## 3. 横向研究：代表项目对比

| 方案 | 技术 | 数据来源 | 优势 | 劣势 | 可借鉴点 |
|---|---|---|---|---|---|
| Vibe Usage | Node CLI + Web + Mac app | 本地日志/SQLite | 统一 bucket/session 模型，工程务实 | 依赖服务端可视化主路径 | 双轨数据模型、parser adapter |
| VibeCodingTracker | Rust CLI/TUI | 本地日志 | 高性能、零配置、多 provider | 非原生桌面 UX | parser 设计、成本聚合思路 |
| CodexBar | Swift 原生菜单栏 | API/OAuth/Cookie/CLI/日志混合 | 原生 macOS UX 很强 | 复杂度高、权限/认证重 | 原生信息架构、provider abstraction |
| Claude-Code-Usage-Tracker | Tauri | Claude 本地日志 | 桌面化简单直接 | 单工具为主 | 本地采集 + dashboard 组合 |
| claude-usage-tracker | 本地脚本 + macOS app 包装 | 多工具本地日志 | local-first、可视化好 | 技术栈较混合 | 仪表盘内容编排、暗色风格 |

### 横向结论

第一阶段最优策略不是“最准官方 quota”，而是：

> **最强的本地可观测性 + 最佳原生体验 + 可扩展 parser 架构**

换句话说，先做“本地 usage intelligence app”，而不是“官方订阅额度镜像 app”。

---

## 4. 对四个首批数据源的现实判断

### Claude Code
- 公共资料和现有工具验证较充分
- 主要是 JSONL session/transcript
- 最适合作为首个 parser

### Codex CLI
- 有 session rollout JSONL，另有 history / sqlite 辅助痕迹
- 第一阶段优先 rollout/session 文件，不依赖 sqlite

### OpenCode
- 公开资料显示其可能使用 session/message JSON 或 sqlite
- 第一阶段优先**更稳定、可遍历、可测试的文件结构**；sqlite 可作为后续增强

### Gemini CLI
- 有 project-hash 目录和 session/chat JSON
- schema 有变化风险
- 需要做 version-tolerant parser

---

## 5. 自动获取 vs 手动获取：最佳可行方案

### 结论：第一阶段采用“自动发现 + 手动刷新 + 手动导入 fallback”

不建议第一阶段把 FSEvents/实时 watcher 作为核心入口，原因：

1. 首批支持 4 个源，格式与路径复杂
2. watcher 会增加调试难度和不可见状态
3. 当前开发环境不是 macOS，本轮优先做可验证主干
4. 手动刷新更利于验证 parser 结果与修复问题

### 第一阶段推荐行为

- 启动时自动扫描默认路径
- 用户可点击“Refresh / Rescan”
- 支持手动添加目录
- 支持导入单个 session 文件 / 目录
- 记录每个 source 的健康状态和最近扫描结果

### 第二阶段再加
- FSEvents 目录监听
- 周期后台增量更新
- 菜单栏快捷入口

---

## 6. 最佳可行技术架构

### 6.1 UI 层

推荐：
- SwiftUI 主界面
- Swift Charts 图表
- AppKit 只做必要桥接

原因：
- 原生性能好
- 开发效率高
- 图表表现足够
- 未来可平滑加菜单栏入口

### 6.2 存储层

推荐：**SQLite 作为主存储**

原因：
- 适合 append-heavy 的 usage event 数据
- 适合聚合与过滤查询
- 适合持久化 import checkpoints
- 比 SwiftData 更适合 analytics workload

建议：
- `usage_events`
- `sessions`
- `sources`
- `import_runs`
- `source_files`
- `daily_buckets`

### 6.3 Parser 层

每个工具一个 adapter：

```swift
protocol UsageParser {
    var sourceID: String { get }
    func discoverCandidates() -> [URL]
    func parseFile(_ url: URL) throws -> ParsedFileResult
}
```

统一输出：
- usage events
- session summaries
- diagnostics

### 6.4 Import 流程

第一阶段：
- 全量扫描
- 内容 hash / event hash 去重
- 结果覆盖式聚合

这样比增量 cursor 更稳，更容易先做对。

第二阶段：
- 文件指纹 + offset/checkpoint 增量导入

### 6.5 分析模型

建议分三层：

1. **Raw Events**
   - 最小可追踪 usage 记录

2. **Sessions**
   - 会话起止、工具、模型、项目、token 汇总

3. **Buckets**
   - 按小时/天聚合，支撑图表

---

## 7. 第一阶段产品定义（MVP+）

### 页面结构

#### Overview
- 今日 tokens
- 7 天 tokens
- 会话数
- 活跃 source 数

#### Trends
- 按日趋势
- 按 source/model 分组趋势

#### Breakdown
- 工具分布
- 模型分布
- 项目分布

#### Sessions
- 最近会话列表
- 会话 token 摘要
- source / model / project 标签

#### Sources & Health
- 各数据源是否发现
- 上次扫描时间
- 扫描错误
- 当前启用状态

#### Settings
- 启用/停用 parser
- 添加自定义路径
- 清空/重建索引

---

## 8. 什么应该避免

### 避免 1：第一阶段就做服务端同步
这会显著扩大复杂度，不符合用户要求。

### 避免 2：第一阶段就大量依赖 cookie / OAuth
会把问题从“usage app”变成“认证维护 app”。

### 避免 3：第一阶段就过度追求实时 watcher
会降低可验证性，不利于 parser 稳定化。

### 避免 4：把每个 provider 特殊逻辑散落在 UI 层
必须做 parser adapter + domain model 抽象。

### 避免 5：过早做复杂成本估算系统
先把 token / session / project / model 可视化做好。
成本估算可以作为辅助字段，不作为核心价值。

---

## 9. 最终最佳可行性方案结论

### 推荐的一阶段方案

**一个原生 Swift/SwiftUI macOS 桌面应用，采用本地自动发现 + 手动刷新模式，从 Claude Code、Codex CLI、OpenCode、Gemini 的本地 session/log 文件中提取 usage 数据，使用 SQLite 做本地统一存储与聚合，并通过 Swift Charts 提供高质量可视化 dashboard。**

### 关键原则

- local-first
- parser-first
- SQLite-first
- manual-refresh-first
- UI/UX 作为核心产品力
- 先稳定支持 4 个主流工具，再扩展自动监听和菜单栏

### 一句话产品定位

> **一个纯本地、漂亮、可靠的 AI coding usage intelligence app for macOS。**
