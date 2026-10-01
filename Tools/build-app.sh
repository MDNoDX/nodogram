#!/usr/bin/env bash
#
# Builds Nodogram.app — a real, double-clickable macOS application bundle.
#
#   ./Tools/build-app.sh            release build (default)
#   ./Tools/build-app.sh debug      debug build
#
# Why a hand-assembled bundle instead of an .xcodeproj: the app is a Swift
# package, and a generated project would be a second source of truth that
# drifts. Assembling the bundle here keeps one build path that works from the
# CLI and from CI.
#
# Telegram credentials are read from Config/Secrets.xcconfig (git-ignored) and
# injected into Info.plist at build time. They are never compiled into source.
# See Documentation/SECURITY_MODEL.md §7.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

CONFIG="${1:-release}"
APP_NAME="Nodogram"
BUNDLE_ID_DEFAULT="com.example.nodogram"
VERSION="0.1.0"
BUILD_NUMBER="1"

say() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m warning:\033[0m %s\n' "$1"; }

# ── Credentials ──────────────────────────────────────────────────────────────
read_xcconfig() {
  # Reads KEY = VALUE from an xcconfig, tolerating spaces and // comments.
  local file="$1" key="$2"
  [ -f "$file" ] || { printf ''; return; }
  sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "$file" \
    | sed 's#//.*##' \
    | sed 's/[[:space:]]*$//' \
    | head -1
}

SECRETS="$ROOT/Config/Secrets.xcconfig"
SIGNING="$ROOT/Config/Signing.xcconfig"

API_ID="$(read_xcconfig "$SECRETS" TELEGRAM_API_ID)"
API_HASH="$(read_xcconfig "$SECRETS" TELEGRAM_API_HASH)"
TEAM_ID="$(read_xcconfig "$SIGNING" DEVELOPMENT_TEAM)"
BUNDLE_ID="$(read_xcconfig "$SIGNING" PRODUCT_BUNDLE_IDENTIFIER)"
BUNDLE_ID="${BUNDLE_ID:-$BUNDLE_ID_DEFAULT}"

if [ -z "$API_ID" ] || [ -z "$API_HASH" ]; then
  warn "No Telegram credentials found in Config/Secrets.xcconfig."
  warn "The app will build and launch, and will show setup instructions."
fi

# ── Compile ──────────────────────────────────────────────────────────────────
say "Building NodogramApp ($CONFIG)"
if [ "$CONFIG" = "debug" ]; then
  swift build --product NodogramApp
else
  swift build -c release --product NodogramApp
fi
BIN_PATH="$(swift build $([ "$CONFIG" = release ] && echo '-c release') --show-bin-path)"
EXECUTABLE="$BIN_PATH/NodogramApp"

[ -x "$EXECUTABLE" ] || { echo "error: executable not found at $EXECUTABLE" >&2; exit 1; }

# ── Icon ─────────────────────────────────────────────────────────────────────
ICNS="$ROOT/Tools/icon/$APP_NAME.icns"
if [ ! -f "$ICNS" ]; then
  say "Generating app icon"
  python3 "$ROOT/Tools/icon/make_icon.py" "$ROOT/Tools/icon/$APP_NAME.iconset" >/dev/null
  iconutil -c icns "$ROOT/Tools/icon/$APP_NAME.iconset" -o "$ICNS"
fi

# ── Assemble the bundle ──────────────────────────────────────────────────────
APP="$ROOT/build/$APP_NAME.app"
say "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$EXECUTABLE" "$APP/Contents/MacOS/$APP_NAME"
cp "$ICNS" "$APP/Contents/Resources/$APP_NAME.icns"

# Localizations, so the app is translatable from day one (brief §55).
for lproj in "$ROOT"/Nodogram/Resources/Localizations/*.lproj; do
  [ -d "$lproj" ] && cp -R "$lproj" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><true/>
    <key>NSSupportsSuddenTermination</key><false/>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>uz-Latn</string>
        <string>uz-Cyrl</string>
        <string>ru</string>
    </array>
    <key>NSHumanReadableCopyright</key>
    <string>Nodogram is an independent, unofficial client. Not affiliated with, endorsed by, or sponsored by Telegram.</string>
    <key>TelegramAPIID</key><string>$API_ID</string>
    <key>TelegramAPIHash</key><string>$API_HASH</string>
</dict>
</plist>
PLIST

# NSSupportsSuddenTermination is false on purpose: TDLib requires its clients be
# closed before termination to keep its database consistent, and drafts are
# flushed on the same path.

# ── Sign ─────────────────────────────────────────────────────────────────────
if [ -n "$TEAM_ID" ]; then
  say "Signing with team $TEAM_ID"
  codesign --force --deep --options runtime --timestamp \
           --sign "Developer ID Application" "$APP" 2>/dev/null \
    || codesign --force --deep --sign - "$APP"
else
  # Ad-hoc signing is enough to run locally and keeps Keychain access working.
  say "Signing ad-hoc (no DEVELOPMENT_TEAM set)"
  codesign --force --deep --sign - "$APP"
fi

codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

say "Built $APP"
echo "    open \"$APP\""
