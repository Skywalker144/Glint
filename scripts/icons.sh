#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .cache
icons=$(mktemp -d "$PWD/.cache/Glint.XXXXXX.iconset")
trap 'rm -rf "$icons"' EXIT
CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang" swift scripts/render-icons.swift "$icons"
iconutil -c icns "$icons" -o build/icon.icns
