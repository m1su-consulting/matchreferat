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
    phase: "secondHalf",
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
