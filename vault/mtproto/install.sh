#!/bin/bash
# Installs the Nodik Watcher as a LaunchAgent so it runs continuously, restarts
# if it crashes, and starts at login — no terminal needed. Run: ./install.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
NODE="$(command -v node)"
LABEL="app.nodik.watcher"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOGDIR="$HOME/Library/Logs/Nodik"
mkdir -p "$LOGDIR"

if [ ! -f "$DIR/.env" ] || ! grep -q '^MTPROTO_SESSION=.\+' "$DIR/.env"; then
  echo "⚠️  .env yoki MTPROTO_SESSION yo'q. Avval: node login.mjs"; exit 1
fi

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$NODE</string><string>$DIR/watcher.mjs</string></array>
  <key>WorkingDirectory</key><string>$DIR</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key><string>$LOGDIR/watcher.log</string>
  <key>StandardErrorPath</key><string>$LOGDIR/watcher.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
sleep 1
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/$LABEL" 2>/dev/null || true
echo "✅ Nodik Watcher o'rnatildi va ishga tushdi. Log: $LOGDIR/watcher.log"
echo "   To'xtatish: launchctl bootout gui/$(id -u)/$LABEL"
