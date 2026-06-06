#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

print_codesign() {
  local label="$1"
  local path="$2"

  if [[ ! -e "$path" ]]; then
    return 0
  fi

  printf '\n[%s]\n' "$label"
  printf 'path: %s\n' "$path"

  if [[ -d "$path" && -f "$path/Contents/Info.plist" ]]; then
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$path/Contents/Info.plist" 2>/dev/null | sed 's/^/bundleIdentifier: /' || true
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$path/Contents/Info.plist" 2>/dev/null | sed 's/^/version: /' || true
  fi

  codesign -dv --verbose=4 "$path" 2>&1 \
    | grep -E '^(Executable|Identifier|CDHash|Signature|TeamIdentifier)=' \
    || true
}

printf 'AppShot TCC identity diagnosis\n'
printf 'repo: %s\n' "$ROOT"

RUNNING_APPS="$(mktemp)"
trap 'rm -f "$RUNNING_APPS"' EXIT

printf '\n[running processes]\n'
if ! ps -axo pid,ppid,command 2>/dev/null \
  | awk '/\/AppShot\.app\/Contents\/MacOS\/AppShot/ || /\/\.local\/bin\/appshot/ || /\/\.build\/.*\/appshot/ { print }'; then
  printf 'unavailable: this process cannot inspect the process table in the current sandbox\n'
fi

ps -axo command 2>/dev/null \
  | awk '/\/AppShot\.app\/Contents\/MacOS\/AppShot/ { sub(/\/Contents\/MacOS\/AppShot.*/, ""); print }' \
  | sort -u >"$RUNNING_APPS" || true

while IFS= read -r app_path; do
  [[ -n "$app_path" ]] || continue
  print_codesign "running app bundle" "$app_path"
done <"$RUNNING_APPS"

print_codesign "installed app" "$HOME/Applications/AppShot.app"
print_codesign "debug app" "$ROOT/.xcode-build/Build/Products/Debug/AppShot.app"
print_codesign "release app" "$ROOT/.xcode-build/Products/Release/AppShot.app"
print_codesign "swiftpm debug cli" "$ROOT/.build/debug/appshot"
print_codesign "installed cli" "$HOME/.local/bin/appshot"

printf '\n[available code signing identities]\n'
security find-identity -v -p codesigning || true

cat <<'NOTE'

[what this means]
macOS privacy permissions are tied to the app's code-signing requirement, not just the visible name.
If two AppShot entries have the same bundle identifier but different CDHash values and use ad-hoc signing,
TCC can treat them as different identities. Xcode Debug builds, installed release builds, and SwiftPM CLI
binaries can therefore disagree about whether Accessibility or Screen Recording is already granted.

The AppShot JSON now exposes this directly under:

  permissions.identity
  permissions.stability

For stable permissions, grant permissions to one installed AppShot.app and keep using that exact app identity.
For development/release builds that should preserve permissions across rebuilds, sign with a stable identity:

  APPSHOT_CODESIGN_IDENTITY="Developer ID Application: ..." scripts/build_release.sh

If no signing identities are listed above, local builds are ad-hoc signed and can require re-authorization
after rebuilds or when switching between Debug, installed app, and CLI identities.
NOTE
