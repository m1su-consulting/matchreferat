// Checks the deployed rules for `matches` and `ongoing` against the real project, with two
// temporary anonymous users. Everything it creates (documents and users) is deleted again.
// Usage: node tests/live-ongoing.mjs
const { apiKey, projectId } = await (await fetch("https://matchreferat.web.app/__/firebase/init.json")).json();
const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
const name = (path) => `projects/${projectId}/databases/(default)/documents/${path}`;
const id = Array.from(crypto.getRandomValues(new Uint8Array(24)), (b) => "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"[b % 62]).join("");

async function call(url, { method = "POST", body, token } = {}) {
  const headers = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  const response = await fetch(url, { method, headers, body: body && JSON.stringify(body) });
  return { status: response.status, json: await response.json().catch(() => ({})) };
}

function value(v) {
  if (typeof v === "boolean") return { booleanValue: v };
  if (Number.isInteger(v)) return { integerValue: String(v) };
  if (typeof v === "number") return { doubleValue: v };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(value) } };
  return { stringValue: v };
}
const fields = (data) => Object.fromEntries(Object.entries(data).map(([k, v]) => [k, value(v)]));
const expireAt = () => new Date(Date.now() + 7 * 864e5);

const match = (owner) => ({
  v: 1, ownerUid: owner, ourTeam: "Testlag", opponent: "Motståndare", isHome: true, homeName: "Testlag",
  awayName: "Motståndare", homeScore: 1, awayScore: 0, phase: "playing", running: false, accumulated: 0.5,
  halfLength: 25, period: 1, periods: 2, periodText: "1:a halvlek", clockLabel: "5'", stats: "", events: [],
  expireAt: expireAt(),
});
const ongoing = (owner, extra = {}) => ({
  v: 1, ownerUid: owner, homeName: "Testlag", awayName: "Motståndare", homeScore: 1, awayScore: 0,
  phase: "playing", periodText: "1:a halvlek", clockLabel: "5'", expireAt: expireAt(), ...extra,
});

/// Writes documents in one commit with `updatedAt` set to the server time, like the app.
const commit = (token, docs) => call(`${base}:commit`, {
  token,
  body: { writes: docs.map(([path, data]) => ({
    update: { name: name(path), fields: fields(data) },
    updateTransforms: [{ fieldPath: "updatedAt", setToServerValue: "REQUEST_TIME" }],
  })) },
});

const signUp = async () => (await call(`https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${apiKey}`, { body: { returnSecureToken: true } })).json;
const alice = await signUp();
const bob = await signUp();
console.log("temporary users created:", Boolean(alice.idToken && bob.idToken));

let failures = 0;
async function check(label, expected, run) {
  const { status, json } = await run();
  const ok = status === expected;
  if (!ok) failures++;
  console.log(`${ok ? "OK  " : "FAIL"} ${label}: ${status} (expected ${expected})`);
  return json;
}

// 1.0.1 flow: matches only.
await check("1.0.1: owner creates a match alone", 200, () => commit(alice.idToken, [[`matches/${id}`, match(alice.localId)]]));
await check("anyone reads the match by id (no sign-in)", 200, () => call(`${base}/matches/${id}`, { method: "GET" }));
await check("other user reads the match by id", 200, () => call(`${base}/matches/${id}`, { method: "GET", token: bob.idToken }));
await check("other user cannot list matches", 403, () => call(`${base}/matches`, { method: "GET", token: bob.idToken }));
await check("owner cannot list matches", 403, () => call(`${base}/matches`, { method: "GET", token: alice.idToken }));
await check("other user cannot delete the match", 403, () => call(`${base}/matches/${id}`, { method: "DELETE", token: bob.idToken }));

// 1.0.2 flow: match and summary in one commit.
await check("1.0.2: owner writes match + ongoing", 200, () => commit(alice.idToken, [[`matches/${id}`, match(alice.localId)], [`ongoing/${id}`, ongoing(alice.localId)]]));
const listed = await check("other user lists ongoing", 200, () => call(`${base}/ongoing?pageSize=100`, { method: "GET", token: bob.idToken }));
const found = (listed.documents ?? []).some((d) => d.name.endsWith(`/ongoing/${id}`));
if (!found) failures++;
console.log(`${found ? "OK  " : "FAIL"} the test match is in the list`);
await check("other user reads ongoing by id", 200, () => call(`${base}/ongoing/${id}`, { method: "GET", token: bob.idToken }));
await check("no sign-in cannot list ongoing", 403, () => call(`${base}/ongoing`, { method: "GET" }));
await check("other user cannot overwrite ongoing", 403, () => commit(bob.idToken, [[`ongoing/${id}`, ongoing(bob.localId, { homeScore: 9 })]]));
await check("other user cannot delete ongoing", 403, () => call(`${base}/ongoing/${id}`, { method: "DELETE", token: bob.idToken }));
await check("players in ongoing are rejected", 403, () => commit(alice.idToken, [[`ongoing/${id}`, ongoing(alice.localId, { players: ["Selma"] })]]));
await check("finished phase in ongoing is rejected", 403, () => commit(alice.idToken, [[`ongoing/${id}`, ongoing(alice.localId, { phase: "finished" })]]));
await check("too long team name is rejected", 403, () => commit(alice.idToken, [[`ongoing/${id}`, ongoing(alice.localId, { homeName: "x".repeat(61) })]]));
await check("owner updates ongoing", 200, () => commit(alice.idToken, [[`ongoing/${id}`, ongoing(alice.localId, { homeScore: 2 })]]));

// Clean-up, which also checks the owner's deletes.
await check("owner deletes ongoing", 200, () => call(`${base}/ongoing/${id}`, { method: "DELETE", token: alice.idToken }));
await check("owner deletes ongoing that is already gone", 200, () => call(`${base}/ongoing/${id}`, { method: "DELETE", token: alice.idToken }));
await check("owner deletes the match", 200, () => call(`${base}/matches/${id}`, { method: "DELETE", token: alice.idToken }));

for (const user of [alice, bob]) {
  await call(`https://identitytoolkit.googleapis.com/v1/accounts:delete?key=${apiKey}`, { body: { idToken: user.idToken } });
}
console.log("temporary users deleted");
console.log(failures === 0 ? "ALL OK" : `${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
