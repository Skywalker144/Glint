#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
command="${1:-}"
certificate="$PWD/build/signing.pem"
directory="$PWD/.signing"
keychain="$directory/Glint.keychain-db"
identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' build/Info.plist)
case "$command" in
    create|import)
        mkdir -p "$directory"
        temporary=$(mktemp -d "$directory/import.XXXXXX")
        trap 'rm -rf "$temporary"' EXIT
        if [[ "$command" == create ]]; then
            if [[ -e "$certificate" || -e "$directory/identity.p12" ]]; then
                echo "Signing identity already exists. Restore its private key instead of creating another certificate." >&2
                exit 1
            fi
            /usr/bin/openssl rand -hex 32 > "$temporary/password"
            cat > "$temporary/openssl.cnf" <<'CONFIG'
[req]
distinguished_name = subject
x509_extensions = signing
prompt = no
[subject]
CN = Glint Personal Code Signing
[signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
CONFIG
            /usr/bin/openssl req -x509 -newkey rsa:3072 -nodes -sha256 -days 36500 \
                -config "$temporary/openssl.cnf" \
                -keyout "$temporary/key.pem" -out "$temporary/certificate.pem" 2>/dev/null
            /usr/bin/openssl pkcs12 -export -inkey "$temporary/key.pem" -in "$temporary/certificate.pem" \
                -out "$temporary/identity.p12" -passout "file:$temporary/password"
            cp "$temporary/certificate.pem" "$certificate"
            chmod 644 "$certificate"
        else
            : "${GLINT_SIGNING_P12_BASE64:?Set GLINT_SIGNING_P12_BASE64 to the exported identity.p12}"
            : "${GLINT_SIGNING_PASSWORD:?Set GLINT_SIGNING_PASSWORD to its password}"
            test -f "$certificate"
            printf '%s' "$GLINT_SIGNING_P12_BASE64" | base64 --decode > "$temporary/identity.p12"
            printf '%s' "$GLINT_SIGNING_PASSWORD" > "$temporary/password"
        fi
        identity=$(/usr/bin/openssl x509 -in "$certificate" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
        imported=$(/usr/bin/openssl pkcs12 -in "$temporary/identity.p12" -passin "file:$temporary/password" -clcerts -nokeys | /usr/bin/openssl x509 -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
        if [[ "$identity" != "$imported" ]]; then
            echo "Imported signing certificate does not match build/signing.pem." >&2
            exit 1
        fi
        cp "$temporary/identity.p12" "$directory/identity.p12"
        cp "$temporary/password" "$directory/password"
        password=$(cat "$directory/password")
        if [[ ! -e "$keychain" ]]; then security create-keychain -p "$password" "$keychain"; fi
        security set-keychain-settings -lut 21600 "$keychain"
        security unlock-keychain -p "$password" "$keychain"
        security import "$directory/identity.p12" -P "$password" -t cert -f pkcs12 -k "$keychain" -T /usr/bin/codesign >/dev/null
        security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
        keychains=()
        while IFS= read -r existing; do
            if [[ "$existing" != "$keychain" ]]; then keychains+=("$existing"); fi
        done < <(security list-keychains -d user | sed -E 's/^ *"(.*)" *$/\1/')
        security list-keychains -d user -s "$keychain" "${keychains[@]}"
        echo "Signing identity installed. Back up .signing/identity.p12 and .signing/password together."
        ;;
    sign|verify)
        if [[ $# != 2 || ! -f "$certificate" ]]; then
            echo "Usage: bash scripts/signing.sh $command <app>; initialize or restore the signing identity first." >&2
            exit 1
        fi
        identity=$(/usr/bin/openssl x509 -in "$certificate" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
        if [[ "$command" == sign ]]; then
            if [[ ! -f "$directory/password" || ! -f "$keychain" ]]; then
                echo "Restore the signing identity with bash scripts/signing.sh import before building." >&2
                exit 1
            fi
            security unlock-keychain -p "$(cat "$directory/password")" "$keychain"
            if ! codesign --force --sign "$identity" --keychain "$keychain" --timestamp=none --identifier "$identifier" "$2"; then
                security find-identity -p codesigning "$keychain"
                exit 1
            fi
        fi
        codesign --verify --deep --strict -R "=identifier \"$identifier\" and certificate leaf = H\"$identity\"" "$2"
        ;;
    *)
        echo 'Usage: bash scripts/signing.sh <create|import|sign|verify> [app]' >&2
        exit 1
        ;;
esac
