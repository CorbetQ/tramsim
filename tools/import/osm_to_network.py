#!/usr/bin/env python3
"""Convertit une réponse Overpass (JSON `out body geom;`/`out body; >; out skel qt;`) en réseau JSON (schéma 1).

Hypothèses documentées (à valider réseau par réseau) :
 - chaque way railway=tram est une voie bidirectionnelle => deux arêtes orientées (_f, _r) ;
 - les nœuds partagés par >=3 extrémités/passages de ways, ou extrémités de way, deviennent des noeuds du graphe ;
 - stations : nœuds railway=tram_stop / public_transport=stop_position, projetées sur l'arête la plus proche.
Usage : osm_to_network.py overpass.json out.json --id angers_a --city Angers --line A --supply overhead
"""
import argparse, json, math, sys
from collections import defaultdict


def haversine(a, b):
    R = 6371008.8
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * R * math.asin(math.sqrt(h))


def build(osm, args):
    nodes = {e["id"]: e for e in osm["elements"] if e["type"] == "node"}
    ways = [e for e in osm["elements"] if e["type"] == "way" and e.get("tags", {}).get("railway") in ("tram", "light_rail")]
    if not ways:
        raise SystemExit("aucune voie tram dans l'extrait")
    use = defaultdict(int)
    for w in ways:
        for i, n in enumerate(w["nodes"]):
            use[n] += 2 if i in (0, len(w["nodes"]) - 1) else 1
    cut = {n for n, c in use.items() if c >= 3}
    for w in ways:
        cut.update((w["nodes"][0], w["nodes"][-1]))
    edges, pos_of = [], {}
    for w in ways:
        seg = [w["nodes"][0]]
        for n in w["nodes"][1:]:
            seg.append(n)
            if n in cut:
                pts = [(nodes[k]["lat"], nodes[k]["lon"]) for k in seg]
                length = sum(haversine(pts[i], pts[i + 1]) for i in range(len(pts) - 1))
                if length > 0.5:
                    tags = w.get("tags", {})
                    ms = tags.get("maxspeed", "")
                    lim = int(ms) if ms.isdigit() else args.default_limit
                    edges.append({"from": seg[0], "to": seg[-1], "length": round(length, 1), "limit_kmh": lim,
                                  "grade": 0.0, "pts": pts, "way": w["id"]})
                seg = [n]
    out_edges = []
    for i, e in enumerate(edges):
        out_edges.append({"id": f"w{e['way']}_{i}_f", "from": f"N{e['from']}", "to": f"N{e['to']}", "length": e["length"],
                          "limit_kmh": e["limit_kmh"], "grade": 0.0, "_pts": e["pts"]})
        out_edges.append({"id": f"w{e['way']}_{i}_r", "from": f"N{e['to']}", "to": f"N{e['from']}", "length": e["length"],
                          "limit_kmh": e["limit_kmh"], "grade": 0.0, "_pts": list(reversed(e["pts"]))})
    stations = []
    for n in nodes.values():
        t = n.get("tags", {})
        if t.get("railway") == "tram_stop" or t.get("public_transport") == "stop_position":
            p = (n["lat"], n["lon"])
            best = None
            for e in out_edges:
                if not e["id"].endswith("_f"):
                    continue
                acc = 0.0
                for a, b in zip(e["_pts"], e["_pts"][1:]):
                    seg = haversine(a, b)
                    # projection plane locale sur le segment [a,b]
                    k = math.cos(math.radians(a[0]))
                    ax, ay = 0.0, 0.0
                    bx, by = (b[1] - a[1]) * k, b[0] - a[0]
                    px, py = (p[1] - a[1]) * k, p[0] - a[0]
                    den = bx * bx + by * by
                    u = 0.0 if den == 0 else max(0.0, min(1.0, (px * bx + py * by) / den))
                    q = (a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u)
                    d = haversine(q, p)
                    if best is None or d < best[0] - 1e-6:
                        best = (d, e["id"], acc + seg * u)
                    acc += seg
            if best and best[0] < args.snap_m:
                stations.append({"name": t.get("name", f"stop_{n['id']}"), "edge": best[1], "offset": round(best[2], 1), "dwell_s": 25,
                                 "snap_m": round(best[0], 1)})
    for e in out_edges:
        e.pop("_pts", None)
    return {"schema": 1, "id": args.id, "city": args.city, "line": args.line, "provisional": False,
            "provenance": f"OpenStreetMap (ODbL), extrait {args.osm_date}", "supply": args.supply, "guidance": args.guidance,
            "nodes": sorted({e["from"] for e in out_edges} | {e["to"] for e in out_edges}),
            "edges": out_edges, "stations": stations, "signals": [], "roads": []}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("overpass"); ap.add_argument("out")
    ap.add_argument("--id", required=True); ap.add_argument("--city", required=True); ap.add_argument("--line", required=True)
    ap.add_argument("--supply", default="overhead"); ap.add_argument("--guidance", default="steel")
    ap.add_argument("--default-limit", type=int, default=50); ap.add_argument("--snap-m", type=float, default=30.0)
    ap.add_argument("--osm-date", default="inconnue")
    a = ap.parse_args()
    net = build(json.load(open(a.overpass)), a)
    json.dump(net, open(a.out, "w"), indent=1, ensure_ascii=False)
    print(f"{len(net['edges'])} arêtes, {len(net['stations'])} stations -> {a.out}")
