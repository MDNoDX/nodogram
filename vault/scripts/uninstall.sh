#!/bin/zsh
# Stops and removes the Nodogram Vault service. Kept messages stay in the
# database; drop it with: dropdb -h 127.0.0.1 nodogram_vault
launchctl bootout "gui/$(id -u)/app.nodogram.vault" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/app.nodogram.vault.plist"
rm -rf "$HOME/Library/Application Support/Nodogram/vault-app"
echo "Nodogram Vault removed."
