# MiMo 余量查询 — 开发计划

> 2026-05-31 更新：本文件记录的是早期 headless SSO 方案。实际产品路径已调整为 App 内官方网页登录 + 自动提取登录态；新的执行计划见 `docs/superpowers/plans/2026-05-31-mimo-official-web-login.md`。不要再把账号密码表单、后台自动重登、UserDefaults token 缓存作为产品方案推进。
> 2026-06-01 更新：MiMo 最终展示口径已改为合并 `plan_total_token + compensation_total_token` 的 token-plan 总额度卡片，并通过 `/tokenPlan/detail` 显示到期时间；`/balance` 已调研但当前暂停，不请求也不展示账户余额卡。
> 2026-06-03 更新：刷新架构已拆成本机 usage 和远程 entitlement 两套逻辑。MiMo 成功查询会写入 schema v3 account snapshot 表；后续网络/解码/服务端失败时可显示上次成功 snapshot 为 stale；401 或缺 token 仍提示重新登录，不做后台账号密码重登。

分支：`feature/mimo-quota-query`
方式：TDD（红-绿-重构）

---

## 总览

8 个阶段，每阶段独立可验证。依赖方向单一：Domain → Service → Integration → UI。

```
Phase 1: Domain 模型扩展（EntitlementSourceSelection + MiMo 凭据模型）
Phase 2: MiMo SSO 认证服务（MiMoSSOAuthService）
Phase 3: MiMo 余量查询服务（MiMoQuotaService）
Phase 4: 凭据存储扩展（EntitlementPreferences + Keychain）
Phase 5: 调度集成（EntitlementResolutionService）
Phase 6: Provider 注册（StaticSourceRegistry + ProviderBrandCatalog）
Phase 7: Settings UI（MiMo 配置界面）
Phase 8: 依赖注入（AppContainer）
```

---

## Phase 1: Domain 模型扩展

目标：让 `EntitlementSourceSelection` 支持 `.mimo`，让现有调度代码不编译失败。

### Step 1.1: 新增 `.mimo` case

文件：`App/Sources/AiUsage/Models/EntitlementModels.swift`

- `EntitlementSourceSelection` 新增 `case mimo`
- 确保 `allCases` 包含 `.mimo`

验证：`swift build` 编译通过（此时 .mimo 未被任何 switch 处理，会 warning 但不 error）。

### Step 1.2: 编写 EntitlementSourceSelection 测试

文件：`App/Tests/AiUsageTests/EntitlementSourceSelectionTests.swift`（新建）

测试用例：
- `.mimo.rawValue == "mimo"`
- `EntitlementSourceSelection(rawValue: "mimo") == .mimo`
- `allCases` 包含 `.mimo`

验证：`swift test --filter EntitlementSourceSelectionTests`

### Step 1.3: 新增 MiMo 凭据模型

文件：`App/Sources/AiUsage/Models/MiMoCredentials.swift`（新建）

```swift
struct MiMoCredentials: Hashable, Sendable {
    let username: String
    let passwordMD5: String  // 大写 MD5
}

struct MiMoServiceToken: Hashable, Sendable {
    let serviceToken: String
    let userId: String
    let slh: String
    let ph: String
    let acquiredAt: Date
    
    var isExpired: Bool { /* > 24h */ }
}
```

验证：`swift build`

---

## Phase 2: MiMo SSO 认证服务

目标：实现小米账号 SSO 4 步登录流程，完全可测试。

### Step 2.1: 编写 MiMoSSOAuthService 测试

文件：`App/Tests/AiUsageTests/MiMoSSOAuthServiceTests.swift`（新建）

用 `MockURLProtocol` 拦截 4 步 HTTP 请求：

测试用例：
1. **正常登录**：4 步依次返回预期响应 → 拿到正确的 serviceToken + userId
2. **密码错误**：step2 返回特定错误格式 → 抛出 `.invalidCredentials`
3. **网络错误**：任意 step 超时/失败 → 抛出 `.networkError`
4. **风控拦截**：step2 返回非预期格式 → 抛出 `.riskControl`
5. **clientSign 计算**：验证 nonce 和 ssecurity 的 SHA1 + base64 编码正确

验证：`swift test --filter MiMoSSOAuthServiceTests`（全部失败，符合预期）

### Step 2.2: 实现 MiMoSSOAuthService

文件：`App/Sources/AiUsage/Services/MiMoSSOAuthService.swift`（新建）

```swift
actor MiMoSSOAuthService {
    enum AuthError: Error {
        case invalidCredentials
        case riskControl
        case networkError(Error)
        case unexpectedResponse
    }
    
    func login(credentials: MiMoCredentials) async throws -> MiMoServiceToken
}
```

内部方法：
- `serviceLogin()` → (sign, qs, callback)
- `serviceLoginAuth2(user:hash:sign:qs:callback)` → (userId, passToken, ssecurity, location)
- `computeClientSign(ssecurity:)` → String
- `fetchServiceToken(location:clientSign:)` → MiMoServiceToken

