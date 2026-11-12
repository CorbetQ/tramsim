#!/usr/bin/env python3
"""Type et implantation des stations d'une ville (quais GTFS + géométrie des voies).

Types (data/stations/<ville>.json) :
- "lateral" : quais latéraux face à face (par défaut), portes à droite ;
- "central" : quai central entre les deux voies (même quai GTFS pour les deux sens, ou quais GTFS situés à gauche de
  leur voie quand le GTFS place les quais hors de l'axe), portes à gauche, entraxe élargi au droit du quai ;
- "offset"  : quais décalés, seulement si les quais GTFS des deux sens sont distants de plus de OFFSET_M le long de la voie ;
- "multi"   : au moins 3 quais tram GTFS (même parent_station ou même nom à moins de 300 m), ou pôle d'échange
  (zone d'arrêt GTFS d'au moins 6 quais tous modes) où des services de tram commencent ou finissent :
  quais latéraux + quai central, portes des deux côtés.
Les arrêts des deux sens sont recentrés sur le quai (rame centrée sur un quai de longueur platform_m = rame la plus
longue de la ville + 3 m) : station.offset (point d'arrêt du nez) est déplacé le long de la ligne dans data/networks.

Usage : stations.py CITY [GTFS_ROOT]   (puis merge_city.py, turnbacks.py, terrain.py --free)
"""
import csv, json, math, os, re, sys, unicodedata
from collections import defaultdict

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from terrain import Frame  # noqa: E402

GTFS_ROOT = os.environ.get("GTFS_CACHE", os.path.join(os.path.dirname(__file__), "..", "..", ".cache", "geography", "gtfs"))
OFFSET_M = 30.0
GROUP_M = 300.0
NOSE_MARGIN = 1.5


def norm(s):
    s = unicodedata.normalize("NFD", s.lower())
    return re.sub(r"[^a-z0-9]+", " ", "".join(c for c in s if unicodedata.category(c) != "Mn")).strip()


def platform_len(city):
    liv = json.load(open(os.path.join(ROOT, "data/rolling_stock/liveries.json"))).get(city, {})
    fam = json.load(open(os.path.join(ROOT, "data/rolling_stock/research.json")))["families"]
    names = set(liv.get("fleet", [])) | {liv.get("family", "citadis_302")}
    names |= {l["family"] for l in liv.get("lines", {}).values() if isinstance(l, dict) and "family" in l}
    L = max([float(fam.get(n, {}).get("length_m") or 32.0) for n in names] + [32.0])
    for l in liv.get("lines", {}).values():
        if isinstance(l, dict) and "length" in l:
            L = max(L, float(l["length"]))
    return round(L + 3.0, 1)


class Chain:
    """Suite d'arêtes d'un sens (approche, inter-stations) : abscisse cumulée, polyligne."""

    def __init__(self, edges):
        self.edges = edges
        self.start = {}
        acc = 0.0
        for e in edges:
            self.start[e["id"]] = acc
            acc += float(e["length"])
        self.total = acc
        pts, cum = [], []
        for e in edges:
            p = np.array(e["pts"], dtype=float)
            if len(p) < 2:
                continue
            seg = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(p, axis=0), axis=1))])
            k = float(e["length"]) / seg[-1] if seg[-1] > 0 else 1.0
            for q, s in zip(p, seg):
                pts.append(q); cum.append(self.start[e["id"]] + s * k)
        self.pts, self.cum = np.array(pts), np.array(cum)

    def xy(self, s):
        return np.array([np.interp(s, self.cum, self.pts[:, 0]), np.interp(s, self.cum, self.pts[:, 1])])

    def proj(self, q):
        """Abscisse et écart latéral (+ à droite du sens de marche) du point q."""
        a, b = self.pts[:-1], self.pts[1:]
        ab = b - a
        l2 = np.maximum(np.sum(ab * ab, 1), 1e-9)
        t = np.clip(np.sum((q - a) * ab, 1) / l2, 0, 1)
        p = a + ab * t[:, None]
        d = np.linalg.norm(p - q, axis=1)
        i = int(np.argmin(d))
        n = np.array([-ab[i][1], ab[i][0]]) / math.sqrt(l2[i])
        return self.cum[i] + (self.cum[i + 1] - self.cum[i]) * t[i], float(np.dot(q - p[i], n)), float(d[i])

    def locate(self, s):
        """(arête, abscisse) ; jamais à moins de 3 m du début d'une arête (le nez s'arrête alors en fin d'arête
        précédente, 2 m avant le nœud, comme les arrêts GTFS) : l'arrêt reste sur l'arête où la rame s'immobilise."""
        for k, e in enumerate(self.edges):
            st = self.start[e["id"]]
            if s <= st + float(e["length"]) + 1e-6:
                o = s - st
                if o < 3.0 and k > 0:
                    p = self.edges[k - 1]
                    return p["id"], round(max(0.0, float(p["length"]) - 2.0), 1)
                return e["id"], round(max(0.0, min(o, float(e["length"]) - 2.0)), 1)
        e = self.edges[-1]
        return e["id"], float(e["length"])


