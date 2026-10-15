#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
if [[ "$configuration" != debug && "$configuration" != release ]]; then
    echo "Usage: bash scripts/build.sh [debug|release] [--universal]" >&2
    exit 1
fi
minimum=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' build/Info.plist)
app="$PWD/dist/Glint.app"
staging="$PWD/dist/.Glint-stage.app"
mkdir -p dist
if [[ -e "$staging" ]]; then rm -rf "$staging"; fi
mkdir -p "$staging/Contents/MacOS" "$staging/Contents/Resources"
if [[ "${2:-}" == --universal ]]; then
    for arch in arm64 x86_64; do
        bash scripts/swift.sh build -c "$configuration" --arch "$arch" --product Glint -Xswiftc -target -Xswiftc "$arch-apple-macos$minimum" -Xswiftc -runtime-compatibility-version -Xswiftc none --scratch-path "$PWD/.build/$arch"
    done
    arm=$(bash scripts/swift.sh build -c "$configuration" --arch arm64 --scratch-path "$PWD/.build/arm64" --show-bin-path)
    intel=$(bash scripts/swift.sh build -c "$configuration" --arch x86_64 --scratch-path "$PWD/.build/x86_64" --show-bin-path)
    lipo -create "$arm/Glint" "$intel/Glint" -output "$staging/Contents/MacOS/Glint"
    binary_path="$arm"
else
    bash scripts/swift.sh build -c "$configuration" --product Glint -Xswiftc -target -Xswiftc "$(uname -m)-apple-macos$minimum" -Xswiftc -runtime-compatibility-version -Xswiftc none
    binary_path=$(bash scripts/swift.sh build -c "$configuration" --show-bin-path)
    cp "$binary_path/Glint" "$staging/Contents/MacOS/Glint"
fi
cp build/Info.plist "$staging/Contents/Info.plist"
cp build/icon.icns "$staging/Contents/Resources/icon.icns"
for bundle in "$binary_path"/*.bundle; do
    [[ -d "$bundle" ]] || continue
    cp -R "$bundle" "$staging/Contents/Resources/"
done
cp LICENSE "$staging/Contents/Resources/LICENSE"
mkdir -p "$staging/Contents/Resources/Licenses"
for package in SwiftMath swift-markdown swift-cmark; do
    source="$PWD/.build/checkouts/$package"
    [[ -d "$source" ]] || source="$PWD/.build/arm64/checkouts/$package"
    for license in "$source"/LICENSE*; do
        [[ -f "$license" ]] && cp "$license" "$staging/Contents/Resources/Licenses/$package-$(basename "$license")"
    done
done
codesign --force --sign - --identifier com.skywalker144.glint "$staging/Contents/MacOS/Glint"
codesign --force --deep --sign - --identifier com.skywalker144.glint "$staging"
codesign --verify --deep --strict "$staging"
if [[ -e "$app" ]]; then rm -rf "$app"; fi
mv "$staging" "$app"
echo "$app"
