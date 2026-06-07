---
name: appshot
description: Give Codex or Claude Code a Codex-style App Shot ability on macOS. If AppShot is not installed locally, bootstrap it first, then use the appshot CLI or MCP server for frontmost app metadata, visible windows, accessibility text/UI tree, optional screenshot, and optional OCR fallback.
---

# AppShot

Use this skill when the user asks to inspect the current Mac app, capture Appshots, gather app/window context, debug UI state, or provide richer context than a bitmap screenshot.

Primary goal: make AppShot fully usable for Codex and Claude Code through Accessibility first: capture the app, find the UI tree/text evidence directly, then act on it. Both Accessibility and Screen Recording permissions must be enabled before treating a capture as successful.

## Workflow

1. Resolve the CLI:
   ```sh
   APPSHOT_BIN="${APPSHOT_BIN:-$(command -v appshot || true)}"
   if [ -z "$APPSHOT_BIN" ] && [ -x "$HOME/.local/bin/appshot" ]; then
     APPSHOT_BIN="$HOME/.local/bin/appshot"
   fi
   ```
2. If the CLI is missing, install AppShot, the CLI, MCP files, and this skill:
   ```sh
   curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | bash
   APPSHOT_BIN="${APPSHOT_BIN:-$HOME/.local/bin/appshot}"
   ```
3. If working from the source repo instead of an installed release, build the CLI:
   ```sh
   swift build
   APPSHOT_BIN="$PWD/.build/debug/appshot"
   ```
4. Check permissions:
   ```sh
   "$APPSHOT_BIN" permissions --prompt --pretty
   ```
5. Check Codex-accessible app readiness:
   ```sh
   "$APPSHOT_BIN" codex-apps-status --pretty
   ```
6. Check Codex Computer Use parity diagnostics when matching Codex's built-in appshot behavior matters:
   ```sh
   "$APPSHOT_BIN" codex-computer-use-status --pretty
   ```
7. Inspect both the booleans and the identity/readiness fields: `permissions.accessibility`, `permissions.screenRecording`, `permissions.identity`, `permissions.stability`, `codexAppsStatus.codexAppsReady`, `codexAppsStatus.blockers`, `codexAppsStatus.tools`, and `codexComputerUseStatus.hostBridge`.
8. If either `accessibility` or `screenRecording` is `false`, or `codexAppsStatus.codexAppsReady` is `false`, treat that as the blocker to solve first. Prompt/open the macOS permission pane as needed, then re-run the permission/readiness check until both permissions are `true` and `codexAppsReady` is `true`.
   If macOS already shows AppShot as enabled but the CLI/App still reports missing permission, diagnose app identity drift before asking the user to re-authorize:
   ```sh
   scripts/diagnose_tcc_identity.sh
   ```
   Xcode Debug builds, installed apps, and SwiftPM CLI binaries can have different code-signing identities and `CDHash` values even when the visible name is the same.
   If `permissions.stability.mode` is `commandLineTool` or `alternateAppBundle`, do not ask for repeated permission toggles. Reset stale rows once, then open and authorize one fixed installed app identity:
   ```sh
   tccutil reset Accessibility com.qppshot.AppShot
   tccutil reset ScreenCapture com.qppshot.AppShot
   open ~/Applications/AppShot.app
   ```
9. If AppShot.app is running and the user can trigger the window they mean, have them press both left and right Option keys together. That writes the current capture into the shared shortcut cache. CLI and MCP capture calls use this recent cache by default when no explicit `windowID`, `pid`, `bundleID`, or screenshot path is passed. Add `--ignore-cache`, `--no-cache`, or `--fresh` when you need a fresh direct capture.
10. Capture context only after both permissions are enabled. Default to the Codex-style appshot block when the result will be shown to Codex, Claude Code, or the user:
   ```sh
   "$APPSHOT_BIN" capture --format codex --max-depth 60 --accessibility-timeout 20
   ```
   Use JSON when you need to inspect exact fields or automate checks:
   ```sh
   "$APPSHOT_BIN" capture --pretty --max-depth 60 --accessibility-timeout 20
   ```
   When a Codex/Claude consumer should receive browser-comment-shaped screenshot metadata by default, use Codex's browser annotation screenshot policy:
   ```sh
   "$APPSHOT_BIN" capture --pretty --browser-annotation-screenshots-mode always --max-depth 60 --accessibility-timeout 20
   ```
