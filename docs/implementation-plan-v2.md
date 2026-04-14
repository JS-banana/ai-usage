# AI Usage Local 复盘审查与二次实施方案

> **For Hermes:** 后续实现应按此方案拆分模块、补齐测试、先修工程基础再扩功能。

**Goal:** 将当前 prototype 重新梳理为可持续演进的原生 macOS 本地产品工程，并给出明确、可执行的下一阶段实施路线。

**Architecture:** 采用 `App Shell + Presentation + Domain + Ingestion + Parsers + Persistence` 分层架构。第一优先级不是加新功能，而是修正工程边界、稳定 parser 契约、引入持久化与可验证测试体系，让后续迭代不失控。

**Tech Stack:** SwiftUI、Swift Charts、SQLite（建议 GRDB）、Swift Testing/XCTest、CryptoKit、后续 Xcode macOS App 工程。

---

## 一、重新 Review 后的总判断

### 结论一句话

**当前仓库更像“方向正确的研究型原型”，还不是“可长期维护的产品级工程底座”。**

这并不意味着前面的工作没价值。相反，前面的研究、产品方向、首批 parser 方向和 UI 信息架构是对的；但从工程角度看，现在这版：

- 模块边界不够清晰
- parser 契约过弱
- ID 设计不稳定
- 错误处理过于宽松
- 测试策略不可靠
- 目录结构还不属于原生 macOS app 的最佳实践

所以，**昨晚的授权/阻塞不会影响方向判断，但确实意味着“代码已落地 ≠ 工程方案已经最优”**。这次应该先做一次“架构纠偏”，再继续功能堆叠。

---

## 二、当前版本的优点

### 1. 产品方向是对的
- local-first
- 不依赖服务端
- 主流工具优先
- Dashboard 优先于复杂同步

### 2. 首批 parser 选型合理
- Claude / Codex / OpenCode / Gemini 是正确的 Phase 1 组合

### 3. UI 信息架构也基本对
- Overview
- Trends
- Breakdown
- Sessions
- Source Health
- Settings

### 4. 已有研究文档可复用
- `docs/research.md`
- `docs/plan.md`

这些不会被推翻，只会被升级。

---

## 三、当前版本的主要问题

## 1. 工程结构不是最佳实践

当前：
- 所有东西都在一个 target/module 里
- UI、状态、parser、聚合逻辑耦合过紧

这会导致：
- parser 改动容易影响 UI
- SQLite 接入会变得混乱
- 后续菜单栏模式难接
- 测试颗粒度差

### 建议目标结构

```text
AIUsageLocal/
├── App/
│   ├── AIUsageLocal.xcodeproj         # 真正的 macOS app 工程
│   ├── AIUsageLocalApp/               # App entry / scenes / assets / plist / entitlements
│   └── Packages/
│       ├── Domain/
│       ├── Ingestion/
│       ├── Parsers/
│       ├── Persistence/
│       ├── Features/
│       │   ├── Dashboard/
│       │   ├── Sessions/
│       │   ├── Sources/
│       │   └── Settings/
│       └── Support/
├── Tests/
│   ├── DomainTests/
│   ├── ParserContractTests/
│   ├── IngestionTests/
│   ├── PersistenceTests/
│   └── FeatureTests/
├── Fixtures/
├── docs/
└── Scripts/
```

---

## 2. parser 设计当前还只是 demo，不是产品级 parser

### 主要问题
- 直接用 `[String: Any]` + `JSONSerialization`
- 大量 `try?` + `continue`
- 错误直接吞掉
- 时间解析失败使用 `.distantPast`
- event/session ID 使用 `hashValue`，不稳定

### 风险
- 重启后 ID 变化，无法可靠去重
- 数据损坏会“静默成功”
- UI 看起来 ready，但实际解析失败
- 趋势图可能被错误时间污染

### 必须立刻修的点
1. `hashValue` 改成稳定哈希（CryptoKit SHA256）
2. `.distantPast` 改成显式 parse failure
3. parser 返回 diagnostics
4. 引入 parser contract tests
5. session summary 前统一排序/校验

---

## 3. 当前 IngestionService 职责过多

它现在同时负责：
- 调 discover
- 调 parse
- 拼 health
- 算 metrics
- 算 breakdown
- 算趋势

