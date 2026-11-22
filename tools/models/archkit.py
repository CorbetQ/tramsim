"""Éléments d'architecture et de mobilier procéduraux (façades à ouvertures, toitures, arbres, mobilier)."""
import math
import numpy as np
from shapely.geometry import Polygon
from meshkit import Kit, v3, norm, UP


# ------------------------------------------------------------------ contours d'ouvertures (repère du mur : u, v)
def rect(u0, u1, v0, v1):
    return [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]


def arch_round(u0, u1, v0, v1, seg=8):
    r = (u1 - u0) / 2; c = (u0 + u1) / 2; vs = v1 - r
    pts = [(u0, v0), (u1, v0), (u1, vs)]
    for i in range(1, seg):
        a = math.pi * i / seg; pts.append((c + r * math.cos(a), vs + r * math.sin(a)))
    pts.append((u0, vs)); return pts


def arch_pointed(u0, u1, v0, v1, seg=5):
    """Ogive (arc brisé équilatéral) : centres aux naissances, rayon = largeur, sommet en v1."""
    w = u1 - u0; rise = w * math.sqrt(3) / 2; vs = v1 - rise
    pts = [(u0, v0), (u1, v0), (u1, vs)]
    a0 = math.pi - math.atan2(rise, -0.0 + w) if False else None
    for i in range(1, seg + 1):   # arc droit : centre (u0, vs), de 0 à 60°
        a = math.radians(60) * i / seg; pts.append((u0 + w * math.cos(a), vs + w * math.sin(a)))
    for i in range(1, seg):        # arc gauche : centre (u1, vs), de 120° à 180°
        a = math.radians(120) + math.radians(60) * i / seg; pts.append((u1 + w * math.cos(a), vs + w * math.sin(a)))
    pts.append((u0, vs)); return pts


class Wall:
    """Mur plan entre deux points 2D (x, z) avec normale extérieure ; coordonnées locales (u le long, v = altitude)."""

    def __init__(self, a, b, out):
        self.a = v3(a[0], 0, a[1]); self.b = v3(b[0], 0, b[1])
        self.L = float(np.linalg.norm(self.b - self.a)); self.t = norm(self.b - self.a)
        self.n = norm(v3(out[0], 0, out[1]))

    def P(self, u, v, d=0.0):
        """Point du mur : abscisse u, altitude v, enfoncement d (positif vers l'intérieur)."""
        return self.a + self.t * u + UP * v - self.n * d


def wall_with_openings(k: Kit, w: Wall, v0, v1, holes, mat, depth=0.25, reveal=None, inner=None, glass="lm_vitre", frame=None, sill=None):
    """Mur percé : face extérieure (trous), tableaux (épaisseur `depth`), vitrage en fond. `inner` : matériau du
    fond de baie (sinon vitrage)."""
    outer = [w.P(0, v0), w.P(w.L, v0), w.P(w.L, v1), w.P(0, v1)]
    k.poly(outer, mat, w.n, holes=[[w.P(u, v) for (u, v) in h] for h in holes])
    for h in holes:
        n = len(h)
        for i in range(n):
            (u0, vv0), (u1, vv1) = h[i], h[(i + 1) % n]
            a, b = w.P(u0, vv0), w.P(u1, vv1)
            c = (np.mean([p[0] for p in h]), np.mean([p[1] for p in h]))
            inward = norm(w.t * (c[0] - (u0 + u1) / 2) + UP * (c[1] - (vv0 + vv1) / 2))
            k.quad(a, b, b - w.n * depth, a - w.n * depth, reveal or mat, inward)
        k.poly([w.P(u, v, depth) for (u, v) in h], inner or glass, w.n)
        if frame:
            u0 = min(p[0] for p in h); u1 = max(p[0] for p in h); vb = min(p[1] for p in h); vt = max(p[1] for p in h)
            um = (u0 + u1) / 2; d = depth - 0.04
            k.box(w.P(um, (vb + vt) / 2, d), (0.06, vt - vb, 0.06), frame, basis=(w.t, UP, -w.n))
            if vt - vb > 1.6:
                k.box(w.P(um, vb + (vt - vb) * 0.72, d), (u1 - u0, 0.06, 0.06), frame, basis=(w.t, UP, -w.n))
        if sill:
            u0 = min(p[0] for p in h); u1 = max(p[0] for p in h); vb = min(p[1] for p in h)
            k.box(w.P((u0 + u1) / 2, vb - 0.06, -0.04), (u1 - u0 + 0.2, 0.12, depth * 0.5 + 0.12), sill, basis=(w.t, UP, -w.n))