11. For complex apps such as Xcode, raise the Accessibility timeout instead of treating a slow AX tree as missing data:
   ```sh
   "$APPSHOT_BIN" capture --pretty --max-depth 60 --accessibility-timeout 30
   ```
12. If the user refers to a non-frontmost or described window, call `"$APPSHOT_BIN" list-windows --pretty` first. Pick the right `windowID`, `windowTitle`, `pid`, or `bundleID` yourself from the structured window list, then pass it to capture, e.g. `"$APPSHOT_BIN" capture --window-id 123 --pretty --max-depth 60 --accessibility-timeout 20`. `list-windows` includes both CG `windows` and AX `accessibilityWindows`; if an Electron/VS Code target appears only in `accessibilityWindows`, capture it by title, e.g. `"$APPSHOT_BIN" capture --bundle-id com.microsoft.VSCode --window-title 'image.png — 自媒体' --pretty --max-depth 60 --accessibility-timeout 20`. When an AX-only target has no CG `windowID`, screenshots use its AX bounds rectangle and report `screenshot.captureMode: bounds`. Explicit target captures activate the target by default to match Codex's front-window behavior; add `--no-activate-target` only when focus must not change. If CLI/MCP frontmost state is unreliable or reports `loginwindow`, prefer the GUI App path while AppShot.app is running:
   ```sh
   "$APPSHOT_BIN" capture --request-app-capture --app-capture-timeout 3 --pretty --max-depth 60 --accessibility-timeout 20
   ```
13. For Claude Code or Codex Computer Use-compatible consumers, the MCP server also exposes `list_apps` and `get_app_state`. `get_app_state` accepts `app` as an app name, full `.app` path, or bundle identifier, accepts optional `windowTitle`, and returns Codex-style appshot text plus PNG image content.
14. Read `captureCache`, then `codex.text` first for Codex-compatible context. For debugging, read `codexAppsStatus.codexAppsReady`, `codexComputerUseStatus`, `accessibility.root`, `accessibility.focusedElement`, `accessibility.text`, `accessibility.electronAccessibility`, and `accessibility.documentReferences[].textPreview`.
    If `accessibility.rootSource` starts with `targetWindowUnmatched`, do not treat the app-level tree as a successful capture of the requested window. Read `appCaptureRequest`, `targetActivation`, and `accessibility.targetWindowMatch`, especially `bestCandidateIsAXWindow`, `axWindowExposure.roleCounts`, and `axWindowExposure.suspectedSelfReferentialAXWindows`, then retry through `--request-app-capture`, with the target app/window active, enable Electron/VS Code screen reader accessibility support when appropriate, or use screenshot/OCR as fallback evidence. For Electron helper/renderer investigation, explicit `--pid` can probe non-`NSRunningApplication` PIDs and will report `auxiliaryProcessCapture`.
    When a Codex/Claude consumer needs browser-comment-shaped context, read `codexBrowserPayload.localBrowserContext`, `codexBrowserPayload.localBrowserCommentMetadata`, `codexBrowserPayload.localBrowserAttachedImages`, `codexBrowserPayload.localBrowserDesignChange`, and `codexBrowserPayload.localBrowserScreenshot`. For browser DOM captures, inspect exact Codex-shaped values such as `localBrowserContext.pageUrl`, `frameUrl`, `targetSelector`, `targetImmediateText`, `targetPath`, `localBrowserCommentMetadata.markerViewportPoint`, and `localBrowserDesignChange.group`.
    For Codex browser runtime-state parity, also read `codexBrowserRuntimeState.interactionMode`, `annotationEditorMode`, `isOriginalViewEnabled`, `isDesignModifierPressed`, `isTweaksEditorOpen`, `activeDesignChange`, `viewportScale`, and `zoomPercent`.
    For Codex browser runtime-protocol parity, read `codexBrowserRuntimeProtocol.eventTypes`, `codexBrowserRuntimeProtocol.channel`, `codexBrowserRuntimeProtocol.liveEventStreamAvailable`, and `codexBrowserPayload.localBrowserRuntimeProtocol`.
    For a supported frontmost browser where Apple Events allows page scripting, add `--include-browser-dom` to gather `codexBrowserDOMIntegration.browserRuntimeEvents`, including comment editor, comment preview, screenshot, design scrub, design modifier, image-drag `sourceUrl`, and design-editor `anchorState` / `designEditorState` candidates.
    Read `codexBrowserDOMIntegration.remoteDebuggingTarget` when the page might be a Codex/Electron remote-debugging surface such as `content shell remote debugging`, `inspectable webcontents`, or localhost ports `9222` / `9229`.
    For Electron apps such as VS Code, add `--include-electron-debugging`, or add `--include-browser-dom` when you also want a browser-shaped payload. Read `codexElectronRemoteDebugging.scannedPorts`, `targets`, `selectedTarget`, `cdpSnapshot`, and `reason`. If the reason is `noInspectableTargets`, the app did not expose a Chrome DevTools Protocol WebContents target, so AppShot cannot extract Electron DOM/AX content through CDP for that run.
    When you need a closer Codex browser runtime match, add `--browser-dom-install-bridge` once, interact with the page, then capture with `--include-browser-dom`. Read `codexBrowserDOMIntegration.browserRuntimeBridge`, especially `codexDesktopShimAvailable`, `hostAPI`, `hostChannel`, `browserRuntimeBridgeEvents`, `browserRuntimeCandidateEvents`, and `liveEventStreamAvailable`. The bridge exposes a page-local `window.codex_desktop.sendMessageToHost` / `subscribeToHostMessages` shim, but this is still not Codex's private Electron host IPC. Use `--browser-dom-clear-bridge-log` to clear the tab-local bridge log before a new run.
