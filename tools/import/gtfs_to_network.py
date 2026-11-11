#!/usr/bin/env python3
"""Construit un réseau jouable (schéma 1) pour UNE ligne de tram à partir d'un GTFS.

Source de vérité : shapes.txt (tracé), stops.txt (arrêts), stop_times.txt (horaires, temps d'arrêt).
Méthode :
 - pour chaque sens, le tracé le plus fréquent (shape_id) est retenu ; les autres variantes sont ignorées ;
 - les arrêts du trajet type sont projetés sur le tracé dans l'ordre (abscisse croissante) ;
 - une arête par inter-station ; une courte arête d'approche avant le premier arrêt de chaque sens ;
 - aux terminus, la fin d'un sens est raccordée à l'approche du sens inverse (rebroussement simplifié) ;
 - limites : 50 km/h par défaut, réduites selon le rayon de courbure mesuré sur le tracé (a_lat 0,9 m/s²) ;
 - pentes : 0 (pas de MNT importé) — signalé `grade_estimated` ;
 - missions : quelques services réels (heures de départ GTFS), en secondes relatives au premier départ + 60 s.
Usage : gtfs_to_network.py GTFS_DIR ROUTE_ID OUT.json --id angers_a --city Angers --source-date 2026-10-24
"""
import argparse, csv, json, math, os
from collections import Counter, defaultdict

APPROACH_M = 60.0
STOP_BACK_M = 2.0      # le nez de la rame s'arrête 2 m avant le nœud
DEFAULT_LIMIT = 50
MIN_LIMIT = 15
A_LAT = 0.9
MAX_SHAPE_GAP = 50.0   # écart arrêt/tracé au-delà duquel le tracé est jugé incohérent


def rd(d, name):
    with open(os.path.join(d, name), encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def hms(t):
    h, m, s = (int(x) for x in t.split(":"))
    return h * 3600 + m * 60 + s


class Proj:
    """Projection équirectangulaire locale en mètres : x vers l'est, z vers le sud (repère Godot)."""
    def __init__(self, lat0, lon0):
        self.lat0, self.lon0 = lat0, lon0
        self.k = math.cos(math.radians(lat0))

    def __call__(self, lat, lon):
        R = 6371008.8
        return (math.radians(lon - self.lon0) * R * self.k, -math.radians(lat - self.lat0) * R)


def dist(a, b):
    return math.hypot(b[0] - a[0], b[1] - a[1])


def cumulative(pts):
    c = [0.0]
    for a, b in zip(pts, pts[1:]):
        c.append(c[-1] + dist(a, b))
    return c


def project(pts, cum, p, s_min):
    """Projection de p sur la polyligne, abscisse >= s_min. Retourne (abscisse, écart)."""
    best = None
    for i in range(len(pts) - 1):
        if cum[i + 1] < s_min:
            continue
        a, b = pts[i], pts[i + 1]
        dx, dz = b[0] - a[0], b[1] - a[1]
        L2 = dx * dx + dz * dz
        u = 0.0 if L2 == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / L2))
        s = cum[i] + u * math.sqrt(L2)
        if s < s_min:
            continue
        q = (a[0] + u * dx, a[1] + u * dz)
        d = dist(q, p)
        if best is None or d < best[1] - 1e-9:
            best = (s, d)
    return best


def point_at(pts, cum, s):
    s = max(0.0, min(cum[-1], s))
    for i in range(len(pts) - 1):
        if cum[i + 1] >= s:
            seg = cum[i + 1] - cum[i]
            u = 0.0 if seg == 0 else (s - cum[i]) / seg
            return (pts[i][0] + u * (pts[i + 1][0] - pts[i][0]), pts[i][1] + u * (pts[i + 1][1] - pts[i][1]))
    return pts[-1]


def sub_polyline(pts, cum, s0, s1, step=5.0):
    out = [point_at(pts, cum, s0)]
    for i, c in enumerate(cum):
        if s0 < c < s1 and dist(out[-1], pts[i]) >= step:
            out.append(pts[i])
    end = point_at(pts, cum, s1)
    if dist(out[-1], end) > 0.01:
        out.append(end)
    return out


def min_radius(poly, span=15.0):
    """Rayon de courbure minimal (m) mesuré sur des triplets espacés d'environ `span` mètres."""
    if len(poly) < 3:
        return math.inf
    cum = cumulative(poly)
    best = math.inf
    s = span
    while s + span <= cum[-1]:
        a, b, c = point_at(poly, cum, s - span), point_at(poly, cum, s), point_at(poly, cum, s + span)
        ab, bc, ca = dist(a, b), dist(b, c), dist(c, a)
        area2 = abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))
        if area2 > 1e-6:
            best = min(best, ab * bc * ca / (2.0 * area2))
        s += span / 3.0
    return best


