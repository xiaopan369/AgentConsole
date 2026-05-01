# Agent Console

<p align="center">
  <strong>中文</strong> | <a href="./README.en.md">English</a>
</p>
<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift">
  <a href="https://github.com/xiaopan369/AgentConsole/releases">
    <img alt="Release" src="https://img.shields.io/github/v/release/xiaopan369/AgentConsole?label=release">
  </a>
  <a href="https://github.com/xiaopan369/AgentConsole/releases">
    <img alt="Downloads" src="https://img.shields.io/github/downloads/xiaopan369/AgentConsole/total?label=downloads">
  </a>
</p>


> 一个面向本地开发者的 macOS 交接控制台：把 Codex、Claude 等 Agent 之间最容易丢失的项目上下文、当前状态、待办事项和续接提示词整理成可持续维护的本地 handoff 工作流。

![Agent Console Demo](./docs/images/agent-console-demo.png)

## 痛点

在多个 AI 编程 Agent 之间切换时，最麻烦的往往不是写代码，而是让下一位 Agent 真正接上上一轮的上下文：

- 需要重复解释项目路径、当前目标、改过哪些文件、下一步要做什么。
- 聊天窗口一换，前一轮的决策、TODO、验证结果很容易断掉。
- 手动整理交接内容费时间，也容易漏掉用户最新要求。
- 新 Agent 不一定会先读项目和交接文件，容易凭空继续。

Agent Console 的目标很简单：把“切换 Agent”变成一个可重复、可检查、可回溯的动作。

## 功能

- 导入本地项目，并在项目内维护 `.agent-handoff` 交接目录。
- 自动维护 `PROJECT_CONTEXT.md`、`CONVERSATION_LOG.md`、`CURRENT_STATE.md`、`TODO.md`、`DECISIONS.md`、`CHANGELOG.md`、`OPEN_QUESTIONS.md`。
- 一键生成 Codex -> Claude / Claude -> Codex 的续接提示词。
- 切换时自动刷新项目快照和 handoff 文件。
- 要求目标 Agent 先返回“交接读取回执”，确认它读到了关键文件。
- 支持会话管理、归档、当前 Agent 状态、Git 状态摘要和最近同步时间。
- 全局工作台数据保存在 `~/AgentWorkspace`，项目交接数据保存在各项目自己的 `.agent-handoff` 中。

## 使用方法

1. 下载并打开 `AgentConsole.dmg`。
2. 将 `AgentConsole.app` 拖入 `Applications`。
3. 启动 Agent Console。
4. 点击“导入项目”，选择你要用 Codex / Claude 协作的本地项目目录。
5. 在 Agent Console 中确认当前会话和当前 Agent。
6. 点击“切换到 Claude”或“切换到 Codex”。
7. 将自动复制的续接提示词粘贴到目标 Agent 的新会话中。
8. 目标 Agent 读取 handoff 文件并回复交接读取回执后，就可以继续上一轮工作。

## 隐私说明

Agent Console 是本地 macOS 应用，不内置远程服务，也不会主动上传你的项目文件、会话内容或 handoff 数据。

全局工作台数据默认保存在 `~/AgentWorkspace`，项目交接数据保存在对应项目目录下的 `.agent-handoff` 中。

你粘贴到 Claude、Codex 或其他 Agent 的内容，将受对应服务自己的隐私政策约束。


## 常见问题排查

### macOS 提示“应用已损坏，无法打开”？

由于 macOS 的安全机制，非 App Store 下载的应用有时会触发这个提示。可以用下面两种方式处理：

**方案 1：命令行修复（推荐）**

打开“终端”，执行：

```bash
sudo xattr -rd com.apple.quarantine "/Applications/AgentConsole.app"
```

注意：如果你修改了应用名称或没有放到 `/Applications`，请相应调整命令里的路径。

**方案 2：系统设置中允许打开**

打开“系统设置” -> “隐私与安全性”，在安全提示区域点击“仍要打开”。

## 开发说明

```bash
swift build
Scripts/run-agent-console.sh
Scripts/run-tests.sh
Scripts/package-dmg.sh
```

## 致谢

本软件由 ChatGPT-5.5 开发。
