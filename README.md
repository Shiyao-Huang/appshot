# AppShot

## English

AppShot gives any AI a Codex-style App Shot capability on macOS, and lets Claude Code use the same App Shot ability that Codex has.

It captures the frontmost Mac application as structured context: app metadata, visible windows, primary window geometry/title, Accessibility text/UI tree, focused element text, and optional screenshots. OCR is available only as an explicit fallback. The project ships as a native macOS app first, with CLI, MCP, Codex skill, Claude Code skill, and plugin support as integration layers.

### Install

```sh
curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | bash
```

By default this installs `AppShot.app` to `~/Applications/AppShot.app`, the `appshot` CLI to `~/.local/bin/appshot`, the MCP server to `~/.local/share/appshot/mcp`, the optional browser bridge extension to `~/.local/share/appshot/browser-extension/appshot-bridge`, the optional Electron host bridge to `~/.local/share/appshot/electron-preload/appshot-host-bridge`, the optional Codex host integration adapter to `~/.local/share/appshot/codex-integration/appshot-codex-host-bridge`, and the Codex skill to `~/.codex/skills/appshot`.

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
- Codex apps readiness surface: `codexAppsStatus`, CLI `codex-apps-status`, and MCP `appshot_codex_apps_status` report whether AppShot is ready as a Codex-accessible app connector, including permission blockers, tool surface, and force-refetch guidance.
- Codex Computer Use parity surface: `codexComputerUseStatus`, CLI `codex-computer-use-status`, and MCP `appshot_codex_computer_use_status` report the installed Codex Computer Use service, `ComputerUseAppApprovals.json`, and native host-bridge requirements such as `SKY_CUA_NATIVE_PIPE`, `x-codex-turn-metadata`, and `requestComputerUseApproval`.
- Computer Use-compatible MCP aliases: `list_apps` and `get_app_state` mirror Codex Computer Use tool names; `get_app_state` returns Codex-style appshot text plus a PNG image content block for Claude Code/Codex consumers.
- Codex browser-comment payload adapter: JSON captures include `codexBrowserPayload` with `localBrowserContext`, `localBrowserCommentMetadata`, `localBrowserAttachedImages`, `localBrowserDesignChange.group`, and `localBrowserScreenshot` field names for Codex/Claude consumers. Browser DOM captures prefer real page URLs, target selectors, immediate target text, marker viewport points, and bridge availability when those values are available.
- Codex browser screenshot policy: `--browser-annotation-screenshots-mode always|necessary`, MCP `browserAnnotationScreenshotsMode`, and App Settings `Browser Screenshots` write `browser-annotation-screenshots-mode` into `codexBrowserSettings`; `always` captures a screenshot for `codexBrowserPayload` by default.
- Codex browser runtime state adapter: JSON captures include `codexBrowserRuntimeState` with Codex `browser-sidebar-runtime-sync` field names such as `interactionMode`, `annotationEditorMode`, `isOriginalViewEnabled`, `isDesignModifierPressed`, `isTweaksEditorOpen`, and `activeDesignChange`.
- Codex browser runtime protocol adapter: JSON captures include `codexBrowserRuntimeProtocol` with the Codex 522 `browser-sidebar-runtime-*` event set, including comment editor, comment preview, screenshot, design scrub, design modifier, image drag, sync, and anchor-update events.
- Browser DOM integration: `--include-browser-dom`, MCP `includeBrowserDOM`, and App Settings `Browser DOM` run a timed, read-only Safari/Chrome DOM probe when Apple Events allows it, producing `codexBrowserDOMIntegration.browserRuntimeEvents` with Codex runtime-shaped candidate events, image-drag `sourceUrl`, comment/design `anchorState`, and `designEditorState`.
- Browser remote-debugging target detection: DOM captures identify Codex-style debug pages such as `content shell remote debugging`, `inspectable webcontents`, and local debug ports `9222` / `9229` in `codexBrowserDOMIntegration.remoteDebuggingTarget`.
- Electron/CDP remote debugging probe: `--include-electron-debugging`, MCP `includeElectronDebugging`, and Electron-targeted `--include-browser-dom` scan known Codex debug ports plus the target app's listening ports, read `/json/version` / `/json/list`, and, when an inspectable `webSocketDebuggerUrl` exists, sample DOM text and `Accessibility.getFullAXTree` through Chrome DevTools Protocol. If VS Code or another Electron app does not expose inspectable WebContents, the capture reports `codexElectronRemoteDebugging.reason: noInspectableTargets` with `scannedPorts` instead of pretending the missing content was captured.
- Target activation and AX exposure diagnostics: explicit `windowID` / `pid` / `bundleID` captures activate the target by default, report `targetActivation`, and include `accessibility.targetWindowMatch.axWindowExposure` so VS Code/Electron shallow captures can be distinguished from permission failures.
- AX window discovery: `list-windows` includes both CG windows and `accessibilityWindows`, plus `windowDiscovery.hasAccessibilityOnlyWindows`. Use `capture --window-title "Title"` or MCP `windowTitle` to target Electron/VS Code windows that are visible to macOS Accessibility but missing from CGWindow. When an AX-only target has no CG `windowID`, screenshots use the AX window bounds and report `screenshot.captureMode: bounds`.
- GUI App capture request: `--request-app-capture` and MCP `requestAppCapture` ask the running `AppShot.app` process to perform the capture and wait for its shared cache. This gives CLI/MCP a Codex-like path through the signed GUI app session when shell frontmost state is unreliable.
- Browser runtime bridge: `--browser-dom-install-bridge`, MCP `browserDOMInstallBridge`, and App Settings `Browser Bridge` optionally install a page-level Safari/Chrome listener plus a `window.codex_desktop.sendMessageToHost` / `subscribeToHostMessages` shim. It records real `browser-sidebar-runtime-*` bridge events into `browserRuntimeBridgeEvents` and reports `codexDesktopShimAvailable`, `nativeCodexDesktopAvailable`, `codexHostBridgeAvailable`, `hostAPI`, and `hostChannel`; `--browser-dom-clear-bridge-log` clears that tab-local log.
- Browser extension/preload helper: `browser-extension/appshot-bridge` is packaged and installed as an optional unpacked MV3 helper. It exposes `window.codex_desktop` from a page preload, relays through `window.postMessage+extension-runtime`, and surfaces `extensionHelperAvailable`, `hostOwner`, and `hostTransport` in `codexBrowserDOMIntegration.browserRuntimeBridge`.
- Electron preload/host helper: `electron-preload/appshot-host-bridge` is packaged and installed as an optional Electron integration. It exposes `window.codex_desktop` from `preload.cjs`, registers `installAppShotElectronHostBridge(ipcMain)` in `host.cjs`, and surfaces `electronHostBridgeAvailable`, `hostOwner: electron-preload`, and `hostTransport: electron-ipc`.
- Codex host integration adapter: `codex-integration/appshot-codex-host-bridge` is packaged and installed as a Codex-side host adapter. It exports `installAppShotCodexHostBridge`, composes the Electron helper, reports `hostOwner: codex-electron-host`, and follows Codex 522's real split IPC path: `codex_desktop:browser-sidebar-runtime-message` for preload-to-host `ipcRenderer.invoke` / `ipcMain.handle`, and `codex_desktop:message-for-view` for host-to-preload `webContents.send` / `ipcRenderer.on`. `scripts/analyze_codex_electron_host_injection.mjs` verifies those packaged insertion points without mutating Codex.app; release/install also include the analyzer and `patch_codex_electron_host_for_appshot.mjs` under the installed Codex integration directory so explicit Codex host patch experiments do not require a source checkout. Standalone CLI/MCP status keeps `privateCodexWebviewHostAttached: false` until a real Codex Electron host loads or wraps it.

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
scripts/build_release.sh 0.1.14
open dist/AppShot-macOS-0.1.14/AppShot.app
```

For a public macOS release, sign with a `Developer ID Application` identity and notarize the DMG:

```sh
APPSHOT_PUBLIC_RELEASE=1 \
APPSHOT_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APPSHOT_NOTARY_PROFILE="appshot-notary" \
scripts/build_release.sh 0.1.14
```

The public release path refuses Apple Development or ad-hoc signatures, submits the DMG to Apple notarization, staples the ticket, and runs Gatekeeper assessment.

CLI examples:

```sh
.build/debug/appshot status --pretty
.build/debug/appshot codex-apps-status --pretty
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

