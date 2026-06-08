# AppShot v0.1.15

## English

AppShot v0.1.15 ships the trained all-app rule catalog with the macOS release package:

- Release zip/DMG packages now include `rules/seed/local-app-strategies.json`.
- The installer copies the trained JSON rule catalog to `~/Library/Application Support/AppShot/rules/seed/local-app-strategies.json`.
- The local rule trainer can resolve the catalog from `APPSHOT_RULE_CATALOG`, the repo seed path, or the installed Application Support path.
- Parity verification now gates release/installer packaging on the trained rule catalog so future releases cannot silently drop it.
- Rule effectiveness remains JSON-governed: strategy changes stay in catalog/rule JSON and are not hard-coded into runtime capture logic.

## 中文

AppShot v0.1.15 会把已经训练好的 all-app rule catalog 一起带进 macOS release 包：

- release zip/DMG 现在包含 `rules/seed/local-app-strategies.json`。
- 安装器会把训练好的 JSON rule catalog 复制到 `~/Library/Application Support/AppShot/rules/seed/local-app-strategies.json`。
- 本地 rule trainer 会按 `APPSHOT_RULE_CATALOG`、repo seed 路径、已安装 Application Support 路径的顺序解析 catalog。
- parity 验证会检查 release/installer 是否携带训练 catalog，避免未来发版遗漏。
- 有效性提升仍然由 JSON 治理：策略变化保留在 catalog/rule JSON 中，不 hard-code 到 runtime capture 逻辑。

# AppShot v0.1.14

## English

AppShot v0.1.14 tightens the Codex browser-host parity surface:

- Added observable native Codex preload host detection in browser DOM captures, reporting `nativeCodexDesktopAvailable`, `codexHostBridgeAvailable`, `hostOwner: codex-electron-host`, and `hostTransport: codex-electron-ipc` when a native Codex host API is visible.
- Kept AppShot's page-local shim distinct from native Codex host APIs by preserving `codexDesktopShimAvailable: false` for native Codex fixtures.
- Mirrored the native Codex host fields into `codexBrowserPayload.localBrowserCommentMetadata.browserDOMIntegration` and live runtime protocol metadata.
- Tightened `scripts/verify_codex_parity.sh` with bundled Codex `comment-preload.js` source anchors plus CLI and MCP fixtures for native Codex host detection.
- Expanded Codex text output for deeper app context by allowing `AXTextArea` child snapshots, increasing the appshot text line budget, and merging de-duplicated Accessibility text evidence with visible/document text evidence.
- Fixed release version drift checks so the Core bridge and browser extension page bridge versions are verified with the package version.

## 中文

AppShot v0.1.14 继续收紧 Codex browser-host parity：

- browser DOM capture 新增可观察原生 Codex preload host 检测；当页面可见原生 Codex host API 时，会报告 `nativeCodexDesktopAvailable`、`codexHostBridgeAvailable`、`hostOwner: codex-electron-host`、`hostTransport: codex-electron-ipc`。
- AppShot page-local shim 和原生 Codex host API 现在明确区分；native Codex fixture 会保持 `codexDesktopShimAvailable: false`。
- 新字段会同步到 `codexBrowserPayload.localBrowserCommentMetadata.browserDOMIntegration` 和 live runtime protocol metadata。
- `scripts/verify_codex_parity.sh` 增加 Codex bundled `comment-preload.js` 源码锚点，以及 CLI/MCP native Codex host fixture。
- 扩大 Codex text 输出：允许继续展开 `AXTextArea` 子节点，提高 appshot text 行数预算，并把去重后的 Accessibility text evidence 与 visible/document text evidence 合并。
- release version drift 检查现在会覆盖 Core bridge 和 browser extension page bridge 版本。

# AppShot v0.1.13

## English

AppShot v0.1.13 turns the remaining Codex-side Electron bridge work into a packaged, testable integration surface:

- Added `codex-integration/appshot-codex-host-bridge`, a Codex-side Electron host adapter that composes the AppShot Electron bridge and emits Codex-shaped runtime sync/message state when loaded by an actual host process.
- Added `codexComputerUseStatus.hostBridge.codexHostIntegration` diagnostics so CLI/MCP callers can see installed bridge artifacts, expected host API/channel/owner/transport values, and the standalone non-claim `privateCodexWebviewHostAttached: false`.
- Packaged and installed the Codex host integration adapter alongside the browser extension and Electron preload helpers.
- Tightened parity verification with `scripts/verify_codex_host_integration.mjs` plus CLI/MCP schema checks for the new host integration diagnostics.

## 中文

AppShot v0.1.13 把剩余的 Codex-side Electron bridge 工作推进成一个可打包、可验证的集成面：

- 新增 `codex-integration/appshot-codex-host-bridge`，提供 Codex-side Electron host adapter；当它被真实 host process 加载时，会复用 AppShot Electron bridge，并输出 Codex-shaped runtime sync/message state。
- 新增 `codexComputerUseStatus.hostBridge.codexHostIntegration` 诊断，让 CLI/MCP 调用方能看到 bridge artifacts、预期 host API/channel/owner/transport，以及 standalone 场景下不会误报的 `privateCodexWebviewHostAttached: false`。
- release 包和安装器会随 browser extension、Electron preload helper 一起安装 Codex host integration adapter。
- `scripts/verify_codex_host_integration.mjs` 和 parity verifier 现在会检查新的 host integration 诊断与 CLI/MCP schema。

