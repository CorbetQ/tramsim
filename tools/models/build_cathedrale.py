"""Cathédrale Saint-Maurice d'Angers : façade occidentale (portail à voussures, grande baie, galerie des chevaliers,
tour-lanterne Renaissance), deux tours à flèches de pierre (75 m), nef unique à voûtes angevines (16,4 m, 3 travées),
transept à roses, chœur et abside. Dimensions : Wikipédia (longueur 90,47 m, façade 23 m, nef 16,4 × 48 m, voûte 24,7 m,
tours 75 m) ; implantation : emprise BD TOPO (IGN) du jeu (rectangle 92 × 53 m) et BD ORTHO."""
import math
import numpy as np
from shapely.geometry import Polygon, Point
import geo
from meshkit import Kit, v3, norm, UP, translate
from archkit import Wall, wall_with_openings, rect, arch_pointed, arch_round

# emprise BD TOPO de la cathédrale (bâtiment principal, repère de la ville) : C-D = façade ouest, A-B = chevet
ENV = [(-12.1, -2954.7), (-44.5, -2912.2), (-117.7, -2967.9), (-85.3, -3010.4)]
STONE = "facade_tuffeau"; TOWER = "facade_tuffeau#c2baa8"; ROOF = "toiture"; GLASS = "lm_vitrail"


class F:
    def __init__(self, o, u):
        self.o = np.array(o, float); self.u = norm(np.array(u, float)); self.v = np.array([-self.u[1], self.u[0]])

    def p2(self, u, v):
        return self.o + self.u * u + self.v * v

    def P(self, u, v, y):
        q = self.p2(u, v); return v3(q[0], y, q[1])

    def wall(self, u0, v0, u1, v1, out):
        """Mur de (u0,v0) à (u1,v1) ; out : normale extérieure en (du, dv)."""
        n = self.u * out[0] + self.v * out[1]
        return Wall(self.p2(u0, v0), self.p2(u1, v1), n)

    def basis(self):
        return (v3(self.u[0], 0, self.u[1]), UP, v3(self.v[0], 0, self.v[1]))


def obox(k, f, u, v, y, su, sy, sv, mat):
    k.box(f.P(u, v, y), (su, sy, sv), mat, basis=f.basis())


def spire(k, f, u, v, y0, r, h, n=8, crockets=True):
    """Flèche octogonale de pierre : arêtiers, crochets, lucarnes à gâble à la base, épi."""
    top = f.P(u, v, y0 + h)
    ring = [f.P(u + r * math.cos(2 * math.pi * (i + .5) / n), v + r * math.sin(2 * math.pi * (i + .5) / n), y0) for i in range(n)]
    c = f.P(u, v, y0)
    k.lod = (0, 2)
    for i in range(n):
        a, b = ring[i], ring[(i + 1) % n]
        k.tri(a, b, top, TOWER, norm(((a + b) / 2 - c) + UP * 0.2))
    k.lod = (0, 1)
    for i in range(n):   # arêtiers saillants
        k.seg_box(ring[i] + (ring[i] - c) * 0.03, top, 0.22, 0.22, TOWER)
    if crockets:
        k.lod = (0, 0)
        for i in range(n):
            for t in np.arange(0.08, 0.92, 0.075):
                p = ring[i] * (1 - t) + top * t; out = norm((ring[i] - c) * v3(1, 0, 1))
                k.box(p + out * 0.18, (0.28, 0.22, 0.28), TOWER, yaw=math.atan2(out[2], out[0]))
        # bandeaux horizontaux (écailles suggérées)
        for t in np.arange(0.1, 0.9, 0.1):
            rr = [ring[i] * (1 - t) + top * t for i in range(n)]
            for i in range(n):
                a, b = rr[i], rr[(i + 1) % n]; o = norm(((a + b) / 2 - top * 1.0) * v3(1, 0, 1)) * 0.04
                k.quad(a + o, b + o, b + o + UP * 0.12, a + o + UP * 0.12, TOWER, norm(o + UP * 0.01))
    # lucarnes à gâble sur 4 faces
    k.lod = (0, 1)
    for i in range(0, n, 2):
        a = 2 * math.pi * (i + 1) / n
        du, dv = math.cos(a), math.sin(a)
        p = f.P(u + du * (r - 0.3), v + dv * (r - 0.3), y0 + 2.2)
        yaw = math.atan2((f.v[1] * dv + f.u[1] * du), (f.u[0] * du + f.v[0] * dv))
        k.box(p, (1.6, 4.4, 1.4), TOWER, yaw=yaw)
        out = v3(f.u[0] * du + f.v[0] * dv, 0, f.u[1] * du + f.v[1] * dv); side = np.cross(UP, out)
        A = p + UP * 2.2 - side * 0.8 + out * 0.71; B = p + UP * 2.2 + side * 0.8 + out * 0.71; C = p + UP * 4.0 + out * 0.71
        k.tri(A, B, C, TOWER, out)
        k.quad(A, C, C - out * 1.5, A - out * 1.5, TOWER, norm(-side + UP)); k.quad(C, B, B - out * 1.5, C - out * 1.5, TOWER, norm(side + UP))
        k.lod = (0, 0)
        k.quad(p - side * 0.4 + out * 0.72 - UP * 1.2, p + side * 0.4 + out * 0.72 - UP * 1.2, p + side * 0.4 + out * 0.72 + UP * 1.4, p - side * 0.4 + out * 0.72 + UP * 1.4, "lm_menuiserie_sombre", out)
        k.lod = (0, 1)
    k.lod = (0, 1)
    k.cyl(top - UP * 0.5, top + UP * 1.2, 0.18, TOWER, 8)
    k.lathe(top + UP * 1.2, [(0.0, 0), (0.35, 0.25), (0.0, 0.55)], "lm_zinc", 8)
    k.box(top + UP * 2.3, (0.12, 1.8, 0.12), "lm_ferronnerie"); k.box(top + UP * 2.6, (0.9, 0.12, 0.12), "lm_ferronnerie", yaw=math.atan2(f.u[1], f.u[0]))


