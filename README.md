# TapScribe (audio-in-the-middle)

Aplikacja w pasku menu dla macOS 14.4+ nagrywająca **dźwięk systemu** (process tap Core Audio) i po zatrzymaniu transkrybująca lokalnie przez WhisperKit (język polski).

## M1 workflow (local git only)

Repozytorium na M1 Pro to **tylko lokalny git** (bez remote). **Nie** używaj `git pull` / `git fetch`.

1. Agent Cursor commituje na **`main`** na tej samej maszynie.
2. Ty budujesz aplikację:

   ```bash
   cd ~/Projects/personal/audio-in-the-middle
   ./scripts/build.sh
   ```

3. Opcjonalnie: `git log -1 --oneline`

Szczegóły: [docs/workflow-m1.md](docs/workflow-m1.md).

## Gdzie są nagrania

Każda sesja to folder:

`~/Recordings/<YYYY-MM-DD_HH-mm-ss>/`

Pliki: **`system.caf`**, po transkrypcji **`transcript.txt`** i **`transcript.srt`**.

W menu: lista ostatnich nagrań (ikona + status), **Pokaż w Finderze** (ostatnia sesja lub `~/Recordings`).

## Dźwięk wyjściowy (nie BlackHole)

TapScribe **nie** pojawia się w **Ustawienia systemowe → Dźwięk → Wyjście**. Podczas nagrywania używa prywatnego urządzenia agregującego; odtwarzanie zostaje na głośnikach / słuchawkach.

## Uprawnienia (TCC)

Przy **Start nagrywania** (bez modelu Whisper):

1. Zgoda na **nagrywanie dźwięku systemu** → `system.caf`.

Transkrypcja **po Stop**, w tle. Przy **pierwszym uruchomieniu** aplikacja prosi o jednorazowe pobranie modelu Whisper (~1,5 GB). Nagrywanie działa od razu; bez modelu transkrypcja nie startuje (komunikat w menu).

Menu **Ustawienia → Model transkrypcji…** / **Pobierz ponownie model…**

Menu: **Ustawienia: dźwięk systemu…**

### Podpis i bundle ID

TCC pamięta **bundle ID + podpis**. Stały ID: `com.tapscribe.app`. Dla trwałych zgód: podpis **Apple Development** i `DEVELOPMENT_TEAM` przy `./scripts/build.sh`.

## Diagnostyka

```bash
APP=build/Build/Products/Debug/TapScribe.app/Contents/MacOS/TapScribe
"$APP" --probe-capture
```

## Miejsce na dysku

- **Na co dzień:** ~**8 GB** wolnego (`scripts/check-prerequisites.sh`).
- Jednorazowo Xcode: ~15–20 GB.

## Build

```bash
./scripts/check-prerequisites.sh
./scripts/build.sh
```
