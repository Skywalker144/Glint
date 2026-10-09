#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-macocr.sh
swiftc -O src/main/native/macselection.swift -o resources/macselection -framework AppKit -framework ApplicationServices
