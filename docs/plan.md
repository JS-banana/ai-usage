# AI Usage Local 研究与实施计划

> 目标：打造一款仅本地运行、原生 Swift/SwiftUI 的 macOS AI coding usage 可视化应用，第一阶段支持 Claude Code、Codex CLI、OpenCode、Gemini CLI。

## 项目目标

- 纯本地：不上传任何数据，不依赖服务端
- 原生体验：Swift/SwiftUI + AppKit 适配 macOS
- 高性能：本地增量解析 + SQLite 存储
- 可扩展：按工具拆分 parser adapter
- 可验证：每个 parser 都有样例与集成测试
- UX 优先：提供直观 dashboard、趋势图、工具/模型/项目过滤、健康状态提示

## 研究结论摘要

### 纵向结论（架构）

现有方案大致分三类：

1. **本地日志/数据库解析型**（最适合我们）
   - 代表：Vibe Usage、VibeCodingTracker、Claude-Code-Usage-Tracker、claude-usage-tracker
   - 优势：隐私好、无需登录远端、离线可用、工程控制力强
   - 劣势：需应对本地文件格式变动

2. **OAuth / Cookie / 非官方 API 抓取型**
   - 代表：CodexBar 一部分 provider 方案
   - 优势：有时能拿到更接近官方 quota 数据
   - 劣势：脆弱、复杂、安全面大，不适合第一阶段

3. **CLI 输出抓取型**
   - 优势：原型快
   - 劣势：最不稳定，不应作为主方案

### 横向结论（能力与取舍）

最佳可行第一阶段应采用：

- **数据获取**：本地日志/数据库自动发现 + 手动导入 fallback
- **本地存储**：SQLite（主存储）
- **状态管理**：SwiftUI Observable / 轻量本地配置
- **刷新机制**：初期以“手动刷新 + 启动时刷新 + 定时轮询重扫”为主；文件监听放在第二阶段增强
- **图表界面**：原生 Swift Charts
- **聚合模型**：
  - Usage events（原始导入记录）
  - Session summaries（会话级）
  - Time buckets（30分钟/1天）

## 为什么不用纯自动 watcher 作为第一阶段主入口

原因：
- 各工具路径与格式可能变化
- 用户需要更强的控制和可验证性
- 在无真实 macOS 环境验证前，先用“显式刷新”更稳

因此建议第一阶段：
- 默认自动发现已知路径
- 用户点击“Refresh / Rescan”触发全量或增量扫描
- 保留后续加入 FSEvents watcher 的接口

## 第一阶段产品定义

### App 形态

- 主窗口 app（不是仅菜单栏）
- 可后续增加菜单栏入口
- 第一阶段优先主窗口 dashboard 体验

### 核心页面

1. Overview
   - 今日 tokens
   - 7天 tokens
   - 会话数
   - 活跃工具数

2. Trends
   - 按天/按小时趋势图

3. Breakdown
   - 按工具 / 模型 / 项目分布

4. Sessions
   - 最近会话列表
   - 会话详情摘要

5. Sources / Health
   - 每个数据源是否发现
   - 最近扫描时间
   - 错误提示

6. Settings
   - 启用/禁用某工具 parser
   - 手动添加目录
   - 重建索引

## 推荐技术方案

### 平台与框架
- Swift 6+
- SwiftUI
- Swift Charts
- SQLite（建议 GRDB，如果需要降低依赖可后续改为原生 sqlite3 封装）

### 数据层

统一 schema：

- `sources`
- `import_runs`
- `raw_session_files`
- `usage_events`
- `session_summaries`
- `bucket_summaries`

### Parser Adapter 接口

```swift
protocol UsageParser {
    var sourceID: String { get }
    func discoverCandidates() -> [URL]
    func parse(at url: URL) throws -> ParsedSourceBatch
}
```

### 第一阶段 parser 策略

- Claude Code: JSONL session parser
- Codex: rollout/session JSONL parser
- OpenCode: session/message JSON 或 sqlite source adapter（二选一，优先更稳的文件结构）
- Gemini: chat/session JSON parser

### 导入策略

- 先做“可重复全量导入 + 去重”
- 去重 key：source + sessionID + event timestamp + event hash
- 第二步再做增量 cursor

## 实施路线

### Milestone 1：项目骨架
- 建 Swift package / Xcode project
- 建目录结构
- 接入 SQLite
- 建基础 dashboard 假数据 UI

### Milestone 2：数据模型与仓储
- 建 schema migration
- 建 repository 层
- 建 importer pipeline

### Milestone 3：Claude + Codex parser
- 完成两个最重要数据源
- 加样例测试

### Milestone 4：OpenCode + Gemini parser
- 接入剩余两个源
- 健康面板展示状态

### Milestone 5：聚合与可视化
- Overview / Trends / Breakdown / Sessions
- 错误与空状态体验

### Milestone 6：验证与打磨
- parser fixtures
- snapshot/logic tests
- README、架构说明、下一阶段计划

## 验收标准

- 能在本地扫描并导入至少 Claude Code、Codex、OpenCode、Gemini 四类数据源
- 能显示总 token、趋势、按工具/模型/项目分布
- 能看到最近会话列表
- 所有数据纯本地存储
- 无服务端依赖
- 有明确测试与样例数据

## 第二阶段预留

- FSEvents 自动监听
- 菜单栏模式
- 更精细的 session timeline
- 导出 CSV / JSON
- 更复杂成本估算
- 更强隐私脱敏开关
