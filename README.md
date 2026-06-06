# AppShot

## English

AppShot gives any AI a Codex-style App Shot capability on macOS, and lets Claude Code use the same App Shot ability that Codex has.

It captures the frontmost Mac application as structured context: app metadata, visible windows, primary window geometry/title, Accessibility text/UI tree, focused element text, and optional screenshots. OCR is available only as an explicit fallback. The project ships as a native macOS app first, with CLI, MCP, Codex skill, Claude Code skill, and plugin support as integration layers.

### Install

```sh
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | bash
```

By default this installs `AppShot.app` to `~/Applications/AppShot.app`, the `appshot` CLI to `~/.local/bin/appshot`, the MCP server to `~/.local/share/appshot/mcp`, and the Codex skill to `~/.codex/skills/appshot`.

To let Claude Code use Codex-style App Shot, install the Claude Code skill and MCP registration too:

```sh
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | APPSHOT_INSTALL_CLAUDE_CODE=1 bash
```

Options:

```sh
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | APPSHOT_INSTALL_DIR=/Applications bash
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | APPSHOT_SKILL_ONLY=1 bash
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | APPSHOT_NO_OPEN=1 bash
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | APPSHOT_RESET_PERMISSIONS=1 bash
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | APPSHOT_INSTALL_CLAUDE_CODE=1 bash
```

### What Is Included