For Electron apps such as VS Code, AppShot also attempts `AXManualAccessibility` and `AXEnhancedUserInterface` before walking the tree. The result is reported in `accessibility.electronAccessibility`, including each attempted AX attribute, so shallow Electron captures can be diagnosed instead of silently looking like normal macOS AX output.

When a requested `windowID` cannot be matched to a macOS `AXWindow`, AppShot reports `accessibility.targetWindowMatch` with candidate scores, focused/main AX results, top candidates, `bestCandidateIsAXWindow`, `axWindowExposure.roleCounts`, and recovery steps. Explicit target captures activate the target app/window by default and write `targetActivation`; pass `--no-activate-target` only when focus must not change. If shell/MCP frontmost state is unreliable, add `--request-app-capture` to ask the running GUI `AppShot.app` to capture and write the shared cache; the result includes `appCaptureRequest`. If `axWindowExposure.suspectedSelfReferentialAXWindows` is true, macOS returned app-level AX candidates instead of real window candidates. In that case `accessibility.rootSource` becomes `targetWindowUnmatchedApplication` or `targetWindowUnmatchedFocusedWindow` instead of pretending the app-level menu tree is the requested window; Codex text also suppresses app menu bar shells so menu noise does not dominate the output. When debugging Electron helper/render processes, explicit `--pid` captures can target non-`NSRunningApplication` PIDs directly and report `auxiliaryProcessCapture` instead of falling back to the frontmost app.

