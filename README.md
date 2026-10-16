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

W menu paska systemowego (natywne **NSMenu**, jak Rectangle/Cursor): **Start nagrywania**, lista ostatnich sesji (klik → folder w Finderze), Ustawienia. Nagrania krótsze niż 60 s nie są transkrybowane (status „Za krótkie”).

Podczas nagrywania ikona w pasku zmienia się na czerwoną, a czas nagrania widać w nagłówku menu. Ikona ma stałą szerokość — macOS ukrywa elementy paska, które przestają się mieścić obok notcha. Transkrypcje idą po kolei w tle; nowe nagranie nie przerywa transkrypcji poprzedniego („W kolejce” / „Transkrypcja…”).

## Dźwięk wyjściowy (nie BlackHole)

TapScribe **nie** pojawia się w **Ustawienia systemowe → Dźwięk → Wyjście**. Podczas nagrywania używa prywatnego urządzenia agregującego; odtwarzanie zostaje na głośnikach / słuchawkach.

## Uprawnienia (TCC)

Przy **Start nagrywania** (bez modelu Whisper):

1. Zgoda na **nagrywanie dźwięku systemu** → `system.caf`.

Transkrypcja **po Stop**, w tle. Przy **pierwszym uruchomieniu** aplikacja proponuje jednorazowe pobranie modelu Whisper (~1,5 GB). Nagrywanie działa od razu, także bez modelu — **Start nagrywania** jest wyłączony tylko przy braku zgody na dźwięk systemu. Bez modelu menu pokazuje „Wymaga konfiguracji → Pobierz model Whisper”, a nagrania po Stop mają status „Brak modelu” (bez transkryptu).

Menu **Wymaga konfiguracji** pokazuje tylko to, czego brakuje: **Zezwól na nagrywanie dźwięku systemu…** (otwiera Ustawienia systemowe) i/lub **Pobierz model transkrypcji (opcjonalnie)…** (w trakcie pobierania: postęp).

Gdy wszystko działa, menu nie pokazuje żadnych przycisków konfiguracji ani naprawy: tylko Start, lista nagrań, **Ustawienia** (**Otwórz folder nagrań**, **Uruchamiaj przy logowaniu**) i Zakończ.

**Uruchamiaj przy logowaniu** rejestruje aplikację przez `SMAppService` (to samo co Ustawienia systemowe → Ogólne → Rzeczy otwierane podczas logowania; ptaszek pokazuje faktyczny stan). Rejestrowana jest aplikacja z miejsca, z którego działa (np. `build/Build/Products/Debug/TapScribe.app`) — po przeniesieniu aplikacji włącz opcję ponownie. Jeśli macOS wymaga zatwierdzenia, pozycja ma znak „–” i otwierają się Ustawienia systemowe. Awaryjne **Pobierz ponownie model…** (z potwierdzeniem; usuwa obecny model) jest schowane w **Ustawienia → Zaawansowane**.

Wielokropek „…” jest tylko przy poleceniach, które otwierają okno lub Ustawienia systemowe (zgodnie z macOS HIG); w statusach („Transkrypcja…”) oznacza trwającą czynność.

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
