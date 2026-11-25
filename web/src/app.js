// Einbürgerungstest Trainer — web version. Mirrors the iOS app's Store logic.

const EXAM = { general: 30, state: 3, passMark: 17, seconds: 60 * 60 };
const INTERVALS = [0, 1, 2, 4, 7]; // Leitner box → days until due
const BUFFER_DAYS = 2;
const STORAGE_KEY = "eb-trainer-v1";
const BAMF_PDF = "https://www.bamf.de/SharedDocs/Anlagen/DE/Integration/Einbuergerung/gesamtfragenkatalog-lebenindeutschland.pdf?__blob=publicationFile";
const TOPICS = [
  "Grundrechte & Verfassung", "Staat & Recht", "Wahlen & Parteien", "Geschichte & Geografie",
  "Arbeit & Wirtschaft", "Familie, Bildung & Religion", "Nordrhein-Westfalen",
];
const MASTERY = { new: "Neu", shaky: "Wackelig", learning: "Gelernt", solid: "Sicher" };
const ORDER = ["solid", "learning", "shaky", "new"];

const $main = document.getElementById("main");
let Q = [];          // all questions, catalog order
let byId = new Map();
let S;               // persisted state
let session = null;  // active practice/exam session
let timerHandle = null;

// ---------- utilities ----------
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const startOfDay = (d = new Date()) => { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; };
const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const dayKey = (d) => { const x = startOfDay(d); return `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, "0")}-${String(x.getDate()).padStart(2, "0")}`; };
const shuffle = (a) => { const b = [...a]; for (let i = b.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [b[i], b[j]] = [b[j], b[i]]; } return b; };
const label = (q) => (q.state ? `NRW ${q.number}` : `Aufgabe ${q.number}`);
const fmtDate = (d) => new Date(d).toLocaleDateString("de-DE", { weekday: "long", day: "numeric", month: "long" });
const minutesText = (sec) => { const s = Math.round(sec); const m = Math.floor(s / 60); return m ? `${m} Min ${String(s % 60).padStart(2, "0")} Sek` : `${s} Sek`; };
const clock = (sec) => `${String(Math.floor(sec / 60)).padStart(2, "0")}:${String(Math.floor(sec % 60)).padStart(2, "0")}`;

// ---------- persistence ----------
function defaultState() {
  const d = addDays(startOfDay(), 28); d.setHours(9);
  return { progress: {}, exams: [], plan: null, examDate: d.toISOString(), examDateConfirmed: false, showEnglish: false };
}
function load() {
  try { const raw = localStorage.getItem(STORAGE_KEY); if (raw) return { ...defaultState(), ...JSON.parse(raw) }; } catch {}
  return defaultState();
}
function save() { try { localStorage.setItem(STORAGE_KEY, JSON.stringify(S)); } catch {} }

// ---------- progress model ----------
const prog = (id) => S.progress[id] || { box: 0, seen: 0, correct: 0, wrong: 0, lastWrong: false, due: null, bookmarked: false };
function mastery(id) {
  const p = prog(id);
  if (!p.seen) return "new";
  if (p.lastWrong) return "shaky";
  return p.box >= 2 ? "solid" : "learning";
}
function counts(list = Q) {
  const c = { solid: 0, learning: 0, shaky: 0, new: 0 };
  for (const q of list) c[mastery(q.id)]++;
  return c;
}
const daysUntilExam = () => Math.round((startOfDay(new Date(S.examDate)) - startOfDay()) / 86400000);
const unseen = () => Q.filter((q) => !prog(q.id).seen);

function refreshPlan(force = false) {
  const today = dayKey(new Date());
  if (!force && S.plan && S.plan.day === today) return;
  const end = addDays(startOfDay(), 1).getTime();
  const reviews = Q.filter((q) => { const p = prog(q.id); return p.seen && (p.lastWrong || (p.due ?? Infinity) < end); })
    .sort((a, b) => { const pa = prog(a.id), pb = prog(b.id); if (pa.lastWrong !== pb.lastWrong) return pa.lastWrong ? -1 : 1; return (pa.due ?? 0) - (pb.due ?? 0); })
    .slice(0, 60).map((q) => q.id);
  const fresh = unseen();
  const days = Math.max(1, daysUntilExam() - BUFFER_DAYS);
  const share = Math.ceil(fresh.length / days);
  const n = Math.min(fresh.length, Math.max(share, fresh.length ? 15 : 0));
  S.plan = { day: today, newIds: fresh.slice(0, n).map((q) => q.id), reviewIds: reviews, done: [] };
  save();
}
const planAll = () => (S.plan ? [...S.plan.reviewIds, ...S.plan.newIds] : []);
const planRemaining = () => planAll().filter((id) => !S.plan.done.includes(id));

