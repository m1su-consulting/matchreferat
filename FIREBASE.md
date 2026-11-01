# Livelänk med Firebase

Appen fungerar helt utan Firebase. Live-delningen aktiveras när du har gjort stegen nedan.

## Status (31 oktober 2026)

Projektet `matchreferat` är uppsatt: anonym inloggning, Firestore, iOS-appen och Hosting finns, och regler och webbsida är publicerade. Länkarna ser ut så här: `https://matchreferat.web.app/m/<24 tecken>`.

Från version 1.0.1 innehåller appen inget Firebase-SDK och ingen inbyggd server. Användaren kopplar en live-server med en kopplingslänk (se [docs/EGEN-SERVER.md](docs/EGEN-SERVER.md)). Projektet `matchreferat` är M1SU:s egen server, och dess kopplingslänk delas bara med personer Mikael litar på. Webbsidorna (livesida, `/koppla`, `/egen-server`, integritetspolicy) ligger på Hosting i det här projektet och fungerar för alla servrar.

## Vad som delas

- Lagnamn, hemma/borta, resultat, klocka och statistik.
- Händelser med spelare som **förnamn + tröjnummer**, till exempel "Mål! Selma (10), assist Wilma (8)". Efternamn lämnar aldrig telefonen.
- Motståndaren är bara ett lagnamn. Inga uppgifter om deras spelare sparas eller visas.
- Länken innehåller en slumpkod på 24 tecken. Den går inte att gissa, och ingen kan lista matcher.
- Matchen raderas när du stänger av "Dela live". Annars slutar länken fungera 7 dagar efter senaste uppdateringen.

## Engångsuppsättning

1. **Skapa projektet.** Gå till https://console.firebase.google.com, välj *Lägg till projekt* och döp det till exempel till `matchreferat`. Google Analytics behövs inte, så stäng av det.
2. **Slå på anonym inloggning.** Gå till *Build → Authentication → Kom igång → Sign-in method → Anonymous → Aktivera*.
3. **Skapa databasen.** Gå till *Build → Firestore Database → Skapa databas*. Välj region `eur3 (europe-west)` eller `europe-north1`, och välj produktionsläge.
4. **Radera gamla matcher automatiskt** (rekommenderas). Gå till *Firestore → TTL → Skapa policy*, med samlingsgrupp `matches` och fält `expireAt`. Om TTL inte är tillgängligt i ditt prisplan döljer webbsidan ändå utgångna matcher, och appen raderar matchen när du stänger av live-delningen.
5. **Lägg till en webbapp** (kugghjulet → Projektinställningar → Lägg till app → Webb) för att få `apiKey` och `projectId` till kopplingslänken. Någon GoogleService-Info.plist behövs inte längre.
6. **Aktivera hosting.** Gå till *Build → Hosting → Kom igång*. Du kan klicka förbi stegen, eftersom de redan är gjorda i det här projektet.
7. **Logga in och koppla projektet** i Terminal:
   ```bash
   cd ~/Developer/matchreferat
   npx firebase login
   npx firebase use --add
   ```
   Välj ditt projekt och kalla det `default`.
8. **Publicera regler och webbsida:**
   ```bash
   npm run deploy
   ```
9. **Bygg om appen**, så att plist-filen kommer med:
   ```bash
   xcodegen generate
   ```
   Kör sedan appen från Xcode (⌘R). Under *Dela live* på Match-fliken får du länken `https://<projekt-id>.web.app/m/<kod>` och en QR-kod.

## Lokalt test med emulatorer (för utveckling)

Emulatorerna behöver Java 21 eller senare. Homebrews `openjdk@21` går inte att installera förrän Command Line Tools stöder macOS 27. Installera i stället Temurin 21 från https://adoptium.net.

```bash
npm run test:rules   # regeltester: listning nekas, andra användare kan inte skriva
npm run emulators    # Auth 9099, Firestore 8080, webbsida http://127.0.0.1:5002
```

Emulatorerna används bara för regeltesterna. Appen pratar alltid med en riktig live-server.

Webbsidan med exempeldata, utan backend: `public/index.html?demo=1`.

## Tester mot det riktiga projektet

```bash
node tests/listen.mjs <matchId> 30     # lyssnar som webbsidan och skriver ut varje uppdatering
node tests/other-user.mjs <matchId>    # en annan anonym användare får inte ändra, radera eller lista
```