15. Add `--include-screenshot --screenshot <path.png>` when a bitmap file is also needed.
16. Use `--include-ocr` only as an explicit fallback when Accessibility text and document references are empty or the target app does not expose visible content through Accessibility.
17. Treat hidden/offscreen text as best-effort only after permissions are fully enabled: AppShot can only report accessibility content and local document references exposed by the target app, while OCR can only report visible screenshot text.
18. For parity QA against a real app/window, use the repo QA script when available:
   ```sh
   scripts/qa_app_capture.py --bundle-id com.apple.dt.Xcode --window-title 'appshot —' --accessibility-timeout 20 --expect-hierarchy 'Source Editor'
   ```
   A valid QA report checks target-window screenshot metadata, image dimensions against window bounds, OCR-visible text, Accessibility text, and hierarchy anchors.

## Install Notes

- Do not reinstall if `appshot` is already available.
- For a broken macOS privacy state during development, reinstall with:
  ```sh
  curl -sfL https://raw.githubusercontent.com/Shiyao-Huang/appshot/main/install.sh | APPSHOT_RESET_PERMISSIONS=1 bash
  ```
- Privacy reset is opt-in because it forces the user to grant Accessibility and Screen Recording again.

## MCP Tools

- `appshot_capture`: frontmost app metadata, windows, accessibility tree/text, optional screenshot, optional OCR fallback, and optional recent shortcut-cache reuse.
- `appshot_permissions`: Accessibility and Screen Recording permission state.
- `appshot_status`: frontmost app metadata, current window, and permission state.
- `appshot_codex_apps_status`: Codex accessible-connector readiness, including `codexAppsReady`, blockers, MCP tool surface, and force-refetch guidance.
- `appshot_codex_computer_use_status`: Codex Computer Use service, app approval, and host bridge parity diagnostics.
- `appshot_list_windows`: visible windows grouped by running app.
- `list_apps`: Computer Use-compatible alias for running app discovery.
- `get_app_state`: Computer Use-compatible alias that returns Codex-style appshot text plus PNG image content.

## Output

The CLI returns JSON with:

