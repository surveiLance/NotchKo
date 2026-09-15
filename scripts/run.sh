#!/bin/zsh
# Rebuild and relaunch.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh "${1:-debug}"
pkill -x Notch 2>/dev/null || true
sleep 0.3
open build/Notch.app
echo "launched"