function record(q, chosen) {
  const p = { ...prog(q.id) };
  p.seen++;
  if (chosen === q.correct) { p.correct++; p.box = p.lastWrong ? 1 : Math.min(p.box + 1, INTERVALS.length - 1); p.lastWrong = false; }
  else { p.wrong++; p.box = 0; p.lastWrong = true; }
  p.due = addDays(startOfDay(), INTERVALS[p.box]).getTime();
  S.progress[q.id] = p;
  if (S.plan && planAll().includes(q.id) && !S.plan.done.includes(q.id)) S.plan.done.push(q.id);
  save();
}
function toggleBookmark(id) { const p = { ...prog(id) }; p.bookmarked = !p.bookmarked; S.progress[id] = p; save(); }

function makeExam() {
  const gen = shuffle(Q.filter((q) => !q.state)).slice(0, EXAM.general).sort((a, b) => a.number - b.number);
  const st = shuffle(Q.filter((q) => q.state)).slice(0, EXAM.state).sort((a, b) => a.number - b.number);
  return [...gen, ...st].map((q) => q.id);
}

// ---------- shared pieces ----------
function masteryBar(c, thin = false) {
  const total = Object.values(c).reduce((a, b) => a + b, 0) || 1;
  const segs = ORDER.filter((m) => c[m]).map((m) => `<span class="m-${m}" style="width:${(c[m] / total) * 100}%"></span>`).join("");
  const aria = ORDER.map((m) => `${c[m]} ${MASTERY[m]}`).join(", ");
  return `<div class="mbar${thin ? " thin" : ""}" role="img" aria-label="${aria}">${segs}</div>`;
}
const legend = (c) => `<div class="legend" aria-hidden="true">${ORDER.map((m) => `<span><i class="m-${m}"></i><span class="num">${c[m]}</span> ${MASTERY[m]}</span>`).join("")}</div>`;
const icon = {
  back: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M15 18l-6-6 6-6"/></svg>`,
  next: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 18l6-6-6-6"/></svg>`,
  chev: `<svg class="chev" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 18l6-6-6-6"/></svg>`,
  bookmark: (on) => `<svg width="20" height="20" viewBox="0 0 24 24" fill="${on ? "currentColor" : "none"}" stroke="currentColor" stroke-width="2" stroke-linejoin="round" aria-hidden="true"><path d="M6 3h12v18l-6-4-6 4z"/></svg>`,
  retry: `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5"/></svg>`,
  spark: `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/></svg>`,
  shuffle: `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M16 3h5v5M4 20 21 3M21 16v5h-5M15 15l6 6M4 4l5 5"/></svg>`,
  timer: `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="13" r="8"/><path d="M12 9v4l2 2M9 2h6"/></svg>`,
  photo: `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="11" r="2"/><path d="m21 17-5-5-8 7"/></svg>`,
};

// ---------- question card ----------
// mode: {kind:'practice', chosen} | {kind:'exam', chosen} | {kind:'review', chosen}
function questionHTML(q, mode) {
  const en = S.showEnglish;
  const revealed = mode.kind === "review" || (mode.kind === "practice" && mode.chosen != null);
  const locked = revealed;
  const marked = prog(q.id).bookmarked;
  const state = (i) => {
    if (mode.kind === "exam") return mode.chosen === i ? "selected" : "";
    if (!revealed) return "";
    if (i === q.correct) return "correct";
    return i === mode.chosen ? "wrong" : "dimmed";
  };
  const keyMark = (i, st) => (st === "correct" ? "✓" : st === "wrong" ? "✕" : String(i + 1));
  let figure = "";
  if (q.image) {
    figure = `<figure class="q-figure"><img src="img/${esc(q.image)}" alt="Abbildung zu ${esc(label(q))}" data-zoom>${q.credit ? `<figcaption>${esc(q.credit)}</figcaption>` : ""}</figure>`;
  } else if (q.photo) {
    figure = `<div class="photo-note">${icon.photo}<span>Zu dieser Frage gehört ein Pressefoto, das hier aus Urheberrechtsgründen fehlt. ${q.photoHint ? esc(q.photoHint) + " " : ""}Du findest es im <a href="${BAMF_PDF}" target="_blank" rel="noopener">offiziellen Katalog (PDF)</a>, ${esc(label(q))}.</span></div>`;
  }
  const answers = q.answers.map((a, i) => {
    const st = state(i);
    return `<button class="answer ${st}" data-answer="${i}" ${locked ? "disabled" : ""} aria-label="${esc(a)}${st === "correct" ? ", richtige Antwort" : st === "wrong" ? ", falsch" : st === "selected" ? ", ausgewählt" : ""}">
      <span class="key" aria-hidden="true">${keyMark(i, st)}</span>
      <span class="txt">${esc(a)}${en ? `<span class="en">${esc(q.en.answers[i])}</span>` : ""}</span></button>`;
  }).join("");
  const explain = revealed && q.en.explanation
    ? `<details class="explain reveal-in"><summary>Why? (English)</summary><p>${esc(q.en.explanation)}</p></details>` : "";
  return `
    <div class="q-meta">
      <span class="num">${esc(label(q))}</span><span aria-hidden="true">·</span><span class="topic">${esc(q.topic)}</span>
      <span class="spacer"></span>
      <button class="chip" data-act="toggle-en" aria-pressed="${en}" title="Englisch (E)">EN</button>
      <button class="mark" data-act="bookmark" data-id="${esc(q.id)}" aria-pressed="${marked}" aria-label="${marked ? "Markierung entfernen" : "Frage markieren"}" title="Markieren (M)">${icon.bookmark(marked)}</button>
    </div>
    <h2 class="q-text">${esc(q.question)}</h2>
    ${en ? `<p class="q-en">${esc(q.en.question)}</p>` : ""}
    ${figure}
    <div class="answers" role="group" aria-label="Antworten">${answers}</div>
    ${explain}`;
}

