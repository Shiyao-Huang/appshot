# Codex Parity Matrix

## Layered Summary

One sentence: AppShot must expose extracted macOS app context in the same shape and operational spirit as the Codex Mac app's built-in appshot/browser annotation surfaces.

Three sentences: The strongest local evidence is the extracted Codex Mac app bundle under `../codex-522/mac-app`, especially runtime event lists, app-session snippets, and the architecture note. AppShot currently implements the native macOS app/window/accessibility/screenshot side and exposes it through CLI, MCP, skill, plugin, release packaging, a Codex browser-comment payload adapter, and the `browser-annotation-screenshots-mode` policy surface. Browser annotation design/tweaks/image-drag behavior is evidence-tracked but not implemented in AppShot because it belongs to Codex's embedded browser runtime, not a standalone macOS capture tool.

Five sentences: The current hard gate is `scripts/verify_codex_parity.sh`. It checks local Codex evidence, AppShot JSON aliases, MCP tool output, and version alignment. Passing the gate proves the implemented subset did not drift from the known Codex evidence it claims to match. It does not prove full parity with every Codex internal appshot behavior. New parity work should add evidence first, then add or update a matrix row, then tighten the verifier.

## Evidence Sources

| Evidence | Path | Used For |
| --- | --- | --- |
| Codex Mac app architecture | `../codex-522/mac-app/docs/appshots-macapp-architecture.md` | Scope, version boundary, browser appshots architecture |
| Runtime events | `../codex-522/mac-app/artifacts/comment-preload-runtime-events-522.txt` | Browser sidebar event names |
| App session snippets | `../codex-522/mac-app/appshots-evidence/522-app-session-appshots-snippets.js` | Settings and thread payload keys |
| Browser preload snippets | `../codex-522/mac-app/appshots-evidence/522-appshots-snippets.js` | Host/preload sync keys and emitted runtime events |
| AppShot verifier | `scripts/verify_codex_parity.sh` | Executable local gate |

## Implemented And Verified

| Area | Codex Evidence | AppShot Surface | Verification |
| --- | --- | --- | --- |
| Front/current app identity | `frontmostApplication`, `currentApplication` in Codex native-module strings | `frontmostApplication`, `currentApplication`, `targetApplication` in `status`/`capture` JSON | `scripts/verify_codex_parity.sh` CLI and MCP checks |
| Front/current window identity | `FrontmostWindow`, `frontmostWindow`, `CGWindow` in Codex native-module strings | `primaryWindow`, `frontmostWindow`, `currentWindow`, `windowID`, `windowNumber` | `scripts/verify_codex_parity.sh` CLI and MCP checks |
| Screen/display metadata | `NSScreen`, `CGWindow` in Codex native-module strings | best-effort `screen.displayID/frame/isMain` or `screen.localizedName/frame/visibleFrame/backingScaleFactor` | CLI capture/list-windows checks plus Swift build |
| Native App build | Extracted AppShot must ship as a real macOS app, not only a CLI/MCP surface | `AppShot.xcodeproj` scheme `AppShot`, bundle id `com.qppshot.AppShot`, version `0.1.3` | `scripts/verify_codex_parity.sh` Xcode build, bundle plist, executable, and codesign checks |
| Accessibility-first text | Codex appshot goal is structured context before OCR fallback | `accessibility.root`, `focusedElement`, `documentReferences`, `text`, `textLineCount` | `scripts/verify_codex_parity.sh` capture schema check |
| Codex appshot text block | User-visible Codex appshots are XML-like `<appshot ...>` blocks with `Window:`, localized AX role lines, selected-context notes, and stable image/window attributes | `codex.format == "codex-appshot-text"`, `codex.text`, CLI `--format codex` / `--codex`, MCP `format: "codex"`, settable annotations including VS Code `AXGroup` containers, compact row/control formatting, and duplicate structural/WebArea line pruning | `scripts/verify_codex_parity.sh` schema, source-anchor, and CLI text checks |
| Visible reading order | Codex-style app context should expose a readable visible text stream, not only raw tree order | `accessibility.visibleText`, `visibleTextLineCount`, coordinate-sorted AX text entries, and `AXBoundsForRange` / `AXStringForRange` line fragments for large text controls | `scripts/verify_codex_parity.sh` schema and source-anchor checks plus Xcode QA artifacts |
| Deep VS Code panels | Codex appshots include nested VS Code terminal/output/chat panel text, not only the editor/welcome page | default `maxDepth` is 60 across Core, App, CLI, MCP, and skill examples so bottom panel terminal content is reached without custom flags | `scripts/verify_codex_parity.sh` default-depth anchors plus manual VS Code `Welcome — iosbash` comparison |
| Shortcut capture cache | User-directed AppShot should preserve the exact window the user just indicated for CLI/MCP consumers | App global shortcut `Left Option + Right Option` writes a shared `captureCache`; CLI/MCP capture reads recent cache by default and supports `--ignore-cache` / `--no-cache` / `--fresh` / `useRecentCache: false` / `preferRecentCache: false` for fresh direct capture, plus explicit `writeCache` and `cacheTrigger` controls | `scripts/verify_codex_parity.sh` source-anchor and CLI/MCP schema checks |
| Browser comment payload adapter | Codex browser comments are assembled with `localBrowserContext`, `localBrowserCommentMetadata`, `localBrowserAttachedImages`, `localBrowserDesignChange`, and `localBrowserScreenshot` | `codexBrowserPayload` maps native AppShot app/window/AX/screenshot evidence into those Codex field names with `format == "codex-browser-comment-payload-adapter"` | `scripts/verify_codex_parity.sh` source-anchor and capture schema checks |
| Browser annotation screenshot policy | `browser-annotation-screenshots-mode`, `always`, `necessary`, and description `When browser annotation screenshots are included` | `codexBrowserSettings`, `localBrowserCommentMetadata.annotationScreenshotsMode`, CLI `--browser-annotation-screenshots-mode always|necessary`, MCP `browserAnnotationScreenshotsMode`, and App Settings `Browser Screenshots`; `always` triggers a screenshot for `codexBrowserPayload` | `scripts/verify_codex_parity.sh` source-anchor, CLI schema, and policy capture checks |
| App/window QA | User-visible parity requires screenshot, OCR-visible text, AX text, and hierarchy checks for real apps | `scripts/qa_app_capture.py` captures a target window and validates target-window screenshot metadata, window-bound image dimensions, AX/OCR text, and target AX hierarchy anchors | Xcode QA artifacts under `artifacts/xcode-parity` |
| TCC identity diagnosis | Codex-style app capture must run under the app identity the user actually authorized | `scripts/diagnose_tcc_identity.sh` reports installed/debug/CLI paths, bundle identifiers, signing mode, and `CDHash` drift | Manual diagnosis plus verifier anchors |
| Permission identity JSON | Codex built-in appshot runs inside a stable signed app identity; AppShot must make mismatched local identities visible | `permissions.identity` and `permissions.stability` report the checking executable, mode, stable grant target, warning, and recovery steps | CLI/MCP schema checks plus `scripts/verify_codex_parity.sh` anchors |
| Screenshot/OCR fallback | Codex browser annotation screenshot events and AppShot README scope | explicit `--include-screenshot`, `--include-ocr` | CLI options and release docs |
| MCP integration | Codex consumption path needs tool-callable context | `appshot_capture`, `appshot_permissions`, `appshot_status`, `appshot_list_windows` | `scripts/verify_codex_parity.sh` MCP smoke test |
| Version/package alignment | Extracted app/plugin must match release identity | plugin, MCP package, MCP server, installer, release script at `0.1.3` | `scripts/verify_codex_parity.sh` version alignment |

