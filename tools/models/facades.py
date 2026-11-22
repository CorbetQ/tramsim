"""Grammaire de façade angevine (tuffeau et ardoise) : rez-de-chaussée commercial, étages à baies régulières,
balcons filants en fer forgé à l'étage noble, bandeaux, corniche, toit à la Mansard avec lucarnes, souches."""
import math
import numpy as np
from shapely.geometry import Polygon, Point
from meshkit import Kit, v3, norm, UP
from archkit import Wall, wall_with_openings, rect, arch_round, clean_ring, mansard

GF_SHOP = 4.2
FLOOR = 3.15


def edges_of(ring, poly, others):
    """Arêtes avec normale extérieure et nature (mitoyenne si un voisin touche la face)."""
    out = []
    for i in range(len(ring)):
        a, b = np.array(ring[i]), np.array(ring[(i + 1) % len(ring)])
        e = b - a; L = float(np.linalg.norm(e))
        if L < 0.5: continue
        n = np.array([e[1], -e[0]]) / L; m = (a + b) / 2
        if poly.contains(Point(*(m + n * 0.05))): n = -n
        party = any(o.contains(Point(*(m + n * 0.7))) for o in others)
        out.append({"a": a, "b": b, "n": n, "L": L, "m": m, "party": party})
    return out