// ---------- views ----------
function setTab(tab) {
  document.querySelectorAll(".tabs a").forEach((a) => { if (a.dataset.tab === tab) a.setAttribute("aria-current", "page"); else a.removeAttribute("aria-current"); });
}

function countdownTitle() {
  const d = daysUntilExam();
  if (d < 0) return "Test geschafft?";
  if (d === 0) return "Heute ist Testtag";
  if (d === 1) return "Morgen ist der Test";
  return `Noch ${d} Tage`;
}

function viewToday() {
  refreshPlan();
  const all = planAll(), rem = planRemaining(), done = S.plan.done.length;
  const c = counts();
  let plan;
  if (!all.length) {
    plan = `<h2>Heute nichts fällig</h2><p class="muted">Alle Fragen sind gelernt und nichts ist zur Wiederholung fällig. Mach einen Probetest.</p>`;
  } else if (!rem.length) {
    plan = `<h2 style="color:var(--green)">Plan für heute erledigt</h2><p class="muted">${all.length} Fragen geschafft. Morgen geht es weiter.</p>`;
  } else {
    const parts = [];
    if (S.plan.newIds.length) parts.push(`${S.plan.newIds.length} neue`);
    if (S.plan.reviewIds.length) parts.push(`${S.plan.reviewIds.length} Wiederholungen`);
    const tail = unseen().length ? `Bei diesem Tempo kennst du alle ${Q.length} Fragen ${BUFFER_DAYS} Tage vor dem Test.` : "Alle Fragen gesehen, jetzt geht es ums Festigen.";
    plan = `<h2>Noch ${rem.length} ${rem.length === 1 ? "Frage" : "Fragen"} für heute</h2>
      <p class="muted" style="margin:0 0 14px">${parts.join(" · ")}. ${tail}</p>
      <div class="progress" style="margin-bottom:16px"><span style="width:${(done / all.length) * 100}%"></span></div>`;
  }
  const last = S.exams[0];
  $main.innerHTML = `
    <h1 class="page-title">${countdownTitle()}</h1>
    <p class="page-sub">Einbürgerungstest · ${esc(fmtDate(S.examDate))}${S.examDateConfirmed ? "" : ` · <button class="text-btn" data-act="settings" style="padding:0;min-height:0">Testtermin festlegen</button>`}</p>
    <h3 class="section-label">Tagesplan</h3>
    <div class="group card">${plan}
      ${rem.length ? `<button class="btn btn-primary btn-block" data-act="start-plan">${done ? "Weiterlernen" : "Lernen starten"}</button>` : ""}
    </div>
    <h3 class="section-label">Fortschritt</h3>
    <div class="group card">
      <div style="display:flex;align-items:baseline;gap:8px;margin-bottom:12px"><span class="big">${c.solid}</span><span class="muted">von ${Q.length} sicher</span></div>
      ${masteryBar(c)}${legend(c)}
    </div>
    <p class="footnote">Sicher heißt: zweimal hintereinander richtig beantwortet.</p>
    <h3 class="section-label">Prüfung simulieren</h3>
    <div class="group">
      <button class="row" data-act="start-exam"><span class="icon">${icon.timer}</span><span class="grow" style="color:var(--ink)">Probetest starten</span><span class="trail">33 Fragen · 60 Min</span></button>
      ${last ? `<div class="row" style="cursor:default"><span class="grow">Letzter Probetest</span><span class="trail" style="font-weight:650;color:${last.correct >= EXAM.passMark ? "var(--green)" : "var(--red)"}">${last.correct}/${last.total}</span></div>` : ""}
    </div>
    <p class="footnote kbd-only">Am Computer: <kbd>1</kbd>–<kbd>4</kbd> antworten, <kbd>Enter</kbd> weiter, <kbd>E</kbd> Englisch, <kbd>M</kbd> markieren.</p>`;
}

function prioritized(list) {
  const rank = { shaky: 0, new: 1, learning: 2, solid: 3 };
  return [...list].sort((a, b) => rank[mastery(a.id)] - rank[mastery(b.id)] || a.order - b.order);
}

