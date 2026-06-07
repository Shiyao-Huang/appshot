#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE_ROOT="$(cd "$ROOT/.." && pwd)"
CODEX_EVIDENCE_ROOT="${CODEX_EVIDENCE_ROOT:-$WORKSPACE_ROOT/codex-522/mac-app}"
CODEX_FOCUSED_DIFF="${CODEX_FOCUSED_DIFF:-$WORKSPACE_ROOT/codex-522/artifacts/appshots-focused-diff-v0.132.0..v0.133.0.patch}"
APP_BIN="${APPSHOT_BIN:-$ROOT/.build/debug/appshot}"
PYTHON="${PYTHON:-/usr/bin/python3}"
XCODE_DERIVED_DATA="${APPSHOT_XCODE_DERIVED_DATA:-$ROOT/.xcode-build/ParityDerivedData}"
XCODE_PRODUCTS="${APPSHOT_XCODE_PRODUCTS:-$ROOT/.xcode-build/ParityProducts}"
APP_BUNDLE="$XCODE_PRODUCTS/Debug/AppShot.app"
PARITY_MATRIX="$ROOT/docs/codex-parity.md"
QA_SCRIPT="$ROOT/scripts/qa_app_capture.py"
TCC_SCRIPT="$ROOT/scripts/diagnose_tcc_identity.sh"
SKILL_FILE="$ROOT/skills/appshot/SKILL.md"

log() {
  printf 'appshot parity: %s\n' "$*"
}

fail() {
  printf 'appshot parity: error: %s\n' "$*" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "missing required evidence/file: $path"
}

require_contains() {
  local path="$1"
  local needle="$2"
  grep -Fq -- "$needle" "$path" || fail "missing '$needle' in $path"
}

log "building Swift products"
(cd "$ROOT" && swift build >/dev/null)
[[ -x "$APP_BIN" ]] || fail "appshot binary is not executable: $APP_BIN"

