# M1 — lokalne repo (bez remote)

Projekt `~/Projects/personal/audio-in-the-middle` ma **tylko lokalny git** na Macu M1 Pro. **Nie ma** `git remote` — **nie używaj** `git pull`, `git fetch` ani `git push`, żeby „zsynchronizować” kod.

## Jak trafiają zmiany

1. Agent Cursor (private worker) edytuje pliki i robi **`git commit` na `main`** na tej samej maszynie.
2. Ty po zakończeniu pracy agenta uruchamiasz wyłącznie:

   ```bash
   cd ~/Projects/personal/audio-in-the-middle
   ./scripts/build.sh
   ```

3. Opcjonalnie sprawdź ostatni commit agenta:

   ```bash
   git log -1 --oneline
   ```

## Czego nie robić

- Nie klonuj repo z GitHuba na M1 w ramach tego projektu (ścieżka robocza jest jedna).
- Nie oczekuj synchronizacji między M4 a M1 przez git — każda maszyna ma własną kopię, jeśli istnieje.