- Native macOS app: status dashboard, permission state, capture actions, menu bar entry, and front-app auto-refresh trail with deduped samples.
- Swift CLI: `appshot`.
- MCP server: `mcp/server.js`.
- Codex skill: `skills/appshot/SKILL.md`.
- Codex plugin manifest: `.codex-plugin/plugin.json`.
- Release packaging for Mac users: `.app`, `.zip`, and `.dmg`.
- Claude Code App Shot support via `APPSHOT_INSTALL_CLAUDE_CODE=1`, which installs the AppShot skill and MCP server registration.
- Global shortcut setting, enabled by default with both left and right Option keys.
- Shared shortcut cache: left+right Option writes the latest capture so CLI/MCP can return it immediately; use `--ignore-cache`, `--no-cache`, or `--fresh` for a direct capture.
- Codex browser-comment payload adapter: JSON captures include `codexBrowserPayload` with `localBrowserContext`, `localBrowserCommentMetadata`, `localBrowserAttachedImages`, `localBrowserDesignChange`, and `localBrowserScreenshot` field names for Codex/Claude consumers.
- Codex browser screenshot policy: `--browser-annotation-screenshots-mode always|necessary`, MCP `browserAnnotationScreenshotsMode`, and App Settings `Browser Screenshots` write `browser-annotation-screenshots-mode` into `codexBrowserSettings`; `always` captures a screenshot for `codexBrowserPayload` by default.
- Codex browser runtime state adapter: JSON captures include `codexBrowserRuntimeState` with Codex `browser-sidebar-runtime-sync` field names such as `interactionMode`, `annotationEditorMode`, `isOriginalViewEnabled`, `isDesignModifierPressed`, `isTweaksEditorOpen`, and `activeDesignChange`.
- Browser DOM integration: `--include-browser-dom`, MCP `includeBrowserDOM`, and App Settings `Browser DOM` run a timed, read-only Safari/Chrome DOM probe when Apple Events allows it, producing `codexBrowserDOMIntegration.browserRuntimeEvents` with image-drag `sourceUrl` and design-editor `anchorState` / `designEditorState` candidates.

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
scripts/build_release.sh 0.1.6
open dist/AppShot-macOS-0.1.6/AppShot.app
```

For a public macOS release, sign with a `Developer ID Application` identity and notarize the DMG:

```sh
APPSHOT_PUBLIC_RELEASE=1 \
APPSHOT_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APPSHOT_NOTARY_PROFILE="appshot-notary" \
scripts/build_release.sh 0.1.6
```

The public release path refuses Apple Development or ad-hoc signatures, submits the DMG to Apple notarization, staples the ticket, and runs Gatekeeper assessment.

CLI examples:

```sh
.build/debug/appshot status --pretty
.build/debug/appshot permissions --prompt --pretty
.build/debug/appshot capture --pretty
.build/debug/appshot capture --include-screenshot --screenshot appshot.png --output appshot.json --pretty
.build/debug/appshot capture --include-ocr --screenshot appshot.png --output appshot.json --pretty
```

Codex parity check:

```sh
scripts/verify_codex_parity.sh
```

This builds the Swift CLI and native `AppShot.app`, checks bundle identity/version, verifies Codex-style JSON aliases, and runs MCP smoke tests. See `docs/codex-parity.md` for the evidence-backed parity matrix.

App/window QA example:

```sh
scripts/qa_app_capture.py --bundle-id com.apple.dt.Xcode --window-title 'appshot —' --accessibility-timeout 20 --expect-hierarchy 'Source Editor'
```

Accessibility output includes both `accessibility.text` for full AX/document text and `accessibility.visibleText` for coordinate-sorted visible UI text. When a large text control exposes `AXBoundsForRange`, AppShot uses line fragments so editor/body text can join the visible reading stream.

JSON capture output also includes `codexBrowserPayload`, a native AppShot adapter for Codex browser-comment payload fields. It maps app/window/AX/screenshot evidence into the same `localBrowser*` names Codex uses, without claiming AppShot implements Codex's embedded browser design editor or image-drag runtime. Use `--browser-annotation-screenshots-mode always` when a Codex/Claude consumer should receive a `localBrowserScreenshot` by default.

For Codex browser runtime-state parity, JSON capture includes `codexBrowserRuntimeState` and mirrors `activeDesignChange` into `codexBrowserPayload.localBrowserDesignChange`. CLI and MCP calls can set those adapter fields with options such as `--browser-annotation-editor-mode design`, `--browser-original-view-enabled`, `--browser-design-modifier-pressed`, `--browser-tweaks-editor-open`, and `--browser-active-design-change-json '{"id":"design","declarations":[]}'`. This is a native adapter surface for Codex/Claude consumers; it does not run Codex's embedded browser DOM/preload design editor or image-drag instrumentation.

For supported frontmost browser apps, `--include-browser-dom` adds `codexBrowserDOMIntegration`. It uses a short-timeout Apple Events JavaScript probe for Safari and Chromium-style browsers to read page images and design target candidates, then emits Codex runtime event-shaped entries such as `browser-sidebar-runtime-image-drag-started`, `browser-sidebar-runtime-image-drag-ended`, and `browser-sidebar-runtime-open-design-editor`. If Apple Events scripting is unavailable, blocked, or times out, the capture returns `available: false` with a reason instead of hanging.

### Permissions

Accessibility permission is required for rich UI/text trees and is AppShot's primary text path. Screen Recording permission is required for screenshots and OCR. OCR is a fallback for apps that do not expose visible content through Accessibility. On macOS, permissions belong to the launched app identity, so run the installed `AppShot.app` when granting AppShot permissions.

The global shortcut is enabled by default: press the left and right Option keys together to capture the current app. You can turn it off from AppShot Settings.

Shortcut captures are written to a shared recent cache. CLI and MCP captures read that cache by default when no explicit target is passed; add `--ignore-cache`, `--no-cache`, or `--fresh` when you need a direct current-window capture.

If macOS shows AppShot as enabled in Privacy & Security but AppShot still reports missing permission, check identity drift:

```sh
scripts/diagnose_tcc_identity.sh
```

Xcode Debug builds, installed release builds, and SwiftPM CLI binaries can have the same visible name but different code-signing identities. Ad-hoc signed builds are especially fragile because a rebuild can change the `CDHash`, making TCC treat it as a different app. For stable development/release permissions, keep using one installed app identity or build with a stable signing identity via `APPSHOT_CODESIGN_IDENTITY`.

To recover from a stale Privacy & Security entry, reset the old TCC rows once, open the exact installed app, and grant permissions again:

```sh
tccutil reset Accessibility com.qppshot.AppShot
tccutil reset ScreenCapture com.qppshot.AppShot
open ~/Applications/AppShot.app
```

### Implementation Note

The first release uses public macOS APIs. Window parsing will continue to be refined against the locally diffed Codex Mac App evidence, rather than guessed from scratch.

## 中文

AppShot 让任何 AI 都拥有 Codex 样式的 App Shot 能力，并让 Claude Code 也拥有和 Codex 一样的 App Shot 能力。

它会把当前前台 Mac 应用捕捉成结构化上下文：App 元数据、可见窗口、主窗口几何信息和标题、Accessibility 文本/UI 树、焦点元素文本，以及可选截图。OCR 只作为显式兜底能力。项目以原生 macOS App 为核心发布，同时支持 CLI、MCP、Codex skill、Claude Code skill 和 plugin。

### 安装

```sh
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | bash
```

默认会把 `AppShot.app` 安装到 `~/Applications/AppShot.app`，把 `appshot` CLI 安装到 `~/.local/bin/appshot`，把 MCP server 安装到 `~/.local/share/appshot/mcp`，并把 Codex skill 安装到 `~/.codex/skills/appshot`。

如果要让 Claude Code 使用 Codex 样式的 App Shot，同时安装 Claude Code skill 和 MCP 注册：

```sh
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | APPSHOT_INSTALL_CLAUDE_CODE=1 bash
```

可选参数：

```sh
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | APPSHOT_INSTALL_DIR=/Applications bash
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | APPSHOT_SKILL_ONLY=1 bash
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | APPSHOT_NO_OPEN=1 bash
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | APPSHOT_RESET_PERMISSIONS=1 bash
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | APPSHOT_INSTALL_CLAUDE_CODE=1 bash
```

### 包含内容

- 原生 macOS App：状态面板、权限状态、捕捉操作、菜单栏入口，以及带重复抑制的前台 App 自动刷新轨迹。
- Swift CLI：`appshot`。
- MCP server：`mcp/server.js`。
- Codex skill：`skills/appshot/SKILL.md`。
- Codex plugin manifest：`.codex-plugin/plugin.json`。
- 面向 Mac 用户的 release 包：`.app`、`.zip`、`.dmg`。
- 通过 `APPSHOT_INSTALL_CLAUDE_CODE=1` 给 Claude Code 安装 AppShot skill 和 MCP 注册，让 Claude Code 拥有 Codex 风格的 App Shot 能力。
- 全局快捷键设置，默认使用左 Option + 右 Option。
- 共享快捷键缓存：左 Option + 右 Option 会写入最近一次捕捉，CLI/MCP 可以立即读取；需要直接重新捕捉时使用 `--ignore-cache`、`--no-cache` 或 `--fresh`。
- Codex browser-comment payload adapter：JSON capture 会包含 `codexBrowserPayload`，内部使用 `localBrowserContext`、`localBrowserCommentMetadata`、`localBrowserAttachedImages`、`localBrowserDesignChange`、`localBrowserScreenshot` 这些 Codex/Claude 消费侧字段名。
- Codex browser screenshot policy：`--browser-annotation-screenshots-mode always|necessary`、MCP `browserAnnotationScreenshotsMode`、App Settings `Browser Screenshots` 会把 `browser-annotation-screenshots-mode` 写入 `codexBrowserSettings`；`always` 会默认给 `codexBrowserPayload` 捕捉截图。
- Codex browser runtime state adapter：JSON capture 会包含 `codexBrowserRuntimeState`，使用 Codex `browser-sidebar-runtime-sync` 同名字段，例如 `interactionMode`、`annotationEditorMode`、`isOriginalViewEnabled`、`isDesignModifierPressed`、`isTweaksEditorOpen`、`activeDesignChange`。
- Browser DOM integration：`--include-browser-dom`、MCP `includeBrowserDOM`、App Settings `Browser DOM` 会在 Apple Events 允许时，对 Safari/Chrome 做带超时的只读 DOM probe，生成 `codexBrowserDOMIntegration.browserRuntimeEvents`，包含 image-drag `sourceUrl` 和 design-editor `anchorState` / `designEditorState` 候选。

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
scripts/build_release.sh 0.1.6
open dist/AppShot-macOS-0.1.6/AppShot.app
```

