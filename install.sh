#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="${APPSHOT_REPO_OWNER:-Shiyao-Huang}"
REPO_NAME="${APPSHOT_REPO_NAME:-appshot}"
VERSION="${APPSHOT_VERSION:-0.1.9}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
SKILL_DIR="$CODEX_HOME/skills/appshot"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CLAUDE_SKILL_DIR="$CLAUDE_HOME/skills/appshot"
INSTALL_DIR="${APPSHOT_INSTALL_DIR:-$HOME/Applications}"
APP_PATH="$INSTALL_DIR/AppShot.app"
BIN_DIR="${APPSHOT_BIN_DIR:-$HOME/.local/bin}"
BIN_PATH="$BIN_DIR/appshot"
MCP_DIR="${APPSHOT_MCP_DIR:-$HOME/.local/share/appshot/mcp}"
BUNDLE_ID="${APPSHOT_BUNDLE_ID:-com.qppshot.AppShot}"
INSTALL_CLAUDE_CODE="${APPSHOT_INSTALL_CLAUDE_CODE:-${APPSHOT_INSTALL_CLAUDE_MCP:-0}}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

log() {
  printf 'appshot: %s\n' "$*"
}

fail() {
  printf 'appshot: error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "AppShot is currently macOS-only."
fi

need_cmd curl
need_cmd ditto

mkdir -p "$CODEX_HOME/skills"

log "installing Codex skill to $SKILL_DIR"
rm -rf "$SKILL_DIR"
mkdir -p "$SKILL_DIR"
SKILL_URL="${APPSHOT_SKILL_URL:-https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/main/skills/appshot/SKILL.md}"
curl -fsSL \
  "$SKILL_URL" \
  -o "$SKILL_DIR/SKILL.md"

if [[ "$INSTALL_CLAUDE_CODE" == "1" ]]; then
  log "installing Claude Code skill to $CLAUDE_SKILL_DIR"
  rm -rf "$CLAUDE_SKILL_DIR"
  mkdir -p "$CLAUDE_SKILL_DIR"
  curl -fsSL \
    "$SKILL_URL" \
    -o "$CLAUDE_SKILL_DIR/SKILL.md"
fi

if [[ "${APPSHOT_SKILL_ONLY:-0}" == "1" ]]; then
  log "skill-only install complete"
  log "restart Codex to pick up the appshot skill"
  if [[ "$INSTALL_CLAUDE_CODE" == "1" ]]; then
    log "restart Claude Code to pick up the appshot skill"
  fi
  exit 0
fi

ZIP_URL="${APPSHOT_ZIP_URL:-https://github.com/$REPO_OWNER/$REPO_NAME/releases/download/v$VERSION/AppShot-macOS-$VERSION.zip}"
ZIP_PATH="$TMP_DIR/AppShot-macOS-$VERSION.zip"
UNPACK_DIR="$TMP_DIR/unpack"

log "downloading AppShot macOS release v$VERSION"
curl -fL "$ZIP_URL" -o "$ZIP_PATH"

mkdir -p "$UNPACK_DIR"
ditto -x -k "$ZIP_PATH" "$UNPACK_DIR"

FOUND_APP="$(find "$UNPACK_DIR" -maxdepth 2 -name 'AppShot.app' -type d | head -n 1)"
[[ -n "$FOUND_APP" ]] || fail "downloaded archive did not contain AppShot.app"
FOUND_CLI="$(find "$UNPACK_DIR" -maxdepth 4 -type f -name 'appshot' -perm -111 | head -n 1)"
FOUND_MCP="$(find "$UNPACK_DIR" -maxdepth 4 -type f -path '*/mcp/server.js' | head -n 1)"

if [[ "${APPSHOT_RESET_PERMISSIONS:-0}" == "1" ]]; then
  log "resetting macOS privacy permissions for $BUNDLE_ID"
  tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
  tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 || true
  tccutil reset AppleEvents "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$APP_PATH"
ditto "$FOUND_APP" "$APP_PATH"

log "installed AppShot.app to $APP_PATH"

if [[ -n "$FOUND_CLI" ]]; then
  mkdir -p "$BIN_DIR"
  ditto "$FOUND_CLI" "$BIN_PATH"
  chmod +x "$BIN_PATH"
  log "installed appshot CLI to $BIN_PATH"
else
  log "release did not include appshot CLI; app install still completed"
fi

if [[ -n "$FOUND_MCP" ]]; then
  rm -rf "$MCP_DIR"
  mkdir -p "$MCP_DIR"
  ditto "$(dirname "$FOUND_MCP")/" "$MCP_DIR/"
  chmod +x "$MCP_DIR/server.js" || true
  log "installed AppShot MCP server to $MCP_DIR"

  if [[ "$INSTALL_CLAUDE_CODE" == "1" ]]; then
    if command -v claude >/dev/null 2>&1; then
      CLAUDE_MCP_SCOPE="${APPSHOT_CLAUDE_MCP_SCOPE:-user}"
      if [[ "$BIN_PATH" == "$HOME/.local/bin/appshot" && "$MCP_DIR" == "$HOME/.local/share/appshot/mcp" ]]; then
        CLAUDE_MCP_COMMAND='APPSHOT_BIN="$HOME/.local/bin/appshot" exec node "$HOME/.local/share/appshot/mcp/server.js"'
      else
        printf -v CLAUDE_MCP_COMMAND 'APPSHOT_BIN=%q exec node %q' "$BIN_PATH" "$MCP_DIR/server.js"
      fi
      log "installing AppShot MCP for Claude Code in $CLAUDE_MCP_SCOPE scope"
      claude mcp remove --scope "$CLAUDE_MCP_SCOPE" appshot >/dev/null 2>&1 || true
      claude mcp add --scope "$CLAUDE_MCP_SCOPE" appshot -- /bin/sh -lc "$CLAUDE_MCP_COMMAND"
    else
      log "Claude Code CLI was not found; skipping Claude MCP install"
    fi
  fi
fi

if [[ "${APPSHOT_NO_OPEN:-0}" == "1" ]]; then
  log "skipping app launch because APPSHOT_NO_OPEN=1"
else
  log "opening AppShot"
  open "$APP_PATH" || true
fi

log "done"
log "restart Codex to pick up the appshot skill"
if [[ "$INSTALL_CLAUDE_CODE" == "1" ]]; then
  log "restart Claude Code to pick up the appshot skill"
fi
log "cli: add $BIN_DIR to PATH if appshot is not found"
log "mcp: set APPSHOT_BIN=$BIN_PATH when running $MCP_DIR/server.js"
log "claude: rerun with APPSHOT_INSTALL_CLAUDE_CODE=1 to give Claude Code the Codex App Shot ability"
log "permissions: grant Accessibility and Screen Recording to AppShot when prompted"