function viewPractice() {
  const mistakes = Q.filter((q) => mastery(q.id) === "shaky");
  const marked = Q.filter((q) => prog(q.id).bookmarked);
  const fresh = unseen();
  const focus = (act, ic, title, n, empty, color = "var(--ink)") => `
    <button class="row" data-act="${act}" ${n === 0 ? "disabled" : ""}>
      <span class="icon" style="color:${n === 0 ? "var(--text-3)" : color}">${ic}</span>
      <span class="grow">${title}${n === 0 && empty ? `<span class="sub">${empty}</span>` : ""}</span>
      ${n > 0 && n !== null ? `<span class="trail">${n}</span>` : ""}
    </button>`;
  const groupRow = (act, title, list, extra = "") => {
    const c = counts(list);
    return `<button class="row" data-act="${act}" ${extra}><span class="grow">
      <span style="display:flex;justify-content:space-between;gap:12px;margin-bottom:7px"><span>${esc(title)}</span><span class="trail" style="font-size:15px">${c.solid}/${list.length}</span></span>
      ${masteryBar(c, true)}</span></button>`;
  };
  const blocks = Array.from({ length: 10 }, (_, b) => {
    const from = b * 30 + 1, to = from + 29;
    return groupRow("block", `Aufgaben ${from}–${to}`, Q.filter((q) => !q.state && q.number >= from && q.number <= to), `data-from="${from}" data-to="${to}"`);
  }).join("");
  $main.innerHTML = `
    <h1 class="page-title">Üben</h1>
    <h3 class="section-label">Schwerpunkte</h3>
    <div class="group">
      ${focus("mistakes", icon.retry, "Fehler wiederholen", mistakes.length, "Keine offenen Fehler", "var(--orange)")}
      ${focus("marked", icon.bookmark(false), "Markierte Fragen", marked.length, "Nichts markiert")}
      ${focus("unseen", icon.spark, "Noch nie gesehen", fresh.length, "Alle Fragen gesehen")}
      <button class="row" data-act="random"><span class="icon">${icon.shuffle}</span><span class="grow">Zufällige 20</span></button>
    </div>
    <h3 class="section-label">Themen</h3>
    <div class="group">${TOPICS.map((t) => groupRow("topic", t, Q.filter((q) => q.topic === t), `data-topic="${esc(t)}"`)).join("")}</div>
    <h3 class="section-label">Der Reihe nach</h3>
    <div class="group">${blocks}${groupRow("nrw", "NRW 1–10", Q.filter((q) => q.state))}</div>
    <p class="footnote">Reihenfolge und Wortlaut wie im offiziellen Fragenkatalog des BAMF (Stand 07.05.2025).</p>`;
}

function viewExamTab() {
  const passed = S.exams.filter((e) => e.correct >= EXAM.passMark).length;
  $main.innerHTML = `
    <h1 class="page-title">Prüfung</h1>
    <div class="group card" style="margin-top:20px">
      <h2>Wie im echten Test</h2>
      <ul class="muted" style="margin:10px 0 18px;padding-left:20px;line-height:1.8">
        <li>33 Fragen: 30 allgemein, 3 zu NRW</li><li>60 Minuten</li>
        <li>Bestanden ab ${EXAM.passMark} richtigen Antworten</li><li>Auflösung erst nach dem Abgeben</li>
      </ul>
      <button class="btn btn-primary btn-block" data-act="start-exam">Probetest starten</button>
    </div>
    ${S.exams.length ? `<h3 class="section-label">Bisherige Probetests</h3><div class="group">
      ${S.exams.map((e) => `<div class="row" style="cursor:default"><span class="dot" style="background:${e.correct >= EXAM.passMark ? "var(--green)" : "var(--red)"}"></span>
        <span class="grow">${esc(new Date(e.date).toLocaleString("de-DE", { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }))}<span class="sub">${minutesText(e.duration)}</span></span>
        <span class="trail" style="font-weight:650;color:var(--text)">${e.correct}/${e.total}</span></div>`).join("")}
    </div><p class="footnote">${passed} von ${S.exams.length} bestanden.</p>` : ""}`;
}

let catQuery = "", catTopic = "";
function catalogRow(q, chosen = null) {
  return `<button class="row cat-row" data-act="detail" data-id="${esc(q.id)}">
    <span class="dot m-${mastery(q.id)}" title="${MASTERY[mastery(q.id)]}"></span>
    <span class="grow"><span class="cat-num">${q.state ? `NRW ${q.number}` : q.number}</span>
      <span class="cat-q">${esc(q.question)}</span>
      ${chosen != null && chosen !== q.correct ? `<span class="cat-a bad"><span aria-hidden="true">✕</span>${esc(q.answers[chosen])}</span>` : ""}
      <span class="cat-a"><span aria-hidden="true">✓</span>${esc(q.answers[q.correct])}</span></span>${icon.chev}</button>`;
}
function catalogResults() {
  const s = catQuery.trim().toLowerCase();
  return Q.filter((q) => (!catTopic || q.topic === catTopic) && (!s || (/^\d+$/.test(s) ? q.number === Number(s)
    : q.question.toLowerCase().includes(s) || q.answers.some((a) => a.toLowerCase().includes(s)) || q.en.question.toLowerCase().includes(s))));
}
function renderCatalogList() {
  const list = catalogResults();
  document.getElementById("cat-list").innerHTML = list.length
    ? `<div class="group">${list.map((q) => catalogRow(q)).join("")}</div>`
    : `<div class="empty">Keine Treffer für „${esc(catQuery)}“.</div>`;
}
function viewCatalog() {
  $main.innerHTML = `
    <h1 class="page-title">Katalog</h1>
    <div class="filters" style="margin-top:16px">
      <input class="search" type="search" id="cat-search" placeholder="Frage, Antwort oder Nummer" aria-label="Katalog durchsuchen" value="${esc(catQuery)}">
      <select id="cat-topic" aria-label="Nach Thema filtern"><option value="">Alle Themen</option>${TOPICS.map((t) => `<option ${t === catTopic ? "selected" : ""}>${esc(t)}</option>`).join("")}</select>
    </div>
    <div id="cat-list"></div>`;
  renderCatalogList();
}

