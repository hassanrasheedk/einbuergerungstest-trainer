#!/bin/sh
# Recreate the five © press photos from the official BAMF PDF (not stored in git).
# Usage: tools/fetch_photos.sh [path/to/katalog.pdf]
set -e
cd "$(dirname "$0")/.."
if [ ! -x .venv/bin/python ]; then
  python3 -m venv .venv
  .venv/bin/pip install --quiet --disable-pip-version-check pymupdf
fi
.venv/bin/python tools/fetch_photos.py "$@"
