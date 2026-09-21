#!/bin/zsh
# Pull the latest source and reinstall. Run from anywhere:
#   ~/NotchKo/scripts/update.sh
set -euo pipefail
cd "$(dirname "$0")/.."
echo "Updating NotchKo…"
git pull --ff-only
./scripts/install.sh
echo "Done — now on $(git log -1 --format='%h  %s')"
