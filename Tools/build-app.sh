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
# Built from the committed 1024 px master (Tools/icon/make_icon.swift draws
# it) with macOS's own tools, whenever the master is newer than the icns.
ICNS="$ROOT/Tools/icon/$APP_NAME.icns"
MASTER="$ROOT/Tools/icon/AppIcon-1024.png"
if [ ! -f "$ICNS" ] || [ "$MASTER" -nt "$ICNS" ]; then
  say "Generating app icon"
  SET="$ROOT/Tools/icon/$APP_NAME.iconset"
  rm -rf "$SET"; mkdir -p "$SET"
  for px in 16 32 128 256 512; do
    sips -z $px $px "$MASTER" --out "$SET/icon_${px}x${px}.png" >/dev/null
    sips -z $((px * 2)) $((px * 2)) "$MASTER" --out "$SET/icon_${px}x${px}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o "$ICNS"
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
elif security find-identity -v -p codesigning 2>/dev/null | grep -q '"Nodogram Local"'; then
  # A self-signed "Nodogram Local" certificate (Keychain Access → Certificate
  # Assistant → Create a Certificate…, type Code Signing) gives every build the
  # same certificate-backed identity, so the Keychain's "Always Allow" sticks
  # across rebuilds. See README → "Stop the Keychain prompts".
  say "Signing with the local certificate \"Nodogram Local\""
  codesign --force --deep --sign "Nodogram Local" "$APP"
else
  # Ad-hoc signing, with an explicit designated requirement.
  #
  # By default an ad-hoc signature's identity is the binary's hash, which
  # changes on every build. The Keychain ties stored keys to that identity, so
  # each rebuild would make macOS ask for the login password again before
  # Nodogram can read its own archive key. Pinning the requirement to the
  # bundle identifier keeps the identity stable across builds.
  #
  # Trade-off, stated plainly: an identifier is weaker than a certificate —
  # another ad-hoc app claiming the same identifier would match. Setting
  # DEVELOPMENT_TEAM in Config/Signing.xcconfig replaces this with a real,
  # certificate-backed identity.
  say "Signing ad-hoc with a stable identity (no DEVELOPMENT_TEAM set)"
  codesign --force --deep --sign - -r="designated => identifier \"$BUNDLE_ID\"" "$APP"
fi

codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

say "Built $APP"
echo "    open \"$APP\""