- `frontmostApplication`
- `currentApplication`
- `targetApplication` for capture output
- `permissions.identity`
- `permissions.stability`
- `codexAppsStatus`
- `codexAppsStatus.codexAppsReady`
- `codexAppsStatus.forceRefetchSupported`
- `codexAppsStatus.retryWhenNotReady`
- `codexAppsStatus.tools`
- `codexAppsStatus.blockers`
- `codexComputerUseStatus`
- `codexComputerUseStatus.hostBridge`
- `codexComputerUseStatus.appApprovals`
- `primaryWindow`
- `frontmostWindow`
- `currentWindow`
- `windows`
- `accessibilityWindows`
- `windowDiscovery`
- `windowDiscovery.preferredAccessibilityWindow`
- `windowDiscovery.hasAccessibilityOnlyWindows`
- `screenshot.captureMode`
- `targetActivation`
- `targetActivation.frontmostMatchedTarget`
- `appCaptureRequest`
- `appCaptureRequest.reason`
- `auxiliaryProcessCapture`
- `captureCache`
- `codexBrowserSettings`
- `codexBrowserSettings.browser-annotation-screenshots-mode`
- `codexBrowserRuntimeState`
- `codexBrowserRuntimeState.interactionMode`
- `codexBrowserRuntimeState.annotationEditorMode`
- `codexBrowserRuntimeState.isOriginalViewEnabled`
- `codexBrowserRuntimeState.isDesignModifierPressed`
- `codexBrowserRuntimeState.isTweaksEditorOpen`
- `codexBrowserRuntimeState.activeDesignChange`
- `codexBrowserRuntimeProtocol`
- `codexBrowserRuntimeProtocol.eventTypes`
- `codexBrowserRuntimeProtocol.channel`
- `codexBrowserRuntimeProtocol.liveEventStreamAvailable`
- `codexBrowserDOMIntegration`
- `codexBrowserDOMIntegration.browserRuntimeBridge`
- `codexBrowserDOMIntegration.browserRuntimeBridge.codexDesktopShimAvailable`
- `codexBrowserDOMIntegration.browserRuntimeBridge.hostAPI`
- `codexBrowserDOMIntegration.browserRuntimeBridge.hostChannel`
- `codexBrowserDOMIntegration.browserRuntimeBridgeEvents`
- `codexBrowserDOMIntegration.browserRuntimeCandidateEvents`
- `codexBrowserDOMIntegration.browserRuntimeEvents`
- `codexBrowserDOMIntegration.browserRuntimeEventTypes`
- `codexBrowserDOMIntegration.liveEventStreamAvailable`
- `codexBrowserDOMIntegration.remoteDebuggingTarget`
- `codexBrowserDOMIntegration.remoteDebuggingTarget.isRemoteDebuggingTarget`
- `codexBrowserDOMIntegration.localBrowserAttachedImages`
- `codexElectronRemoteDebugging`
- `codexElectronRemoteDebugging.scannedPorts`
- `codexElectronRemoteDebugging.targets`
- `codexElectronRemoteDebugging.selectedTarget`
- `codexElectronRemoteDebugging.cdpSnapshot`
- `codexElectronRemoteDebugging.domSnapshot`
- `codexBrowserPayload`
- `codexBrowserPayload.localBrowserContext`
- `codexBrowserPayload.localBrowserContext.pageUrl`
- `codexBrowserPayload.localBrowserContext.frameUrl`
- `codexBrowserPayload.localBrowserContext.targetSelector`
- `codexBrowserPayload.localBrowserContext.targetImmediateText`
- `codexBrowserPayload.localBrowserContext.targetPath`
- `codexBrowserPayload.localBrowserCommentMetadata`
- `codexBrowserPayload.localBrowserCommentMetadata.markerViewportPoint`
- `codexBrowserPayload.localBrowserCommentMetadata.browserDOMIntegration.remoteDebuggingTarget`
- `codexBrowserPayload.localBrowserCommentMetadata.electronRemoteDebugging`
- `codexBrowserPayload.localBrowserAttachedImages`
- `codexBrowserPayload.localBrowserDesignChange`
- `codexBrowserPayload.localBrowserDesignChange.group`
- `codexBrowserPayload.localBrowserRuntimeState`
- `codexBrowserPayload.localBrowserRuntimeProtocol`
- `codexBrowserPayload.localBrowserRuntimeEvents`
- `codexBrowserPayload.localBrowserScreenshot`
- `accessibility.root`
- `accessibility.rootSource`
- `accessibility.targetWindowMatch`
- `accessibility.targetWindowMatch.bestCandidateIsAXWindow`
- `accessibility.targetWindowMatch.axWindowExposure`
- `accessibility.targetWindowMatch.axWindowExposure.suspectedSelfReferentialAXWindows`
- `accessibility.focusedElement`
- `accessibility.electronAccessibility`
- `accessibility.electronAccessibility.attempts`
- `accessibility.text`
- `accessibility.documentReferences`
- `codex.format`
- `codex.text`
- optional `screenshot`
- optional `ocr.text`
- optional `ocr.observations`

Prefer citing exact JSON fields instead of summarizing vaguely.

A valid test should report `permissions.accessibility: true` and `permissions.screenRecording: true`. If either value is false, report the missing permission instead of calling the AppShot test successful.
A valid Codex or Claude Code troubleshooting capture should include a complete `codex.text` block and meaningful `accessibility.text`. If Accessibility text is empty, report that AX did not expose readable text and only then consider `--include-ocr` as fallback.