For Electron apps with multiple windows, Codex often sees windows through the Accessibility tree even when CGWindow does not list them. `appshot list-windows --pretty` now reports `accessibilityWindows`, `windowDiscovery.preferredAccessibilityWindow`, and `windowDiscovery.hasAccessibilityOnlyWindows` for each app. If a desired VS Code window appears only in that AX list, target it by title; screenshots for AX-only windows fall back to the AX bounds rectangle and report `screenshot.captureMode: bounds`:

```sh
appshot capture --bundle-id com.microsoft.VSCode --window-title "image.png — 自媒体" --pretty
```

JSON capture output also includes `codexBrowserPayload`, a native AppShot adapter for Codex browser-comment payload fields. It maps app/window/AX/screenshot evidence into the same `localBrowser*` names Codex uses, without claiming AppShot implements Codex's embedded browser design editor or image-drag runtime. When `--include-browser-dom` is available, the payload uses the browser page URL for `localBrowserContext.pageUrl` / `frameUrl`, exposes DOM target values such as `targetSelector`, `targetImmediateText`, `targetPath`, and writes viewport metadata such as `markerViewportPoint`. Use `--browser-annotation-screenshots-mode always` when a Codex/Claude consumer should receive a `localBrowserScreenshot` by default.

For Codex browser runtime-state parity, JSON capture includes `codexBrowserRuntimeState` and mirrors `activeDesignChange` into `codexBrowserPayload.localBrowserDesignChange.group`, matching the Codex browser comment payload shape. CLI and MCP calls can set those adapter fields with options such as `--browser-annotation-editor-mode design`, `--browser-original-view-enabled`, `--browser-design-modifier-pressed`, `--browser-tweaks-editor-open`, and `--browser-active-design-change-json '{"id":"design","declarations":[]}'`. JSON capture also includes `codexBrowserRuntimeProtocol`, an evidence-backed protocol adapter for the full Codex 522 `browser-sidebar-runtime-*` event set; it is mirrored into `codexBrowserPayload.localBrowserRuntimeProtocol`.

