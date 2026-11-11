#!/usr/bin/env python3
"""Réseau complet d'une ville pour le mode libre : toutes les lignes fusionnées dans le repère de la ville.

- Les arêtes de chaque ligne sont reprojetées dans le repère de la première ligne (origine lat/lon).
- Les nœuds proches (< MERGE_M) dont les voies entrantes ou sortantes vont dans la même direction sont fusionnés :
  là où deux lignes se séparent ou se rejoignent apparaît un aiguillage (plusieurs arêtes sortantes).
- Les arêtes doublons (même départ, même arrivée après fusion) sont supprimées ; chaque arête garde la liste
  des lignes qui l'empruntent.
- Les stations homonymes proches sont dédoublonnées.
- Pas de rebroussement artificiel aux terminus : l'approche de chaque sens part d'un heurtoir (nœud "_pre"),
  le retournement se fait par changement de cabine et communication de voies (ajoutées par turnbacks.py).
Usage : merge_city.py CITY_ID NETWORKS_DIR OUT.json
"""
import json, math, os, sys
from collections import defaultdict

MERGE_M = 25.0
R = 6371008.8


class Frame:
    def __init__(self, lat0, lon0):
        self.lat0, self.lon0, self.k = lat0, lon0, math.cos(math.radians(lat0))

    def fwd(self, lat, lon):
        return (math.radians(lon - self.lon0) * R * self.k, -math.radians(lat - self.lat0) * R)

    def inv(self, x, z):
        return (self.lat0 - math.degrees(z / R), self.lon0 + math.degrees(x / (R * self.k)))


def heading(p, q):
    return math.atan2(q[1] - p[1], q[0] - p[0])


def angle_diff(a, b):
    d = abs(a - b) % (2 * math.pi)
    return min(d, 2 * math.pi - d)


