#!/usr/bin/env python3
"""Marque les arrêts de retournement des réseaux libres (data/free/<ville>.json) : tout arrêt où au moins
un service GTFS du tram commence ou se termine (terminus et terminus partiels) reçoit "turnback": true.
Ajoute à chacun de ces arrêts une vraie communication de voies : croisement en ciseaux (deux diagonales
"raw": true, déjà calées sur l'axe réel des voies, ±1,75 m) placé avant le quai, entre la voie du quai et
la voie opposée ; les arêtes traversées sont découpées et chaque nœud de communication est un aiguillage.
Les côtés de raccordement des diagonales ("from_side"/"to_side") sont écrits explicitement.
Usage : turnbacks.py data/sources/gtfs_catalogue.json GTFS_ROOT data/free"""
import csv, json, math, os, sys
from collections import Counter

TRACK_OFFSET = 1.75   # demi-entraxe (voir LineView.TRACK_OFFSET)
CLEAR_M = 55.0        # quai -> fin de communication : place pour la rame la plus longue
CROSS_M = 30.0        # longueur de la communication le long de la voie
SEARCH_M = 12.0       # écart d'axe maximal entre les deux voies


def plen(pts):
    return sum(math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1))


def at(pts, s):
    """Point et direction unitaire à l'abscisse géométrique s."""
    acc = 0.0
    for i in range(len(pts) - 1):
        seg = math.dist(pts[i], pts[i + 1])
        if acc + seg >= s or i == len(pts) - 2:
            u = 0.0 if seg == 0 else min(1.0, max(0.0, (s - acc) / seg))
            a, b = pts[i], pts[i + 1]
            d = ((b[0] - a[0]) / (seg or 1), (b[1] - a[1]) / (seg or 1))
            return (a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u), d
        acc += seg
    return tuple(pts[0]), (1.0, 0.0)


def cut(pts, s0, s1):
    out, acc = [at(pts, s0)[0]], 0.0
    for i in range(len(pts) - 1):
        acc += math.dist(pts[i], pts[i + 1])
        if s0 < acc < s1:
            out.append(tuple(pts[i + 1]))
    out.append(at(pts, s1)[0])
    return [[round(x, 2), round(z, 2)] for x, z in out]


class Geo:
    def __init__(self, e):
        self.e, self.pts = e, e["pts"]
        self.total = plen(self.pts)
        self.k = self.total / e["length"] if e["length"] > 0 else 1.0

    def axis(self, off):
        return at(self.pts, off * self.k)

    def real(self, off):
        (x, z), (dx, dz) = self.axis(off)
        return (x - dz * TRACK_OFFSET, z + dx * TRACK_OFFSET)


def project(p, d, edges, exclude):
    """Voie de sens opposé passant à moins de SEARCH_M de l'axe en p : (arête, abscisse de jeu)."""
    best, bd = None, SEARCH_M
    for e in edges:
        if e["id"] == exclude or e.get("raw") or len(e.get("pts", [])) < 2:
            continue
        pts, acc = e["pts"], 0.0
        g = None
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            seg = math.dist(a, b)
            if seg > 0:
                ux, uz = (b[0] - a[0]) / seg, (b[1] - a[1]) / seg
                u = min(seg, max(0.0, (p[0] - a[0]) * ux + (p[1] - a[1]) * uz))
                dist = math.dist(p, (a[0] + ux * u, a[1] + uz * u))
                if dist < bd and ux * d[0] + uz * d[1] < -0.8:
                    bd, best, g = dist, e, acc + u
            acc += seg
        if g is not None:
            best_g = g / (plen(pts) / e["length"])
    return (best, best_g) if best else (None, 0.0)


def split(net, e, offs):
    """Découpe l'arête e aux abscisses offs (croissantes) ; retourne (pièces, nœuds créés)."""
    g = Geo(e)
    cuts = [0.0] + offs + [e["length"]]
    nodes = [e["from"]] + [f"{e['id']}@{k}" for k in range(len(offs))] + [e["to"]]
    pieces = []
    for k in range(len(cuts) - 1):
        a, b = cuts[k], cuts[k + 1]
        ne = dict(e, id=f"{e['id']}|{k}", length=round(b - a, 1), **{"from": nodes[k], "to": nodes[k + 1]})
        ne["pts"] = cut(e["pts"], a * g.k, b * g.k)
        if "limits" in e:
            ne["limits"] = [[round(max(z[0], a) - a, 1), round(min(z[1], b) - a, 1), z[2]] for z in e["limits"] if z[1] > a and z[0] < b]
        pieces.append(ne)
    i = net["edges"].index(e)
    net["edges"][i:i + 1] = pieces
    for s in net["stations"]:
        if s["edge"] == e["id"]:
            k = max(j for j in range(len(cuts) - 1) if float(s["offset"]) >= cuts[j] or j == 0)
            s["edge"], s["offset"] = pieces[k]["id"], round(min(float(s["offset"]) - cuts[k], pieces[k]["length"]), 1)
    net["nodes"] += nodes[1:-1]
    return pieces, nodes[1:-1]