log "building native App target"
(cd "$ROOT" && xcodebuild -quiet \
  -project AppShot.xcodeproj \
  -scheme AppShot \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$XCODE_DERIVED_DATA" \
  SYMROOT="$XCODE_PRODUCTS" \
  build >/dev/null)
[[ -d "$APP_BUNDLE" ]] || fail "App bundle was not built: $APP_BUNDLE"
[[ -x "$APP_BUNDLE/Contents/MacOS/AppShot" ]] || fail "App executable is not runnable: $APP_BUNDLE/Contents/MacOS/AppShot"
codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null

EVENTS="$CODEX_EVIDENCE_ROOT/artifacts/comment-preload-runtime-events-522.txt"
APP_SESSION_SNIPPETS="$CODEX_EVIDENCE_ROOT/appshots-evidence/522-app-session-appshots-snippets.js"
PRELOAD_SNIPPETS="$CODEX_EVIDENCE_ROOT/appshots-evidence/522-appshots-snippets.js"
COMMENT_PRELOAD="$CODEX_EVIDENCE_ROOT/asar-522/.vite/build/comment-preload.js"

log "checking Codex Mac app evidence"
require_file "$EVENTS"
require_file "$APP_SESSION_SNIPPETS"
require_file "$PRELOAD_SNIPPETS"
require_file "$COMMENT_PRELOAD"
require_file "$CODEX_FOCUSED_DIFF"
require_file "$PARITY_MATRIX"
require_file "$QA_SCRIPT"
require_file "$TCC_SCRIPT"
require_file "$SKILL_FILE"

for event in \
  browser-sidebar-runtime-clear-comment-screenshot \
  browser-sidebar-runtime-close-comment-preview \
  browser-sidebar-runtime-close-editor \
  browser-sidebar-runtime-prepare-comment-screenshot \
  browser-sidebar-runtime-comment-screenshot-ready \
  browser-sidebar-runtime-create-comment-at-point \
  browser-sidebar-runtime-design-modifier-state \
  browser-sidebar-runtime-design-scrub-changed \
  browser-sidebar-runtime-exit-comment-mode \
  browser-sidebar-runtime-focus-editor \
  browser-sidebar-runtime-image-drag-ended \
  browser-sidebar-runtime-image-drag-started \
  browser-sidebar-runtime-message \
  browser-sidebar-runtime-mouse-navigation \
  browser-sidebar-runtime-open-comment-preview \
  browser-sidebar-runtime-open-editor \
  browser-sidebar-runtime-open-design-editor \
  browser-sidebar-runtime-open-design-editor-at-point \
  browser-sidebar-runtime-restore-editor \
  browser-sidebar-runtime-select-comment \
  browser-sidebar-runtime-sync \
  browser-sidebar-runtime-update-anchor
do
  require_contains "$EVENTS" "$event"
done

for key in \
  browser-annotation-screenshots-mode \
  localBrowserContext \
  localBrowserScreenshot \
  localBrowserAttachedImages \
  localBrowserDesignChange
do
  require_contains "$APP_SESSION_SNIPPETS" "$key"
done

for key in \
  activeDesignChange \
  annotationEditorMode \
  isDesignModifierPressed \
  isOriginalViewEnabled \
  isTweaksEditorOpen
do
  require_contains "$PRELOAD_SNIPPETS" "$key"
done

for key in \
  'sendMessageToHost(e){d.ipcRenderer.invoke(ke,e)}' \
  'subscribeToHostMessages(e){Hf=!0' \
  'd.ipcRenderer.on(Oe' \
  'codex_desktop:browser-sidebar-runtime-message'
do
  require_contains "$COMMENT_PRELOAD" "$key"
done

for key in \
  AccessibleConnectorsStatus \
  codex_apps_ready \
  force_refetch \
  ConnectorsSnapshot
do
  require_contains "$CODEX_FOCUSED_DIFF" "$key"
done

log "checking parity matrix anchors"
for anchor in \
  "Implemented And Verified" \
  "Evidence-Tracked But Not Implemented" \
  "frontmostApplication" \
  "currentApplication" \
  "targetApplication" \
  "frontmostWindow" \
  "windowNumber" \
  "localBrowserContext" \
  "localBrowserCommentMetadata" \
  "localBrowserScreenshot" \
  "localBrowserAttachedImages" \
  "localBrowserDesignChange" \
  "codexBrowserPayload" \
  "codexBrowserRuntimeState" \
  "codexBrowserRuntimeProtocol" \
  "codexBrowserDOMIntegration" \
  "browserRuntimeBridge" \
  "browserRuntimeBridgeEvents" \
  "browserRuntimeCandidateEvents" \
  "appshot-browser-runtime-bridge" \
  "codexDesktopShimAvailable" \
  "nativeCodexDesktopAvailable" \
  "codexHostBridgeAvailable" \
  "window.codex_desktop" \
  "extensionHelperAvailable" \
  "electronHostBridgeAvailable" \
  "hostAPI" \
  "hostChannel" \
  "hostOwner" \
  "hostTransport" \
  "window.postMessage+extension-runtime" \
  "electron-ipc" \
  "browser-extension/appshot-bridge" \
  "electron-preload/appshot-host-bridge" \
  "codex-integration/appshot-codex-host-bridge" \
  "codex-host-adapter.cjs" \
  "codexHostIntegration" \
  "privateCodexWebviewHostAttached" \
  "codex-electron-host" \
  "codex-electron-ipc" \
  "codex-electron-ipc+appshot-electron-ipc" \
  "Browser runtime bridge event log" \
  "codex-browser-runtime-state-adapter" \
  "codex-browser-runtime-protocol-adapter" \
  "codex-browser-dom-integration" \
  "codex-browser-comment-payload-adapter" \
  "browser-annotation-screenshots-mode" \
  "Browser annotation screenshot policy" \
  "Browser runtime state adapter" \
  "Browser Bridge" \
  "--browser-dom-install-bridge" \
  "--browser-dom-clear-bridge-log" \
  "browser-sidebar-runtime-open-design-editor" \
  "browser-sidebar-runtime-image-drag-started" \
  "browser-sidebar-runtime-image-drag-ended" \
  "browser-sidebar-runtime-create-comment-at-point" \
  "browser-sidebar-runtime-update-anchor" \
  "browser-sidebar-runtime-design-modifier-state" \
  "isOriginalViewEnabled" \
  "isDesignModifierPressed" \
  "activeDesignChange" \
  "scripts/qa_app_capture.py" \
  "target-window screenshot metadata" \
  "window-bound image dimensions" \
  "TCC identity diagnosis" \
  "Permission identity JSON" \
  "Codex apps readiness surface" \
  "codexAppsReady" \
  "AccessibleConnectorsStatus" \
  "Deep VS Code panels" \
  "maxDepth" \
  "Shortcut capture cache" \
  "captureCache" \
  "--ignore-cache" \
  "useRecentCache" \
  "Codex appshot text block" \
  "codex-appshot-text" \
  "--format codex" \
  "selected-context note" \
  "settable annotations" \
  "permissions.identity" \
  "permissions.stability" \
  "Do not mark full Codex parity complete"
do
  require_contains "$PARITY_MATRIX" "$anchor"
done

log "checking package version alignment"
"$PYTHON" - "$ROOT" "$APP_BUNDLE" "$CODEX_EVIDENCE_ROOT" <<'PY'
import json
import pathlib
import plistlib
import re
import sys

root = pathlib.Path(sys.argv[1])
app_bundle = pathlib.Path(sys.argv[2])
codex_evidence_root = pathlib.Path(sys.argv[3])
plugin = json.loads((root / ".codex-plugin/plugin.json").read_text())
mcp = json.loads((root / "mcp/package.json").read_text())
extension_manifest = json.loads((root / "browser-extension/appshot-bridge/manifest.json").read_text())
extension_page = (root / "browser-extension/appshot-bridge/page-bridge.js").read_text()
extension_content = (root / "browser-extension/appshot-bridge/content.js").read_text()
extension_background = (root / "browser-extension/appshot-bridge/background.js").read_text()
electron_preload = (root / "electron-preload/appshot-host-bridge/preload.cjs").read_text()
electron_host = (root / "electron-preload/appshot-host-bridge/host.cjs").read_text()
electron_host_readme = (root / "electron-preload/appshot-host-bridge/README.md").read_text()
codex_host_adapter = (root / "codex-integration/appshot-codex-host-bridge/codex-host-adapter.cjs").read_text()
codex_host_readme = (root / "codex-integration/appshot-codex-host-bridge/README.md").read_text()
codex_host_verifier = (root / "scripts/verify_codex_host_integration.mjs").read_text()
server = (root / "mcp/server.js").read_text()
installer = (root / "install.sh").read_text()
release = (root / "scripts/build_release.sh").read_text()
app = (root / "Sources/AppShotApp/AppShotApp.swift").read_text()
cli = (root / "Sources/AppShotCLI/AppShotCLI.swift").read_text()
core = (root / "Sources/AppShotCore/AppShotCore.swift").read_text()
parity = (root / "docs/codex-parity.md").read_text()
app_session = (codex_evidence_root / "appshots-evidence/522-app-session-appshots-snippets.js").read_text()
comment_preload = (codex_evidence_root / "asar-522/.vite/build/comment-preload.js").read_text()
qa = (root / "scripts/qa_app_capture.py").read_text()
tcc = (root / "scripts/diagnose_tcc_identity.sh").read_text()
skill = (root / "skills/appshot/SKILL.md").read_text()

expected = "0.1.14"
checks = {
    "plugin version": plugin.get("version"),
    "mcp package version": mcp.get("version"),
    "browser bridge extension version": extension_manifest.get("version"),
}
for name, value in checks.items():
    if value != expected:
        raise SystemExit(f"{name} is {value!r}, expected {expected!r}")

info_plist = app_bundle / "Contents/Info.plist"
executable = app_bundle / "Contents/MacOS/AppShot"
if not info_plist.exists():
    raise SystemExit(f"native app missing Info.plist: {info_plist}")
if not executable.exists():
    raise SystemExit(f"native app missing executable: {executable}")
info = plistlib.loads(info_plist.read_bytes())
native_checks = {
    "native app bundle id": info.get("CFBundleIdentifier"),
    "native app version": info.get("CFBundleShortVersionString"),
    "native app executable": info.get("CFBundleExecutable"),
}
expected_native = {
    "native app bundle id": "com.qppshot.AppShot",
    "native app version": expected,
    "native app executable": "AppShot",
}
for name, value in native_checks.items():
    expected_value = expected_native[name]
    if value != expected_value:
        raise SystemExit(f"{name} is {value!r}, expected {expected_value!r}")

version_re = re.escape(expected)
for name, text, pattern in [
    ("mcp server", server, rf'version:\s*"{version_re}"'),
    ("core browser bridge", core, rf'appshotBridgeVersion\s*=\s*"{version_re}"'),
    ("browser bridge page helper", extension_page, rf'const version = "{version_re}"'),
    ("installer default", installer, rf'VERSION="\$\{{APPSHOT_VERSION:-{version_re}\}}"'),
    ("release default", release, rf'VERSION="\$\{{1:-{version_re}\}}"'),
]:
    if not re.search(pattern, text):
        raise SystemExit(f"{name} is not aligned to {expected}")

for name, text, needles in [
    ("App shortcut/settings", app, ["OptionPairShortcutMonitor", "Left Option + Right Option", "AppShotSettingsView", "isGlobalShortcutEnabled", "writeCache", "captureCacheSummary", "left-right-option", "appShotCaptureRequestNotificationName", "appShotCaptureRequestCacheTrigger", "handleAppCaptureRequest", "browserAnnotationScreenshotsMode", "Browser Screenshots", "browserAnnotationEditorMode", "Browser Editor", "browserOriginalViewEnabled", "browserDesignModifierPressed", "browserTweaksEditorOpen", "includeBrowserDOM", "Browser DOM", "browserDOMInstallBridge", "Browser Bridge"]),
    ("CLI timeout/options", cli, ["--accessibility-timeout", "--screenshot-timeout", "--activate-target", "--no-activate-target", "--request-app-capture", "--app-capture-timeout", "--window-title", "--format", "--codex", "format == \"codex\"", "--ignore-cache", "--cache-max-age", "--write-cache", "--browser-annotation-screenshots-mode", "--browser-annotation-editor-mode", "--browser-original-view-enabled", "--browser-design-modifier-pressed", "--browser-tweaks-editor-open", "--browser-active-design-change-json", "--include-browser-dom", "--browser-dom-timeout", "--browser-dom-fixture-json", "--browser-dom-install-bridge", "--browser-dom-clear-bridge-log", "--include-electron-debugging", "--electron-debugging-timeout"]),
    ("MCP timeout/schema/format", server, ["accessibilityTimeout", "screenshotTimeout", "activateTarget", "requestAppCapture", "appCaptureTimeout", "windowTitle", "--window-title", "format", "\"codex\"", "--format", "useRecentCache", "preferRecentCache", "cacheMaxAge", "writeCache", "cacheTrigger", "--no-cache", "browserAnnotationScreenshotsMode", "browserAnnotationEditorMode", "browserOriginalViewEnabled", "browserDesignModifierPressed", "browserTweaksEditorOpen", "browserActiveDesignChange", "includeBrowserDOM", "browserDOMTimeout", "browserDOMFixture", "browserDOMInstallBridge", "browserDOMClearBridgeLog", "includeElectronDebugging", "electronDebuggingTimeout", "get_app_state", "list_apps", "appshot_codex_computer_use_status"]),
    ("Claude Code installer", installer, ["APPSHOT_INSTALL_CLAUDE_CODE", "CLAUDE_SKILL_DIR", "claude mcp add", "APPSHOT_BIN=$BIN_PATH"]),
    ("browser/electron/codex bridge installer/release", installer + release, ["APPSHOT_BROWSER_EXTENSION_DIR", "browser-extension/appshot-bridge", "FOUND_BROWSER_EXTENSION", "load unpacked", "ditto \"$ROOT/browser-extension/appshot-bridge\"", "APPSHOT_ELECTRON_PRELOAD_DIR", "electron-preload/appshot-host-bridge", "FOUND_ELECTRON_PRELOAD", "ditto \"$ROOT/electron-preload/appshot-host-bridge\"", "APPSHOT_CODEX_INTEGRATION_DIR", "codex-integration/appshot-codex-host-bridge", "FOUND_CODEX_INTEGRATION", "ditto \"$ROOT/codex-integration/appshot-codex-host-bridge\""]),
    ("public release gate", release, ["APPSHOT_PUBLIC_RELEASE", "Developer ID Application", "APPSHOT_NOTARY_PROFILE", "stapler validate", "spctl --assess"]),
    ("AX hierarchy safeguards", core, ["isAXDescendantAttribute", "localChildIDs", "focusedVisited", "mainWindowVisited", "targetActivation", "activateCaptureTarget", "appCaptureRequest", "requestGUIAppCapture", "auxiliaryProcessCapture", "captureAuxiliaryProcess", "targetWindowMatch", "matchingAXWindowResult", "axWindowExposure", "suspectedSelfReferentialAXWindows", "targetWindowUnmatchedApplication", "bestCandidateIsAXWindow", "codexIsMenuBarElement", "axShouldCompactRow", "axCompactInteractiveDescendants", "AXGroup"]),
    ("AX window discovery", core + cli + server + parity + skill, ["accessibilityWindows", "windowDiscovery", "accessibilityWindow", "preferredAccessibilityWindow", "hasAccessibilityOnlyWindows", "resolveCaptureTargetByWindowTitle", "--window-title", "captureMode", "screenshotRectArgument", "titlesCompatible"]),
    ("Codex text formatter", core, ["codexSummaryPayload", "codexSummaryText", "codex-appshot-text", "<appshot", "Selected:", "Note: Pay special attention", "codexSettableAnnotation", "codexRoleName", "codexShouldDedupeStructuralLine", "codexShouldUseAccessibilityTextEvidence", "HTML 内容"]),
    ("Codex browser payload adapter", core + server + skill, ["codexBrowserPayload", "codexBrowserPayload(from:", "codex-browser-comment-payload-adapter", "localBrowserContext", "localBrowserCommentMetadata", "localBrowserAttachedImages", "localBrowserDesignChange", "targetImmediateText", "markerViewportPoint", "localBrowserScreenshot", "codexBrowserSettings", "browser-annotation-screenshots-mode", "always", "necessary"]),
    ("Codex browser runtime adapter", core + cli + server + skill, ["codexBrowserRuntimeState", "codexBrowserRuntimeStatePayload", "codex-browser-runtime-state-adapter", "browser-sidebar-runtime-sync", "interactionMode", "annotationEditorMode", "isAgentControllingBrowser", "canUseTweaks", "isDesignModifierPressed", "isOriginalViewEnabled", "isTweaksEditorOpen", "activeDesignChange", "viewportScale", "zoomPercent"]),
    ("Codex browser runtime protocol", core + skill, ["codexBrowserRuntimeProtocol", "codexBrowserRuntimeProtocolPayload", "codex-browser-runtime-protocol-adapter", "codexBrowserRuntimeEventTypes", "codex_desktop:browser-sidebar-runtime-message", "sendMessageToHost", "subscribeToHostMessages", "browser-sidebar-runtime-create-comment-at-point", "browser-sidebar-runtime-update-anchor", "browser-sidebar-runtime-design-modifier-state", "browser-sidebar-runtime-design-scrub-changed", "browser-sidebar-runtime-open-comment-preview", "browser-sidebar-runtime-clear-comment-screenshot", "liveEventStreamAvailable"]),
    ("Codex browser DOM integration", core + cli + server + skill, ["codexBrowserDOMIntegration", "codexBrowserDOMIntegrationPayload", "codex-browser-dom-integration", "browser-apple-events-dom-probe", "includeBrowserDOM", "browserDOMFixture", "browserRuntimeEvents", "localBrowserRuntimeEvents", "browser-sidebar-runtime-image-drag-started", "browser-sidebar-runtime-image-drag-ended", "sourceUrl", "browser-sidebar-runtime-open-design-editor", "browser-sidebar-runtime-open-design-editor-at-point", "browser-sidebar-runtime-create-comment-at-point", "browser-sidebar-runtime-update-anchor", "anchorState", "designEditorState", "browserDOMInstallBridge", "browserDOMClearBridgeLog", "appshot-browser-runtime-bridge", "browserRuntimeBridge", "browserRuntimeBridgeEvents", "browserRuntimeCandidateEvents", "window.codex_desktop", "codexDesktopShimAvailable", "nativeCodexDesktopAvailable", "codexHostBridgeAvailable", "extensionHelperAvailable", "electronHostBridgeAvailable", "hostAPI", "hostChannel", "hostOwner", "hostTransport"]),
    ("Native Codex comment preload evidence", comment_preload + core + parity + skill, ["sendMessageToHost(e){d.ipcRenderer.invoke(ke,e)}", "subscribeToHostMessages(e){Hf=!0", "d.ipcRenderer.on(Oe", "codex_desktop:browser-sidebar-runtime-message", "nativeCodexDesktopAvailable", "codexHostBridgeAvailable", "codex-electron-ipc"]),
    ("Browser bridge extension helper", json.dumps(extension_manifest) + extension_page + extension_content + extension_background + installer + release + parity + skill, ["manifest_version", "service_worker", "content_scripts", "page-bridge.js", "content.js", "background.js", "window.codex_desktop", "sendMessageToHost", "subscribeToHostMessages", "codex_desktop:browser-sidebar-runtime-message", "window.postMessage+extension-runtime", "browser-extension", "extensionHelperAvailable", "hostOwner", "hostTransport"]),
    ("Electron host preload helper", electron_preload + electron_host + electron_host_readme + installer + release + parity + skill, ["preload.cjs", "host.cjs", "window.codex_desktop", "sendMessageToHost", "subscribeToHostMessages", "installAppShotElectronHostBridge", "codex_desktop:browser-sidebar-runtime-message", "electron-preload", "electron-ipc", "electronHostBridgeAvailable", "hostOwner", "hostTransport"]),
    ("Codex host integration adapter", codex_host_adapter + codex_host_readme + codex_host_verifier + core + installer + release + parity + skill, ["codex-host-adapter.cjs", "installAppShotCodexHostBridge", "codex_desktop:browser-sidebar-runtime-message", "sendMessageToHost", "subscribeToHostMessages", "codex-electron-host", "codex-electron-ipc+appshot-electron-ipc", "host-managed-browser-state", "codexHostIntegration", "privateCodexWebviewHostAttached", "scripts/verify_codex_host_integration.mjs"]),
    ("Codex browser remote debugging target", core + app_session + parity + skill, ["remoteDebuggingTarget", "codexBrowserRemoteDebuggingTarget", "content shell remote debugging", "inspectable webcontents", "9222", "9229"]),
    ("Electron CDP remote debugging probe", core + cli + server + parity + skill, ["codexElectronRemoteDebugging", "codexElectronRemoteDebuggingPayload", "codex-electron-remote-debugging", "electron-cdp-probe", "scannedPorts", "selectedTarget", "webSocketDebuggerUrl", "Chrome DevTools Protocol", "Accessibility.getFullAXTree", "Runtime.evaluate", "domSnapshot", "includeElectronDebugging", "--include-electron-debugging"]),
    ("Codex apps readiness surface", core + cli + server + parity + skill, ["codexAppsStatus", "codex-apps-status", "appshot_codex_apps_status", "codex-accessible-connectors-status", "codexAppsReady", "forceRefetchSupported", "retryWhenNotReady", "AccessibleConnectorsStatus", "force_refetch"]),
    ("Codex Computer Use bridge diagnostics", core + cli + server + parity, ["codexComputerUseStatus", "codex-computer-use-status", "codex-computer-use-status", "com.openai.sky.CUAService", "SkyComputerUseService", "SkyComputerUseClient", "ComputerUseAppApprovals.json", "SKY_CUA_NATIVE_PIPE", "x-codex-turn-metadata", "codexTurnMetadata", "requestComputerUseApproval", "get_app_state", "list_apps", "codexHostIntegration", "privateCodexWebviewHostAttached"]),
    ("Electron accessibility unlock", core + parity + skill, ["enableElectronAccessibility", "electronAccessibility", "AXManualAccessibility", "AXEnhancedUserInterface", "enhancedUserInterface", "Electron/VS Code AX unlock"]),
    ("Default deep capture", core + app + cli + server + skill, ["maxDepth: Int = 60", "var maxDepth = 60", "default: 60", "args.maxDepth ?? 60", "--max-depth 60"]),
    ("Shortcut capture cache", core, ["captureCacheStatus", "recentCaptureCache", "payloadByWritingCaptureCache", "captureCacheMetadata", "captureCache", "cacheMaxAgeSeconds"]),
    ("Visible text ordering", core, ["visibleTextLines", "VisibleTextEntry", "visibleTextLineCount", "visibleTextFragments", "AXBoundsForRange", "AXStringForRange"]),
    ("QA capture checks", qa, ["--expect-ax", "--expect-visible", "--expect-ocr", "--expect-hierarchy", "accessibilityWindows", "--window-title", "captureMode", "screenshot captured", "screenshot matches target window", "screenshot size matches window bounds", "visible text available", "accessibility root is target window", "hierarchy contains"]),
    ("TCC identity diagnostics", tcc, ["CDHash", "Signature", "TeamIdentifier", "ad-hoc", "APPSHOT_CODESIGN_IDENTITY", "security find-identity", "permissions.identity", "permissions.stability", "running app bundle"]),
    ("Permission identity JSON", core, ["permissionIdentity", "permissionStability", "recommendedGrantTarget", "currentExecutablePath", "stableInstalledApp", "commandLineTool"]),
    ("Codex skill workflow", skill, ["--accessibility-timeout 20", "--ignore-cache", "left and right Option", "captureCache", "scripts/qa_app_capture.py", "scripts/diagnose_tcc_identity.sh", "tccutil reset Accessibility", "permissions.identity", "permissions.stability", "target-window screenshot metadata", "appshot_status", "currentApplication", "targetApplication", "frontmostWindow", "currentWindow"]),
]:
    missing = [needle for needle in needles if needle not in text]
    if missing:
        raise SystemExit(f"{name} missing anchors: {', '.join(missing)}")
PY

log "checking browser bridge extension helper"
(cd "$ROOT" && node scripts/verify_browser_bridge_extension.mjs >/dev/null)
log "checking Electron host bridge helper"
(cd "$ROOT" && node scripts/verify_electron_host_bridge.mjs >/dev/null)
log "checking Codex host integration adapter"
(cd "$ROOT" && node scripts/verify_codex_host_integration.mjs >/dev/null)

STATUS_JSON="$(mktemp)"
CODEX_APPS_JSON="$(mktemp)"
LIST_WINDOWS_JSON="$(mktemp)"
CAPTURE_JSON="$(mktemp)"
APP_REQUEST_JSON="$(mktemp)"
POLICY_JSON="$(mktemp)"
RUNTIME_JSON="$(mktemp)"
DOM_JSON="$(mktemp)"
ELECTRON_BRIDGE_JSON="$(mktemp)"
NATIVE_CODEX_BRIDGE_JSON="$(mktemp)"
DEBUG_DOM_JSON="$(mktemp)"
ELECTRON_JSON="$(mktemp)"
CODEX_TXT="$(mktemp)"
MCP_JSONL="$(mktemp)"
RUN_DIR="$(mktemp -d)"
POLICY_SCREENSHOT="$RUN_DIR/policy.png"
MCP_POLICY_SCREENSHOT="$RUN_DIR/mcp-policy.png"
MCP_POLICY_SCREENSHOT_JSON="$("$PYTHON" -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$MCP_POLICY_SCREENSHOT")"
trap 'rm -f "$STATUS_JSON" "$CODEX_APPS_JSON" "$LIST_WINDOWS_JSON" "$CAPTURE_JSON" "$APP_REQUEST_JSON" "$POLICY_JSON" "$RUNTIME_JSON" "$DOM_JSON" "$ELECTRON_BRIDGE_JSON" "$NATIVE_CODEX_BRIDGE_JSON" "$DEBUG_DOM_JSON" "$ELECTRON_JSON" "$CODEX_TXT" "$MCP_JSONL"; rm -rf "$RUN_DIR"' EXIT

