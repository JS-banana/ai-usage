# Persistence Package Plan

## Objective

为下一阶段本地数据底座准备独立 `Persistence` package，使其能在你本地 Mac 上直接继续接入 GRDB / SQLite，并与现有 `Domain`、`ParserCore`、未来 `Ingestion` 模块配合。

## Proposed Package Layout

```text
Packages/
└── Persistence/
    ├── Sources/Persistence/
    │   ├── Database/
    │   │   ├── DatabaseManager.swift
    │   │   ├── Migrations.swift
    │   │   └── SchemaVersion.swift
    │   ├── Repositories/
    │   │   ├── SourceRepository.swift
    │   │   ├── ImportRunRepository.swift
    │   │   ├── UsageEventRepository.swift
    │   │   ├── SessionRepository.swift
    │   │   └── DiagnosticRepository.swift
    │   ├── Queries/
    │   │   ├── DashboardQueries.swift
    │   │   ├── SessionQueries.swift
    │   │   └── SourceHealthQueries.swift
    │   └── Models/
    │       ├── PersistedSource.swift
    │       ├── PersistedImportRun.swift
    │       └── PersistedDailyBucket.swift
    └── Tests/PersistenceTests/
```

## Initial Responsibilities

### DatabaseManager
- 打开数据库连接
- 管理 db path
- 初始化/运行 migrations

### Migrations
- v1 schema
- 唯一索引
- 常用 query indexes

### Repositories
- 面向写入与基础读取
- 尽量小接口，避免把 analytics 逻辑塞进 repository

### Queries
- 专门负责 dashboard / session list / source health

## Suggested First GRDB Integration Steps (on Mac)

1. 在 `Package.swift` 增加依赖：
   - `https://github.com/groue/GRDB.swift`
2. 新增 `Persistence` target
3. 先只落 migration + open database + smoke test
4. 再接 `UsageEvent` / `SessionSummary` 落盘
5. 再接 DashboardQueries

## Why Not Implement GRDB Here Yet

当前环境：
- 无 Swift toolchain
- 无 Xcode
- 无法解析和下载 Swift package 依赖

因此在这里先把：
- 模块边界
- schema 设计
- package 布局
- repository/query 责任划分

设计清楚，等你本地拉取后直接继续。