For supported frontmost browser apps, `--include-browser-dom` adds `codexBrowserDOMIntegration`. It uses a short-timeout Apple Events JavaScript probe for Safari and Chromium-style browsers to read page images and design target candidates, then emits Codex runtime event-shaped candidate entries such as `browser-sidebar-runtime-open-editor`, `browser-sidebar-runtime-create-comment-at-point`, `browser-sidebar-runtime-update-anchor`, `browser-sidebar-runtime-open-design-editor`, `browser-sidebar-runtime-design-scrub-changed`, `browser-sidebar-runtime-image-drag-started`, and `browser-sidebar-runtime-image-drag-ended`. `--browser-dom-install-bridge` goes one step closer to Codex by installing a temporary page listener and a page-local `window.codex_desktop` shim with `sendMessageToHost` / `subscribeToHostMessages`; it logs real pointer, keyboard, drag, sync, and shim message events into `codexBrowserDOMIntegration.browserRuntimeBridgeEvents`. For a browser-owned bridge, load the unpacked helper at `~/.local/share/appshot/browser-extension/appshot-bridge`; its `page-bridge.js`, `content.js`, and `background.js` route the same Codex-shaped messages through `window.postMessage+extension-runtime`. For an Electron-owned bridge in an app you control, wire `~/.local/share/appshot/electron-preload/appshot-host-bridge/preload.cjs` into `BrowserWindow.webPreferences.preload` and register `installAppShotElectronHostBridge(ipcMain)` from `host.cjs`. If an observable native Codex preload host API is already present, AppShot reports `nativeCodexDesktopAvailable`, `codexHostBridgeAvailable`, `hostOwner: codex-electron-host`, `hostTransport: codex-electron-ipc`, and keeps `codexDesktopShimAvailable: false`. For a Codex-side host integration experiment, run `scripts/analyze_codex_electron_host_injection.mjs`, then load `~/.local/share/appshot/codex-integration/appshot-codex-host-bridge/codex-host-adapter.cjs` inside the actual Codex Electron host before Codex registers `ipcMain.handle(Ts)`, or wrap the existing handler with `wrapCodexRuntimeMessageHandler`. Inspect `codexBrowserDOMIntegration.browserRuntimeBridge.codexDesktopShimAvailable`, `nativeCodexDesktopAvailable`, `codexHostBridgeAvailable`, `extensionHelperAvailable`, `electronHostBridgeAvailable`, `hostAPI`, `hostChannel`, `hostInboundChannel`, `hostOutboundChannel`, `ipcPattern`, `hostOwner`, and `hostTransport` to verify the active bridge; inspect `codexComputerUseStatus.hostBridge.codexHostIntegration` to see whether the Codex host adapter artifacts are installed and whether the private Codex webview host is actually attached. These bridge events are merged into `codexBrowserPayload.localBrowserRuntimeEvents` and make `localBrowserRuntimeProtocol.liveEventStreamAvailable` true for that tab. If Apple Events scripting is unavailable, blocked, or times out, the capture returns `available: false` with a reason instead of hanging. This bridge is page-level/browser-extension/Electron-preload/Codex-host instrumentation, but the standalone CLI/MCP path still cannot claim Codex's internal Electron preload lifecycle.

For Electron apps, add `--include-electron-debugging` or use `--include-browser-dom` against an Electron target. AppShot will report `codexElectronRemoteDebugging` with scanned ports, DevTools targets, selected target scoring, and an optional CDP DOM/AX snapshot. This is the public DevTools-adjacent path toward Codex-like Electron content, but it still depends on the target app exposing inspectable WebContents.

DOM captures also include `codexBrowserDOMIntegration.remoteDebuggingTarget`, matching Codex app-session evidence for `content shell remote debugging`, `inspectable webcontents`, and localhost debug ports `9222` / `9229`. The same classification is mirrored into `codexBrowserPayload.localBrowserCommentMetadata.browserDOMIntegration.remoteDebuggingTarget`.

`status` and `capture` also include `codexAppsStatus`, and the same payload is available through `appshot codex-apps-status --pretty` or MCP `appshot_codex_apps_status`. This mirrors the Codex app-list readiness shape from the focused diff: `codexAppsReady` is derived from permission blockers, `forceRefetchSupported` / `retryWhenNotReady` document the retry path, and `tools` lists the AppShot MCP surface Claude Code or Codex can call.

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

