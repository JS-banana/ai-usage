<h1 align="center">AiUsage</h1>

<p align="center">
  <strong>一个放在 macOS 菜单栏里的 AI usage 查看器。</strong>
</p>

<p align="center">
  用最直接的方式，把你常用 AI coding agent 的 usage 和额度状态收拢到一起。
</p>

## 它是做什么的

AiUsage 是本地优先的，不会替你托管账号，也不会替你保存线上服务的真实凭证。

它不会替代你原本在用的 Claude Code、Codex CLI、OpenCode、Gemini CLI，  
只是把这些工具里的 usage 信息集中展示出来，让你不用来回切着看。

## 现在支持

- Claude Code
- Codex CLI
- OpenCode
- Gemini CLI

## 你能看到什么

- 今天用了多少
- 本周用了多少
- 请求次数
- Cached tokens
- 套餐额度状态

## 安装

如果 macOS 提示 `“AiUsage”已损坏，无法打开`，执行：

```bash
xattr -rd com.apple.quarantine /Applications/AiUsage.app
```
