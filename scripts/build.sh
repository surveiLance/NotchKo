#!/bin/zsh
# Builds Notch.app without Xcode: swift build + hand-rolled bundle + ad-hoc sign.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
if ! swift build -c "$CONFIG" > /tmp/notch-build.log 2>&1; then
  grep -E "error" -A3 /tmp/notch-build.log | head -40
  echo "build failed"; exit 1
fi
grep -E "warning:" /tmp/notch-build.log | grep -v "Swift 6" | head -10 || true

BIN=".build/$CONFIG/Notch"

APP="build/Notch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Notch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
echo -n 'APPL????' > "$APP/Contents/PkgInfo"
# Sign with the stable "Notch Dev" certificate if it exists (keeps TCC grants
# like Accessibility across rebuilds); otherwise ad-hoc.
if security find-identity -p codesigning 2>/dev/null | grep -q "Notch Dev"; then
  codesign --force --sign "Notch Dev" "$APP" 2>/dev/null && SIG="Notch Dev" || SIG="ad-hoc"
else
  codesign --force --sign - "$APP" 2>/dev/null; SIG="ad-hoc"
fi
echo "built $APP ($CONFIG, signed: $SIG)"
