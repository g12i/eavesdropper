# Eavesdropper

A macOS 14.4+ menu bar app that records **system audio** (process tap via Core Audio) and transcribes it on-demand using WhisperKit with local language models.

## What It Does

- **Records system audio** to a session folder when you click "Start Recording"
- **On-demand transcription** - choose language (Polish/English/Auto) in a dialog after recording stops
- **Manual transcription queue** - transcriptions run one at a time, in FIFO order
- **No automatic transcription** - you control when to transcribe each recording
- **Supports multiple languages** via language selector (auto-detect available)
- **Optional launch at login** (via macOS System Settings)

## Requirements

- **macOS 14.4+** (Sonoma or later)
- **Apple Silicon** (M1, M2, M3, etc.) — Intel support untested
- **~1.5 GB free space** for the Whisper model (downloaded on first use)
- **System audio recording permission** (granted on first use)

## How to Build

```bash
./scripts/build.sh
```

Builds to `build/Build/Products/Debug/Eavesdropper.app`.

Optional prerequisites check:
```bash
./scripts/check-prerequisites.sh
```

## Recordings Location

Each recording session is a folder:

```
~/Recordings/<YYYY-MM-DD_HH-mm-ss>/
```

Files per session:
- **`system.caf`** - raw audio
- **`transcript.txt`** - transcribed text (after transcription)
- **`transcript.srt`** - SRT subtitle file (after transcription)
- **`transcription.json`** - metadata (language, model, timestamps)

## How to Use

1. **Start Recording** - appears in the menu bar
   - First use: grant system audio permission (one-time TCC dialog)
   - First transcription: download model (~1.5 GB) on demand in the transcription dialog

2. **Stop Recording** - session appears in the menu with "No transcript"

3. **Open Transcription Dialog** - click the session row in the menu
   - Choose language: Polish / English / Auto
   - Warning if recording is <60s (but you can still transcribe)
   - Click **Transcribe** to start
   - Watch progress bar or close the window (transcription continues in background)

4. **Alternate menu item** - Option-click a session row to open it in Finder

5. **Settings**:
   - Open Recordings Folder
   - Launch at Login
   - Re-download Model (Advanced)

6. **Quit** - stops active recording and transcription

## Menu Bar Behavior

The status icon changes:
- **Waveform (light)** - idle
- **Red circle** - recording in progress
- Time elapsed shown in menu header during recording

Session rows show status:
- **Recording…** - currently recording
- **No transcript** - idle, no transcript yet
- **Queued** - waiting for transcription
- **Transcribing…** - currently transcribing (with %)
- **Error** - transcription failed
- **Model missing** - model not downloaded

## Permissions (TCC)

- **System audio recording** - granted once, stored by bundle ID + signature
- Bundle ID: `com.eavesdropper.app`
- To retain permissions after moving the app, re-enable "Launch at Login"

## Model Download

First transcription triggers a one-time download of the Whisper model (~1.5 GB).
- Download UI in the transcription dialog shows progress
- Recording works without the model
- Transcription is unavailable until model is ready

## Disk Space

- **Typical:** ~8 GB free space (for model + recordings)
- **Build:** Xcode requires ~15–20 GB one-time

## Architecture

- **Single transcriber worker** - transcriptions run sequentially (no parallelism)
- **Per-session state machine** - idle → queued → loadingModel → transcribing → done
- **Language persistence** - last chosen language saved to UserDefaults
- **Atomic file writes** - prevents partial transcripts on error

## Troubleshooting

Diagnose audio capture:
```bash
APP=build/Build/Products/Debug/Eavesdropper.app/Contents/MacOS/Eavesdropper
"$APP" --probe-capture
```

Transcribe via CLI (for testing):
```bash
"$APP" --transcribe /path/to/audio.caf --language pl
"$APP" --transcribe /path/to/audio.caf --language en
"$APP" --transcribe /path/to/audio.caf --language auto
```

## Development Notes

- No network after model download - transcription is fully local
- Recordings shorter than 60s show a dialog warning (but can still be transcribed)
- Inactive app uses `.accessory` activation policy (no dock icon)
- Dialog shows window when transcribing; close it to continue in background
