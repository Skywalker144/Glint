#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh release
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/Info.plist)
archive="dist/Glint-${version}-arm64-mac.zip"
image="dist/Glint-${version}-arm64.dmg"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent dist/Glint.app "$archive"
mkdir -p .cache/dmg
stage=$(mktemp -d "$PWD/.cache/dmg/stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
cp -R dist/Glint.app "$stage/Glint.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname Glint -srcfolder "$stage" -ov -format UDZO "$image"
(
    cd dist
    shasum -a 256 "$(basename "$archive")" "$(basename "$image")"
) > dist/SHA256SUMS