# ------------------------------------------------------------------ anneaux décalés (onglet borné)
def offset_ring(ring, d, max_miter=2.5):
    """Décale un anneau 2D (sens quelconque) de d vers l'intérieur ; même nombre de sommets."""
    P = Polygon(ring); ccw = P.exterior.is_ccw
    out = []; n = len(ring)
    for i in range(n):
        p0, p1, p2 = np.array(ring[i - 1]), np.array(ring[i]), np.array(ring[(i + 1) % n])
        e0 = norm(p1 - p0); e1 = norm(p2 - p1)
        # normale intérieure (x,z) : pour un anneau CCW (repère x droite, z haut), intérieur à gauche
        n0 = np.array([-e0[1], e0[0]]); n1 = np.array([-e1[1], e1[0]])
        if not ccw: n0, n1 = -n0, -n1
        m = norm(n0 + n1) if np.linalg.norm(n0 + n1) > 1e-6 else n0
        s = 1.0 / max(np.dot(m, n0), 1.0 / max_miter)
        out.append(tuple(p1 + m * d * s))
    return out


def clean_ring(ring, tol=0.35):
    """Retire les sommets quasi colinéaires et les arêtes trop courtes."""
    P = Polygon(ring).simplify(tol, preserve_topology=True)
    if P.geom_type != "Polygon" or P.is_empty: return list(ring)
    c = list(P.exterior.coords)[:-1]
    return c if len(c) >= 3 else list(ring)


def mansard(k: Kit, ring, y, mat_roof="toiture", mat_top="lm_zinc", brisis=(0.9, 2.9), terrasson=(2.6, 0.9)):
    """Toit à la Mansard : brisis raide puis terrasson faible ; retour à un toit plat si le décalage échoue."""
    r1 = offset_ring(ring, brisis[0]); r2 = offset_ring(ring, terrasson[0])
    ok1 = Polygon(r1).is_valid and Polygon(r1).area > 4; ok2 = Polygon(r2).is_valid and Polygon(r2).area > 2
    if not ok1:
        k.poly([(p[0], y, p[1]) for p in ring], mat_top, UP); return y
    y1 = y + brisis[1]; y2 = y1 + (terrasson[1] if ok2 else 0)
    c = np.mean(np.array(ring), axis=0)
    def band(ra, rb, ya, yb, mat):
        for i in range(len(ra)):
            j = (i + 1) % len(ra)
            a, b = ra[i], ra[j]; e = np.array(b) - np.array(a)
            nout = np.array([e[1], -e[0]]); mid = (np.array(a) + np.array(b)) / 2
            if np.dot(nout, mid - c) < 0: nout = -nout
            hint = norm(v3(nout[0], 0.6, nout[1]))
            k.quad((a[0], ya, a[1]), (b[0], ya, b[1]), (rb[j][0], yb, rb[j][1]), (rb[i][0], yb, rb[i][1]), mat, hint)
    band(ring, r1, y, y1, mat_roof)
    if ok2:
        band(r1, r2, y1, y2, mat_roof); k.poly([(p[0], y2, p[1]) for p in r2], mat_top, UP)
    else:
        k.poly([(p[0], y1, p[1]) for p in r1], mat_top, UP)
    return y2


def hip_roof(k: Kit, ring, y, rise, mat="toiture"):
    """Croupe simple pour un quadrilatère : faîtage sur le grand axe."""
    pts = np.array(ring[:4], float)
    e = [np.linalg.norm(pts[(i + 1) % 4] - pts[i]) for i in range(4)]
    i0 = int(np.argmax([e[0] + e[2], e[1] + e[3]]))
    a, b, c, d = [pts[(i0 + j) % 4] for j in range(4)]    # a-b et c-d : longs pans
    short = (np.linalg.norm(d - a) + np.linalg.norm(c - b)) / 2
    m1 = (a + d) / 2; m2 = (b + c) / 2; ax = norm(m2 - m1)
    r1 = m1 + ax * short * 0.5; r2 = m2 - ax * short * 0.5
    R1 = v3(r1[0], y + rise, r1[1]); R2 = v3(r2[0], y + rise, r2[1])
    A, B, C, D = [v3(p[0], y, p[1]) for p in (a, b, c, d)]
    cen = (A + B + C + D) / 4
    for tri_or_quad in ((A, B, R2, R1), (C, D, R1, R2)):
        hint = norm(((tri_or_quad[0] + tri_or_quad[1]) / 2 - cen) * v3(1, 0, 1) + UP)
        k.quad(*tri_or_quad, mat, hint)
    k.tri(B, C, R2, mat, norm(((B + C) / 2 - cen) * v3(1, 0, 1) + UP))
    k.tri(D, A, R1, mat, norm(((D + A) / 2 - cen) * v3(1, 0, 1) + UP))