def pinnacle(k, f, u, v, y0, h=6.0, r=0.6):
    k.lod = (0, 1)
    k.cyl(f.P(u, v, y0), f.P(u, v, y0 + h * 0.35), r, TOWER, 8)
    k.lathe(f.P(u, v, y0 + h * 0.35), [(r * 1.1, 0), (r * 1.1, 0.2), (0.0, h * 0.65)], TOWER, 8, smooth=False)


def buttress(k, f, u, v, y0, y1, out, depth=2.6, width=2.0, steps=3):
    """Contrefort à ressauts (glacis) ; out = (du, dv) unitaire vers l'extérieur."""
    du, dv = out
    for s in range(steps):
        ya = y0 + (y1 - y0) * s / steps; yb = y0 + (y1 - y0) * (s + 1) / steps
        d = depth * (1 - 0.28 * s)
        uc = u + du * d / 2; vc = v + dv * d / 2
        su = d if du else width; sv = width if du else d
        k.lod = (0, 1); obox(k, f, uc, vc, (ya + yb) / 2, su, yb - ya, sv, STONE)
        # glacis
        a = f.P(u + du * d - (dv * width / 2 if du == 0 else 0), v + dv * d - (du * width / 2 if dv == 0 else 0), yb)
        k.lod = (0, 0)
        p0 = f.P(u + du * d, v + dv * d, yb); p1 = f.P(u + du * d * 0.72, v + dv * d * 0.72, yb + 0.9)
        side = f.P(u + (dv != 0) * width / 2, v + (du != 0) * width / 2, 0) - f.P(u, v, 0)
        k.quad(p0 - side, p0 + side, p1 + side, p1 - side, STONE, norm(v3(*(p0 - f.P(u, v, yb))) * v3(1, 0, 1) + UP))


def openings_wall(k, f, u0, v0, u1, v1, out, y0, y1, holes, depth=0.9, lod_flat=True):
    w = f.wall(u0, v0, u1, v1, out)
    k.lod = (0, 0); wall_with_openings(k, w, y0, y1, holes, STONE, depth, inner=GLASS)
    for h in holes:   # remplages : meneau central et oculus
        us = [p[0] for p in h]; vs = [p[1] for p in h]
        um = (min(us) + max(us)) / 2; wd = max(us) - min(us)
        if wd > 1.6:
            k.box(w.P(um, (min(vs) + max(vs)) / 2 - 0.4, depth - 0.15), (0.16, max(vs) - min(vs) - 1.0, 0.25), STONE, basis=(w.t, UP, -w.n))
    if lod_flat:
        k.lod = (1, 1); k.quad(w.P(0, y0), w.P(w.L, y0), w.P(w.L, y1), w.P(0, y1), STONE, w.n)
        for h in holes:
            k.poly([w.P(a, b, -0.02) for a, b in h], GLASS, w.n)
    return w


