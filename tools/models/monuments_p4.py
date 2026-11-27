"""Monuments P4 des 26 autres villes (glTF LOD0-2) : constructeurs paramétriques (église gothique ou romane,
basilique à coupoles, tour, palais classique, forteresse, arc, ouvrages singuliers) géoréférencés sur les emprises
BD TOPO de data/scenes (bâtiment le plus grand ou le plus haut du type attendu près d'un point WGS84 vérifié ;
data/landmarks.json est décalé pour plusieurs monuments, cf. docs/CDC_REFONTE_VISUELLE.md « État P4 — villes »).
Silhouettes d'après les dimensions publiées (hauteurs des tours et flèches, longueurs) ; détails procéduraux.
Appelé par build_monuments.py (SPECS_P4) ; chaque constructeur renvoie (Kit, ancre, méta : replace, blocks)."""
import glob, json, math
import numpy as np
from shapely.geometry import Polygon, Point, LineString
from shapely.ops import unary_union
import geo
from meshkit import Kit, v3, norm, UP
from archkit import mansard, hip_roof

STONE = "pierre_taille"; SLATE = "toiture"; TILE = "toiture#a65e44"; ZINC = "lm_zinc"; GLASS = "lm_vitre"
DARK = "lm_menuiserie_sombre"; METAL = "mobilier_metal"; WHITE = "lm_peinture_blanche"; BRICK = "facade_brique"
VIT = "lm_vitrail"; GOLD = "lm_jaune#c9a246"; CONC = "beton_banche"; WATER = "eau"; INOX = "lm_inox"; ENDUIT = "facade_enduit"
GREEN_CU = "lm_zinc#6f9a8a"   # cuivre patiné

_C = {}
def city_of(name):
    if name not in _C: _C[name] = geo.City(name)
    return _C[name]


# ------------------------------------------------------------------ outils
def ccw(ring):
    ring = [tuple(map(float, p)) for p in ring]
    if len(ring) > 1 and ring[0] == ring[-1]: ring = ring[:-1]
    return ring if Polygon(ring).exterior.is_ccw else ring[::-1]


class F2:
    """Repère 2D (centre, axe u, axe v) : p(a, b) ; P(a, b, y) en 3D ; anneaux rectangulaires."""
    def __init__(self, c, u):
        self.c = np.array(c, float); self.u = np.array(u, float) / np.linalg.norm(u); self.v = np.array([-self.u[1], self.u[0]])
    def p(self, a, b): return self.c + self.u * a + self.v * b
    def P(self, a, b, y): q = self.p(a, b); return v3(q[0], y, q[1])
    def ring(self, a0, a1, b0, b1): return [tuple(self.p(a0, b0)), tuple(self.p(a1, b0)), tuple(self.p(a1, b1)), tuple(self.p(a0, b1))]
    def yaw(self): return -math.atan2(self.u[1], self.u[0])
    def circle(self, a, b, r, n=16): return [tuple(self.p(a + r * math.cos(2 * math.pi * i / n), b + r * math.sin(2 * math.pi * i / n))) for i in range(n)]


def obb(ring):
    r = Polygon(ring).minimum_rotated_rectangle
    p = np.array(r.exterior.coords[:4]); e0 = p[1] - p[0]; e1 = p[2] - p[1]
    if np.linalg.norm(e0) < np.linalg.norm(e1): e0, e1 = e1, e0
    return p.mean(axis=0), e0 / np.linalg.norm(e0), np.linalg.norm(e0) / 2, np.linalg.norm(e1) / 2


def xy(city, lat, lon): return np.array(geo.ll2xy(lat, lon, city.origin))


def find(city, lat, lon, r=120.0, kinds=None, minh=0.0, mode="area", maxarea=1e9, n=1):
    """Emprises BD TOPO près d'un point : kinds (codes CityScene.K_*), hauteur mini ; tri par aire, hauteur ou distance."""
    p = Point(*xy(city, lat, lon)); out = []
    for b in city.scene()["b"]:
        P = Polygon(b["ring"])
        if not P.is_valid or P.area > maxarea: continue
        d = P.distance(p)
        if d > r or b["h"] < minh: continue
        if kinds is not None and (b["kind"] & 7) not in kinds: continue
        out.append((b, P, d))
    key = {"area": lambda t: -t[1].area, "h": lambda t: -t[0]["h"], "near": lambda t: t[2]}[mode]
    out.sort(key=key)
    return out[:n]


def gmin(city, ring):
    return min(city.ground(p[0], p[1]) for p in ring)


_T = {}
def tracks(city):
    """Axes des voies de tous les réseaux de la ville (repère de la scène) : [(LineString, [y])]."""
    if city.name in _T: return _T[city.name]
    out = []
    for f in glob.glob(str(geo.ROOT / f"data/networks/{city.name}_*.json")):
        n = json.loads(open(f).read()); o = n["origin"]
        for e in n["edges"]:
            pts = [geo.ll2xy(*geo.xy2ll(p[0], p[1], o), city.origin) for p in e["pts"]]
            if len(pts) > 1: out.append((LineString(pts), e.get("y", [])))
    _T[city.name] = out
    return out


def nearest_track(city, x, z):
    best = None
    for ls, _ in tracks(city):
        d = ls.distance(Point(x, z))
        if best is None or d < best[0]: best = (d, ls)
    d, ls = best
    s = ls.project(Point(x, z)); q = np.array(ls.interpolate(s).coords[0]); q2 = np.array(ls.interpolate(min(s + 2, ls.length)).coords[0])
    t = q2 - q
    if np.linalg.norm(t) < 1e-6: t = q - np.array(ls.interpolate(max(s - 2, 0)).coords[0])
    return d, q, t / np.linalg.norm(t)


def gauge_check(k, a, city, name):
    """Gabarit (comme test_landmark_models) : sommets LOD0 à moins de 1,5 m d'un axe de voie (±1,75 m) entre
    rail + 0,35 et rail + 4,2 m. Retourne le nombre de sommets fautifs (avertissement)."""
    P = []
    for (lo, hi, g, m), B in k.parts.items():
        if lo <= 0 <= hi: P.extend(np.array(B["p"]).reshape(-1, 3).tolist())
    if not P: return 0
    P = np.array(P)
    bad = 0
    for ls, ys in tracks(city):
        if ls.distance(Point(a[0], a[2])) > 400: continue
        L = ls.length; m = int(L / 0.5) + 1
        for i in range(m):
            s = min(L, i * 0.5); q = np.array(ls.interpolate(s).coords[0]); q2 = np.array(ls.interpolate(min(s + 0.5, L)).coords[0])
            t = q2 - q; t = t / (np.linalg.norm(t) + 1e-9); nrm = np.array([-t[1], t[0]])
            y = city.ground(q[0], q[1])
            for o in (-1.75, 0.0, 1.75):
                c = q + nrm * o
                dd = np.hypot(P[:, 0] - c[0], P[:, 2] - c[1])
                bad += int(np.sum((dd < 1.5) & (P[:, 1] > y + 0.35) & (P[:, 1] < y + 4.2)))
    if bad: print("GABARIT", name, bad)
    return bad


def finish(k, city, replace, blocks, anchor_xz):
    ay = city.ground(*anchor_xz)
    return k, (float(anchor_xz[0]), ay, float(anchor_xz[1])), {"replace": [list(map(list, ccw(r))) for r in replace], "blocks": blocks}


def block(ring, y0, h): return [list(map(list, ccw(ring))), float(y0), float(h)]


# ------------------------------------------------------------------ éléments
def walls(k, ring, y0, y1, mat):
    k.prism(ring, y0, y1, mat, top=False)


def gable_roof(k, F, a0, a1, b0, b1, y, rise, mat, gable_mat=None):
    """Toit à deux pans le long de u (faîtage à b = (b0 + b1) / 2) avec pignons."""
    bm = (b0 + b1) / 2
    A, B, C, D = F.P(a0, b0, y), F.P(a1, b0, y), F.P(a1, b1, y), F.P(a0, b1, y)
    R0, R1 = F.P(a0, bm, y + rise), F.P(a1, bm, y + rise)
    k.quad(A, B, R1, R0, mat, norm(v3(0, 1, 0) - v3(F.v[0], 0, F.v[1])))
    k.quad(C, D, R0, R1, mat, norm(v3(0, 1, 0) + v3(F.v[0], 0, F.v[1])))
    gm = gable_mat or mat
    k.tri(D, A, R0, gm, v3(-F.u[0], 0, -F.u[1])); k.tri(B, C, R1, gm, v3(F.u[0], 0, F.u[1]))


def pyramid(k, ring, y, h, mat):
    c = np.mean(np.array(ring), axis=0); apex = v3(c[0], y + h, c[1])
    for i in range(len(ring)):
        a, b = ring[i], ring[(i + 1) % len(ring)]
        m = (np.array(a) + np.array(b)) / 2 - c
        k.tri(v3(a[0], y, a[1]), v3(b[0], y, b[1]), apex, mat, norm(v3(m[0], 0.3, m[1])))


def spire(k, c, r, y, h, mat, n=8, lucarnes=True):
    ring = [(c[0] + r * math.cos(2 * math.pi * (i + 0.5) / n), c[1] + r * math.sin(2 * math.pi * (i + 0.5) / n)) for i in range(n)]
    pyramid(k, ring, y, h, mat)
    if lucarnes:
        lod = k.lod; k.lod = (0, 1)
        for i in range(0, n, 2):
            ang = 2 * math.pi * i / n; q = np.array(c) + np.array([math.cos(ang), math.sin(ang)]) * r * 0.75
            k.box(v3(q[0], y + h * 0.18, q[1]), (0.5, h * 0.12, 0.5), mat, yaw=-ang)
        k.lod = lod


def pinnacles(k, ring, y, h, mat, r=0.45):
    lod = k.lod; k.lod = (0, 1)
    for p in ring:
        k.cyl(v3(p[0], y, p[1]), v3(p[0], y + h, p[1]), r, mat, 6, r2=0.02)
    k.lod = lod


def lancets(k, F, a0, a1, b, y0, y1, out, pitch, w, mat=VIT, round_=False):
    """Baies (lancettes à arc brisé ou plein cintre) sur une face plane b = cste (normale out = ±1 selon v)."""
    lod = k.lod; k.lod = (0, 1)
    n = max(1, int((a1 - a0) / pitch)); o = v3(F.v[0] * out, 0, F.v[1] * out); bb = b + out * 0.06
    for i in range(n):
        a = a0 + (i + 0.5) * (a1 - a0) / n
        P0, P1 = F.P(a - w / 2, bb, y0), F.P(a + w / 2, bb, y0)
        k.quad(P0, P1, P1 + UP * (y1 - y0), P0 + UP * (y1 - y0), mat, o)
        k.tri(P0 + UP * (y1 - y0), P1 + UP * (y1 - y0), F.P(a, bb, y1 + w * (0.5 if round_ else 0.8)), mat, o)
    k.lod = lod


def face_lancets(k, F, a, b0, b1, y0, y1, out, pitch, w, mat=VIT):
    """Baies sur une face a = cste (normale ±u)."""
    lod = k.lod; k.lod = (0, 1)
    n = max(1, int((b1 - b0) / pitch)); o = v3(F.u[0] * out, 0, F.u[1] * out); aa = a + out * 0.06
    for i in range(n):
        b = b0 + (i + 0.5) * (b1 - b0) / n
        P0, P1 = F.P(aa, b - w / 2, y0), F.P(aa, b + w / 2, y0)
        k.quad(P0, P1, P1 + UP * (y1 - y0), P0 + UP * (y1 - y0), mat, o)
        k.tri(P0 + UP * (y1 - y0), P1 + UP * (y1 - y0), F.P(aa, b, y1 + w * 0.8), mat, o)
    k.lod = lod


def rose(k, F, a, y, r, out=-1):
    lod = k.lod; k.lod = (0, 1)
    c = F.P(a + out * 0.08, 0, y); o = v3(F.u[0] * out, 0, F.u[1] * out); n = 16
    for i in range(n):
        a0 = 2 * math.pi * i / n; a1 = 2 * math.pi * (i + 1) / n
        k.tri(c, c + v3(F.v[0], 0, F.v[1]) * r * math.cos(a0) + UP * r * math.sin(a0), c + v3(F.v[0], 0, F.v[1]) * r * math.cos(a1) + UP * r * math.sin(a1), VIT, o)
    k.lod = lod


def window_grid(k, F, a0, a1, b, y0, rows, fh, pitch, ww, wh, out, mat=DARK, frame=None):
    """Grille de baies rectangulaires sur une face b = cste ; encadrement saillant en LOD0."""
    n = max(1, int((a1 - a0) / pitch)); o = v3(F.v[0] * out, 0, F.v[1] * out)
    for r in range(rows):
        for i in range(n):
            a = a0 + (i + 0.5) * (a1 - a0) / n; y = y0 + r * fh
            P0, P1 = F.P(a - ww / 2, b + out * 0.05, y), F.P(a + ww / 2, b + out * 0.05, y)
            k.lod = (0, 1); k.quad(P0, P1, P1 + UP * wh, P0 + UP * wh, mat, o)
            if frame:
                k.lod = (0, 0)
                q = F.p(a, b + out * 0.1); k.box(v3(q[0], y - 0.08, q[1]), (ww + 0.4, 0.16, 0.2), frame, yaw=F.yaw())
                k.box(v3(q[0], y + wh + 0.12, q[1]), (ww + 0.3, 0.24, 0.2), frame, yaw=F.yaw())
    k.lod = (0, 2)


