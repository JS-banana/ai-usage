# Refresh and Entitlement Architecture

AiUsage separates local usage statistics from remote entitlement or subscription state.

## Two Data Domains

**Usage domain**

- Sources: local files and history from Codex, Claude Code, OpenCode, Gemini, and similar agents.
- Pipeline: `SourceDiscovery` -> parser -> `ImportCoordinator` -> SQLite -> Query read models.
- Product question: how many tokens and requests were used on this machine?
- Refresh default: 10 minute TTL.

**Entitlement domain**

- Sources: official web login cookies, third-party quota APIs, or local CLI probes.
- Current providers: MiMo official web session, Laifuyou/sub2api-style quota bridge, Codex/Claude CLI probe.
- Product question: what quota or subscription allowance remains for an account or plan?
- Refresh default: 30 minute TTL.

These domains can be shown together, but failure in one domain must not erase the other.

## Refresh Flow

`AppState` owns user-visible refresh state:

- `lastUsageRefresh`
- `lastEntitlementRefresh`
- `usageRefreshState`
- `entitlementRefreshState`

`AppDataService` exposes separate operations:

- `refreshUsage`: run local import and rebuild usage read models.
- `refreshEntitlements`: resolve remote quota summaries from an existing usage snapshot.
- `refreshAll`: compose usage then entitlement refresh for explicit full refresh.
- `refreshIfStale`: apply the domain TTL rules before doing work.

The menu opening path must not call refresh directly. App startup and the background scheduler use `refreshIfStale`; the quota refresh icon calls entitlement refresh only.

## MiMo Rules

- The product path is official web login inside the app, then extraction of `serviceToken`, `userId`, `slh`, and `ph`.
- Background refresh only reuses the stored token.
- The app never silently retries username/password login in the background.
- `/api/v1/tokenPlan/usage` is the primary quota endpoint.
- `/api/v1/tokenPlan/detail` may provide expiry.
- `/api/v1/balance` remains intentionally paused.
- A successful MiMo quota response is persisted to schema v3 account snapshot tables.
- If a later MiMo refresh fails because of network, decoding, or server error, the UI may show the latest successful snapshot as stale.
- If MiMo returns 401 or no token exists, show a compact relogin-required state.

## Persistence

Schema v3 contains the entitlement snapshot surface:

- `provider_accounts`
- `account_refresh_runs`
- `account_snapshots`
- `allowance_windows`
- `account_diagnostics`

New entitlement providers should write account snapshots instead of inventing provider-specific cache files. Add a database migration only when the existing v3 tables cannot express the data.