## Evidence-Tracked But Not Implemented

| Area | Codex Evidence | Why Not Claimed Complete | Next Concrete Step |
| --- | --- | --- | --- |
| Design editor/tweaks | `browser-sidebar-runtime-open-design-editor`, `design-scrub`, `isTweaksEditorOpen` | Requires DOM element targeting and Codex browser host/preload IPC | Keep evidence checked; do not present AppShot as implementing this |
| Image drag metadata | `browser-sidebar-runtime-image-drag-started`, `browser-sidebar-runtime-image-drag-ended`, `sourceUrl` | Requires browser page drag instrumentation | Add only with a browser integration layer |
| Original view/design modifier state | `isOriginalViewEnabled`, `isDesignModifierPressed`, `activeDesignChange` | Browser runtime state, not macOS AX/window state | Preserve as evidence gate until implementation exists |

## Verification Contract

Run:

```sh
scripts/verify_codex_parity.sh
```

The verifier must fail when:

- Local Codex Mac app evidence is missing.
- Required browser appshot/design/image-drag event evidence disappears.
- AppShot CLI output loses Codex-style app/window aliases.
- Native `AppShot.app` no longer builds, loses its executable, changes bundle id/version unexpectedly, or fails codesign verification.
- Accessibility output loses coordinate-sorted `visibleText` / `visibleTextLineCount` or `AXBoundsForRange`-backed line fragments.
- Default capture depth drops below the level needed to reach nested VS Code terminal/output/chat panels.
- Codex text output loses the `<appshot ...>` wrapper, `Window:` header, `codex-appshot-text` format marker, `--format codex` CLI path, MCP `format: "codex"` path, selected-context note, compact row/control rendering, or settable annotations.
- Shortcut capture cache loses the left/right Option trigger, shared `captureCache`, CLI `--ignore-cache` / `--no-cache` / `--fresh`, or MCP `useRecentCache` / `preferRecentCache` / `writeCache` controls.
- Browser comment adapter output loses `codexBrowserPayload`, `codex-browser-comment-payload-adapter`, or the Codex field names `localBrowserContext`, `localBrowserCommentMetadata`, `localBrowserAttachedImages`, `localBrowserDesignChange`, and `localBrowserScreenshot`.
- Browser annotation screenshot policy loses `browser-annotation-screenshots-mode`, `always`, `necessary`, CLI `--browser-annotation-screenshots-mode`, MCP `browserAnnotationScreenshotsMode`, App Settings `Browser Screenshots`, or the `always` screenshot behavior.
- `scripts/qa_app_capture.py` loses its target-window screenshot, window-bound image size, OCR, AX text, or hierarchy checks.
- `scripts/diagnose_tcc_identity.sh` stops explaining bundle/signing/`CDHash` identity drift.
- Permission JSON loses `identity` or `stability`, making CLI/App/MCP TCC drift invisible.
- MCP tools disappear or stop returning the verified aliases.
- Package versions drift across plugin, MCP, installer, or release scripts.
- This matrix loses its core implemented and evidence-tracked anchors.

## Completion Rule

Do not mark full Codex parity complete until every evidence-tracked row is either implemented with a verifier-backed surface or explicitly removed because updated Codex evidence proves it is out of scope.
