"""Trémie de la ligne 3 de Nantes (passage inférieur sous la voie routière, seul ouvrage couvert proche d'Angers dans
les données : data/networks/nantes_3.json, tunnel 235,6-283,5 m) : cadre en béton banché à deux travées, file de
poteaux centrale, poutres de couverture, réglettes LED continues, trottoirs de service et caniveaux à grille, dalle de
voie (rails à gorge de la voie du jeu), marquages, niches de secours, portails à chevrons et murs en aile, remblai
routier. UV2 générées à l'import (LightmapGI)."""
import math
import numpy as np
from shapely.geometry import Polygon, LineString, Point
import geo
from meshkit import Kit, v3, norm, UP

NETS = {"nantes_3": ("3v0_0_3", "3v0_1_29")}
CONC = "beton_banche"; SLAB = "beton_dalle"


def build():
    net = geo.network("nantes_3"); city = geo.City("nantes"); G = city.ground
    def sc(p):
        lat, lon = geo.xy2ll(p[0], p[1], net["origin"]); return np.array(geo.ll2xy(lat, lon, city.origin))
    E = []
    for eid in NETS["nantes_3"]:
        pts, y, e = geo.edge_axis(net, eid)
        acc = np.r_[0, np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))]
        t0, t1 = e["tunnel"][0]
        ss = np.linspace(t0 - 30, t1 + 30, 50)
        P = np.array([sc((np.interp(s, acc, pts[:, 0]), np.interp(s, acc, pts[:, 1]))) for s in ss])
        Y = np.interp(ss, acc, y)
        inside = (ss >= t0) & (ss <= t1)
        E.append((P, Y, inside))
    allp = np.vstack([E[0][0], E[1][0]])
    c = allp.mean(axis=0); _, vec = np.linalg.eigh((allp - c).T @ (allp - c)); t = vec[:, 1]
    if t[0] < 0: t = -t
    n = np.array([-t[1], t[0]])
    U = lambda p: float(np.dot(np.asarray(p) - c, t)); W = lambda p: float(np.dot(np.asarray(p) - c, n))
    spans = [[U(p) for p in P[ins]] for P, Y, ins in E]
    u0 = max(min(s) for s in spans); u1 = min(max(s) for s in spans)
    u0, u1 = min(min(s) for s in spans), max(max(s) for s in spans)
    ws = [np.mean([W(p) for p in P]) for P, Y, ins in E]
    centres = sorted([w + o for w in ws for o in (-1.75, 1.75)])
    wl, wr = centres[0] - 2.05, centres[-1] + 2.05
    wm = (ws[0] + ws[1]) / 2
    uy = np.concatenate([[U(p) for p in P] for P, Y, ins in E]); yy = np.concatenate([Y for P, Y, ins in E])
    o = np.argsort(uy); uy, yy = uy[o], yy[o]
    ry = lambda u: float(np.interp(u, uy, yy))          # niveau du rail (axe de voie)
    X = lambda u, w, y: v3(*(c + t * u + n * w)[[0]], y, *(c + t * u + n * w)[[1]]) if False else v3((c + t * u + n * w)[0], y, (c + t * u + n * w)[1])
    k = Kit()
    SOF = 5.3; DECK = 1.15; TH = 0.5      # sous-face (au-dessus du rail), épaisseur du tablier, des piédroits
    step = 1.5
    us = np.arange(u0, u1 + 1e-6, (u1 - u0) / max(1, round((u1 - u0) / step)))
    # ------------------------------------------------------------ radier, piédroits, sous-face (bandes le long de u)
    for i in range(len(us) - 1):
        a, b = us[i], us[i + 1]; ya, yb = ry(a), ry(b)
        k.lod = (0, 2)
        k.quad(X(a, wl - TH, ya - 0.03), X(b, wl - TH, yb - 0.03), X(b, wr + TH, yb - 0.03), X(a, wr + TH, ya - 0.03), SLAB, UP)
        for w_, s in ((wl, 1), (wr, -1)):   # faces intérieures des piédroits
            k.quad(X(a, w_, ya - 0.03), X(b, w_, yb - 0.03), X(b, w_, yb + SOF), X(a, w_, ya + SOF), CONC, v3(*(n * s))[[0]].tolist() + [0] if False else v3(n[0] * s, 0, n[1] * s))
            k.quad(X(a, w_ - s * TH, ya - 1.0), X(b, w_ - s * TH, yb - 1.0), X(b, w_ - s * TH, yb + SOF + DECK), X(a, w_ - s * TH, ya + SOF + DECK), CONC, v3(-n[0] * s, 0, -n[1] * s))
        k.quad(X(a, wl - TH, ya + SOF), X(b, wl - TH, yb + SOF), X(b, wr + TH, yb + SOF), X(a, wr + TH, ya + SOF), SLAB, -UP)
        k.quad(X(a, wl - TH, ya + SOF + DECK), X(b, wl - TH, yb + SOF + DECK), X(b, wr + TH, yb + SOF + DECK), X(a, wr + TH, ya + SOF + DECK), "enrobe", UP)
        # trottoirs de service (0,2 m) et caniveaux à grille
        k.lod = (0, 1)
        for w_, s in ((wl, 1), (wr, -1)):
            wi = w_ + s * 0.38
            k.quad(X(a, w_, ya + 0.2), X(b, w_, yb + 0.2), X(b, wi, yb + 0.2), X(a, wi, ya + 0.2), SLAB, UP)
            k.quad(X(a, wi, ya - 0.03), X(b, wi, yb - 0.03), X(b, wi, yb + 0.2), X(a, wi, ya + 0.2), SLAB, v3(n[0] * s, 0, n[1] * s))
            k.quad(X(a, wi + s * 0.02, ya + 0.004), X(b, wi + s * 0.02, yb + 0.004), X(b, wi + s * 0.3, yb + 0.004), X(a, wi + s * 0.3, ya + 0.004), "lm_caniveau", UP)
            k.quad(X(a, wi - s * 0.08, ya + 0.205), X(b, wi - s * 0.08, yb + 0.205), X(b, wi - s * 0.02, yb + 0.205), X(a, wi - s * 0.02, ya + 0.205), "lm_marquage", UP)
        # terre-plein central (entre voies intérieures)
        ci0, ci1 = centres[1] + 1.7, centres[2] - 1.7
        if ci1 - ci0 > 0.8:
            k.quad(X(a, ci0, ya + 0.2), X(b, ci0, yb + 0.2), X(b, ci1, yb + 0.2), X(a, ci1, ya + 0.2), SLAB, UP)
            for w_, s in ((ci0, -1), (ci1, 1)):
                k.quad(X(a, w_, ya - 0.03), X(b, w_, yb - 0.03), X(b, w_, yb + 0.2), X(a, w_, ya + 0.2), SLAB, v3(n[0] * s, 0, n[1] * s))
                k.quad(X(a, w_ - s * 0.06, ya + 0.205), X(b, w_ - s * 0.06, yb + 0.205), X(b, w_ - s * 0.14, yb + 0.205), X(a, w_ - s * 0.14, ya + 0.205), "lm_jaune", UP)
    # ------------------------------------------------------------ joints de banchage, poutres, poteaux, LED, équipements
    L = u1 - u0
    k.lod = (0, 0)
    for u in np.arange(u0 + 3.0, u1, 3.0):   # joints verticaux de reprise de bétonnage
        for w_, s in ((wl, 1), (wr, -1)):
            k.box(X(u, w_ + s * 0.005, ry(u) + SOF / 2), (0.04, SOF, 0.02), "lm_joint", yaw=math.atan2(t[1], t[0]))
    for u in np.arange(u0 + 0.6, u1, 1.25):   # poutres précontraintes de couverture
        k.lod = (0, 1)
        a = X(u, wl, ry(u) + SOF - 0.32); b = X(u, wr, ry(u) + SOF - 0.32)
        k.seg_box(a, b, 0.42, 0.64, SLAB)
    for u in np.arange(u0 + 3.0, u1 - 1.0, 6.0):   # file centrale de poteaux et chevêtre
        k.lod = (0, 2)
        k.box(X(u, wm, ry(u) + SOF / 2), (0.7, SOF, 0.7), CONC, yaw=math.atan2(t[1], t[0]))
        k.collider(X(u, wm, ry(u) + SOF / 2), (0.7, SOF, 0.7), math.atan2(t[1], t[0]))
        k.lod = (0, 0)
        for s in (-1, 1):   # bandes réfléchissantes
            k.box(X(u, wm, ry(u) + 0.9 + s * 0.3), (0.72, 0.15, 0.72), "lm_jaune", yaw=math.atan2(t[1], t[0]))
    k.lod = (0, 1)
    k.seg_box(X(u0, wm, ry(u0) + SOF - 0.45), X(u1, wm, ry(u1) + SOF - 0.45), 0.9, 0.9, CONC)
    # réglettes LED continues (deux parois + chevêtre central)
    for w_, s in ((wl, 1), (wr, -1), (wm - 0.46, -1), (wm + 0.46, 1)):
        for i in range(len(us) - 1):
            a, b = us[i], us[i + 1]
            k.lod = (0, 1)
            yl = SOF - 0.75 if abs(w_ - wm) < 1 else 4.45
            k.seg_box(X(a + 0.05, w_ + s * 0.06, ry(a) + yl), X(b - 0.05, w_ + s * 0.06, ry(b) + yl), 0.1, 0.09, "mobilier_metal")
            k.lod = (0, 2)
            k.seg_box(X(a + 0.08, w_ + s * 0.115, ry(a) + yl - 0.03), X(b - 0.08, w_ + s * 0.115, ry(b) + yl - 0.03), 0.01, 0.04, "lm_led")
    # chemin de câbles, niches de secours, signalisation d'évacuation
    k.lod = (0, 0)
    for w_, s in ((wl, 1), (wr, -1)):
        k.seg_box(X(u0, w_ + s * 0.12, ry(u0) + 3.6), X(u1, w_ + s * 0.12, ry(u1) + 3.6), 0.22, 0.08, "lm_zinc")
        k.seg_box(X(u0, w_ + s * 0.06, ry(u0) + 1.0), X(u1, w_ + s * 0.06, ry(u1) + 1.0), 0.1, 0.25, "lm_zinc")   # main courante
        for u in np.arange(u0 + 12.0, u1 - 4.0, 24.0):
            k.box(X(u, w_ + s * 0.02, ry(u) + 1.25), (1.0, 1.5, 0.06), "lm_rouge", yaw=math.atan2(t[1], t[0]))
            k.box(X(u + 1.6, w_ + s * 0.03, ry(u) + 2.3), (0.45, 0.22, 0.04), "lm_secours", yaw=math.atan2(t[1], t[0]))
            k.box(X(u - 1.6, w_ + s * 0.03, ry(u) + 1.6), (0.3, 0.42, 0.03), "lm_panneau", yaw=math.atan2(t[1], t[0]))
    # ------------------------------------------------------------ portails : tête de tablier, chevrons, murs en aile
    for ue, sgn in ((u0, -1), (u1, 1)):
        y = ry(ue)
        k.lod = (0, 2)
        k.quad(X(ue, wl - TH, y + SOF), X(ue, wr + TH, y + SOF), X(ue, wr + TH, y + SOF + DECK + 0.95), X(ue, wl - TH, y + SOF + DECK + 0.95), CONC, v3(t[0] * sgn, 0, t[1] * sgn))
        k.lod = (0, 1)
        k.box(X(ue + sgn * 0.1, (wl + wr) / 2, y + SOF + DECK + 1.05), (0.5, 0.2, wr - wl + 1.4), CONC, yaw=math.atan2(t[1], t[0]))   # couronnement
        k.box(X(ue + sgn * 0.12, (wl + wr) / 2, y + SOF + 0.1), (0.25, 0.25, wr - wl), CONC, yaw=math.atan2(t[1], t[0]))   # larmier
        k.lod = (0, 0)
        nch = int((wr - wl) / 0.5)
        for j in range(nch):   # chevrons jaune et noir (gabarit)
            w_ = wl + (j + 0.5) * (wr - wl) / nch
            k.box(X(ue + sgn * 0.03, w_, y + SOF + 0.35), (0.04, 0.5, (wr - wl) / nch), "lm_jaune" if j % 2 else "lm_menuiserie_sombre", yaw=math.atan2(t[1], t[0]))
        # garde-corps (lisses) sur le tablier
        k.lod = (0, 1)
        for yy_ in (1.0, 1.35):
            k.seg_box(X(ue - sgn * 0.3, wl - TH, y + SOF + DECK + 0.95 + yy_ - 0.9), X(ue - sgn * 0.3, wr + TH, y + SOF + DECK + 0.95 + yy_ - 0.9), 0.08, 0.12, "lm_zinc")
        for w_ in np.arange(wl - TH, wr + TH, 2.0):
            k.box(X(ue - sgn * 0.3, w_, y + SOF + DECK + 1.25), (0.1, 0.6, 0.1), "lm_zinc")
        # murs en aile évasés (20°), hauteur décroissante
        for w_, s in ((wl - TH, -1), (wr + TH, 1)):
            d = np.array([t[0] * sgn, t[1] * sgn]) * math.cos(math.radians(20)) + n * s * math.sin(math.radians(20))
            base = c + t * ue + n * w_
            seg = 6
            for j in range(seg):
                p0 = base + d * 9.0 * j / seg; p1 = base + d * 9.0 * (j + 1) / seg
                h0 = (SOF + DECK + 0.9) * (1 - j / seg) + 0.6; h1 = (SOF + DECK + 0.9) * (1 - (j + 1) / seg) + 0.6
                g0, g1 = G(*p0), G(*p1)
                y0_, y1_ = y, y
                k.lod = (0, 2)
                nn = np.array([-d[1], d[0]])
                for side in (1, -1):
                    q0, q1 = p0 + nn * side * 0.25, p1 + nn * side * 0.25
                    k.quad(v3(q0[0], min(g0, y0_) - 1, q0[1]), v3(q1[0], min(g1, y1_) - 1, q1[1]), v3(q1[0], y1_ + h1, q1[1]), v3(q0[0], y0_ + h0, q0[1]), CONC, v3(nn[0] * side, 0, nn[1] * side))
                k.quad(v3(p0[0] - nn[0] * .25, y0_ + h0, p0[1] - nn[1] * .25), v3(p1[0] - nn[0] * .25, y1_ + h1, p1[1] - nn[1] * .25), v3(p1[0] + nn[0] * .25, y1_ + h1, p1[1] + nn[1] * .25), v3(p0[0] + nn[0] * .25, y0_ + h0, p0[1] + nn[1] * .25), CONC, UP)
            k.collider(v3(*(base + d * 4.5)[[0]], y + 3, *(base + d * 4.5)[[1]]) if False else v3((base + d * 4.5)[0], y + 3, (base + d * 4.5)[1]), (9.0, 6, 0.5), math.atan2(d[1], d[0]))
    # ------------------------------------------------------------ remblai routier de part et d'autre (talus enherbés)
    top = lambda u: ry(u) + SOF + DECK
    for s, wedge in ((-1, wl - TH), (1, wr + TH)):
        for i in range(len(us) - 1):
            a, b = us[i], us[i + 1]
            far = wedge + s * 16.0
            pa, pb = c + t * a + n * far, c + t * b + n * far
            k.lod = (0, 2)
            k.quad(X(a, wedge, top(a)), X(b, wedge, top(b)), X(b, wedge + s * 8, top(b)), X(a, wedge + s * 8, top(a)), "enrobe", UP)
            k.quad(X(a, wedge + s * 8, top(a)), X(b, wedge + s * 8, top(b)), v3(pb[0], G(*pb) - 0.3, pb[1]), v3(pa[0], G(*pa) - 0.3, pa[1]), "gazon", UP)
        for ue, sgn in ((u0, -1), (u1, 1)):   # talus en bout (pente 3/2 vers les voies)
            p_far = c + t * ue + n * (wedge + s * 16.0)
            k.quad(X(ue, wedge, top(ue)), X(ue, wedge + s * 8, top(ue)), v3(p_far[0], G(*p_far) - 0.3, p_far[1]), X(ue, wedge, ry(ue) - 0.5), "gazon", v3(t[0] * sgn, 0.6, t[1] * sgn))
    # marquage de la chaussée supérieure (axe, rives)
    k.lod = (0, 1)
    for wv in np.arange(wl - TH - 7.5, wr + TH + 7.5, 3.5):
        k.seg_box(X(u0 + 0.3, wv, top(u0) + 0.01), X(u1 - 0.3, wv, top(u1) + 0.01), 0.12, 0.01, "lm_marquage")
    # collisions des piédroits et du tablier
    for w_ in (wl - TH / 2, wr + TH / 2):
        k.collider(X((u0 + u1) / 2, w_, ry((u0 + u1) / 2) + SOF / 2), (L, SOF + 1, TH), math.atan2(t[1], t[0]))
    k.collider(X((u0 + u1) / 2, (wl + wr) / 2, ry((u0 + u1) / 2) + SOF + DECK / 2), (L, DECK, wr - wl + 2 * TH), math.atan2(t[1], t[0]))
    foot = [tuple(c + t * u + n * w) for u, w in ((u0, wl - TH), (u1, wl - TH), (u1, wr + TH), (u0, wr + TH))]
    gauge = [[tuple(p) for p in P] for P, Y, ins in E]
    meta = {"tunnel_footprint": foot, "portal_cut": [list(c + t * u0 + n * wm), list(c + t * u1 + n * wm), (wr - wl) / 2 + TH + 0.5],
            "blocks": [], "keepout": [], "replace": [], "centres": centres, "axis": [list(c), list(t), list(n)], "u": [u0, u1],
            "rail_y": [[float(a), float(b)] for a, b in zip(uy[::4], yy[::4])]}
    anchor = (c[0], ry(0.0), c[1])
    return k, anchor, meta, E


if __name__ == "__main__":
    k, a, m, _ = build()
    print(a, m["u"], m["centres"])
    for l in range(3): print("LOD", l, k.tris(l))
