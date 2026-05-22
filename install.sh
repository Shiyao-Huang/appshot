#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="${APPSHOT_REPO_OWNER:-Shiyao-Huang}"
REPO_NAME="${APPSHOT_REPO_NAME:-appshot}"
VERSION="${APPSHOT_VERSION:-0.1.0}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
SKILL_DIR="$CODEX_HOME/skills/appshot"
INSTALL_DIR="${APPSHOT_INSTALL_DIR:-$HOME/Applications}"
APP_PATH="$INSTALL_DIR/AppShot.app"
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
curl -fsSL \
  "https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/main/skills/appshot/SKILL.md" \
  -o "$SKILL_DIR/SKILL.md"

if [[ "${APPSHOT_SKILL_ONLY:-0}" == "1" ]]; then
  log "skill-only install complete"
  log "restart Codex to pick up the appshot skill"
  exit 0
fi

ZIP_URL="https://github.com/$REPO_OWNER/$REPO_NAME/releases/download/v$VERSION/AppShot-macOS-$VERSION.zip"
ZIP_PATH="$TMP_DIR/AppShot-macOS-$VERSION.zip"
UNPACK_DIR="$TMP_DIR/unpack"

log "downloading AppShot macOS release v$VERSION"
curl -fL "$ZIP_URL" -o "$ZIP_PATH"

mkdir -p "$UNPACK_DIR"
ditto -x -k "$ZIP_PATH" "$UNPACK_DIR"

FOUND_APP="$(find "$UNPACK_DIR" -maxdepth 2 -name 'AppShot.app' -type d | head -n 1)"
[[ -n "$FOUND_APP" ]] || fail "downloaded archive did not contain AppShot.app"

mkdir -p "$INSTALL_DIR"
rm -rf "$APP_PATH"
ditto "$FOUND_APP" "$APP_PATH"

log "installed AppShot.app to $APP_PATH"
if [[ "${APPSHOT_NO_OPEN:-0}" == "1" ]]; then
  log "skipping app launch because APPSHOT_NO_OPEN=1"
else
  log "opening AppShot"
  open "$APP_PATH" || true
fi

log "done"
log "restart Codex to pick up the appshot skill"
log "permissions: grant Accessibility and Screen Recording to AppShot when prompted"