def gable_roof(k, f, u0, u1, hw, y, ridge, along="u", over=0.4, gable_walls=True):
    """Toit à deux pans d'ardoise ; along = 'u' (faîtage parallèle à l'axe) ou 'v'."""
    if along == "u":
        A = f.P(u0 - over, -hw - over * 0.6, y - 0.3); B = f.P(u1 + over, -hw - over * 0.6, y - 0.3)
        C = f.P(u1 + over, 0, ridge); D = f.P(u0 - over, 0, ridge)
        A2 = f.P(u0 - over, hw + over * 0.6, y - 0.3); B2 = f.P(u1 + over, hw + over * 0.6, y - 0.3)
        k.quad(A, B, C, D, ROOF, norm(v3(*(A - D)) * v3(1, 0, 1) + UP)); k.quad(B2, A2, D, C, ROOF, norm(v3(*(A2 - D)) * v3(1, 0, 1) + UP))
        k.seg_box(D + UP * 0.1, C + UP * 0.1, 0.3, 0.25, "lm_ardoise_faitage")
        if gable_walls:
            for uu, s in ((u0, -1), (u1, 1)):
                k.tri(f.P(uu, -hw, y), f.P(uu, hw, y), f.P(uu, 0, ridge), STONE, v3(*(f.P(s, 0, 0) - f.P(0, 0, 0))))
    else:
        # u0,u1 = bornes en v (bras), hw = demi-largeur en u autour de u_c (passé dans y? non : voir appelant)
        raise ValueError


