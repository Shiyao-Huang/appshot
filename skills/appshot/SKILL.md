---
name: appshot
description: Capture the current macOS app context for Codex using AppShot. If AppShot is not installed locally, bootstrap it first, then use the appshot CLI or MCP server for frontmost app metadata, visible windows, accessibility text/UI tree, optional screenshot, and optional OCR fallback.
---

# AppShot

Use this skill when the user asks to inspect the current Mac app, capture Appshots, gather app/window context, debug UI state, or provide richer context than a bitmap screenshot.

Primary goal: make AppShot fully usable for Codex through Accessibility first: capture the app, find the UI tree/text evidence directly, then act on it. Both Accessibility and Screen Recording permissions must be enabled before treating a capture as successful.

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
5. If either `accessibility` or `screenRecording` is `false`, treat that as the blocker to solve first. Prompt/open the macOS permission pane as needed, then re-run the permission check until both are `true`.
6. Capture context only after both permissions are enabled. Default to Accessibility capture:
   ```sh
   "$APPSHOT_BIN" capture --pretty --max-depth 10
   ```
7. If the user refers to a non-frontmost or described window, call `"$APPSHOT_BIN" list-windows --pretty` first. Pick the right `windowID`, `pid`, or `bundleID` yourself from the structured window list, then pass it to capture, e.g. `"$APPSHOT_BIN" capture --window-id 123 --pretty --max-depth 10`.
8. Read `accessibility.root`, `accessibility.focusedElement`, `accessibility.text`, and `accessibility.documentReferences[].textPreview` first. This is the primary Codex path.
9. Add `--include-screenshot --screenshot <path.png>` when a bitmap file is also needed.
10. Use `--include-ocr` only as an explicit fallback when Accessibility text and document references are empty or the target app does not expose visible content through Accessibility.
11. Treat hidden/offscreen text as best-effort only after permissions are fully enabled: AppShot can only report accessibility content and local document references exposed by the target app, while OCR can only report visible screenshot text.

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
- `appshot_list_windows`: visible windows grouped by running app.

## Output

The CLI returns JSON with:

- `frontmostApplication`
- `primaryWindow`
- `windows`
- `accessibility.root`
- `accessibility.focusedElement`
- `accessibility.text`
- `accessibility.documentReferences`
- optional `screenshot`
- optional `ocr.text`
- optional `ocr.observations`

Prefer citing exact JSON fields instead of summarizing vaguely.

A valid test should report `permissions.accessibility: true` and `permissions.screenRecording: true`. If either value is false, report the missing permission instead of calling the AppShot test successful.
A valid Codex troubleshooting capture should include meaningful `accessibility.text`. If Accessibility text is empty, report that AX did not expose readable text and only then consider `--include-ocr` as fallback.
