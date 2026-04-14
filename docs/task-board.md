# AI Usage Local Task Board

## Current Mission

将 `ai-usage-local` 从研究型 prototype 演进为可持续迭代的产品级原生 macOS 本地 AI usage app 工程底座。

## Now

### In Progress
- 全局二次思考与执行路径复核

### Next Up
1. 建立正式 project-management / context-management 文档
2. 执行 P0 工程重构
3. 设计 P1 persistence foundation

## P0 Engineering Refactor Checklist

- [ ] 建立新版目录结构草案
- [ ] 重新定义 Domain model 与 invariants
- [ ] 替换不稳定 ID 方案
- [ ] 统一时间解析与 parse diagnostics
- [ ] parser contract 升级
- [ ] fixture 改为正式测试资源
- [ ] 设计 parser contract tests

## P1 Foundation Checklist

- [ ] 设计 `Persistence` package
- [ ] 设计 SQLite schema
- [ ] 设计 `ImportCoordinator`
- [ ] 设计 `AnalyticsQueryService`
- [ ] 设计 source health / import runs / diagnostics 模型

## Deferred

- [ ] Menu bar 模式
- [ ] FSEvents watcher
- [ ] Export CSV / JSON
- [ ] 成本估算增强
- [ ] App sandbox/bookmark 策略实现
