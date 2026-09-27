set -eu
cd "$(dirname "$0")/.."
xcrun swiftc -O -target "$(uname -m)-apple-macos13.0" -module-cache-path src-tauri/target/swift-cache src-tauri/native/main.swift -o src-tauri/resources/glint-native