log "checking CLI status/capture schema"
(cd "$RUN_DIR" && "$APP_BIN" status --pretty >"$STATUS_JSON")
(cd "$RUN_DIR" && "$APP_BIN" codex-apps-status --pretty >"$CODEX_APPS_JSON")
(cd "$RUN_DIR" && "$APP_BIN" list-windows --pretty >"$LIST_WINDOWS_JSON")
(cd "$RUN_DIR" && "$APP_BIN" capture --max-depth 1 --ignore-cache --pretty >"$CAPTURE_JSON")
(cd "$RUN_DIR" && "$APP_BIN" capture --max-depth 1 --ignore-cache --request-app-capture --app-capture-timeout 0.1 --pretty >"$APP_REQUEST_JSON")
(cd "$RUN_DIR" && "$APP_BIN" capture --max-depth 1 --ignore-cache --browser-annotation-screenshots-mode always --screenshot "$POLICY_SCREENSHOT" --pretty >"$POLICY_JSON")
(cd "$RUN_DIR" && "$APP_BIN" capture --max-depth 1 --ignore-cache --browser-annotation-editor-mode design --browser-original-view-enabled --browser-design-modifier-pressed --browser-tweaks-editor-open --browser-active-design-change-json '{"id":"verifier-design","declarations":[]}' --pretty >"$RUNTIME_JSON")
(cd "$RUN_DIR" && "$APP_BIN" capture --max-depth 1 --ignore-cache --browser-dom-fixture-json '{"pageUrl":"https://example.test/page","title":"Fixture Page","viewportSize":{"width":800,"height":600},"devicePixelRatio":2,"runtimeBridge":{"installed":true,"liveEventStreamAvailable":true,"version":"0.1.14","source":"appshot-browser-runtime-bridge","extensionHelperAvailable":true,"hostOwner":"browser-extension","hostTransport":"window.postMessage+extension-runtime","eventCount":1,"events":[{"type":"browser-sidebar-runtime-open-editor","source":"appshot-browser-runtime-bridge","bridgeEvent":true,"candidate":false,"anchorState":{"anchor":{"selector":"button.cta"}}}]},"images":[{"sourceUrl":"https://example.test/hero.png","alt":"Hero","selector":"img.hero","rect":{"x":10,"y":20,"width":300,"height":200},"naturalSize":{"width":600,"height":400}}],"designTargets":[{"selector":"button.cta","role":"button","text":"Buy","rect":{"x":50,"y":80,"width":120,"height":44}}]}' --pretty >"$DOM_JSON")
(cd "$RUN_DIR" && "$APP_BIN" capture --max-depth 1 --ignore-cache --browser-dom-fixture-json '{"pageUrl":"https://example.test/electron","title":"Electron Bridge Fixture","viewportSize":{"width":800,"height":600},"runtimeBridge":{"installed":true,"liveEventStreamAvailable":true,"version":"0.1.14","source":"appshot-browser-runtime-bridge","electronHostBridgeAvailable":true,"hostOwner":"electron-preload","hostTransport":"electron-ipc","eventCount":1,"events":[{"type":"browser-sidebar-runtime-message","source":"appshot-browser-runtime-bridge","bridgeEvent":true,"candidate":false,"hostOwner":"electron-preload","hostTransport":"electron-ipc"}]},"designTargets":[{"selector":"main","role":"document","text":"Electron Bridge","rect":{"x":0,"y":0,"width":800,"height":600}}]}' --pretty >"$ELECTRON_BRIDGE_JSON")
(cd "$RUN_DIR" && "$APP_BIN" capture --max-depth 1 --ignore-cache --browser-dom-fixture-json '{"pageUrl":"https://example.test/codex-native","title":"Native Codex Host Fixture","viewportSize":{"width":800,"height":600},"runtimeBridge":{"installed":false,"nativeCodexDesktopAvailable":true,"codexHostBridgeAvailable":true,"hostOwner":"codex-electron-host","hostTransport":"codex-electron-ipc","eventCount":1,"events":[{"type":"browser-sidebar-runtime-sync","source":"codex-comment-preload","bridgeEvent":true,"candidate":false,"hostOwner":"codex-electron-host","hostTransport":"codex-electron-ipc"}]},"designTargets":[{"selector":"main","role":"document","text":"Native Codex Host","rect":{"x":0,"y":0,"width":800,"height":600}}]}' --pretty >"$NATIVE_CODEX_BRIDGE_JSON")
(cd "$RUN_DIR" && "$APP_BIN" capture --max-depth 1 --ignore-cache --browser-dom-fixture-json '{"pageUrl":"http://127.0.0.1:9222/json","title":"Inspectable WebContents","viewportSize":{"width":900,"height":700},"designTargets":[{"selector":"body","role":"document","text":"Inspectable WebContents","rect":{"x":0,"y":0,"width":900,"height":700}}]}' --pretty >"$DEBUG_DOM_JSON")
(cd "$RUN_DIR" && "$APP_BIN" capture --max-depth 1 --ignore-cache --include-electron-debugging --electron-debugging-timeout 0.5 --pretty >"$ELECTRON_JSON")
(cd "$RUN_DIR" && "$APP_BIN" capture --max-depth 1 --ignore-cache --format codex >"$CODEX_TXT")

"$PYTHON" - "$STATUS_JSON" "$CODEX_APPS_JSON" "$LIST_WINDOWS_JSON" "$CAPTURE_JSON" "$APP_REQUEST_JSON" "$POLICY_JSON" "$RUNTIME_JSON" "$DOM_JSON" "$DEBUG_DOM_JSON" "$ELECTRON_JSON" "$CODEX_TXT" "$ELECTRON_BRIDGE_JSON" "$NATIVE_CODEX_BRIDGE_JSON" <<'PY'
import json
import sys