这不是最佳实践。

### 应拆分为

#### A. ImportCoordinator
负责：
- 发现 source files
- 调 parser
- 写入 persistence
- 记录 import run

#### B. AnalyticsRepository / QueryService
负责：
- 读 SQLite
- 出 dashboard 数据
- 出 sessions 列表
- 出 source health summary

#### C. Feature ViewModel
负责：
- 页面状态
- loading/error/empty
- 调用 query/use case

---

## 4. 当前测试不可靠

### 主要问题
- fixture path 使用绝对路径
- 只有 happy path
- 没有 malformed input 测试
- 没有 analytics 测试
- 没有去重/稳定 ID 测试

### 必须升级为三层测试

#### Layer 1: Parser Contract Tests
每个 parser 都要满足统一契约：
- 事件 ID 稳定
- 时间合法
- token 不为负
- session 聚合正确
- diagnostics 可观察

#### Layer 2: Fixture-based Parser Tests
覆盖：
- 正常数据
- 缺字段
- 多 schema 版本
- 部分损坏
- 空文件
- 重复 event

#### Layer 3: Analytics / Persistence Tests
覆盖：
- 今日/近7天聚合
- top N breakdown
- source health
- dedupe
- import runs

---

## 5. 当前不是最佳“原生 macOS app”落地方式

虽然 Swift Package 适合原型，但**正式产品应有 Xcode 原生 app 工程**。

原因：
- app lifecycle
- Assets / AppIcon
- Settings
- Entitlements
- Sandbox / bookmark / file access
- 签名、归档、发布
- 后续菜单栏模式

### 结论
后续应该：
- 保留 Swift packages 做模块化代码
- 但外层切到 Xcode macOS app 工程承载真正产品

---

## 四、最佳实践版工程方案

## 1. 分层架构

### App Shell
- 启动入口
- Window/Settings/MenuBar scene
- DI 组装

### Features
- DashboardFeature
- SessionsFeature
- SourcesFeature
- SettingsFeature

### Domain
- `UsageEvent`
- `SessionSummary`
- `SourceDescriptor`
- `ImportRun`
- `ParserDiagnostic`
- 统一 invariants

### Parsers
- `UsageParser` protocol
- `ClaudeCodeParser`
- `CodexParser`
- `OpenCodeParser`
- `GeminiParser`

### Ingestion
- `SourceDiscoveryService`
- `ImportCoordinator`
- `DeduplicationService`
- `NormalizationPipeline`

### Persistence
- SQLite schema
- migrations
- repositories
- query layer

### Support
- stable hashing
- date parsing
- logging
- file fingerprinting

---

## 2. 新 parser 契约建议

```swift
public protocol UsageParser {
    var source: SourceDescriptor { get }
    func discover(in environment: ParserEnvironment) throws -> [DiscoveredFile]
    func parse(file: DiscoveredFile) throws -> ParsedFileReport
}
```

### ParsedFileReport 应包含
- normalized events
- normalized sessions
- warnings
- skipped records
- schema version guess
- source fingerprint

而不是只返回裸数组。

---

## 3. Persistence 最佳方案

### 第一推荐
- SQLite + GRDB

原因：
- 对 analytics workload 更适合
- migration、query、test 支持成熟
- 比直接手写 sqlite3 更稳

### 核心表建议
- `sources`
- `source_files`
- `import_runs`
- `usage_events`
- `sessions`
- `daily_buckets`
- `parser_diagnostics`
- `custom_paths`

---

## 4. UI/UX 最佳实践建议

### 第一阶段形态
- 主窗口 app 优先
- 暂不把 menu bar 作为主入口

### Dashboard 结构
- 顶部 summary cards
- 时间范围切换（1D / 7D / 30D / All）
- 趋势图
- source/model/project 分布
- session list
- source health + diagnostics

### 设计原则
- macOS 原生，不要 Web dashboard 思维硬搬
- 强调信息层级和状态可见性
- 任何“未解析/解析失败/路径不可访问”都要可见

---

## 五、可执行实施方案（新版）

## Phase 0：工程纠偏（必须先做）

### Task 0.1：重组仓库结构
**Objective:** 将当前单模块原型升级为分层模块工程

