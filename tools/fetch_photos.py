"""Render the third-party photos used by picture questions from the official BAMF PDF.

Five picture questions show press photos (© Deutscher Bundestag / © Bundesregierung).
They are not redistributed in this repository; this script recreates them locally
from the official catalog before you build.

usage: python fetch_photos.py [katalog.pdf]
       (downloads the PDF from bamf.de when no path is given)
"""
import json
import sys
import tempfile
import urllib.request
from pathlib import Path

import fitz

sys.path.insert(0, str(Path(__file__).parent))
from build_catalog import parse, render_image  # noqa: E402

PDF_URL = (
    "https://www.bamf.de/SharedDocs/Anlagen/DE/Integration/Einbuergerung/"
    "gesamtfragenkatalog-lebenindeutschland.pdf?__blob=publicationFile"
)
ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Sources" / "EinbuergerungTrainer" / "Resources"
MAX_SIDE = 1100  # longest side, in pixels


def photo_questions():
    """Picture questions whose image carries a © credit, from catalog.json."""
    catalog = json.loads((RESOURCES / "catalog.json").read_text())["questions"]
    return [q for q in catalog if q["image"] and (q.get("credit") or "").startswith("©")]


def download(dest: Path) -> Path:
    print(f"Downloading official catalog from bamf.de …")
    req = urllib.request.Request(PDF_URL, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=60) as r, open(dest, "wb") as f:
        f.write(r.read())
    return dest


def main(pdf_path=None):
    wanted = {q["id"]: q["image"] for q in photo_questions()}
    with tempfile.TemporaryDirectory() as tmp:
        pdf = Path(pdf_path) if pdf_path else download(Path(tmp) / "katalog.pdf")
        doc, parsed = parse(str(pdf))
        done = []
        for q in parsed:
            key = f"{q['n']}" if q["state"] is None else f"{q['state']}-{q['n']}"
            if key not in wanted:
                continue
            name = render_image(doc, q, Path(tmp), key.replace("-", "_"))
            if name != wanted[key]:
                sys.exit(f"Could not find the picture for question {key} in the PDF.")
            pix = fitz.Pixmap(str(Path(tmp) / name))
            scale = MAX_SIDE / max(pix.width, pix.height)
            if scale < 1:
                pix = fitz.Pixmap(pix, round(pix.width * scale), round(pix.height * scale), None)
            pix.save(str(RESOURCES / name))
            done.append(key)

    missing = sorted(set(wanted) - set(done))
    if missing:
        sys.exit(f"Missing photos for questions: {', '.join(missing)}")
    print(f"Rendered {len(done)} photos into {RESOURCES.relative_to(ROOT)}: {', '.join(done)}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
