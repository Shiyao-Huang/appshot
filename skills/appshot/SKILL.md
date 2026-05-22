---
name: appshot
description: Capture the current macOS app context for Codex using the local appshot CLI or MCP server, including frontmost app metadata, visible windows, accessibility text/UI tree, and optional screenshot.
---

# AppShot

Use this skill when the user asks to inspect the current Mac app, capture Appshots, gather app/window context, debug UI state, or provide richer context than a bitmap screenshot.

## Workflow

1. Build the native CLI if needed: `swift build` from the plugin root.
2. Check permissions: `.build/debug/appshot permissions --prompt --pretty`.
3. Capture context: `.build/debug/appshot capture --pretty --max-depth 6`.
4. Add `--include-screenshot --screenshot <path.png>` when a bitmap is also needed.
5. Treat hidden/offscreen text as best-effort: AppShot can only report accessibility content exposed by the target app.

## MCP Tools

- `appshot_capture`: frontmost app metadata, windows, accessibility tree, optional screenshot.
- `appshot_permissions`: Accessibility and Screen Recording permission state.
- `appshot_list_windows`: visible windows grouped by running app.

## Output

The CLI returns JSON with:

- `frontmostApplication`
- `primaryWindow`
- `windows`
- `accessibility.root`
- optional `screenshot`

Prefer citing exact JSON fields instead of summarizing vaguely.
