#!/usr/bin/env bash
set -euo pipefail

fail=0
say_fail() { echo "FAIL: $*"; fail=1; }
say_ok() { echo "OK: $*"; }

product_version="$(sw_vers -productVersion)"
major="${product_version%%.*}"
minor_patch="${product_version#*.}"
minor="${minor_patch%%.*}"

if [[ "$(uname -m)" != "arm64" ]]; then
  say_fail "Apple Silicon required (arm64)"
else
  say_ok "arch arm64"
fi

if (( major < 14 || (major == 14 && minor < 4) )); then
  say_fail "macOS 14.4+ required (got $product_version)"
else
  say_ok "macOS $product_version"
fi

if ! xcode-select -p >/dev/null 2>&1; then
  say_fail "xcode-select not configured"
else
  dev_path="$(xcode-select -p)"
  say_ok "xcode-select -> $dev_path"
  if [[ "$dev_path" == *"Xcode-27"* ]] || [[ "$dev_path" == *"Xcode_27"* ]]; then
    say_fail "Xcode 27 selected on Sonoma — use Xcode 16.x (see scripts/install-xcode-sonoma.sh)"
  fi
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  say_fail "xcodebuild unavailable"
else
  xver="$(xcodebuild -version | head -1)"
  say_ok "$xver"
  if [[ "$xver" =~ Xcode\ ([0-9]+) ]]; then
    xmajor="${BASH_REMATCH[1]}"
    if (( xmajor >= 17 )) && (( major == 14 )); then
      say_fail "Xcode $xmajor on macOS 14 — install/select Xcode 16.x"
    fi
  fi
fi

for cmd in xcodegen ffmpeg ffprobe swift; do
  if command -v "$cmd" >/dev/null 2>&1; then
    say_ok "$cmd present"
  else
    say_fail "$cmd missing"
  fi
done

# Runtime: Whisper Core ML cache (~1.5GB) + working headroom. Xcode one-time install needs ~15–20GB extra (see README).
MIN_FREE_GB="${TAPSCRIBE_MIN_FREE_GB:-8}"
free_gb="$(df -g "$HOME" | awk 'NR==2 {print $4}')"
if (( free_gb < MIN_FREE_GB )); then
  say_fail "need at least ${MIN_FREE_GB}GB free for runtime (Whisper model + headroom; have ${free_gb}GB)"
else
  say_ok "disk free ${free_gb}GB (runtime minimum ${MIN_FREE_GB}GB)"
fi

if (( fail != 0 )); then
  echo "Prerequisites check failed."
  exit 1
fi
echo "Prerequisites check passed."