默认会把 `AppShot.app` 安装到 `~/Applications/AppShot.app`，把 `appshot` CLI 安装到 `~/.local/bin/appshot`，把 MCP server 安装到 `~/.local/share/appshot/mcp`，把可选 browser bridge extension 安装到 `~/.local/share/appshot/browser-extension/appshot-bridge`，把可选 Electron host bridge 安装到 `~/.local/share/appshot/electron-preload/appshot-host-bridge`，把可选 Codex host integration adapter 安装到 `~/.local/share/appshot/codex-integration/appshot-codex-host-bridge`，并把 Codex skill 安装到 `~/.codex/skills/appshot`。

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
- Codex apps readiness surface：`codexAppsStatus`、CLI `codex-apps-status` 和 MCP `appshot_codex_apps_status` 会报告 AppShot 作为 Codex 可访问 app connector 是否 ready，包括权限 blocker、工具列表和 force-refetch 指引。
- Codex Computer Use parity surface：`codexComputerUseStatus`、CLI `codex-computer-use-status` 和 MCP `appshot_codex_computer_use_status` 会报告已安装的 Codex Computer Use 服务、`ComputerUseAppApprovals.json`，以及 `SKY_CUA_NATIVE_PIPE`、`x-codex-turn-metadata`、`requestComputerUseApproval` 等 host bridge 依赖。
- Computer Use 兼容 MCP aliases：`list_apps` 和 `get_app_state` 对齐 Codex Computer Use 的工具名；`get_app_state` 会返回 Codex-style appshot 文本和 PNG image content，方便 Claude Code/Codex 消费。
- Codex browser-comment payload adapter：JSON capture 会包含 `codexBrowserPayload`，内部使用 `localBrowserContext`、`localBrowserCommentMetadata`、`localBrowserAttachedImages`、`localBrowserDesignChange.group`、`localBrowserScreenshot` 这些 Codex/Claude 消费侧字段名。Browser DOM capture 在可用时会优先使用真实页面 URL、目标 selector、目标即时文本、marker viewport point 和 bridge 可用状态。
- Codex browser screenshot policy：`--browser-annotation-screenshots-mode always|necessary`、MCP `browserAnnotationScreenshotsMode`、App Settings `Browser Screenshots` 会把 `browser-annotation-screenshots-mode` 写入 `codexBrowserSettings`；`always` 会默认给 `codexBrowserPayload` 捕捉截图。
- Codex browser runtime state adapter：JSON capture 会包含 `codexBrowserRuntimeState`，使用 Codex `browser-sidebar-runtime-sync` 同名字段，例如 `interactionMode`、`annotationEditorMode`、`isOriginalViewEnabled`、`isDesignModifierPressed`、`isTweaksEditorOpen`、`activeDesignChange`。
- Codex browser runtime protocol adapter：JSON capture 会包含 `codexBrowserRuntimeProtocol`，内部是 Codex 522 的 `browser-sidebar-runtime-*` 事件集合，覆盖 comment editor、comment preview、screenshot、design scrub、design modifier、image drag、sync 和 anchor update。
- Browser DOM integration：`--include-browser-dom`、MCP `includeBrowserDOM`、App Settings `Browser DOM` 会在 Apple Events 允许时，对 Safari/Chrome 做带超时的只读 DOM probe，生成 `codexBrowserDOMIntegration.browserRuntimeEvents`，包含 Codex runtime 形状的候选事件、image-drag `sourceUrl`、comment/design `anchorState` 和 `designEditorState`。
- Browser remote-debugging target detection：DOM capture 会在 `codexBrowserDOMIntegration.remoteDebuggingTarget` 里识别 Codex 风格调试页，例如 `content shell remote debugging`、`inspectable webcontents`，以及本机调试端口 `9222` / `9229`。
- Electron/CDP remote debugging probe：`--include-electron-debugging`、MCP `includeElectronDebugging`，以及面向 Electron 目标的 `--include-browser-dom` 会扫描 Codex 已知调试端口和目标 App 的监听端口，读取 `/json/version` / `/json/list`；如果存在可检查的 `webSocketDebuggerUrl`，会通过 Chrome DevTools Protocol 抽取 DOM 文本和 `Accessibility.getFullAXTree`。如果 VS Code 或其他 Electron App 没有暴露 inspectable WebContents，capture 会返回 `codexElectronRemoteDebugging.reason: noInspectableTargets` 和 `scannedPorts`，不会把缺失内容伪装成已捕捉。
- 目标激活和 AX 暴露诊断：显式指定 `windowID` / `pid` / `bundleID` 时默认会先激活目标，输出 `targetActivation`，并在 `accessibility.targetWindowMatch.axWindowExposure` 中记录 AX window 候选暴露情况，方便把 VS Code/Electron 浅捕捉和权限失败区分开。
- AX window discovery：`list-windows` 同时输出 CG windows 和 `accessibilityWindows`，并带有 `windowDiscovery.hasAccessibilityOnlyWindows`。使用 `capture --window-title "标题"` 或 MCP `windowTitle` 可以选中 macOS Accessibility 可见、但 CGWindow 缺失的 Electron/VS Code 窗口。当 AX-only 目标没有 CG `windowID` 时，截图会用 AX window bounds 裁剪，并输出 `screenshot.captureMode: bounds`。
- GUI App capture request：`--request-app-capture` 和 MCP `requestAppCapture` 会请求正在运行的 `AppShot.app` 进程执行捕捉，并等待它写入 shared cache。这样 CLI/MCP 可以通过签名 GUI App 会话接近 Codex 内置 AppShot 路径，避开 shell frontmost 不可靠的问题。
- Browser runtime bridge：`--browser-dom-install-bridge`、MCP `browserDOMInstallBridge`、App Settings `Browser Bridge` 会可选安装一个页面级 Safari/Chrome 监听器和 `window.codex_desktop.sendMessageToHost` / `subscribeToHostMessages` shim，把真实 `browser-sidebar-runtime-*` bridge 事件写入 `browserRuntimeBridgeEvents`，并报告 `codexDesktopShimAvailable`、`nativeCodexDesktopAvailable`、`codexHostBridgeAvailable`、`hostAPI`、`hostChannel`；`--browser-dom-clear-bridge-log` 可以清空当前 tab 的本地日志。
- Browser extension/preload helper：`browser-extension/appshot-bridge` 会作为可选 unpacked MV3 helper 打包和安装。它从页面 preload 暴露 `window.codex_desktop`，通过 `window.postMessage+extension-runtime` 转发，并在 `codexBrowserDOMIntegration.browserRuntimeBridge` 中输出 `extensionHelperAvailable`、`hostOwner`、`hostTransport`。
- Electron preload/host helper：`electron-preload/appshot-host-bridge` 会作为可选 Electron integration 打包和安装。它从 `preload.cjs` 暴露 `window.codex_desktop`，在 `host.cjs` 中注册 `installAppShotElectronHostBridge(ipcMain)`，并输出 `electronHostBridgeAvailable`、`hostOwner: electron-preload`、`hostTransport: electron-ipc`。
- Codex host integration adapter：`codex-integration/appshot-codex-host-bridge` 会作为 Codex-side host adapter 打包和安装。它导出 `installAppShotCodexHostBridge`，复用 Electron helper，报告 `hostOwner: codex-electron-host`，并按 Codex 522 的真实双通道 IPC 工作：`codex_desktop:browser-sidebar-runtime-message` 用于 preload-to-host `ipcRenderer.invoke` / `ipcMain.handle`，`codex_desktop:message-for-view` 用于 host-to-preload `webContents.send` / `ipcRenderer.on`。`scripts/analyze_codex_electron_host_injection.mjs` 可以在不修改 Codex.app 的情况下验证这些打包产物接入点；release/install 也会把 analyzer 和 `patch_codex_electron_host_for_appshot.mjs` 放进已安装的 Codex integration 目录，所以显式 Codex host patch 实验不需要源码 checkout；在真实 Codex Electron host 接入之前，standalone CLI/MCP 会保持 `privateCodexWebviewHostAttached: false`。

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
scripts/build_release.sh 0.1.14
open dist/AppShot-macOS-0.1.14/AppShot.app
```

公开 macOS 发布包需要 `Developer ID Application` 证书并完成 DMG 公证：

```sh
APPSHOT_PUBLIC_RELEASE=1 \
APPSHOT_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APPSHOT_NOTARY_PROFILE="appshot-notary" \
scripts/build_release.sh 0.1.14
```

公开发布路径会拒绝 Apple Development 或 ad-hoc 签名，提交 Apple notarization，staple 公证票据，并运行 Gatekeeper 校验。

CLI 示例：

```sh
.build/debug/appshot status --pretty
.build/debug/appshot codex-apps-status --pretty
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

