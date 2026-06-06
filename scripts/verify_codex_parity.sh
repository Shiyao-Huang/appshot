#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE_ROOT="$(cd "$ROOT/.." && pwd)"
CODEX_EVIDENCE_ROOT="${CODEX_EVIDENCE_ROOT:-$WORKSPACE_ROOT/codex-522/mac-app}"
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

log "checking Codex Mac app evidence"
require_file "$EVENTS"
require_file "$APP_SESSION_SNIPPETS"
require_file "$PRELOAD_SNIPPETS"
require_file "$PARITY_MATRIX"
require_file "$QA_SCRIPT"
require_file "$TCC_SCRIPT"
require_file "$SKILL_FILE"

for event in \
  browser-sidebar-runtime-prepare-comment-screenshot \
  browser-sidebar-runtime-comment-screenshot-ready \
  browser-sidebar-runtime-open-editor \
  browser-sidebar-runtime-open-design-editor \
  browser-sidebar-runtime-open-design-editor-at-point \
  browser-sidebar-runtime-design-scrub-changed \
  browser-sidebar-runtime-image-drag-started \
  browser-sidebar-runtime-image-drag-ended
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
  "localBrowserScreenshot" \
  "localBrowserDesignChange" \
  "browser-sidebar-runtime-open-design-editor" \
  "browser-sidebar-runtime-image-drag-started" \
  "scripts/qa_app_capture.py" \
  "target-window screenshot metadata" \
  "window-bound image dimensions" \
  "TCC identity diagnosis" \
  "Permission identity JSON" \
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
"$PYTHON" - "$ROOT" "$APP_BUNDLE" <<'PY'
import json
import pathlib
import plistlib
import re
import sys

root = pathlib.Path(sys.argv[1])
app_bundle = pathlib.Path(sys.argv[2])
plugin = json.loads((root / ".codex-plugin/plugin.json").read_text())
mcp = json.loads((root / "mcp/package.json").read_text())
server = (root / "mcp/server.js").read_text()
installer = (root / "install.sh").read_text()
release = (root / "scripts/build_release.sh").read_text()
app = (root / "Sources/AppShotApp/AppShotApp.swift").read_text()
cli = (root / "Sources/AppShotCLI/AppShotCLI.swift").read_text()
core = (root / "Sources/AppShotCore/AppShotCore.swift").read_text()
qa = (root / "scripts/qa_app_capture.py").read_text()
tcc = (root / "scripts/diagnose_tcc_identity.sh").read_text()
skill = (root / "skills/appshot/SKILL.md").read_text()