关键实现细节：
- 密码哈希：`MD5(password).uppercased()`
- clientSign：`base64(sha1("nonce=<random>&<ssecurity>"))`
- URLSession 注入（init 参数，默认 .shared）

验证：`swift test --filter MiMoSSOAuthServiceTests` → 全部通过

---

## Phase 3: MiMo 余量查询服务

目标：用 serviceToken 调用 /tokenPlan/usage，映射为 EntitlementSummarySnapshot。

### Step 3.1: 编写 MiMoQuotaService 测试

文件：`App/Tests/AiUsageTests/MiMoQuotaServiceTests.swift`（新建）

用 `MockURLProtocol` 返回研究文档中的 JSON 响应。

测试用例：
1. **正常查询**：返回标准 JSON → 映射正确
   - `usage.plan_total_token + usage.compensation_total_token` → primaryWindow.progress
   - primaryWindow 左侧显示 used 百分比，右侧显示到期时间
   - 不请求 `/balance`，不显示账户余额补充卡片
2. **401 未授权**：HTTP 401 → 抛出 `.unauthorized`
3. **补偿额度为 0**：合并总额度 progress 只按基础套餐额度计算
4. **Cookie 构造**：验证请求 Cookie 格式正确
5. **stale 判定**：acquiredAt > 3600s → status == .stale

验证：`swift test --filter MiMoQuotaServiceTests`（全部失败）

### Step 3.2: 实现 MiMoQuotaService

文件：`App/Sources/AiUsage/Services/MiMoQuotaService.swift`（新建）

```swift
actor MiMoQuotaService {
    enum QuotaError: Error {
        case unauthorized
        case networkError(Error)
        case decodingError(Error)
    }
    
    func fetch(
        serviceToken: MiMoServiceToken,
        targetID: EntitlementTargetID,
        title: String,
        now: Date
    ) async throws -> EntitlementSummarySnapshot
}
```

内部结构：
- `MiMoUsageResponse`（Decodable）：code, data.monthUsage, data.usage
- `mapResponse(response:serviceToken:targetID:title:now:)` → EntitlementSummarySnapshot

窗口映射：
- primaryWindow: "套餐总额度" / `(plan.used + compensation.used) / (plan.limit + compensation.limit)` / 到期时间
- extraWindows: 当前不用于 MiMo 账户余额展示

验证：`swift test --filter MiMoQuotaServiceTests` → 全部通过

---

## Phase 4: 凭据存储扩展

目标：EntitlementPreferences 能存取 MiMo 凭据（Keychain）和 serviceToken（UserDefaults）。

### Step 4.1: 编写 EntitlementPreferences MiMo 测试

文件：`App/Tests/AiUsageTests/EntitlementPreferencesMiMoTests.swift`（新建）

测试用例：
1. `mimoCredentials` 初始返回 nil
2. `setMiMoCredentials` → `mimoCredentials` 返回正确值
3. `mimoServiceToken` 初始返回 nil
4. `setMiMoServiceToken` → `mimoServiceToken` 返回正确值
5. 覆盖写入：第二次 setMiMoCredentials 覆盖第一次
6. `mimoServiceToken(for:)` 按 targetID 隔离

验证：`swift test --filter EntitlementPreferencesMiMoTests`（全部失败）

### Step 4.2: 实现 EntitlementPreferences MiMo 扩展

文件：`App/Sources/AiUsage/Services/EntitlementPreferences.swift`（修改）

新增方法：

```swift
// Keychain 存取（使用 Security framework）
static func mimoCredentials(userDefaults:) -> MiMoCredentials?
static func setMiMoCredentials(_ creds: MiMoCredentials, userDefaults:)
static func clearMiMoCredentials(userDefaults:)

// UserDefaults 存取
static func mimoServiceToken(for targetID:, userDefaults:) -> MiMoServiceToken?
static func setMiMoServiceToken(_ token: MiMoServiceToken, for targetID:, userDefaults:)
static func clearMiMoServiceToken(for targetID:, userDefaults:)
```

Keychain 实现：
- 使用 `kSecClassGenericPassword`
- service: `"ai-usage.mimo"`, account: `"xiaomi-credentials"`
- 存储 JSON 编码的 `{username, passwordMD5}`

UserDefaults key 方案：
- `entitlement.target.mimo.serviceToken`
- `entitlement.target.mimo.userId`
- `entitlement.target.mimo.tokenAcquiredAt`

验证：`swift test --filter EntitlementPreferencesMiMoTests` → 全部通过

---

## Phase 5: 调度集成

目标：EntitlementResolutionService 在 `.mimo` 分支调用 MiMoQuotaService。

### Step 5.1: 编写调度测试

文件：`App/Tests/AiUsageTests/EntitlementResolutionMiMoTests.swift`（新建）

测试用例：
1. `.mimo` 配置 + 有效凭据 + serviceToken 未过期 → 直接调用 MiMoQuotaService
2. `.mimo` 配置 + 有效凭据 + serviceToken 过期 → 先调 MiMoSSOAuthService.login 再查
3. `.mimo` 配置 + serviceToken 401 → 自动重登一次
4. `.mimo` 配置 + 无凭据 → 返回 .unconfigured
5. `.mimo` 配置 + 登录失败 → 返回 .failed

