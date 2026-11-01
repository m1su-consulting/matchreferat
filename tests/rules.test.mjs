// Run with `npm run test:rules` (starts the Firestore emulator; needs Java 21+).
import { after, before, beforeEach, test } from "node:test";
import { readFileSync } from "node:fs";
import { assertFails, assertSucceeds, initializeTestEnvironment } from "@firebase/rules-unit-testing";
import { collection, deleteDoc, doc, getDoc, getDocs, serverTimestamp, setDoc, Timestamp, updateDoc } from "firebase/firestore";

const ID = "AbCdEfGhIjKlMnOpQrStUv12";
let env;

function match(ownerUid, extra = {}) {
  return {
    v: 1,
    ownerUid,
    ourTeam: "Ditt lag",
    opponent: "Ekbacka IK",
    isHome: true,
    homeName: "Ditt lag",
    awayName: "Ekbacka IK",
    homeScore: 2,
    awayScore: 1,
    phase: "playing",
    period: 2,
    periods: 2,
    running: true,
    startedAt: Timestamp.now(),
    accumulated: 0,
    halfLength: 25,
    periodText: "2:a halvlek",
    clockLabel: "34'",
    stats: "Skott 3–3 · På mål 3–2 · Hörnor 2–1",
    events: [{ m: "9'", type: "goal", side: "us", text: "Mål! Selma (10), assist Wilma (8)", team: "Ditt lag" }],
    updatedAt: serverTimestamp(),
    expireAt: Timestamp.fromMillis(Date.now() + 7 * 864e5),
    ...extra,
  };
}

const db = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();

async function seed() {
  await assertSucceeds(setDoc(doc(db("alice"), "matches", ID), match("alice")));
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-matchreferat",
    firestore: { rules: readFileSync("firestore.rules", "utf8"), host: "127.0.0.1", port: 8080 },
  });
});
after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

test("ägaren kan skapa en match", seed);

test("man kan inte skapa en match åt någon annan", async () => {
  await assertFails(setDoc(doc(db("alice"), "matches", ID), match("bob")));
});

test("oinloggad kan inte skapa", async () => {
  await assertFails(setDoc(doc(db(null), "matches", ID), match("alice")));
});

test("kort eller ogiltigt id nekas", async () => {
  await assertFails(setDoc(doc(db("alice"), "matches", "kort"), match("alice")));
  await assertFails(setDoc(doc(db("alice"), "matches", "AbCdEfGhIjKlMnOpQrStUv1-"), match("alice")));
});

test("vem som helst med id:t kan läsa matchen", async () => {
  await seed();
  await assertSucceeds(getDoc(doc(db(null), "matches", ID)));
  await assertSucceeds(getDoc(doc(db("bob"), "matches", ID)));
});

test("ingen kan lista matcher", async () => {
  await seed();
  await assertFails(getDocs(collection(db(null), "matches")));
  await assertFails(getDocs(collection(db("bob"), "matches")));
  await assertFails(getDocs(collection(db("alice"), "matches")));
});

test("en annan användare kan inte ändra eller radera", async () => {
  await seed();
  await assertFails(setDoc(doc(db("bob"), "matches", ID), match("bob")));
  await assertFails(updateDoc(doc(db("bob"), "matches", ID), { homeScore: 9, updatedAt: serverTimestamp() }));
  await assertFails(deleteDoc(doc(db("bob"), "matches", ID)));
  await assertFails(deleteDoc(doc(db(null), "matches", ID)));
});

test("ägaren kan uppdatera och radera", async () => {
  await seed();
  await assertSucceeds(setDoc(doc(db("alice"), "matches", ID), match("alice", { homeScore: 3 })));
  await assertSucceeds(deleteDoc(doc(db("alice"), "matches", ID)));
});

test("ägaren kan inte byta ägare", async () => {
  await seed();
  await assertFails(setDoc(doc(db("alice"), "matches", ID), match("bob")));
});

test("okända fält, fel typer och för lång livslängd nekas", async () => {
  await assertFails(setDoc(doc(db("alice"), "matches", ID), match("alice", { lastName: "Lund" })));
  await assertFails(setDoc(doc(db("alice"), "matches", ID), match("alice", { homeScore: "2" })));
  await assertFails(setDoc(doc(db("alice"), "matches", ID), match("alice", { ourTeam: "x".repeat(61) })));
  await assertFails(setDoc(doc(db("alice"), "matches", ID), match("alice", { expireAt: Timestamp.fromMillis(Date.now() + 30 * 864e5) })));
  await assertFails(setDoc(doc(db("alice"), "matches", ID), match("alice", { events: Array(201).fill({}) })));
});

// Ongoing-match summaries: listable by signed-in users, writable only by the owner.

