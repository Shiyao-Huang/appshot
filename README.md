# AppShot

## English

AppShot gives any AI a Codex-style app screenshot capability on macOS.

It captures the frontmost Mac application as structured context: app metadata, visible windows, primary window geometry/title, Accessibility text/UI tree, and optional screenshots. The project ships as a native macOS app first, with CLI, MCP, Codex skill, and plugin support as secondary integration layers.

### What Is Included

- Native macOS app: status dashboard, permission state, capture actions, and menu bar entry.
- Swift CLI: `appshot`.
- MCP server: `mcp/server.js`.
- Codex skill: `skills/appshot/SKILL.md`.
- Codex plugin manifest: `.codex-plugin/plugin.json`.
- Release packaging for Mac users: `.app`, `.zip`, and `.dmg`.

### Build And Run

```sh
swift build
swift scripts/generate_app_icon.swift
xcodebuild -project AppShot.xcodeproj -scheme AppShot -configuration Release build
```

For a complete local release package:

```sh
chmod +x scripts/build_release.sh
scripts/build_release.sh 0.1.0
open dist/AppShot.app
```

CLI examples:

```sh
.build/debug/appshot status --pretty
.build/debug/appshot permissions --prompt --pretty
.build/debug/appshot capture --pretty
.build/debug/appshot capture --include-screenshot --screenshot appshot.png --output appshot.json --pretty
```

### Permissions

Accessibility permission is required for rich UI/text trees. Screen Recording permission is required for screenshots. On macOS, permissions belong to the launched app identity, so run `dist/AppShot.app` when granting AppShot permissions.

### Implementation Note

The first release uses public macOS APIs. Window parsing will continue to be refined against the locally diffed Codex Mac App evidence, rather than guessed from scratch.

## 中文

AppShot 让任何 AI 都拥有 Codex 样式的应用截图能力。

它会把当前前台 Mac 应用捕捉成结构化上下文：App 元数据、可见窗口、主窗口几何信息和标题、Accessibility 文本/UI 树，以及可选截图。项目以原生 macOS App 为核心发布，同时支持 CLI、MCP、Codex skill 和 plugin。

### 包含内容

- 原生 macOS App：状态面板、权限状态、捕捉操作、菜单栏入口。
- Swift CLI：`appshot`。
- MCP server：`mcp/server.js`。
- Codex skill：`skills/appshot/SKILL.md`。
- Codex plugin manifest：`.codex-plugin/plugin.json`。
- 面向 Mac 用户的 release 包：`.app`、`.zip`、`.dmg`。

### 构建和运行

```sh
swift build
swift scripts/generate_app_icon.swift
xcodebuild -project AppShot.xcodeproj -scheme AppShot -configuration Release build
```

完整生成本地发布包：

```sh
chmod +x scripts/build_release.sh
scripts/build_release.sh 0.1.0
open dist/AppShot.app
```

CLI 示例：

```sh
.build/debug/appshot status --pretty
.build/debug/appshot permissions --prompt --pretty
.build/debug/appshot capture --pretty
.build/debug/appshot capture --include-screenshot --screenshot appshot.png --output appshot.json --pretty
```

### 权限

完整 UI/文本树需要辅助功能权限。截图需要屏幕录制权限。在 macOS 上，权限归属于启动的 App 身份，所以授权时请运行 `dist/AppShot.app`，不要只跑 SwiftPM 里的 CLI 可执行文件。

### 实现说明

首个版本使用公开 macOS API。后续窗口解析会严格对照本地 diff 出来的 Codex Mac App 证据继续补齐，不凭空猜实现。

