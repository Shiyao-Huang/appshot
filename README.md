# AppShot

## English

AppShot gives any AI a Codex-style app screenshot capability on macOS.

It captures the frontmost Mac application as structured context: app metadata, visible windows, primary window geometry/title, Accessibility text/UI tree, focused element text, and optional screenshots. OCR is available only as an explicit fallback. The project ships as a native macOS app first, with CLI, MCP, Codex skill, and plugin support as secondary integration layers.

### Install

```sh
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | bash
```

By default this installs `AppShot.app` to `~/Applications/AppShot.app`, the `appshot` CLI to `~/.local/bin/appshot`, the MCP server to `~/.local/share/appshot/mcp`, and the Codex skill to `~/.codex/skills/appshot`.

Options:

```sh
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | APPSHOT_INSTALL_DIR=/Applications bash
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | APPSHOT_SKILL_ONLY=1 bash
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | APPSHOT_NO_OPEN=1 bash
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | APPSHOT_RESET_PERMISSIONS=1 bash
```

### What Is Included

- Native macOS app: status dashboard, permission state, capture actions, menu bar entry, and front-app auto-refresh trail with deduped samples.
- Swift CLI: `appshot`.
- MCP server: `mcp/server.js`.
- Codex skill: `skills/appshot/SKILL.md`.
- Codex plugin manifest: `.codex-plugin/plugin.json`.
- Release packaging for Mac users: `.app`, `.zip`, and `.dmg`.

### Build And Run

In Xcode, open `AppShot.xcodeproj`, select the `AppShot` scheme, and run the app target. Do not run `install.sh` from Xcode; it is a Terminal/curl installer and is not a build target.

```sh
swift build
swift scripts/generate_app_icon.swift
xcodebuild -project AppShot.xcodeproj -scheme AppShot -configuration Release build
```

For a complete local release package:

```sh
chmod +x scripts/build_release.sh
scripts/build_release.sh 0.1.1
open dist/AppShot-macOS-0.1.1/AppShot.app
```

CLI examples:

```sh
.build/debug/appshot status --pretty
.build/debug/appshot permissions --prompt --pretty
.build/debug/appshot capture --pretty
.build/debug/appshot capture --include-screenshot --screenshot appshot.png --output appshot.json --pretty
.build/debug/appshot capture --include-ocr --screenshot appshot.png --output appshot.json --pretty
```

### Permissions

Accessibility permission is required for rich UI/text trees and is AppShot's primary text path. Screen Recording permission is required for screenshots and OCR. OCR is a fallback for apps that do not expose visible content through Accessibility. On macOS, permissions belong to the launched app identity, so run `dist/AppShot.app` when granting AppShot permissions.

### Implementation Note

The first release uses public macOS APIs. Window parsing will continue to be refined against the locally diffed Codex Mac App evidence, rather than guessed from scratch.

## 中文

AppShot 让任何 AI 都拥有 Codex 样式的应用截图能力。

它会把当前前台 Mac 应用捕捉成结构化上下文：App 元数据、可见窗口、主窗口几何信息和标题、Accessibility 文本/UI 树、焦点元素文本，以及可选截图。OCR 只作为显式兜底能力。项目以原生 macOS App 为核心发布，同时支持 CLI、MCP、Codex skill 和 plugin。

### 安装

```sh
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | bash
```

默认会把 `AppShot.app` 安装到 `~/Applications/AppShot.app`，把 `appshot` CLI 安装到 `~/.local/bin/appshot`，把 MCP server 安装到 `~/.local/share/appshot/mcp`，并把 Codex skill 安装到 `~/.codex/skills/appshot`。

可选参数：

```sh
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | APPSHOT_INSTALL_DIR=/Applications bash
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | APPSHOT_SKILL_ONLY=1 bash
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | APPSHOT_NO_OPEN=1 bash
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | APPSHOT_RESET_PERMISSIONS=1 bash
```

### 包含内容

- 原生 macOS App：状态面板、权限状态、捕捉操作、菜单栏入口，以及带重复抑制的前台 App 自动刷新轨迹。
- Swift CLI：`appshot`。
- MCP server：`mcp/server.js`。
- Codex skill：`skills/appshot/SKILL.md`。
- Codex plugin manifest：`.codex-plugin/plugin.json`。
- 面向 Mac 用户的 release 包：`.app`、`.zip`、`.dmg`。

### 构建和运行

在 Xcode 里打开 `AppShot.xcodeproj`，选择 `AppShot` scheme，然后运行 App target。不要在 Xcode 里运行 `install.sh`；它是给 Terminal/curl 使用的安装脚本，不是构建 target。

```sh
swift build
swift scripts/generate_app_icon.swift
xcodebuild -project AppShot.xcodeproj -scheme AppShot -configuration Release build
```

完整生成本地发布包：

```sh
chmod +x scripts/build_release.sh
scripts/build_release.sh 0.1.1
open dist/AppShot-macOS-0.1.1/AppShot.app
```

CLI 示例：

```sh
.build/debug/appshot status --pretty
.build/debug/appshot permissions --prompt --pretty
.build/debug/appshot capture --pretty
.build/debug/appshot capture --include-screenshot --screenshot appshot.png --output appshot.json --pretty
.build/debug/appshot capture --include-ocr --screenshot appshot.png --output appshot.json --pretty
```

### 权限

完整 UI/文本树需要辅助功能权限，这是 AppShot 的主文本路径。截图和 OCR 需要屏幕录制权限。当 App 没有通过 Accessibility 暴露正文时，OCR 才作为兜底从可见像素里恢复文字。在 macOS 上，权限归属于启动的 App 身份，所以授权时请运行 `dist/AppShot.app`，不要只跑 SwiftPM 里的 CLI 可执行文件。

### 实现说明

首个版本使用公开 macOS API。后续窗口解析会严格对照本地 diff 出来的 Codex Mac App 证据继续补齐，不凭空猜实现。