status = json.load(open(sys.argv[1]))
codex_apps = json.load(open(sys.argv[2]))
list_windows = json.load(open(sys.argv[3]))
capture = json.load(open(sys.argv[4]))
app_request = json.load(open(sys.argv[5]))
policy = json.load(open(sys.argv[6]))
runtime = json.load(open(sys.argv[7]))
dom = json.load(open(sys.argv[8]))
debug_dom = json.load(open(sys.argv[9]))
electron = json.load(open(sys.argv[10]))
codex_text = open(sys.argv[11]).read()
electron_bridge = json.load(open(sys.argv[12]))
native_codex_bridge = json.load(open(sys.argv[13]))

def require_keys(name, payload, keys):
    missing = [key for key in keys if key not in payload]
    if missing:
        raise SystemExit(f"{name} missing keys: {', '.join(missing)}")

def check_codex_host_integration(name, payload):
    require_keys(name, payload, ["format", "hostBridge"])
    if payload.get("format") != "codex-computer-use-status":
        raise SystemExit(f"{name} returned unexpected format")
    host_bridge = payload.get("hostBridge", {})
    require_keys(
        f"{name} hostBridge",
        host_bridge,
        ["requiresCodexHostBridge", "nativePipeEnvironment", "requiredSignals", "codexHostIntegration"],
    )
    integration = host_bridge.get("codexHostIntegration", {})
    require_keys(
        f"{name} codexHostIntegration",
        integration,
        [
            "format",
            "source",
            "requiredCodexSideIntegration",
            "privateCodexWebviewHostAttached",
            "codexAppBundle",
            "integrationArtifacts",
            "hostAPI",
            "hostChannel",
            "expectedHostOwners",
            "expectedHostTransports",
            "verifiedBy",
            "nonClaim",
            "nextAction",
        ],
    )
    if integration.get("format") != "codex-electron-host-integration-status":
        raise SystemExit(f"{name} codexHostIntegration format drifted")
    if integration.get("requiredCodexSideIntegration") is not True:
        raise SystemExit(f"{name} codexHostIntegration lost requiredCodexSideIntegration")
    if integration.get("privateCodexWebviewHostAttached") is not False:
        raise SystemExit(f"{name} must not claim Codex private host attachment from standalone CLI/MCP")
    if integration.get("hostChannel") != "codex_desktop:browser-sidebar-runtime-message":
        raise SystemExit(f"{name} codexHostIntegration hostChannel drifted")
    if sorted(integration.get("hostAPI", [])) != ["sendMessageToHost", "subscribeToHostMessages"]:
        raise SystemExit(f"{name} codexHostIntegration host API drifted")
    if "codex-electron-host" not in integration.get("expectedHostOwners", []):
        raise SystemExit(f"{name} codexHostIntegration missing Codex host owner")
    if "codex-electron-ipc+appshot-electron-ipc" not in integration.get("expectedHostTransports", []):
        raise SystemExit(f"{name} codexHostIntegration missing Codex host transport")
    artifacts = integration.get("integrationArtifacts", {})
    require_keys(
        f"{name} codexHostIntegration.integrationArtifacts",
        artifacts,
        ["codexHostAdapter", "electronPreloadHelper", "browserExtensionHelper"],
    )
    for artifact_name, artifact in artifacts.items():
        require_keys(
            f"{name} codexHostIntegration.integrationArtifacts.{artifact_name}",
            artifact,
            ["path", "available", "allRequiredFilesAvailable", "requiredFiles"],
        )
        if not isinstance(artifact.get("requiredFiles"), list):
            raise SystemExit(f"{name} {artifact_name} requiredFiles was not a list")

require_keys(
    "status",
    status,
    ["schemaVersion", "permissions", "codexAppsStatus", "codexComputerUseStatus", "captureCache", "frontmostApplication", "currentApplication", "primaryWindow", "frontmostWindow", "currentWindow"],
)
require_keys(
    "capture",
    capture,
    ["schemaVersion", "permissions", "codexAppsStatus", "codexComputerUseStatus", "frontmostApplication", "currentApplication", "targetApplication", "windows", "accessibility", "codex", "codexBrowserSettings", "codexBrowserPayload", "codexBrowserRuntimeState", "codexBrowserRuntimeProtocol"],
)

check_codex_host_integration("status codexComputerUseStatus", status.get("codexComputerUseStatus", {}))
check_codex_host_integration("capture codexComputerUseStatus", capture.get("codexComputerUseStatus", {}))
check_codex_host_integration("codex-apps-status codexComputerUseStatus", codex_apps.get("codexComputerUseStatus", {}))
require_keys(
    "app capture request",
    app_request,
    ["schemaVersion", "appCaptureRequest", "captureCache", "accessibility", "codex"],
)
require_keys(
    "app capture request diagnostics",
    app_request.get("appCaptureRequest", {}),
    ["requested", "available", "source", "requestID", "trigger", "timeoutSeconds", "reason"],
)
if app_request["appCaptureRequest"].get("requested") is not True:
    raise SystemExit("appCaptureRequest did not record a requested GUI capture")

require_keys(
    "CLI codex apps status",
    codex_apps,
    ["format", "source", "codexAppsReady", "forceRefetchSupported", "retryWhenNotReady", "connectors", "connectorCount", "accessibleConnectors", "accessibleConnectorCount", "tools", "toolCount", "blockers", "codexComputerUseStatus", "evidence"],
)
if codex_apps.get("format") != "codex-accessible-connectors-status":
    raise SystemExit("codex-apps-status returned unexpected format")
for required_tool in ["appshot_capture", "appshot_permissions", "appshot_status", "appshot_list_windows", "appshot_codex_apps_status", "appshot_codex_computer_use_status", "list_apps", "get_app_state"]:
    if required_tool not in codex_apps.get("tools", []):
        raise SystemExit(f"codex-apps-status missing tool: {required_tool}")
if codex_apps.get("connectorCount") != 1:
    raise SystemExit("codex-apps-status should report one AppShot connector")
if codex_apps.get("toolCount") != 8:
    raise SystemExit("codex-apps-status should report eight AppShot MCP tools")
if codex_apps.get("forceRefetchSupported") is not True or codex_apps.get("retryWhenNotReady") is not True:
    raise SystemExit("codex-apps-status lost Codex force-refetch readiness semantics")
if codex_apps.get("codexAppsReady") != (len(codex_apps.get("blockers", [])) == 0):
    raise SystemExit("codex-apps-status readiness does not match blockers")
if codex_apps.get("accessibleConnectorCount") != len(codex_apps.get("accessibleConnectors", [])):
    raise SystemExit("codex-apps-status accessibleConnectorCount does not match accessibleConnectors")
if codex_apps.get("evidence", {}).get("anchors") != ["AccessibleConnectorsStatus", "codex_apps_ready", "force_refetch", "ConnectorsSnapshot"]:
    raise SystemExit("codex-apps-status evidence anchors drifted")

require_keys("list-windows", list_windows, ["schemaVersion", "capturedAt", "applications"])
if not isinstance(list_windows.get("applications"), list):
    raise SystemExit("list-windows applications was not a list")
for app in list_windows.get("applications", []):
    require_keys("list-windows app", app, ["windows", "accessibilityWindows", "windowDiscovery", "captureParameters"])
    if not isinstance(app.get("accessibilityWindows"), list):
        raise SystemExit("list-windows accessibilityWindows was not a list")
    discovery = app.get("windowDiscovery", {})
    require_keys(
        "list-windows windowDiscovery",
        discovery,
        ["source", "cgWindowCount", "accessibilityWindowCount", "hasAccessibilityOnlyWindows", "preferredAccessibilityWindow"],
    )
    if not isinstance(discovery.get("hasAccessibilityOnlyWindows"), bool):
        raise SystemExit("list-windows hasAccessibilityOnlyWindows was not a boolean")
for name, payload in [("status", status.get("codexAppsStatus", {})), ("capture", capture.get("codexAppsStatus", {}))]:
    require_keys(f"{name} codexAppsStatus", payload, ["format", "codexAppsReady", "forceRefetchSupported", "retryWhenNotReady", "tools", "blockers", "codexComputerUseStatus"])
    if payload.get("format") != "codex-accessible-connectors-status":
        raise SystemExit(f"{name} codexAppsStatus format drifted")
    if "appshot_codex_apps_status" not in payload.get("tools", []):
        raise SystemExit(f"{name} codexAppsStatus missing MCP readiness tool")
    if payload.get("codexAppsReady") != (len(payload.get("blockers", [])) == 0):
        raise SystemExit(f"{name} codexAppsStatus readiness does not match blockers")

if isinstance(capture.get("primaryWindow"), dict):
    require_keys("capture primaryWindow", capture["primaryWindow"], ["ownerPID", "bounds", "isOnScreen"])
    if capture["primaryWindow"].get("source") == "accessibilityWindow":
        require_keys("capture AX primaryWindow", capture["primaryWindow"], ["source", "title", "captureParameters"])
    else:
        require_keys("capture CG primaryWindow", capture["primaryWindow"], ["windowID", "windowNumber"])
    require_keys("capture", capture, ["frontmostWindow", "currentWindow", "targetActivation"])
    target_activation = capture.get("targetActivation", {})
    require_keys("capture targetActivation", target_activation, ["requested"])
    if target_activation.get("requested") is True:
        require_keys("capture targetActivation", target_activation, ["appActivateResult", "frontmostBefore", "frontmostAfter", "frontmostMatchedTarget"])

accessibility = capture.get("accessibility", {})
require_keys("capture accessibility", accessibility, ["trusted", "rootSource", "root", "text", "textLineCount", "visibleText", "visibleTextLineCount", "electronAccessibility"])
if accessibility.get("rootSource") not in {"targetWindow", "focusedWindow", "application", "targetWindowUnmatchedFocusedWindow", "targetWindowUnmatchedApplication"}:
    raise SystemExit(f"unexpected accessibility.rootSource: {accessibility.get('rootSource')!r}")
if "targetWindow" in accessibility:
    target_window_match = accessibility.get("targetWindowMatch", {})
    require_keys("capture targetWindowMatch", target_window_match, ["matched", "candidateCount", "axWindowExposure", "bestScore", "bestCandidateIsAXWindow", "topCandidates", "focusedWindowResult", "mainWindowResult", "recoverySteps"])
    if not isinstance(target_window_match.get("matched"), bool):
        raise SystemExit("targetWindowMatch matched was not a boolean")
    if not isinstance(target_window_match.get("candidateCount"), int):
        raise SystemExit("targetWindowMatch candidateCount was not an integer")
    if not isinstance(target_window_match.get("topCandidates"), list):
        raise SystemExit("targetWindowMatch topCandidates was not a list")
    if target_window_match.get("matched") and target_window_match.get("bestCandidateIsAXWindow") is not True:
        raise SystemExit("targetWindowMatch matched without an AXWindow best candidate")
    ax_window_exposure = target_window_match.get("axWindowExposure", {})
    require_keys("capture axWindowExposure", ax_window_exposure, ["hasAXWindowRoles", "roleCounts", "suspectedSelfReferentialAXWindows"])
    if not isinstance(ax_window_exposure.get("hasAXWindowRoles"), bool):
        raise SystemExit("axWindowExposure hasAXWindowRoles was not a boolean")
    if not isinstance(ax_window_exposure.get("roleCounts"), dict):
        raise SystemExit("axWindowExposure roleCounts was not an object")
if (
    accessibility.get("trusted")
    and accessibility.get("rootSource") in {"targetWindow", "focusedWindow"}
    and accessibility.get("visibleTextLineCount", 0) <= 0
):
    raise SystemExit("trusted window accessibility capture has no visibleText lines")