对于 VS Code 这类 Electron App，AppShot 会在遍历 UI 树之前尝试 `AXManualAccessibility` 和 `AXEnhancedUserInterface`。结果会记录到 `accessibility.electronAccessibility`，包括每个 AX attribute 的尝试结果，这样 Electron 捕捉过浅时可以诊断，而不是伪装成普通 macOS AX 输出。

当指定的 `windowID` 无法匹配到 macOS `AXWindow` 时，AppShot 会输出 `accessibility.targetWindowMatch`，包含候选得分、focused/main AX 结果、top candidates、`bestCandidateIsAXWindow`、`axWindowExposure.roleCounts` 和恢复步骤。显式目标捕捉默认会先激活目标 App/window，并写入 `targetActivation`；只有在不能改变焦点时才传 `--no-activate-target`。如果 shell/MCP 的 frontmost 状态不可靠，可以加 `--request-app-capture`，让正在运行的 GUI `AppShot.app` 执行捕捉并写入 shared cache；结果会包含 `appCaptureRequest`。如果 `axWindowExposure.suspectedSelfReferentialAXWindows` 为 true，说明 macOS 返回的是 app 级 AX 候选而不是真正窗口候选。这时 `accessibility.rootSource` 会变成 `targetWindowUnmatchedApplication` 或 `targetWindowUnmatchedFocusedWindow`，避免把 app 级菜单树伪装成指定窗口；Codex 文本也会压掉 app 菜单栏 shell，避免菜单噪声淹没正文。调试 Electron helper/renderer 进程时，显式 `--pid` 可以直接探测非 `NSRunningApplication` PID，并用 `auxiliaryProcessCapture` 标记结果，而不是回退到前台 App。