验证：`swift test --filter EntitlementResolutionMiMoTests`（全部失败）

### Step 5.2: 修改 EntitlementResolutionService

文件：`App/Sources/AiUsage/Services/EntitlementResolutionService.swift`

- init 新增 `mimoAuth: MiMoSSOAuthService` 和 `mimoQuota: MiMoQuotaService`
- `resolveSummary` 新增 `.mimo` case：
  ```
  .mimo:
    读取凭据 → 无则 return unconfigured
    读取 serviceToken → 过期或 nil → 重新登录
    调用 mimoQuota.fetch → 失败且 401 → 重登一次 → 再查
  ```

验证：`swift test --filter EntitlementResolutionMiMoTests` → 全部通过

---

## Phase 6: Provider 注册

目标：MiMo 作为 provider 出现在 provider 列表和品牌目录中。

### Step 6.1: 修改 StaticSourceRegistry

文件：`Packages/Ingestion/Sources/Ingestion/SourceRegistry.swift`

- 新增 mimo provider descriptor（无 parser，纯远程）：
  - capabilities: `[.accountQuotaSnapshots]`
  - backendKind: `.remoteAPI`
  - credentialKind: `.accountSession`

### Step 6.2: 修改 SourceRegistryTests

文件：`Packages/Ingestion/Tests/IngestionTests/SourceRegistryTests.swift`

新增测试：
- mimo provider 存在于 `providerDescriptors()`
- mimo capabilities 包含 `.accountQuotaSnapshots`
- mimo backendKind == `.remoteAPI`

验证：`swift test --filter SourceRegistryTests`

### Step 6.3: 修改 ProviderBrandCatalog

文件：`App/Sources/AiUsage/Models/ProviderBrandCatalog.swift`

新增 `mimo` 品牌：
- accent: `.mimo`（需在 ProviderTabBranding 中新增 case）
- color: 橙色系 (255/255, 103/255, 0/255) — 小米品牌橙
- logo: nil（用 fallback monogram "M"）

### Step 6.4: 修改 EntitlementPreferences.supportsOfficialSource

文件：`App/Sources/AiUsage/Services/EntitlementPreferences.swift`

`supportsOfficialSource(for:)` 中对 `.provider("mimo")` 返回 false（MiMo 不支持官方 CLI 探测）。

验证：`swift build` + `swift test`

---

## Phase 7: Settings UI

目标：设置页显示 MiMo 配置区域，支持账号密码输入。

### Step 7.1: 修改 SettingsView

文件：`App/Sources/AiUsage/Views/SettingsView.swift`

为 MiMo provider 渲染专属配置 UI：
- segmented picker 增加 "小米账号" 选项（仅 mimo provider 显示）
- 选中后显示：
  - `TextField("小米账号")` → `EntitlementPreferences.setMiMoCredentials`
  - `SecureField("密码")` → 存入 Keychain
  - 说明文字："登录后 serviceToken 自动缓存，过期自动刷新"
  - "立即刷新" 按钮

### Step 7.2: 手动验证

- 启动 App → 设置 → 找到 MiMo
- 输入凭据 → 刷新 → 观察是否拿到用量数据
- 检查菜单栏是否正确显示 MiMo 余量

验证：手动截图确认 UI 正确。

---

## Phase 8: 依赖注入

目标：AppContainer 把新 service 注入到系统中。

### Step 8.1: 修改 AppContainer

文件：`App/Sources/AiUsage/AppContainer/AppContainer.swift`

- `AppContainer.live()` 新增：
  ```swift
  let mimoAuth = MiMoSSOAuthService()
  let mimoQuota = MiMoQuotaService()
  ```
- 传入 `EntitlementResolutionService` init

验证：`swift build` + 完整流程测试

---

## 每阶段产出

| Phase | 产出文件 | 测试文件 | 验证命令 |
|-------|----------|----------|----------|
| 1 | EntitlementModels.swift, MiMoCredentials.swift | EntitlementSourceSelectionTests.swift | `swift test --filter EntitlementSourceSelection` |
| 2 | MiMoSSOAuthService.swift | MiMoSSOAuthServiceTests.swift | `swift test --filter MiMoSSOAuth` |
| 3 | MiMoQuotaService.swift | MiMoQuotaServiceTests.swift | `swift test --filter MiMoQuota` |
| 4 | EntitlementPreferences.swift (修改) | EntitlementPreferencesMiMoTests.swift | `swift test --filter EntitlementPreferencesMiMo` |
| 5 | EntitlementResolutionService.swift (修改) | EntitlementResolutionMiMoTests.swift | `swift test --filter EntitlementResolutionMiMo` |
| 6 | SourceRegistry.swift, ProviderBrandCatalog.swift | SourceRegistryTests.swift (修改) | `swift test --filter SourceRegistry` |
| 7 | SettingsView.swift (修改) | 手动测试 | 截图验证 |
| 8 | AppContainer.swift (修改) | `swift build` + 全量测试 | `swift test` |
