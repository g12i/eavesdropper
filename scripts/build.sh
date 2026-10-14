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

xcodebuild -project TapScribe.xcodeproj -scheme TapScribe -configuration Debug \
  -derivedDataPath build "${SIGN_ARGS[@]}" build

APP="build/Build/Products/Debug/TapScribe.app"
if [[ -d "$APP" ]]; then
  codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Authority|Identifier" || true
fi