def tower(k, c, side, y0, h, mat, top="spire", top_h=0.0, top_mat=SLATE, u=(1.0, 0.0), openings=True):
    """Tour carrée (contreforts d'angle, abat-sons) ; top : spire, flat, lantern, dome, octagon, iron, pyramid, none."""
    F = F2(c, u); s = side / 2
    k.lod = (0, 2); k.prism(F.ring(-s, s, -s, s), y0, y0 + h, mat)
    k.lod = (0, 1)
    for (a, b) in ((-s, -s), (s, -s), (s, s), (-s, s)):   # contreforts d'angle
        k.box(F.P(a, b, y0 + h * 0.42), (side * 0.2, h * 0.84, side * 0.2), mat, yaw=F.yaw())
    if openings:
        for sgn in (-1, 1):
            lancets(k, F, -s * 0.7, s * 0.7, s * sgn, y0 + h * 0.72, y0 + h * 0.9, sgn, side * 0.35, side * 0.16, DARK)
            face_lancets(k, F, s * sgn, -s * 0.7, s * 0.7, y0 + h * 0.72, y0 + h * 0.9, sgn, side * 0.35, side * 0.16, DARK)
    k.lod = (0, 2); top_y = y0 + h
    ring = F.ring(-s, s, -s, s)
    if top == "spire":
        k.prism(F.ring(-s * 1.04, s * 1.04, -s * 1.04, s * 1.04), top_y, top_y + 0.6, mat)
        pinnacles(k, ring, top_y + 0.6, side * 0.45, mat)
        spire(k, tuple(F.c), s * 0.86, top_y + 0.6, top_h, top_mat)
    elif top == "flat":
        k.prism(F.ring(-s * 1.06, s * 1.06, -s * 1.06, s * 1.06), top_y, top_y + 1.2, mat)
        pinnacles(k, ring, top_y + 1.2, max(top_h, side * 0.35), mat, r=0.6)
    elif top == "pyramid":
        pyramid(k, F.ring(-s * 1.05, s * 1.05, -s * 1.05, s * 1.05), top_y, top_h, top_mat)
    elif top == "lantern":   # lanterne octogonale à dôme (Tours, Orléans)
        k.prism(F.ring(-s * 1.04, s * 1.04, -s * 1.04, s * 1.04), top_y, top_y + 0.8, mat)
        k.prism(F.circle(0, 0, s * 0.7, 8), top_y + 0.8, top_y + 0.8 + top_h * 0.55, mat)
        k.lathe(v3(F.c[0], 0, F.c[1]), [(s * 0.72, top_y + 0.8 + top_h * 0.55), (s * 0.6, top_y + 0.8 + top_h * 0.75), (s * 0.3, top_y + 0.8 + top_h * 0.92), (0.05, top_y + 0.8 + top_h)], top_mat, seg=8)
    elif top == "dome":
        k.lathe(v3(F.c[0], 0, F.c[1]), [(s * 0.9, top_y), (s * 0.85, top_y + top_h * 0.4), (s * 0.55, top_y + top_h * 0.8), (0.05, top_y + top_h)], top_mat, seg=12)
    elif top == "octagon":   # clocher roman octogonal à étages en retrait et flèche (Saint-Sernin)
        y = top_y; r = s * 0.95
        for i in range(3):
            k.prism(F.circle(0, 0, r, 8), y, y + top_h * 0.16, mat)
            k.lod = (0, 1)
            for j in range(8):
                ang = 2 * math.pi * (j + 0.5) / 8; q = F.c + np.array([math.cos(ang), math.sin(ang)]) * r * 0.93
                k.box(v3(q[0], y + top_h * 0.08, q[1]), (r * 0.42, top_h * 0.1, 0.25), DARK, yaw=-ang + math.pi / 2)
            k.lod = (0, 2); y += top_h * 0.16; r *= 0.86
        spire(k, tuple(F.c), r, y, top_h * 0.52, mat, lucarnes=False)
    elif top == "iron":   # flèche de fonte ajourée (Rouen) : cône de montants et de cerces
        k.lod = (0, 2); spire(k, tuple(F.c), s * 0.7, top_y, top_h, "lm_ferronnerie#3b3d3c", n=8, lucarnes=False)
        k.lod = (0, 1)
        for f in np.linspace(0.1, 0.8, 6):
            k.lathe(v3(F.c[0], 0, F.c[1]), [(s * 0.72 * (1 - f) + 0.3, top_y + top_h * f), (s * 0.72 * (1 - f) + 0.3, top_y + top_h * f + 0.5)], METAL, seg=8)
    k.lod = (0, 2)
    return top_y + top_h


def dome(k, c, r, y, h, mat, drum=0.0, drum_mat=STONE, onion=False, lantern=True, seg=16):
    if drum > 0:
        k.lod = (0, 2); k.cyl(v3(c[0], y, c[1]), v3(c[0], y + drum, c[1]), r * 1.02, drum_mat, seg)
        lod = k.lod; k.lod = (0, 1)
        for j in range(seg):
            ang = 2 * math.pi * j / seg; q = np.array(c) + np.array([math.cos(ang), math.sin(ang)]) * r * 1.03
            k.box(v3(q[0], y + drum * 0.5, q[1]), (r * 0.18, drum * 0.55, 0.15), DARK, yaw=-ang + math.pi / 2)
        k.lod = lod; y += drum
    k.lod = (0, 2)
    if onion:
        prof = [(r, 0), (r * 1.18, h * 0.3), (r * 1.05, h * 0.5), (r * 0.55, h * 0.75), (r * 0.12, h * 0.92), (0.03, h)]
    else:
        prof = [(r * math.cos(t * math.pi / 2), h * math.sin(t * math.pi / 2)) for t in np.linspace(0, 1, 6)]
        prof[-1] = (0.03, h)
    k.lathe(v3(c[0], 0, c[1]), [(p[0], y + p[1]) for p in prof], mat, seg=seg)
    if lantern:
        k.lod = (0, 1); k.cyl(v3(c[0], y + h * 0.95, c[1]), v3(c[0], y + h * 1.12, c[1]), r * 0.12, drum_mat, 8)
        k.cyl(v3(c[0], y + h * 1.12, c[1]), v3(c[0], y + h * 1.2, c[1]), r * 0.13, mat, 8, r2=0.02); k.lod = (0, 2)
    return y + h


def statue(k, p, y, h, mat=GOLD, pedestal=0.0, ped_mat=STONE, arms=True):
    """Statue (silhouette) sur piédestal : corps, tête, bras levés."""
    k.lod = (0, 2)
    if pedestal > 0: k.cyl(v3(p[0], y, p[1]), v3(p[0], y + pedestal, p[1]), h * 0.2, ped_mat, 8)
    y += pedestal
    k.cyl(v3(p[0], y, p[1]), v3(p[0], y + h * 0.75, p[1]), h * 0.14, mat, 8, r2=h * 0.08)
    k.lathe(v3(p[0], 0, p[1]), [(0.01, y + h * 0.75), (h * 0.08, y + h * 0.8), (h * 0.07, y + h * 0.9), (0.01, y + h * 0.95)], mat, seg=8)
    if arms:
        k.lod = (0, 1)
        k.seg_box(v3(p[0], y + h * 0.68, p[1]), v3(p[0] + h * 0.12, y + h * 1.05, p[1]), h * 0.05, h * 0.05, mat)
        k.lod = (0, 2)


def equestrian(k, p, yaw, y, scale, mat="lm_ferronnerie#3f4a45", pedestal=4.0):
    """Statue équestre en bronze sur piédestal (silhouette : cheval, cavalier, étendard ou bras levé)."""
    F = F2(p, (math.cos(yaw), math.sin(yaw))); s = scale
    k.lod = (0, 2); k.prism(F.ring(-2.6 * s, 2.6 * s, -1.2 * s, 1.2 * s), y, y + pedestal, STONE)
    k.prism(F.ring(-2.8 * s, 2.8 * s, -1.4 * s, 1.4 * s), y + pedestal, y + pedestal + 0.4, STONE)
    y += pedestal + 0.4
    k.box(F.P(0, 0, y + 1.6 * s), (2.6 * s, 1.1 * s, 0.9 * s), mat, yaw=F.yaw())   # corps du cheval
    for a in (-0.95, 0.95):
        for b in (-0.3, 0.3):
            k.seg_box(F.P(a * s, b * s, y + 1.2 * s), F.P(a * s * (1.25 if a > 0 else 1.0), b * s, y), 0.25 * s, 0.25 * s, mat)
    k.seg_box(F.P(1.2 * s, 0, y + 1.9 * s), F.P(1.9 * s, 0, y + 2.9 * s), 0.5 * s, 0.6 * s, mat)   # encolure
    k.box(F.P(2.1 * s, 0, y + 2.85 * s), (0.9 * s, 0.4 * s, 0.4 * s), mat, yaw=F.yaw())
    k.seg_box(F.P(-1.3 * s, 0, y + 1.9 * s), F.P(-1.8 * s, 0, y + 0.9 * s), 0.25 * s, 0.25 * s, mat)   # queue
    k.cyl(F.P(-0.1 * s, 0, y + 2.1 * s), F.P(0, 0, y + 3.4 * s), 0.35 * s, mat, 8, r2=0.25 * s)    # cavalier
    k.lathe(v3(F.P(0, 0, 0)[0], 0, F.P(0, 0, 0)[2]), [(0.01, y + 3.4 * s), (0.22 * s, y + 3.55 * s), (0.01, y + 3.85 * s)], mat, seg=8)
    k.lod = (0, 1); k.seg_box(F.P(0.1 * s, 0.3 * s, y + 3.1 * s), F.P(0.7 * s, 0.4 * s, y + 4.4 * s), 0.12 * s, 0.12 * s, mat); k.lod = (0, 2)