# AppShot v0.1.2

## English

AppShot v0.1.2 focuses on stable signed releases and cross-agent integration:

- Release builds now default to `0.1.2` and refuse ad-hoc output.
- Public release mode is explicit: set `APPSHOT_PUBLIC_RELEASE=1` with a `Developer ID Application` identity and `APPSHOT_NOTARY_PROFILE` to require notarization, stapling, and Gatekeeper assessment.
- The installer can give Claude Code the Codex App Shot ability with `APPSHOT_INSTALL_CLAUDE_CODE=1`, installing both the AppShot skill and MCP server registration.
- The native app now includes a global shortcut setting. It is enabled by default and uses left Option + right Option to capture the current app.
- AppShot continues to report TCC identity stability directly, so users can distinguish the stable installed app from Xcode DerivedData or CLI identities.

## 中文

AppShot v0.1.2 重点补齐稳定签名发布和跨 agent 集成：

- release 构建默认版本切到 `0.1.2`，并拒绝 ad-hoc 输出。
- 公开发布模式变成显式路径：设置 `APPSHOT_PUBLIC_RELEASE=1`，配合 `Developer ID Application` 证书和 `APPSHOT_NOTARY_PROFILE`，强制执行 notarization、staple 和 Gatekeeper 校验。
- 安装器可以通过 `APPSHOT_INSTALL_CLAUDE_CODE=1` 让 Claude Code 拥有 Codex App Shot 能力，同时安装 AppShot skill 和 MCP server 注册。
- 原生 App 新增全局快捷键设置，默认开启，使用左 Option + 右 Option 捕获当前 App。
- AppShot 继续直接暴露 TCC 身份稳定性，方便区分固定安装版、Xcode DerivedData 版和 CLI 身份。

# AppShot v0.1.1

## English

AppShot v0.1.1 focuses on making the Mac release installable end to end:

- Release packages now include `AppShot.app`, the `appshot` CLI, and MCP server files.
- The curl installer installs the app, CLI, MCP server, and Codex skill.
- The Codex skill bootstraps AppShot when the local CLI is missing.
- Permission reset is available with `APPSHOT_RESET_PERMISSIONS=1` for broken development TCC states.
- Accessibility remains the primary text path; OCR is explicit fallback only.
- Codex parity verification is now runnable with `scripts/verify_codex_parity.sh`; it checks local Codex Mac app evidence, native App target build output, CLI JSON aliases, MCP tools, and package version alignment.
- App/window QA is now scriptable with `scripts/qa_app_capture.py`, including target-window screenshot metadata, window-bound image dimensions, OCR text, Accessibility text, and hierarchy anchors.
- TCC identity diagnosis is now available with `scripts/diagnose_tcc_identity.sh` to explain cases where Privacy & Security shows AppShot enabled but the running build still cannot see permissions.
- Accessibility output now includes coordinate-sorted `visibleText` and `visibleTextLineCount` for a more human-readable visible text stream alongside the full AX tree text.
- Large Accessibility text controls now contribute `AXBoundsForRange` line fragments, so editor/body text can participate in `visibleText` when the app exposes range bounds.

## 中文

AppShot v0.1.1 的重点是把 Mac 发布包补成完整可安装形态：

- Release 包现在包含 `AppShot.app`、`appshot` CLI 和 MCP server 文件。
- curl 安装器会安装 App、CLI、MCP server 和 Codex skill。
- Codex skill 会在本地缺少 CLI 时自动引导安装 AppShot。
- 开发阶段权限状态损坏时，可以用 `APPSHOT_RESET_PERMISSIONS=1` 重置 TCC 授权记录。
- Accessibility 仍然是主文本路径，OCR 只作为显式兜底能力。
- 现在可以运行 `scripts/verify_codex_parity.sh` 做 Codex 一致性检查；它会检查本地 Codex Mac app 证据、原生 App target 构建产物、CLI JSON 别名、MCP tools 和包版本一致性。
- 现在可以用 `scripts/qa_app_capture.py` 对真实 App/window 做脚本化 QA，包括目标窗口截图元数据、窗口 bounds 对应的图片尺寸、OCR 文本、Accessibility 文本和层级锚点。
- 现在可以用 `scripts/diagnose_tcc_identity.sh` 诊断 TCC 身份漂移，解释“隐私设置里 AppShot 已打开，但当前运行构建仍然识别不到权限”的情况。
- Accessibility 输出现在包含按坐标排序的 `visibleText` 和 `visibleTextLineCount`，在完整 AX 树文本之外提供更接近人眼阅读顺序的可见文本流。
- 大块 Accessibility 文本控件现在会贡献 `AXBoundsForRange` 行级片段，因此当目标 App 暴露文本范围坐标时，编辑器/正文文本也可以进入 `visibleText`。

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
