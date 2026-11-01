# Skapa en egen live-server

> Matchreferat · tar cirka 15 minuter · gratis

Livelänken i Matchreferat behöver en plats där matchen kan lagras medan andra tittar. Den platsen är en gratis databas hos Google Firebase som **du** äger. Ingen annan kan läsa dina matcher utan länken, och allt raderas automatiskt.

Du behöver ett Google-konto. Gratisnivån (Spark) räcker gott, och du behöver inte ange något kort.

## 1. Skapa ett Firebase-projekt

1. Gå till [console.firebase.google.com](https://console.firebase.google.com/) och logga in med ditt Google-konto.
1. Klicka **Skapa ett projekt** (Create a project), ge det ett namn, till exempel _mitt-lag-live_.
1. Google Analytics behövs inte – stäng av det. Klicka **Skapa**.

## 2. Slå på anonym inloggning

1. I vänstermenyn: **Security → Authentication**. Klicka **Get started** om knappen visas.
1. Fliken **Sign-in method** → **Anonymous** → slå på **Enable** → **Save**.

> Ingen behöver skapa konto. Den anonyma inloggningen gör bara att endast din telefon kan ändra din match.

## 3. Skapa databasen

1. I vänstermenyn: **Databases & Storage → Firestore** → **Create database**.
1. Välj en plats i Europa, till exempel **europe-north1 (Finland)** eller **eur3**. Den går inte att ändra senare.
1. Välj **Start in production mode** → **Create**.

## 4. Lägg in säkerhetsreglerna

1. I Firestore, öppna fliken **Rules**.
1. Ta bort allt som står där och klistra in reglerna nedan. Klicka **Publish**.

Se [firestore.rules](../firestore.rules) – kopiera hela filen.

> Reglerna gör att vem som helst med en livelänk kan läsa just den matchen, men ingen kan lista matcherna och bara den som skapade matchen kan ändra den. Alla som har kopplat appen till servern (med kopplingslänken) ser dessutom en lista "Pågår nu" med lagnamn, ställning och matchminut för matcher som delas live. Spelare och händelser syns bara på livesidan.
>
> **Har du redan en server?** Klistra in reglerna igen när du uppdaterar appen till 1.0.2, annars visas inte "Pågår nu". Livedelningen fungerar ändå med de gamla reglerna.

## 5. Automatisk radering (rekommenderas)

1. I Firestore, öppna fliken **Time-to-live (TTL)** → **Create policy**.
1. Collection group: `matches`, Timestamp field: `expireAt` → **Create**.
1. Skapa en policy till med Collection group: `ongoing`, Timestamp field: `expireAt`.

> Då raderas matcher automatiskt sju dagar efter senaste uppdateringen. Matchen raderas också direkt när du stänger av "Dela live".

## 6. Hämta uppgifterna för appen

1. Klicka på kugghjulet → **Project settings**.
1. Under **Your apps**, klicka på webbikonen **</>** för att lägga till en webbapp. Ge den valfritt namn. Firebase Hosting behövs inte.
1. Du ser nu en kodruta med `firebaseConfig`. Där står `apiKey` (börjar med _AIza_) och `projectId`. Det är de två du behöver.

> API-nyckeln för webben är inte hemlig – den identifierar bara projektet. Det är säkerhetsreglerna som skyddar datan.

## 7. Koppla appen

1. Gå till [matchreferat.web.app/koppla](https://matchreferat.web.app/koppla), fyll i projekt-id och API-nyckel och klicka **Skapa kopplingslänk**.
1. Öppna länken på telefonen (eller skanna QR-koden) och tryck **Öppna i Matchreferat**. Appen testar anslutningen och kopplas.
1. Klart! Nu fungerar **Dela live** på matchsidan. Du kan dela kopplingslänken med andra föräldrar du litar på.

## Om något inte fungerar

Gå till **Inställningar → Live-server → Testa anslutningen** i appen. Den talar om vad som saknas: anonym inloggning, databasen eller säkerhetsreglerna.

> [Support](https://matchreferat.web.app/support) · [Integritetspolicy](https://matchreferat.web.app/integritet)
