# P1 Foundation Design

## Goal

在 P0 工程纠偏完成后，为 AI Usage Local 落地可持续的本地数据底座：

- SQLite/GRDB persistence
- ImportCoordinator
- Query/analytics 分层
- import runs / diagnostics / source health 持久化

## Proposed Modules

### Persistence
负责：
- 数据库连接管理
- schema migrations
- repositories
- query models

### Ingestion
负责：
- source discovery
- parser dispatch
- normalize
- dedupe
- persist import runs

### Features / Query Layer
负责：
- DashboardQueryService
- SessionsQueryService
- SourceHealthQueryService

## Schema Draft

### sources
- id
- display_name
- enabled
- built_in
- created_at
- updated_at

### source_files
- id
- source_id
- path
- fingerprint
- last_seen_at
- last_import_run_id

### import_runs
- id
- started_at
- finished_at
- status
- total_files
- total_events
- total_sessions
- skipped_records

### parser_diagnostics
- id
- import_run_id
- source_id
- file_path
- severity
- message
- created_at

### usage_events
- id
- source_id
- session_id
- model
- project
- timestamp
- input_tokens
- output_tokens
- cached_tokens
- total_tokens

### sessions
- id
- source_id
- model
- project
- started_at
- ended_at
- messages
- total_tokens
- file_path

### daily_buckets (可后续 materialize)
- source_id
- bucket_date
- total_tokens
- session_count

## ImportCoordinator Outline

1. load enabled sources
2. discover candidate files
3. fingerprint files
4. parse via parser adapters
5. validate normalized records
6. dedupe
7. write import_run + diagnostics + events + sessions in one transaction
8. refresh materialized daily buckets (or compute on query in early phase)

## Dedupe Strategy

- event id 为稳定哈希
- session id 为稳定哈希
- `usage_events.id` 唯一索引
- `sessions.id` 唯一索引

## Query Layer Outline

### DashboardQueryService
- summary(range)
- trend(range, granularity)
- breakdownBySource(range)
- breakdownByModel(range)
- breakdownByProject(range)

### SessionsQueryService
- recentSessions(limit)
- sessions(filter)
- sessionDetail(id)

### SourceHealthQueryService
- sourceOverview()
- latestDiagnostics(sourceID)

## Why SQLite + GRDB

- 适合 append-heavy analytics
- 支持 migration
- 测试友好
- 比手写 sqlite3 更稳健
- 比 SwiftData 更适合这类数据导向产品

## Not Yet Implemented In This Environment

由于当前环境不是 macOS 且无 Swift toolchain，本阶段先完成：
- schema 设计
- package 结构设计
- 文档与边界定义

等你在本地 Mac 拉取后，可直接继续：
- 接入 GRDB dependency
- 建 migrations
- 跑 Xcode build/test
