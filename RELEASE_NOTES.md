# AppShot v0.1.1

## English

AppShot v0.1.1 focuses on making the Mac release installable end to end:

- Release packages now include `AppShot.app`, the `appshot` CLI, and MCP server files.
- The curl installer installs the app, CLI, MCP server, and Codex skill.
- The Codex skill bootstraps AppShot when the local CLI is missing.
- Permission reset is available with `APPSHOT_RESET_PERMISSIONS=1` for broken development TCC states.
- Accessibility remains the primary text path; OCR is explicit fallback only.

## 中文

AppShot v0.1.1 的重点是把 Mac 发布包补成完整可安装形态：

- Release 包现在包含 `AppShot.app`、`appshot` CLI 和 MCP server 文件。
- curl 安装器会安装 App、CLI、MCP server 和 Codex skill。
- Codex skill 会在本地缺少 CLI 时自动引导安装 AppShot。
- 开发阶段权限状态损坏时，可以用 `APPSHOT_RESET_PERMISSIONS=1` 重置 TCC 授权记录。
- Accessibility 仍然是主文本路径，OCR 只作为显式兜底能力。

# AppShot v0.1.0

## English

AppShot gives any AI a Codex-style app screenshot capability on macOS. It captures the frontmost application as structured context: app metadata, visible windows, primary window bounds/title, accessibility tree text, and optional screenshots.

This release is built for Mac users:

- Native macOS app with a dashboard and menu bar entry.
- Swift CLI: `appshot`.
- MCP server for AI tools.
- Codex skill and plugin scaffold.
- Non-blocking capture path with Accessibility and screenshot timeouts.

Notes:

- Accessibility permission is required for rich UI/text trees.
- Screen Recording permission is required for screenshots.
- Window parsing will continue to be improved against the local Codex Mac App diff evidence, rather than guessed from scratch.

## 中文

AppShot 让任何 AI 都拥有 Codex 样式的应用截图能力。它可以把当前前台 App 捕捉成结构化上下文：App 元数据、可见窗口、主窗口位置和标题、Accessibility 文本/UI 树，以及可选截图。

这个版本专门面向 Mac 用户发布：

- 原生 macOS App，带状态面板和菜单栏入口。
- Swift CLI：`appshot`。
- 面向 AI 工具的 MCP server。
- Codex skill 和 plugin 脚手架。
- 捕捉流程已改为非阻塞，并为 Accessibility 和截图增加超时，降低卡死风险。

注意：

- 完整 UI/文本树需要开启辅助功能权限。
- 截图需要开启屏幕录制权限。
- 后续窗口解析会严格对照本地 diff 出来的 Codex Mac App 证据继续补齐，不凭空猜实现。