公开 macOS 发布包需要 `Developer ID Application` 证书并完成 DMG 公证：

```sh
APPSHOT_PUBLIC_RELEASE=1 \
APPSHOT_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APPSHOT_NOTARY_PROFILE="appshot-notary" \
scripts/build_release.sh 0.1.6
```

公开发布路径会拒绝 Apple Development 或 ad-hoc 签名，提交 Apple notarization，staple 公证票据，并运行 Gatekeeper 校验。

CLI 示例：

```sh
.build/debug/appshot status --pretty
.build/debug/appshot permissions --prompt --pretty
.build/debug/appshot capture --pretty
.build/debug/appshot capture --include-screenshot --screenshot appshot.png --output appshot.json --pretty
.build/debug/appshot capture --include-ocr --screenshot appshot.png --output appshot.json --pretty
```

Codex 一致性检查：

```sh
scripts/verify_codex_parity.sh
```

这个脚本会构建 Swift CLI 和原生 `AppShot.app`，检查 bundle 身份和版本，验证 Codex 风格 JSON 别名，并运行 MCP smoke test。证据化的一致性矩阵见 `docs/codex-parity.md`。

App/window QA 示例：

```sh
scripts/qa_app_capture.py --bundle-id com.apple.dt.Xcode --window-title 'appshot —' --accessibility-timeout 20 --expect-hierarchy 'Source Editor'
```

