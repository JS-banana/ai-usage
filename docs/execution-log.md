# AiUsage Execution Log

## Project Location

正式项目目录：`/home/claw/projects/ai-usage-local`

Git remote:
- `origin = https://github.com/JS-banana/ai-usage-local.git`

## Current Working Principles

- 所有后续开发在正式目录进行，不再使用临时目录
- 优先进行工程基础重构，再继续堆功能
- 每一阶段先做设计校验，再做实现
- 解析器设计、持久化设计、测试设计必须同步推进

## Two-pass Global Thinking Summary

### Pass 1: Product / architecture
- 产品方向不变：纯本地、原生 macOS、主流工具优先
- 第一阶段不追求官方 quota，而追求本地 usage intelligence
- 主窗口 dashboard 优先于菜单栏/实时 watcher

### Pass 2: Engineering / execution
- 当前仓库是 prototype，不是 product-grade foundation
- 必须优先修正模块边界、稳定 ID、diagnostics、测试资源管理
- 下一步要落地 persistence 边界（SQLite/GRDB）和 import/query 分层

## Current Active Priorities

### P0
1. 模块结构重组
2. parser contract 升级
3. 稳定 ID / 时间解析错误治理
4. fixture 资源化与 parser contract tests

### P1
1. Persistence package 设计
2. ImportCoordinator / QueryService 分层
3. SQLite schema + migrations 设计文档

## Context Rules For Future Iterations

- 若修改 parser，必须同步更新 fixture/tests
- 若修改 domain model，必须先更新 implementation plan 或 design notes
- 若新增外部依赖，必须记录理由与替代方案
- 若因为当前 Linux 环境无法验证 macOS 行为，必须显式记录“未验证项”

## Validation Constraints

当前环境限制：
- 非 macOS
- 无 Swift toolchain
- 无 Xcode

因此当前阶段允许：
- 架构重构
- 文档与目录重组
- parser / domain / persistence 代码设计与静态修改
- 测试资源组织

当前阶段无法完成：
- 原生运行验证
- Xcode build 验证
- macOS UI/权限/沙盒验证