expected = "0.1.2"
checks = {
    "plugin version": plugin.get("version"),
    "mcp package version": mcp.get("version"),
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

for name, text, pattern in [
    ("mcp server", server, r'version:\s*"0\.1\.2"'),
    ("installer default", installer, r'VERSION="\$\{APPSHOT_VERSION:-0\.1\.2\}"'),
    ("release default", release, r'VERSION="\$\{1:-0\.1\.2\}"'),
]:
    if not re.search(pattern, text):
        raise SystemExit(f"{name} is not aligned to {expected}")

for name, text, needles in [
    ("App shortcut/settings", app, ["OptionPairShortcutMonitor", "Left Option + Right Option", "AppShotSettingsView", "isGlobalShortcutEnabled", "writeCache", "captureCacheSummary", "left-right-option"]),
    ("CLI timeout/options", cli, ["--accessibility-timeout", "--screenshot-timeout", "--format", "--codex", "format == \"codex\"", "--ignore-cache", "--cache-max-age", "--write-cache"]),
    ("MCP timeout/schema/format", server, ["accessibilityTimeout", "screenshotTimeout", "format", "\"codex\"", "--format", "useRecentCache", "cacheMaxAge", "--ignore-cache"]),
    ("Claude Code installer", installer, ["APPSHOT_INSTALL_CLAUDE_CODE", "CLAUDE_SKILL_DIR", "claude mcp add", "APPSHOT_BIN=$BIN_PATH"]),
    ("public release gate", release, ["APPSHOT_PUBLIC_RELEASE", "Developer ID Application", "APPSHOT_NOTARY_PROFILE", "stapler validate", "spctl --assess"]),
    ("AX hierarchy safeguards", core, ["isAXDescendantAttribute", "localChildIDs", "focusedVisited", "mainWindowVisited", "axShouldCompactRow", "axCompactInteractiveDescendants", "AXGroup"]),
    ("Codex text formatter", core, ["codexSummaryPayload", "codexSummaryText", "codex-appshot-text", "<appshot", "Selected:", "Note: Pay special attention", "codexSettableAnnotation", "codexRoleName", "codexShouldDedupeStructuralLine", "HTML 内容"]),
    ("Shortcut capture cache", core, ["captureCacheStatus", "recentCaptureCache", "payloadByWritingCaptureCache", "captureCacheMetadata", "captureCache", "cacheMaxAgeSeconds"]),
    ("Visible text ordering", core, ["visibleTextLines", "VisibleTextEntry", "visibleTextLineCount", "visibleTextFragments", "AXBoundsForRange"]),
    ("QA capture checks", qa, ["--expect-ax", "--expect-visible", "--expect-ocr", "--expect-hierarchy", "screenshot captured", "screenshot matches target window", "screenshot size matches window bounds", "visible text available", "accessibility root is target window", "hierarchy contains"]),
    ("TCC identity diagnostics", tcc, ["CDHash", "Signature", "TeamIdentifier", "ad-hoc", "APPSHOT_CODESIGN_IDENTITY", "security find-identity", "permissions.identity", "permissions.stability", "running app bundle"]),
    ("Permission identity JSON", core, ["permissionIdentity", "permissionStability", "recommendedGrantTarget", "currentExecutablePath", "stableInstalledApp", "commandLineTool"]),
    ("Codex skill workflow", skill, ["--accessibility-timeout 20", "--ignore-cache", "left and right Option", "captureCache", "scripts/qa_app_capture.py", "scripts/diagnose_tcc_identity.sh", "tccutil reset Accessibility", "permissions.identity", "permissions.stability", "target-window screenshot metadata", "appshot_status", "currentApplication", "targetApplication", "frontmostWindow", "currentWindow"]),
]:
    missing = [needle for needle in needles if needle not in text]
    if missing:
        raise SystemExit(f"{name} missing anchors: {', '.join(missing)}")
PY

STATUS_JSON="$(mktemp)"
CAPTURE_JSON="$(mktemp)"
CODEX_TXT="$(mktemp)"
MCP_JSONL="$(mktemp)"
trap 'rm -f "$STATUS_JSON" "$CAPTURE_JSON" "$CODEX_TXT" "$MCP_JSONL"' EXIT

log "checking CLI status/capture schema"
"$APP_BIN" status --pretty >"$STATUS_JSON"
"$APP_BIN" capture --max-depth 1 --ignore-cache --pretty >"$CAPTURE_JSON"
"$APP_BIN" capture --max-depth 1 --ignore-cache --format codex >"$CODEX_TXT"

"$PYTHON" - "$STATUS_JSON" "$CAPTURE_JSON" "$CODEX_TXT" <<'PY'
import json
import sys

status = json.load(open(sys.argv[1]))
capture = json.load(open(sys.argv[2]))
codex_text = open(sys.argv[3]).read()

def require_keys(name, payload, keys):
    missing = [key for key in keys if key not in payload]
    if missing:
        raise SystemExit(f"{name} missing keys: {', '.join(missing)}")

require_keys(
    "status",
    status,
    ["schemaVersion", "permissions", "captureCache", "frontmostApplication", "currentApplication", "primaryWindow", "frontmostWindow", "currentWindow"],
)
require_keys(
    "capture",
    capture,
    ["schemaVersion", "permissions", "frontmostApplication", "currentApplication", "targetApplication", "windows", "accessibility", "codex"],
)

if isinstance(capture.get("primaryWindow"), dict):
    require_keys("capture primaryWindow", capture["primaryWindow"], ["windowID", "windowNumber", "ownerPID", "bounds", "isOnScreen"])
    require_keys("capture", capture, ["frontmostWindow", "currentWindow"])

accessibility = capture.get("accessibility", {})
require_keys("capture accessibility", accessibility, ["trusted", "rootSource", "root", "text", "textLineCount", "visibleText", "visibleTextLineCount"])
if accessibility.get("rootSource") not in {"targetWindow", "focusedWindow", "application"}:
    raise SystemExit(f"unexpected accessibility.rootSource: {accessibility.get('rootSource')!r}")
if accessibility.get("trusted") and accessibility.get("visibleTextLineCount", 0) <= 0:
    raise SystemExit("trusted accessibility capture has no visibleText lines")

codex = capture.get("codex", {})
require_keys("capture codex", codex, ["format", "text", "treeLineCount", "selectedLineCount", "hasFocusedElement"])
if codex.get("format") != "codex-appshot-text":
    raise SystemExit(f"unexpected codex format: {codex.get('format')!r}")
if not codex.get("text", "").startswith("<appshot "):
    raise SystemExit("capture codex text does not start with <appshot")
if "Window:" not in codex.get("text", ""):
    raise SystemExit("capture codex text missing Window header")
if not codex_text.startswith("<appshot ") or "Window:" not in codex_text or "</appshot>" not in codex_text:
    raise SystemExit("CLI --format codex output is not a complete appshot block")

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
  | APPSHOT_BIN="$APP_BIN" node "$ROOT/mcp/server.js" >"$MCP_JSONL"

"$PYTHON" - "$MCP_JSONL" <<'PY'
import json
import sys

lines = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
if [line.get("id") for line in lines] != [1, 2, 3, 4]:
    raise SystemExit("MCP response ids are not [1, 2, 3, 4]")

tools = {tool["name"] for tool in lines[1]["result"]["tools"]}
expected_tools = {"appshot_capture", "appshot_permissions", "appshot_status", "appshot_list_windows"}
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
PY

log "ok"