# ------------------------------------------------------------------ constructeurs génériques
def church(cname, lat, lon, r=90.0, west=True, h=None, aisles=True, gothic=True, stone=STONE, roof=SLATE,
           towers=(("west_pair", 60.0, "flat", 0.0),), apse=True, transept=0.55, rose_=True, kinds=(1, 2), a_extra=0.0, flip=False):
    """Église ou cathédrale sur l'emprise BD TOPO la plus grande (kinds) près du point. towers : (position, hauteur de
    la tour, couronnement, hauteur du couronnement) ; positions : west_pair, west_n, west_s, west, crossing,
    transept_n_pair, east (chevet)."""
    city = city_of(cname); k = Kit()
    sel = find(city, lat, lon, r, kinds=kinds)
    if not sel: raise RuntimeError(f"{cname} : pas d'église près de {lat}, {lon}")
    b, P, d = sel[0]
    others = [t for t in find(city, lat, lon, r, kinds=kinds, n=40) if t[1].intersects(P.buffer(6.0))]
    union = unary_union([t[1] for t in others] + [P])
    ring = ccw(list((union if union.geom_type == "Polygon" else max(union.geoms, key=lambda q: q.area)).exterior.coords))
    c, u, L, W = obb(ring)
    F = F2(c, u)
    if F.p(-L, 0)[0] > F.p(L, 0)[0]: F = F2(c, -u)   # façade (a = -L) à l'ouest (x le plus petit)
    if flip: F = F2(c, -F.u)                          # façade à l'est
    L += a_extra
    g = gmin(city, ring) - 0.3
    H = h or max(float(b["h"]), 16.0)
    Wn = W * (0.5 if aisles else 1.0)
    ha = H * 0.55 if aisles else H
    ae = L - (Wn if apse else 0.0)
    k.lod = (0, 2)
    # nef
    k.prism(F.ring(-L, ae, -Wn, Wn), g, g + H, stone, top=False)
    gable_roof(k, F, -L, ae, -Wn, Wn, g + H, Wn * (1.1 if gothic else 0.6), roof, stone)
    if aisles:   # bas-côtés
        for sgn in (-1, 1):
            b0, b1 = sorted((sgn * Wn, sgn * W))
            k.prism(F.ring(-L + 2, ae, b0, b1), g, g + ha, stone, top=False)
            k.quad(F.P(-L + 2, sgn * W, g + ha), F.P(ae, sgn * W, g + ha), F.P(ae, sgn * Wn, g + ha + 2.5), F.P(-L + 2, sgn * Wn, g + ha + 2.5), roof, v3(0, 1, 0))
    if transept > 0:   # transept
        at = (-L + ae) * 0.5 + (ae + L) * 0.18; tw = Wn * 1.05
        k.prism(F.ring(at - tw, at + tw, -W - 2.5, W + 2.5), g, g + H, stone, top=False)
        Ft = F2(F.p(at, 0), F.v)
        gable_roof(k, Ft, -W - 2.5, W + 2.5, -tw, tw, g + H, tw * (1.1 if gothic else 0.6), roof, stone)
        for sgn in (-1, 1):
            if rose_: rose(k, Ft, sgn * (W + 2.5), g + H * 0.68, tw * 0.55, out=sgn)
    else:
        at = 0.0
    if apse:   # chevet en hémicycle (déambulatoire bas et sanctuaire)
        hemi = [tuple(F.p(ae + Wn * math.cos(t), Wn * math.sin(t))) for t in np.linspace(-math.pi / 2, math.pi / 2, 9)]
        k.prism(hemi, g, g + H, stone, top=False)
        ap = F.P(ae, 0, g + H + Wn * (1.1 if gothic else 0.6))
        for i in range(len(hemi) - 1):
            k.tri(v3(hemi[i][0], g + H, hemi[i][1]), v3(hemi[i + 1][0], g + H, hemi[i + 1][1]), ap, roof, v3(0, 1, 0))
        if aisles:
            hemi2 = [tuple(F.p(ae + W * math.cos(t), W * math.sin(t))) for t in np.linspace(-math.pi / 2, math.pi / 2, 11)]
            k.prism(hemi2, g, g + ha, stone)
    # contreforts, arcs-boutants et baies
    bay = 6.0
    for sgn in (-1, 1):
        n = int((ae - (-L + 4)) / bay)
        for i in range(n + 1):
            a = -L + 4 + i * bay
            if transept > 0 and abs(a - at) < Wn * 1.2: continue
            k.lod = (0, 1)
            k.box(F.P(a, sgn * (W + 0.7), g + ha * 0.5 + 1), (1.2, ha + 2, 1.6), stone, yaw=F.yaw())
            if gothic and aisles:
                k.lod = (0, 0)
                k.seg_box(F.P(a, sgn * (W + 0.7), g + ha + 2), F.P(a, sgn * Wn, g + H * 0.82), 0.8, 0.9, stone)
                k.cyl(F.P(a, sgn * (W + 0.7), g + ha + 2), F.P(a, sgn * (W + 0.7), g + ha + 5), 0.4, stone, 6, r2=0.02)
        k.lod = (0, 2)
        lancets(k, F, -L + 4, ae, sgn * (W if aisles else Wn), g + 2.5, g + ha - 2.5, sgn, bay, 1.8 if gothic else 1.2, round_=not gothic)
        if aisles: lancets(k, F, -L + 4, ae, sgn * Wn, g + ha + 3.0, g + H - 2.0, sgn, bay, 2.2 if gothic else 1.4, round_=not gothic)
    # façade : portails, rose
    k.lod = (0, 1)
    for bb, w_ in ((0.0, 3.6), (-Wn * 1.25, 2.4), (Wn * 1.25, 2.4)):
        if abs(bb) + w_ / 2 > W: continue
        P0, P1 = F.P(-L - 0.1, bb - w_ / 2, g), F.P(-L - 0.1, bb + w_ / 2, g)
        k.quad(P0, P1, P1 + UP * w_ * 1.4, P0 + UP * w_ * 1.4, DARK, v3(-F.u[0], 0, -F.u[1]))
        k.tri(P0 + UP * w_ * 1.4, P1 + UP * w_ * 1.4, F.P(-L - 0.1, bb, g + w_ * 2.1), DARK, v3(-F.u[0], 0, -F.u[1]))
        if gothic:   # gâble
            k.lod = (0, 0)
            k.tri(F.P(-L - 0.4, bb - w_ * 0.75, g + w_ * 2.0), F.P(-L - 0.4, bb + w_ * 0.75, g + w_ * 2.0), F.P(-L - 0.4, bb, g + w_ * 3.1), stone, v3(-F.u[0], 0, -F.u[1]))
            k.lod = (0, 1)
    if rose_: rose(k, F, -L, g + H * 0.66, Wn * 0.55)
    k.lod = (0, 2)
    top = g + H
    tw_ = min(max(W * 0.55, 8.0), 15.0)
    for (pos, th, kind_, kh) in towers:
        if pos == "west_pair": pts = [(-L + tw_ / 2, -W + tw_ / 2), (-L + tw_ / 2, W - tw_ / 2)]
        elif pos == "west_n": pts = [(-L + tw_ / 2, (-W + tw_ / 2) * (1 if F.p(0, -1)[1] < F.p(0, 1)[1] else -1))]
        elif pos == "west_s": pts = [(-L + tw_ / 2, (W - tw_ / 2) * (1 if F.p(0, -1)[1] < F.p(0, 1)[1] else -1))]
        elif pos == "west": pts = [(-L + tw_ / 2, 0.0)]
        elif pos == "crossing": pts = [(at, 0.0)]
        elif pos == "transept_n_pair":
            sg = -1 if F.p(0, -1)[1] < F.p(0, 1)[1] else 1
            pts = [(at - Wn, sg * (W + 2.5 - tw_ * 0.4)), (at + Wn, sg * (W + 2.5 - tw_ * 0.4))]
        else: pts = [(ae, 0.0)]
        side = tw_ * (0.75 if pos in ("crossing", "transept_n_pair") else 1.0)
        for (a, bb) in pts:
            y0 = g if pos != "crossing" else g + H * 0.9
            t = tower(k, tuple(F.p(a, bb)), side, y0, th - (y0 - g), stone, kind_, kh, SLATE if kind_ in ("spire", "pyramid") and roof == SLATE else (stone if kind_ in ("spire",) else (GREEN_CU if kind_ in ("dome", "lantern") else roof)), u=tuple(F.u))
            top = max(top, t)
    blocks = [block(ring, g, top - g)]
    return finish(k, city, [t[0]["ring"] for t in others], blocks, tuple(F.c))


def skyscraper(cname, lat, lon, r=80.0, h=None, mat=GLASS, band=WHITE, top="flat", top_h=0.0, minh=40.0, circle_r=0.0, floor=3.9, mullion=0.0, top_mat=None, frame_mat=None):
    """Tour : emprise BD TOPO la plus haute près du point (ou cercle de rayon circle_r), nez de dalle, résille, couronnement
    (flat, pyramid : « crayon » de la Part-Dieu, crown : couronne vitrée, lantern : lanterne de Perret, spire)."""
    city = city_of(cname); k = Kit()
    sel = find(city, lat, lon, r, minh=minh, mode="h")
    if sel:
        b, P, _ = sel[0]; ring = ccw(b["ring"]); H = h or float(b["h"]); rep = [b["ring"]]
    else:
        if circle_r <= 0: raise RuntimeError(f"{cname} : pas de tour près de {lat}, {lon}")
        c = xy(city, lat, lon); ring = ccw([(c[0] + circle_r * math.cos(2 * math.pi * i / 20), c[1] + circle_r * math.sin(2 * math.pi * i / 20)) for i in range(20)]); H = h; rep = []
    if circle_r > 0 and sel:   # silhouette ronde imposée (crayon) : cercle inscrit dans l'emprise
        cc = Polygon(ring).centroid; rr = min(circle_r, math.sqrt(Polygon(ring).area / math.pi))
        ring = ccw([(cc.x + rr * math.cos(2 * math.pi * i / 20), cc.y + rr * math.sin(2 * math.pi * i / 20)) for i in range(20)])
    P = Polygon(ring); c = np.array(P.centroid.coords[0]); g = gmin(city, ring)
    k.lod = (0, 2); k.prism(ring, g, g + H, mat)
    # nez de dalle et montants
    for i in range(len(ring)):
        a, bq = np.array(ring[i]), np.array(ring[(i + 1) % len(ring)]); e = bq - a; Ls = np.linalg.norm(e)
        if Ls < 1.0: continue
        t = e / Ls; o = np.array([t[1], -t[0]]); m = (a + bq) / 2
        if P.contains(Point(*(m + o * 0.3))): o = -o
        yaw = -math.atan2(t[1], t[0])
        k.lod = (0, 0)
        for f in np.arange(floor, H - 1.0, floor * (1 if H < 120 else 2)):
            q = m + o * 0.12; k.box(v3(q[0], g + f, q[1]), (Ls, 0.35, 0.25), band, yaw=yaw)
        if mullion > 0:
            k.lod = (0, 1)
            for j in range(1, int(Ls / mullion)):
                q = a + t * j * mullion + o * 0.15; k.box(v3(q[0], g + H / 2, q[1]), (0.3, H, 0.3), frame_mat or band, yaw=yaw)
    k.lod = (0, 2); y = g + H
    tm = top_mat or band
    if top == "pyramid":
        pyramid(k, ring, y, top_h, tm)
    elif top == "crown":
        inner = list(P.buffer(-1.5).exterior.coords)[:-1]
        k.prism(inner, y, y + top_h, GLASS); k.prism(ring, y + top_h - 0.6, y + top_h, tm)
    elif top == "lantern":   # lanterne ajourée (tour Perret)
        inner = list(P.buffer(-P.length / 40).exterior.coords)[:-1]
        k.prism(inner, y, y + top_h, DARK, top=False); k.prism(ring, y + top_h, y + top_h + 1.2, tm)
        y += top_h + 1.2
    elif top == "spire":
        k.cyl(v3(c[0], y, c[1]), v3(c[0], y + top_h, c[1]), 0.8, METAL, 8, r2=0.1)
    else:
        k.prism(list(P.buffer(-0.4).exterior.coords)[:-1], y, y + 1.2, tm)
    return finish(k, city, rep, [block(ring, g, H + top_h)], tuple(c))


