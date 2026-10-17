#!/bin/zsh
# Renders the popover, Settings and glyph to PNGs (light and dark) in <out-dir>. DEBUG builds only.
set -euo pipefail
out=${1:?usage: scripts/snapshot.sh <out-dir>}
mkdir -p "$out"
cd "$(dirname "$0")/.."
swift build --product SnailApp
SNAIL_SNAPSHOT_DIR="$(cd "$out" && pwd)" "$(swift build --show-bin-path)/SnailApp"
ls "$out"/*.png