electron_accessibility = accessibility.get("electronAccessibility", {})
require_keys("capture electronAccessibility", electron_accessibility, ["requested", "enabled", "attempts", "enhancedUserInterface"])
attempts = electron_accessibility.get("attempts", [])
if not isinstance(attempts, list) or len(attempts) < 2:
    raise SystemExit("electronAccessibility did not record both AX unlock attempts")
attempt_attributes = {attempt.get("attribute") for attempt in attempts if isinstance(attempt, dict)}
if {"AXManualAccessibility", "AXEnhancedUserInterface"} - attempt_attributes:
    raise SystemExit("electronAccessibility missing manual/enhanced AX attempts")
for attempt in attempts:
    if not isinstance(attempt, dict):
        raise SystemExit("electronAccessibility attempt was not an object")
    require_keys("electronAccessibility attempt", attempt, ["attribute", "requested", "result", "enabled"])

codex = capture.get("codex", {})
require_keys("capture codex", codex, ["format", "text", "treeLineCount", "selectedLineCount", "hasFocusedElement", "hasBrowserPayload", "browserPayloadFormat"])
if codex.get("format") != "codex-appshot-text":
    raise SystemExit(f"unexpected codex format: {codex.get('format')!r}")
if codex.get("hasBrowserPayload") is not True:
    raise SystemExit("capture codex summary does not report hasBrowserPayload")
if codex.get("browserPayloadFormat") != "codex-browser-comment-payload-adapter":
    raise SystemExit(f"unexpected browser payload format: {codex.get('browserPayloadFormat')!r}")
if codex.get("hasBrowserRuntimeState") is not True:
    raise SystemExit("capture codex summary does not report hasBrowserRuntimeState")
if codex.get("browserRuntimeStateFormat") != "codex-browser-runtime-state-adapter":
    raise SystemExit(f"unexpected browser runtime state format: {codex.get('browserRuntimeStateFormat')!r}")
if not codex.get("text", "").startswith("<appshot "):
    raise SystemExit("capture codex text does not start with <appshot")
if "Window:" not in codex.get("text", ""):
    raise SystemExit("capture codex text missing Window header")
if not codex_text.startswith("<appshot ") or "Window:" not in codex_text or "</appshot>" not in codex_text:
    raise SystemExit("CLI --format codex output is not a complete appshot block")

browser_payload = capture.get("codexBrowserPayload", {})
require_keys(
    "capture codexBrowserPayload",
    browser_payload,
    ["format", "source", "type", "content", "position", "localBrowserContext", "localBrowserCommentMetadata", "localBrowserAttachedImages", "localBrowserDesignChange", "localBrowserRuntimeProtocol", "localBrowserScreenshot"],
)
if browser_payload.get("format") != "codex-browser-comment-payload-adapter":
    raise SystemExit(f"unexpected codexBrowserPayload format: {browser_payload.get('format')!r}")
context = browser_payload.get("localBrowserContext", {})
require_keys("capture localBrowserContext", context, ["pageUrl", "framePath", "frameUrl", "targetDescription", "targetRole", "targetName", "targetSelector", "targetPath", "nearbyText"])
metadata = browser_payload.get("localBrowserCommentMetadata", {})
require_keys("capture localBrowserCommentMetadata", metadata, ["kind", "annotationScreenshotsMode", "applicationName", "windowTitle"])
if metadata.get("kind") != "appshot-native":
    raise SystemExit(f"unexpected browser metadata kind: {metadata.get('kind')!r}")

runtime_state = capture.get("codexBrowserRuntimeState", {})
require_keys(
    "capture codexBrowserRuntimeState",
    runtime_state,
    ["format", "source", "type", "interactionMode", "annotationEditorMode", "isAgentControllingBrowser", "canUseTweaks", "isDesignModifierPressed", "isOriginalViewEnabled", "isTweaksEditorOpen", "comments", "activeDesignChange", "viewportScale", "zoomPercent"],
)
if runtime_state.get("format") != "codex-browser-runtime-state-adapter":
    raise SystemExit(f"unexpected runtime state format: {runtime_state.get('format')!r}")
if runtime_state.get("type") != "browser-sidebar-runtime-sync":
    raise SystemExit(f"unexpected runtime state type: {runtime_state.get('type')!r}")
if runtime_state.get("interactionMode") != "comment" or runtime_state.get("annotationEditorMode") != "comment":
    raise SystemExit("default runtime state did not preserve Codex comment mode defaults")
if runtime_state.get("canUseTweaks") is not True:
    raise SystemExit("default runtime state should allow tweaks")
if runtime_state.get("isDesignModifierPressed") or runtime_state.get("isOriginalViewEnabled") or runtime_state.get("isTweaksEditorOpen"):
    raise SystemExit("default runtime state should keep design/original/tweaks flags off")

runtime_protocol = capture.get("codexBrowserRuntimeProtocol", {})
require_keys(
    "capture codexBrowserRuntimeProtocol",
    runtime_protocol,
    ["format", "source", "channel", "hostMessageAPI", "syncEventType", "eventTypes", "eventTypeCount", "payloadKeys", "runtimeState", "liveEventStreamAvailable"],
)
if runtime_protocol.get("format") != "codex-browser-runtime-protocol-adapter":
    raise SystemExit(f"unexpected runtime protocol format: {runtime_protocol.get('format')!r}")
expected_runtime_events = [
    "browser-sidebar-runtime-clear-comment-screenshot",
    "browser-sidebar-runtime-close-comment-preview",
    "browser-sidebar-runtime-close-editor",
    "browser-sidebar-runtime-comment-screenshot-ready",
    "browser-sidebar-runtime-create-comment-at-point",
    "browser-sidebar-runtime-design-modifier-state",
    "browser-sidebar-runtime-design-scrub-changed",
    "browser-sidebar-runtime-exit-comment-mode",
    "browser-sidebar-runtime-focus-editor",
    "browser-sidebar-runtime-image-drag-ended",
    "browser-sidebar-runtime-image-drag-started",
    "browser-sidebar-runtime-message",
    "browser-sidebar-runtime-mouse-navigation",
    "browser-sidebar-runtime-open-comment-preview",
    "browser-sidebar-runtime-open-design-editor",
    "browser-sidebar-runtime-open-design-editor-at-point",
    "browser-sidebar-runtime-open-editor",
    "browser-sidebar-runtime-prepare-comment-screenshot",
    "browser-sidebar-runtime-restore-editor",
    "browser-sidebar-runtime-select-comment",
    "browser-sidebar-runtime-sync",
    "browser-sidebar-runtime-update-anchor",
]
if runtime_protocol.get("eventTypes") != expected_runtime_events:
    raise SystemExit("runtime protocol eventTypes do not match Codex 522 evidence")
if runtime_protocol.get("eventTypeCount") != len(expected_runtime_events):
    raise SystemExit("runtime protocol eventTypeCount is wrong")
if runtime_protocol.get("liveEventStreamAvailable") is not False:
    raise SystemExit("runtime protocol should not claim a live preload stream")
if browser_payload.get("localBrowserRuntimeProtocol", {}).get("eventTypeCount") != len(expected_runtime_events):
    raise SystemExit("browser payload did not mirror runtime protocol")

settings = capture.get("codexBrowserSettings", {})
require_keys("capture codexBrowserSettings", settings, ["browser-annotation-screenshots-mode", "annotationScreenshotsMode", "description", "schema"])
if settings.get("browser-annotation-screenshots-mode") != "necessary":
    raise SystemExit(f"unexpected default browser annotation screenshots mode: {settings.get('browser-annotation-screenshots-mode')!r}")

policy_settings = policy.get("codexBrowserSettings", {})
policy_browser_payload = policy.get("codexBrowserPayload", {})
policy_metadata = policy_browser_payload.get("localBrowserCommentMetadata", {})
require_keys("policy codexBrowserSettings", policy_settings, ["browser-annotation-screenshots-mode", "schema"])
require_keys("policy codexBrowserPayload", policy_browser_payload, ["localBrowserScreenshot", "localBrowserCommentMetadata"])
if policy_settings.get("browser-annotation-screenshots-mode") != "always":
    raise SystemExit(f"policy capture did not preserve always mode: {policy_settings.get('browser-annotation-screenshots-mode')!r}")
if policy_metadata.get("annotationScreenshotsMode") != "always":
    raise SystemExit(f"policy metadata did not preserve always mode: {policy_metadata.get('annotationScreenshotsMode')!r}")
if "screenshot" not in policy:
    raise SystemExit("policy capture did not attempt a screenshot for always mode")
require_keys("policy screenshot", policy.get("screenshot", {}), ["path", "captureMode", "captured"])
if policy["screenshot"].get("captureMode") not in {"windowID", "bounds", "screen"}:
    raise SystemExit("policy screenshot captureMode drifted")

runtime_state = runtime.get("codexBrowserRuntimeState", {})
runtime_payload = runtime.get("codexBrowserPayload", {})
runtime_metadata = runtime_payload.get("localBrowserCommentMetadata", {})
require_keys("runtime codexBrowserRuntimeState", runtime_state, ["annotationEditorMode", "isDesignModifierPressed", "isOriginalViewEnabled", "isTweaksEditorOpen", "activeDesignChange"])
if runtime_state.get("annotationEditorMode") != "design":
    raise SystemExit("runtime capture did not preserve design annotation editor mode")
if runtime_state.get("isDesignModifierPressed") is not True:
    raise SystemExit("runtime capture did not preserve design modifier")
if runtime_state.get("isOriginalViewEnabled") is not True:
    raise SystemExit("runtime capture did not preserve original view")
if runtime_state.get("isTweaksEditorOpen") is not True:
    raise SystemExit("runtime capture did not preserve tweaks editor")
if runtime_state.get("activeDesignChange", {}).get("id") != "verifier-design":
    raise SystemExit("runtime capture did not preserve activeDesignChange")
if runtime_payload.get("localBrowserDesignChange", {}).get("group", {}).get("id") != "verifier-design":
    raise SystemExit("runtime browser payload did not mirror activeDesignChange as a Codex design group")
if runtime_metadata.get("runtimeState", {}).get("isOriginalViewEnabled") is not True:
    raise SystemExit("runtime browser metadata did not embed runtimeState")

dom_integration = dom.get("codexBrowserDOMIntegration", {})
dom_browser_payload = dom.get("codexBrowserPayload", {})
require_keys("dom codexBrowserDOMIntegration", dom_integration, ["format", "source", "available", "images", "designTargets", "browserRuntimeBridge", "browserRuntimeBridgeEvents", "browserRuntimeBridgeEventCount", "browserRuntimeCandidateEvents", "browserRuntimeCandidateEventCount", "browserRuntimeEvents", "browserRuntimeEventTypes", "browserRuntimeProtocol", "liveEventStreamAvailable", "localBrowserAttachedImages"])
if dom_integration.get("format") != "codex-browser-dom-integration":
    raise SystemExit(f"unexpected browser DOM integration format: {dom_integration.get('format')!r}")
if dom_integration.get("available") is not True:
    raise SystemExit("browser DOM fixture integration should be available")
bridge = dom_integration.get("browserRuntimeBridge", {})
if bridge.get("source") != "appshot-browser-runtime-bridge":
    raise SystemExit("browser DOM bridge fixture did not preserve bridge source")