def chains_of(net):
    E = {e["id"]: e for e in net["edges"]}
    out_of = defaultdict(list)
    for e in net["edges"]:
        out_of[e["from"]].append(e)
    res = []
    for e in net["edges"]:
        if not e["id"].endswith("_appr"):
            continue
        ch, cur, seen = [e], e, {e["id"]}
        while True:
            nx = [x for x in out_of[cur["to"]] if not x["id"].endswith("_appr") and x["id"] not in seen and not x.get("raw")]
            if len(nx) != 1:
                break
            cur = nx[0]; seen.add(cur["id"]); ch.append(cur)
        res.append(Chain(ch))
    return res


def gtfs_tram_quays(city, root):
    d = os.path.join(root, city)
    rd = lambda n: csv.DictReader(open(os.path.join(d, n), encoding="utf-8-sig"))
    cat = {e["id"]: e for e in json.load(open(os.path.join(ROOT, "data/sources/gtfs_catalogue.json")))["networks"]}
    types = {str(t) for t in cat.get(city, {}).get("route_types", [0])} | {"900"}
    routes = {r["route_id"] for r in rd("routes.txt") if r.get("route_type", "").strip() in types}
    trips = {t["trip_id"] for t in rd("trips.txt") if t["route_id"] in routes}
    served = set()
    first, last = {}, {}
    with open(os.path.join(d, "stop_times.txt"), encoding="utf-8-sig") as f:
        r = csv.reader(f)
        h = next(r)
        it, ist, isq = h.index("trip_id"), h.index("stop_id"), h.index("stop_sequence")
        for row in r:
            t = row[it]
            if t in trips:
                served.add(row[ist])
                q = int(row[isq])
                if t not in first or q < first[t][0]: first[t] = (q, row[ist])
                if t not in last or q > last[t][0]: last[t] = (q, row[ist])
    stops = {s["stop_id"]: s for s in rd("stops.txt")}
    ends = defaultdict(int)
    for v in list(first.values()) + list(last.values()):
        ends[norm(stops.get(v[1], {}).get("stop_name", ""))] += 1
    return stops, served, ends