def curve_zones(poly, span=25.0, step=5.0, margin=15.0):
    """Zones [début, fin, km/h] autour des courbes dont la vitesse admissible < 50 km/h."""
    cum = cumulative(poly)
    if cum[-1] < 2 * span:
        return []
    raw = []
    s = span
    while s + span <= cum[-1]:
        a, b, c = point_at(poly, cum, s - span), point_at(poly, cum, s), point_at(poly, cum, s + span)
        ab, bc, ca = dist(a, b), dist(b, c), dist(c, a)
        area2 = abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))
        if area2 > 1e-6:
            r = ab * bc * ca / (2.0 * area2)
            lim = max(MIN_LIMIT, int(math.sqrt(A_LAT * r) * 3.6))
            if lim < DEFAULT_LIMIT:
                raw.append([max(0.0, s - margin), min(cum[-1], s + margin), lim])
        s += step
    zones = []
    for z in raw:
        if zones and z[0] <= zones[-1][1]:
            zones[-1][1] = max(zones[-1][1], z[1]); zones[-1][2] = min(zones[-1][2], z[2])
        else:
            zones.append(z)
    return [[round(a, 1), round(b, 1), v] for a, b, v in zones]


class Feed:
    """Tables GTFS utiles, chargées une fois (stop_times filtré sur les routes demandées)."""
    def __init__(self, gtfs, route_ids):
        self.dir = gtfs
        self.stops = {s["stop_id"]: s for s in rd(gtfs, "stops.txt")}
        self.routes = {r["route_id"]: r for r in rd(gtfs, "routes.txt")}
        self.trips = [t for t in rd(gtfs, "trips.txt") if t["route_id"] in route_ids]
        self.shapes = defaultdict(list)
        if os.path.exists(os.path.join(gtfs, "shapes.txt")):
            wanted = {t.get("shape_id", "") for t in self.trips}
            for r in rd(gtfs, "shapes.txt"):
                if r["shape_id"] in wanted:
                    self.shapes[r["shape_id"]].append((int(float(r["shape_pt_sequence"])), float(r["shape_pt_lat"]), float(r["shape_pt_lon"])))
        ids = {t["trip_id"] for t in self.trips}
        self.st = defaultdict(list)
        with open(os.path.join(gtfs, "stop_times.txt"), encoding="utf-8-sig") as f:
            for r in csv.DictReader(f):
                if r["trip_id"] in ids:
                    self.st[r["trip_id"]].append(r)
        for v in self.st.values():
            v.sort(key=lambda r: int(r["stop_sequence"]))
        # parent_station -> nom commun pour regrouper les quais
        self.name = {k: v["stop_name"].strip() for k, v in self.stops.items()}

    def pattern(self, t):
        return tuple(r["stop_id"] for r in self.st[t["trip_id"]])


def variants(feed, route_id, min_share=0.10, min_trips=20):
    """Variantes d'une ligne : un couple de terminus (noms) = une variante, avec le motif le plus fréquent par sens."""
    trips = [t for t in feed.trips if t["route_id"] == route_id and feed.st.get(t["trip_id"])]
    groups = defaultdict(lambda: defaultdict(list))
    for t in trips:
        pat = feed.pattern(t)
        if len(pat) < 2:
            continue
        key = frozenset((feed.name[pat[0]], feed.name[pat[-1]]))
        groups[key][t.get("direction_id") or ("0" if feed.name[pat[0]] <= feed.name[pat[-1]] else "1")].append(t)
    out = []
    total = max(1, len(trips))
    for key, by_dir in groups.items():
        n = sum(len(v) for v in by_dir.values())
        if n < min_trips and n / total < min_share:
            continue
        sel = {}
        for d, ts in by_dir.items():
            pat = Counter(feed.pattern(t) for t in ts).most_common(1)[0][0]
            typed = [t for t in ts if feed.pattern(t) == pat]
            shape = Counter(t.get("shape_id", "") for t in typed).most_common(1)[0][0]
            sel[d] = (pat, typed, shape if shape in feed.shapes else None)
        out.append((n, key, sel))
    out.sort(key=lambda x: -x[0])
    return out


