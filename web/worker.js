// Sync API for the Einbürgerungstest Trainer. Everything else is served as static assets.
//
// POST /api/sync/<CODE>   body: SyncState   →   merged SyncState
//
// A sync code is 20 random base32 characters (100 bits), created on one device and typed
// into the other. Only a SHA-256 hash of the code is used as the storage key.
// The server merges, so phone and browser never overwrite each other's progress:
//   progress   per question, the entry with the newer updatedAt wins (ties: more answers wins)
//   exams      union by id, newest first
//   plan       same day → keep the stored lists, union the done ids; different day → newer day wins
//   settings   a confirmed exam date beats a placeholder, then the newer settingsUpdatedAt wins
//   resetAt    a reset on either device drops everything recorded before it

const CODE_RE = /^[A-Z2-7]{20}$/;
const MAX_BODY = 512 * 1024;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const m = url.pathname.match(/^\/api\/sync\/([^/]+)$/);
    if (!m) return env.ASSETS.fetch(request);
    if (request.method !== "POST") return json({ error: "method not allowed" }, 405);

    const code = normalizeCode(decodeURIComponent(m[1]));
    if (!CODE_RE.test(code)) return json({ error: "invalid sync code" }, 400);

    const text = await request.text();
    if (text.length > MAX_BODY) return json({ error: "payload too large" }, 413);
    let incoming;
    try { incoming = sanitize(JSON.parse(text)); } catch { return json({ error: "invalid json" }, 400); }

    const key = `sync:${await sha256(code)}`;
    const stored = sanitize((await env.SYNC.get(key, "json")) || {});
    const merged = merge(stored, incoming);
    // KV writes are the scarce resource (1,000/day on the free plan): only write real changes.
    if (canonical(merged) !== canonical(stored)) await env.SYNC.put(key, JSON.stringify(merged));
    merged.serverTime = Date.now();
    return json(merged);
  },
};

/** JSON with sorted keys and sorted id lists, so equal states compare equal. */
export function canonical(v) {
  if (Array.isArray(v)) return `[${v.map(canonical).join(",")}]`;
  if (v && typeof v === "object") {
    return `{${Object.keys(v).filter((k) => k !== "serverTime").sort()
      .map((k) => `${JSON.stringify(k)}:${canonical(k === "done" ? [...v[k]].sort() : v[k])}`).join(",")}}`;
  }
  return JSON.stringify(v ?? null);
}

export function normalizeCode(s) {
  return String(s).toUpperCase().replace(/[^A-Z2-7]/g, "");
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

async function sha256(s) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

const num = (v, d = 0) => (typeof v === "number" && Number.isFinite(v) ? v : d);
const ids = (a) => (Array.isArray(a) ? a.filter((x) => typeof x === "string" && x.length < 16) : []);

function sanitize(s) {
  const out = { v: 1, progress: {}, exams: [], plan: null, examDate: null, examDateConfirmed: false, settingsUpdatedAt: 0, resetAt: 0 };
  if (!s || typeof s !== "object") return out;
  if (s.progress && typeof s.progress === "object") {
    for (const [id, p] of Object.entries(s.progress)) {
      if (typeof id !== "string" || id.length > 16 || !p || typeof p !== "object") continue;
      out.progress[id] = {
        box: num(p.box), seen: num(p.seen), correct: num(p.correct), wrong: num(p.wrong),
        lastWrong: !!p.lastWrong, due: typeof p.due === "number" ? p.due : null,
        bookmarked: !!p.bookmarked, updatedAt: num(p.updatedAt),
      };
    }
  }
  if (Array.isArray(s.exams)) {
    out.exams = s.exams.filter((e) => e && typeof e.id === "string").slice(0, 500).map((e) => ({
      id: e.id.slice(0, 64), date: String(e.date || ""), correct: num(e.correct), total: num(e.total),
      duration: num(e.duration), wrongIds: ids(e.wrongIds),
    }));
  }
  if (s.plan && typeof s.plan.day === "string") {
    out.plan = { day: s.plan.day.slice(0, 10), newIds: ids(s.plan.newIds), reviewIds: ids(s.plan.reviewIds), done: ids(s.plan.done) };
  }
  if (typeof s.examDate === "string") out.examDate = s.examDate.slice(0, 40);
  out.examDateConfirmed = !!s.examDateConfirmed;
  out.settingsUpdatedAt = num(s.settingsUpdatedAt);
  out.resetAt = num(s.resetAt);
  return out;
}

export function merge(a, b) {
  const resetAt = Math.max(a.resetAt, b.resetAt);
  const progress = {};
  for (const id of new Set([...Object.keys(a.progress), ...Object.keys(b.progress)])) {
    const pa = a.progress[id], pb = b.progress[id];
    let win = !pa ? pb : !pb ? pa
      : pa.updatedAt !== pb.updatedAt ? (pa.updatedAt > pb.updatedAt ? pa : pb)
      : (pa.seen >= pb.seen ? pa : pb);
    if (win.updatedAt <= resetAt && resetAt > 0) continue;
    progress[id] = win;
  }
  const exams = new Map();
  for (const e of [...a.exams, ...b.exams]) {
    if (resetAt > 0 && Date.parse(e.date) <= resetAt) continue;
    exams.set(e.id, e);
  }
  const examList = [...exams.values()].sort((x, y) => Date.parse(y.date) - Date.parse(x.date));

  let plan = null;
  if (a.plan && b.plan) {
    plan = a.plan.day === b.plan.day
      ? { ...a.plan, done: [...new Set([...a.plan.done, ...b.plan.done])] }
      : (a.plan.day > b.plan.day ? a.plan : b.plan);
  } else plan = a.plan || b.plan;

  // A date the user actually picked beats a placeholder; otherwise the newer change wins.
  let settings;
  if (!a.examDate) settings = b;
  else if (!b.examDate) settings = a;
  else if (a.examDateConfirmed !== b.examDateConfirmed) settings = a.examDateConfirmed ? a : b;
  else settings = b.settingsUpdatedAt > a.settingsUpdatedAt ? b : a;
  return {
    v: 1, progress, exams: examList, plan,
    examDate: settings.examDate || a.examDate || b.examDate,
    examDateConfirmed: settings.examDateConfirmed,
    settingsUpdatedAt: Math.max(a.settingsUpdatedAt, b.settingsUpdatedAt),
    resetAt,
  };
}