def main(city, root=GTFS_ROOT):
    L = platform_len(city)
    h = L / 2.0 - NOSE_MARGIN
    stops, served, ends = gtfs_tram_quays(city, root)
    nets = []
    for f in sorted(os.listdir(os.path.join(ROOT, "data/networks"))):
        if f.endswith(".json"):
            p = os.path.join(ROOT, "data/networks", f)
            d = json.load(open(p))
            if d.get("source_id") == city and d.get("origin"):
                nets.append((p, d))
    if not nets:
        raise SystemExit("aucune ligne pour " + city)
    cframe = Frame(*nets[0][1]["origin"])
    # positions des quais GTFS tram (repère ville)
    qpos = {}
    for sid in served:
        s = stops.get(sid)
        if s and s.get("stop_lat"):
            x, z = cframe.fwd(float(s["stop_lat"]), float(s["stop_lon"]))
            qpos[sid] = np.array([float(x), float(z)])
    # groupes : nom normalisé + proximité, enrichis des quais tram de même parent ou même nom
    groups = []
    def group_for(name, p):
        k = norm(name)
        for g in groups:
            if g["key"] == k and np.linalg.norm(g["c"] - p) < GROUP_M:
                return g
        g = {"key": k, "name": name, "c": p, "quays": set(), "pairs": [], "singles": [], "lats": []}
        groups.append(g)
        return g
    per_net = []
    for path, d in nets:
        nf = Frame(*d["origin"])
        to_city = lambda q, nf=nf: np.array(cframe.fwd(*nf.inv(q[0], q[1])), dtype=float)
        to_net = lambda q, nf=nf: np.array(nf.fwd(*cframe.inv(q[0], q[1])), dtype=float)
        chs = chains_of(d)
        where = {}
        for ci, c in enumerate(chs):
            for e in c.edges:
                where[e["id"]] = ci
        recs = []
        for si, s in enumerate(d["stations"]):
            ci = where.get(s["edge"])
            if ci is None:
                continue
            c = chs[ci]
            sc = c.start[s["edge"]] + float(s["offset"])
            g = group_for(s["name"], to_city(c.xy(sc)))
            g["quays"].add(s.get("stop_id", ""))
            recs.append({"si": si, "ci": ci, "s": sc, "g": g, "sid": s.get("stop_id", "")})
        for ci in range(len(chs)):   # arrêts voisins sur la chaîne (embranchements)
            seq = sorted([r for r in recs if r["ci"] == ci], key=lambda r: r["s"])
            for k, r in enumerate(seq):
                r["nb"] = frozenset(norm(d["stations"][o["si"]]["name"]) for o in (seq[k - 1] if k else None, seq[k + 1] if k + 1 < len(seq) else None) if o)
                r["g"].setdefault("nbs", set()).add(r["nb"])
        per_net.append((path, d, chs, recs, to_net))
    parent = defaultdict(set)
    for sid, s in stops.items():
        if s.get("parent_station"):
            parent[s["parent_station"]].add(sid)
    for g in groups:
        ext = set()
        for sid in list(g["quays"]):
            ps = stops.get(sid, {}).get("parent_station")
            if ps:
                ext |= {q for q in parent[ps] if q in served}
        for sid, p in qpos.items():
            if norm(stops[sid]["stop_name"]) == g["key"] and np.linalg.norm(p - g["c"]) < GROUP_M:
                ext.add(sid)
        g["quays"] = {q for q in g["quays"] | ext if q in qpos}
        # pôle d'échange : zone d'arrêt GTFS d'au moins 6 quais (tous modes) où des services de tram commencent ou finissent
        allq = set()
        for sid in g["quays"]:
            ps = stops.get(sid, {}).get("parent_station")
            if ps:
                allq |= parent[ps]
        # ... ou embranchement de lignes / variantes (arrêts voisins différents)
        g["hub"] = len(allq) >= 6 and (ends.get(g["key"], 0) >= 4 or len(g.get("nbs", ())) >= 2)
    # écart latéral des quais GTFS : informatif seulement si le GTFS ne place pas les quais sur le tracé
    all_lat = []
    for path, d, chs, recs, to_net in per_net:
        for r in recs:
            if r["sid"] in qpos:
                _, lat, dist = chs[r["ci"]].proj(to_net(qpos[r["sid"]]))
                r["lat"] = lat
                all_lat.append(abs(lat))
    lateral_info = bool(all_lat) and float(np.median(all_lat)) > 2.0
    # paires de sens opposés (même groupe) : chaîne partenaire = celle qui commence où finit l'autre
    for path, d, chs, recs, to_net in per_net:
        E = {e["id"]: e for e in d["edges"]}
        partner = {}
        for i, a in enumerate(chs):
            for j, b in enumerate(chs):
                if i != j and E[b.edges[0]["id"]]["from"] == a.edges[-1]["to"]:
                    partner[i] = j
        used = set()
        for r in recs:
            if id(r) in used:
                continue
            j = partner.get(r["ci"])
            best = None
            for o in recs:
                if o["ci"] == j and o["g"] is r["g"] and id(o) not in used and o is not r:
                    pa = chs[r["ci"]].xy(r["s"]); pb = chs[j].xy(o["s"])
                    dd = np.linalg.norm(pa - pb)
                    if dd < GROUP_M and (best is None or dd < best[0]):
                        best = (dd, o)
            if best is not None:
                used.add(id(r)); used.add(id(best[1]))
                r["g"]["pairs"].append((path, r, best[1]))
            else:
                r["g"]["singles"].append((path, r))
    # convention GTFS : quais au point d'arrêt du nez (écart systématique des deux sens) ou au milieu du quai
    deltas = []
    for g in groups:
        for path, a, b in g["pairs"]:
            d, chs, to_net = next((x[1], x[2], x[4]) for x in per_net if x[0] == path)
            qa, qb = qpos.get(a["sid"]), qpos.get(b["sid"])
            if qa is not None and qb is not None and a["sid"] != b["sid"]:
                c0 = chs[a["ci"]]
                deltas.append(c0.proj(to_net(qa))[0] - c0.proj(to_net(qb))[0])
    bias = float(np.median(deltas)) if deltas else 0.0
    if abs(bias) < 15.0:
        bias = 0.0
    # type de chaque groupe
    cand = {}
    for path, d, chs, recs, to_net in per_net:
        cand[path] = (d, chs, to_net)
    out = []
    stats = defaultdict(int)
    for g in groups:
        nq = 0   # quais tram le long d'une même paire de voies (lignes qui se croisent : quais comptés par axe)
        for path, a, b in g["pairs"] or [(p, r, r) for p, r in g["singles"]]:
            d, chs, to_net = cand[path]
            near = 0
            for c0, r in ((chs[a["ci"]], a), (chs[b["ci"]], b)):
                ref = c0.proj(to_net(qpos[r["sid"]]))[0] if r["sid"] in qpos else r["s"]
                n = 0
                for q in g["quays"]:
                    u, _, dist = c0.proj(to_net(qpos[q]))
                    n += dist < 20.0 and abs(u - ref) < 80.0
                near = max(near, n)
            nq = max(nq, near)
        kind = "lateral"
        if nq >= 3 or g["hub"]:
            kind = "multi"
        else:
            for path, a, b in g["pairs"]:
                d, chs, to_net = cand[path]
                qa, qb = qpos.get(a["sid"]), qpos.get(b["sid"])
                if a["sid"] == b["sid"] or (qa is not None and qb is not None and np.linalg.norm(qa - qb) < 2.5 and lateral_info):
                    kind = "central"; break
                if lateral_info and a.get("lat", 9) < -1.0 and b.get("lat", 9) < -1.0:
                    kind = "central"; break
                if qa is not None and qb is not None:
                    c0 = chs[a["ci"]]
                    ua = c0.proj(to_net(qa))[0]; ub = c0.proj(to_net(qb))[0]
                    if abs(ua - ub - bias) > OFFSET_M:
                        kind = "offset"
            if not g["pairs"] and lateral_info and all(r.get("lat", 9) < -1.0 for _, r in g["singles"]) and g["singles"]:
                kind = "central"
        g["kind"] = kind
        stats[kind] += 1
        # recentrage des arrêts sur le quai (paires) : nez à c + h dans chaque sens
        for path, a, b in g["pairs"]:
            d, chs, to_net = cand[path]
            ca, cb = chs[a["ci"]], chs[b["ci"]]
            ua_n = a["s"]
            ub_n = ca.proj(cb.xy(b["s"]))[0]
            qa, qb = qpos.get(a["sid"]), qpos.get(b["sid"])
            us = [ca.proj(to_net(q))[0] + sg * bias * 0.5 for q, sg in ((qa, -1.0), (qb, 1.0)) if q is not None]
            if len(us) == 1 or (qa is not None and qb is not None and a["sid"] == b["sid"]):
                us = [float(np.mean(us))]
            if kind == "multi" and nq >= 3:
                us = [ca.proj(to_net(qpos[q]))[0] for q in g["quays"]] or us
            if kind == "offset" or not us:
                continue
            c = float(np.mean(us))
            # bornes : rame entière sur la voie, pas au-delà des extrémités de chaque chaîne
            lo_a, hi_a = L + 1.0, ca.total - 2.0
            lo_b, hi_b = L + 1.0, cb.total - 2.0
            # nez A : s_a' = a.s + (c + h - ua_n) ; nez B : s_b' = b.s + (ub_n - (c - h))
            c_lo = max(lo_a - a["s"] + ua_n - h, b["s"] + ub_n + h - hi_b)
            c_hi = min(hi_a - a["s"] + ua_n - h, b["s"] + ub_n + h - lo_b)
            if c_lo > c_hi:
                continue
            c = min(max(c, c_lo), c_hi)
            na, nb = a["s"] + (c + h - ua_n), b["s"] + (ub_n - (c - h))
            if max(abs(na - a["s"]), abs(nb - b["s"])) > L + 5.0:
                continue   # appariement incohérent (ligne en boucle, sens non parallèles) : arrêts GTFS conservés
            for r, s_new in ((a, a["s"] + (c + h - ua_n)), (b, b["s"] + (ub_n - (c - h)))):
                st = d["stations"][r["si"]]
                old = (st["edge"], st["offset"])
                st["edge"], st["offset"] = chs[r["ci"]].locate(s_new)
                stats["arrêts_recentrés"] += old != (st["edge"], st["offset"])
                for m in d.get("missions", []):
                    if (m.get("start_edge"), m.get("start_offset")) == old and m.get("stops", [None])[0] == r["si"]:
                        m["start_edge"], m["start_offset"] = st["edge"], st["offset"]
        lat, lon = cframe.inv(*g["c"])
        door = {"lateral": "right", "offset": "right", "central": "left", "multi": "both"}[kind]
        out.append({"name": g["name"], "type": kind, "doors": door, "lat": round(float(lat), 6), "lon": round(float(lon), 6),
                    "quays": sorted(g["quays"])})
    for path, d, chs, recs, to_net in per_net:
        for m in d.get("missions", []):   # départ de mission = point d'arrêt de son premier arrêt
            if m.get("stops"):
                st = d["stations"][m["stops"][0]]
                m["start_edge"], m["start_offset"] = st["edge"], st["offset"]
        json.dump(d, open(path, "w"), ensure_ascii=False, separators=(",", ":"))
    os.makedirs(os.path.join(ROOT, "data/stations"), exist_ok=True)
    res = {"schema": 1, "city": city, "platform_m": L,
           "source": "Quais GTFS (stops.txt, parent_station, stop_times des lignes de tram) et tracés des lignes ; "
                     "tools/import/stations.py",
           "lateral_info": lateral_info, "gtfs_head_bias_m": round(bias, 1), "stations": sorted(out, key=lambda s: s["name"])}
    json.dump(res, open(os.path.join(ROOT, "data/stations", city + ".json"), "w"), ensure_ascii=False, indent=0)
    print(city, "quai", L, "m", dict(stats))


if __name__ == "__main__":
    main(*sys.argv[1:3])
