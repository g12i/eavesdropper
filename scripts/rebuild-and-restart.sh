#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/build/Build/Products/Debug/Eavesdropper.app"

"$ROOT/scripts/build.sh"

killall Eavesdropper 2>/dev/null || true
open "$APP"

echo "Eavesdropper rebuilt and started: $APP"