def palace(cname, lat, lon, r=60.0, kinds=None, minh=6.0, h=None, mat=STONE, roof="mansard", roof_mat=SLATE, floors=None,
           pitch=4.0, center=True, columns=0, pediment=True, dome_r=0.0, dome_h=0.0, clock=False, n=6, frame=None, maxarea=1e9, pilasters=True):
    """Palais ou hôtel de ville classique sur les emprises BD TOPO près du point : murs, baies encadrées, pilastres,
    corniche, comble (mansard, hip, flat, tile), avant-corps central à colonnes et fronton face à la voie la plus
    proche, dôme et horloge en option."""
    city = city_of(cname); k = Kit()
    sel = find(city, lat, lon, r, kinds=kinds, minh=minh, n=n, maxarea=maxarea)
    if not sel: raise RuntimeError(f"{cname} : pas d'emprise près de {lat}, {lon}")
    main = sel[0]
    rings = [ccw(t[0]["ring"]) for t in sel]
    blocks = []; topmax = 0.0
    for ring, t in zip(rings, sel):
        H = h or max(float(t[0]["h"]), 10.0)
        g = gmin(city, ring) - 0.2
        P = Polygon(ring)
        k.lod = (0, 2); k.prism(ring, g, g + H, mat, top=(roof == "flat") and None)
        fl = floors or max(1, int(H / 5.0))
        for i in range(len(ring)):   # baies et pilastres sur les faces de plus de 8 m
            a, b = np.array(ring[i]), np.array(ring[(i + 1) % len(ring)]); Ls = np.linalg.norm(b - a)
            if Ls < 8.0: continue
            F = F2((a + b) / 2, (b - a)); out = 1 if not P.contains(Point(*F.p(0, 0.5))) else -1
            window_grid(k, F, -Ls / 2 + 1.5, Ls / 2 - 1.5, 0.0, g + 1.2, fl, H / fl, pitch, pitch * 0.42, min(H / fl * 0.58, 3.4), out, frame=frame or mat)
            if pilasters:
                k.lod = (0, 1)
                for j in range(int(Ls / pitch) + 1):
                    aa = -Ls / 2 + 1.5 + j * (Ls - 3.0) / max(int(Ls / pitch), 1)
                    q = F.p(aa - (Ls - 3.0) / max(int(Ls / pitch), 1) / 2 if j else aa, out * 0.15)
                    if j: k.box(v3(q[0], g + H * 0.5, q[1]), (0.6, H - 1.0, 0.3), frame or mat, yaw=F.yaw())
            k.lod = (0, 2)
            q = F.p(0, out * 0.3); k.box(v3(q[0], g + H - 0.3, q[1]), (Ls + 0.6, 0.6, 0.6), frame or mat, yaw=F.yaw())   # corniche
        y = g + H
        if roof == "mansard": mansard(k, ring, y, mat_roof=roof_mat, mat_top=ZINC)
        elif roof == "hip": hip_roof(k, ring, y, min(math.sqrt(P.area) * 0.18, 7.0), roof_mat)
        elif roof == "tile": hip_roof(k, ring, y, min(math.sqrt(P.area) * 0.1, 4.0), TILE)
        else:
            inner = P.buffer(-0.5)
            if inner.geom_type == "Polygon": k.prism(ring, y, y + 1.0, frame or mat, top=False)
        blocks.append(block(ring, g, H + 4.0)); topmax = max(topmax, H + 4.0)
    # avant-corps central face à la voie la plus proche
    ring = rings[0]; P = Polygon(ring); g = gmin(city, ring) - 0.2; H = h or max(float(main[0]["h"]), 10.0)
    cpt = np.array(P.centroid.coords[0])
    if center:
        d, q, t = nearest_track(city, *cpt)
        best = None
        for i in range(len(ring)):
            a, b = np.array(ring[i]), np.array(ring[(i + 1) % len(ring)]); Ls = np.linalg.norm(b - a)
            if Ls < 10: continue
            m = (a + b) / 2; dd = np.linalg.norm(m - q) - Ls * 0.3
            if best is None or dd < best[0]: best = (dd, a, b, Ls)
        if best:
            _, a, b, Ls = best; F = F2((a + b) / 2, b - a); out = 1 if not P.contains(Point(*F.p(0, 0.5))) else -1
            wc = min(Ls * 0.3, 24.0); dep = 1.2
            k.lod = (0, 2); k.prism(F.ring(-wc / 2, wc / 2, 0, out * dep), g, g + H + 1.5, mat)
            if pediment:
                o = v3(F.v[0] * out, 0, F.v[1] * out)
                k.tri(F.P(-wc / 2, out * dep, g + H + 1.5), F.P(wc / 2, out * dep, g + H + 1.5), F.P(0, out * dep, g + H + 1.5 + wc * 0.16), mat, o)
                k.quad(F.P(-wc / 2, out * dep, g + H + 1.5), F.P(0, out * dep, g + H + 1.5 + wc * 0.16), F.P(0, 0, g + H + 1.5 + wc * 0.16), F.P(-wc / 2, 0, g + H + 1.5), roof_mat if roof != "flat" else mat, v3(0, 1, 0))
                k.quad(F.P(0, out * dep, g + H + 1.5 + wc * 0.16), F.P(wc / 2, out * dep, g + H + 1.5), F.P(wc / 2, 0, g + H + 1.5), F.P(0, 0, g + H + 1.5 + wc * 0.16), roof_mat if roof != "flat" else mat, v3(0, 1, 0))
            if columns:
                k.lod = (0, 1)
                for j in range(columns):
                    aa = -wc / 2 + 0.8 + j * (wc - 1.6) / max(columns - 1, 1)
                    k.cyl(F.P(aa, out * (dep + 0.5), g + 1.0), F.P(aa, out * (dep + 0.5), g + H - 0.6), 0.45, mat, 10)
                k.lod = (0, 2)
                k.prism(F.ring(-wc / 2, wc / 2, out * dep, out * (dep + 1.1)), g + H - 0.6, g + H + 0.4, mat)
                k.prism(F.ring(-wc / 2, wc / 2, out * dep, out * (dep + 1.3)), g, g + 1.0, mat)
            if clock:
                k.lod = (0, 1); c3 = F.P(0, out * (dep + 0.08), g + H + 0.2)
                k.cyl(c3, c3 + v3(F.v[0] * out, 0, F.v[1] * out) * 0.15, 1.2, WHITE, 16); k.lod = (0, 2)
    if dome_r > 0:
        dome(k, tuple(cpt), dome_r, g + H + 1.0, dome_h, SLATE if roof_mat == SLATE else roof_mat, drum=dome_r * 0.5, drum_mat=mat)
        topmax = max(topmax, H + dome_h + dome_r)
    return finish(k, city, [t[0]["ring"] for t in sel], blocks, tuple(cpt))


def fortress(cname, lat, lon, r=150.0, mat=STONE, minh=4.0, towers=True, extra_h=3.0, maxarea=40000, kinds=(3,), tower_mat=None, roofs=False):
    """Forteresse (châteaux, citadelles, enceintes) sur les emprises BD TOPO de type château près du point : murs à
    talus, parapet crénelé, tours rondes aux angles saillants (toits en poivrière en option)."""
    import build_monuments as bm
    city = city_of(cname); k = Kit()
    sel = find(city, lat, lon, r, kinds=kinds, minh=minh, n=40, maxarea=maxarea)
    if not sel: raise RuntimeError(f"{cname} : pas de forteresse près de {lat}, {lon}")
    blocks = []
    for b, P, _ in sel:
        ring = ccw(b["ring"]); g = gmin(city, ring) - 0.5; top = g + max(b["h"], 6.0)
        k.lod = (0, 2); k.prism(ring, g, top, mat, top=None)
        k.lod = (0, 1); bm.talus(k, ring, g, g + min(4.0, b["h"] * 0.4), 1.0, mat)
        k.lod = (0, 2); bm.parapet(k, ring, top, mat, h=1.1, t=0.6, merlons=True)
        blocks.append(block(ring, g, top - g + 1.5))
        if towers and P.area > 300:
            n = len(ring)
            for i in range(n):
                p = np.array(ring[i]); pa = np.array(ring[i - 1]); pb = np.array(ring[(i + 1) % n])
                if np.dot(norm2(pa - p), norm2(pb - p)) > -0.3 and np.linalg.norm(p - pa) > 10:
                    rr = min(max(math.sqrt(P.area) * 0.06, 3.0), 6.0); tt = top + extra_h
                    k.lod = (0, 2); k.cyl(v3(p[0], g, p[1]), v3(p[0], tt, p[1]), rr, tower_mat or mat, 14)
                    if roofs: k.lathe(v3(p[0], 0, p[1]), [(rr * 1.05, tt), (0.05, tt + rr * 2.2)], SLATE, seg=14)
                    else: bm.parapet(k, [tuple(q) for q in bm.circle(p, rr, 14)], tt, tower_mat or mat, h=1.0, t=0.5, merlons=True, step=1.8)
    c = np.array(unary_union([t[1] for t in sel]).centroid.coords[0])
    return finish(k, city, [t[0]["ring"] for t in sel], blocks, tuple(c))


def norm2(v):
    n = np.linalg.norm(v); return v / n if n > 1e-9 else v


def arch(cname, lat, lon, L, W, H, yaw_deg=None, bays=1, mat=STONE, attic=3.0, replace_r=0.0, track_side=0.0):
    """Arc de triomphe ou porte de ville : massif percé de bays arches en plein cintre, entablement et attique.
    yaw_deg : orientation de l'axe long (degrés depuis l'est, sens trigonométrique du plan x, z) ; sinon parallèle à
    la voie la plus proche."""
    city = city_of(cname); k = Kit()
    c = xy(city, lat, lon)
    if yaw_deg is None:
        d, q, t = nearest_track(city, *c); u = t
        if track_side: c = q + np.array([-t[1], t[0]]) * track_side
    else:
        u = np.array([math.cos(math.radians(yaw_deg)), math.sin(math.radians(yaw_deg))])
    F = F2(c, u); g = city.ground(*c) - 0.2
    k.lod = (0, 2)
    wb = L / (bays * 1.6 + 0.6); pier = (L - bays * wb) / (bays + 1); hb = H * 0.62
    a = -L / 2
    for i in range(bays + 1):
        k.prism(F.ring(a, a + pier, -W / 2, W / 2), g, g + H, mat, top=False)
        if i < bays:
            a1 = a + pier; a2 = a1 + wb
            # voûte en plein cintre (intrados) et tympan
            seg = 8
            for s in range(seg):
                t0 = math.pi * s / seg; t1 = math.pi * (s + 1) / seg
                x0 = (a1 + a2) / 2 - wb / 2 * math.cos(t0); x1 = (a1 + a2) / 2 - wb / 2 * math.cos(t1)
                y0 = g + hb + wb / 2 * math.sin(t0); y1 = g + hb + wb / 2 * math.sin(t1)
                k.quad(F.P(x0, -W / 2, y0), F.P(x1, -W / 2, y1), F.P(x1, W / 2, y1), F.P(x0, W / 2, y0), mat, v3(0, -1, 0))
                for sg in (-1, 1):
                    k.quad(F.P(x0, sg * W / 2, y0), F.P(x1, sg * W / 2, y1), F.P(x1, sg * W / 2, g + H), F.P(x0, sg * W / 2, g + H), mat, v3(F.v[0] * sg, 0, F.v[1] * sg))
            k.prism(F.ring(a1, a2, -W / 2, W / 2), g + H - 0.01, g + H, mat, top=None, walls=False)
        a += pier + (wb if i < bays else 0)
    k.lod = (0, 1)
    k.prism(F.ring(-L / 2 - 0.4, L / 2 + 0.4, -W / 2 - 0.4, W / 2 + 0.4), g + H - 1.2, g + H, mat)   # entablement
    k.lod = (0, 2)
    if attic > 0: k.prism(F.ring(-L / 2, L / 2, -W / 2, W / 2), g + H, g + H + attic, mat)
    rep = [t[0]["ring"] for t in find(city, lat, lon, replace_r, n=10)] if replace_r > 0 else []
    return finish(k, city, rep, [block(F.ring(-L / 2, L / 2, -W / 2, W / 2), g, H + attic)], tuple(F.c))


# ------------------------------------------------------------------ basiliques à coupoles
def domed(cname, lat, lon, r=60.0, kinds=(1, 2), yaw_deg=None, dims=None, H=20.0, mat=STONE, roof=SLATE, domes=(), towers=(),
          statue_=None, hill=False, stripes=None, replace=True):
    """Basilique ou édifice à coupoles : corps (emprise BD TOPO ou rectangle dims = (L, W) orienté yaw_deg), coupoles
    [(a, b, rayon, hauteur, tambour, oignon, matériau)], tours [(a, b, côté, hauteur, couronnement, h. couronnement)],
    statue dorée (a, b, hauteur au-dessus du point haut, piédestal)."""
    city = city_of(cname); k = Kit()
    sel = find(city, lat, lon, r, kinds=kinds) if kinds else []
    if sel and dims is None:
        b, P, _ = sel[0]; c, u, L, W = obb(b["ring"]); ring = ccw(b["ring"])
    else:
        c = xy(city, lat, lon); u = np.array([math.cos(math.radians(yaw_deg or 0)), math.sin(math.radians(yaw_deg or 0))]); L, W = dims[0] / 2, dims[1] / 2
        ring = F2(c, u).ring(-L, L, -W, W)
    if yaw_deg is not None and dims is None: u = np.array([math.cos(math.radians(yaw_deg)), math.sin(math.radians(yaw_deg))])
    F = F2(c, u)
    g = gmin(city, F.ring(-L, L, -W, W)) - 0.3
    k.lod = (0, 2)
    if stripes:   # assises bicolores (Major de Marseille : pierre de Cassis et pierre verte de Florence)
        y = g; i = 0
        while y < g + H:
            k.prism(F.ring(-L, L, -W, W), y, min(g + H, y + 0.9), stripes[i % 2], top=False); y += 0.9; i += 1
    else:
        k.prism(F.ring(-L, L, -W, W), g, g + H, mat, top=False)
    gable_roof(k, F, -L, L, -W, W, g + H, W * 0.35, roof, mat)
    lancets(k, F, -L + 3, L - 3, -W, g + 3, g + H * 0.6, -1, 6.0, 1.6, round_=True)
    lancets(k, F, -L + 3, L - 3, W, g + 3, g + H * 0.6, 1, 6.0, 1.6, round_=True)
    top = g + H
    for (a, b_, rr, hh, drum, onion, m) in domes:
        top = max(top, dome(k, tuple(F.p(a, b_)), rr, g + H, hh, m, drum=drum, drum_mat=mat, onion=onion))
    for (a, b_, side, hh, kind_, kh) in towers:
        top = max(top, tower(k, tuple(F.p(a, b_)), side, g, hh, mat, kind_, kh, SLATE if kind_ != "dome" else roof, u=tuple(F.u)))
    if statue_:
        a, b_, sh, ped = statue_
        statue(k, F.p(a, b_), top, sh, pedestal=ped); top += sh + ped
    rep = [t[0]["ring"] for t in find(city, lat, lon, r, kinds=kinds, n=10)] if (replace and kinds) else []
    return finish(k, city, rep, [block(F.ring(-L, L, -W, W), g, top - g)], tuple(F.c))


