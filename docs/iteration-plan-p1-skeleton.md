# Iteration Plan — P1 Code Skeleton

## Goal

在当前无 macOS / 无 Swift toolchain 的环境中，安全推进下一轮代码开发，优先把**未来会稳定存在的边界层**落地到代码结构里，而不是冒进实现无法验证的 GRDB/macOS 细节。

## Global Thinking Results

### Pass 1
- 当前最缺的不是更多 parser，而是 `Persistence` / `Ingestion` / `Query` 的边界骨架。
- 如果不先把边界落下来，后续在本地 Mac 上接 SQLite/GRDB 会持续返工。

### Pass 2
- 当前环境最适合写：
  - package/target 拆分
  - protocol / DTO / coordinator skeleton
  - schema/version/table 常量
  - handoff / validation docs
- 当前环境不适合写：
  - GRDB 真实实现
  - Xcode/macOS 工程细节
  - 实际运行验证

## This Iteration Scope

### Will Implement Now
1. 新增 `Persistence` package skeleton
2. 新增 `Ingestion` package skeleton
3. 新增 `Query` package skeleton
4. 在 `Domain` 中补充 import/source 等中立模型
5. 更新 `Package.swift`
6. 编写本地 Mac/Xcode 验证交接文档

### Will Explicitly Defer
1. GRDB dependency 接入
2. SQLite migrations 真正实现
3. DatabaseManager 真正实现
4. Xcode app project
5. menu bar / watcher / sandbox

## Design Rule

所有本轮新增代码应满足：
- 不依赖 macOS-only runtime 行为
- 不依赖未安装的 Swift package 依赖
- 只落稳定接口，不落高风险细节实现
- 未来在本地 Mac 上接入时尽量零返工
