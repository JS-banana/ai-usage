# Ai Usage App

macOS 菜单栏 AI usage 查看器。本地优先，不托管账号，不保存线上凭证。

## 产品边界

AiUsage 有两套一等功能逻辑，代码和刷新策略必须保持分层：

1. **本机 Agent Usage 统计**：Codex、Claude Code、OpenCode、Gemini 等本机日志/历史文件解析，经过 Ingestion → Persistence → Query 聚合出 token、请求数、趋势和来源健康度。
2. **Entitlement / Subscription 查询**：MiMo、后续 GPT Plus、GLM 等账号或订阅套餐的远程额度查询。它依赖官方网页登录态、第三方 API 或 CLI 探测，回答剩余额度、重置/过期时间、是否需要重新登录。

不要把远程额度失败当成本地 usage 失败；也不要让本地日志扫描阻塞手动额度刷新。

## 架构

纯 SPM 多包架构，无 Xcode 工程。模块依赖方向单一：

```
Domain（零依赖）
├── Support（工具函数：日期解析、数字格式化、文件发现）
├── ProviderKit（Provider 描述符、能力定义）
├── ParserCore（各平台 JSONL/JSON 日志解析器）
├── Ingestion（数据导入协调、来源发现、去重）
├── Persistence（GRDB/SQLite，schema v3）
└── Query（Dashboard、趋势、来源健康度查询）
App (ExecutableTarget) — 依赖以上所有模块
```

## 支持的 Provider

| Provider | sourceID | 数据来源 | 额度查询 |
|----------|----------|----------|----------|
| Claude Code | claude-code | `~/.claude/projects/**/*.jsonl` | 官方 CLI 探测 + 第三方 API |
| Codex CLI | codex | `~/.codex/sessions/**/*.jsonl` | 官方 CLI 探测 + 第三方 API |
| OpenCode | opencode | `~/.local/share/opencode/storage/message/*.json` | 第三方 API |
| Gemini CLI | gemini | `~/.gemini/tmp/**/*session*.json` | 第三方 API |
| MiMo | mimo | 无本地日志（纯远程） | App 内官方网页登录 + `/api/v1/tokenPlan/usage`、`/api/v1/tokenPlan/detail` |

## 额度查询

三条路径：

1. **第三方 API（LaifuyouQuotaService）**：通过 endpointURL + apiKey 调用 `/quota-summary`，返回 5h/7d 额度窗口。支持 sub2api 等聚合平台。
2. **官方 CLI 探测（OfficialEntitlementProbe）**：shell 调用 `codex -s read-only` 或 `claude -p '/usage'`，解析 ANSI 输出中的百分比。当前仅 Claude Code 和 Codex。
3. **MiMo 官方网页登录（MiMoWebLoginView + MiMoQuotaService）**：App 内打开小米/MiMo 官方页面，用户在官方页面完成账号密码、验证码或风控校验；App 自动提取登录后的 `serviceToken` Cookie，存入 Keychain，再调用 `/api/v1/tokenPlan/usage` 返回套餐总 token 用量，并用 `/api/v1/tokenPlan/detail` 补充套餐到期时间。MiMo 没有 5h/week 限额，UI 将 `plan_total_token` 与 `compensation_total_token` 合并为一个 token-plan 总额度卡片，显示 used 百分比、到期时间和简短 token 明细；账户余额接口已调研但当前暂停，不请求 `/api/v1/balance`，也不展示余额卡。菜单栏 icon 始终按剩余额度展示：MiMo 使用合并 token-plan 剩余比例的单个 token tank，coding-plan provider 使用 5h/session 与 7d/week 双柱。后台刷新只复用已存 token，401 或缺 token 时提示重新登录，不用账号密码静默重试；网络失败时优先保留上次成功额度 snapshot 并标记 stale。

总览额度派生逻辑：显式配置优先，否则从可见 provider 中选择"风险最高"的（failed > stale > ready，使用率高的优先）。

## 刷新策略

- Usage 默认 TTL：10 分钟，触发本地日志增量导入和 Query read model 更新。
- Entitlement 默认 TTL：30 分钟，触发远程额度查询或 CLI 探测。
- 打开菜单和 app active 不做无条件刷新；后台 scheduler 只执行 `refreshIfStale`。
- 手动刷新全部数据可以调用组合入口；额度卡片上的刷新图标只刷新 entitlement，不跑本地 usage import。
- 初始化尚未加载 quota 时不显示“套餐额度暂不可用”大块占位；只有已完成刷新后缺登录态、401 或失败时才给紧凑反馈。

## 数据库

GRDB.swift (SQLite)，当前 schema v3：
- v1：sources、source_files、import_runs、usage_events、sessions、parser_diagnostics、daily_buckets
- v2：添加 request_count、request_semantic、request_confidence 字段
- v3：provider_accounts、account_refresh_runs、account_snapshots、allowance_windows、account_diagnostics

增量导入策略：`FileFingerprint.metadataSignature` 对比文件指纹，跳过未变更文件。

## 构建与发布

```bash
# 本地构建
./build.sh              # → dist/AiUsage.app
./build.sh --install    # 构建并安装到 /Applications
./build.sh --open       # 构建并打开

# 测试
swift test
swift test --filter ParserCoreTests

# 发布
# PR 合并到 main 自动触发 GitHub Actions：版本递增 → git tag → 构建 → zip/dmG → GitHub Release
```

## 性能

本地 token 统计采用增量计算：今日之前已计算的数据通过文件指纹缓存，只解析变更文件。

## 待办

1. **sub2api 分组聚合查询**：通过 API Key 查询分组下所有账号的综合余额（5h + week）。`LaifuyouQuotaService` 已有单账号查询基础，需扩展为分组维度。
2. **MiMo 平台余量查询**（官方网页登录态方案）
    - 调研文档：`docs/mimo-platform-research.md`
    - 认证方式：App 内官方网页登录 → serviceToken Cookie → Keychain → `GET /api/v1/tokenPlan/usage` + `GET /api/v1/tokenPlan/detail`
    - 支持多账号并行查询
3. **查询配置优化**：当前查询参数需要调整

## 规则

- **及时更新本文件**：项目架构、provider 支持状态、schema 版本等发生变化时同步更新
- **新增 Provider**：实现 `UsageParser` 协议 → 注册到 `StaticSourceRegistry` → 在 `ProviderBrandCatalog` 添加品牌
- **数据库 schema 变更**：在 `PersistenceMigrator` 注册新 migration，更新 `SchemaVersion`
- **版本号**：当前在 `build.sh` 的 `VERSION` 变量中管理，CI 自动同步到 git tag