# ------------------------------------------------------------------ ouvrages singuliers
def eiffel():
    """Tour Eiffel (1889, 330 m) vue lointaine : quatre piles en treillis courbes, arcs du premier étage, plateformes
    (57, 116, 276 m), fût unique au-dessus du deuxième étage, campanile et antennes ; peinture « brun Tour Eiffel »."""
    city = city_of("idf"); k = Kit(); c = xy(city, 48.85826, 2.29450); g = city.ground(*c)
    paint = "lm_ferronnerie#6b5a45"; u = np.array([math.cos(math.radians(-46)), math.sin(math.radians(-46))]); F = F2(c, u)
    def half(y):   # demi-largeur de l'enveloppe (profil hyperbolique) à la hauteur y
        return 62.0 * math.exp(-y / 62.0) + 2.0 if y < 276 else 3.0
    k.lod = (0, 2)
    ys = [0, 20, 40, 57, 80, 100, 116, 150, 190, 230, 276]
    for (sa, sb) in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
        for i in range(len(ys) - 1):
            y0, y1 = ys[i], ys[i + 1]
            if y0 >= 116: continue
            w0, w1 = half(y0), half(y1); pw0 = 13.0 * (1 - y0 / 140) + 2.5; pw1 = 13.0 * (1 - y1 / 140) + 2.5
            # pile : caisson ajouré (faces en treillis vues comme plans sombres, des deux côtés)
            A0 = F.P(sa * w0, sb * w0, g + y0); A1 = F.P(sa * w1, sb * w1, g + y1)
            B0 = F.P(sa * (w0 - pw0), sb * w0, g + y0); B1 = F.P(sa * (w1 - pw1), sb * w1, g + y1)
            C0 = F.P(sa * w0, sb * (w0 - pw0), g + y0); C1 = F.P(sa * w1, sb * (w1 - pw1), g + y1)
            k.quad(A0, B0, B1, A1, paint, None); k.quad(A0, C0, C1, A1, paint, None)
            k.quad(B0, A0, A1, B1, paint, None); k.quad(C0, A0, A1, C1, paint, None)
    # fût au-dessus du 2e étage
    for i in range(len(ys) - 1):
        y0, y1 = ys[i], ys[i + 1]
        if y0 < 116: continue
        w0, w1 = half(y0), half(y1)
        for (sa, sb) in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
            k.seg_box(F.P(sa * w0, sb * w0, g + y0), F.P(sa * w1, sb * w1, g + y1), 1.6, 1.6, paint)
        for s in range(4):
            a0 = [(1, 1), (1, -1), (-1, -1), (-1, 1)][s]; a1 = [(1, 1), (1, -1), (-1, -1), (-1, 1)][(s + 1) % 4]
            k.seg_box(F.P(a0[0] * w1, a0[1] * w1, g + y1), F.P(a1[0] * w1, a1[1] * w1, g + y1), 0.8, 0.8, paint)
            k.lod = (0, 1)
            k.seg_box(F.P(a0[0] * w0, a0[1] * w0, g + y0), F.P(a1[0] * w1, a1[1] * w1, g + y1), 0.5, 0.5, paint)
            k.seg_box(F.P(a1[0] * w0, a1[1] * w0, g + y0), F.P(a0[0] * w1, a0[1] * w1, g + y1), 0.5, 0.5, paint)
            k.lod = (0, 2)
    # plateformes et arcs
    for (y, hh) in ((57, 7.0), (116, 4.5), (276, 3.5)):
        w = half(y) + (3 if y < 276 else 1.5)
        k.prism(F.ring(-w, w, -w, w), g + y - hh, g + y, paint, bottom=True)
    k.lod = (0, 1)
    for s in range(4):   # arcs décoratifs du premier étage
        a0 = [(1, 1), (1, -1), (-1, -1), (-1, 1)][s]; a1 = [(1, 1), (1, -1), (-1, -1), (-1, 1)][(s + 1) % 4]
        pts = []
        for t in np.linspace(0, 1, 9):
            pa = np.array(a0) * (1 - t) + np.array(a1) * t; yy = 39 + 13 * math.sin(math.pi * t)
            pts.append(F.P(pa[0] * half(yy), pa[1] * half(yy), g + yy))
        for i in range(len(pts) - 1): k.seg_box(pts[i], pts[i + 1], 1.2, 1.2, paint)
    k.lod = (0, 2)
    k.prism(F.ring(-3.5, 3.5, -3.5, 3.5), g + 276, g + 300, paint)        # campanile
    k.cyl(F.P(0, 0, g + 300), F.P(0, 0, g + 330), 0.9, WHITE, 6, r2=0.2)   # antennes
    ring = F.ring(-64, 64, -64, 64)
    return finish(k, city, [t[0]["ring"] for t in find(city, 48.85826, 2.29450, 40, n=6)], [block(ring, g, 330)], tuple(c))


def grande_arche():
    """Grande Arche de la Défense (1989, cube évidé de 110 m, revêtu de marbre de Carrare et de verre ; « nuage »
    de toile sous l'arche), axe historique tourné de 6,33°."""
    city = city_of("idf"); k = Kit()
    sel = find(city, 48.8925, 2.2360, 140, minh=30, n=2)
    c = np.array(unary_union([t[1] for t in sel]).centroid.coords[0]) if sel else xy(city, 48.8925, 2.2360)
    u = np.array([math.cos(math.radians(-32.5)), math.sin(math.radians(-32.5))]); F = F2(c, u)
    g = city.ground(*c) + 0.0; S = 54.0; D = 50.0; t = 9.5; H = 110.0
    m = "lm_peinture_blanche#e6e4de"
    k.lod = (0, 2)
    for sg in (-1, 1):   # deux parois verticales (bureaux)
        k.prism(F.ring(min(sg * S, sg * (S - t)), max(sg * S, sg * (S - t)), -D / 2, D / 2), g + 8, g + H - t, m)
    k.prism(F.ring(-S, S, -D / 2, D / 2), g + H - t, g + H, m)             # toit
    k.prism(F.ring(-S, S, -D / 2, D / 2), g + 8, g + 8 + t * 0.6, m, top=None)     # socle
    k.lod = (0, 1)
    for sg in (-1, 1):   # résille de verre des faces avant et arrière
        for j in range(1, 12):
            y = g + 8 + j * (H - 8 - t) / 12
            k.box(F.P(0, sg * (D / 2 + 0.1), y), (2 * S, 0.3, 0.3), GLASS, yaw=F.yaw())
    k.lod = (0, 2)
    for (a, b) in ((-12, -8), (10, 6), (0, 0)):   # « nuage » (toile tendue)
        k.quad(F.P(a - 14, b - 9, g + 40), F.P(a + 14, b - 9, g + 41), F.P(a + 14, b + 9, g + 40), F.P(a - 14, b + 9, g + 41), "lm_toile#eeeeea", v3(0, -1, 0))
    k.prism(F.ring(-S - 10, S + 10, -D / 2 - 25, -D / 2), g, g + 8, STONE, top=None)
    return finish(k, city, [t[0]["ring"] for t in sel], [block(F.ring(-S, S, -D / 2, D / 2), g, H)], tuple(c))


def miroir_eau():
    """Miroir d'eau de Bordeaux (2006, 130 × 42 m, 2 cm d'eau sur dalle de granit) face à la place de la Bourse,
    côté Garonne de la ligne C : dalle sombre réfléchissante parallèle à la voie, buses de brume."""
    city = city_of("bordeaux"); k = Kit()
    c0 = xy(city, 44.84148, -0.56910)
    d, q, t = nearest_track(city, *c0)
    nrm = np.array([-t[1], t[0]])
    if np.dot(c0 - q, nrm) < 0: nrm = -nrm
    c = q + nrm * max(30.0, d)
    F = F2(c, t); g = city.ground(*c)
    k.lod = (0, 2)
    k.prism(F.ring(-65, 65, -21, 21), g - 0.05, g + 0.04, "bordure_granit")
    k.prism(F.ring(-64.2, 64.2, -20.2, 20.2), g + 0.04, g + 0.06, WATER, top=None, walls=False)
    k.lod = (0, 0)
    for i in range(-30, 31, 3):
        for j in (-12, 0, 12):
            k.cyl(F.P(i * 2.0, j, g + 0.05), F.P(i * 2.0, j, g + 0.09), 0.12, INOX, 6)
    return finish(k, city, [], [], tuple(c))


def ombriere():
    """Ombrière du Vieux-Port (Foster + Partners, 2013) : auvent de 46 × 22 m en inox poli miroir à 6 m sur huit
    poteaux élancés, quai de la Fraternité."""
    city = city_of("marseille"); k = Kit(); c = xy(city, 43.29517, 5.37437); g = city.ground(*c)
    u = np.array([math.cos(math.radians(15)), math.sin(math.radians(15))]); F = F2(c, u)
    k.lod = (0, 2); k.prism(F.ring(-23, 23, -11, 11), g + 6.0, g + 6.35, INOX, bottom=True)
    for a in (-17, -6, 6, 17):
        for b in (-6, 6):
            k.cyl(F.P(a, b, g), F.P(a, b, g + 6.0), 0.18, INOX, 8)
    return finish(k, city, [], [block(F.ring(-23, 23, -11, 11), g + 6.0, 0.4)], tuple(c))


def volcan():
    """Le Volcan (Oscar Niemeyer, 1982) : tronc de cône blanc évasé de 30 m sur la place du Havre (Espace Niemeyer),
    collerette et petit volcan voisin."""
    city = city_of("lehavre"); k = Kit()
    sel = find(city, 49.49170, 0.10930, 70, minh=12, mode="h")
    c = np.array(sel[0][1].centroid.coords[0]) if sel else xy(city, 49.49170, 0.10930)
    g = city.ground(*c) - 2.0; m = "lm_peinture_blanche#f1efe9"
    k.lod = (0, 2)
    k.lathe(v3(c[0], 0, c[1]), [(26.0, g), (22.0, g + 12), (17.5, g + 24), (16.0, g + 28.5), (15.0, g + 29.5), (0.1, g + 29.6)], m, seg=40)
    k.lathe(v3(c[0], 0, c[1]), [(16.2, g + 28.0), (16.6, g + 29.2), (15.2, g + 29.6)], m, seg=40)
    return finish(k, city, [t[0]["ring"] for t in sel], [block([tuple(p) for p in F2(c, (1, 0)).circle(0, 0, 26, 16)], g, 30)], tuple(c))


def confluences():
    """Musée des Confluences (Coop Himmelb(l)au, 2014) : « cristal » de verre facetté côté ville et « nuage » d'inox
    sur piliers, pointe vers le confluent."""
    city = city_of("lyon"); k = Kit()
    sel = find(city, 45.73260, 4.81800, 90, kinds=(4,))
    b, P, _ = sel[0]; c, u, L, W = obb(b["ring"]); F = F2(c, u)
    if F.p(L, 0)[1] < F.p(-L, 0)[1]: F = F2(c, -u)   # pointe vers le sud (le confluent)
    g = gmin(city, b["ring"])
    k.lod = (0, 2)
    cr = [F.p(-L, -W), F.p(-L * 0.35, -W * 1.05), F.p(-L * 0.3, W), F.p(-L, W * 0.8)]
    k.prism([tuple(p) for p in cr], g, g + 33, GLASS)
    pts = [(-L * 0.4, -W), (L * 0.2, -W * 1.1), (L, -W * 0.2), (L * 1.05, W * 0.15), (L * 0.3, W), (-L * 0.4, W * 0.9)]
    base = [tuple(F.p(a, b_)) for a, b_ in pts]; top = [tuple(F.p(a * 0.9, b_ * 0.8)) for a, b_ in pts]
    y0, y1 = g + 9, g + 37
    for i in range(len(pts)):
        a0, a1 = base[i], base[(i + 1) % len(pts)]; t0, t1 = top[i], top[(i + 1) % len(pts)]
        k.quad(v3(a0[0], y0, a0[1]), v3(a1[0], y0, a1[1]), v3(t1[0], y1 - (i % 3) * 4, t1[1]), v3(t0[0], y1 - ((i - 1) % 3) * 4, t0[1]), INOX, None)
    k.poly([v3(p[0], y0, p[1]) for p in base], INOX, -UP)
    k.poly([v3(p[0], y1 - 4, p[1]) for p in top], INOX, UP)
    for (a, b_) in ((-L * 0.1, -W * 0.5), (L * 0.4, 0), (-L * 0.1, W * 0.5)):
        k.cyl(F.P(a, b_, g), F.P(a, b_, g + 9), 2.2, CONC, 10)
    return finish(k, city, [b["ring"]], [block(F.ring(-L, L * 1.05, -W * 1.1, W), g, 37)], tuple(F.c))


def conversation_nice():
    """« Conversation à Nice » (Jaume Plensa, 2007) : sept personnages assis, translucides et éclairés la nuit, sur des
    mâts de 11 m de part et d'autre de la ligne 1 (place Masséna, avenue Jean-Médecin) ; fontaine du Soleil."""
    city = city_of("nice"); k = Kit()
    c0 = xy(city, 43.69760, 7.27015); d, q, t = nearest_track(city, *c0); nrm = np.array([-t[1], t[0]])
    g = city.ground(*q)
    k.lod = (0, 2)
    for i in range(7):
        s = (i - 3) * 22.0; side = 1 if i % 2 == 0 else -1
        p = q + t * s + nrm * side * 9.0; gp = city.ground(*p)
        k.cyl(v3(p[0], gp, p[1]), v3(p[0], gp + 11.0, p[1]), 0.12, METAL, 8)
        k.box(v3(p[0], gp + 11.6, p[1]), (1.0, 1.2, 1.0), "lm_peinture_blanche#f2efe6", yaw=i * 0.9)   # corps
        k.box(v3(p[0] + 0.45, gp + 11.1, p[1]), (0.9, 0.35, 0.8), "lm_peinture_blanche#f2efe6", yaw=i * 0.9)   # jambes
        k.lathe(v3(p[0], 0, p[1]), [(0.01, gp + 12.2), (0.3, gp + 12.45), (0.01, gp + 12.8)], "lm_peinture_blanche#f2efe6", seg=8)
    # fontaine du Soleil (Apollon, 7 m) au sud de la place
    fs = xy(city, 43.69620, 7.27070); gf = city.ground(*fs)
    k.lathe(v3(fs[0], 0, fs[1]), [(9.0, gf), (9.0, gf + 0.6), (8.6, gf + 0.6), (8.6, gf + 0.2), (0.1, gf + 0.2)], STONE, seg=24)
    k.prism([tuple(p) for p in F2(fs, (1, 0)).circle(0, 0, 8.6, 24)], gf + 0.15, gf + 0.25, WATER, walls=False)
    statue(k, fs, gf, 7.0, mat="pierre_taille#f0efe9", pedestal=2.0)
    return finish(k, city, [], [], tuple(q))