def build():
    city = geo.City("angers"); G = city.ground
    C, D = np.array(ENV[2]), np.array(ENV[3]); A, B = np.array(ENV[0]), np.array(ENV[1])
    fo = (C + D) / 2; axis = (A + B) / 2 - fo
    f = F(fo, axis)
    if np.dot(f.v, D - C) < 0: pass
    Y0 = G(*f.p2(1.0, 0.0)) + 0.25
    gmin = min(G(*f.p2(u, v)) for u in np.arange(0, 92, 6) for v in (-24, -10, 0, 10, 24))
    yb = gmin - 1.5
    k = Kit()
    # ------------------------------------------------------------ soubassement et parvis
    k.lod = (0, 2)
    foot = [(0, -11.5), (10.5, -11.5), (10.5, -10.2), (58, -10.2), (58, -24.5), (74, -24.5), (74, -9.2), (82.5, -9.2),
            (82.5, 9.2), (74, 9.2), (74, 24.5), (58, 24.5), (58, 10.2), (10.5, 10.2), (10.5, 11.5), (0, 11.5)]
    ring = [tuple(f.p2(u, v)) for u, v in foot]
    k.prism(ring, yb, Y0 + 0.6, "pierre_taille", top=False)
    k.lod = (0, 1)
    for s in range(3):   # marches du parvis
        obox(k, f, -1.2 - s * 0.45, 0, Y0 - 0.17 * s - 0.1, 0.45 + s * 0.9, 0.18, 14 + s, "pierre_taille")
    # ------------------------------------------------------------ nef (3 travées carrées angevines)
    EA = Y0 + 21.5; RI = Y0 + 33.5
    bays = [(10.5, 26.3), (26.3, 42.2), (42.2, 58.0)]
    for side in (-1, 1):
        for (ua, ub) in bays:
            um = (ua + ub) / 2
            holes = [arch_pointed(um - ua - 3.6, um - ua - 1.0, Y0 + 9.0, Y0 + 19.0, 4), arch_pointed(um - ua + 1.0, um - ua + 3.6, Y0 + 9.0, Y0 + 19.0, 4)]
            holes = [[(p[0], p[1]) for p in h] for h in holes]
            if side < 0:
                openings_wall(k, f, ua, side * 10.2, ub, side * 10.2, (0, side), Y0, EA, holes)
            else:
                L = ub - ua
                hh = [[(L - p[0], p[1]) for p in h][::-1] for h in holes]
                openings_wall(k, f, ub, side * 10.2, ua, side * 10.2, (0, side), Y0, EA, hh)
            k.lod = (2, 2); obox(k, f, um, side * 10.2 - side * 0.5, (Y0 + EA) / 2, ub - ua, EA - Y0, 1.0, STONE)
            # oculus entre les lancettes
            k.lod = (0, 0)
            c = f.P(um, side * 10.25, Y0 + 19.6)
            k.cyl(c, c + v3(f.v[0], 0, f.v[1]) * side * 0.35, 1.0, STONE, 16, caps=False)
            k.cyl(c + v3(f.v[0], 0, f.v[1]) * side * 0.05, c + v3(f.v[0], 0, f.v[1]) * side * 0.06, 0.95, GLASS, 16)
        for u in (10.5, 26.3, 42.2, 58.0):
            buttress(k, f, u, side * 10.2, Y0, EA - 1.0, (0, side), depth=3.0, width=2.4)
        # corniche à modillons
        k.lod = (0, 1); obox(k, f, 34.25, side * 10.4, EA - 0.2, 47.5, 0.4, 0.8, STONE)
        k.lod = (0, 0)
        for u in np.arange(11, 58, 0.9):
            obox(k, f, u, side * 10.45, EA - 0.6, 0.25, 0.35, 0.5, STONE)
    gable_roof(k, f, 10.5, 74.0, 10.4, EA, RI, gable_walls=False)
    k.lod = (2, 2); obox(k, f, 34.25, 0, (Y0 + EA) / 2, 47.5, EA - Y0, 20.4, STONE)
    # ------------------------------------------------------------ transept et roses
    for side in (-1, 1):
        va, vb = side * 10.2, side * 24.5
        for uu, out in ((58.0, -1), (74.0, 1)):
            holes = [arch_pointed(abs(vb - va) / 2 - 1.3, abs(vb - va) / 2 + 1.3, Y0 + 8.0, Y0 + 18.5, 4)]
            if (side > 0) == (out < 0):
                openings_wall(k, f, uu, va, uu, vb, (out, 0), Y0, EA, holes)
            else:
                openings_wall(k, f, uu, vb, uu, va, (out, 0), Y0, EA, holes)
        # pignon à rose
        w = openings_wall(k, f, 58.0 if side > 0 else 74.0, vb, 74.0 if side > 0 else 58.0, vb, (0, side), Y0, EA,
                          [arch_pointed(2.0, 4.6, Y0 + 3.0, Y0 + 10.5, 3), arch_pointed(11.4, 14.0, Y0 + 3.0, Y0 + 10.5, 3)])
        k.lod = (0, 2)
        k.tri(f.P(58.0, vb, EA), f.P(74.0, vb, EA), f.P(66.0, vb, RI - 0.5), STONE, v3(f.v[0] * side, 0, f.v[1] * side))
        cen = f.P(66.0, vb + side * 0.02, Y0 + 15.5); nv = v3(f.v[0], 0, f.v[1]) * side
        k.lod = (0, 1)
        k.cyl(cen, cen + nv * 0.5, 4.2, STONE, 28, caps=False)
        k.cyl(cen + nv * 0.05, cen + nv * 0.06, 4.0, GLASS, 28)
        k.lod = (0, 0)
        for i in range(12):   # remplage rayonnant
            a = 2 * math.pi * i / 12; d = v3(*(f.P(66.0 + math.cos(a), vb, 0) - f.P(66.0, vb, 0))) + UP * math.sin(a)
            k.seg_box(cen + nv * 0.12 + d * 0.6, cen + nv * 0.12 + d * 3.9, 0.14, 0.14, STONE, up=nv)
        k.cyl(cen + nv * 0.1, cen + nv * 0.25, 0.7, STONE, 12)
        k.lod = (0, 1)
        for uu in (58.0, 74.0):
            buttress(k, f, uu, vb, Y0, EA - 1.0, (0, side), depth=2.6, width=2.2)
        pinnacle(k, f, 58.0, vb, EA, 5.0, 0.5); pinnacle(k, f, 74.0, vb, EA, 5.0, 0.5)
        # toit du bras (faîtage selon v)
        k.lod = (0, 2)
        a0 = f.P(58.0 - 0.4, 0, EA - 0.3); a1 = f.P(58.0 - 0.4, vb + side * 0.4, EA - 0.3)
        r0 = f.P(66.0, 0, RI); r1 = f.P(66.0, vb + side * 0.4, RI)
        b0 = f.P(74.0 + 0.4, 0, EA - 0.3); b1 = f.P(74.0 + 0.4, vb + side * 0.4, EA - 0.3)
        k.quad(a0, a1, r1, r0, ROOF, norm(v3(*(a0 - r0)) * v3(1, 0, 1) + UP)); k.quad(b1, b0, r0, r1, ROOF, norm(v3(*(b0 - r0)) * v3(1, 0, 1) + UP))
        k.lod = (2, 2); obox(k, f, 66.0, side * 17.35, (Y0 + EA) / 2, 16.0, EA - Y0, 14.3, STONE)
    # ------------------------------------------------------------ chœur et abside
    EC = Y0 + 20.5; RC = Y0 + 31.0
    for side in (-1, 1):
        holes = [arch_pointed(2.6, 5.2, Y0 + 7.5, Y0 + 17.5, 4)]
        if side < 0: openings_wall(k, f, 74.0, -9.2, 82.5, -9.2, (0, -1), Y0, EC, holes)
        else: openings_wall(k, f, 82.5, 9.2, 74.0, 9.2, (0, 1), Y0, EC, [[(8.5 - p[0], p[1]) for p in holes[0]][::-1]])
    gable_roof(k, f, 74.0, 82.5, 9.4, EC, RC, gable_walls=False)
    n = 7; R = 9.2; uc = 82.5
    pts = [(uc + R * math.sin(math.pi * i / (n - 1) - math.pi / 2 + math.pi / 2) * 0 + R * math.cos(math.pi * i / (n - 1) - math.pi / 2), R * math.sin(math.pi * i / (n - 1) - math.pi / 2)) for i in range(n)]
    for i in range(n - 1):
        (ua, va), (ub, vb) = pts[i], pts[i + 1]
        L = math.hypot(ub - ua, vb - va); mu, mv = (ua + ub) / 2 - uc, (va + vb) / 2
        out = (mu / math.hypot(mu, mv), mv / math.hypot(mu, mv))
        openings_wall(k, f, ua, va, ub, vb, out, Y0, EC, [arch_pointed(L / 2 - 1.1, L / 2 + 1.1, Y0 + 7.0, Y0 + 17.0, 4)], depth=0.8)
        k.lod = (0, 2)
        k.tri(f.P(ua + out[0] * 0.3, va + out[1] * 0.3, EC - 0.3), f.P(ub + out[0] * 0.3, vb + out[1] * 0.3, EC - 0.3), f.P(uc, 0, RC), ROOF, v3(*(f.P(out[0], out[1], 0) - f.P(0, 0, 0))) + UP)
        if 0 < i:
            buttress(k, f, ua, va, Y0, EC - 1.0, (pts[i][0] - uc) / R and ((pts[i][0] - uc) / R, pts[i][1] / R) or (0, 1), depth=2.4, width=1.8) if False else None
            o2 = ((ua - uc) / R, va / R)
            k.lod = (0, 1)
            for s in range(3):
                d = 2.4 * (1 - 0.28 * s); ya = Y0 + (EC - 1 - Y0) * s / 3; ybb = Y0 + (EC - 1 - Y0) * (s + 1) / 3
                p = f.P(ua + o2[0] * d / 2, va + o2[1] * d / 2, (ya + ybb) / 2)
                k.box(p, (d, ybb - ya, 1.8), STONE, yaw=math.atan2(f.u[1] * o2[0] + f.v[1] * o2[1], f.u[0] * o2[0] + f.v[0] * o2[1]))
    k.lod = (2, 2); obox(k, f, 81.5, 0, (Y0 + EC) / 2, 18, EC - Y0, 18, STONE)
    # ------------------------------------------------------------ massif occidental : tours, portail, galerie, lanterne
    TT = Y0 + 44.0
    for side in (-1, 1):
        vc = side * 7.8
        k.lod = (2, 2); obox(k, f, 4.6, vc, (Y0 + TT) / 2, 9.2, TT - Y0, 7.4, STONE)
        # fûts : 4 étages, baies géminées en haut (beffroi)
        for (ya, yb_, kind) in ((Y0, Y0 + 13.0, "blind"), (Y0 + 13.0, Y0 + 24.0, "lancet"), (Y0 + 24.0, Y0 + 34.0, "blind"), (Y0 + 34.0, TT, "belfry")):
            for (fu, fv, out, L) in ((0.0, vc, (-1, 0), 7.4), (4.6, vc + side * 3.7, (0, side), 9.2)):
                if fu == 0.0:
                    a = (0.0, vc - 3.7); b = (0.0, vc + 3.7)
                    if side > 0: a, b = b, a
                    a, b = (0.0, vc + 3.7 * (1 if side < 0 else -1) * -1), (0.0, vc + 3.7 * (1 if side < 0 else -1))
                    a, b = (0.0, vc - 3.7), (0.0, vc + 3.7)
                    a, b = b, a   # sens : normale -u
                else:
                    a, b = (0.0, vc + side * 3.7), (9.2, vc + side * 3.7)
                    if side < 0: a, b = b, a
                Lw = math.hypot(b[0] - a[0], b[1] - a[1])
                if kind == "belfry":
                    hl = [arch_pointed(Lw / 2 - 2.6, Lw / 2 - 0.4, ya + 1.0, yb_ - 1.2, 4), arch_pointed(Lw / 2 + 0.4, Lw / 2 + 2.6, ya + 1.0, yb_ - 1.2, 4)]
                elif kind == "lancet":
                    hl = [arch_pointed(Lw / 2 - 0.8, Lw / 2 + 0.8, ya + 3.0, yb_ - 1.5, 4)]
                else:
                    hl = []
                wv = f.wall(a[0], a[1], b[0], b[1], out)
                k.lod = (0, 0)
                if hl:
                    wall_with_openings(k, wv, ya, yb_, hl, STONE, 0.7, inner="lm_menuiserie_sombre" if kind == "belfry" else GLASS)
                    if kind == "belfry":   # abat-sons
                        for h in hl:
                            us = [p[0] for p in h]; vs = [p[1] for p in h]
                            for yy in np.arange(min(vs) + 0.5, max(vs) - 1.0, 0.55):
                                k.box(wv.P((min(us) + max(us)) / 2, yy, 0.4), ((max(us) - min(us)) * 0.95, 0.06, 0.4), "lm_ardoise_faitage", basis=(wv.t, norm(UP + wv.n * 0.6), -wv.n))
                else:
                    k.quad(wv.P(0, ya), wv.P(wv.L, ya), wv.P(wv.L, yb_), wv.P(0, yb_), STONE, wv.n)
                    for j in range(3):   # arcatures aveugles
                        uu = wv.L * (j + 0.5) / 3
                        k.poly([wv.P(x, y, -0.12) for x, y in arch_pointed(uu - 0.8, uu + 0.8, ya + 2.0, yb_ - 1.0, 3)], STONE, wv.n)
                k.lod = (1, 1)
                k.quad(wv.P(0, ya), wv.P(wv.L, ya), wv.P(wv.L, yb_), wv.P(0, yb_), STONE, wv.n)
                for h in hl: k.poly([wv.P(x, y, -0.02) for x, y in h], "lm_menuiserie_sombre", wv.n)
            k.lod = (0, 1); obox(k, f, 4.6, vc, yb_ - 0.15, 9.7, 0.35, 7.9, STONE)   # cordon
        # face côté nef (cachée) et dessus
        k.lod = (0, 1)
        for (ua, va_, ub, vb_, out) in ((9.2, vc + side * 3.7, 9.2, vc - side * 3.7, (1, 0)),):
            wv = f.wall(ua, va_, ub, vb_, out); k.quad(wv.P(0, Y0), wv.P(wv.L, Y0), wv.P(wv.L, TT), wv.P(0, TT), STONE, wv.n)
        # contreforts d'angle de la tour
        for (bu, bv, out) in ((0.0, vc + side * 3.7, (-1, 0)), (0.0, vc - side * 3.7, (-1, 0)), (9.2, vc + side * 3.7, (0, side))):
            buttress(k, f, bu, bv, Y0, Y0 + 30.0, out, depth=1.6, width=1.5, steps=4)
        # balustrade et pinacles d'angle, flèche
        k.lod = (0, 1); obox(k, f, 4.6, vc, TT + 0.6, 9.4, 1.2, 7.6, STONE)
        for du in (0.7, 8.5):
            for dv in (-3.0, 3.0):
                pinnacle(k, f, du, vc + dv, TT + 1.2, 7.5, 0.55)
        spire(k, f, 4.6, vc, TT + 1.0, 3.55, 75.0 + Y0 - TT - 1.0 - 3.0)
    # partie centrale (v ±4.1) : portail, grande baie, galerie des chevaliers, tour-lanterne
    k.lod = (2, 2); obox(k, f, 5.0, 0, (Y0 + Y0 + 31) / 2, 10, 31, 8.2, STONE)
    wv = f.wall(0.0, 4.1, 0.0, -4.1, (-1, 0))
    portal = arch_pointed(1.7, 6.5, Y0, Y0 + 8.3, 6)
    window = arch_pointed(1.6, 6.6, Y0 + 12.0, Y0 + 24.0, 6)
    k.lod = (0, 0)
    wall_with_openings(k, wv, Y0, Y0 + 26.0, [portal, window], STONE, 1.6, inner="lm_menuiserie_sombre")
    # voussures (arcs concentriques en retrait) et tympan
    for j in range(5):
        d = 0.3 + j * 0.25; s = 0.95 - j * 0.07
        arcp = arch_pointed(4.1 - 2.4 * s, 4.1 + 2.4 * s, Y0 + 5.2 - j * 0.2, Y0 + 8.3 - j * 0.45, 8)
        for i in range(2, len(arcp) - 1):
            a, b = arcp[i], arcp[i + 1]
            k.seg_box(wv.P(a[0], a[1], d), wv.P(b[0], b[1], d), 0.22, 0.22, STONE)
    k.poly([wv.P(x, y, 1.55) for x, y in arch_pointed(2.6, 5.6, Y0 + 5.1, Y0 + 7.0, 6)], "pierre_taille", wv.n)
    for j in range(4):   # statues-colonnes
        for s in (-1, 1):
            u = 4.1 + s * (1.4 + j * 0.25)
            p = wv.P(u, Y0 + 1.2, 0.35 + j * 0.28)
            k.lod = (0, 0)
            k.cyl(p - UP * 1.2, p, 0.16, STONE, 8, caps=False)
            k.lathe(p, [(0.22, 0), (0.2, 1.6), (0.25, 2.3), (0.14, 2.6), (0.15, 2.95), (0.0, 3.05)], STONE, 8)
    for j in range(5):   # meneaux de la grande baie
        u = 2.4 + j * 0.85
        k.box(wv.P(u, Y0 + 17.0, 1.45), (0.18, 9.8, 0.25), STONE, basis=(wv.t, UP, -wv.n))
    k.box(wv.P(4.1, Y0 + 21.4, 1.45), (4.8, 0.18, 0.25), STONE, basis=(wv.t, UP, -wv.n))
    # gâble du portail
    k.lod = (0, 1)
    gA = wv.P(0.8, Y0 + 9.2, -0.6); gB = wv.P(7.4, Y0 + 9.2, -0.6); gC = wv.P(4.1, Y0 + 12.4, -0.6)
    k.tri(gA, gB, gC, STONE, wv.n); k.quad(gA, gC, gC + wv.n * 0.8, gA + wv.n * 0.8, STONE, norm(-wv.t + UP)) if False else None
    k.box(wv.P(4.1, Y0 + 9.0, -0.3), (7.0, 0.5, 0.8), STONE, basis=(wv.t, UP, -wv.n))
    k.lod = (1, 1)
    k.quad(wv.P(0, Y0), wv.P(wv.L, Y0), wv.P(wv.L, Y0 + 26), wv.P(0, Y0 + 26), STONE, wv.n)
    k.poly([wv.P(x, y, -0.02) for x, y in portal], "lm_menuiserie_sombre", wv.n); k.poly([wv.P(x, y, -0.02) for x, y in window], GLASS, wv.n)
    # galerie des chevaliers (8 niches et statues) Y0+26..31
    k.lod = (0, 1)
    k.box(wv.P(4.1, Y0 + 26.2, -0.4), (9.2, 0.4, 1.0), STONE, basis=(wv.t, UP, -wv.n))
    k.box(wv.P(4.1, Y0 + 30.8, -0.4), (9.2, 0.5, 1.0), STONE, basis=(wv.t, UP, -wv.n))
    gw = f.wall(0.6, 4.1, 0.6, -4.1, (-1, 0))
    niches = [arch_round(0.25 + j * 0.98 + 0.08, 0.25 + j * 0.98 + 0.88, Y0 + 26.5, Y0 + 30.4, 6) for j in range(8)]
    k.lod = (0, 0)
    wall_with_openings(k, gw, Y0 + 26.0, Y0 + 31.0, niches, STONE, 0.5, inner=STONE)
    for j in range(8):
        p = gw.P(0.25 + j * 0.98 + 0.48, Y0 + 26.5, 0.2)
        k.lathe(p, [(0.18, 0), (0.2, 0.25), (0.22, 1.5), (0.27, 2.2), (0.13, 2.5), (0.15, 2.8), (0.0, 2.95)], "pierre_taille", 8)
    k.lod = (1, 1); k.quad(gw.P(0, Y0 + 26), gw.P(gw.L, Y0 + 26), gw.P(gw.L, Y0 + 31), gw.P(0, Y0 + 31), STONE, gw.n)
    # tour-lanterne Renaissance (Jean Delespine) : étage carré à pilastres, clocheton hexagonal, croix d'Anjou
    k.lod = (0, 2)
    LT0 = Y0 + 31.0; LT1 = Y0 + 45.0
    sq = [tuple(f.p2(u, v)) for u, v in ((1.0, -3.6), (8.2, -3.6), (8.2, 3.6), (1.0, 3.6))]
    k.prism(sq, LT0, LT1, STONE, top=STONE)
    k.lod = (0, 0)
    for (fu, side_v, out) in ((1.0, None, (-1, 0)),):
        lw = f.wall(1.0, 3.6, 1.0, -3.6, (-1, 0))
        k.quad(lw.P(0, LT0), lw.P(lw.L, LT0), lw.P(lw.L, LT1), lw.P(0, LT1), STONE, lw.n)
        for u in (0.4, 2.5, 4.7, 6.8):
            k.box(lw.P(u, (LT0 + LT1) / 2, -0.15), (0.45, LT1 - LT0, 0.3), STONE, basis=(lw.t, UP, -lw.n))
        for u in (1.45, 5.75):
            k.poly([lw.P(x, y, -0.02) for x, y in arch_round(u - 0.65, u + 0.65, LT0 + 3.0, LT0 + 9.5, 8)], "lm_menuiserie_sombre", lw.n)
        k.box(lw.P(3.6, LT0 + 11.5, -0.3), (7.6, 0.6, 0.6), STONE, basis=(lw.t, UP, -lw.n))
    k.lod = (0, 1)
    k.box(f.P(4.6, 0, LT1 + 0.4), (8.0, 0.8, 8.0), STONE, basis=f.basis())
    hc = f.P(4.6, 0, LT1 + 0.8)
    k.lathe(hc, [(2.6, 0), (2.6, 5.5), (2.9, 5.8), (2.9, 6.1), (2.2, 6.4), (1.2, 8.2), (0.3, 9.4), (0.3, 10.4), (0.0, 10.6)], STONE, 6, smooth=False)
    k.lod = (0, 0)
    for i in range(6):
        a = 2 * math.pi * (i + 0.5) / 6
        p = hc + v3(math.cos(a), 0, math.sin(a)) * 2.62
        k.quad(p + UP * 1.2 - v3(-math.sin(a), 0, math.cos(a)) * 0.55, p + UP * 1.2 + v3(-math.sin(a), 0, math.cos(a)) * 0.55,
               p + UP * 4.6 + v3(-math.sin(a), 0, math.cos(a)) * 0.55, p + UP * 4.6 - v3(-math.sin(a), 0, math.cos(a)) * 0.55, "lm_menuiserie_sombre", v3(math.cos(a), 0, math.sin(a)))
    k.lod = (0, 1)
    k.box(hc + UP * 11.6, (0.14, 2.0, 0.14), "lm_ferronnerie")
    for yy, w_ in ((11.95, 1.0), (12.35, 0.7)):   # croix d'Anjou (double traverse)
        k.box(hc + UP * yy, (w_, 0.12, 0.12), "lm_ferronnerie", yaw=math.atan2(f.v[1], f.v[0]))
    k.lod = (2, 2)
    k.cyl(hc, hc + UP * 10.6, 2.6, STONE, 6, r2=0.2)
    # cônes des flèches LOD2
    for side in (-1, 1):
        k.cyl(f.P(4.6, side * 7.8, TT), f.P(4.6, side * 7.8, Y0 + 75.0), 3.6, STONE, 8, r2=0.05)
    # LOD2 : toits
    k.lod = (2, 2)
    gable_roof(k, f, 10.5, 82.5, 10.4, EA, RI, gable_walls=False)
    # collisions simples et emprise à remplacer
    for (u, v, su, sv, h) in ((4.6, 0, 9.2, 23, 44), (34.25, 0, 47.5, 20.4, 22), (66, 0, 16, 49, 22), (82, 0, 17, 18.4, 21)):
        k.collider(f.P(u, v, Y0 + h / 2 - 1), (su, h + 2, sv), math.atan2(f.u[1], f.u[0]))
    meta = {"replace": [list(Polygon(ENV).buffer(3.0, join_style=2).exterior.coords)[:-1]],
            "blocks": [[[tuple(f.p2(u, v)) for u, v in foot], yb, RI - yb]], "keepout": []}
    anchor = (fo[0], Y0, fo[1])
    return k, anchor, meta


if __name__ == "__main__":
    k, a, m = build()
    for l in range(3): print("LOD", l, k.tris(l))