function ongoing(ownerUid, extra = {}) {
  return {
    v: 1,
    ownerUid,
    homeName: "Ditt lag",
    awayName: "Ekbacka IK",
    homeScore: 2,
    awayScore: 1,
    phase: "playing",
    periodText: "2:a halvlek",
    clockLabel: "34'",
    updatedAt: serverTimestamp(),
    expireAt: Timestamp.fromMillis(Date.now() + 7 * 864e5),
    ...extra,
  };
}

async function seedOngoing() {
  await assertSucceeds(setDoc(doc(db("alice"), "ongoing", ID), ongoing("alice")));
}

test("ägaren kan lägga upp en pågående match", seedOngoing);

test("inloggade kan lista pågående matcher, oinloggade inte", async () => {
  await seedOngoing();
  await assertSucceeds(getDocs(collection(db("bob"), "ongoing")));
  await assertSucceeds(getDoc(doc(db("bob"), "ongoing", ID)));
  await assertFails(getDocs(collection(db(null), "ongoing")));
});

test("matcher går fortfarande inte att lista när ongoing finns", async () => {
  await seed();
  await seedOngoing();
  await assertFails(getDocs(collection(db("bob"), "matches")));
});

test("bara ägaren kan ändra eller radera en pågående match", async () => {
  await seedOngoing();
  await assertFails(setDoc(doc(db("bob"), "ongoing", ID), ongoing("bob")));
  await assertFails(updateDoc(doc(db("bob"), "ongoing", ID), { homeScore: 9, updatedAt: serverTimestamp() }));
  await assertFails(deleteDoc(doc(db("bob"), "ongoing", ID)));
  await assertSucceeds(setDoc(doc(db("alice"), "ongoing", ID), ongoing("alice", { homeScore: 3 })));
  await assertSucceeds(deleteDoc(doc(db("alice"), "ongoing", ID)));
});

test("ägaren kan radera en sammanfattning som redan är borta", async () => {
  await assertSucceeds(deleteDoc(doc(db("alice"), "ongoing", ID)));
  await assertFails(deleteDoc(doc(db(null), "ongoing", ID)));
});

test("pågående match: spelare, händelser, avslutad match och fel fält nekas", async () => {
  await assertFails(setDoc(doc(db("alice"), "ongoing", ID), ongoing("alice", { events: [] })));
  await assertFails(setDoc(doc(db("alice"), "ongoing", ID), ongoing("alice", { players: ["Selma"] })));
  await assertFails(setDoc(doc(db("alice"), "ongoing", ID), ongoing("alice", { phase: "finished" })));
  await assertFails(setDoc(doc(db("alice"), "ongoing", ID), ongoing("alice", { homeScore: "2" })));
  await assertFails(setDoc(doc(db("alice"), "ongoing", ID), ongoing("alice", { homeName: "x".repeat(61) })));
  await assertFails(setDoc(doc(db("alice"), "ongoing", ID), ongoing("alice", { expireAt: Timestamp.fromMillis(Date.now() + 30 * 864e5) })));
  await assertFails(setDoc(doc(db("alice"), "ongoing", "kort"), ongoing("alice")));
});

// Sport, added in 1.0.3: optional so 1.0.2 apps (which never send it) keep working.

test("innebandymatch med sport och perioder godkänns, fotboll utan sport som förut", async () => {
  const floorball = { sport: "floorball", periods: 3, period: 2, halfLength: 15, periodText: "2:a period",
    stats: "Skott 3–3 · På mål 3–2 · Utvisningar 2",
    events: [{ m: "9'", type: "suspension", side: "us", text: "Utvisning 2 min – Lova (5)", team: "Ditt lag" },
             { m: "19'", type: "goal", side: "us", text: "Straffmål! Saga (10)", team: "Ditt lag" }] };
  await assertSucceeds(setDoc(doc(db("alice"), "matches", ID), match("alice", floorball)));
  await assertSucceeds(setDoc(doc(db("alice"), "ongoing", ID), ongoing("alice", { sport: "floorball", periodText: "2:a period" })));
  await assertSucceeds(setDoc(doc(db("alice"), "matches", ID), match("alice", { sport: "football" })));
  await assertSucceeds(setDoc(doc(db("alice"), "matches", ID), match("alice")));
  await assertSucceeds(setDoc(doc(db("alice"), "ongoing", ID), ongoing("alice")));
});

test("okänd sport eller fel typ nekas", async () => {
  await assertFails(setDoc(doc(db("alice"), "matches", ID), match("alice", { sport: "tennis" })));
  await assertFails(setDoc(doc(db("alice"), "matches", ID), match("alice", { sport: 1 })));
  await assertFails(setDoc(doc(db("alice"), "ongoing", ID), ongoing("alice", { sport: "handboll" })));
});
