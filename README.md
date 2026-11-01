# Matchreferat

iOS-app (SwiftUI) för föräldrar som vill referera ungdomsfotbollsmatcher live när matchen inte sänds, i stället för att skriva i Messenger.

- Lag med trupp, spelform (5–11 mot), antal halvlekar och minuter.
- Ny match: välj lag, motståndare och hemma/borta.
- Logga mål, skott, hörnor, frisparkar, kort och byten med stora knappar, och ångra direkt.
- Tidslinje och färdigt referat att kopiera eller dela.
- Livelänk via Firebase: andra följer matchen på en webbsida som uppdateras i realtid. Bara förnamn och tröjnummer lämnar telefonen.

## Bygga

Kräver Xcode och [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open Matchreferat.xcodeproj
```

Projektet genereras från `project.yml`, så ändra inställningar där och kör `xcodegen generate` igen.

## Livelänk

Appen har ingen inbyggd server och inga tredjepartsbibliotek. Livelänken använder en **live-server** som användaren kopplar själv: ett eget gratis Firebase-projekt, eller en kopplingslänk från någon som har ett. Appen loggar in anonymt och skriver matchen via Firebase REST-API:erna.

- Guide för föräldrar: [docs/EGEN-SERVER.md](docs/EGEN-SERVER.md) (även på https://matchreferat.web.app/egen-server).
- Kopplingslänkar skapas på https://matchreferat.web.app/koppla. Formatet är `matchreferat://koppla?p=<projectId>&k=<webApiKey>&n=<namn>`.
- Livelänkar har servern i fragmentet: `https://matchreferat.web.app/m/<id>#p=<projectId>&k=<apiKey>`.
- Webbsidor och regler för M1SU:s eget projekt: se [FIREBASE.md](FIREBASE.md).

## Struktur

- `Sources/`: appen (SwiftUI, `@Observable`-store, sparas som JSON).
- `public/`: webbsidan för livelänken (Firebase Hosting).
- `firestore.rules`, `tests/`: säkerhetsregler och tester.
- `branding/`: logga och appikon.

Exempeldata i appen har påhittade spelare.

## App Store

Metadata, granskningsanteckningar och skärmdumpar ligger i `appstore/`. Bygg och ladda upp:

```bash
scripts/archive.sh            # bygger Release-arkiv och öppnar Xcode Organizer
scripts/archive.sh --upload   # bygger och laddar upp direkt till App Store Connect
```