def chevalement_couriot():
    """Puits Couriot (Saint-Étienne) : chevalement métallique de 1913 (≈ 30 m), molettes, bâtiment de la recette ; les
    crassiers voisins relèvent du relief."""
    city = city_of("saintetienne"); k = Kit(); c = xy(city, 45.43470, 4.37180); g = city.ground(*c)
    F = F2(c, (1, 0)); m = "lm_ferronnerie#4b4f52"
    k.lod = (0, 2)
    for (a, b) in ((-3, -3), (3, -3), (3, 3), (-3, 3)):
        k.seg_box(F.P(a, b, g), F.P(a * 0.6, b * 0.6, g + 30), 0.5, 0.5, m)
    for y in (8, 16, 24):
        for s in range(4):
            a0 = [(-1, -1), (1, -1), (1, 1), (-1, 1)][s]; a1 = [(-1, -1), (1, -1), (1, 1), (-1, 1)][(s + 1) % 4]
            f = 3 - 1.2 * y / 30
            k.seg_box(F.P(a0[0] * f, a0[1] * f, g + y), F.P(a1[0] * f, a1[1] * f, g + y), 0.35, 0.35, m)
    for s in (-1, 1):   # bigues inclinées
        k.seg_box(F.P(-12, s * 3, g), F.P(-1.5, s * 2, g + 28), 0.6, 0.6, m)
    for b in (-1.2, 1.2):   # molettes
        k.cyl(F.P(0, b - 0.15, g + 31), F.P(0, b + 0.15, g + 31), 3.0, m, 16)
    k.prism(F.ring(-8, 8, -6, 6), g, g + 9, BRICK)
    gable_roof(k, F, -8, 8, -6, 6, g + 9, 3, SLATE, BRICK)
    return finish(k, city, [t[0]["ring"] for t in find(city, 45.43470, 4.37180, 18, n=4)], [block(F.ring(-12, 8, -6, 6), g, 34)], tuple(c))


def pont_avignon():
    """Pont Saint-Bénézet (XIIe-XIIIe) : quatre arches en anse de panier sur piles à avant-becs et la chapelle
    Saint-Nicolas sur la deuxième pile, depuis la rive d'Avignon vers le nord-ouest."""
    city = city_of("avignon"); k = Kit(); c = xy(city, 43.95390, 4.80460); g = city.ground(*c)
    u = np.array([math.cos(math.radians(150)), math.sin(math.radians(150))]); F = F2(c, -u)
    k.lod = (0, 2); W = 2.4; span = 33.0; yd = g + 13.0
    for i in range(5):
        a = -60 + i * span
        k.prism(F.ring(a - 4, a + 4, -W - 1.5, W + 1.5), g - 6, yd - 4, STONE)
        k.prism([tuple(F.p(a + 4, -W - 1.5)), tuple(F.p(a + 8, 0)), tuple(F.p(a + 4, W + 1.5))], g - 6, yd - 6, STONE)
        if i < 4:
            seg = 10
            for s in range(seg):
                t0 = math.pi * s / seg; t1 = math.pi * (s + 1) / seg
                x0 = a + 4 + (span - 8) / 2 * (1 - math.cos(t0)); x1 = a + 4 + (span - 8) / 2 * (1 - math.cos(t1))
                y0 = yd - 9 + 7 * math.sin(t0); y1 = yd - 9 + 7 * math.sin(t1)
                k.quad(F.P(x0, -W, y0), F.P(x1, -W, y1), F.P(x1, W, y1), F.P(x0, W, y0), STONE, v3(0, -1, 0))
                for sg in (-1, 1): k.quad(F.P(x0, sg * W, y0), F.P(x1, sg * W, y1), F.P(x1, sg * W, yd), F.P(x0, sg * W, yd), STONE, v3(F.v[0] * sg, 0, F.v[1] * sg))
            k.prism(F.ring(a, a + span, -W, W), yd - 0.01, yd + 0.8, STONE, walls=False)
    a = -60 + span
    k.prism(F.ring(a - 5, a + 5, -W - 1.2, W + 1.2), yd, yd + 6, STONE)
    gable_roof(k, F, a - 5, a + 5, -W - 1.2, W + 1.2, yd + 6, 2.5, "toiture#9c8b74", STONE)
    tower(k, tuple(F.p(a + 4, 0)), 2.2, yd + 6, 3.0, STONE, "pyramid", 2.0, "toiture#9c8b74", u=tuple(F.u), openings=False)
    return finish(k, city, [], [block(F.ring(-64, 76, -4, 4), g - 6, 19)], tuple(c))


def gare_strasbourg():
    """Gare de Strasbourg : bâtiment voyageurs de 1883 (grès, pavillons d'angle, horloge) sous la verrière en
    « bulle » de 2007 (120 m, arcs métalliques), face à la place de la Gare et à la station souterraine."""
    city = city_of("strasbourg"); k = Kit()
    sel = find(city, 48.58500, 7.73460, 160, kinds=(5,), n=3)
    if not sel: sel = find(city, 48.58500, 7.73460, 120, minh=12, n=1)
    b, P, _ = sel[0]; c, u, L, W = obb(b["ring"]); F = F2(c, u)
    if np.dot(F.v, xy(city, 48.5843, 7.7360) - c) < 0: F = F2(c, -u)   # +v vers la place
    g = gmin(city, b["ring"]); H = 16.0; sand = "pierre_taille#c9a690"
    k.lod = (0, 2)
    k.prism(F.ring(-L, L, -W, W), g, g + H, sand)
    hip_roof(k, F.ring(-L, L, -W, W), g + H, 4.0, SLATE)
    for a in (-L + 9, 0, L - 9):
        k.prism(F.ring(a - 8, a + 8, W - 1, W + 1.5), g, g + H + 5, sand)
        hip_roof(k, F.ring(a - 8, a + 8, W - 1, W + 1.5), g + H + 5, 4.0, SLATE)
    window_grid(k, F, -L + 2, L - 2, W + 1.5, g + 1.5, 2, 6.5, 4.5, 2.4, 4.0, 1, frame=sand)
    k.lod = (0, 1); c3 = F.P(0, W + 1.6, g + H + 2.5); k.cyl(c3, c3 + v3(F.v[0], 0, F.v[1]) * 0.2, 1.4, WHITE, 16)
    # verrière : demi-coque en arcs le long de la façade (largeur 25 m, hauteur 23 m)
    k.lod = (0, 2)
    Lb = min(L, 60.0)
    prof = [(0.0, 23.0), (6.0, 22.0), (12.0, 19.0), (17.0, 15.0), (21.0, 10.0), (24.0, 4.5), (25.0, 0.0)]
    for j in range(len(prof) - 1):
        (b0, y0), (b1, y1) = prof[j], prof[j + 1]
        k.quad(F.P(-Lb, W + 1.5 + b0, g + y0), F.P(Lb, W + 1.5 + b0, g + y0), F.P(Lb, W + 1.5 + b1, g + y1), F.P(-Lb, W + 1.5 + b1, g + y1), "vitrage", v3(0, 1, 0))
    k.lod = (0, 1)
    for a in np.arange(-Lb, Lb + 0.1, 6.0):
        for j in range(len(prof) - 1):
            (b0, y0), (b1, y1) = prof[j], prof[j + 1]
            k.seg_box(F.P(a, W + 1.5 + b0, g + y0), F.P(a, W + 1.5 + b1, g + y1), 0.25, 0.35, WHITE)
    k.lod = (0, 2)
    return finish(k, city, [b["ring"]], [block(F.ring(-L, L, -W, W + 27), g, H + 5)], tuple(F.c))


def pylones_recouvrance():
    """Pont de Recouvrance (Brest, 1954, pont levant de 88 m) : quatre pylônes de béton de 64 m aux extrémités de
    la travée levante, de part et d'autre du tablier franchi par la ligne A, contrepoids et câbles."""
    city = city_of("brest"); k = Kit()
    c0 = xy(city, 48.38420, -4.49390); d, q, t = nearest_track(city, *c0); nrm = np.array([-t[1], t[0]])
    g = city.ground(*q) + 0.0
    yd = g
    k.lod = (0, 2)
    for s in (-44.0, 44.0):
        for sd in (-1, 1):
            p = q + t * s + nrm * sd * 9.5
            F = F2(p, t)
            k.prism(F.ring(-3.5, 3.5, -2.2, 2.2), yd - 25, yd + 64, CONC)
            k.prism(F.ring(-4.0, 4.0, -2.6, 2.6), yd + 62, yd + 65, CONC)
            k.lod = (0, 1)
            for y in np.arange(yd + 4, yd + 60, 6): k.box(F.P(0, sd * 2.25, y), (5.0, 0.25, 0.08), DARK, yaw=F.yaw())
            k.lod = (0, 2)
        Fm = F2(q + t * s, t)
        k.prism(Fm.ring(-2.0, 2.0, -11.5, 11.5), yd + 60, yd + 63, CONC)   # entretoise haute
    return finish(k, city, [], [], tuple(q))


# ------------------------------------------------------------------ catalogue P4 (2 à 4 monuments par ville)
# Coordonnées : points WGS84 vérifiés sur les emprises BD TOPO (le constructeur prend l'emprise du type attendu la plus
# grande ou la plus haute près du point). Portées LOD [0, LOD1, LOD2, fin] en m.
R_BIG = [0, 400, 1400, 9000]; R_MED = [0, 260, 900, 4000]; R_SMALL = [0, 150, 500, 1800]; R_FAR = [0, 800, 3000, 16000]
RED_BRICK = "facade_brique#b8735a"; SAND_RED = "pierre_taille#b98b7c"; VOLVIC = "pierre_taille#3d3c3e"; BLOND = "pierre_taille#ddcfae"
BLACK = "pierre_taille#5a5753"

def S(mid, city, fn, ranges, name, shot):
    return (mid, city, f"{city}/{mid.split('_', 1)[1]}", fn, ranges, {"landmark": name, "lot": "P4", "shot": shot})

