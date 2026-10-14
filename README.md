# TapScribe (audio-in-the-middle)

Menu bar app for macOS 14.4+ that records **system audio** (Core Audio process tap) and **microphone** on separate tracks, then transcribes locally with WhisperKit (Polish).

## Sound output (not BlackHole)

TapScribe does **not** install a virtual output device and does **not** appear in **System Settings → Sound → Output**. It uses a **private aggregate device** only while recording; playback stays on your normal output (built‑in speakers, headphones, etc.). This is intentional — no BlackHole and no Multi‑Output Device.

## Permissions (TCC)

On **Start nagrywania**, TapScribe:

1. Requests **microphone** access (if enabled).
2. Requests **system audio recording** consent, then starts the process tap.

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
