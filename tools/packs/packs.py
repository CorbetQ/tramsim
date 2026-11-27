"""Packs de ville (P4) : filtre d'exclusion du preset Android et inventaire des tailles.
  python3 tools/packs/packs.py filters   # réécrit exclude_filter du preset « Android » (export_presets.cfg)
  python3 tools/packs/packs.py sizes     # tailles brutes par ville (données + modèles importés) et du paquet de base
Les fichiers exclus sont ceux que tools/packs/build_packs.gd met dans les packs (mêmes motifs)."""
import json, re, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
BASE_EXCLUDE = "override.cfg, tests/*, tools/*, docs/*, data/geography/*, build/*, .github/*, data/audio/reference/*"


def cities():
    return sorted(p.stem for p in (ROOT / "data/scenes").glob("*.json") if "_" not in p.stem)


def packed():
    base = json.loads((ROOT / "data/packs/base.json").read_text())["cities"]
    return [c for c in cities() if c not in base]


def patterns(c):
    return [f"data/scenes/{c}.*", f"data/scenes/{c}_*", f"data/free/{c}.*", f"data/free/{c}_*", f"assets/models/{c}/*"]


def filters():
    p = ROOT / "export_presets.cfg"; s = p.read_text()
    pats = ", ".join(x for c in packed() for x in patterns(c))
    head, sep, rest = s.partition('name="Android"')
    rest = re.sub(r'^exclude_filter=".*"$', f'exclude_filter="{BASE_EXCLUDE}, {pats}"', rest, count=1, flags=re.M)
    p.write_text(head + sep + rest)
    print("Android : %d villes en packs, %d motifs exclus" % (len(packed()), len(pats.split(", "))))


def size(c):
    n = 0
    for d in ("data/scenes", "data/free"):
        for f in (ROOT / d).glob(f"{c}*"):
            if f.stem == c or f.name.startswith(c + "_") or f.name.startswith(c + "."): n += f.stat().st_size
    for f in (ROOT / "assets/models" / c).glob("*.import") if (ROOT / "assets/models" / c).exists() else []:
        m = re.search(r'^path="res://(.+?)"', f.read_text(), re.M)
        if m and (ROOT / m.group(1)).exists(): n += (ROOT / m.group(1)).stat().st_size
    return n


def sizes():
    tot = 0
    for c in cities():
        s = size(c); tot += s if c in packed() else 0
        print(f"{c:14s} {s / 1048576:7.1f} Mo {'pack' if c in packed() else 'base'}")
    print(f"packs : {tot / 1048576:.1f} Mo")


if __name__ == "__main__":
    {"filters": filters, "sizes": sizes}[sys.argv[1]]()