def build(gtfs, route_id, args, feed=None, selection=None, prefix=None, net_id=None):
    feed = feed or Feed(gtfs, {route_id})
    if selection is None:
        vs = variants(feed, route_id)
        if not vs:
            raise SystemExit(f"route {route_id} absente ou sans service")
        selection = vs[0][2]
    prefix = prefix or route_id
    stops = feed.stops
    route = feed.routes[route_id]
    any_pt = stops[next(iter(selection.values()))[0][0]]
    proj = Proj(float(any_pt["stop_lat"]), float(any_pt["stop_lon"]))
    st_by_trip = feed.st
    straight = False

    nodes, edges, stations, missions, report = [], [], [], [], {}
    dir_info = {}
    for d in sorted(selection):
        full, typed, shape_id = selection[d]
        # quais homonymes consécutifs (même station, quais distincts) : fusionnés en un seul arrêt
        groups = []
        for k, sid in enumerate(full):
            if groups and feed.name[full[groups[-1][0]]] == feed.name[sid]:
                groups[-1].append(k)
            else:
                groups.append([k])
        pattern = tuple(full[g[0]] for g in groups)
        if shape_id:
            pts = [proj(la, lo) for _, la, lo in sorted(feed.shapes[shape_id])]
        else:  # pas de tracé : segments droits entre arrêts (géométrie estimée)
            straight = True
            pts = [proj(float(stops[s]["stop_lat"]), float(stops[s]["stop_lon"])) for s in pattern]
        for attempt in (0, 1):
            cum = cumulative(pts)
            s_prev, abscissa, worst = 0.0, [], 0.0
            for sid in pattern:
                p = proj(float(stops[sid]["stop_lat"]), float(stops[sid]["stop_lon"]))
                s, gap = project(pts, cum, p, s_prev) or (s_prev, 0.0)
                worst = max(worst, gap)
                abscissa.append(s)
                s_prev = s
            if worst <= MAX_SHAPE_GAP or attempt == 1:
                break
            # tracé incohérent avec les arrêts : repli sur des segments droits entre arrêts
            straight = True
            pts = [proj(float(stops[x]["stop_lat"]), float(stops[x]["stop_lon"])) for x in pattern]
        pre = f"{prefix}{d}_pre"
        nodes.append(pre)
        # approche : prolonge le tracé en amont du premier arrêt
        a0 = point_at(pts, cum, abscissa[0])
        a1 = point_at(pts, cum, min(cum[-1], abscissa[0] + 5.0))
        ux, uz = a0[0] - a1[0], a0[1] - a1[1]
        n = math.hypot(ux, uz) or 1.0
        appr_start = (a0[0] + ux / n * APPROACH_M, a0[1] + uz / n * APPROACH_M)
        node0 = f"{prefix}{d}_S0"
        nodes.append(node0)
        st_index = []
        edges.append({"id": f"{prefix}{d}_appr", "from": pre, "to": node0, "length": APPROACH_M,
                      "limit_kmh": 30, "grade": 0.0, "pts": [[round(x, 2) for x in appr_start], [round(x, 2) for x in a0]]})
        stations.append({"name": stops[pattern[0]]["stop_name"], "stop_id": pattern[0], "edge": f"{prefix}{d}_appr",
                         "offset": APPROACH_M - STOP_BACK_M, "dwell_s": 20})
        st_index.append(len(stations) - 1)
        for i in range(1, len(pattern)):
            s0, s1 = abscissa[i - 1], abscissa[i]
            poly = sub_polyline(pts, cum, s0, s1)
            length = max(1.0, s1 - s0)
            r = min_radius(poly)
            zones = curve_zones(poly)
            ni = f"{prefix}{d}_S{i}"
            nodes.append(ni)
            e = {"id": f"{prefix}{d}_{i}", "from": f"{prefix}{d}_S{i-1}", "to": ni, "length": round(length, 1),
                 "limit_kmh": DEFAULT_LIMIT, "limits": zones, "grade": 0.0, "min_radius_m": None if r == math.inf else round(r, 1),
                 "pts": [[round(x, 2), round(z, 2)] for x, z in poly]}
            edges.append(e)
            stations.append({"name": stops[pattern[i]]["stop_name"], "stop_id": pattern[i], "edge": e["id"],
                             "offset": round(max(0.0, length - STOP_BACK_M), 1), "dwell_s": 20})
            st_index.append(len(stations) - 1)
        # temps d'arrêt, temps de parcours et missions à partir des services réels
        dwell, run = defaultdict(list), defaultdict(list)
        for t in typed:
            rows = st_by_trip[t["trip_id"]]
            for k, g in enumerate(groups):
                dwell[k].append(hms(rows[g[-1]]["departure_time"]) - hms(rows[g[0]]["arrival_time"]))
                if k:
                    run[k].append(hms(rows[g[0]]["arrival_time"]) - hms(rows[groups[k - 1][-1]]["departure_time"]))
        for k, si in enumerate(st_index):
            vals = sorted(dwell[k])
            stations[si]["dwell_s"] = max(20, vals[len(vals) // 2] if vals else 20)
        # limite de l'inter-station : relevée si l'horaire l'exige (vitesse moyenne x 1,5), bornée à vmax
        vmax = getattr(args, "vmax", 70)
        by_id = {e["id"]: e for e in edges}
        for k in range(1, len(groups)):
            vals = sorted(v for v in run[k] if v > 0)
            if not vals:
                continue
            e = by_id[f"{prefix}{d}_{k}"]
            need = e["length"] / vals[len(vals) // 2] * 3.6 * 1.5
            e["limit_kmh"] = int(max(DEFAULT_LIMIT, min(vmax, math.ceil(need / 5.0) * 5)))
        typed.sort(key=lambda t: hms(st_by_trip[t["trip_id"]][groups[0][-1]]["departure_time"]))
        picks = [typed[int(j * (len(typed) - 1) / max(1, args.missions - 1))] for j in range(min(args.missions, len(typed)))]
        for t in picks:
            rows = st_by_trip[t["trip_id"]]
            t0 = hms(rows[groups[0][-1]]["departure_time"])
            missions.append({"id": t["trip_id"], "direction": d, "headsign": t.get("trip_headsign", ""),
                             "start_time": rows[groups[0][-1]]["departure_time"], "start_edge": f"{prefix}{d}_appr",
                             "start_offset": APPROACH_M - STOP_BACK_M, "stops": st_index,
                             "departures": [hms(rows[g[-1]]["departure_time"]) - t0 + 60 for g in groups]})
        dir_info[d] = {"first_node": pre, "last_node": f"{prefix}{d}_S{len(pattern) - 1}"}
        report[d] = {"shape": shape_id, "stops": len(pattern), "length_m": round(abscissa[-1] - abscissa[0]),
                     "max_stop_gap_m": round(worst, 1), "trips": len(typed)}
    # rebroussements : fin d'un sens -> approche de l'autre (le nœud d'approche est fusionné avec le terminus)
    ds = sorted(dir_info)
    if len(ds) == 2:
        for a, b in ((ds[0], ds[1]), (ds[1], ds[0])):
            old = dir_info[b]["first_node"]
            for e in edges:
                if e["from"] == old:
                    e["from"] = dir_info[a]["last_node"]
            nodes.remove(old)
    return {
        "schema": 1, "id": net_id or args.id, "origin": [round(proj.lat0, 7), round(proj.lon0, 7)], "city": args.city, "line": route["route_short_name"],
        "long_name": route["route_long_name"], "color": "#" + (route.get("route_color") or "c8102e"),
        "provisional": False,
        "provenance": f"GTFS {args.publisher} (licence {args.licence}), données du {args.source_date} via transport.data.gouv.fr. "
                      "Tracé = shapes.txt ; arrêts et horaires = stops/stop_times. Une ligne = un réseau (tronçons communs non fusionnés).",
        "estimated": (["géométrie : segments droits entre arrêts (tracé absent ou incohérent)"] if straight else []) + ["grade (aucun MNT importé)", "limit_kmh (50 km/h par défaut, relevée si l'horaire GTFS l'exige ; zones réduites autour des courbes selon le rayon mesuré)",
                      "supply (" + args.supply_note + ")", "rebroussement simplifié aux terminus"],
        "supply": args.supply, "guidance": "steel",
        "nodes": nodes, "edges": edges, "stations": stations, "signals": [], "roads": [], "missions": missions,
        "import_report": report,
    }


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("gtfs"); ap.add_argument("route"); ap.add_argument("out")
    ap.add_argument("--id", required=True); ap.add_argument("--city", required=True)
    ap.add_argument("--source-date", required=True); ap.add_argument("--publisher", default="exploitant")
    ap.add_argument("--licence", default="voir jeu de données")
    ap.add_argument("--supply", default="overhead"); ap.add_argument("--supply-note", default="non vérifié")
    ap.add_argument("--missions", type=int, default=6)
    a = ap.parse_args()
    net = build(a.gtfs, a.route, a)
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(net, f, ensure_ascii=False, separators=(",", ":"))
    print(json.dumps(net["import_report"], ensure_ascii=False), f"-> {a.out}")
