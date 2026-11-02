# Plan för Matchreferat

Senast uppdaterad 2026-11-02.

## Läget nu

- **1.0.2 (bygge 3)** är inskickad till Apple och väntar på granskning sedan 2026-11-01. Den ersatte 1.0.1, som drogs tillbaka. Grenen `main` är samma som `v1.0.2`.
- **1.0.3 (bygge 4)** är klar på grenen `v1.0.3`, pushad men inte ihopslagen med `main`. Den innehåller:
  - Innebandy: sport per lag och match, perioder (3 × 20), utvisningar med förvalda 2 min.
  - Straffknapp i fotboll.
  - Sportval på första sidan, och startsidan visar bara pågående match och Pågår nu för vald sport.
  - Inställningar: skärm tänd, vibration, sport vid start, live-server och om appen.
  - Ny appikon och ny första sida.
  - Live: valfritt fält `sport` i Firestore-reglerna och webbvisare för innebandy.

## Nästa steg

1. Vänta på Apples besked om 1.0.2. Släpp den själv med "Release This Version" när den godkänts.
2. Slå ihop `v1.0.3` med `main` när 1.0.2 är släppt.
3. Deploya de nya Firestore-reglerna och webbsidorna (`npm run deploy`) innan 1.0.3 skickas in, så att fältet `sport` tillåts.
4. Kör `tests/live-ongoing.mjs` mot de deployade reglerna.
5. Kontrollera ljust och mörkt läge och stor text på de nya innebandyskärmarna.
6. Uppdatera `appstore/METADATA.md` för 1.0.3: nyheter, undertitel, nyckelord (innebandy) och granskningsanteckningar.
7. Bygg och ladda upp med `scripts/archive.sh --upload`, och skicka in 1.0.3 för granskning.

## Öppna frågor

- **Licens för repot.** Repot är publikt men saknar en `LICENSE`-fil, vilket betyder att ingen får återanvända koden. Bestäm om det ska vara så, eller välj till exempel MIT.
- **Matchhistorik.** Appen visar i dag pågående match men ingen lista över tidigare matcher. Ska avslutade matcher sparas och gå att bläddra bland, och hur länge? Live-data på servern raderas inte automatiskt (ingen TTL, medvetet val), men lokalt i appen kan historiken leva vidare.
- **Radering på servern.** Ska gamla matcher på live-servern tas bort automatiskt efter en tid, eller räcker det att användaren tar bort dem själv?

## Att komma ihåg

- Lägg aldrig in kopplingslänken till M1SU:s eget Firebase-projekt i repot. Den finns bara i granskningsanteckningarna i App Store Connect.
- Bumpa `CURRENT_PROJECT_VERSION` i `project.yml` före varje uppladdning och kör `xcodegen generate`.
- Inga personuppgifter, lagnamn eller riktiga namn i ikoner eller skärmdumpar.