对于多窗口 Electron App，Codex 经常能从 Accessibility 树看到一些 CGWindow 没列出的窗口。`appshot list-windows --pretty` 现在会为每个 App 输出 `accessibilityWindows`、`windowDiscovery.preferredAccessibilityWindow` 和 `windowDiscovery.hasAccessibilityOnlyWindows`。如果目标 VS Code 窗口只出现在 AX 列表里，可以按标题捕捉；这类 AX-only 窗口的截图会退到 AX bounds 矩形裁剪，并输出 `screenshot.captureMode: bounds`：

```sh
appshot capture --bundle-id com.microsoft.VSCode --window-title "image.png — 自媒体" --pretty
```

JSON capture 还会包含 `codexBrowserPayload`，这是 AppShot 原生捕捉到 Codex browser-comment payload 字段的适配层。它会把 App/window/AX/screenshot 证据映射到 Codex 使用的 `localBrowser*` 字段名，但不声称 AppShot 已经实现 Codex 内置浏览器的 design editor 或 image-drag runtime。当 `--include-browser-dom` 可用时，payload 会用浏览器页面 URL 填充 `localBrowserContext.pageUrl` / `frameUrl`，并暴露 DOM 目标字段，例如 `targetSelector`、`targetImmediateText`、`targetPath`，以及 `markerViewportPoint` 这类 viewport 元数据。需要默认给 Codex/Claude 消费侧提供 `localBrowserScreenshot` 时，使用 `--browser-annotation-screenshots-mode always`。

为了靠近 Codex browser runtime state，JSON capture 还会包含 `codexBrowserRuntimeState`，并把 `activeDesignChange` 镜像到 `codexBrowserPayload.localBrowserDesignChange.group`，对齐 Codex browser comment payload 的结构。CLI 和 MCP 可以通过 `--browser-annotation-editor-mode design`、`--browser-original-view-enabled`、`--browser-design-modifier-pressed`、`--browser-tweaks-editor-open`、`--browser-active-design-change-json '{"id":"design","declarations":[]}'` 设置这些 adapter 字段。JSON capture 也会包含 `codexBrowserRuntimeProtocol`，这是基于 Codex 522 证据的完整 `browser-sidebar-runtime-*` 事件协议适配，并镜像到 `codexBrowserPayload.localBrowserRuntimeProtocol`。

