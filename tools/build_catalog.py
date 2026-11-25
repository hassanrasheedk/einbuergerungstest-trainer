"""Build Resources/catalog.json from the official BAMF PDF + an answer key dataset.

Question/answer text, numbering and images come from the official BAMF
"Gesamtfragenkatalog" (Stand 07.05.2025). The correct answer, English
translation and explanation come from the MIT-licensed dataset of
github.com/bitesinbyte/leben-in-deutschland, matched by answer *text* (not
letter), so differences in option order cannot shift the key.

usage: python build_catalog.py <katalog.pdf> <question.json> <out_dir>
"""
import json
import re
import sys
import unicodedata
from difflib import SequenceMatcher
from pathlib import Path

import fitz

STATES = {
    "Baden-Württemberg": "BW", "Bayern": "BY", "Berlin": "BE", "Brandenburg": "BB",
    "Bremen": "HB", "Hamburg": "HH", "Hessen": "HE", "Mecklenburg-Vorpommern": "MV",
    "Niedersachsen": "NI", "Nordrhein-Westfalen": "NW", "Rheinland-Pfalz": "RP",
    "Saarland": "SL", "Sachsen": "SN", "Sachsen-Anhalt": "ST",
    "Schleswig-Holstein": "SH", "Thüringen": "TH",
}
KEEP_STATE = "NW"
TOPICS = {
    "Constitution": "Grundrechte & Verfassung", "Rights & Freedoms": "Grundrechte & Verfassung",
    "Assembly & Protests": "Grundrechte & Verfassung",
    "Law & Governance": "Staat & Recht", "Federal System": "Staat & Recht",
    "Democracy & Politics": "Staat & Recht",
    "Elections": "Wahlen & Parteien",
    "History & Geography": "Geschichte & Geografie",
    "Economy & Employment": "Arbeit & Wirtschaft",
    "Education & Religion": "Familie, Bildung & Religion",
}  # state questions to bundle: Nordrhein-Westfalen


def norm(s):
    s = unicodedata.normalize("NFC", s).lower()
    s = s.replace("…", "...").replace("„", '"').replace("“", '"').replace("–", "-")
    # "die Kanzlerin/der Kanzler" == "der Kanzler/die Kanzlerin": compare as sorted word bag
    words = re.findall(r"[a-z0-9äöüß]+", s.replace("/", " "))
    return "".join(sorted(words))


def norm_seq(s):
    """Order-preserving normalisation: '1=A, 2=B' and '1=B, 2=A' stay different."""
    s = unicodedata.normalize("NFC", s).lower()
    return re.sub(r"[^a-z0-9äöüß]+", "", s)


def match_index(options, target):
    """Index of the option that is `target`. Word order first; the order-insensitive
    word bag (for swapped gender pairs) only when word order gives no unique hit."""
    for f in (norm_seq, norm):
        hits = [i for i, o in enumerate(options) if f(o) == f(target)]
        if len(hits) == 1:
            return hits[0], True
    sims = [SequenceMatcher(None, norm_seq(o), norm_seq(target)).ratio() for o in options]
    return max(range(len(options)), key=lambda i: sims[i]), False


def lines(doc):
    for pn, page in enumerate(doc):
        out = []
        for b in page.get_text("dict")["blocks"]:
            for l in b.get("lines", []):
                t = "".join(s["text"] for s in l["spans"]).strip()
                if not t:
                    continue
                bold = any("Bold" in s["font"] for s in l["spans"])
                box = t.startswith(("\uf0a3", "\u25a1"))
                out.append(dict(page=pn, x=l["bbox"][0], y0=l["bbox"][1], y1=l["bbox"][3], t=t, bold=bold, box=box))
        out.sort(key=lambda r: (round(r["y0"]), r["x"]))
        yield from out


def finish(q):
    """Assign raw lines to question text / answer boxes by geometry, not reading order."""
    key = lambda l: (l["page"], (l["y0"] + l["y1"]) / 2)
    boxes = sorted((l for l in q["raw"] if l["box"]), key=key)
    first = key(boxes[0])
    q["abox"] = (boxes[0]["page"], boxes[0]["y0"])
    boxx = boxes[0]["x"]
    q["a"] = ["" for _ in boxes]
    for l in sorted((l for l in q["raw"] if not l["box"]), key=lambda l: (key(l), l["x"])):
        k = key(l)
        if k >= (first[0], first[1] - 8) and l["x"] > boxx + 10:
            i = max(j for j, bx in enumerate(boxes) if key(bx) <= (k[0], k[1] + 8))
            q["a"][i] = (q["a"][i] + " " + l["t"]).strip()
        elif k < (first[0], first[1] - 8) and l["x"] < 115 and not re.match(r"^Bild \d$", l["t"]):
            q["q"].append(l["t"])