function viewDetail(id) {
  const q = byId.get(id);
  if (!q) return viewCatalog();
  $main.innerHTML = `
    <div class="session-bar"><button class="text-btn" data-act="back">${icon.back} Zurück</button><span class="title">${esc(label(q))}</span><span style="width:70px"></span></div>
    ${questionHTML(q, { kind: "review", chosen: null })}`;
}

// ---------- practice session ----------
function startPractice(title, ids) {
  session = { kind: "practice", title, initial: [...ids], queue: [...ids], index: 0, chosen: null, correct: 0, answered: 0, requeued: [], finished: !ids.length };
  renderSession();
}
function renderSession() {
  if (!session) return route();
  window.scrollTo({ top: 0 });
  if (session.kind === "exam") return renderExam();
  const s = session;
  if (s.finished) return renderPracticeSummary();
  const q = byId.get(s.queue[s.index]);
  $main.innerHTML = `
    <div class="session-bar">
      <button class="text-btn" data-act="end-session">Beenden</button>
      <span class="title">${s.index + 1} von ${s.queue.length}</span>
      <span style="width:80px"></span>
    </div>
    <div class="progress session-progress"><span style="width:${(s.index / s.queue.length) * 100}%"></span></div>
    <div id="qcard">${questionHTML(q, { kind: "practice", chosen: s.chosen })}</div>
    <div class="action-bar" id="action-bar">${practiceActions()}</div>`;
}
function practiceActions() {
  const s = session;
  if (s.chosen == null) return `<span class="hint grow">Antworten mit <kbd>1</kbd>–<kbd>4</kbd></span>`;
  return `<span class="hint grow"><kbd>Enter</kbd> weiter</span>
    <button class="btn btn-primary reveal-in" data-act="next" style="min-width:min(260px,100%)">${s.index + 1 < s.queue.length ? "Weiter" : "Auswertung"}</button>`;
}
function choosePractice(i) {
  const s = session; if (s.chosen != null) return;
  const q = byId.get(s.queue[s.index]);
  s.chosen = i; s.answered++;
  if (i === q.correct) s.correct++;
  record(q, i);
  if (i !== q.correct && !s.requeued.includes(q.id)) { s.requeued.push(q.id); s.queue.push(q.id); }
  document.getElementById("qcard").innerHTML = questionHTML(q, { kind: "practice", chosen: i });
  document.getElementById("action-bar").innerHTML = practiceActions();
  const title = document.querySelector(".session-bar .title");
  if (title) title.textContent = `${s.index + 1} von ${s.queue.length}`;
  document.querySelector('[data-act="next"]')?.focus({ preventScroll: true });
}
function nextPractice() {
  const s = session; if (s.chosen == null) return;
  s.chosen = null;
  if (s.index + 1 < s.queue.length) s.index++; else s.finished = true;
  renderSession();
}
function renderPracticeSummary() {
  const s = session;
  const qs = [...new Set(s.initial)].map((id) => byId.get(id));
  const c = counts(qs);
  $main.innerHTML = `
    <div class="session-bar"><span style="width:80px"></span><span class="title">${esc(s.title)}</span><button class="text-btn" data-act="end-session">Fertig</button></div>
    <div class="group card" style="margin-top:8px">
      ${s.answered ? `<div class="big" style="font-size:34px">${s.correct} von ${s.answered} richtig</div>
        <p class="muted">${s.requeued.length ? `${s.requeued.length} Fragen waren zunächst falsch. Sie kommen in den nächsten Tagen wieder.` : "Alles auf Anhieb gewusst."}</p>`
        : `<h2>Nichts zu tun</h2><p class="muted">In dieser Auswahl gibt es gerade keine Fragen.</p>`}
      ${masteryBar(c)}${legend(c)}
    </div>
    ${s.requeued.length ? `<h3 class="section-label">Zunächst falsch</h3><div class="group">${s.requeued.map((id) => catalogRow(byId.get(id))).join("")}</div>` : ""}`;
}

