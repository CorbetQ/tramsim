#!/usr/bin/env python3
"""Télécharge les GTFS du catalogue dans DEST/<id>/ (un dossier vide par source, contenu non fiable).
Usage : fetch_gtfs.py data/sources/gtfs_catalogue.json DEST [id ...]"""
import json, os, subprocess, sys, zipfile


def fetch(entry, dest):
    d = os.path.join(dest, entry["id"])
    os.makedirs(d, exist_ok=True)
    z = os.path.join(d, "gtfs.zip")
    if not os.path.exists(z):
        r = subprocess.run(["curl", "-sSL", "--fail", "-m", "600", "-o", z, entry["url"]], capture_output=True, text=True)
        if r.returncode != 0:
            if os.path.exists(z):
                os.remove(z)
            return f"échec téléchargement: {r.stderr.strip()[:200]}"
    try:
        with zipfile.ZipFile(z) as f:
            for n in f.namelist():
                base = os.path.basename(n)
                if base.endswith(".txt") and base in ("routes.txt", "trips.txt", "stops.txt", "stop_times.txt", "shapes.txt", "agency.txt", "feed_info.txt"):
                    with f.open(n) as src, open(os.path.join(d, base), "wb") as out:
                        out.write(src.read())
    except zipfile.BadZipFile:
        return "archive invalide"
    return "ok"


if __name__ == "__main__":
    cat = json.load(open(sys.argv[1]))
    only = set(sys.argv[3:])
    for e in cat["networks"]:
        if not only or e["id"] in only:
            print(e["id"], fetch(e, sys.argv[2]), flush=True)
