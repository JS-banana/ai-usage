# Local macOS / Xcode Validation Guide

## Goal

你在本地 Mac 上拉取代码后，验证当前工程结构、SwiftPM target、parser tests、以及后续接入 Xcode/GRDB 的准备状态。

## Repository Location Suggestion

```bash
cd ~/projects
git clone https://github.com/JS-banana/ai-usage-local.git
cd ai-usage-local
```

## Step 1: Inspect Current Structure

确认以下目录存在：

- `App/`
- `Packages/Domain/`
- `Packages/Support/`
- `Packages/ParserCore/`
- `Packages/Persistence/`
- `Packages/Ingestion/`
- `Packages/Query/`
- `docs/`

## Step 2: Open with Xcode

有两种方式：

### Option A: 直接用 Xcode 打开 package
- Xcode -> Open -> `Package.swift`

### Option B: 命令行
```bash
open Package.swift
```

## Step 3: Resolve and Inspect Targets

在 Xcode 中确认这些 targets 可见：

- `Domain`
- `Support`
- `ParserCore`
- `Persistence`
- `Ingestion`
- `Query`
- `AiUsage`
- `ParserCoreTests`
- `AiUsageTests`

## Step 4: Run Tests

优先跑：

```bash
swift test
```

额度和刷新策略相关改动优先跑：

```bash
swift test --filter AppStateTests
swift test --filter AppDataServiceTests
swift test --filter EntitlementResolutionMiMoTests
swift test --filter MiMoQuotaServiceTests
swift test --filter PersistenceTests
```

如果你直接用 Xcode：
- Product -> Test

重点确认：
- `ParserCoreTests` 能识别 `Bundle.module` 资源
- fixtures 能正常读取
- target 依赖链无循环

## Step 5: Validate Parser Resource Loading

如果测试失败，重点检查：
- `Packages/ParserCore/Tests/ParserCoreTests/Resources/...` 是否被 Xcode 识别为资源
- `Bundle.module.url(forResource:withExtension:)` 是否返回 nil

## Step 6: Manual Review of Current Skeleton

确认这些文件存在且结构合理：

### Domain
- `Packages/Domain/Sources/Domain/DomainModels.swift`
- `Packages/Domain/Sources/Domain/IngestionModels.swift`

### Support
- `Packages/Support/Sources/Support/ParserSupport.swift`

### ParserCore
- `Packages/ParserCore/Sources/ParserCore/UsageParser.swift`
- `Packages/ParserCore/Sources/ParserCore/*Parser.swift`

### Persistence
- `Packages/Persistence/Sources/Persistence/...`

### Ingestion
- `Packages/Ingestion/Sources/Ingestion/...`

### Query
- `Packages/Query/Sources/Query/...`

## Step 7: Next Real Coding Work on Mac

本地 Mac 上建议继续推进：

### Priority A
1. 给 `Persistence` 接入 GRDB dependency
2. 建立 migrations
3. 实现 `DatabaseManager`
4. 实现 `ImportPersistence`

### Priority B
5. 让 `ImportCoordinator` 真正调用 persistence 落库
6. 实现 Query 层的真实数据读取
7. 逐步把 App 当前内存聚合逻辑迁移到 Query service

### Priority C
8. 建立 Xcode 原生 macOS app 工程
9. 配置 AppIcon / bundle / sandbox strategy
10. 验证真实本地数据路径

## Step 8: Validate Live Menu-Bar Behavior

构建并打开真实 bundle：

```bash
./build.sh --open
```

检查：

- `pgrep -fl AiUsage` 只保留一个真实运行进程，避免 debug binary 和 `dist/AiUsage.app` 混跑。
- `defaults read com.jsbanana.aiusage | rg 'entitlement.target.mimo|entitlement.mimo'` 可看到 MiMo 选源或账号 mirror。
- 打开菜单不会无条件刷新；状态不应每次都跳到“正在刷新数据”。
- 点击 quota 卡片的刷新图标只刷新额度，不触发本机 usage import。
- 点击“设置”后设置窗口应出现在最前面；设置内只出现本机 agent 显隐，不出现 quota URL / API Key / 总览套餐配置。
- 主弹窗 tab 应为“总览 / 额度 / 已启用 agent”；MiMo 出现在“额度”tab 的厂商分组下，不作为 agent tab。
- 在“额度”tab 可把菜单栏显示目标设为 Auto、厂商聚合或具体账号；切换后菜单栏柱状图跟随该目标。
- MiMo token 可用时显示 token-plan 总额度；网络失败时保留上次成功额度并标记 stale；401 或缺 token 时提示重新登录。

## Known Constraints from Remote Development

以下部分尚未在当前远端环境验证：
- Swift 编译
- SwiftPM 依赖解析
- Xcode build
- GRDB package 接入
- 原生 macOS UI 运行

## Success Criteria for This Validation Round

当你本地验证时，这一轮可以判定为成功的条件：

- `swift test` 能跑通或至少明确失败点
- `ParserCoreTests` 能读到 fixtures
- 所有新 targets 都能被 Xcode 识别
- 代码结构清晰，无明显 module 冲突

## If You Hit Issues

建议优先排查：
1. `Package.swift` target path / resource path
2. `Bundle.module` 资源加载
3. Swift 版本 / Xcode 版本兼容
4. target import 关系