def gable(k: Kit, a, b, y, depth_dir, depth, rise, mat_roof="toiture", mat_wall="facade_tuffeau", over=0.3):
    """Toit à deux pans : pignons aux extrémités a et b (2D), profondeur le long de depth_dir."""
    a, b = np.array(a, float), np.array(b, float); dd = norm(np.array(depth_dir, float))
    A0 = v3(a[0], y, a[1]); B0 = v3(b[0], y, b[1]); off = v3(dd[0], 0, dd[1]) * depth
    mid = (A0 + B0) / 2 + off / 2 + UP * rise
    # faîtage parallèle à depth_dir passant au milieu de ab
    R0 = (A0 + B0) / 2 + UP * rise - v3(dd[0], 0, dd[1]) * over; R1 = R0 + off + v3(dd[0], 0, dd[1]) * over * 2
    ov = v3(dd[0], 0, dd[1]) * over
    k.quad(A0 - ov, A0 + off + ov, R1, R0, mat_roof, norm((A0 - (A0 + B0) / 2) + UP))
    k.quad(B0 + off + ov, B0 - ov, R0, R1, mat_roof, norm((B0 - (A0 + B0) / 2) + UP))
    k.tri(A0, B0, (A0 + B0) / 2 + UP * rise, mat_wall, -v3(dd[0], 0, dd[1]))
    k.tri(A0 + off, B0 + off, (A0 + B0) / 2 + off + UP * rise, mat_wall, v3(dd[0], 0, dd[1]))


