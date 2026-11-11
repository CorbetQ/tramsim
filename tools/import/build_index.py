#!/usr/bin/env python3
"""Génère data/index.json (catalogue léger lu par le menu) à partir de data/networks/*.json."""
import json, os, sys

root = sys.argv[1] if len(sys.argv) > 1 else "data"
out = []
for f in sorted(os.listdir(os.path.join(root, "networks"))):
    if not f.endswith(".json"):
        continue
    d = json.load(open(os.path.join(root, "networks", f), encoding="utf-8"))
    out.append({"id": d["id"], "city": d["city"], "line": d["line"], "long_name": d.get("long_name", ""),
                "path": "res://data/networks/" + f, "kind": d.get("kind", "tram"), "guidance": d.get("guidance", "steel"),
                "supply": d.get("supply", "overhead"), "stations": len(d.get("stations", [])),
                "length_km": round(sum(e["length"] for e in d["edges"]) / 2000.0, 1), "missions": len(d.get("missions", []))})
out.sort(key=lambda x: (x["city"], x["id"]))
json.dump({"schema": 1, "networks": out}, open(os.path.join(root, "index.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)
print(len(out), "entrées ->", os.path.join(root, "index.json"))