SPECS_P4 = [
    # Lyon
    S("lyon_fourviere", "lyon", lambda: domed("lyon", 45.76230, 4.82250, 60, kinds=(1,), H=22.0, mat="pierre_taille#e6e1d6", roof=SLATE,
        towers=((-30, -10, 7.5, 48.0, "flat", 2.0), (-30, 10, 7.5, 48.0, "flat", 2.0), (30, -10, 7.5, 48.0, "flat", 2.0), (30, 10, 7.5, 48.0, "flat", 2.0)),
        statue_=(36, 0, 5.0, 0.0)), R_FAR, "Basilique Notre-Dame de Fourvière", [700.0, 220.0, 120.0, 40.0]),
    S("lyon_tour_part_dieu", "lyon", lambda: skyscraper("lyon", 45.76120, 4.85560, 120, h=142.0, mat="pierre_taille#c9906f", band="pierre_taille#b97c5c", top="pyramid", top_h=23.0, circle_r=20.0, minh=100.0), R_FAR, "Tour Part-Dieu (Crayon)", [450.0, 120.0, 210.0, 90.0]),
    S("lyon_tour_incity", "lyon", lambda: skyscraper("lyon", 45.75990, 4.85200, 120, mat=GLASS, band=WHITE, top="crown", top_h=12.0, minh=120.0, mullion=3.0), R_FAR, "Tour Incity", [450.0, 120.0, 250.0, 90.0]),
    S("lyon_confluences", "lyon", confluences, R_MED, "Musée des Confluences", [200.0, 70.0, 170.0, 15.0]),
    # Bordeaux
    S("bordeaux_place_bourse", "bordeaux", lambda: palace("bordeaux", 44.84140, -0.57010, 75, minh=10.0, h=17.0, mat=BLOND, roof="mansard", pitch=4.2, columns=4, n=6, maxarea=6000), R_MED, "Place de la Bourse", [180.0, 45.0, 90.0, 10.0]),
    S("bordeaux_miroir_eau", "bordeaux", miroir_eau, R_SMALL, "Miroir d'eau", [140.0, 35.0, 80.0, 0.0]),
    S("bordeaux_grand_theatre", "bordeaux", lambda: palace("bordeaux", 44.84270, -0.57440, 40, kinds=(4,), h=19.0, mat=BLOND, roof="hip", roof_mat=ZINC, floors=2, pitch=4.6, columns=12, pediment=False, n=1), R_MED, "Grand Théâtre", [150.0, 40.0, 200.0, 10.0]),
    S("bordeaux_cathedrale", "bordeaux", lambda: church("bordeaux", 44.83780, -0.57760, 60, h=29.0, towers=(("transept_n_pair", 81.0, "spire", 28.0),), rose_=True, stone=BLOND), R_BIG, "Cathédrale Saint-André", [260.0, 90.0, 150.0, 30.0]),
    # Strasbourg
    S("strasbourg_cathedrale", "strasbourg", lambda: church("strasbourg", 48.58180, 7.75090, 60, h=32.0, stone=SAND_RED, roof="toiture#7f6a5c",
        towers=(("west_pair", 66.0, "flat", 1.0), ("west_n", 142.0, "spire", 50.0)), transept=0.6), R_FAR, "Cathédrale Notre-Dame", [420.0, 140.0, 200.0, 50.0]),
    S("strasbourg_gare", "strasbourg", gare_strasbourg, R_MED, "Gare centrale", [180.0, 50.0, 200.0, 8.0]),
    S("strasbourg_parlement", "strasbourg", lambda: skyscraper("strasbourg", 48.59740, 7.76810, 80, mat=GLASS, band="lm_bois#9a7a55", top="flat", minh=40.0, mullion=2.5, frame_mat="lm_bois#9a7a55"), R_BIG, "Parlement européen (Louise-Weiss)", [300.0, 80.0, 200.0, 25.0]),
    # Lille
    S("lille_beffroi", "lille", lambda: _belfry("lille", 50.63290, 3.07110, 104.0), R_FAR, "Beffroi de l'hôtel de ville", [420.0, 120.0, 200.0, 50.0]),
    S("lille_gare_flandres", "lille", lambda: palace("lille", 50.63650, 3.07040, 60, kinds=(5,), minh=8.0, h=19.0, mat=STONE, roof="mansard", pitch=5.0, columns=0, clock=True, n=1), R_MED, "Gare Lille-Flandres", [170.0, 40.0, 250.0, 10.0]),
    S("lille_tour_euralille", "lille", lambda: skyscraper("lille", 50.63790, 3.07520, 130, mat=GLASS, band="beton_banche#b9b6ad", top="flat", minh=90.0, mullion=3.0), R_FAR, "Tour de Lille (Euralille)", [400.0, 120.0, 230.0, 60.0]),
    # Toulouse
    S("toulouse_capitole", "toulouse", lambda: palace("toulouse", 43.60450, 1.44330, 70, kinds=(4,), h=20.0, mat=RED_BRICK, roof="tile", frame=STONE, columns=8, pitch=4.5, n=2), R_MED, "Capitole", [200.0, 60.0, 200.0, 10.0]),
    S("toulouse_saint_sernin", "toulouse", lambda: church("toulouse", 43.60830, 1.44190, 60, h=21.0, gothic=False, stone=RED_BRICK, roof=TILE, towers=(("crossing", 67.0, "octagon", 32.0),), rose_=False), R_BIG, "Basilique Saint-Sernin", [320.0, 120.0, 200.0, 30.0]),
    S("toulouse_dome_grave", "toulouse", lambda: domed("toulouse", 43.59960, 1.43280, 50, kinds=(1, 2, 4), dims=(30.0, 30.0), H=18.0, mat=RED_BRICK, roof=TILE, domes=((0, 0, 12.0, 20.0, 8.0, False, GREEN_CU),), replace=False), R_BIG, "Dôme de la Grave", [300.0, 90.0, 120.0, 25.0]),
    # Marseille
    S("marseille_notre_dame_garde", "marseille", lambda: domed("marseille", 43.28400, 5.37130, 60, kinds=None, dims=(56.0, 16.0), yaw_deg=0.0, H=14.0, stripes=("pierre_taille#e8e2d4", "pierre_taille#7f8a6f"), roof=SLATE,
        domes=((8, 0, 6.5, 8.0, 4.0, False, "pierre_taille#d9d2c0"),), towers=((-24, 0, 11.0, 41.0, "dome", 5.0),), statue_=(-24, 0, 11.2, 12.5)), R_FAR, "Notre-Dame-de-la-Garde", [650.0, 180.0, 180.0, 40.0]),
    S("marseille_major", "marseille", lambda: domed("marseille", 43.29940, 5.36530, 90, kinds=(1, 2), H=24.0, stripes=("pierre_taille#d8cdb4", "pierre_taille#6e7b63"), roof=SLATE,
        domes=((25, 0, 9.0, 13.0, 8.0, False, "pierre_taille#d8cdb4"), (-5, 0, 6.0, 9.0, 5.0, False, "pierre_taille#d8cdb4"), (-25, 0, 5.0, 8.0, 4.0, False, "pierre_taille#d8cdb4")),
        towers=((-45, -12, 8.0, 52.0, "dome", 6.0), (-45, 12, 8.0, 52.0, "dome", 6.0))), R_BIG, "Cathédrale de la Major", [300.0, 90.0, 230.0, 25.0]),
    S("marseille_ombriere", "marseille", ombriere, R_SMALL, "Ombrière du Vieux-Port", [70.0, 18.0, 150.0, 4.0]),
    S("marseille_tour_cma_cgm", "marseille", lambda: skyscraper("marseille", 43.31330, 5.36660, 90, mat=GLASS, band=WHITE, top="flat", minh=90.0, mullion=2.4), R_FAR, "Tour CMA CGM", [420.0, 120.0, 160.0, 70.0]),
    # Nice
    S("nice_negresco", "nice", lambda: palace("nice", 43.69460, 7.25810, 40, minh=10.0, h=24.0, mat="facade_enduit#efe6d8", roof="flat", pitch=3.6, columns=0, pediment=False, dome_r=8.5, dome_h=11.0, roof_mat="toiture#d88d8d", n=1), R_MED, "Hôtel Negresco", [160.0, 40.0, 200.0, 15.0]),
    S("nice_massena", "nice", conversation_nice, R_SMALL, "Place Masséna (Conversation à Nice, fontaine du Soleil)", [90.0, 25.0, 200.0, 8.0]),
    S("nice_saint_nicolas", "nice", lambda: domed("nice", 43.70360, 7.25330, 40, kinds=(1, 2), H=16.0, mat="facade_brique#b07a5e", roof="toiture#6f9a8a",
        domes=((0, 0, 4.5, 9.0, 6.0, True, GREEN_CU), (-8, -6, 2.5, 6.0, 3.0, True, GREEN_CU), (-8, 6, 2.5, 6.0, 3.0, True, GREEN_CU), (8, -6, 2.5, 6.0, 3.0, True, GREEN_CU), (8, 6, 2.5, 6.0, 3.0, True, GREEN_CU)),
        towers=((-14, 0, 5.0, 28.0, "dome", 5.0),)), R_MED, "Cathédrale Saint-Nicolas", [160.0, 45.0, 150.0, 15.0]),
    # Montpellier
    S("montpellier_opera_comedie", "montpellier", lambda: palace("montpellier", 43.60850, 3.88010, 45, kinds=(4,), h=22.0, mat=BLOND, roof="hip", roof_mat=ZINC, floors=3, columns=6, n=1), R_MED, "Opéra Comédie", [140.0, 35.0, 200.0, 10.0]),
    S("montpellier_arc_triomphe", "montpellier", lambda: arch("montpellier", 43.61120, 3.87270, 18.0, 7.0, 15.0, yaw_deg=None, bays=1, mat=BLOND, attic=3.0), R_SMALL, "Arc de triomphe (Porte du Peyrou)", [70.0, 15.0, 160.0, 8.0]),
    # Grenoble
    S("grenoble_tour_perret", "grenoble", lambda: skyscraper("grenoble", 45.18400, 5.73460, 80, h=80.0, mat=CONC, band=CONC, top="lantern", top_h=14.0, minh=0.0, circle_r=5.5), R_FAR, "Tour Perret", [300.0, 70.0, 200.0, 45.0]),
    S("grenoble_bastille", "grenoble", lambda: fortress("grenoble", 45.19870, 5.72530, 220, mat="pierre_taille#b8b0a0", minh=2.0), R_FAR, "Fort de la Bastille", [500.0, 150.0, 180.0, 0.0]),
    # Île-de-France
    S("idf_tour_eiffel", "idf", eiffel, R_FAR, "Tour Eiffel", [900.0, 200.0, 150.0, 120.0]),
    S("idf_grande_arche", "idf", grande_arche, R_FAR, "Grande Arche de la Défense", [320.0, 60.0, 120.0, 50.0]),
    S("idf_sacre_coeur", "idf", lambda: domed("idf", 48.88670, 2.34310, 70, kinds=(1, 2), H=20.0, mat="pierre_taille#f2efe8", roof="pierre_taille#f2efe8",
        domes=((5, 0, 8.5, 16.0, 14.0, False, "pierre_taille#f2efe8"), (-12, -10, 3.5, 6.0, 4.0, False, "pierre_taille#f2efe8"), (-12, 10, 3.5, 6.0, 4.0, False, "pierre_taille#f2efe8")),
        towers=((30, 0, 7.0, 84.0, "dome", 6.0),)), R_FAR, "Basilique du Sacré-Cœur", [700.0, 200.0, 170.0, 40.0]),
    S("idf_basilique_saint_denis", "idf", lambda: church("idf", 48.93550, 2.35940, 60, h=29.0, towers=(("west_s", 58.0, "flat", 1.0),), stone=STONE), R_BIG, "Basilique Saint-Denis", [220.0, 70.0, 230.0, 25.0]),
    # Reims
    S("reims_cathedrale", "reims", lambda: church("reims", 49.25360, 4.03410, 60, h=38.0, towers=(("west_pair", 81.0, "flat", 4.0),), transept=0.6), R_FAR, "Cathédrale Notre-Dame", [380.0, 120.0, 250.0, 40.0]),
    S("reims_porte_mars", "reims", lambda: arch("reims", 49.25950, 4.02980, 32.0, 6.0, 13.0, yaw_deg=None, bays=3, mat="pierre_taille#cfc4ae", attic=0.0), R_SMALL, "Porte de Mars", [80.0, 20.0, 200.0, 6.0]),
    # Dijon
    S("dijon_tour_philippe_le_bon", "dijon", lambda: _belfry("dijon", 47.32160, 5.04150, 46.0, top="flat", mat=BLOND, side=10.0), R_BIG, "Palais des ducs (tour Philippe le Bon)", [250.0, 70.0, 160.0, 25.0]),
    S("dijon_saint_benigne", "dijon", lambda: church("dijon", 47.32150, 5.03490, 60, h=28.0, roof="toiture#b0883a", towers=(("west_pair", 45.0, "pyramid", 10.0), ("crossing", 93.0, "spire", 45.0)), stone=BLOND), R_FAR, "Cathédrale Saint-Bénigne", [330.0, 100.0, 230.0, 35.0]),
    S("dijon_porte_guillaume", "dijon", lambda: arch("dijon", 47.32225, 5.03600, 16.0, 6.0, 16.0, yaw_deg=None, bays=1, mat=BLOND, attic=2.5), R_SMALL, "Porte Guillaume", [70.0, 15.0, 120.0, 8.0]),
    # Rouen
    S("rouen_cathedrale", "rouen", lambda: church("rouen", 49.44020, 1.09480, 70, h=28.0, towers=(("west_pair", 77.0, "flat", 5.0), ("crossing", 151.0, "iron", 70.0))), R_FAR, "Cathédrale Notre-Dame", [420.0, 140.0, 220.0, 50.0]),
    S("rouen_gros_horloge", "rouen", lambda: _gros_horloge(), R_SMALL, "Gros-Horloge", [70.0, 20.0, 160.0, 10.0]),
    # Caen
    S("caen_chateau", "caen", lambda: fortress("caen", 49.18630, -0.36260, 180, mat="facade_tuffeau#e2d8bf"), R_BIG, "Château de Caen", [330.0, 110.0, 200.0, 0.0]),
    S("caen_abbaye_hommes", "caen", lambda: church("caen", 49.18140, -0.37270, 80, h=24.0, gothic=False, stone="facade_tuffeau#e6dcc4", towers=(("west_pair", 82.0, "spire", 38.0), ("crossing", 55.0, "pyramid", 8.0))), R_FAR, "Abbaye-aux-Hommes", [330.0, 100.0, 200.0, 30.0]),
    # Le Havre
    S("lehavre_saint_joseph", "lehavre", lambda: _saint_joseph(), R_FAR, "Église Saint-Joseph", [450.0, 130.0, 200.0, 50.0]),
    S("lehavre_hotel_de_ville", "lehavre", lambda: palace("lehavre", 49.49450, 0.10700, 90, kinds=(4,), h=14.0, mat="beton_banche#c3bba9", roof="flat", pitch=3.6, columns=0, pediment=False, n=2, maxarea=12000), R_MED, "Hôtel de ville", [250.0, 60.0, 200.0, 20.0]),
    S("lehavre_volcan", "lehavre", volcan, R_MED, "Le Volcan (Espace Niemeyer)", [140.0, 45.0, 230.0, 10.0]),
    # Brest
    S("brest_chateau", "brest", lambda: fortress("brest", 48.38380, -4.49500, 200, mat="pierre_taille#8f8c86"), R_BIG, "Château de Brest", [350.0, 110.0, 180.0, 0.0]),
    S("brest_recouvrance", "brest", pylones_recouvrance, R_BIG, "Pont de Recouvrance (pylônes)", [220.0, 60.0, 120.0, 25.0]),
    # Tours
    S("tours_cathedrale", "tours", lambda: church("tours", 47.39550, 0.69430, 60, h=29.0, towers=(("west_pair", 68.0, "lantern", 12.0),), stone="facade_tuffeau#e9e1cc"), R_BIG, "Cathédrale Saint-Gatien", [300.0, 90.0, 230.0, 30.0]),
    S("tours_hotel_de_ville", "tours", lambda: palace("tours", 47.39060, 0.68890, 50, kinds=(4,), h=20.0, mat="facade_tuffeau#ebe3cf", roof="mansard", columns=4, clock=True, dome_r=0.0, n=1), R_MED, "Hôtel de ville", [150.0, 40.0, 180.0, 12.0]),
    # Orléans
    S("orleans_cathedrale", "orleans", lambda: church("orleans", 47.90190, 1.90970, 60, h=32.0, towers=(("west_pair", 88.0, "lantern", 14.0), ("crossing", 114.0, "spire", 50.0))), R_FAR, "Cathédrale Sainte-Croix", [380.0, 110.0, 270.0, 40.0]),
    S("orleans_jeanne_arc", "orleans", lambda: _equestrian("orleans", 47.90240, 1.90450, 1.4), R_SMALL, "Statue de Jeanne d'Arc (place du Martroi)", [35.0, 10.0, 200.0, 5.0]),
    # Le Mans
    S("lemans_cathedrale", "lemans", lambda: church("lemans", 48.01050, 0.19900, 70, h=34.0, towers=(("transept_n_pair", 64.0, "flat", 2.0),), transept=0.7), R_FAR, "Cathédrale Saint-Julien", [350.0, 110.0, 120.0, 35.0]),
    S("lemans_enceinte", "lemans", lambda: fortress("lemans", 48.00920, 0.19650, 220, mat="pierre_taille#c9a890", minh=2.0, maxarea=8000, kinds=(3, 4)), R_MED, "Enceinte gallo-romaine (Cité Plantagenêt)", [220.0, 80.0, 250.0, 0.0]),
    # Besançon
    S("besancon_citadelle", "besancon", lambda: fortress("besancon", 47.23180, 6.03130, 260, mat="pierre_taille#b9b4a6", minh=2.0), R_FAR, "Citadelle", [550.0, 180.0, 300.0, 0.0]),
    S("besancon_cathedrale", "besancon", lambda: church("besancon", 47.23430, 6.02980, 60, h=24.0, gothic=False, towers=(("west", 55.0, "dome", 8.0),), stone="pierre_taille#cdbfa5", rose_=False), R_BIG, "Cathédrale Saint-Jean", [260.0, 80.0, 200.0, 25.0]),
    # Mulhouse
    S("mulhouse_temple_saint_etienne", "mulhouse", lambda: church("mulhouse", 47.74660, 7.33890, 50, h=22.0, towers=(("west", 97.0, "spire", 50.0),), stone=SAND_RED, aisles=True), R_FAR, "Temple Saint-Étienne", [300.0, 90.0, 200.0, 35.0]),
    S("mulhouse_tour_europe", "mulhouse", lambda: skyscraper("mulhouse", 47.74810, 7.34210, 120, mat=GLASS, band="beton_banche#c8c2b4", top="crown", top_h=8.0, minh=60.0), R_FAR, "Tour de l'Europe", [380.0, 120.0, 180.0, 60.0]),
    # Clermont-Ferrand
    S("clermont_cathedrale", "clermont", lambda: church("clermont", 45.77890, 3.08660, 70, h=28.6, stone=VOLVIC, roof="toiture#4a4b4e", towers=(("west_pair", 108.0, "spire", 48.0),)), R_FAR, "Cathédrale Notre-Dame-de-l'Assomption", [420.0, 130.0, 210.0, 45.0]),
    S("clermont_vercingetorix", "clermont", lambda: _equestrian("clermont", 45.77690, 3.08140, 1.6), R_SMALL, "Statue de Vercingétorix (place de Jaude)", [40.0, 12.0, 200.0, 6.0]),
    # Saint-Étienne
    S("saintetienne_hotel_de_ville", "saintetienne", lambda: palace("saintetienne", 45.43940, 4.38680, 50, kinds=(4,), h=19.0, mat="pierre_taille#d4cbb6", roof="mansard", columns=6, clock=True, n=1), R_MED, "Hôtel de ville", [150.0, 45.0, 180.0, 12.0]),
    S("saintetienne_couriot", "saintetienne", chevalement_couriot, R_MED, "Puits Couriot", [110.0, 30.0, 200.0, 15.0]),
    # Avignon
    S("avignon_palais_papes", "avignon", lambda: fortress("avignon", 43.95080, 4.80750, 120, kinds=(3, 4, 1, 2, 0), mat="pierre_taille#d6c7a6", minh=12.0, towers=False), R_FAR, "Palais des Papes", [380.0, 120.0, 230.0, 20.0]),
    S("avignon_pont", "avignon", pont_avignon, R_BIG, "Pont Saint-Bénézet", [220.0, 50.0, 230.0, 8.0]),
    # Aubagne
    S("aubagne_hotel_de_ville", "aubagne", lambda: palace("aubagne", 43.29270, 5.57030, 60, kinds=(4,), h=13.0, mat="facade_enduit#e8d2b0", roof="tile", frame=STONE, columns=0, clock=True, n=1), R_MED, "Hôtel de ville", [110.0, 30.0, 180.0, 10.0]),
    S("aubagne_saint_sauveur", "aubagne", lambda: church("aubagne", 43.29310, 5.56900, 90, h=14.0, gothic=False, aisles=False, roof=TILE, stone="pierre_taille#e0cfae", towers=(("west", 30.0, "pyramid", 5.0),), rose_=False, transept=0.0), R_MED, "Église Saint-Sauveur", [130.0, 40.0, 200.0, 12.0]),
    # Valenciennes
    S("valenciennes_hotel_de_ville", "valenciennes", lambda: palace("valenciennes", 50.35770, 3.52330, 50, kinds=(4,), h=19.0, mat="pierre_taille#ddd4c0", roof="mansard", columns=4, clock=True, n=1), R_MED, "Hôtel de ville", [140.0, 40.0, 180.0, 12.0]),
    S("valenciennes_saint_cordon", "valenciennes", lambda: church("valenciennes", 50.36060, 3.51630, 70, h=24.0, stone="facade_brique#8e4f3e", towers=(("west", 80.0, "spire", 38.0),)), R_BIG, "Basilique Notre-Dame-du-Saint-Cordon", [300.0, 90.0, 200.0, 30.0]),
]


