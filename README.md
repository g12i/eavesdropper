# TapScribe (audio-in-the-middle)

Menu bar app for macOS 14.4+ that records **system audio** (Core Audio process tap) and optionally **microphone** on separate tracks, then transcribes locally with WhisperKit (Polish) **after** you stop recording.

## M1 workflow (local git only)

This tree on the M1 Pro uses **local-only git** (no remote). Do **not** run `git pull` / `git fetch` to update code.

1. Cursor private worker commits on **`main`** on the same machine.
2. You rebuild the app:

   ```bash
   cd ~/Projects/personal/audio-in-the-middle
   ./scripts/build.sh
   ```

3. Optional — see the last agent commit:

   ```bash
   git log -1 --oneline
   ```

Details: [docs/workflow-m1.md](docs/workflow-m1.md).

## Where recordings are saved

Each session is a folder:

`~/Recordings/<YYYY-MM-DD_HH-mm-ss>/`

Typical files: `system.caf` (always when capture succeeds), optional `mic.caf`, later `transcript.txt` and `transcript.srt`.

In the menu bar app use **Pokaż w Finderze** (last session) or **Otwórz folder nagrań…** (`~/Recordings`).

## Sound output (not BlackHole)

TapScribe does **not** install a virtual output device and does **not** appear in **System Settings → Sound → Output**. It uses a **private aggregate device** only while recording; playback stays on your normal output (built‑in speakers, headphones, etc.). This is intentional — no BlackHole and no Multi‑Output Device.

## Permissions (TCC)

On **Start nagrywania**, TapScribe ( **no Whisper model required** ):

1. Requests **system audio recording** consent and starts the process tap → `system.caf`.
2. Requests **microphone** access only if **Nagrywaj mikrofon** is enabled → optional `mic.caf`.

Transcription runs **after Stop**, in the background. If the Whisper model is missing, it is **downloaded then**; recording is not blocked.

Use menu items **Ustawienia: dźwięk systemu…** and **Ustawienia: mikrofon…** if access was denied.

### Stable bundle ID and signing

TCC remembers grants per **bundle identifier + code signature**.

- Bundle ID is fixed: `com.tapscribe.app` (`project.yml` / `PRODUCT_BUNDLE_IDENTIFIER`).
- **Unsigned / adhoc** debug builds (`CODE_SIGNING_ALLOWED=NO`) often **do not show prompts** or **reset permissions every build**.
- For persistent TCC: sign with **Apple Development** (Personal Team), set `DEVELOPMENT_TEAM` in the environment, and run `./scripts/build.sh` without disabling signing. Confirm with:

  ```bash
  codesign -dv --verbose=2 build/Build/Products/Debug/TapScribe.app 2>&1 | grep Authority
  ```

Reset permissions if needed:

```bash
tccutil reset All com.tapscribe.app
```

## Diagnostics (no menu)

After building:

```bash
APP=build/Build/Products/Debug/TapScribe.app/Contents/MacOS/TapScribe
"$APP" --probe-capture          # mic + system tap probe
"$APP" --probe-capture --no-mic # system only
```

Logs TCC state, signing summary, and a short tap session to `/tmp`.

## Disk space

- **Runtime:** ~**8 GB** free recommended (Whisper model ~1.5 GB + headroom). Checked by `scripts/check-prerequisites.sh`.
- **One-time Xcode install:** plan ~15–20 GB; the old “40 GB” figure in the product plan was for **first-time Xcode + model**, not daily use.

## Build

```bash
./scripts/check-prerequisites.sh
./scripts/build.sh
```