def side(h, ref):
    return 1 if h[0] * ref[0] + h[1] * ref[1] >= 0 else -1


def diagonal(net, did, a_node, b_node, pa, pb, ref_a, ref_b, lines):
    """pa, pb : fonctions t -> point réel des deux voies ; la diagonale passe de pa(0) à pb(1)."""
    pts = []
    for i in range(9):
        t = i / 8
        w = t * t * (3 - 2 * t)
        A, B = pa(t), pb(t)
        pts.append([round(A[0] * (1 - w) + B[0] * w, 2), round(A[1] * (1 - w) + B[1] * w, 2)])
    h0 = (pts[1][0] - pts[0][0], pts[1][1] - pts[0][1])
    h1 = (pts[-2][0] - pts[-1][0], pts[-2][1] - pts[-1][1])
    net["edges"].append({"id": did, "from": a_node, "to": b_node, "length": round(plen(pts), 1), "limit_kmh": 20, "grade": 0.0,
                         "pts": pts, "raw": True, "crossover": True, "lines": lines,
                         "from_side": side(h0, ref_a), "to_side": side(h1, ref_b)})


def add_crossovers(net, names):
    placed = []
    by_id = lambda i: next((e for e in net["edges"] if e["id"] == i), None)
    outs = Counter(e["from"] for e in net["edges"])
    plats = sorted((s for s in net["stations"] if s["name"] in names), key=lambda s: outs[by_id(s["edge"])["to"]] > 0)
    for s in plats:
        E0 = by_id(s["edge"])
        if E0 is None or E0.get("raw") or len(E0.get("pts", [])) < 2:
            continue
        pq = Geo(E0).axis(float(s["offset"]))[0]
        if any(n == s["name"] and math.dist(q, pq) < 400 for n, q in placed):
            continue
        found = None
        for D in range(int(CLEAR_M), 400, 10):  # au plus près du quai, en reculant si la place manque
            E, pos, rem = E0, float(s["offset"]), float(D)
            while E is not None and rem > pos:
                rem -= pos
                ins = [e for e in net["edges"] if e["to"] == E["from"]]
                E = ins[0] if len(ins) == 1 and not ins[0].get("raw") and len(ins[0].get("pts", [])) >= 2 else None
                pos = E["length"] if E else 0.0
            if E is None:
                break
            o2 = pos - rem
            o1 = o2 - CROSS_M
            if o1 < 5.0:
                continue
            gx = Geo(E)
            (p1, d1), (p2, d2) = gx.axis(o1), gx.axis(o2)
            F, g1 = project(p1, d1, net["edges"], E["id"])
            F2, g2 = project(p2, d2, net["edges"], E["id"])
            if F is not None and F is F2 and 5.0 <= g2 < g1 - 10.0 <= F["length"] - 15.0:
                found = (E, o1, o2, gx, p1, d1, d2, F, g1, g2)
                break
        if not found:
            continue
        E, o1, o2, gx, p1, d1, d2, F, g1, g2 = found
        gf = Geo(F)
        ref_y1, ref_y2 = gf.axis(g1)[1], gf.axis(g2)[1]
        (xa, xb, xc), (x1, x2) = split(net, E, [round(o1, 1), round(o2, 1)])
        (fa, fb, fc), (y2, y1) = split(net, F, [round(g2, 1), round(g1, 1)])
        lines = sorted(set(E.get("lines", [])) | set(F.get("lines", [])))
        ox = lambda t: gx.real(o1 + (o2 - o1) * t)
        of = lambda t: gf.real(g1 + (g2 - g1) * t)
        base = f"X:{E['id']}"
        diagonal(net, base + ":1", x1, y2, ox, of, d1, ref_y2, lines)
        diagonal(net, base + ":2", y1, x2, of, ox, ref_y1, d2, lines)
        net.setdefault("crossovers", []).append({"station": s["name"], "nodes": [x1, x2, y1, y2], "edges": [base + ":1", base + ":2"]})
        placed.append((s["name"], pq))
    sw = set(net.get("switches", []))
    for c in net.get("crossovers", []):
        sw |= set(c["nodes"])
    net["switches"] = sorted(sw)
    return {n for n, _ in placed}

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
    if not net.get("crossovers"):  # idempotent : communications ajoutées une seule fois (après merge_city)
        ok = add_crossovers(net, keep)
        miss = sorted(keep - ok)
        if miss:
            print("  sans communication :", ", ".join(miss))
    json.dump(net, open(fp, "w"), ensure_ascii=False, separators=(",", ":"))
    print(e["id"], len(keep), "arrêts de retournement,", len(net.get("crossovers", [])), "communications")