// ---------- exam session ----------
function startExam() {
  session = { kind: "exam", ids: makeExam(), answers: {}, index: 0, startedAt: Date.now(), result: null };
  clearInterval(timerHandle);
  timerHandle = setInterval(tickExam, 1000);
  renderSession();
}
function tickExam() {
  const s = session;
  if (!s || s.kind !== "exam" || s.result) { clearInterval(timerHandle); return; }
  const left = EXAM.seconds - (Date.now() - s.startedAt) / 1000;
  const el = document.getElementById("timer");
  if (el) { el.textContent = clock(Math.max(0, left)); el.classList.toggle("low", left < 300); }
  if (left <= 0) submitExam();
}
function renderExam() {
  const s = session;
  if (s.result) return renderExamResult();
  const q = byId.get(s.ids[s.index]);
  const answered = Object.keys(s.answers).length;
  const left = EXAM.seconds - (Date.now() - s.startedAt) / 1000;
  $main.innerHTML = `
    <div class="session-bar">
      <button class="text-btn" data-act="quit-exam">Abbrechen</button>
      <span class="title"><span id="timer" class="timer${left < 300 ? " low" : ""}" aria-label="Verbleibende Zeit">${clock(Math.max(0, left))}</span></span>
      <button class="text-btn" data-act="submit-exam">Abgeben</button>
    </div>
    <div class="progress session-progress"><span style="width:${(answered / s.ids.length) * 100}%"></span></div>
    <div id="qcard">${questionHTML(q, { kind: "exam", chosen: s.answers[q.id] })}</div>
    <div class="action-bar">
      <button class="btn btn-secondary" data-act="prev" ${s.index === 0 ? "disabled" : ""} aria-label="Vorherige Frage">${icon.back}</button>
      <button class="btn btn-secondary grow num" data-act="overview" style="font-size:15px">Frage ${s.index + 1} von ${s.ids.length}</button>
      <button class="btn btn-primary" data-act="next-q" ${s.index + 1 >= s.ids.length ? "disabled" : ""} aria-label="Nächste Frage">${icon.next}</button>
    </div>
    <p class="footnote kbd-only" style="text-align:center"><kbd>1</kbd>–<kbd>4</kbd> wählen · <kbd>←</kbd> <kbd>→</kbd> blättern</p>`;
}
function chooseExam(i) {
  const s = session; const id = s.ids[s.index];
  s.answers[id] = i;
  const q = byId.get(id);
  document.getElementById("qcard").innerHTML = questionHTML(q, { kind: "exam", chosen: i });
  const bar = document.querySelector(".session-progress > span");
  if (bar) bar.style.width = `${(Object.keys(s.answers).length / s.ids.length) * 100}%`;
}
function examGo(delta) {
  const s = session; const n = s.index + delta;
  if (n < 0 || n >= s.ids.length) return;
  s.index = n; renderExam(); window.scrollTo({ top: 0 });
}
function submitExam(confirmFirst = false) {
  const s = session; if (!s || s.result) return;
  if (confirmFirst) {
    const open = s.ids.length - Object.keys(s.answers).length;
    if (!confirm(open ? `Noch ${open} Fragen offen. Trotzdem abgeben?` : "Test abgeben?")) return;
  }
  clearInterval(timerHandle);
  let correct = 0; const wrong = [];
  for (const id of s.ids) {
    const q = byId.get(id); const a = s.answers[id];
    if (a != null) { record(q, a); if (a === q.correct) correct++; else wrong.push(id); } else wrong.push(id);
  }
  s.result = { id: crypto.randomUUID?.() ?? String(Date.now()), date: new Date().toISOString(), correct, total: s.ids.length, duration: (Date.now() - s.startedAt) / 1000, wrongIds: wrong };
  S.exams.unshift(s.result); save();
  renderSession();
}
function renderExamResult() {
  const s = session, r = s.result, pass = r.correct >= EXAM.passMark;
  const wrong = r.wrongIds.map((id) => byId.get(id));
  $main.innerHTML = `
    <div class="session-bar"><span style="width:80px"></span><span class="title">Ergebnis</span><button class="text-btn" data-act="end-session">Fertig</button></div>
    <div class="group card" style="margin-top:8px">
      <div class="verdict ${pass ? "pass" : "fail"}">${pass ? "✓ Bestanden" : "✕ Nicht bestanden"}</div>
      <div style="display:flex;align-items:baseline;gap:8px"><span class="score" id="score">${r.correct}</span><span class="muted" style="font-size:20px">von ${r.total} richtig</span></div>
      <p class="muted" style="margin:4px 0 0">Zum Bestehen brauchst du ${EXAM.passMark}. Zeit: ${minutesText(r.duration)}.</p>
    </div>
    ${wrong.length ? `<h3 class="section-label">Falsch oder offen (${wrong.length})</h3><div class="group">${wrong.map((q) => catalogRow(q, s.answers[q.id] ?? null)).join("")}</div>` : ""}`;
  countUp(document.getElementById("score"), r.correct);
}
function countUp(el, to) {
  if (!el || matchMedia("(prefers-reduced-motion: reduce)").matches || to === 0) return;
  const t0 = performance.now(), dur = 600;
  const step = (t) => { const p = Math.min(1, (t - t0) / dur); el.textContent = Math.round(to * (1 - Math.pow(1 - p, 3))); if (p < 1) requestAnimationFrame(step); };
  el.textContent = "0"; requestAnimationFrame(step);
}
function overviewDialog() {
  const s = session;
  const d = document.createElement("dialog");
  d.innerHTML = `<div class="sheet"><div class="sheet-head"><h2 class="num">${Object.keys(s.answers).length} von ${s.ids.length} beantwortet</h2><button class="text-btn" data-close>Schließen</button></div>
    <div class="grid group">${s.ids.map((id, i) => `<button data-go="${i}" class="${s.answers[id] != null ? "done" : ""} ${i === s.index ? "current" : ""}" aria-label="Frage ${i + 1}, ${s.answers[id] != null ? "beantwortet" : "offen"}">${i + 1}</button>`).join("")}</div></div>`;
  d.addEventListener("click", (e) => {
    const go = e.target.closest("[data-go]");
    if (go) { s.index = Number(go.dataset.go); d.close(); renderExam(); }
    if (e.target.closest("[data-close]") || e.target === d) d.close();
  });
  d.addEventListener("close", () => d.remove());
  document.body.append(d); d.showModal();
}
function zoomDialog(src, alt) {
  const d = document.createElement("dialog");
  d.className = "zoom";
  d.innerHTML = `<img src="${esc(src)}" alt="${esc(alt)}">`;
  d.addEventListener("click", () => d.close());
  d.addEventListener("close", () => d.remove());
  document.body.append(d); d.showModal();
}

