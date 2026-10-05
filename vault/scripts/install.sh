#!/bin/zsh
# Installs Nodogram Vault as a background service that starts at login and
# restarts if it ever stops. Re-run after pulling changes to update it.
# Remove with scripts/uninstall.sh.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
SUPPORT="$HOME/Library/Application Support/Nodogram"
APP="$SUPPORT/vault-app"
LOGS="$HOME/Library/Logs/Nodogram"
PLIST="$HOME/Library/LaunchAgents/app.nodogram.vault.plist"
NODE="$(command -v node)"

[[ -f "$SUPPORT/vault.env" ]] || { echo "Missing $SUPPORT/vault.env (see vault/README.md)"; exit 1; }

# Background services may not read ~/Downloads or ~/Documents, so the
# service runs from its own copy in Application Support.
mkdir -p "$APP" "$LOGS"
rsync -a --delete --exclude test --exclude scripts "$SRC/" "$APP/"
(cd "$APP" && npm install --omit=dev --silent)

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>app.nodogram.vault</string>
  <key>ProgramArguments</key>
  <array><string>$NODE</string><string>$APP/src/index.mjs</string></array>
  <key>WorkingDirectory</key><string>$APP</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$LOGS/vault.log</string>
  <key>StandardErrorPath</key><string>$LOGS/vault.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/app.nodogram.vault" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Nodogram Vault installed and running. Log: $LOGS/vault.log"
