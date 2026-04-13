#!/usr/bin/env bash
# build.sh — Build Glyphyx.saver
#
# Usage:
#   ./build.sh           # unsigned build (default, used by CI)
#   ./build.sh --sign    # auto-detect Developer ID cert and sign
#
set -euo pipefail

BUILD_DIR="$(pwd)/build"
SIGN=false

for arg in "$@"; do
    [[ "$arg" == "--sign" ]] && SIGN=true
done

if [ "$SIGN" = true ]; then
    CERT=$(security find-identity -v -p codesigning \
        | grep "Developer ID" \
        | head -1 \
        | sed 's/.*"\(.*\)"/\1/')
    if [ -z "$CERT" ]; then
        echo "error: No Developer ID certificate found in keychain."
        echo "       Install one from developer.apple.com or run without --sign."
        exit 1
    fi
    echo "Signing with: $CERT"
    SIGN_OPTS=(
        CODE_SIGN_IDENTITY="$CERT"
        CODE_SIGNING_REQUIRED=YES
        CODE_SIGNING_ALLOWED=YES
    )
else
    SIGN_OPTS=(
        CODE_SIGN_IDENTITY=""
        CODE_SIGNING_REQUIRED=NO
        CODE_SIGNING_ALLOWED=NO
    )
fi

xcodebuild \
    -project Glyphyx.xcodeproj \
    -target Glyphyx \
    -configuration Release \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    "${SIGN_OPTS[@]}" \
    build

echo ""
echo "✓ Built: $BUILD_DIR/Glyphyx.saver"
echo "  Double-click it to install."