// ---------- routing & events ----------
function route() {
  if (session) return renderSession();
  const [, tab = "heute", arg] = (location.hash || "#/heute").split("/");
  const valid = ["heute", "ueben", "pruefung", "katalog"];
  const t = valid.includes(tab) ? tab : "heute";
  setTab(t);
  if (t === "heute") viewToday();
  else if (t === "ueben") viewPractice();
  else if (t === "pruefung") viewExamTab();
  else if (arg) viewDetail(decodeURIComponent(arg));
  else viewCatalog();
}

function rerenderQuestion() {
  if (session?.kind === "practice" && !session.finished) {
    document.getElementById("qcard").innerHTML = questionHTML(byId.get(session.queue[session.index]), { kind: "practice", chosen: session.chosen });
  } else if (session?.kind === "exam" && !session.result) {
    const id = session.ids[session.index];
    document.getElementById("qcard").innerHTML = questionHTML(byId.get(id), { kind: "exam", chosen: session.answers[id] });
  } else route();
}

function endSession() { session = null; clearInterval(timerHandle); route(); }

$main.addEventListener("click", (e) => {
  const img = e.target.closest("[data-zoom]"); if (img) return zoomDialog(img.src, img.alt);
  const ans = e.target.closest("[data-answer]");
  if (ans && !ans.disabled) { const i = Number(ans.dataset.answer); return session?.kind === "exam" ? chooseExam(i) : choosePractice(i); }
  const el = e.target.closest("[data-act]"); if (!el || el.disabled) return;
  const act = el.dataset.act;
  switch (act) {
    case "start-plan": return startPractice("Tagesplan", planRemaining());
    case "start-exam": return startExam();
    case "settings": return openSettings();
    case "mistakes": return startPractice("Fehler wiederholen", shuffle(Q.filter((q) => mastery(q.id) === "shaky")).map((q) => q.id));
    case "marked": return startPractice("Markierte Fragen", Q.filter((q) => prog(q.id).bookmarked).map((q) => q.id));
    case "unseen": return startPractice("Noch nie gesehen", unseen().map((q) => q.id));
    case "random": return startPractice("Zufällige 20", shuffle(Q).slice(0, 20).map((q) => q.id));
    case "topic": return startPractice(el.dataset.topic, prioritized(Q.filter((q) => q.topic === el.dataset.topic)).map((q) => q.id));
    case "block": { const f = Number(el.dataset.from), t = Number(el.dataset.to); return startPractice(`Aufgaben ${f}–${t}`, Q.filter((q) => !q.state && q.number >= f && q.number <= t).map((q) => q.id)); }
    case "nrw": return startPractice("Nordrhein-Westfalen", Q.filter((q) => q.state).map((q) => q.id));
    case "next": return nextPractice();
    case "end-session": return endSession();
    case "quit-exam": if (confirm("Probetest abbrechen? Er wird nicht gewertet.")) endSession(); return;
    case "submit-exam": return submitExam(true);
    case "prev": return examGo(-1);
    case "next-q": return examGo(1);
    case "overview": return overviewDialog();
    case "toggle-en": S.showEnglish = !S.showEnglish; save(); return rerenderQuestion();
    case "bookmark": toggleBookmark(el.dataset.id); return rerenderQuestion();
    case "detail": if (session) { const id = el.dataset.id; return reviewInline(id); } location.hash = `#/katalog/${encodeURIComponent(el.dataset.id)}`; return;
    case "back": history.length > 1 ? history.back() : (location.hash = "#/katalog"); return;
  }
});

