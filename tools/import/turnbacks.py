#!/usr/bin/env python3
"""Marque les arrêts de retournement des réseaux libres (data/free/<ville>.json) : tout arrêt où au moins
un service GTFS du tram commence ou se termine (terminus et terminus partiels) reçoit "turnback": true.
Usage : turnbacks.py data/sources/gtfs_catalogue.json GTFS_ROOT data/free"""
import csv, json, os, sys
from collections import Counter

cat = json.load(open(sys.argv[1]))
for e in cat["networks"]:
    if e.get("skip"):
        continue
    d = os.path.join(sys.argv[2], e["id"]); fp = os.path.join(sys.argv[3], e["id"] + ".json")
    if not (os.path.exists(os.path.join(d, "routes.txt")) and os.path.exists(fp)):
        continue
    types = {str(t) for t in e.get("route_types", [0])} | {"900"}
    rd = lambda n: csv.DictReader(open(os.path.join(d, n), encoding="utf-8-sig"))
    routes = {r["route_id"] for r in rd("routes.txt") if r.get("route_type", "").strip() in types}
    trips = {t["trip_id"] for t in rd("trips.txt") if t["route_id"] in routes}
    names = {s["stop_id"]: s["stop_name"].strip() for s in rd("stops.txt")}
    first, last = {}, {}
    for r in rd("stop_times.txt"):
        t = r["trip_id"]
        if t not in trips:
            continue
        q = int(r["stop_sequence"])
        if t not in first or q < first[t][0]: first[t] = (q, r["stop_id"])
        if t not in last or q > last[t][0]: last[t] = (q, r["stop_id"])
    ends = Counter(names.get(v[1], "") for v in list(first.values()) + list(last.values()))
    keep = {n for n, c in ends.items() if c >= 4}   # au moins quelques services : vrai point de retournement
    net = json.load(open(fp))
    k = 0
    for s in net["stations"]:
        s["turnback"] = s["name"] in keep
        k += s["turnback"]
    net["turnback_stations"] = sorted(keep)
    json.dump(net, open(fp, "w"), ensure_ascii=False, separators=(",", ":"))
    print(e["id"], len(keep), "arrêts de retournement")
