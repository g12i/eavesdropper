#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodegen generate

SIGN_ARGS=()
if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
    SIGN_ARGS+=(CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=-)
else
  SIGN_ARGS+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" -allowProvisioningUpdates)
fi

# Pinned Package.resolved must stay buildable with the oldest Xcode in use (16.2 / Swift 6.0 on the M1):
# newer swift-collections / swift-crypto releases require newer Swift tools. Never let xcodebuild re-resolve.
xcodebuild -project Eavesdropper.xcodeproj -scheme Eavesdropper -configuration Debug \
  -derivedDataPath build -onlyUsePackageVersionsFromResolvedFile "${SIGN_ARGS[@]}" build

APP="build/Build/Products/Debug/Eavesdropper.app"
if [[ -d "$APP" ]]; then
    codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Authority|Identifier" || true
fi