if bridge.get("codexDesktopShimAvailable") is not True:
    raise SystemExit("browser DOM bridge fixture did not expose Codex desktop shim availability")
if bridge.get("hostChannel") != "codex_desktop:browser-sidebar-runtime-message":
    raise SystemExit("browser DOM bridge fixture did not preserve Codex host channel")
if sorted(bridge.get("hostAPI", [])) != ["sendMessageToHost", "subscribeToHostMessages"]:
    raise SystemExit("browser DOM bridge fixture did not expose Codex host API names")
if bridge.get("extensionHelperAvailable") is not True:
    raise SystemExit("browser DOM bridge fixture did not preserve extension helper availability")
if bridge.get("hostOwner") != "browser-extension":
    raise SystemExit("browser DOM bridge fixture did not preserve extension host owner")
if bridge.get("hostTransport") != "window.postMessage+extension-runtime":
    raise SystemExit("browser DOM bridge fixture did not preserve extension host transport")
if dom_integration.get("liveEventStreamAvailable") is not True:
    raise SystemExit("browser DOM bridge fixture should report liveEventStreamAvailable")
if dom_integration.get("browserRuntimeBridgeEventCount") != 1:
    raise SystemExit("browser DOM bridge fixture should expose one bridge event")
if dom_integration.get("browserRuntimeCandidateEventCount") != len(expected_runtime_events):
    raise SystemExit("browser DOM fixture candidate event count is wrong")
if dom_integration.get("browserRuntimeEventCount") != len(expected_runtime_events) + 1:
    raise SystemExit("browser DOM combined runtime event count should include bridge plus candidates")
bridge_event = dom_integration.get("browserRuntimeBridgeEvents", [{}])[0]
if bridge_event.get("bridgeEvent") is not True or bridge_event.get("candidate") is not False:
    raise SystemExit("browser DOM bridge event flags were not preserved")
if bridge_event.get("anchorState", {}).get("anchor", {}).get("selector") != "button.cta":
    raise SystemExit("browser DOM bridge event did not preserve selector anchor")
event_types = [event.get("type") for event in dom_integration.get("browserRuntimeEvents", [])]
for expected_event in expected_runtime_events:
    if expected_event not in event_types:
        raise SystemExit(f"browser DOM integration missing event: {expected_event}")
if sorted(dom_integration.get("browserRuntimeEventTypes", [])) != sorted(set(event_types)):
    raise SystemExit("browser DOM integration event type summary does not match runtime events")
started = next(event for event in dom_integration["browserRuntimeEvents"] if event.get("type") == "browser-sidebar-runtime-image-drag-started")
if started.get("sourceUrl") != "https://example.test/hero.png":
    raise SystemExit("browser DOM image drag event did not preserve sourceUrl")
design_event = next(event for event in dom_integration["browserRuntimeEvents"] if event.get("type") == "browser-sidebar-runtime-open-design-editor")
require_keys("dom design event", design_event, ["anchorState", "designEditorState"])
if design_event["anchorState"].get("anchor", {}).get("selector") != "button.cta":
    raise SystemExit("browser DOM design event did not preserve selector anchor")
if len(dom_browser_payload.get("localBrowserAttachedImages", [])) != 1:
    raise SystemExit("browser DOM attached images were not mirrored into codexBrowserPayload")
if len(dom_browser_payload.get("localBrowserRuntimeEvents", [])) != len(expected_runtime_events) + 1:
    raise SystemExit("browser DOM runtime events were not mirrored into codexBrowserPayload")
if dom_browser_payload.get("localBrowserRuntimeEvents", [{}])[0].get("bridgeEvent") is not True:
    raise SystemExit("browser DOM bridge event was not first in codexBrowserPayload runtime events")
dom_metadata_bridge = dom_browser_payload.get("localBrowserCommentMetadata", {}).get("browserDOMIntegration", {})
if dom_metadata_bridge.get("codexDesktopShimAvailable") is not True:
    raise SystemExit("browser DOM payload metadata did not summarize Codex desktop shim availability")
if sorted(dom_metadata_bridge.get("hostAPI", [])) != ["sendMessageToHost", "subscribeToHostMessages"]:
    raise SystemExit("browser DOM payload metadata did not summarize Codex host API names")
if dom_metadata_bridge.get("extensionHelperAvailable") is not True:
    raise SystemExit("browser DOM payload metadata did not summarize extension helper availability")
if dom_metadata_bridge.get("hostOwner") != "browser-extension":
    raise SystemExit("browser DOM payload metadata did not summarize extension host owner")
if dom_metadata_bridge.get("hostTransport") != "window.postMessage+extension-runtime":
    raise SystemExit("browser DOM payload metadata did not summarize extension host transport")
if dom_browser_payload.get("localBrowserRuntimeProtocol", {}).get("liveEventStreamAvailable") is not True:
    raise SystemExit("browser DOM bridge availability was not mirrored into codexBrowserPayload runtime protocol")
dom_context = dom_browser_payload.get("localBrowserContext", {})
dom_metadata = dom_browser_payload.get("localBrowserCommentMetadata", {})
if dom_context.get("pageUrl") != "https://example.test/page":
    raise SystemExit("browser DOM payload did not preserve real pageUrl")
if dom_context.get("frameUrl") != "https://example.test/page":
    raise SystemExit("browser DOM payload did not preserve real frameUrl")
if dom_context.get("targetSelector") != "button.cta":
    raise SystemExit("browser DOM payload did not preserve target selector")
if dom_context.get("targetImmediateText") != "Buy":
    raise SystemExit("browser DOM payload did not preserve target immediate text")
if dom_metadata.get("kind") != "browser":
    raise SystemExit("browser DOM payload did not switch metadata kind to browser")
if dom_metadata.get("markerViewportPoint", {}).get("x") is None:
    raise SystemExit("browser DOM payload did not expose markerViewportPoint")
if dom_metadata.get("browserDOMIntegration", {}).get("liveEventStreamAvailable") is not True:
    raise SystemExit("browser DOM metadata did not mirror liveEventStreamAvailable")

electron_bridge_integration = electron_bridge.get("codexBrowserDOMIntegration", {})
electron_bridge_payload = electron_bridge.get("codexBrowserPayload", {})
electron_bridge_runtime = electron_bridge_integration.get("browserRuntimeBridge", {})
if electron_bridge_runtime.get("electronHostBridgeAvailable") is not True:
    raise SystemExit("Electron bridge fixture did not expose electronHostBridgeAvailable")
if electron_bridge_runtime.get("hostOwner") != "electron-preload":
    raise SystemExit("Electron bridge fixture did not preserve electron host owner")
if electron_bridge_runtime.get("hostTransport") != "electron-ipc":
    raise SystemExit("Electron bridge fixture did not preserve electron host transport")
if electron_bridge_runtime.get("hostChannel") != "codex_desktop:browser-sidebar-runtime-message":
    raise SystemExit("Electron bridge fixture did not preserve Codex host channel")
electron_bridge_metadata = electron_bridge_payload.get("localBrowserCommentMetadata", {}).get("browserDOMIntegration", {})
if electron_bridge_metadata.get("electronHostBridgeAvailable") is not True:
    raise SystemExit("Electron bridge payload metadata did not summarize electron host bridge availability")
if electron_bridge_metadata.get("hostOwner") != "electron-preload":
    raise SystemExit("Electron bridge payload metadata did not summarize electron host owner")
if electron_bridge_metadata.get("hostTransport") != "electron-ipc":
    raise SystemExit("Electron bridge payload metadata did not summarize electron host transport")

native_codex_integration = native_codex_bridge.get("codexBrowserDOMIntegration", {})
native_codex_payload = native_codex_bridge.get("codexBrowserPayload", {})
native_codex_runtime = native_codex_integration.get("browserRuntimeBridge", {})
if native_codex_runtime.get("nativeCodexDesktopAvailable") is not True:
    raise SystemExit("native Codex fixture did not expose nativeCodexDesktopAvailable")
if native_codex_runtime.get("codexHostBridgeAvailable") is not True:
    raise SystemExit("native Codex fixture did not expose codexHostBridgeAvailable")
if native_codex_runtime.get("codexDesktopShimAvailable") is not False:
    raise SystemExit("native Codex fixture must not be labeled as an AppShot Codex desktop shim")
if native_codex_runtime.get("hostOwner") != "codex-electron-host":
    raise SystemExit("native Codex fixture did not preserve Codex host owner")
if native_codex_runtime.get("hostTransport") != "codex-electron-ipc":
    raise SystemExit("native Codex fixture did not preserve native Codex host transport")
if native_codex_integration.get("liveEventStreamAvailable") is not True:
    raise SystemExit("native Codex fixture did not mark the subscribable Codex host stream as live")
native_codex_event = native_codex_integration.get("browserRuntimeBridgeEvents", [{}])[0]
if native_codex_event.get("type") != "browser-sidebar-runtime-sync":
    raise SystemExit("native Codex fixture did not preserve the Codex runtime sync event")
native_codex_metadata = native_codex_payload.get("localBrowserCommentMetadata", {}).get("browserDOMIntegration", {})
if native_codex_metadata.get("nativeCodexDesktopAvailable") is not True:
    raise SystemExit("native Codex payload metadata did not summarize native Codex desktop availability")
if native_codex_metadata.get("codexHostBridgeAvailable") is not True:
    raise SystemExit("native Codex payload metadata did not summarize Codex host bridge availability")
if native_codex_metadata.get("codexDesktopShimAvailable") is not False:
    raise SystemExit("native Codex payload metadata must not summarize an AppShot shim")
if native_codex_metadata.get("hostOwner") != "codex-electron-host":
    raise SystemExit("native Codex payload metadata did not summarize Codex host owner")
if native_codex_metadata.get("hostTransport") != "codex-electron-ipc":
    raise SystemExit("native Codex payload metadata did not summarize native Codex host transport")
if native_codex_payload.get("localBrowserRuntimeProtocol", {}).get("liveEventStreamAvailable") is not True:
    raise SystemExit("native Codex fixture did not mirror live stream availability into payload protocol")

debug_dom_integration = debug_dom.get("codexBrowserDOMIntegration", {})
debug_dom_payload = debug_dom.get("codexBrowserPayload", {})
debug_remote = debug_dom_integration.get("remoteDebuggingTarget", {})
if debug_remote.get("isRemoteDebuggingTarget") is not True:
    raise SystemExit("browser DOM fixture did not detect Codex remote debugging target")
if debug_remote.get("titleMatched") is not True:
    raise SystemExit("browser DOM fixture did not detect inspectable WebContents title")
if debug_remote.get("localDebugPortMatched") is not True:
    raise SystemExit("browser DOM fixture did not detect localhost debug port")
if debug_remote.get("port") != 9222:
    raise SystemExit("browser DOM fixture did not preserve debug port 9222")
debug_remote_metadata = debug_dom_payload.get("localBrowserCommentMetadata", {}).get("browserDOMIntegration", {}).get("remoteDebuggingTarget", {})
if debug_remote_metadata.get("isRemoteDebuggingTarget") is not True:
    raise SystemExit("browser payload metadata did not mirror remote debugging target")

electron_debugging = electron.get("codexElectronRemoteDebugging", {})
require_keys(
    "electron codexElectronRemoteDebugging",
    electron_debugging,
    ["format", "source", "requested", "available", "supported", "processIdentifier", "processIDs", "knownPorts", "scannedPorts", "httpProbeCount", "httpProbes", "targetCount", "targets", "selectedTarget", "cdpSnapshot", "liveEventStreamAvailable", "reason", "evidence"],
)
if electron_debugging.get("format") != "codex-electron-remote-debugging":
    raise SystemExit("electron debugging capture returned unexpected format")
