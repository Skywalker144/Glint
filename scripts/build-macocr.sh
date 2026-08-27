#!/usr/bin/env bash
# 预编译 Vision OCR 命令行程序，供打包时内置（用户机无需安装 Xcode）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p resources
swiftc -O src/main/native/macocr.swift -o resources/macocr -framework Vision -framework AppKit
echo "built resources/macocr"
