"""Station Ralliement (Angers, ligne C) et abords : quais (emprises OSM du jeu), auvents vitrés, mobilier, dallage
de la place, arbres, façades tuffeau/ardoise et Grand Théâtre. Géoréférencé sur data/ (BD TOPO, sol IGN)."""
import json, math
import numpy as np
from shapely.geometry import Polygon, LineString, Point, MultiPolygon
from shapely.ops import unary_union
import triangle as tr
import geo
from meshkit import Kit, v3, norm, UP, translate
from archkit import (Wall, wall_with_openings, rect, arch_round, tree, bench, ticket_machine, info_pole, bollard, lamp,
                     bin_, mansard, clean_ring)
from facades import building

EDGES = ("cv0_0_9", "cv0_0_10", "cv0_1_9", "cv0_1_10")
WAYS = (193089410, 193089411)


def offset_line(pts, y, o):
    out = []
    for i in range(len(pts)):
        d = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]; d = d / np.linalg.norm(d)
        out.append((pts[i][0] - d[1] * o, pts[i][1] + d[0] * o))
    return out


def polys(g):
    if g.is_empty: return []
    return [g] if g.geom_type == "Polygon" else [p for p in g.geoms if p.geom_type == "Polygon"]


def build():
    city = geo.City("angers"); net = geo.network("angers_c")
    assert net["origin"] == city.origin
    G = city.ground
    prof = next(s for s in json.loads((geo.ROOT / "data/station_models/angers.json").read_text())["stations"] if s["id"] == "ralliement")
    ax, az = geo.ll2xy(prof["lat"], prof["lon"], city.origin)
    anchor = (ax, G(ax, az), az)
    # ------------------------------------------------ voies (axe de chaque sens, ±1,75 m de l'axe commun)
    centres = []
    for eid in EDGES:
        pts, y, _ = geo.edge_axis(net, eid)
        sel = [i for i in range(len(pts)) if math.dist(pts[i], (ax, az)) < 160]
        p2, y2 = pts[sel], y[sel]
        for o in (-1.75, 1.75):
            centres.append((LineString(offset_line(p2, y2, o)), y2))
    track_lines = unary_union([c[0] for c in centres])
    def rail_y(x, z):
        best = None
        for L, yy in centres:
            d = L.project(Point(x, z), normalized=True)
            dist = L.distance(Point(x, z))
            if best is None or dist < best[0]:
                best = (dist, float(np.interp(d, np.linspace(0, 1, len(yy)), yy)))
        return best[1]
    corridor = track_lines.buffer(3.3, cap_style=2)
    gauge_low = track_lines.buffer(1.52)     # nez de quai hors gabarit du jeu (1,5 m) de l'axe d'une voie
    gauge = track_lines.buffer(1.65)         # rien dans le gabarit (1,5 m + marge)
    k = Kit()
    meta = {"replace": [], "keepout": [], "blocks": [], "platform_ways": list(WAYS)}
    # ------------------------------------------------ quais
    quays = []
    for pf in net["platforms"]:
        if pf.get("osm_way") not in WAYS: continue
        P = Polygon(pf["pts"]).buffer(0)
        Q = P.difference(gauge_low)
        Q = max(polys(Q), key=lambda p: p.area)
        A = np.array([[p[0], p[1], 1.0] for p in pf["pts"]]); b = np.array(pf["y"]) + float(pf.get("height_m", 0.3))
        coef, *_ = np.linalg.lstsq(A, b, rcond=None)
        top = lambda x, z, c=coef: min(float(c[0] * x + c[1] * z + c[2]), rail_y(x, z) + 0.3)   # quai : 30 cm au-dessus du rail au plus
        ring = list(Q.exterior.coords)[:-1]
        quays.append({"poly": Q, "top": top, "ring": ring, "way": pf["osm_way"]})
        # dalle supérieure (dallage), chants, bordure granit côté voie, bande podotactile
        k.lod = (0, 2)
        k.poly([(x, top(x, z), z) for x, z in ring], "dallage", UP)
        for i in range(len(ring)):
            a, c = ring[i], ring[(i + 1) % len(ring)]
            mid = Point((a[0] + c[0]) / 2, (a[1] + c[1]) / 2)
            e = np.array(c) - np.array(a); L = np.linalg.norm(e)
            if L < 0.05: continue
            n = np.array([e[1], -e[0]]) / L
            if Q.contains(Point(mid.x + n[0] * 0.05, mid.y + n[1] * 0.05)): n = -n
            k.quad((a[0], G(*a) - 0.3, a[1]), (c[0], G(*c) - 0.3, c[1]), (c[0], top(*c), c[1]), (a[0], top(*a), a[1]),
                   "bordure_granit", v3(n[0], 0, n[1]))
            if track_lines.distance(mid) < 2.2 and L > 4:   # bordure de quai côté voie et podotactile
                ii = -n
                k.lod = (0, 1)
                for (w0, w1, mat, dy) in ((0.0, 0.32, "bordure_granit", 0.008), (0.5, 0.9, "lm_podotactile", 0.006)):
                    pa = np.array(a) + ii * w0; pb = np.array(c) + ii * w0; pc = np.array(c) + ii * w1; pd = np.array(a) + ii * w1
                    k.quad(*[(p[0], top(*p) + dy, p[1]) for p in (pa, pb, pc, pd)], mat, UP)
                k.lod = (0, 0)
                cnt = int(L / 0.3)
                for j in range(cnt):
                    for r in (0.6, 0.8):
                        p = np.array(a) + e / L * (j + 0.5) * L / cnt + ii * r
                        k.box((p[0], top(*p) + 0.012, p[1]), (0.035, 0.012, 0.035), "lm_podotactile", yaw=math.atan2(e[1], e[0]))
                k.lod = (0, 2)
        meta["blocks"].append([ring, top(*ring[0]) - 0.6, 0.6])
        for i in range(len(pf["pts"])):
            a, c = pf["pts"][i], pf["pts"][(i + 1) % len(pf["pts"])]
            meta["keepout"].append([a, c, 0.6])
    # ------------------------------------------------ auvents vitrés (empreintes OSM) : poteaux hors gabarit
    for cno, can in enumerate(prof["canopies"]):
        C = Polygon([geo.ll2xy(a, b, city.origin) for a, b in can["footprint"]]).buffer(0)
        q = next((q for q in quays if q["way"] == can["platform_way"]), quays[0])
        base = q["top"](*C.centroid.coords[0])
        y_low = max(rail_y(*C.centroid.coords[0]) + 4.75, base + 4.2)
        slope = 0.03 if cno == 0 else -0.03
        Cr = Polygon(clean_ring(list(C.exterior.coords)[:-1], 0.4))
        ring = list(Cr.exterior.coords)[:-1]
        ctr = np.array(Cr.centroid.coords[0])
        # axe principal (ACP)
        P = np.array(ring) - ctr; ev, evec = np.linalg.eigh(P.T @ P); t2 = evec[:, 1]; n2 = np.array([-t2[1], t2[0]])
        Y = lambda x, z: y_low + 0.6 + slope * float(np.dot(np.array([x, z]) - ctr, n2))
        k.lod = (0, 2)
        k.poly([(x, Y(x, z), z) for x, z in ring], "vitrage", UP)
        k.poly([(x, Y(x, z) - 0.02, z) for x, z in ring], "vitrage", -UP)
        # rive périphérique (poutre de rive) et ossature en grille
        for i in range(len(ring)):
            a, c = ring[i], ring[(i + 1) % len(ring)]
            k.lod = (0, 2); k.seg_box((a[0], Y(*a) - 0.14, a[1]), (c[0], Y(*c) - 0.14, c[1]), 0.18, 0.32, "lm_peinture_blanche")
        lo = P @ t2; lo_n = P @ n2
        k.lod = (0, 1)
        for s in np.arange(lo.min() + 1.6, lo.max(), 1.6):
            seg = LineString([ctr + t2 * s + n2 * (lo_n.min() - 1), ctr + t2 * s + n2 * (lo_n.max() + 1)]).intersection(Cr)
            for g in ([seg] if seg.geom_type == "LineString" else list(getattr(seg, "geoms", []))):
                if g.length < 0.3: continue
                (x0, z0), (x1, z1) = g.coords[0], g.coords[-1]
                k.seg_box((x0, Y(x0, z0) - 0.09, z0), (x1, Y(x1, z1) - 0.09, z1), 0.06, 0.16, "lm_peinture_blanche")
        for s in np.arange(lo_n.min() + 2.5, lo_n.max(), 2.5):
            seg = LineString([ctr + n2 * s + t2 * (lo.min() - 1), ctr + n2 * s + t2 * (lo.max() + 1)]).intersection(Cr)
            for g in ([seg] if seg.geom_type == "LineString" else list(getattr(seg, "geoms", []))):
                if g.length < 0.3: continue
                (x0, z0), (x1, z1) = g.coords[0], g.coords[-1]
                k.seg_box((x0, Y(x0, z0) - 0.2, z0), (x1, Y(x1, z1) - 0.2, z1), 0.12, 0.36, "lm_peinture_blanche")
        # poteaux : grille 6 m dans l'empreinte, hors gabarit (1,9 m de l'axe des voies)
        for s in np.arange(lo.min() + 1.2, lo.max() - 0.5, 6.0):
            for r in np.arange(lo_n.min() + 1.0, lo_n.max() - 0.5, 6.0):
                p = ctr + t2 * s + n2 * r
                if not Cr.contains(Point(*p)) or track_lines.distance(Point(*p)) < 1.9: continue
                gy = max(G(*p), q["top"](*p) if q["poly"].buffer(0.3).contains(Point(*p)) else G(*p))
                k.lod = (0, 2); k.cyl((p[0], gy - 0.1, p[1]), (p[0], Y(*p) - 0.3, p[1]), 0.12, "lm_peinture_blanche", 12)
                k.lod = (0, 0)
                for d in (t2, -t2):   # jambes de force
                    k.seg_box((p[0], Y(*p) - 1.3, p[1]), (p[0] + d[0] * 1.2, Y(*p) - 0.3, p[1] + d[1] * 1.2), 0.08, 0.08, "lm_peinture_blanche")
                k.lod = (0, 0); k.box((p[0], gy + 0.03, p[1]), (0.5, 0.06, 0.5), "lm_inox")
                k.collider((p[0], (gy + Y(*p)) / 2, p[1]), (0.3, Y(*p) - gy, 0.3))
        # éclairage sous auvent (réglettes)
        k.lod = (0, 0)
        for s in np.arange(lo.min() + 3.0, lo.max() - 1.0, 4.8):
            p = ctr + t2 * s
            if Cr.contains(Point(*p)):
                k.box((p[0], Y(*p) - 0.42, p[1]), (1.2, 0.05, 0.12), "eclairage", yaw=math.atan2(n2[1], n2[0]))
    # ------------------------------------------------ dallage de la place (drapé sur le sol IGN, +4 cm)
    place = Polygon([geo.ll2xy(a, b, city.origin) for a, b in prof["surfaces"][0]["footprint"]]).buffer(0)
    paving = place.difference(corridor)
    for q in quays: paving = paving.difference(q["poly"].buffer(0.02))
    trees_xy = []
    for t in city.scene()["t"]:
        if place.buffer(4).contains(Point(*t["v"])) and track_lines.distance(Point(*t["v"])) > 4.0:
            trees_xy.append((t["v"], t["r"]))
    for P in polys(paving):
        if P.area < 1: continue
        V = []; S = []; H = []
        def ring_add(coords, closed=True):
            b0 = len(V)
            cs = list(coords)[:-1]
            for i, c in enumerate(cs):
                V.append(c); S.append((b0 + i, b0 + (i + 1) % len(cs)))
        ring_add(P.exterior.coords)
        for hole in P.interiors:
            ring_add(hole.coords); H.append(Polygon(hole).representative_point().coords[0])
        d = {"vertices": np.array(V), "segments": np.array(S)}
        if H: d["holes"] = np.array(H)
        T = tr.triangulate(d, "pq25a3.0")
        vs = T["vertices"]; ts = T["triangles"]
        ys = [G(x, z) + 0.04 for x, z in vs]
        P3 = [(vs[i][0], ys[i], vs[i][1]) for i in range(len(vs))]
        k.lod = (0, 2)
        for t in ts:
            k.tri(P3[t[0]], P3[t[1]], P3[t[2]], "paves_granit", UP)
    # caniveau central et lignes de calepinage (bandes granit) : LOD0
    k.lod = (0, 0)
    for P in polys(paving):
        for frac in np.arange(0.0, 1.0, 0.08):
            pass
    # ------------------------------------------------ arbres de la place
    rng = np.random.default_rng(7)
    for (x, z), r in trees_xy:
        g = G(x, z)
        tree(k, (x, g, z), h=float(np.clip(r * 3.2, 7, 13)), crown_r=float(np.clip(r, 2.2, 4.5)), rng=rng)
        k.lod = (0, 1)
        k.cyl((x, g + 0.03, z), (x, g + 0.06, z), 1.1, "mobilier_metal", 16)   # grille d'arbre fonte
        meta["keepout"].append([[x, z], [x, z], 1.2])
        k.collider((x, g + 2, z), (0.6, 4, 0.6))
    # ------------------------------------------------ mobilier des quais
    k.lod = (0, 1)
    for q in quays:
        Q = q["poly"]; c = np.array(Q.centroid.coords[0])
        P = np.array(q["ring"]) - c; ev, evec = np.linalg.eigh(P.T @ P); t2 = evec[:, 1]
        n2 = np.array([-t2[1], t2[0]])
        if track_lines.distance(Point(*(c + n2))) < track_lines.distance(Point(*c)): n2 = -n2   # n2 : côté opposé aux voies
        half = (P @ t2).max(); wid = (P @ n2).max()
        back = lambda s, off=0.45: c + t2 * s + n2 * (wid - off)
        def put(fn, s, off=0.45, *a):
            p = back(s, off)
            if track_lines.distance(Point(*p)) < 2.0 or not Q.contains(Point(*p)): return
            fn(k, (p[0], q["top"](*p), p[1]), *a)
        for s in (-half * 0.55, half * 0.1):
            put(lambda kk, p: bench(kk, p, -t2 if False else t2), s, 0.5)
        put(lambda kk, p: ticket_machine(kk, p, -t2), half * 0.45, 0.4)
        put(lambda kk, p: info_pole(kk, p, t2), -half * 0.15, 0.3)
        put(lambda kk, p: bin_(kk, p), half * 0.3, 0.35)
        for s in (-half + 0.4, half - 0.4):
            for o in (0.4, 1.0):
                put(lambda kk, p: bollard(kk, p), s, o)
        # plaque de nom de station suspendue
        p = back(-half * 0.35, 0.9)
        if Q.contains(Point(*p)) and track_lines.distance(Point(*p)) > 1.9:
            y = q["top"](*p)
            k.box((p[0], y + 2.55, p[1]), (1.6, 0.36, 0.06), "lm_panneau", yaw=math.atan2(t2[1], t2[0]))
            k.box((p[0], y + 2.55 + 0.2, p[1]), (1.6, 0.05, 0.07), "lm_ligne", yaw=math.atan2(t2[1], t2[0]))
            k.cyl((p[0], y, p[1]), (p[0], y + 2.75, p[1]), 0.04, "mobilier_metal", 8)
    # candélabres autour de la place (pas dans le gabarit)
    ring = list(place.buffer(-2.0).exterior.coords)
    L = LineString(ring); n = int(L.length / 26)
    for i in range(n):
        p = L.interpolate(i / n, normalized=True)
        if track_lines.distance(p) < 4.0: continue
        q = L.interpolate(min(1.0, i / n + 0.01), normalized=True)
        tng = np.array([q.x - p.x, q.y - p.y]); inw = np.array([-tng[1], tng[0]])
        if not place.contains(Point(p.x + inw[0], p.y + inw[1])): inw = -inw
        k.lod = (0, 1); lamp(k, (p.x, G(p.x, p.y), p.y), inw, 8.0, 0.0)
    # terrasses de café (relevé IGN)
    for cafe in prof.get("furniture", []):
        if cafe["type"] != "cafe": continue
        x, z = geo.ll2xy(*cafe["position"], city.origin); hd = math.radians(cafe["heading_deg"])
        t2 = np.array([math.cos(hd), -math.sin(hd)]); n2 = np.array([-t2[1], t2[0]])
        for i in range(int(cafe["length_m"] / 4)):
            p = np.array([x, z]) + t2 * ((i + 0.5) * 4 - cafe["length_m"] / 2)
            if track_lines.distance(Point(*p)) < 4.0: continue
            g = G(*p); k.lod = (0, 1)
            k.cyl((p[0], g, p[1]), (p[0], g + 2.4, p[1]), 0.03, "mobilier_metal", 6)
            k.lathe((p[0], g + 2.1, p[1]), [(1.6, 0.0), (0.05, 0.45)], "lm_toile", 12, smooth=False)
            k.lod = (0, 0)
            for j in (-0.8, 0.8):
                q2 = p + n2 * j
                k.cyl((q2[0], g, q2[1]), (q2[0], g + 0.72, q2[1]), 0.03, "mobilier_metal", 6, caps=False)
                k.cyl((q2[0], g + 0.72, q2[1]), (q2[0], g + 0.75, q2[1]), 0.35, "lm_inox", 10)
    # ------------------------------------------------ bâtiments autour de la place
    sc = city.scene()
    th_ll = prof["landmarks"][0]["footprint"]
    theatre = Polygon([geo.ll2xy(a, b, city.origin) for a, b in th_ll]).buffer(0)
    blds = []
    for b in sc["b"]:
        P = Polygon(b["ring"]).buffer(0)
        if P.is_empty or P.area < 15 or P.area > 4000: continue
        if P.distance(place) > 22 or P.centroid.distance(Point(ax, az)) > 110: continue
        if P.intersects(corridor.buffer(1.0)): continue
        blds.append((P, b))
    others = [P for P, b in blds]
    meta["replace"] = []
    nb = 0
    for P, b in blds:
        if theatre.contains(P.centroid) or P.intersection(theatre).area > 0.5 * P.area: continue
        det = lambda e, P=P: 0 if (Point(*e["m"]).distance(place) < 10 and Point(*e["m"]).distance(Point(ax, az)) < 95) else 1
        res = building(k, list(P.exterior.coords)[:-1], max(6.0, b["h"]), G, [o for o in others if o is not P], det, rng,
                       shop=b["h"] > 9)
        if res:
            nb += 1
            meta["replace"].append(list(P.buffer(0.3).exterior.coords)[:-1])
            meta["blocks"].append([res["ring"], res["base"], res["height"]])
            k.collider((P.centroid.x, res["base"] + res["height"] / 2, P.centroid.y), (math.sqrt(P.area) * 0.8, res["height"], math.sqrt(P.area) * 0.8))
    theatre_model(k, theatre, 18.9, G, place, (ax, az), [o for o in others], rng)
    meta["replace"].append(list(theatre.buffer(0.5).exterior.coords)[:-1])
    meta["blocks"].append([list(theatre.exterior.coords)[:-1], G(*theatre.centroid.coords[0]) - 1, 24.0])
    print("bâtiments", nb, "+ théâtre ; arbres", len(trees_xy))
    # gabarit : contrôle de la géométrie générée
    meta["gauge_lines"] = [[list(c) for c in L.coords] for L, _ in centres]
    return k, anchor, meta, centres