if electron_debugging.get("source") != "electron-cdp-probe":
    raise SystemExit("electron debugging capture returned unexpected source")
if electron_debugging.get("requested") is not True:
    raise SystemExit("electron debugging capture did not report requested=true")
if 9222 not in electron_debugging.get("knownPorts", []) or 9229 not in electron_debugging.get("knownPorts", []):
    raise SystemExit("electron debugging capture lost Codex known debug ports")
if not isinstance(electron_debugging.get("scannedPorts"), list):
    raise SystemExit("electron debugging scannedPorts was not a list")
if not isinstance(electron_debugging.get("httpProbes"), list):
    raise SystemExit("electron debugging httpProbes was not a list")
if not isinstance(electron_debugging.get("targets"), list):
    raise SystemExit("electron debugging targets was not a list")
if not isinstance(electron_debugging.get("cdpSnapshot"), dict):
    raise SystemExit("electron debugging cdpSnapshot was not an object")
electron_metadata = electron.get("codexBrowserPayload", {}).get("localBrowserCommentMetadata", {}).get("electronRemoteDebugging", {})
if electron_metadata.get("format") != "codex-electron-remote-debugging":
    raise SystemExit("electron debugging summary was not mirrored into browser metadata")
if electron_metadata.get("targetCount") != electron_debugging.get("targetCount"):
    raise SystemExit("electron debugging metadata targetCount did not mirror top-level targetCount")

for name, payload in [("status", status), ("capture", capture)]:
    permissions = payload.get("permissions", {})
    require_keys(f"{name} permissions", permissions, ["accessibility", "screenRecording", "identity", "stability"])
    require_keys(f"{name} permissions.identity", permissions["identity"], ["processIdentifier", "bundleIdentifier", "bundlePath", "executablePath", "isBundledApp", "recommendedAppPath", "recommendedBundleIdentifier"])
    require_keys(f"{name} permissions.stability", permissions["stability"], ["mode", "isStableGrantTarget", "recommendedGrantTarget", "recoverySteps", "currentExecutablePath"])
    if permissions["stability"].get("mode") not in {"stableInstalledApp", "commandLineTool", "alternateAppBundle"}:
        raise SystemExit(f"{name} unexpected permission stability mode: {permissions['stability'].get('mode')!r}")
PY

log "checking MCP tool surface"
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"appshot_status","arguments":{}}}' \
  '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"appshot_capture","arguments":{"format":"codex","maxDepth":1,"useRecentCache":false}}}' \
  '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"appshot_capture","arguments":{"format":"json","maxDepth":1,"useRecentCache":false,"browserAnnotationScreenshotsMode":"always","screenshotPath":'"$MCP_POLICY_SCREENSHOT_JSON"',"browserAnnotationEditorMode":"design","browserOriginalViewEnabled":true,"browserDesignModifierPressed":true,"browserTweaksEditorOpen":true,"browserActiveDesignChange":{"id":"mcp-design","declarations":[]}}}}' \
  '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"appshot_capture","arguments":{"format":"json","maxDepth":1,"useRecentCache":false,"browserDOMFixture":{"pageUrl":"https://example.test/mcp","title":"MCP Fixture","viewportSize":{"width":1024,"height":768},"runtimeBridge":{"installed":true,"liveEventStreamAvailable":true,"version":"0.1.14","source":"appshot-browser-runtime-bridge","extensionHelperAvailable":true,"hostOwner":"browser-extension","hostTransport":"window.postMessage+extension-runtime","eventCount":1,"events":[{"type":"browser-sidebar-runtime-open-editor","source":"appshot-browser-runtime-bridge","bridgeEvent":true,"candidate":false,"anchorState":{"anchor":{"selector":"a.primary"}}}]},"images":[{"sourceUrl":"https://example.test/mcp.png","selector":"img.mcp","rect":{"x":1,"y":2,"width":30,"height":40}}],"designTargets":[{"selector":"a.primary","role":"link","text":"Open","rect":{"x":5,"y":6,"width":70,"height":24}}]}}}}' \
  '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"appshot_capture","arguments":{"format":"json","maxDepth":1,"useRecentCache":false,"browserDOMFixture":{"pageUrl":"http://localhost:9229/json","title":"Content Shell Remote Debugging","viewportSize":{"width":640,"height":480},"designTargets":[{"selector":"main","role":"document","text":"Content Shell Remote Debugging","rect":{"x":0,"y":0,"width":640,"height":480}}]}}}}' \
  '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"appshot_codex_apps_status","arguments":{}}}' \
  '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"list_apps","arguments":{}}}' \
  '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"get_app_state","arguments":{"app":"com.openai.codex"}}}' \
  '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"appshot_codex_computer_use_status","arguments":{}}}' \
  '{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"appshot_capture","arguments":{"format":"json","maxDepth":1,"useRecentCache":false,"browserDOMFixture":{"pageUrl":"https://example.test/mcp-electron","title":"MCP Electron Bridge","runtimeBridge":{"installed":true,"liveEventStreamAvailable":true,"version":"0.1.14","source":"appshot-browser-runtime-bridge","electronHostBridgeAvailable":true,"hostOwner":"electron-preload","hostTransport":"electron-ipc","events":[{"type":"browser-sidebar-runtime-message","source":"appshot-browser-runtime-bridge","bridgeEvent":true,"candidate":false,"hostOwner":"electron-preload","hostTransport":"electron-ipc"}]},"designTargets":[{"selector":"main","role":"document","text":"Electron Bridge","rect":{"x":0,"y":0,"width":640,"height":480}}]}}}}' \
  '{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"appshot_capture","arguments":{"format":"json","maxDepth":1,"useRecentCache":false,"browserDOMFixture":{"pageUrl":"https://example.test/mcp-codex-native","title":"MCP Native Codex Host","runtimeBridge":{"installed":false,"nativeCodexDesktopAvailable":true,"codexHostBridgeAvailable":true,"hostOwner":"codex-electron-host","hostTransport":"codex-electron-ipc","events":[{"type":"browser-sidebar-runtime-sync","source":"codex-comment-preload","bridgeEvent":true,"candidate":false,"hostOwner":"codex-electron-host","hostTransport":"codex-electron-ipc"}]},"designTargets":[{"selector":"main","role":"document","text":"Native Codex Host","rect":{"x":0,"y":0,"width":640,"height":480}}]}}}}' \
  | (cd "$RUN_DIR" && APPSHOT_BIN="$APP_BIN" node "$ROOT/mcp/server.js" >"$MCP_JSONL")

"$PYTHON" - "$MCP_JSONL" <<'PY'
import json
import sys

lines = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
expected_response_ids = list(range(1, 14))
if [line.get("id") for line in lines] != expected_response_ids:
    raise SystemExit(f"MCP response ids are not {expected_response_ids}")

tools = {tool["name"] for tool in lines[1]["result"]["tools"]}
expected_tools = {"appshot_capture", "appshot_permissions", "appshot_status", "appshot_list_windows", "appshot_codex_apps_status", "appshot_codex_computer_use_status", "list_apps", "get_app_state"}
missing = sorted(expected_tools - tools)
if missing:
    raise SystemExit(f"MCP missing tools: {', '.join(missing)}")

status = json.loads(lines[2]["result"]["content"][0]["text"])
for key in ["captureCache", "frontmostApplication", "currentApplication", "primaryWindow", "frontmostWindow", "currentWindow"]:
    if key not in status:
        raise SystemExit(f"MCP status missing key: {key}")
permissions = status.get("permissions", {})
for key in ["identity", "stability"]:
    if key not in permissions:
        raise SystemExit(f"MCP status permissions missing key: {key}")

codex_text = lines[3]["result"]["content"][0]["text"]
if not codex_text.startswith("<appshot ") or "Window:" not in codex_text or "</appshot>" not in codex_text:
    raise SystemExit("MCP codex capture did not return a complete appshot block")

mcp_policy = json.loads(lines[4]["result"]["content"][0]["text"])
mcp_policy_settings = mcp_policy.get("codexBrowserSettings", {})
mcp_policy_payload = mcp_policy.get("codexBrowserPayload", {})
mcp_policy_metadata = mcp_policy_payload.get("localBrowserCommentMetadata", {})
mcp_runtime_state = mcp_policy.get("codexBrowserRuntimeState", {})
if mcp_policy_settings.get("browser-annotation-screenshots-mode") != "always":
    raise SystemExit("MCP policy capture did not preserve always mode")
if mcp_policy_metadata.get("annotationScreenshotsMode") != "always":
    raise SystemExit("MCP policy metadata did not preserve always mode")
if "screenshot" not in mcp_policy:
    raise SystemExit("MCP policy capture did not attempt screenshot for always mode")
if mcp_policy.get("screenshot", {}).get("captureMode") not in {"windowID", "bounds", "screen"}:
    raise SystemExit("MCP policy screenshot captureMode drifted")
if mcp_runtime_state.get("annotationEditorMode") != "design":
    raise SystemExit("MCP runtime capture did not preserve design annotation editor mode")
if mcp_runtime_state.get("isOriginalViewEnabled") is not True:
    raise SystemExit("MCP runtime capture did not preserve original view")
if mcp_runtime_state.get("isDesignModifierPressed") is not True:
    raise SystemExit("MCP runtime capture did not preserve design modifier")
if mcp_runtime_state.get("isTweaksEditorOpen") is not True:
    raise SystemExit("MCP runtime capture did not preserve tweaks editor")
if mcp_runtime_state.get("activeDesignChange", {}).get("id") != "mcp-design":
    raise SystemExit("MCP runtime capture did not preserve activeDesignChange")
if mcp_policy_payload.get("localBrowserDesignChange", {}).get("group", {}).get("id") != "mcp-design":
    raise SystemExit("MCP runtime capture did not mirror activeDesignChange as a Codex design group")

mcp_dom = json.loads(lines[5]["result"]["content"][0]["text"])
mcp_dom_integration = mcp_dom.get("codexBrowserDOMIntegration", {})
mcp_dom_payload = mcp_dom.get("codexBrowserPayload", {})
if mcp_dom_integration.get("format") != "codex-browser-dom-integration":
    raise SystemExit("MCP DOM fixture did not return codex browser DOM integration")
if mcp_dom_integration.get("browserRuntimeBridgeEventCount") != 1:
    raise SystemExit("MCP DOM fixture did not preserve bridge events")
bridge = mcp_dom_integration.get("browserRuntimeBridge", {})
if bridge.get("codexDesktopShimAvailable") is not True:
    raise SystemExit("MCP DOM fixture did not expose Codex desktop shim availability")
if bridge.get("hostChannel") != "codex_desktop:browser-sidebar-runtime-message":
    raise SystemExit("MCP DOM fixture did not preserve Codex host channel")
if sorted(bridge.get("hostAPI", [])) != ["sendMessageToHost", "subscribeToHostMessages"]:
    raise SystemExit("MCP DOM fixture did not expose Codex host API names")
if bridge.get("extensionHelperAvailable") is not True:
    raise SystemExit("MCP DOM fixture did not expose extension helper availability")
if bridge.get("hostOwner") != "browser-extension":
    raise SystemExit("MCP DOM fixture did not preserve extension host owner")
