#!/bin/zsh
# Optimised build → /Applications/Notch.app → relaunch from there.
# First launch from /Applications registers it as a login item.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh release
pkill -x Notch 2>/dev/null || true
sleep 0.3
rm -rf /Applications/Notch.app
cp -R build/Notch.app /Applications/Notch.app
open /Applications/Notch.app
echo "installed /Applications/Notch.app"
