// Checks against the real project that a different anonymous user cannot change a match.
// Creates a temporary anonymous user and deletes it again afterwards.
// Usage: node tests/other-user.mjs <matchId>
const matchId = process.argv[2];
const { apiKey, projectId } = await (await fetch("https://matchreferat.web.app/__/firebase/init.json")).json();
const doc = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/matches/${matchId}`;

async function call(url, { method = "POST", body, token } = {}) {
  const headers = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  const response = await fetch(url, { method, headers, body: body && JSON.stringify(body) });
  return { status: response.status, json: await response.json().catch(() => ({})) };
}

const signUp = await call(`https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${apiKey}`, { body: { returnSecureToken: true } });
console.log("temporary user created:", signUp.status);
const token = signUp.json.idToken;

const checks = [
  ["overwrite score", 403, () => call(`${doc}?updateMask.fieldPaths=homeScore`, { method: "PATCH", token, body: { fields: { homeScore: { integerValue: "9" } } } })],
  ["take ownership", 403, () => call(`${doc}?updateMask.fieldPaths=ownerUid`, { method: "PATCH", token, body: { fields: { ownerUid: { stringValue: signUp.json.localId } } } })],
  ["delete", 403, () => call(doc, { method: "DELETE", token })],
  ["list matches", 403, () => call(doc.slice(0, doc.lastIndexOf("/")), { method: "GET", token })],
  ["read by id", 200, () => call(doc, { method: "GET", token })],
];
for (const [name, expected, run] of checks) {
  const { status } = await run();
  console.log(`${status === expected ? "OK  " : "FAIL"} ${name}: ${status} (expected ${expected})`);
}

const removed = await call(`https://identitytoolkit.googleapis.com/v1/accounts:delete?key=${apiKey}`, { body: { idToken: token } });
console.log("temporary user deleted:", removed.status);
