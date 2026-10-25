#!/usr/bin/env bash
# Repair Eavesdropper system.caf files affected by the 48 kHz tag / 44.1 kHz content bug,
# then export corrected audio as MP3.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Pitch correction: treat PCM as 44.1 kHz, resample to 48 kHz (matches file metadata).
REPAIR_FILTER='asetrate=44100,aresample=48000'
MP3_ARGS=(-codec:a libmp3lame -q:a 2)

DRY_RUN=false
FORCE=false
BATCH=false
INPUT_PATHS=()

usage() {
  cat <<'EOF'
Usage:
  repair-recording-to-mp3.sh /path/to/system.caf [output.mp3]
  repair-recording-to-mp3.sh --recordings

Options:
  --recordings   Process every ~/Recordings/**/system.caf
  --dry-run      Print ffmpeg commands without running them
  --force        Overwrite existing system-repaired.mp3
  -h, --help     Show this help

Requires ffmpeg (brew install ffmpeg).
EOF
}

require_ffmpeg() {
  if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "Error: ffmpeg not found in PATH." >&2
    echo "Install with: brew install ffmpeg" >&2
    exit 1
  fi
}

default_output_for() {
  local caf="$1"
  local dir
  dir="$(dirname "$caf")"
  echo "${dir}/system-repaired.mp3"
}

repair_one() {
  local input="$1"
  local output="${2:-}"

  if [[ ! -f "$input" ]]; then
    echo "Error: input file not found: $input" >&2
    return 1
  fi

  if [[ -z "$output" ]]; then
    output="$(default_output_for "$input")"
  fi

  if [[ -f "$output" && "$FORCE" != true ]]; then
    echo "Skip (already exists): $output"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    printf 'dry-run: ffmpeg -y -i %q -af %q' "$input" "$REPAIR_FILTER"
    printf ' %q' "${MP3_ARGS[@]}"
    printf ' %q\n' "$output"
    return 0
  fi

  echo "Repairing: $input -> $output"
  ffmpeg -y -i "$input" -af "$REPAIR_FILTER" "${MP3_ARGS[@]}" "$output"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --recordings)
        BATCH=true
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --force)
        FORCE=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        INPUT_PATHS+=("$@")
        break
        ;;
      -*)
        echo "Error: unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
      *)
        INPUT_PATHS+=("$1")
        shift
        ;;
    esac
  done
}

run_batch() {
  local recordings_root="${HOME}/Recordings"
  if [[ ! -d "$recordings_root" ]]; then
    echo "Error: recordings folder not found: $recordings_root" >&2
    exit 1
  fi

  local found=0
  while IFS= read -r -d '' caf; do
    found=1
    repair_one "$caf" || true
  done < <(find "$recordings_root" -type f -name 'system.caf' -print0)

  if [[ "$found" -eq 0 ]]; then
    echo "No system.caf files under $recordings_root"
  fi
}

main() {
  parse_args "$@"

  if [[ "$BATCH" == true ]]; then
    if [[ ${#INPUT_PATHS[@]} -gt 0 ]]; then
      echo "Error: do not pass file paths with --recordings" >&2
      exit 1
    fi
    require_ffmpeg
    run_batch
    exit 0
  fi

  if [[ ${#INPUT_PATHS[@]} -eq 0 ]]; then
    usage >&2
    exit 1
  fi

  require_ffmpeg

  local input="${INPUT_PATHS[0]}"
  local output=""
  if [[ ${#INPUT_PATHS[@]} -ge 2 ]]; then
    output="${INPUT_PATHS[1]}"
  fi
  if [[ ${#INPUT_PATHS[@]} -gt 2 ]]; then
    echo "Error: too many arguments" >&2
    usage >&2
    exit 1
  fi

  repair_one "$input" "$output"
}

main "$@"