def _belfry(cname, lat, lon, H, top="lantern", mat=RED_BRICK, side=12.0):
    """Beffroi (Lille : 104 m, brique et béton armé, 1932) ou tour civile : fût carré, ressauts, couronnement."""
    city = city_of(cname); k = Kit()
    sel = find(city, lat, lon, 140, minh=25.0, mode="h", maxarea=1500)
    if sel:
        b = sel[0][0]; c = np.array(sel[0][1].centroid.coords[0]); _, u, _, _ = obb(b["ring"]); rep = [b["ring"]]
    else:
        c = xy(city, lat, lon); u = np.array([1.0, 0.0]); rep = []
    g = city.ground(*c) - 0.2
    if top == "lantern":   # Lille : fût, tête évasée, lanterne et flèche
        tower(k, tuple(c), side, g, H * 0.72, mat, "none", 0.0, u=tuple(u))
        F = F2(c, u); s = side / 2
        k.lod = (0, 2); k.prism(F.ring(-s * 1.2, s * 1.2, -s * 1.2, s * 1.2), g + H * 0.72, g + H * 0.8, "pierre_taille#d8d0bd")
        k.prism(F.circle(0, 0, s * 0.85, 8), g + H * 0.8, g + H * 0.9, mat)
        spire(k, tuple(c), s * 0.6, g + H * 0.9, H * 0.1, "lm_zinc#6f9a8a", lucarnes=False)
        k.lod = (0, 1)
        for sg in (-1, 1):
            c3 = F.P(0, sg * s * 1.21, g + H * 0.76); k.cyl(c3, c3 + v3(F.v[0], 0, F.v[1]) * sg * 0.15, side * 0.32, WHITE, 16)
        k.lod = (0, 2)
    else:
        tower(k, tuple(c), side, g, H, mat, top, 2.0, u=tuple(u))
    F = F2(c, u); s = side * 0.6
    return finish(k, city, rep, [block(F.ring(-s, s, -s, s), g, H)], tuple(c))


def _gros_horloge():
    """Gros-Horloge de Rouen : arche Renaissance enjambant la rue (cadran doré de 2,5 m sur chaque face) accolée au
    beffroi gothique (hauteur 30 m) à toit d'ardoise et lanterne."""
    city = city_of("rouen"); k = Kit(); c = xy(city, 49.44118, 1.09170)
    u = np.array([math.cos(math.radians(-10)), math.sin(math.radians(-10))])
    k0, a, meta = arch("rouen", 49.44118, 1.09170, 11.0, 6.0, 9.0, yaw_deg=-10, bays=1, mat=STONE, attic=4.0)
    k = k0; F = F2(c, u); g = city.ground(*c) - 0.2
    k.lod = (0, 2); gable_roof(k, F, -5.5, 5.5, -3, 3, g + 13, 3.5, SLATE, STONE)
    for sg in (-1, 1):
        k.lod = (0, 1); c3 = F.P(0, sg * 3.1, g + 10.5); k.cyl(c3, c3 + v3(F.v[0], 0, F.v[1]) * sg * 0.2, 1.25, GOLD, 16)
    tower(k, tuple(F.p(-9.0, 0)), 6.5, g, 30.0, STONE, "pyramid", 8.0, SLATE, u=tuple(u))
    meta["blocks"].append(block(F.ring(-12.5, -5.5, -3.5, 3.5), g, 38.0))
    meta["replace"] = [list(map(list, ccw(t[0]["ring"]))) for t in find(city, 49.44118, 1.09170, 12, n=4)]
    return k, a, meta


def _saint_joseph():
    """Église Saint-Joseph du Havre (Auguste Perret, 1951-1957) : base carrée en béton brut et tour-lanterne
    octogonale de 107 m percée de 12 768 verres colorés."""
    city = city_of("lehavre"); k = Kit()
    sel = find(city, 49.48930, 0.09930, 90, kinds=(1, 2))
    if sel: b = sel[0][0]; c = np.array(sel[0][1].centroid.coords[0]); _, u, L, W = obb(b["ring"]); rep = [b["ring"]]
    else: c = xy(city, 49.48930, 0.09930); u = np.array([1.0, 0.0]); L = W = 20.0; rep = []
    F = F2(c, u); g = city.ground(*c) - 0.2; m = "beton_banche#bdb6a6"; s = min(L, W, 22.0)
    k.lod = (0, 2); k.prism(F.ring(-s, s, -s, s), g, g + 18, m)
    k.prism(F.circle(0, 0, 8.5, 8), g + 18, g + 107, m)
    k.lod = (0, 1)
    for j in range(8):
        ang = 2 * math.pi * (j + 0.5) / 8; q = F.c + np.array([math.cos(ang), math.sin(ang)]) * 8.3
        for y in np.arange(g + 22, g + 100, 6):
            k.box(v3(q[0], y + 2.5, q[1]), (5.5, 4.0, 0.3), VIT, yaw=-ang + math.pi / 2)
    k.lod = (0, 2)
    return finish(k, city, rep, [block(F.ring(-s, s, -s, s), g, 107)], tuple(c))


def _equestrian(cname, lat, lon, scale):
    city = city_of(cname); k = Kit(); c = xy(city, lat, lon); g = city.ground(*c) - 0.1
    d, q, t = nearest_track(city, *c)
    if d < 8.0: c = q + (c - q) / max(d, 0.1) * 8.0   # garde au gabarit
    equestrian(k, c, math.atan2(t[1], t[0]), g, scale)
    F = F2(c, t)
    return finish(k, city, [], [block(F.ring(-3 * scale, 3 * scale, -1.5 * scale, 1.5 * scale), g, 4.4 + 4.5 * scale)], tuple(c))