# ------------------------------------------------------------------ végétation
def tree(k: Kit, base, h, crown_r, rng, lod_cards=(0, 0), species="platane"):
    """Arbre : tronc et charpentières lissés, houppier en cartes feuillues (alpha) orientées aléatoirement.
    LOD0 : ~140 cartes ; LOD1 : ~40 ; LOD2 : 6 grandes cartes croisées."""
    base = v3(base); trunk_h = h * 0.38; r0 = max(0.14, h * 0.018)
    lod = k.lod
    k.lod = (0, 1); k.cyl(base - UP * 0.3, base + UP * trunk_h, r0, "lm_ecorce", 10, caps=False, r2=r0 * 0.75)
    top = base + UP * trunk_h
    crown_c = base + UP * (trunk_h + (h - trunk_h) * 0.5)
    branches = []
    for i in range(5):
        a = rng.uniform(0, 2 * math.pi); el = rng.uniform(0.5, 0.95)
        d = norm(v3(math.cos(a) * math.cos(el), math.sin(el) + 0.25, math.sin(a) * math.cos(el)))
        end = top + d * (h - trunk_h) * rng.uniform(0.45, 0.7)
        k.cyl(top, end, r0 * 0.55, "lm_ecorce", 7, caps=False, r2=r0 * 0.18); branches.append(end)
    k.lod = (2, 2); k.cyl(base - UP * 0.3, base + UP * trunk_h * 1.4, r0, "lm_ecorce", 5, caps=False, r2=r0 * 0.5)
    ry = (h - trunk_h) * 0.55
    for lvl, count, size in ((0, 150, 1.9), (1, 46, 3.0), (2, 7, crown_r * 1.5)):
        k.lod = (lvl, lvl)
        for i in range(count):
            if lvl == 2:
                p = crown_c + v3(rng.uniform(-.2, .2), rng.uniform(-.3, .3), rng.uniform(-.2, .2)) * crown_r
                yaw = math.pi * i / count; tilt = 0.0
            else:
                while True:
                    q = v3(rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))
                    if np.dot(q, q) <= 1: break
                q = q * (0.55 + 0.45 * rng.uniform(0, 1) ** 0.5)
                p = crown_c + v3(q[0] * crown_r, q[1] * ry, q[2] * crown_r)
                yaw = rng.uniform(0, math.pi); tilt = rng.uniform(-0.6, 0.6)
            s = size * rng.uniform(0.8, 1.2)
            X = v3(math.cos(yaw), 0, math.sin(yaw)); Y = norm(UP * math.cos(tilt) + np.cross(X, UP) * math.sin(tilt))
            hx, hy = X * s / 2, Y * s / 2
            atlas = rng.integers(0, 4)  # 4 vignettes 2×2 dans la texture de feuillage
            u0, v0 = (atlas % 2) * 0.5, (atlas // 2) * 0.5
            uvs = ((u0, v0 + 0.5), (u0 + 0.5, v0 + 0.5), (u0 + 0.5, v0), (u0, v0))
            nrm = norm(p - crown_c + UP * 0.3)
            pts = (p - hx - hy, p + hx - hy, p + hx + hy, p - hx + hy)
            k.tri(pts[0], pts[1], pts[2], "lm_feuillage", None, (uvs[0], uvs[1], uvs[2]), (nrm, nrm, nrm))
            k.tri(pts[0], pts[2], pts[3], "lm_feuillage", None, (uvs[0], uvs[2], uvs[3]), (nrm, nrm, nrm))
    k.lod = lod


# ------------------------------------------------------------------ mobilier (repère : position, tangente t 2D)
def frame_of(t):
    t = norm(v3(t[0], 0, t[1])); n = np.cross(UP, t)
    return t, n


def bench(k: Kit, p, t):
    X, Z = frame_of(t); p = v3(p)
    B = (X, UP, Z)
    for s in (-0.75, 0.75):
        k.box(p + X * s + UP * 0.22, (0.08, 0.44, 0.5), "mobilier_metal", basis=B)
        k.box(p + X * s + UP * 0.62 - Z * 0.22, (0.07, 0.5, 0.07), "mobilier_metal", basis=B)
    for i in range(4):
        k.box(p + UP * 0.45 + Z * (-0.18 + i * 0.12), (1.8, 0.04, 0.1), "lm_bois", basis=B)
    for i in range(2):
        k.box(p + UP * (0.65 + i * 0.16) - Z * 0.25, (1.8, 0.11, 0.035), "lm_bois", basis=B)
    k.collider(p + UP * 0.4, (1.8, 0.8, 0.6), math.atan2(X[2], X[0]))


def ticket_machine(k: Kit, p, t):
    X, Z = frame_of(t); p = v3(p); B = (X, UP, Z)
    k.box(p + UP * 0.85, (0.62, 1.7, 0.42), "lm_inox", basis=B)
    k.box(p + UP * 1.73, (0.7, 0.06, 0.5), "mobilier_metal", basis=B)
    k.box(p + UP * 1.32 + Z * 0.212, (0.36, 0.28, 0.01), "lm_ecran", basis=B)
    k.box(p + UP * 1.0 + Z * 0.23, (0.46, 0.18, 0.05), "mobilier_metal", basis=B)
    k.box(p + UP * 0.55 + Z * 0.215, (0.3, 0.12, 0.02), "lm_menuiserie", basis=B)
    k.collider(p + UP * 0.85, (0.62, 1.7, 0.42), math.atan2(X[2], X[0]))


def info_pole(k: Kit, p, t, line_color_mat="lm_ligne"):
    X, Z = frame_of(t); p = v3(p); B = (X, UP, Z)
    k.cyl(p, p + UP * 2.9, 0.045, "mobilier_metal", 8)
    k.box(p + UP * 2.35 + X * 0.0, (0.9, 0.9, 0.06), "lm_panneau", basis=B)
    k.box(p + UP * 2.85, (0.9, 0.12, 0.07), line_color_mat, basis=B)
    k.box(p + UP * 1.45, (0.5, 0.7, 0.05), "lm_ecran", basis=B)


def bollard(k: Kit, p):
    p = v3(p)
    k.cyl(p, p + UP * 0.85, 0.065, "mobilier_metal", 8, caps=False)
    k.cyl(p + UP * 0.85, p + UP * 0.92, 0.07, "mobilier_metal", 8, r2=0.02)
    k.box(p + UP * 0.72, (0.14, 0.04, 0.14), "lm_peinture_blanche")


def lamp(k: Kit, p, t, h=7.5, arm=1.2):
    X, Z = frame_of(t); p = v3(p); B = (X, UP, Z)
    k.cyl(p, p + UP * h, 0.09, "mobilier_metal", 10, caps=False, r2=0.055)
    k.cyl(p, p + UP * 0.6, 0.14, "mobilier_metal", 10, caps=False, r2=0.11)
    head = p + UP * h + Z * arm
    k.seg_box(p + UP * (h - 0.1), head + UP * 0.05, 0.08, 0.06, "mobilier_metal")
    k.box(head, (0.32, 0.1, 0.7), "mobilier_metal", basis=B)
    k.box(head - UP * 0.055, (0.26, 0.01, 0.6), "eclairage", basis=B)
    k.collider(p + UP * h / 2, (0.25, h, 0.25))


def bin_(k: Kit, p):
    p = v3(p)
    k.cyl(p, p + UP * 0.9, 0.24, "mobilier_metal", 12, caps=True)
    k.cyl(p + UP * 0.9, p + UP * 0.95, 0.26, "lm_inox", 12)