对于支持的前台浏览器 App，`--include-browser-dom` 会额外生成 `codexBrowserDOMIntegration`。它通过短超时的 Apple Events JavaScript probe 只读 Safari 和 Chromium 系浏览器页面，提取图片和可设计元素候选，再生成 Codex runtime event 形状的候选数据，例如 `browser-sidebar-runtime-open-editor`、`browser-sidebar-runtime-create-comment-at-point`、`browser-sidebar-runtime-update-anchor`、`browser-sidebar-runtime-open-design-editor`、`browser-sidebar-runtime-design-scrub-changed`、`browser-sidebar-runtime-image-drag-started`、`browser-sidebar-runtime-image-drag-ended`。`--browser-dom-install-bridge` 会再向 Codex 靠近一步：安装临时页面监听器和页面级 `window.codex_desktop` shim，提供 `sendMessageToHost` / `subscribeToHostMessages`，把真实 pointer、keyboard、drag、sync 和 shim message 事件记录到 `codexBrowserDOMIntegration.browserRuntimeBridgeEvents`。如果需要 browser-owned bridge，可以在浏览器里加载 unpacked helper：`~/.local/share/appshot/browser-extension/appshot-bridge`；其中 `page-bridge.js`、`content.js`、`background.js` 会把同一组 Codex-shaped messages 通过 `window.postMessage+extension-runtime` 转发。如果需要 Electron-owned bridge，并且你控制目标 Electron App，可以把 `~/.local/share/appshot/electron-preload/appshot-host-bridge/preload.cjs` 接进 `BrowserWindow.webPreferences.preload`，再从 `host.cjs` 注册 `installAppShotElectronHostBridge(ipcMain)`。如果页面能观察到 Codex 原生 preload host API，AppShot 会报告 `nativeCodexDesktopAvailable`、`codexHostBridgeAvailable`、`hostOwner: codex-electron-host`、`hostTransport: codex-electron-ipc`，并保持 `codexDesktopShimAvailable: false`。如果要做 Codex-side host integration 实验，先运行 `scripts/analyze_codex_electron_host_injection.mjs`，再在真实 Codex Electron host 注册 `ipcMain.handle(Ts)` 之前加载 `~/.local/share/appshot/codex-integration/appshot-codex-host-bridge/codex-host-adapter.cjs`，或用 `wrapCodexRuntimeMessageHandler` 包住现有 handler。查看 `codexBrowserDOMIntegration.browserRuntimeBridge.codexDesktopShimAvailable`、`nativeCodexDesktopAvailable`、`codexHostBridgeAvailable`、`extensionHelperAvailable`、`electronHostBridgeAvailable`、`hostAPI`、`hostChannel`、`hostInboundChannel`、`hostOutboundChannel`、`ipcPattern`、`hostOwner`、`hostTransport` 可以确认当前 bridge；查看 `codexComputerUseStatus.hostBridge.codexHostIntegration` 可以确认 adapter artifact 是否已安装，以及私有 Codex webview host 是否真的接入。bridge 事件会合并进 `codexBrowserPayload.localBrowserRuntimeEvents`，并让当前 tab 的 `localBrowserRuntimeProtocol.liveEventStreamAvailable` 变为 true。如果 Apple Events scripting 不可用、被权限挡住或超时，capture 会返回 `available: false` 和原因，不会卡住。这个 bridge 是页面级/browser-extension/Electron-preload/Codex-host instrumentation；standalone CLI/MCP 路径仍不能声称拥有 Codex 内部 Electron preload lifecycle。

对于 Electron App，可以显式加 `--include-electron-debugging`，也可以对 Electron 目标使用 `--include-browser-dom`。AppShot 会输出 `codexElectronRemoteDebugging`，包含扫描端口、DevTools targets、目标评分和可选的 CDP DOM/AX snapshot。这是靠近 Codex Electron 内容提取的公开 DevTools 路径，但仍依赖目标 App 暴露 inspectable WebContents。

DOM capture 也会包含 `codexBrowserDOMIntegration.remoteDebuggingTarget`，对齐 Codex app-session 证据中对 `content shell remote debugging`、`inspectable webcontents` 和 localhost 调试端口 `9222` / `9229` 的识别。同一个分类会镜像到 `codexBrowserPayload.localBrowserCommentMetadata.browserDOMIntegration.remoteDebuggingTarget`。

`status` 和 `capture` 还会包含 `codexAppsStatus`，同一份 payload 也可以通过 `appshot codex-apps-status --pretty` 或 MCP `appshot_codex_apps_status` 获取。这一层对齐 Codex focused diff 里的 app-list readiness 形状：`codexAppsReady` 由权限 blockers 推导，`forceRefetchSupported` / `retryWhenNotReady` 说明重试路径，`tools` 列出 Claude Code 或 Codex 可调用的 AppShot MCP surface。

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
