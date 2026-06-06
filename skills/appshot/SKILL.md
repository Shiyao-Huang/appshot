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
5. Inspect both the booleans and the identity fields: `permissions.accessibility`, `permissions.screenRecording`, `permissions.identity`, and `permissions.stability`.
6. If either `accessibility` or `screenRecording` is `false`, treat that as the blocker to solve first. Prompt/open the macOS permission pane as needed, then re-run the permission check until both are `true`.
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
7. Capture context only after both permissions are enabled. Default to the Codex-style appshot block when the result will be shown to Codex, Claude Code, or the user:
   ```sh
   "$APPSHOT_BIN" capture --format codex --max-depth 10
   ```
   Use JSON when you need to inspect exact fields or automate checks:
   ```sh
   "$APPSHOT_BIN" capture --pretty --max-depth 10
   ```
8. For complex apps such as Xcode, raise the Accessibility timeout instead of treating a slow AX tree as missing data:
   ```sh
   "$APPSHOT_BIN" capture --pretty --max-depth 10 --accessibility-timeout 20
   ```
9. If the user refers to a non-frontmost or described window, call `"$APPSHOT_BIN" list-windows --pretty` first. Pick the right `windowID`, `pid`, or `bundleID` yourself from the structured window list, then pass it to capture, e.g. `"$APPSHOT_BIN" capture --window-id 123 --pretty --max-depth 10`.
10. Read `codex.text` first for Codex-compatible context. For debugging, read `accessibility.root`, `accessibility.focusedElement`, `accessibility.text`, and `accessibility.documentReferences[].textPreview`.
11. Add `--include-screenshot --screenshot <path.png>` when a bitmap file is also needed.
12. Use `--include-ocr` only as an explicit fallback when Accessibility text and document references are empty or the target app does not expose visible content through Accessibility.
13. Treat hidden/offscreen text as best-effort only after permissions are fully enabled: AppShot can only report accessibility content and local document references exposed by the target app, while OCR can only report visible screenshot text.
14. For parity QA against a real app/window, use the repo QA script when available:
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

- `appshot_capture`: frontmost app metadata, windows, accessibility tree/text, optional screenshot, and optional OCR fallback.
- `appshot_permissions`: Accessibility and Screen Recording permission state.
- `appshot_status`: frontmost app metadata, current window, and permission state.
- `appshot_list_windows`: visible windows grouped by running app.

## Output

The CLI returns JSON with:

- `frontmostApplication`
- `currentApplication`
- `targetApplication` for capture output
- `permissions.identity`
- `permissions.stability`
- `primaryWindow`
- `frontmostWindow`
- `currentWindow`
- `windows`
- `accessibility.root`
- `accessibility.focusedElement`
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