def main(city, nets_dir, out):
    nets = [json.load(open(os.path.join(nets_dir, f))) for f in sorted(os.listdir(nets_dir)) if f.endswith(".json")]
    nets = [n for n in nets if n.get("source_id") == city and n.get("origin")]
    if not nets:
        raise SystemExit(f"aucune ligne pour {city}")
    frame = Frame(*nets[0]["origin"])
    edges, stations = [], []
    node_pos, node_in, node_out = {}, defaultdict(list), defaultdict(list)
    for n in nets:
        nf = Frame(*n["origin"])
        tag = n["id"]
        tr = lambda p: list(frame.fwd(*nf.inv(p[0], p[1])))
        for e in n["edges"]:
            pts = [tr(p) for p in e.get("pts", [])]
            ne = dict(e)
            ne["id"] = f"{tag}:{e['id']}"
            ne["from"] = f"{tag}:{e['from']}"
            if e["id"].endswith("_appr"):  # heurtoir après le quai au lieu de la boucle vers l'autre sens
                ne["from"] = f"{tag}:{e['id'][:-4]}pre"
            ne["to"] = f"{tag}:{e['to']}"
            ne["pts"] = [[round(x, 2), round(z, 2)] for x, z in pts]
            ne["lines"] = [n["line"]]
            edges.append(ne)
            if len(pts) >= 2:
                node_pos[ne["from"]] = pts[0]
                node_pos[ne["to"]] = pts[-1]
                node_out[ne["from"]].append(heading(pts[0], pts[min(1, len(pts) - 1)]))
                node_in[ne["to"]].append(heading(pts[-2], pts[-1]))
        for s in n["stations"]:
            stations.append(dict(s, edge=f"{tag}:{s['edge']}", lines=[n["line"]]))
    # union-find : fusion des nœuds proches de même orientation
    parent = {k: k for k in node_pos}

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def head_of(k):
        hs = node_in.get(k) or node_out.get(k) or []
        return hs[0] if hs else None

    keys = sorted(node_pos)
    grid = defaultdict(list)
    for k in keys:
        x, z = node_pos[k]
        grid[(int(x // MERGE_M), int(z // MERGE_M))].append(k)
    for k in keys:
        x, z = node_pos[k]
        gx, gz = int(x // MERGE_M), int(z // MERGE_M)
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for o in grid[(gx + dx, gz + dz)]:
                    if o <= k or k.split(":")[0] == o.split(":")[0]:
                        continue
                    if k.endswith("_pre") != o.endswith("_pre"):
                        continue  # un heurtoir ne se raccorde qu'à un autre heurtoir
                    if math.dist(node_pos[k], node_pos[o]) > MERGE_M:
                        continue
                    ha, hb = head_of(k), head_of(o)
                    if ha is not None and hb is not None and angle_diff(ha, hb) > math.radians(50):
                        continue  # voies de sens opposés : pas de raccordement
                    parent[find(o)] = find(k)
    for e in edges:
        if e["from"] in parent: e["from"] = find(e["from"])
        if e["to"] in parent: e["to"] = find(e["to"])
    # doublons : même départ et même arrivée -> une seule arête (lignes cumulées)
    seen, kept, alias = {}, [], {}
    for e in edges:
        key = (e["from"], e["to"])
        if key in seen and e["from"] != e["to"]:
            k0 = seen[key]
            for l in e["lines"]:
                if l not in k0["lines"]: k0["lines"].append(l)
            alias[e["id"]] = k0["id"]
            continue
        if e["from"] == e["to"]:
            alias[e["id"]] = None
            continue
        seen[key] = e
        kept.append(e)
    # stations : réattachées aux arêtes conservées, dédoublonnées par nom et proximité
    st_out, st_seen = [], {}
    for s in stations:
        eid = alias.get(s["edge"], s["edge"])
        if eid is None:
            continue
        key = (s["name"], eid)
        if key in st_seen:
            for l in s["lines"]:
                if l not in st_seen[key]["lines"]: st_seen[key]["lines"].append(l)
            continue
        elen = next(e["length"] for e in kept if e["id"] == eid) if eid != s["edge"] else None
        s = dict(s, edge=eid)
        if elen is not None:
            s["offset"] = round(min(float(s["offset"]), max(0.0, elen - 2.0)), 1)
        st_seen[key] = s
        st_out.append(s)
    nodes = sorted({e["from"] for e in kept} | {e["to"] for e in kept})
    outdeg = defaultdict(int)
    for e in kept: outdeg[e["from"]] += 1
    switches = [n for n in nodes if outdeg[n] > 1]
    city_name = nets[0]["city"]
    res = {"schema": 1, "id": f"{city}_libre", "city": city_name, "line": "réseau complet", "long_name": "Toutes les lignes (mode libre)",
           "kind": "free", "free_only": True, "origin": nets[0]["origin"], "source_id": city, "color": nets[0].get("color", "#c8102e"),
           "provisional": False, "provenance": "Fusion des lignes de la ville (tools/import/merge_city.py) ; raccordements entre lignes "
           "déduits de la proximité des arrêts communs (estimés, pas les vrais appareils de voie).",
           "estimated": ["aiguillages entre lignes : position déduite des arrêts communs"] + [x for x in nets[0].get("estimated", []) if "rebroussement" not in x],
           "supply": nets[0].get("supply", "overhead"), "guidance": nets[0].get("guidance", "steel"),
           "nodes": nodes, "edges": kept, "stations": st_out, "signals": [], "roads": [], "missions": [],
           "switches": switches, "lines": sorted({n["line"] for n in nets})}
    with open(out, "w", encoding="utf-8") as f:
        json.dump(res, f, ensure_ascii=False, separators=(",", ":"))
    print(f"{city}: {len(nets)} lignes -> {len(kept)} arêtes, {len(st_out)} stations, {len(switches)} aiguillages")


if __name__ == "__main__":
    main(*sys.argv[1:4])