def parse(pdf):
    doc = fitz.open(pdf)
    qs, cur, state, pending_state = [], None, None, False
    for ln in lines(doc):
        t = ln["t"]
        if re.match(r"^Seite \d+ von \d+$", t) or t in ("Teil I", "Teil II", "Allgemeine Fragen"):
            continue
        m = re.match(r"^Fragen für das Bundesland (.+)$", t)
        if m:
            state = STATES[m.group(1).strip()]
            continue
        m = re.match(r"^Aufgabe (\d+)$", t)
        if m and ln["bold"]:
            cur = dict(state=state, n=int(m.group(1)), q=[], a=[], page=ln["page"], qend=None, abox=None, head=(ln["page"], ln["y1"]), raw=[])
            qs.append(cur)
            continue
        if cur is None or re.match(r"^\d+\.$", t):
            continue
        cur["raw"].append(ln)
    for q in qs:
        finish(q)
    return doc, qs


def render_image(doc, q, out_dir, key):
    """Render the picture area (images/vector art + 'Bild n' captions) above the answers."""
    (ph, y_head), (pa, y_box) = q["head"], q["abox"]
    page = doc[pa]
    top = y_head if ph == pa else 0
    rects = [fitz.Rect(i["bbox"]) for i in page.get_image_info()]
    rects += [d["rect"] for d in page.get_drawings() if d["rect"].width > 30 and d["rect"].height > 30]
    rects = [r for r in rects if r.y0 >= top - 2 and r.y1 <= y_box + 2 and r.width < page.rect.width * 0.95]
    if not rects:
        return None
    u = fitz.Rect(rects[0])
    for r in rects[1:]:
        u |= r
    clip = fitz.Rect(max(u.x0 - 6, 40), u.y0 - 6, min(u.x1 + 6, page.rect.width - 40), y_box - 4)
    pix = page.get_pixmap(clip=clip, dpi=220)
    name = f"img_{key}.png"
    pix.save(out_dir / name)
    return name


def main(pdf, dataset, out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    doc, qs = parse(pdf)
    data = json.load(open(dataset))
    general = [d for d in data if "-" not in d["num"]]
    bystate = {}
    for d in data:
        if "-" in d["num"]:
            bystate.setdefault(d["num"].split("-")[0], []).append(d)

    result, problems = [], []
    for q in qs:
        if q["state"] not in (None, KEEP_STATE):
            continue
        key = f"{q['n']}" if q["state"] is None else f"{q['state']}-{q['n']}"
        question = re.sub(r"\s+", " ", " ".join(q["q"])).strip()
        credit = None
        if "©" in question:
            question, credit = [x.strip() for x in question.split("©", 1)]
            credit = "© " + credit
        if " In Anlehnung an " in question:
            question, credit = [x.strip() for x in question.split(" In Anlehnung an ", 1)]
            credit = "In Anlehnung an " + credit
        answers = [re.sub(r"\s+", " ", a).strip() for a in q["a"]]
        if len(answers) != 4:
            problems.append((key, "answers", answers))
        pool = general if q["state"] is None else bystate[q["state"]]
        # best candidate: question similarity + answer-set similarity
        def score(d):
            qs_ = SequenceMatcher(None, norm(question), norm(d["question"])).ratio()
            aset = sorted(norm(d[k]) for k in "abcd")
            as_ = SequenceMatcher(None, "|".join(sorted(map(norm, answers))), "|".join(aset)).ratio()
            return qs_ + as_
        best = max(pool, key=score)
        correct, exact = match_index(answers, best[best["solution"]])
        sim = SequenceMatcher(None, norm_seq(answers[correct]), norm_seq(best[best["solution"]])).ratio()
        if score(best) < 1.8 or (sim < 0.9 and not exact):
            problems.append((key, round(sim, 2), question[:70], "| OFFICIAL:", answers[correct], "| KEY:", best[best["solution"]]))
        en = best["translation"]["en"]
        # translation letters follow the dataset order; remap to official order
        letter_for = {}
        for k in "abcd":
            i, _ = match_index(answers, best[k])
            letter_for[i] = k
        if len(letter_for) != 4:
            problems.append((key, "ambiguous EN mapping", question[:70]))
        image = render_image(doc, q, out, key.replace("-", "_"))
        result.append(dict(
            id=key,
            number=q["n"],
            state=q["state"],
            question=question,
            answers=answers,
            correct=correct,
            image=image,
            credit=credit,
            topic="Nordrhein-Westfalen" if q["state"] else TOPICS[best.get("category", "").strip("'")],
            en=dict(
                question=en["question"],
                answers=[en.get(letter_for.get(i, "a"), "") for i in range(4)],
                explanation=en.get("context", ""),
            ),
        ))
    json.dump(dict(source="BAMF Gesamtfragenkatalog, Stand 07.05.2025", questions=result),
              open(out / "catalog.json", "w"), ensure_ascii=False, indent=1)
    print(f"{len(result)} questions, {sum(1 for r in result if r['image'])} with images")
    for p in problems:
        print("CHECK", p)


if __name__ == "__main__":
    main(*sys.argv[1:4])