**Files:**
- Create: `App/AIUsageLocal.xcodeproj`
- Create: `App/Packages/Domain/`
- Create: `App/Packages/Parsers/`
- Create: `App/Packages/Ingestion/`
- Create: `App/Packages/Persistence/`
- Create: `App/Packages/Features/`
- Create: `Tests/...`
- Migrate existing sources into the new layout

**Verification:**
- 工程目录清晰
- target/module 边界明确
- 旧代码完成归位

### Task 0.2：定义稳定 Domain Model
**Objective:** 为 UsageEvent/SessionSummary/Diagnostics 建立严格模型与 invariant

**Must include:**
- stable IDs
- token semantics
- valid timestamp constraints
- session time ordering

### Task 0.3：引入稳定哈希与统一时间解析
**Objective:** 消除 `hashValue` 与 `.distantPast` 风险

**Verification:**
- 所有 parser 不再依赖 `hashValue`
- 所有 parser 不再把解析错误当作合法时间

---

## Phase 1：Parser 契约与测试基座

### Task 1.1：重写 parser protocol
**Objective:** parser 输出带 diagnostics 的 `ParsedFileReport`

### Task 1.2：建立 parser contract tests
**Objective:** 所有 parser 共享统一校验规则

### Task 1.3：修复 fixture 资源加载
**Objective:** 使用 test bundle resources，去掉绝对路径

### Task 1.4：为四个 parser 补齐失败场景测试
**Objective:** 提升可靠性

覆盖：
- malformed json/jsonl
- missing timestamp
- missing usage fields
- duplicate events
- empty files
- mixed valid + invalid records

---

## Phase 2：本地存储与导入管线

### Task 2.1：接入 SQLite/GRDB
**Objective:** 建立可迁移的本地持久化层

### Task 2.2：实现 ImportCoordinator
**Objective:** 实现 discover → parse → normalize → dedupe → persist

### Task 2.3：实现 source health / import runs / diagnostics 持久化
**Objective:** 所有导入结果可追踪

### Task 2.4：实现 query services
**Objective:** 为 Dashboard / Sessions / Sources 提供独立查询接口

---

## Phase 3：Feature 化 UI

### Task 3.1：DashboardFeature
- summary
- trends
- breakdown
- range switch

### Task 3.2：SessionsFeature
- 最近会话列表
- session detail
- source/model/project filter

### Task 3.3：SourcesFeature
- source health
- diagnostics
- path visibility

### Task 3.4：SettingsFeature
- enable/disable source
- custom paths
- rebuild index
- privacy messaging

---

## Phase 4：产品化打磨

### Task 4.1：空状态/错误状态/权限状态
### Task 4.2：日志与调试支持
### Task 4.3：性能测试与大数据量基准
### Task 4.4：发布准备（icon, signing, archive, app sandbox strategy）

---

## 六、优先级排序

### P0（必须立即修）
- 模块化重组
- 稳定 ID
- 移除 `.distantPast`
- parser diagnostics
- fixture 测试重构

### P1（下一步主线）
- SQLite/GRDB
- import pipeline
- query layer
- feature view models

### P2（体验增强）
- 真实路径配置
- 更强过滤
- session detail
- 空状态与错误提示

### P3（二期）
- FSEvents watcher
- menu bar mode
- export CSV/JSON
- 成本估算增强

---

## 七、最终建议

### 是否需要继续打磨？
**非常需要。**
不是方向不对，而是应该**先打磨工程基础，再堆功能**。

### 昨晚的推进是否受影响？
有影响，但主要是“没法在正确平台做构建验证”，不是“方向错了”。
所以成果可以保留，但必须按本方案进行架构升级。

### 当前代码是否是最佳实践？
**不是最佳实践，只是合格原型。**
最佳实践版应该是：
- Xcode 原生 app 工程承载产品
- Swift packages 承载模块
- parser 契约更强
- SQLite 持久化先落地
- 测试从 demo fixtures 升级为 contract + persistence + feature 测试

---

## 八、接下来最值得做的第一步

如果继续推进，我建议下一轮直接做这三件事：

1. **重构仓库结构为产品级模块化结构**
2. **引入稳定 ID / diagnostics / parser contract tests**
3. **接入 SQLite/GRDB 持久化底座**

在这三件事完成之前，不建议继续大量扩 UI 或加 watcher。
