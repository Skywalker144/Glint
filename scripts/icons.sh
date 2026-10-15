#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .cache
icons=$(mktemp -d "$PWD/.cache/Glint.XXXXXX.iconset")
trap 'rm -rf "$icons"' EXIT
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" build/icon.png --out "$icons/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" build/icon.png --out "$icons/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$icons" -o build/icon.icns
