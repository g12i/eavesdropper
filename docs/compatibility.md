# macOS / Xcode compatibility

| Host OS | Xcode for local GUI + build | Notes |
|---------|----------------------------|--------|
| macOS 14 (Sonoma) | **16.x** | Xcode 17+ / Xcode 27 GUI does not run on Sonoma. Use `scripts/install-xcode-sonoma.sh`. |
| macOS 15+ | 16.x or newer | Match team policy; TapScribe targets macOS 14.4+. |

`scripts/check-prerequisites.sh` fails on Sonoma when `xcode-select` points at Xcode 17+ or a path containing `Xcode-27`.

Unsigned local builds: omit `DEVELOPMENT_TEAM` and run `./scripts/build.sh` (sets `CODE_SIGNING_ALLOWED=NO`). For stable TCC prompts, use Apple Development signing (plan step 0.4). Keep `PRODUCT_BUNDLE_IDENTIFIER` at `com.tapscribe.app`.

**Disk:** `check-prerequisites.sh` requires **8 GB** free for runtime (override with `TAPSCRIBE_MIN_FREE_GB`). Product plan “40 GB” meant **first Xcode install + model**, not everyday recording.