// Inside a finished session the summary lists questions; open them without leaving the session.
function reviewInline(id) {
  const q = byId.get(id);
  const chosen = session?.kind === "exam" ? session.answers[id] ?? null : null;
  const d = document.createElement("dialog");
  d.style.width = "min(680px, calc(100vw - 32px))";
  d.innerHTML = `<div class="sheet"><div class="sheet-head"><h2>${esc(label(q))}</h2><button class="text-btn" data-close>Schließen</button></div>${questionHTML(q, { kind: "review", chosen })}</div>`;
  d.addEventListener("click", (e) => {
    if (e.target.closest("[data-close]") || e.target === d) d.close();
    const act = e.target.closest("[data-act]")?.dataset.act;
    if (act === "toggle-en") { S.showEnglish = !S.showEnglish; save(); d.close(); reviewInline(id); }
    if (act === "bookmark") { toggleBookmark(id); d.close(); reviewInline(id); }
  });
  d.addEventListener("close", () => d.remove());
  document.body.append(d); d.showModal();
}

$main.addEventListener("input", (e) => {
  if (e.target.id === "cat-search") { catQuery = e.target.value; renderCatalogList(); }
});
$main.addEventListener("change", (e) => {
  if (e.target.id === "cat-topic") { catTopic = e.target.value; renderCatalogList(); }
});

document.addEventListener("keydown", (e) => {
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  if (document.querySelector("dialog[open]")) return;
  if (["INPUT", "SELECT", "TEXTAREA"].includes(document.activeElement?.tagName)) return;
  const k = e.key.toLowerCase();
  if (!session) return;
  const idx = { 1: 0, 2: 1, 3: 2, 4: 3, a: 0, b: 1, c: 2, d: 3 }[k];
  if (session.kind === "practice" && !session.finished) {
    if (idx != null && session.chosen == null) { e.preventDefault(); return choosePractice(idx); }
    if ((k === "enter" || k === "arrowright" || k === " ") && session.chosen != null) { e.preventDefault(); return nextPractice(); }
  }
  if (session.kind === "exam" && !session.result) {
    if (idx != null) { e.preventDefault(); return chooseExam(idx); }
    if (k === "arrowright" || k === "enter") { e.preventDefault(); return examGo(1); }
    if (k === "arrowleft") { e.preventDefault(); return examGo(-1); }
  }
  if (k === "e" && ((session.kind === "practice" && !session.finished) || (session.kind === "exam" && !session.result))) {
    S.showEnglish = !S.showEnglish; save(); return rerenderQuestion();
  }
  if (k === "m" && ((session.kind === "practice" && !session.finished) || (session.kind === "exam" && !session.result))) {
    const id = session.kind === "exam" ? session.ids[session.index] : session.queue[session.index];
    toggleBookmark(id); return rerenderQuestion();
  }
});

window.addEventListener("hashchange", () => { if (session && session.kind === "exam" && !session.result) return; session = null; route(); });
document.addEventListener("visibilitychange", () => { if (!document.hidden && !session) { refreshPlan(); route(); } });

// ---------- settings ----------
const $settings = document.getElementById("settings");
function openSettings() {
  const d = new Date(S.examDate);
  document.getElementById("exam-date").value = dayKey(d);
  document.getElementById("always-en").checked = S.showEnglish;
  $settings.showModal();
}
document.getElementById("open-settings").addEventListener("click", openSettings);
document.getElementById("exam-date").addEventListener("change", (e) => {
  if (!e.target.value) return;
  const [y, m, day] = e.target.value.split("-").map(Number);
  S.examDate = new Date(y, m - 1, day, 9).toISOString();
  S.examDateConfirmed = true; S.plan = null; save(); refreshPlan(true);
});
document.getElementById("always-en").addEventListener("change", (e) => { S.showEnglish = e.target.checked; save(); });
document.getElementById("reset").addEventListener("click", () => {
  if (!confirm("Gesamten Fortschritt und alle Probetests löschen?")) return;
  const keep = { examDate: S.examDate, examDateConfirmed: S.examDateConfirmed, showEnglish: S.showEnglish };
  S = { ...defaultState(), ...keep }; save(); refreshPlan(true);
});
$settings.addEventListener("close", () => { if (session) rerenderQuestion(); else route(); });
$settings.addEventListener("click", (e) => { if (e.target === $settings) $settings.close(); });

// ---------- boot ----------
(async function boot() {
  S = load();
  try {
    const res = await fetch("catalog.json");
    const data = await res.json();
    Q = data.questions.map((q) => ({ ...q, order: q.state ? 1000 + q.number : q.number })).sort((a, b) => a.order - b.order);
  } catch {
    $main.innerHTML = `<div class="empty">Der Fragenkatalog konnte nicht geladen werden. Bitte Seite neu laden.</div>`;
    return;
  }
  byId = new Map(Q.map((q) => [q.id, q]));
  refreshPlan();
  route();
})();