Accessibility 输出同时包含完整 AX/document 文本 `accessibility.text`，以及按坐标排序的可见 UI 文本 `accessibility.visibleText`。当大块文本控件暴露 `AXBoundsForRange` 时，AppShot 会使用行级片段，让编辑器/正文文本也进入可见阅读流。

JSON capture 还会包含 `codexBrowserPayload`，这是 AppShot 原生捕捉到 Codex browser-comment payload 字段的适配层。它会把 App/window/AX/screenshot 证据映射到 Codex 使用的 `localBrowser*` 字段名，但不声称 AppShot 已经实现 Codex 内置浏览器的 design editor 或 image-drag runtime。需要默认给 Codex/Claude 消费侧提供 `localBrowserScreenshot` 时，使用 `--browser-annotation-screenshots-mode always`。

为了靠近 Codex browser runtime state，JSON capture 还会包含 `codexBrowserRuntimeState`，并把 `activeDesignChange` 镜像到 `codexBrowserPayload.localBrowserDesignChange`。CLI 和 MCP 可以通过 `--browser-annotation-editor-mode design`、`--browser-original-view-enabled`、`--browser-design-modifier-pressed`、`--browser-tweaks-editor-open`、`--browser-active-design-change-json '{"id":"design","declarations":[]}'` 设置这些 adapter 字段。它是给 Codex/Claude 消费侧使用的原生适配层，不等于已经运行 Codex 内置浏览器的 DOM/preload design editor 或 image-drag instrumentation。

对于支持的前台浏览器 App，`--include-browser-dom` 会额外生成 `codexBrowserDOMIntegration`。它通过短超时的 Apple Events JavaScript probe 只读 Safari 和 Chromium 系浏览器页面，提取图片和可设计元素候选，再生成 Codex runtime event 形状的数据，例如 `browser-sidebar-runtime-image-drag-started`、`browser-sidebar-runtime-image-drag-ended`、`browser-sidebar-runtime-open-design-editor`。如果 Apple Events scripting 不可用、被权限挡住或超时，capture 会返回 `available: false` 和原因，不会卡住。

### 权限

完整 UI/文本树需要辅助功能权限，这是 AppShot 的主文本路径。截图和 OCR 需要屏幕录制权限。当 App 没有通过 Accessibility 暴露正文时，OCR 才作为兜底从可见像素里恢复文字。在 macOS 上，权限归属于启动的 App 身份，所以授权时请运行已安装的 `AppShot.app`，不要只跑 SwiftPM 里的 CLI 可执行文件。

全局快捷键默认开启：同时按下左 Option 和右 Option 可以捕获当前 App。你可以在 AppShot Settings 里关闭它。

快捷键捕捉会写入共享 recent cache。没有指定明确窗口目标时，CLI 和 MCP 默认读取这个缓存；如果需要直接抓当前窗口，加 `--ignore-cache`、`--no-cache` 或 `--fresh`。

如果 macOS 隐私设置里已经显示 AppShot 打开了，但 AppShot 仍然识别不到权限，先检查身份漂移：

```sh
scripts/diagnose_tcc_identity.sh
```

Xcode Debug 构建、已安装 release App、SwiftPM CLI 可能显示同一个名字，但代码签名身份不同。尤其是 ad-hoc 签名，重新构建后 `CDHash` 可能变化，TCC 会把它当成另一个 App。要让开发/发布权限稳定，请固定使用同一个已安装 App 身份，或者通过 `APPSHOT_CODESIGN_IDENTITY` 使用稳定签名身份构建。

如果隐私设置里有旧记录导致状态错乱，可以先重置旧 TCC 记录，再打开同一个已安装 App 重新授权：

```sh
tccutil reset Accessibility com.qppshot.AppShot
tccutil reset ScreenCapture com.qppshot.AppShot
open ~/Applications/AppShot.app
```

### 实现说明

首个版本使用公开 macOS API。后续窗口解析会严格对照本地 diff 出来的 Codex Mac App 证据继续补齐，不凭空猜实现。
