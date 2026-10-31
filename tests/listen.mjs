// Listens to one live match the same way the web page does and prints each update.
// Usage: node tests/listen.mjs <matchId> [seconds]
import { initializeApp } from "firebase/app";
import { doc, getFirestore, onSnapshot } from "firebase/firestore";

const [matchId, seconds = "30"] = process.argv.slice(2);
const config = await (await fetch("https://matchreferat.web.app/__/firebase/init.json")).json();
const db = getFirestore(initializeApp(config));
const start = Date.now();

onSnapshot(doc(db, "matches", matchId), (snap) => {
  const d = snap.data();
  if (!d) return console.log("no document");
  const last = d.events.at(-1);
  console.log(`+${((Date.now() - start) / 1000).toFixed(1)}s ${d.homeScore}–${d.awayScore} events=${d.events.length} last="${last.m} ${last.text}" stats="${d.stats}"`);
}, (err) => console.log("error", err.code));

setTimeout(() => process.exit(0), Number(seconds) * 1000);