def theatre_model(k, P, h, G, place, centre, others, rng):
    """Grand Théâtre (1871) : soubassement à refends et trois arcades, étage noble à colonnes jumelées et grandes
    baies cintrées, entablement, attique à balustrade et groupe sculpté central ; toit d'ardoise."""
    ring = clean_ring(list(P.exterior.coords)[:-1], 0.5)
    poly = Polygon(ring)
    gs = [G(x, z) for x, z in ring]; g0 = min(gs); gm = float(np.mean(gs)); eave = gm + h
    # façade principale : arête la plus longue tournée vers la place
    best = None
    for i in range(len(ring)):
        a, b = np.array(ring[i]), np.array(ring[(i + 1) % len(ring)]); L = np.linalg.norm(b - a)
        m = (a + b) / 2; sc = L - Point(*m).distance(place) * 2
        if best is None or sc > best[0]: best = (sc, i)
    fi = best[1]
    k.lod = (2, 2); k.prism(ring, g0 - 1, eave, "facade_tuffeau", top="toiture")
    from facades import edges_of
    for idx, e in enumerate(edges_of(ring, poly, others)):
        w = Wall(e["a"], e["b"], e["n"]); gf = G(*e["m"]); base = min(gf, g0) - 1.0
        is_front = np.allclose(e["a"], ring[fi])
        if not is_front:
            k.lod = (0, 1)
            if e["party"] or e["L"] < 3:
                k.quad(w.P(0, base), w.P(e["L"], base), w.P(e["L"], eave), w.P(0, eave), "facade_tuffeau", w.n); continue
            bays = max(1, int(e["L"] / 4.2)); sp = e["L"] / bays
            holes = [arch_round((i + .5) * sp - .7, (i + .5) * sp + .7, gf + 7.0, gf + 11.5, 6) for i in range(bays)]
            holes += [rect((i + .5) * sp - .6, (i + .5) * sp + .6, gf + 1.0, gf + 3.6) for i in range(bays)]
            k.lod = (0, 0); wall_with_openings(k, w, base, eave, holes, "facade_tuffeau", 0.3, glass="lm_vitre")
            k.lod = (1, 1); k.quad(w.P(0, base), w.P(e["L"], base), w.P(e["L"], eave), w.P(0, eave), "facade_tuffeau", w.n)
            continue
        L = e["L"]; B = (w.t, UP, -w.n)
        # soubassement : trois arcades d'entrée
        arc = [arch_round(L / 2 + o - 1.7, L / 2 + o + 1.7, gf, gf + 5.2, 10) for o in (-5.6, 0.0, 5.6)]
        win = [arch_round(L / 2 + o - 1.3, L / 2 + o + 1.3, gf + 7.4, gf + 13.0, 10) for o in (-5.6, 0.0, 5.6)]
        side = [rect(o - 0.7, o + 0.7, gf + 8.0, gf + 11.8) for o in (L / 2 - 10.5, L / 2 + 10.5) if 1.0 < o < L - 1.0]
        k.lod = (0, 0)
        wall_with_openings(k, w, base, eave, arc + win + side, "facade_tuffeau", 0.45, glass="lm_vitre")
        for o in (-5.6, 0.0, 5.6):   # portes vitrées en fond d'arcade
            k.box(w.P(L / 2 + o, gf + 2.0, 0.42), (3.3, 0.06, 0.05), "lm_menuiserie_sombre", basis=B)
            k.box(w.P(L / 2 + o, gf + 2.0, 0.42), (0.06, 4.0, 0.05), "lm_menuiserie_sombre", basis=B)
        # refends horizontaux du soubassement
        for yy in np.arange(gf + 0.55, gf + 6.3, 0.55):
            k.box(w.P(L / 2, yy, -0.02), (L, 0.05, 0.04), "pierre_taille", basis=B)
        k.box(w.P(L / 2, gf + 6.45, -0.18), (L + 0.2, 0.45, 0.36), "facade_tuffeau", basis=B)   # bandeau
        # colonnes jumelées (corinthiennes simplifiées) entre les baies
        for o in (-8.4, -2.8, 2.8, 8.4):
            for dd in (-0.5, 0.5):
                u = L / 2 + o + dd
                if not (0.6 < u < L - 0.6): continue
                p0 = w.P(u, gf + 6.7, -0.42)
                k.box(p0 + UP * 0.15, (0.9, 0.3, 0.9), "facade_tuffeau", basis=B)
                k.cyl(p0 + UP * 0.3, p0 + UP * 6.9, 0.33, "facade_tuffeau", 14, caps=False, r2=0.29)
                k.lathe(p0 + UP * 6.9, [(0.29, 0), (0.38, 0.45), (0.46, 0.7), (0.46, 0.8)], "facade_tuffeau", 12)
            k.box(w.P(L / 2 + o, gf + 13.95, -0.42), (2.0, 0.3, 0.95), "facade_tuffeau", basis=B)
        # balcons balustrés devant les grandes baies
        for o in (-5.6, 0.0, 5.6):
            k.box(w.P(L / 2 + o, gf + 6.75, -0.5), (3.2, 0.12, 0.6), "pierre_taille", basis=B)
            k.box(w.P(L / 2 + o, gf + 7.75, -0.72), (3.2, 0.1, 0.2), "facade_tuffeau", basis=B)
            for j in range(9):
                p0 = w.P(L / 2 + o - 1.45 + j * 0.36, gf + 6.8, -0.72)
                k.lathe(p0, [(0.07, 0), (0.1, 0.25), (0.05, 0.55), (0.08, 0.85), (0.07, 0.9)], "facade_tuffeau", 6)
            k.lathe(w.P(L / 2 + o, gf + 13.3, -0.12), [(0.3, 0), (0.22, 0.5), (0.0, 0.6)], "facade_tuffeau", 8)   # clé ornée
        # entablement, corniche, attique balustré
        k.box(w.P(L / 2, gf + 14.6, -0.3), (L + 0.3, 1.0, 0.6), "facade_tuffeau", basis=B)
        k.box(w.P(L / 2, gf + 15.25, -0.55), (L + 0.8, 0.3, 1.1), "pierre_taille", basis=B)
        k.box(w.P(L / 2, gf + 15.5, -0.2), (L, 0.2, 0.5), "facade_tuffeau", basis=B)
        for j in range(int(L / 0.42)):
            u = 0.3 + j * 0.42
            if u > L - 0.3: break
            k.lathe(w.P(u, gf + 15.6, -0.2), [(0.08, 0), (0.11, 0.2), (0.05, 0.5), (0.09, 0.75)], "facade_tuffeau", 6)
        k.box(w.P(L / 2, gf + 16.45, -0.2), (L, 0.14, 0.5), "facade_tuffeau", basis=B)
        # attique central et groupe sculpté (volumes simplifiés)
        k.box(w.P(L / 2, gf + 17.6, 0.3), (9.0, 2.6, 1.2), "facade_tuffeau", basis=B)
        k.box(w.P(L / 2, gf + 19.0, 0.3), (9.6, 0.3, 1.4), "pierre_taille", basis=B)
        for o, hh in ((-1.4, 2.3), (0.0, 2.9), (1.4, 2.3)):
            p0 = w.P(L / 2 + o, gf + 19.15, 0.3)
            k.lathe(p0, [(0.45, 0), (0.38, hh * 0.3), (0.3, hh * 0.7), (0.18, hh * 0.9), (0.0, hh)], "pierre_taille", 8)
        k.lod = (1, 1)
        k.quad(w.P(0, base), w.P(L, base), w.P(L, eave), w.P(0, eave), "facade_tuffeau", w.n)
        for o in (-5.6, 0.0, 5.6):
            for (y0, y1, hw) in ((gf, gf + 5.2, 1.7), (gf + 7.4, gf + 13.0, 1.3)):
                k.quad(w.P(L / 2 + o - hw, y0, -0.02), w.P(L / 2 + o + hw, y0, -0.02), w.P(L / 2 + o + hw, y1, -0.02), w.P(L / 2 + o - hw, y1, -0.02), "lm_vitre", w.n)
        k.box(w.P(L / 2, gf + 15.0, -0.4), (L + 0.6, 1.4, 0.8), "facade_tuffeau", basis=B)
        k.box(w.P(L / 2, gf + 17.6, 0.3), (9.0, 2.6, 1.2), "facade_tuffeau", basis=B)
    k.lod = (0, 1)
    mansard(k, ring, eave, "toiture", "lm_zinc", brisis=(1.2, 3.5), terrasson=(4.0, 1.5))


if __name__ == "__main__":
    k, anchor, meta, _ = build()
    for l in range(3): print("LOD", l, k.tris(l))
