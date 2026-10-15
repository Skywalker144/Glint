#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.cache/clang"
command="${1:-build}"
shift || true
options=(--disable-sandbox --cache-path "$PWD/.cache/swift-cache")
if swift "$command" --help 2>/dev/null | rg -q -- '--disable-experimental-prebuilts'; then
    options+=(--disable-experimental-prebuilts)
fi
if [[ "$command" == build ]]; then options+=(--build-system swiftbuild); fi
if [[ "$command" == test ]]; then
    if ! xcodebuild -version >/dev/null 2>&1; then options+=(--build-system native); fi
fi
exec swift "$command" "${options[@]}" "$@"