if bridge.get("hostTransport") != "window.postMessage+extension-runtime":
    raise SystemExit("MCP DOM fixture did not preserve extension host transport")
if mcp_dom_integration.get("browserRuntimeCandidateEventCount") != 22:
    raise SystemExit("MCP DOM fixture did not preserve candidate event set")
if mcp_dom_integration.get("liveEventStreamAvailable") is not True:
    raise SystemExit("MCP DOM fixture did not preserve bridge liveEventStreamAvailable")
events = mcp_dom_integration.get("browserRuntimeEvents", [])
event_by_type = {event.get("type"): event for event in events}
if event_by_type.get("browser-sidebar-runtime-image-drag-started", {}).get("sourceUrl") != "https://example.test/mcp.png":
    raise SystemExit("MCP DOM fixture did not preserve image sourceUrl")
if event_by_type.get("browser-sidebar-runtime-open-design-editor", {}).get("anchorState", {}).get("anchor", {}).get("selector") != "a.primary":
    raise SystemExit("MCP DOM fixture did not mirror design event into payload")
if len(mcp_dom_payload.get("localBrowserRuntimeEvents", [])) != 23:
    raise SystemExit("MCP DOM fixture did not mirror bridge plus the full Codex runtime candidate event set")
if mcp_dom_payload.get("localBrowserRuntimeEvents", [{}])[0].get("bridgeEvent") is not True:
    raise SystemExit("MCP DOM fixture did not put bridge event into payload")
metadata_bridge = mcp_dom_payload.get("localBrowserCommentMetadata", {}).get("browserDOMIntegration", {})
if metadata_bridge.get("codexDesktopShimAvailable") is not True:
    raise SystemExit("MCP DOM payload metadata did not summarize Codex desktop shim availability")
if metadata_bridge.get("extensionHelperAvailable") is not True:
    raise SystemExit("MCP DOM payload metadata did not summarize extension helper availability")
if metadata_bridge.get("hostOwner") != "browser-extension":
    raise SystemExit("MCP DOM payload metadata did not summarize extension host owner")
if metadata_bridge.get("hostTransport") != "window.postMessage+extension-runtime":
    raise SystemExit("MCP DOM payload metadata did not summarize extension host transport")
if mcp_dom_payload.get("localBrowserRuntimeProtocol", {}).get("liveEventStreamAvailable") is not True:
    raise SystemExit("MCP DOM fixture did not mirror liveEventStreamAvailable into payload protocol")
mcp_dom_context = mcp_dom_payload.get("localBrowserContext", {})
mcp_dom_metadata = mcp_dom_payload.get("localBrowserCommentMetadata", {})
if mcp_dom_context.get("pageUrl") != "https://example.test/mcp":
    raise SystemExit("MCP DOM payload did not preserve real pageUrl")
if mcp_dom_context.get("targetSelector") != "a.primary":
    raise SystemExit("MCP DOM payload did not preserve target selector")
if mcp_dom_context.get("targetImmediateText") != "Open":
    raise SystemExit("MCP DOM payload did not preserve target immediate text")
if mcp_dom_metadata.get("kind") != "browser":
    raise SystemExit("MCP DOM payload did not switch metadata kind to browser")
if mcp_dom_metadata.get("markerViewportPoint", {}).get("x") is None:
    raise SystemExit("MCP DOM payload did not expose markerViewportPoint")

mcp_electron_bridge = json.loads(lines[11]["result"]["content"][0]["text"])
mcp_electron_runtime = mcp_electron_bridge.get("codexBrowserDOMIntegration", {}).get("browserRuntimeBridge", {})
if mcp_electron_runtime.get("electronHostBridgeAvailable") is not True:
    raise SystemExit("MCP Electron bridge fixture did not expose electronHostBridgeAvailable")
if mcp_electron_runtime.get("hostOwner") != "electron-preload":
    raise SystemExit("MCP Electron bridge fixture did not preserve electron host owner")
if mcp_electron_runtime.get("hostTransport") != "electron-ipc":
    raise SystemExit("MCP Electron bridge fixture did not preserve electron host transport")
mcp_electron_metadata = mcp_electron_bridge.get("codexBrowserPayload", {}).get("localBrowserCommentMetadata", {}).get("browserDOMIntegration", {})
if mcp_electron_metadata.get("electronHostBridgeAvailable") is not True:
    raise SystemExit("MCP Electron bridge payload metadata did not summarize electron host bridge availability")
if mcp_electron_metadata.get("hostOwner") != "electron-preload":
    raise SystemExit("MCP Electron bridge payload metadata did not summarize electron host owner")
if mcp_electron_metadata.get("hostTransport") != "electron-ipc":
    raise SystemExit("MCP Electron bridge payload metadata did not summarize electron host transport")

mcp_native_codex = json.loads(lines[12]["result"]["content"][0]["text"])
mcp_native_runtime = mcp_native_codex.get("codexBrowserDOMIntegration", {}).get("browserRuntimeBridge", {})
if mcp_native_runtime.get("nativeCodexDesktopAvailable") is not True:
    raise SystemExit("MCP native Codex fixture did not expose nativeCodexDesktopAvailable")
if mcp_native_runtime.get("codexHostBridgeAvailable") is not True:
    raise SystemExit("MCP native Codex fixture did not expose codexHostBridgeAvailable")
if mcp_native_runtime.get("codexDesktopShimAvailable") is not False:
    raise SystemExit("MCP native Codex fixture must not be labeled as an AppShot shim")
if mcp_native_runtime.get("hostOwner") != "codex-electron-host":
    raise SystemExit("MCP native Codex fixture did not preserve Codex host owner")
if mcp_native_runtime.get("hostTransport") != "codex-electron-ipc":
    raise SystemExit("MCP native Codex fixture did not preserve native Codex host transport")
mcp_native_metadata = mcp_native_codex.get("codexBrowserPayload", {}).get("localBrowserCommentMetadata", {}).get("browserDOMIntegration", {})
if mcp_native_metadata.get("nativeCodexDesktopAvailable") is not True:
    raise SystemExit("MCP native Codex payload metadata did not summarize native Codex desktop availability")
if mcp_native_metadata.get("codexHostBridgeAvailable") is not True:
    raise SystemExit("MCP native Codex payload metadata did not summarize Codex host bridge availability")
if mcp_native_metadata.get("codexDesktopShimAvailable") is not False:
    raise SystemExit("MCP native Codex payload metadata must not summarize an AppShot shim")
if mcp_native_metadata.get("hostOwner") != "codex-electron-host":
    raise SystemExit("MCP native Codex payload metadata did not summarize Codex host owner")
if mcp_native_metadata.get("hostTransport") != "codex-electron-ipc":
    raise SystemExit("MCP native Codex payload metadata did not summarize native Codex host transport")
if mcp_native_codex.get("codexBrowserPayload", {}).get("localBrowserRuntimeProtocol", {}).get("liveEventStreamAvailable") is not True:
    raise SystemExit("MCP native Codex fixture did not mirror live stream availability into payload protocol")

mcp_debug_dom = json.loads(lines[6]["result"]["content"][0]["text"])
mcp_debug_remote = mcp_debug_dom.get("codexBrowserDOMIntegration", {}).get("remoteDebuggingTarget", {})
if mcp_debug_remote.get("isRemoteDebuggingTarget") is not True:
    raise SystemExit("MCP DOM fixture did not detect Codex remote debugging target")
if mcp_debug_remote.get("titleMatched") is not True:
    raise SystemExit("MCP DOM fixture did not detect content shell title")
if mcp_debug_remote.get("localDebugPortMatched") is not True:
    raise SystemExit("MCP DOM fixture did not detect localhost debug port")
if mcp_debug_remote.get("port") != 9229:
    raise SystemExit("MCP DOM fixture did not preserve debug port 9229")

mcp_codex_apps = json.loads(lines[7]["result"]["content"][0]["text"])
if mcp_codex_apps.get("format") != "codex-accessible-connectors-status":
    raise SystemExit("MCP codex apps status returned unexpected format")
if mcp_codex_apps.get("forceRefetchSupported") is not True:
    raise SystemExit("MCP codex apps status did not preserve forceRefetchSupported")
if mcp_codex_apps.get("retryWhenNotReady") is not True:
    raise SystemExit("MCP codex apps status did not preserve retryWhenNotReady")
if mcp_codex_apps.get("codexAppsReady") != (len(mcp_codex_apps.get("blockers", [])) == 0):
    raise SystemExit("MCP codex apps readiness does not match blockers")
if "appshot_codex_apps_status" not in mcp_codex_apps.get("tools", []):
    raise SystemExit("MCP codex apps status did not include its own tool surface")

mcp_list_apps = lines[8]["result"]["content"][0]["text"]
if "com.openai.codex" not in mcp_list_apps:
    raise SystemExit("MCP list_apps did not include Codex")

mcp_get_app_state = lines[9]["result"]
content = mcp_get_app_state.get("content", [])
if not content or content[0].get("type") != "text" or not content[0].get("text", "").startswith("<appshot "):
    raise SystemExit("MCP get_app_state did not return Codex-style appshot text")
if not any(item.get("type") == "image" and item.get("mimeType") == "image/png" and item.get("data") for item in content):
    raise SystemExit("MCP get_app_state did not return a PNG image content block")

mcp_cua = json.loads(lines[10]["result"]["content"][0]["text"])
if mcp_cua.get("format") != "codex-computer-use-status":
    raise SystemExit("MCP Codex Computer Use status returned unexpected format")
if mcp_cua.get("serviceBundleIdentifier") != "com.openai.sky.CUAService":
    raise SystemExit("MCP Codex Computer Use status lost service bundle identifier")
for name, payload in [
    ("MCP Codex Computer Use status", mcp_cua),
    ("MCP codex apps nested Computer Use status", mcp_codex_apps.get("codexComputerUseStatus", {})),
]:
    host_bridge = payload.get("hostBridge", {})
    integration = host_bridge.get("codexHostIntegration", {})
    if integration.get("format") != "codex-electron-host-integration-status":
        raise SystemExit(f"{name} lost codexHostIntegration format")
    if integration.get("requiredCodexSideIntegration") is not True:
        raise SystemExit(f"{name} lost requiredCodexSideIntegration")
    if integration.get("privateCodexWebviewHostAttached") is not False:
        raise SystemExit(f"{name} must not claim Codex private host attachment from standalone MCP")
    if integration.get("hostChannel") != "codex_desktop:browser-sidebar-runtime-message":
        raise SystemExit(f"{name} codexHostIntegration hostChannel drifted")
    if sorted(integration.get("hostAPI", [])) != ["sendMessageToHost", "subscribeToHostMessages"]:
        raise SystemExit(f"{name} codexHostIntegration host API drifted")
    if "codex-electron-host" not in integration.get("expectedHostOwners", []):
        raise SystemExit(f"{name} codexHostIntegration missing Codex host owner")
    if "codex-electron-ipc+appshot-electron-ipc" not in integration.get("expectedHostTransports", []):
        raise SystemExit(f"{name} codexHostIntegration missing Codex host transport")
    artifacts = integration.get("integrationArtifacts", {})
    for artifact_name in ["codexHostAdapter", "electronPreloadHelper", "browserExtensionHelper"]:
        artifact = artifacts.get(artifact_name, {})
        if "path" not in artifact or "requiredFiles" not in artifact:
            raise SystemExit(f"{name} missing integration artifact diagnostics for {artifact_name}")
PY

log "ok"
