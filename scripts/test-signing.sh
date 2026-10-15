#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .cache
fixture=$(mktemp -d "$PWD/.cache/signing-script.XXXXXX")
trap 'if [[ -f "$fixture/.signing/Glint.keychain-db" ]]; then security delete-keychain "$fixture/.signing/Glint.keychain-db"; fi; rm -rf "$fixture"' EXIT
mkdir -p "$fixture/scripts" "$fixture/build"
cp scripts/signing.sh "$fixture/scripts/"
cp build/Info.plist "$fixture/build/"
bash "$fixture/scripts/signing.sh" create
printf 'int main(void) { return 0; }\n' > "$fixture/main.c"
xcrun clang "$fixture/main.c" -o "$fixture/Glint"
bash "$fixture/scripts/signing.sh" sign "$fixture/Glint"
cp "$fixture/build/signing.pem" "$fixture/original.pem"
cp "$fixture/.signing/identity.p12" "$fixture/original.p12"
cp "$fixture/.signing/password" "$fixture/original.password"
if bash "$fixture/scripts/signing.sh" create > "$fixture/create.log" 2>&1; then
    echo 'Creating a second signing identity should fail.' >&2
    exit 1
fi
cmp "$fixture/original.pem" "$fixture/build/signing.pem"
cmp "$fixture/original.p12" "$fixture/.signing/identity.p12"
export GLINT_SIGNING_P12_BASE64=$(base64 -i "$fixture/.signing/identity.p12")
export GLINT_SIGNING_PASSWORD=$(cat "$fixture/.signing/password")
cp build/signing.pem "$fixture/build/signing.pem"
if bash "$fixture/scripts/signing.sh" import > "$fixture/import.log" 2>&1; then
    echo 'Importing an identity with a different certificate should fail.' >&2
    exit 1
fi
cmp "$fixture/original.p12" "$fixture/.signing/identity.p12"
cmp "$fixture/original.password" "$fixture/.signing/password"
cp "$fixture/original.pem" "$fixture/build/signing.pem"
security delete-keychain "$fixture/.signing/Glint.keychain-db"
bash "$fixture/scripts/signing.sh" import
bash "$fixture/scripts/signing.sh" sign "$fixture/Glint"
bash "$fixture/scripts/signing.sh" verify "$fixture/Glint"
echo 'Signing creation, restoration, identity pinning and signing checks passed.'