def building(k: Kit, ring, h, ground, others, detail_fn, rng, shop=True, wall_mat="facade_tuffeau", top_mat="lm_zinc"):
    """`ground(x, z)` : altitude du sol ; `detail_fn(edge)` : 0 = détail complet, 1 = baies simples, 2 = aveugle."""
    ring = clean_ring(ring, 0.3)
    poly = Polygon(ring)
    if not poly.is_valid or poly.area < 12: return None
    gs = [ground(x, z) for x, z in ring]
    g0 = min(gs); gmean = float(np.mean(gs)); eave = gmean + h
    edges = edges_of(ring, poly, others)
    lod = k.lod
    # LOD2 : volume simple et toit plat sombre
    k.lod = (2, 2)
    k.prism(ring, g0 - 1.0, eave, wall_mat, top="toiture")
    # LOD0-1 : murs
    for e in edges:
        w = Wall(e["a"], e["b"], e["n"])
        kind = 2 if e["party"] else detail_fn(e)
        gf = ground(*e["m"]); base = min(gf, g0) - 1.0
        if kind == 2 or e["L"] < 2.2:
            k.lod = (0, 1); k.quad(w.P(0, base), w.P(e["L"], base), w.P(e["L"], eave), w.P(0, eave), wall_mat, w.n)
            continue
        bays = max(1, int((e["L"] - 0.8) / 2.85)); sp = e["L"] / bays
        if sp < 1.9: bays = max(1, int(e["L"] / 2.4)); sp = e["L"] / bays
        g1 = gf + (GF_SHOP if shop else 3.4)
        floors = max(0, int((eave - g1 - 0.7) / FLOOR))
        holes = []; wins = []
        for i in range(bays):
            c = (i + 0.5) * sp
            if shop:
                ww = min(sp - 0.55, 2.7)
                holes.append(rect(c - ww / 2, c + ww / 2, gf + 0.12, gf + 3.25)); wins.append(("shop", c, ww, gf + 0.12, gf + 3.25))
            else:
                holes.append(rect(c - 0.6, c + 0.6, gf + 0.9, gf + 2.7)); wins.append(("win", c, 1.2, gf + 0.9, gf + 2.7))
            for f in range(floors):
                y0 = g1 + f * FLOOR
                if f == 0 and floors >= 2:   # étage noble : portes-fenêtres et balcon
                    holes.append(rect(c - 0.62, c + 0.62, y0 + 0.12, y0 + 2.6)); wins.append(("french", c, 1.24, y0 + 0.12, y0 + 2.6))
                else:
                    holes.append(rect(c - 0.58, c + 0.58, y0 + 0.85, y0 + 2.5)); wins.append(("win", c, 1.16, y0 + 0.85, y0 + 2.5))
        if kind == 0:
            k.lod = (0, 0)
            wall_with_openings(k, w, base, eave, holes, wall_mat, 0.24, glass="lm_vitre")
            for (t, c, ww, y0, y1) in wins:
                B = (w.t, UP, -w.n)
                if t == "shop":
                    k.box(w.P(c, y0 + (y1 - y0) * 0.5, 0.2), (0.05, y1 - y0, 0.05), "lm_menuiserie_sombre", basis=B)
                    k.box(w.P(c, y1 - 0.55, 0.2), (ww, 0.05, 0.05), "lm_menuiserie_sombre", basis=B)
                    k.box(w.P(c, y1 + 0.32, -0.06), (ww + 0.3, 0.5, 0.12), ["lm_devanture_a", "lm_devanture_b", "mobilier_metal"][int(rng.integers(0, 3))], basis=B)
                    continue
                k.box(w.P(c, (y0 + y1) / 2, 0.19), (0.05, y1 - y0, 0.05), "lm_menuiserie", basis=B)
                k.box(w.P(c, y1 - 0.5, 0.19), (ww, 0.05, 0.05), "lm_menuiserie", basis=B)
                # encadrement en tuffeau, appui et clé
                k.box(w.P(c - ww / 2 - 0.07, (y0 + y1) / 2, -0.025), (0.14, y1 - y0 + 0.1, 0.05), wall_mat, basis=B)
                k.box(w.P(c + ww / 2 + 0.07, (y0 + y1) / 2, -0.025), (0.14, y1 - y0 + 0.1, 0.05), wall_mat, basis=B)
                k.box(w.P(c, y1 + 0.1, -0.03), (ww + 0.34, 0.2, 0.06), wall_mat, basis=B)
                k.box(w.P(c, y1 + 0.13, -0.06), (0.26, 0.26, 0.06), "pierre_taille", basis=B)
                if t == "win":
                    k.box(w.P(c, y0 - 0.05, -0.05), (ww + 0.24, 0.1, 0.14), "pierre_taille", basis=B)
                    k.box(w.P(c, y0 + 0.35, 0.12), (ww, 0.04, 0.03), "lm_ferronnerie", basis=B)   # garde-corps d'appui
                else:
                    k.box(w.P(c, y0 - 0.07, -0.28), (ww + 0.5, 0.14, 0.6), "pierre_taille", basis=B)
                    for yy in (y0 + 0.95, y0 + 0.12):
                        k.box(w.P(c, yy, -0.55), (ww + 0.46, 0.04, 0.04), "lm_ferronnerie", basis=B)
                    nb = 9
                    for j in range(nb):
                        u = c - (ww + 0.4) / 2 + (ww + 0.4) * j / (nb - 1)
                        k.box(w.P(u, y0 + 0.5, -0.55), (0.02, 0.85, 0.02), "lm_ferronnerie", basis=B)
                    for s in (-1, 1):
                        k.box(w.P(c + s * (ww + 0.4) / 2, y0 + 0.5, -0.3), (0.02, 0.85, 0.5), "lm_ferronnerie", basis=B)
            # bandeaux d'étage et soubassement
            for f in range(floors + 1):
                y = g1 + f * FLOOR - 0.1
                k.box(w.P(e["L"] / 2, y, -0.04), (e["L"], 0.18, 0.08), wall_mat, basis=(w.t, UP, -w.n))
            k.box(w.P(e["L"] / 2, base + (gf + 0.6 - base) / 2, -0.03), (e["L"], gf + 0.6 - base, 0.06), "pierre_taille", basis=(w.t, UP, -w.n))
        if kind >= 0:
            # LOD1 (et LOD0 éloigné, kind 1) : mur plein et baies en aplat sombre légèrement saillant
            k.lod = (1, 1) if kind == 0 else (0, 1)
            k.quad(w.P(0, base), w.P(e["L"], base), w.P(e["L"], eave), w.P(0, eave), wall_mat, w.n)
            for (t, c, ww, y0, y1) in wins:
                k.quad(w.P(c - ww / 2, y0, -0.015), w.P(c + ww / 2, y0, -0.015), w.P(c + ww / 2, y1, -0.015), w.P(c - ww / 2, y1, -0.015),
                       "lm_vitre", w.n)
                if t == "french" and kind == 0:
                    k.box(w.P(c, y0 + 0.5, -0.3), (ww + 0.5, 1.0, 0.6), "lm_ferronnerie", basis=(w.t, UP, -w.n), faces=(4, 2))
    # corniche continue (LOD0-1)
    k.lod = (0, 1)
    pr = Polygon(ring); rr = ring if pr.exterior.is_ccw else ring[::-1]
    path = [(x, eave, z) for x, z in rr]
    # côté du profil : vérifie que +x du profil pointe vers l'extérieur
    t0 = norm(v3(path[1]) - v3(path[0])); side = np.cross(t0, UP)
    m0 = (v3(path[0]) + v3(path[1])) / 2
    out_sign = -1.0 if poly.contains(Point(m0[0] + side[0] * 0.3, m0[2] + side[2] * 0.3)) else 1.0
    prof = [(0.0, -0.45), (0.07, -0.45), (0.07, -0.3), (0.16, -0.2), (0.32, -0.05), (0.36, 0.0), (0.36, 0.1), (0.0, 0.1)]
    k.sweep(path, [(x * out_sign, y) for x, y in prof], wall_mat, closed=True)
    top = mansard(k, ring, eave + 0.1, "toiture", top_mat)
    # lucarnes (LOD0-1) sur les faces détaillées
    for e in edges:
        if e["party"] or detail_fn(e) != 0 or e["L"] < 4: continue
        w = Wall(e["a"], e["b"], e["n"])
        bays = max(1, int((e["L"] - 0.8) / 2.85)); sp = e["L"] / bays
        for i in range(bays):
            if bays > 2 and i % 2 == 1: continue
            c = (i + 0.5) * sp; B = (w.t, UP, -w.n)
            k.lod = (0, 1)
            k.box(w.P(c, eave + 1.05, 0.55), (1.1, 1.7, 0.9), wall_mat, basis=B)
            k.lod = (0, 0)
            k.quad(w.P(c - 0.38, eave + 0.45, 0.095), w.P(c + 0.38, eave + 0.45, 0.095), w.P(c + 0.38, eave + 1.6, 0.095), w.P(c - 0.38, eave + 1.6, 0.095), "lm_vitre", w.n)
            k.lod = (0, 1)
            A = w.P(c - 0.62, eave + 1.9, 0.08); Bp = w.P(c + 0.62, eave + 1.9, 0.08); Cp = w.P(c, eave + 2.55, 0.08)
            k.tri(A, Bp, Cp, wall_mat, w.n)
            k.quad(A, Cp, Cp - w.n * 1.1, A - w.n * 1.1, "toiture", norm(-w.t + UP))
            k.quad(Cp, Bp, Bp - w.n * 1.1, Cp - w.n * 1.1, "toiture", norm(w.t + UP))
    # souches de cheminée
    k.lod = (0, 1)
    for i in range(0, len(ring), max(1, len(ring) // 2)):
        p = np.array(ring[i]) * 0.75 + np.array(poly.centroid.coords[0]) * 0.25
        if not poly.contains(Point(*p)): continue
        yaw = float(rng.uniform(0, 3))
        k.box((p[0], top + 0.7, p[1]), (0.55, 1.6, 1.1), wall_mat, yaw=yaw)
        k.box((p[0], top + 1.55, p[1]), (0.65, 0.1, 1.2), "pierre_taille", yaw=yaw)
    k.lod = lod
    return {"ring": ring, "base": g0 - 1.0, "height": top - g0 + 1.0}
