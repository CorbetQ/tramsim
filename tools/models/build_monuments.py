"""Monuments P3 d'Angers et de Nantes (glTF LOD0-2, géoréférencés sur la BD TOPO de data/scenes et sur les
constructions linéaires BD TOPO : douves du château des ducs). Silhouettes et volumes d'après les dimensions publiées
(Wikipédia, sites des monuments) ; détails procéduraux (bandes de schiste et de tuffeau, mâchicoulis, merlons, baies).
Appelé par build_all.py. Chaque constructeur renvoie (Kit, ancre (x, y, z) repère de la ville, méta : replace, blocks)."""
import math
import numpy as np
from shapely.geometry import Polygon, Point, LineString
import geo
from meshkit import Kit, v3, norm, UP
from archkit import mansard, hip_roof

TUF = "facade_tuffeau"; SCH = "pierre_taille#6b6f78"; GRA = "pierre_taille#9c9890"; STONE = "pierre_taille"
SLATE = "toiture"; ZINC = "lm_zinc"; GLASS = "lm_vitre"; DARK = "lm_menuiserie_sombre"; METAL = "mobilier_metal"
WHITE = "lm_peinture_blanche"; BRICK = "facade_brique"; WOOD = "lm_bois"; IRON = "lm_ferronnerie"; GOLD = "lm_jaune"
CONC = "beton_banche"


# ------------------------------------------------------------------ outils
def ccw(ring):
    ring = [tuple(map(float, p)) for p in ring]
    if len(ring) > 1 and ring[0] == ring[-1]: ring = ring[:-1]
    return ring if Polygon(ring).exterior.is_ccw else ring[::-1]


def out_n(a, b):
    """Normale sortante d'une arête d'un anneau CCW (repère x, z ; z vers le sud : CCW de shapely)."""
    e = np.array(b) - np.array(a); n = np.array([e[1], -e[0]]); L = np.linalg.norm(n)
    return n / L if L > 1e-9 else n


def walls(k, ring, y0, y1, mat):
    ring = ccw(ring)
    for i in range(len(ring)):
        a, b = ring[i], ring[(i + 1) % len(ring)]
        n = out_n(a, b)
        k.quad((a[0], y0, a[1]), (b[0], y0, b[1]), (b[0], y1, b[1]), (a[0], y1, a[1]), mat, v3(n[0], 0, n[1]))


def banded(k, ring, y0, y1, bands):
    """Murs à assises alternées : bands = [(matériau, épaisseur), ...] répétés de bas en haut."""
    y = y0; i = 0
    while y < y1 - 1e-3:
        mat, t = bands[i % len(bands)]
        walls(k, ring, y, min(y1, y + t), mat); y += t; i += 1


def talus(k, ring, y0, y1, d, mat):
    """Glacis (fruit) au pied : anneau élargi de d en bas, raccordé au mur en y1."""
    ring = ccw(ring); big = ccw(list(Polygon(ring).buffer(d, join_style=2).exterior.coords))
    P = Polygon(big)
    if not P.is_valid: return
    # raccord par projection : chaque sommet du mur vers le point le plus proche de l'anneau élargi
    ext = P.exterior
    for i in range(len(ring)):
        a, b = ring[i], ring[(i + 1) % len(ring)]
        pa = ext.interpolate(ext.project(Point(a))); pb = ext.interpolate(ext.project(Point(b)))
        n = out_n(a, b)
        k.quad((pa.x, y0, pa.y), (pb.x, y0, pb.y), (b[0], y1, b[1]), (a[0], y1, a[1]), mat, v3(n[0], 0.5, n[1]))


def parapet(k, ring, y, mat, h=1.2, t=0.5, merlons=True, step=2.2, cap=True):
    ring = ccw(ring)
    inner = Polygon(ring).buffer(-t, join_style=2)
    k.poly([(p[0], y, p[1]) for p in ring], mat, UP) if inner.is_empty else None
    walls(k, ring, y, y + h, mat)
    if not inner.is_empty and inner.geom_type == "Polygon":
        ir = ccw(list(inner.exterior.coords))
        for i in range(len(ir)):   # face intérieure
            a, b = ir[i], ir[(i + 1) % len(ir)]; n = -out_n(a, b)
            k.quad((a[0], y, a[1]), (b[0], y, b[1]), (b[0], y + h, b[1]), (a[0], y + h, a[1]), mat, v3(n[0], 0, n[1]))
        if cap: k.poly([(p[0], y, p[1]) for p in ir], mat, UP)
        # chemin de ronde : couronnement
        for i in range(len(ring)):
            a, b = ring[i], ring[(i + 1) % len(ring)]
            pa = inner.exterior.interpolate(inner.exterior.project(Point(a))); pb = inner.exterior.interpolate(inner.exterior.project(Point(b)))
            k.quad((a[0], y + h, a[1]), (b[0], y + h, b[1]), (pb.x, y + h, pb.y), (pa.x, y + h, pa.y), mat, UP)
    if merlons:
        lod = k.lod; k.lod = (0, 0)
        ext = LineString(ring + [ring[0]])
        n = int(ext.length / step)
        for j in range(n):
            if j % 2: continue
            p = ext.interpolate((j + 0.5) * step); q = ext.interpolate((j + 0.5) * step + 0.1)
            yaw = math.atan2(q.y - p.y, q.x - p.x)
            k.box(v3(p.x, y + h + 0.45, p.y), (step * 0.9, 0.9, t), mat, yaw=-yaw)
        k.lod = lod


def machicolations(k, ring, y, mat, d=0.7, h=1.6, step=1.6):
    """Mâchicoulis : encorbellement continu (bandeau en surplomb) sur consoles."""
    ring = ccw(ring); big = Polygon(ring).buffer(d, join_style=2)
    br = ccw(list(big.exterior.coords))
    walls(k, br, y, y + h, mat)
    ext = Polygon(br).exterior
    for i in range(len(ring)):   # sous-face de l'encorbellement (bande, pas de couvercle)
        a, b = ring[i], ring[(i + 1) % len(ring)]
        pa = ext.interpolate(ext.project(Point(a))); pb = ext.interpolate(ext.project(Point(b)))
        k.quad((a[0], y, a[1]), (b[0], y, b[1]), (pb.x, y, pb.y), (pa.x, y, pa.y), mat, -UP)
    lod = k.lod; k.lod = (0, 0)
    ext = LineString(ring + [ring[0]])
    for j in range(int(ext.length / step)):
        p = ext.interpolate(j * step); q = ext.interpolate(j * step + 0.1)
        yaw = math.atan2(q.y - p.y, q.x - p.x)
        c = np.array([p.x, p.y]); nrm = np.array([-(q.y - p.y), q.x - p.x]); nrm /= max(np.linalg.norm(nrm), 1e-9)
        if Polygon(ring).contains(Point(c + nrm * 0.2)): nrm = -nrm
        cc = c + nrm * d * 0.5
        k.box(v3(cc[0], y - 0.7, cc[1]), (0.45, 1.4, d), mat, yaw=-yaw)
    k.lod = lod
    return br


def cone(k, c, r, y0, h, mat, seg=20):
    k.lathe(v3(c[0], 0, c[1]), [(r, y0), (r * 0.55, y0 + h * 0.45), (0.05, y0 + h)], mat, seg=seg)


def circle(c, r, n=20):
    return [(c[0] + r * math.cos(2 * math.pi * i / n), c[1] + r * math.sin(2 * math.pi * i / n)) for i in range(n)]


def obb(ring):
    """Rectangle orienté : centre, axe long u, axe court v (2D), demi-longueurs."""
    r = Polygon(ring).minimum_rotated_rectangle
    p = np.array(r.exterior.coords[:4])
    e0 = p[1] - p[0]; e1 = p[2] - p[1]
    if np.linalg.norm(e0) < np.linalg.norm(e1): e0, e1 = e1, e0
    c = p.mean(axis=0)
    return c, e0 / np.linalg.norm(e0), e1 / np.linalg.norm(e1), np.linalg.norm(e0) / 2, np.linalg.norm(e1) / 2


class Frame2:
    def __init__(self, c, u, v): self.c, self.u, self.v = np.array(c, float), np.array(u, float), np.array(v, float)
    def p(self, a, b): return self.c + self.u * a + self.v * b
    def ring(self, a0, a1, b0, b1): return [tuple(self.p(a0, b0)), tuple(self.p(a1, b0)), tuple(self.p(a1, b1)), tuple(self.p(a0, b1))]
    def P(self, a, b, y): q = self.p(a, b); return v3(q[0], y, q[1])
    def yaw(self): return -math.atan2(self.u[1], self.u[0])


def window_grid(k, w0, w1, y0, rows, fh, wpitch, ww, wh, out, mat_frame=TUF, arched=False):
    """Baies sur une face plane w0-w1 (2D) : fond sombre en léger retrait, encadrement saillant (LOD0)."""
    w0, w1 = np.array(w0, float), np.array(w1, float); L = np.linalg.norm(w1 - w0); t = (w1 - w0) / L
    o = np.array(out, float); n = max(1, int(L / wpitch))
    lod = k.lod
    for r in range(rows):
        for i in range(n):
            x = (i + 0.5) * L / n; c = w0 + t * x; y = y0 + r * fh
            a = c - t * ww / 2 + o * 0.03; b = c + t * ww / 2 + o * 0.03
            k.lod = (0, 1)
            k.quad((a[0], y, a[1]), (b[0], y, b[1]), (b[0], y + wh, b[1]), (a[0], y + wh, a[1]), DARK, v3(o[0], 0, o[1]))
            if arched:
                m = (a + b) / 2
                k.tri((a[0], y + wh, a[1]), (b[0], y + wh, b[1]), (m[0], y + wh + ww * 0.45, m[1]), DARK, v3(o[0], 0, o[1]))
            k.lod = (0, 0)
            for (p0, p1, yy, hh) in ((a - t * 0.15, a, y - 0.1, wh + 0.25), (b, b + t * 0.15, y - 0.1, wh + 0.25)):
                cc = (p0 + p1) / 2 + o * 0.06
                k.box(v3(cc[0], yy + hh / 2, cc[1]), (0.15, hh, 0.12), mat_frame, yaw=-math.atan2(t[1], t[0]))
            cc = c + o * 0.09
            k.box(v3(cc[0], y - 0.06, cc[1]), (ww + 0.4, 0.12, 0.18), mat_frame, yaw=-math.atan2(t[1], t[0]))
    k.lod = lod


def bd_rings(city, x, z, r, pred):
    out = []
    for b in city.scene()["b"]:
        P = Polygon(b["ring"])
        if P.is_valid and P.centroid.distance(Point(x, z)) < r and pred(b, P): out.append(b)
    return out


def ground_min(city, ring, d=0.0):
    ring = ccw(ring)
    pts = ring if d == 0 else list(Polygon(ring).buffer(d).exterior.coords)
    return min(city.ground(p[0], p[1]) for p in pts)


def finish(k, rings_replace, blocks, anchor_xz, city):
    ay = city.ground(*anchor_xz)
    return k, (anchor_xz[0], ay, anchor_xz[1]), {"replace": [list(map(list, ccw(r))) for r in rings_replace], "blocks": blocks}


# ------------------------------------------------------------------ Angers
def chateau_angers():
    """Château d'Angers (XIIIe) : enceinte de 17 tours en bandes de schiste ardoisier et de tuffeau, arasées au
    XVIe s. ; tours et courtines BD TOPO (emprises, hauteurs LiDAR), glacis au pied, fossé du relief IGN."""
    city = geo.City("angers"); k = Kit()
    sel = bd_rings(city, -434, -2891, 135, lambda b, P: (b["kind"] & 7) == 3 and b["h"] >= 20 and P.area < 5000 and b["cls"] == 4)
    blocks = []
    for b in sel:
        ring = ccw(b["ring"]); base = ground_min(city, ring, 1.5) - 1.0
        top = ground_min(city, ring) + b["h"]
        k.lod = (0, 2)
        banded(k, ring, base, top, [(SCH, 1.3), (TUF, 0.9), (SCH, 1.1), (TUF, 0.8)])
        k.lod = (0, 1)
        talus(k, ring, base, base + 5.0, 1.4, SCH)
        k.lod = (0, 2)
        parapet(k, ring, top, SCH, h=1.1, t=0.6, merlons=True)
        blocks.append([list(map(list, ring)), base, top - base + 1.1])
    # tour du Moulin (angle nord, la plus haute) : échauguette et toit en poivrière
    north = max(sel, key=lambda b: -Polygon(b["ring"]).centroid.y)
    c = Polygon(north["ring"]).centroid; top = ground_min(city, north["ring"]) + north["h"]
    k.lod = (0, 2)
    k.cyl(v3(c.x, top, c.y), v3(c.x, top + 4.0, c.y), 2.6, TUF, 16)
    cone(k, (c.x, c.y), 3.2, top + 4.0, 6.0, SLATE)
    u = Polygon(sum([list(b["ring"]) for b in sel], [])).convex_hull.centroid
    return finish(k, [b["ring"] for b in sel], blocks, (u.x, u.y), city)


def gare_saint_laud():
    """Gare d'Angers-Saint-Laud : bâtiment voyageurs XIXe en tuffeau, pavillon central à comble d'ardoise et horloge,
    ailes à arcades, marquise vitrée côté parvis (nord)."""
    city = geo.City("angers"); k = Kit()
    b = max(bd_rings(city, -174.8, -2301.4, 30, lambda b, P: P.area > 1500), key=lambda b: Polygon(b["ring"]).area)
    c, u, v, hl, hw = obb(b["ring"])
    if v[1] > 0: v = -v   # v vers le nord (parvis) : z décroissant
    F = Frame2(c, u, v); g = ground_min(city, b["ring"])
    hw = min(hw, 11.0)
    k.lod = (0, 2)
    # ailes (2 niveaux) et pavillon central (3 niveaux)
    for a0, a1, h in ((-hl, -13.0, 11.0), (13.0, hl, 11.0)):
        k.prism(F.ring(a0, a1, -hw, hw), g, g + h, TUF, top=False)
        hip_roof(k, F.ring(a0, a1, -hw, hw), g + h, 4.5, SLATE)
        window_grid(k, F.p(a0, hw), F.p(a1, hw), g + 1.0, 1, 5, 4.2, 2.2, 3.6, v, arched=True)
        window_grid(k, F.p(a0, hw), F.p(a1, hw), g + 6.4, 1, 4, 4.2, 1.4, 2.6, v)
    k.prism(F.ring(-13.0, 13.0, -hw - 1.2, hw), g, g + 15.5, TUF, top=False)
    mansard(k, F.ring(-13.0, 13.0, -hw - 1.2, hw), g + 15.5, SLATE, ZINC, brisis=(1.8, 5.0), terrasson=(5.5, 1.5))
    window_grid(k, F.p(-13.0, hw), F.p(13.0, hw), g + 1.0, 1, 5, 5.2, 3.2, 5.0, v, arched=True)
    window_grid(k, F.p(-13.0, hw), F.p(13.0, hw), g + 8.0, 2, 3.6, 5.2, 1.6, 2.5, v)
    # corniche et fronton à horloge
    k.lod = (0, 1)
    k.box(F.P(0, hw + 0.2, g + 15.3), (26.4, 0.5, 1.0), TUF, yaw=F.yaw())
    k.box(F.P(0, hw + 0.4, g + 18.0), (7.0, 5.0, 1.0), TUF, yaw=F.yaw())
    p = F.P(0, hw + 0.95, g + 18.0); vv = v3(v[0], 0, v[1])
    k.cyl(p - vv * 0.05, p + vv * 0.1, 1.5, WHITE, 24)
    k.cyl(p + vv * 0.1, p + vv * 0.14, 0.12, DARK, 8)
    # marquise vitrée du parvis
    k.lod = (0, 2)
    k.box(F.P(0, hw + 4.0, g + 5.2), (40.0, 0.25, 8.0), GLASS, yaw=F.yaw())
    k.lod = (0, 1)
    for a in range(-18, 19, 6):
        k.cyl(F.P(a, hw + 7.6, g), F.P(a, hw + 7.6, g + 5.1), 0.15, METAL, 8)
    ring = F.ring(-hl, hl, -hw - 1.2, hw)
    return finish(k, [b["ring"]], [[list(map(list, ccw(ring))), g, 20.0]], tuple(c), city)


def hotel_de_ville_angers():
    """Hôtel de ville d'Angers (bd de la Résistance-et-de-la-Déportation) : bâtiments BD TOPO (usage administratif),
    façades en tuffeau à travées, combles d'ardoise à la Mansart, avant-corps à fronton, horloge et campanile."""
    city = geo.City("angers"); k = Kit()
    sel = bd_rings(city, 433, -3003, 75, lambda b, P: (b["kind"] & 7) == 4 and P.area > 250)
    blocks = []
    main = max(sel, key=lambda b: Polygon(b["ring"]).area)
    for b in sel:
        ring = ccw(Polygon(b["ring"]).simplify(0.6).exterior.coords)
        g = ground_min(city, ring); h = max(b["h"], 9.0)
        k.lod = (0, 2)
        k.prism(ring, g, g + h, TUF, top=False)
        mansard(k, ring, g + h, SLATE, ZINC, brisis=(1.2, 3.6), terrasson=(3.4, 1.0))
        for i in range(len(ring)):
            a, bb = ring[i], ring[(i + 1) % len(ring)]
            if math.dist(a, bb) < 8: continue
            n = out_n(a, bb)
            window_grid(k, a, bb, g + 1.2, max(1, int((h - 1.5) / 3.8)), 3.8, 3.4, 1.4, 2.4, n)
            k.lod = (0, 1)
            e = np.array(bb) - np.array(a); m = (np.array(a) + bb) / 2 + n * 0.25
            k.box(v3(m[0], g + h - 0.25, m[1]), (float(np.linalg.norm(e)), 0.5, 0.6), TUF, yaw=-math.atan2(e[1], e[0]))
            k.lod = (0, 2)
        blocks.append([list(map(list, ring)), g, h + 4.6])
    # avant-corps de la façade principale (plus longue arête du bâtiment principal) : fronton, horloge, campanile
    ring = ccw(main["ring"]); g = ground_min(city, ring); h = max(main["h"], 9.0)
    i = max(range(len(ring)), key=lambda i: math.dist(ring[i], ring[(i + 1) % len(ring)]))
    a, bb = np.array(ring[i]), np.array(ring[(i + 1) % len(ring)]); n = out_n(a, bb); t = (bb - a) / np.linalg.norm(bb - a)
    m = (a + bb) / 2; F = Frame2(m, t, n)
    k.lod = (0, 2)
    k.prism(F.ring(-6, 6, -1.0, 1.2), g, g + h + 2.0, TUF)
    k.tri(F.P(-6.3, 1.3, g + h + 2.0), F.P(6.3, 1.3, g + h + 2.0), F.P(0, 1.3, g + h + 5.0), TUF, v3(n[0], 0, n[1]))
    k.quad(F.P(-6.3, 1.3, g + h + 2.0), F.P(0, 1.3, g + h + 5.0), F.P(0, -6, g + h + 5.0), F.P(-6.3, -6, g + h + 2.0), SLATE, v3(-t[0], 1, -t[1]))
    k.quad(F.P(0, 1.3, g + h + 5.0), F.P(6.3, 1.3, g + h + 2.0), F.P(6.3, -6, g + h + 2.0), F.P(0, -6, g + h + 5.0), SLATE, v3(t[0], 1, t[1]))
    k.lod = (0, 1)
    p = F.P(0, 1.35, g + h + 3.0); nn = v3(n[0], 0, n[1])
    k.cyl(p, p + nn * 0.12, 1.0, WHITE, 24)
    cp = F.p(0, -3.0)
    k.cyl(v3(cp[0], g + h + 4.5, cp[1]), v3(cp[0], g + h + 8.0, cp[1]), 1.3, TUF, 8)
    k.lathe(v3(cp[0], 0, cp[1]), [(1.6, g + h + 8.0), (1.2, g + h + 9.5), (0.3, g + h + 11.0), (0.05, g + h + 13.0)], ZINC, seg=8)
    k.cyl(v3(cp[0], g + h + 13.0, cp[1]), v3(cp[0], g + h + 16.0, cp[1]), 0.05, METAL, 6)
    window_grid(k, F.p(-6, 1.2), F.p(6, 1.2), g + 1.0, 1, 4, 4.0, 2.4, 3.8, n, arched=True)
    c = Polygon(sum([list(b["ring"]) for b in sel], [])).convex_hull.centroid
    return finish(k, [b["ring"] for b in sel], blocks, (c.x, c.y), city)


# ------------------------------------------------------------------ Nantes
# Contrescarpe des douves (BD TOPO, constructions linéaires « mur de soutènement »), repère de la ville de Nantes
DOUVES = [(6586.6, 625.3), (6595.1, 611.6), (6604.0, 583.1), (6612.1, 572.2), (6621.9, 564.3), (6642.1, 558.5), (6683.8, 554.0),
          (6703.4, 549.2), (6714.3, 557.2), (6747.6, 556.5), (6755.4, 555.9), (6776.0, 591.6), (6789.9, 617.6), (6783.0, 612.0),
          (6771.4, 626.9), (6755.4, 634.4), (6744.4, 645.5), (6739.0, 658.7), (6744.7, 679.0), (6739.3, 688.9), (6716.7, 704.4),
          (6685.3, 723.7), (6654.2, 739.3), (6632.8, 748.2), (6619.2, 747.8), (6610.8, 741.6), (6598.8, 721.8), (6586.0, 701.3),
          (6578.4, 684.5), (6575.7, 658.2), (6580.9, 638.8)]


def chateau_nantes():
    """Château des ducs de Bretagne (XVe) : courtines et tours à mâchicoulis en tuffeau sur soubassement de granit,
    châtelet d'entrée à deux tours (ouest, pont dormant BD TOPO), bastion du Fer-à-cheval ; enceinte tracée à 13 m
    en retrait de la contrescarpe BD TOPO, pied dans les douves (relief IGN)."""
    city = geo.City("nantes"); k = Kit()
    outer = Polygon(DOUVES).buffer(0)
    curt = outer.buffer(-13.0, join_style=2)
    # gabarit de la ligne 1 (allée du Cdt-Charcot, au ras des douves) : enceinte tenue à 13 m de l'axe des voies
    tracks = []
    for e in geo.network("nantes_1")["edges"]:
        pts = e["pts"] if isinstance(e["pts"], list) else __import__("json").loads(e["pts"])
        if len(pts) > 1 and LineString(pts).distance(outer) < 60: tracks.append(LineString(pts))
    if tracks:
        from shapely.ops import unary_union
        curt = curt.difference(unary_union(tracks).buffer(13.0))
        if curt.geom_type != "Polygon": curt = max(curt.geoms, key=lambda q: q.area)
    curt = curt.simplify(2.5)
    ring = ccw(list(curt.exterior.coords))
    inner = curt.buffer(-3.2, join_style=2)
    g_in = city.ground(curt.centroid.x, curt.centroid.y)
    # le relief IGN lisse les douves : courtines à 9 m au-dessus de la contrescarpe (≈ 13 m au-dessus des douves)
    g_out = float(np.mean([city.ground(*q) for q in outer.exterior.coords]))
    top = g_out + 9.0
    base = min(city.ground(p[0], p[1]) for p in outer.buffer(-10.5).exterior.coords) - 0.5
    band = ccw(list(curt.exterior.coords))
    k.lod = (0, 2)
    banded(k, band, base, top, [(GRA, max(2.0, g_in - base + 1.5)), (TUF, 40.0)])
    talus(k, band, base, base + 4.0, 1.2, GRA)
    ir = ccw(list(inner.exterior.coords))
    for i in range(len(ir)):   # face intérieure des courtines (côté cour) et chemin de ronde
        a, b = ir[i], ir[(i + 1) % len(ir)]; nn = -out_n(a, b)
        k.quad((a[0], g_in - 1.0, a[1]), (b[0], g_in - 1.0, b[1]), (b[0], top, b[1]), (a[0], top, a[1]), TUF, v3(nn[0], 0, nn[1]))
    ext = curt.exterior
    for i in range(len(ir)):
        a, b = ir[i], ir[(i + 1) % len(ir)]
        pa = ext.interpolate(ext.project(Point(a))); pb = ext.interpolate(ext.project(Point(b)))
        k.quad((a[0], top, a[1]), (b[0], top, b[1]), (pb.x, top, pb.y), (pa.x, top, pa.y), GRA, UP)
    machicolations(k, band, top, TUF, d=0.6, h=1.4)
    parapet(k, ccw(list(curt.buffer(0.6, join_style=2).exterior.coords)), top + 1.4, TUF, h=0.9, t=0.5, merlons=False, cap=False)
    # tours : sommets saillants de l'enceinte (angle > 28°) et châtelet d'entrée face au pont ouest
    towers = []
    n = len(ring)
    for i in range(n):
        a, p, b = np.array(ring[i - 1]), np.array(ring[i]), np.array(ring[(i + 1) % n])
        d1, d2 = norm(p - a), norm(b - p)
        turn = math.degrees(math.acos(np.clip(np.dot(d1, d2), -1, 1)))
        clear = min([tl.distance(Point(p)) for tl in tracks] or [99.0])
        if turn > 28 and clear > 12.0 and all(np.linalg.norm(p - q) > 22 for q, _ in towers): towers.append((p, 7.5))
    gate = np.array([6600.0, 631.0])   # extrémité intérieure du pont dormant (BD TOPO)
    e = curt.exterior; s = e.project(Point(gate)); gp = e.interpolate(s)
    t = np.array(e.interpolate(s + 1).coords[0]) - np.array(gp.coords[0]); t = t / np.linalg.norm(t)
    for sgn in (-1, 1):
        q = np.array(gp.coords[0]) + t * 8.5 * sgn
        towers = [(p, r) for (p, r) in towers if np.linalg.norm(p - q) > 14]
        towers.append((q, 6.5))
    blocks = [[list(map(list, band)), base, top + 3 - base]]
    for j, (p, r) in enumerate(towers):
        tr = circle(p, r, 24); tb = min(city.ground(*q) for q in circle(p, r + 2, 8)) - 0.5
        tt = top + 4.0
        k.lod = (0, 2)
        banded(k, tr, tb, tt, [(GRA, max(1.0, g_in - tb + 1.5)), (TUF, 40.0)])
        talus(k, tr, tb, tb + 4.0, 1.4, GRA)
        machicolations(k, tr, tt, TUF, d=0.7, h=1.6)
        parapet(k, circle(p, r + 0.7, 24), tt + 1.6, TUF, h=1.0, t=0.5, merlons=False)
        if r < 7.0:   # tours du châtelet : poivrières d'ardoise
            cone(k, p, r + 0.9, tt + 2.6, r * 1.6, SLATE, 24)
        else:
            k.poly([(q[0], tt + 1.6, q[1]) for q in circle(p, r + 0.2, 24)], SLATE, UP)
        blocks.append([list(map(list, ccw(tr))), tb, tt + 2.6 - tb])
    # porte charretière et piétonne entre les tours
    k.lod = (0, 1)
    gq = np.array(gp.coords[0]); nrm = np.array([-t[1], t[0]])
    if curt.contains(Point(gq + nrm * 2)): nrm = -nrm
    yaw = -math.atan2(t[1], t[0])
    k.box(v3(gq[0] + nrm[0] * 0.2, g_in + 2.4, gq[1] + nrm[1] * 0.2), (4.0, 4.8, 0.3), DARK, yaw=yaw)
    c = outer.centroid
    rep = bd_rings(city, c.x, c.y, 140, lambda b, P: P.intersects(curt.exterior.buffer(4.5)) and not P.within(curt.buffer(-6)))
    return finish(k, [b["ring"] for b in rep], blocks, (c.x, c.y), city)


def cathedrale_nantes():
    """Cathédrale Saint-Pierre-et-Saint-Paul : façade occidentale à deux tours carrées (63 m) et trois portails,
    nef haute (voûtes 37,5 m) sous toit d'ardoise, bas-côtés et arcs-boutants, transept, chœur ; tuffeau blanc.
    Emprise BD TOPO (rectangle 102 × 55 m) et tours (bloc ouest)."""
    city = geo.City("nantes"); k = Kit()
    b = max(bd_rings(city, 6608.8, 404.5, 30, lambda b, P: P.area > 4000), key=lambda b: Polygon(b["ring"]).area)
    tw = bd_rings(city, 6569.4, 413.1, 12, lambda b, P: P.area > 400 and b["h"] > 40)
    c, u, v, hl, hw = obb(b["ring"])
    tc = Polygon(tw[0]["ring"]).centroid if tw else Point(c - u * hl)
    if np.dot(np.array([tc.x, tc.y]) - c, u) > 0: u = -u   # u vers l'est (chœur), façade à -hl
    v = np.array([-u[1], u[0]])
    F = Frame2(c, u, v); g = ground_min(city, b["ring"])
    W = hw; nave = W * 0.34
    k.lod = (0, 2)
    # nef et chœur, toit à deux pans
    k.prism(F.ring(-hl + 14, hl, -nave, nave), g, g + 38.0, TUF, top=False)
    gr = F.ring(-hl + 14, hl, -nave, nave)
    A, B, C, D = [v3(p[0], g + 38.0, p[1]) for p in gr]
    R0 = F.P(-hl + 14, 0, g + 51.0); R1 = F.P(hl, 0, g + 51.0)
    k.quad(A, B, R1, R0, SLATE, v3(-v[0], 1, -v[1])); k.quad(C, D, R0, R1, SLATE, v3(v[0], 1, v[1]))
    k.tri(D, A, R0, TUF, v3(-u[0], 0, -u[1])); k.tri(B, C, R1, TUF, v3(u[0], 0, u[1]))
    # bas-côtés, transept
    for s in (-1, 1):
        k.prism(F.ring(-hl + 14, hl - 6, s * nave, s * W) if s > 0 else F.ring(-hl + 14, hl - 6, -W, -nave), g, g + 20.0, TUF)
    k.prism(F.ring(hl * 0.25 - 9, hl * 0.25 + 9, -W - 3, W + 3), g, g + 36.0, TUF, top=False)
    tr = F.ring(hl * 0.25 - 9, hl * 0.25 + 9, -W - 3, W + 3)
    hip_roof(k, tr, g + 36.0, 10.0, SLATE)
    # contreforts et arcs-boutants
    k.lod = (0, 1)
    for a in np.arange(-hl + 20, hl - 4, 8.0):
        if abs(a - hl * 0.25) < 11: continue
        for s in (-1, 1):
            k.box(F.P(a, s * (W + 0.8), g + 12.0), (1.4, 24.0, 2.2), TUF, yaw=F.yaw())
            k.seg_box(F.P(a, s * (W + 0.8), g + 22.0), F.P(a, s * (nave + 0.5), g + 33.0), 0.9, 0.9, TUF)
        k.lod = (0, 0)
        for s in (-1, 1):   # hautes baies de la nef
            k.quad(F.P(a - 1.5, s * (nave + 0.05), g + 24.0), F.P(a + 1.5, s * (nave + 0.05), g + 24.0),
                   F.P(a + 1.5, s * (nave + 0.05), g + 34.0), F.P(a - 1.5, s * (nave + 0.05), g + 34.0), "lm_vitrail", v3(s * v[0], 0, s * v[1]))
        k.lod = (0, 1)
    # façade et tours (bloc ouest)
    k.lod = (0, 2)
    x0 = -hl
    for s in (-1, 1):
        k.prism(F.ring(x0, x0 + 14, s * (nave + 0.5) if s > 0 else -W, W if s > 0 else -(nave + 0.5)), g, g + 63.0, TUF)
        k.lod = (0, 1)
        for yy in (30.0, 46.0):   # baies hautes des tours (abat-sons)
            k.quad(F.P(x0 - 0.05, s * (nave + W) / 2 - 1.6, g + yy), F.P(x0 - 0.05, s * (nave + W) / 2 + 1.6, g + yy),
                   F.P(x0 - 0.05, s * (nave + W) / 2 + 1.6, g + yy + 10), F.P(x0 - 0.05, s * (nave + W) / 2 - 1.6, g + yy + 10), DARK, v3(-u[0], 0, -u[1]))
        k.lod = (0, 2)
        tr = F.ring(x0, x0 + 14, s * (nave + 0.5) if s > 0 else -W, W if s > 0 else -(nave + 0.5))
        parapet(k, ccw(tr), g + 63.0, TUF, h=1.3, t=0.5, merlons=False)
    k.prism(F.ring(x0, x0 + 14, -nave - 0.5, nave + 0.5), g, g + 40.0, TUF)
    k.tri(F.P(x0 - 0.02, -nave, g + 40.0), F.P(x0 - 0.02, nave, g + 40.0), F.P(x0 - 0.02, 0, g + 48.0), TUF, v3(-u[0], 0, -u[1]))
    # portails (ogives) et grande baie
    k.lod = (0, 1)
    for s, wdt in ((-1, 4.0), (0, 5.5), (1, 4.0)):
        yv = s * (nave + W) / 2 if s else 0.0
        P0 = F.P(x0 - 0.06, yv - wdt / 2, g); P1 = F.P(x0 - 0.06, yv + wdt / 2, g)
        k.quad(P0, P1, P1 + UP * 9.0, P0 + UP * 9.0, DARK, v3(-u[0], 0, -u[1]))
        k.tri(P0 + UP * 9.0, P1 + UP * 9.0, F.P(x0 - 0.06, yv, g + 9.0 + wdt * 0.9), DARK, v3(-u[0], 0, -u[1]))
        k.box(F.P(x0 - 0.8, yv, g + 7.0), (1.4, 14.0, wdt + 3.0), TUF, yaw=F.yaw() + math.pi / 2)
    k.quad(F.P(x0 - 0.06, -4, g + 20), F.P(x0 - 0.06, 4, g + 20), F.P(x0 - 0.06, 4, g + 34), F.P(x0 - 0.06, -4, g + 34), "lm_vitrail", v3(-u[0], 0, -u[1]))
    # contreforts d'angle des tours (ressauts), pinacles, baies des bas-côtés
    for s in (-1, 1):
        y0t = s * (nave + 0.5) if s > 0 else -W; y1t = W if s > 0 else -(nave + 0.5)
        for (xa, ya) in ((x0, y0t), (x0, y1t), (x0 + 14, y1t if s > 0 else y0t)):
            for j, (hh, dd) in enumerate(((22.0, 2.2), (40.0, 1.6), (56.0, 1.0))):
                k.lod = (0, 1) if j < 2 else (0, 0)
                k.box(F.P(xa - 0.4 * dd, ya + (0.4 * dd if ya == y1t and s > 0 or ya == -W else -0.4 * dd), g + hh / 2), (dd * 1.6, hh, dd * 1.6), TUF, yaw=F.yaw())
        k.lod = (0, 0)
        for (xa, ya) in ((x0, y0t), (x0, y1t), (x0 + 14, y0t), (x0 + 14, y1t)):
            q = F.p(xa, ya); k.lathe(v3(q[0], 0, q[1]), [(0.9, g + 64.3), (0.05, g + 68.0)], TUF, seg=4, smooth=False)
    k.lod = (0, 0)
    for a in np.arange(-hl + 24, hl - 8, 8.0):
        if abs(a - hl * 0.25) < 11: continue
        for s in (-1, 1):
            q = F.p(a, s * (W + 0.8)); k.lathe(v3(q[0], 0, q[1]), [(0.8, g + 24.0), (0.05, g + 27.5)], TUF, seg=4, smooth=False)
            k.quad(F.P(a - 1.2, s * (W + 0.03), g + 6.0), F.P(a + 1.2, s * (W + 0.03), g + 6.0),
                   F.P(a + 1.2, s * (W + 0.03), g + 16.0), F.P(a - 1.2, s * (W + 0.03), g + 16.0), "lm_vitrail", v3(s * v[0], 0, s * v[1]))
    rep = [b["ring"]] + [t["ring"] for t in tw]
    ring = F.ring(-hl, hl, -W - 3, W + 3)
    return finish(k, rep, [[list(map(list, ccw(ring))), g, 51.0]], tuple(c), city)


def tour_bretagne():
    """Tour Bretagne (1976, 144 m, 32 niveaux) : fût de bureaux à résille verticale claire et bandeaux vitrés,
    couronnement technique et belvédère, sculpture blanche du Nid au sommet (silhouette)."""
    city = geo.City("nantes"); k = Kit()
    # emprise BD TOPO de la tour (h LiDAR 109 m) : 47,2176 N, 1,5582 O (landmarks.json décalé de 70 m)
    b = max(bd_rings(city, 5998.0, 491.0, 25, lambda b, P: b["h"] > 80), key=lambda b: b["h"])
    c, u, v, hl, hw = obb(b["ring"])
    F = Frame2(c, u, v); g = ground_min(city, b["ring"])
    L, Wd = hl, hw
    k.lod = (0, 2)
    k.prism(F.ring(-L, L, -Wd, Wd), g, g + 136.0, GLASS)
    k.prism(F.ring(-L + 1.5, L - 1.5, -Wd + 1.5, Wd - 1.5), g + 136.0, g + 144.0, CONC)
    # résille : montants clairs tous les 1,8 m sur les 4 faces, nez de dalle tous les 4 niveaux
    k.lod = (0, 1)
    for (a0, b0, a1, b1, o) in ((-L, -Wd, L, -Wd, -v), (L, Wd, -L, Wd, v), (-L, Wd, -L, -Wd, -u), (L, -Wd, L, Wd, u)):
        p0 = F.p(a0, b0); p1 = F.p(a1, b1); n = int(np.linalg.norm(p1 - p0) / 1.8)
        e = (p1 - p0) / np.linalg.norm(p1 - p0); yaw = -math.atan2(e[1], e[0])
        for i in range(n + 1):
            q = p0 + (p1 - p0) * i / n + o * 0.12
            k.box(v3(q[0], g + 68.0, q[1]), (0.35, 136.0, 0.25), "lm_peinture_blanche#d9d8d2", yaw=yaw)
        k.lod = (0, 0)
        for f in range(0, 34, 2):
            q = (p0 + p1) / 2 + o * 0.15
            k.box(v3(q[0], g + 4.0 + f * 4.0, q[1]), (float(np.linalg.norm(p1 - p0)), 0.5, 0.3), "lm_peinture_blanche#d9d8d2", yaw=yaw)
        k.lod = (0, 1)
    # le Nid (oiseau blanc sur le toit)
    k.lod = (0, 2)
    k.lathe(v3(c[0], 0, c[1]), [(0.1, g + 144.0), (6.0, g + 146.0), (8.0, g + 149.0), (5.0, g + 152.0), (0.1, g + 153.0)], WHITE, seg=16)
    return finish(k, [b["ring"]], [[list(map(list, ccw(F.ring(-L, L, -Wd, Wd)))), g, 153.0]], tuple(c), city)


def gare_nantes():
    """Gare de Nantes : mezzanine franchissant les voies (2020, boîte vitrée sur « arbres » blancs, ombrière),
    emprise BD TOPO de la passerelle (bâtiment étroit nord-sud de 160 m)."""
    city = geo.City("nantes"); k = Kit()
    b = max(bd_rings(city, 7187, 557, 60, lambda b, P: (lambda r: r[3] > 50 and r[4] < 15)(obb(b["ring"]))),
            key=lambda b: obb(b["ring"])[3])
    c, u, v, hl, hw = obb(b["ring"])
    F = Frame2(c, u, v); g = ground_min(city, b["ring"])
    k.lod = (0, 2)
    k.prism(F.ring(-hl, hl, -hw, hw), g + 8.0, g + 16.0, GLASS, top=False)
    k.prism(F.ring(-hl, hl, -hw, hw), g + 7.0, g + 8.0, WHITE, top=WHITE, bottom=True)
    k.prism(F.ring(-hl - 4, hl + 4, -hw - 6, hw + 6), g + 16.0, g + 16.8, WHITE, bottom=True)   # ombrière
    k.lod = (0, 1)
    for a in np.arange(-hl + 6, hl - 2, 12.0):   # arbres : fût et quatre branches
        for s in (-1, 1):
            base = F.P(a, s * (hw + 2.5), g); top = F.P(a, s * (hw + 2.5), g + 9.0)
            k.cyl(base, top, 0.35, WHITE, 10)
            for (da, db) in ((-3, 0), (3, 0), (0, -2.5), (0, 2.5)):
                k.cyl(top, F.P(a + da, s * (hw + 2.5) + db, g + 16.0), 0.18, WHITE, 6)
    k.lod = (0, 0)
    for a in np.arange(-hl, hl, 3.0):   # menuiseries
        for s in (-1, 1):
            k.box(F.P(a, s * (hw + 0.05), g + 12.0), (0.15, 8.0, 0.15), METAL, yaw=F.yaw())
    return finish(k, [b["ring"]], [[list(map(list, ccw(F.ring(-hl, hl, -hw, hw)))), g + 7.0, 10.0]], tuple(c), city)


def tour_lu():
    """Tour LU (Lieu Unique, 1909, ≈ 38 m) : fût carré en pierre et brique, tambour octogonal à arcades, dôme de
    cuivre doré et lanterne ; implantée à l'angle sud-ouest de l'emprise BD TOPO de l'ancienne biscuiterie."""
    city = geo.City("nantes"); k = Kit()
    sel = bd_rings(city, 6961, 780, 60, lambda b, P: (b["kind"] & 7) == 4 and P.area > 500)
    lm = np.array(geo.ll2xy(47.21500, -1.54580, city.origin))
    best = None
    for b in sel:
        for p in b["ring"]:
            if best is None or np.linalg.norm(np.array(p) - lm) < np.linalg.norm(best - lm): best = np.array(p, float)
    c = Polygon(sum([list(b["ring"]) for b in sel], [])).centroid
    d = norm(np.array([c.x, c.y]) - best); p = best + d * 4.0
    g = city.ground(*p)
    k.lod = (0, 2)
    sq = circle(p, 4.6, 4)
    sq = [(p[0] + 4.0 * a, p[1] + 4.0 * b) for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    banded(k, sq, g, g + 22.0, [(STONE, 1.2), (BRICK, 2.4)])
    k.poly([(q[0], g + 22.0, q[1]) for q in sq], STONE, UP)
    k.lathe(v3(p[0], 0, p[1]), [(4.3, g + 22.0), (4.3, g + 23.0), (3.6, g + 23.0), (3.6, g + 30.0), (4.0, g + 30.0), (4.0, g + 31.0)], STONE, seg=8, smooth=False)
    k.lathe(v3(p[0], 0, p[1]), [(3.7, g + 31.0), (3.5, g + 33.0), (2.6, g + 35.0), (1.0, g + 36.2), (0.6, g + 36.4)], "lm_jaune#b08a3e", seg=16)
    k.cyl(v3(p[0], g + 36.4, p[1]), v3(p[0], g + 38.0, p[1]), 0.5, "lm_jaune#b08a3e", 8)
    k.lod = (0, 1)
    for i in range(8):   # arcades du tambour
        a = 2 * math.pi * (i + 0.5) / 8; q = (p[0] + math.cos(a) * 3.62, p[1] + math.sin(a) * 3.62); o = v3(math.cos(a), 0, math.sin(a))
        s = v3(-math.sin(a), 0, math.cos(a))
        P0 = v3(q[0], g + 24.0, q[1]) - s * 0.8; P1 = v3(q[0], g + 24.0, q[1]) + s * 0.8
        k.quad(P0, P1, P1 + UP * 4.0, P0 + UP * 4.0, DARK, o)
        k.tri(P0 + UP * 4.0, P1 + UP * 4.0, v3(q[0], g + 28.8, q[1]), DARK, o)
    k.lod = (0, 0)
    for (a, b) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):   # pinacles d'angle
        k.cyl(v3(p[0] + 4.0 * a, g + 22.0, p[1] + 4.0 * b), v3(p[0] + 4.0 * a, g + 26.0, p[1] + 4.0 * b), 0.45, STONE, 8)
    return finish(k, [], [[list(map(list, ccw(sq))), g, 38.0]], tuple(p), city)


def passage_pommeraye():
    """Passage Pommeraye (1843) : façade d'entrée sur rue (trois niveaux, portail en plein cintre, pilastres,
    attique) posée sur l'alignement BD TOPO le plus proche, verrière à deux pans au-dessus du passage."""
    city = geo.City("nantes"); k = Kit()
    lm = np.array(geo.ll2xy(47.21290, -1.55960, city.origin))
    best = None
    for b in bd_rings(city, lm[0], lm[1], 40, lambda b, P: True):
        r = ccw(b["ring"])
        for i in range(len(r)):
            a, bb = np.array(r[i]), np.array(r[(i + 1) % len(r)])
            if np.linalg.norm(bb - a) < 9: continue
            d = Point(lm).distance(LineString([a, bb]))
            if best is None or d < best[0]: best = (d, a, bb, b)
    _, a, bb, b = best
    t = (bb - a) / np.linalg.norm(bb - a); n = out_n(a, bb)
    m = np.array(LineString([a, bb]).interpolate(LineString([a, bb]).project(Point(lm))).coords[0])
    F = Frame2(m, t, n); g = city.ground(*m); H = 15.0
    k.lod = (0, 2)
    k.prism(F.ring(-7.0, 7.0, 0.0, 0.6), g, g + H, STONE)
    k.prism(F.ring(-7.2, 7.2, 0.0, 1.0), g + H, g + H + 0.6, STONE)
    k.prism(F.ring(-4.0, 4.0, 0.0, 0.8), g + H + 0.6, g + H + 3.0, STONE)   # attique
    k.lod = (0, 1)
    P0 = F.P(-2.2, 0.62, g); P1 = F.P(2.2, 0.62, g); o = v3(n[0], 0, n[1])
    k.quad(P0, P1, P1 + UP * 5.0, P0 + UP * 5.0, DARK, o)
    for i in range(1, 8):   # plein cintre
        a0 = math.pi * (i - 1) / 8; a1 = math.pi * i / 8
        k.tri(F.P(0, 0.62, g + 5.0), F.P(2.2 * math.cos(a0), 0.62, g + 5.0 + 2.2 * math.sin(a0)), F.P(2.2 * math.cos(a1), 0.62, g + 5.0 + 2.2 * math.sin(a1)), DARK, o)
    k.tri(F.P(0, 0.62, g + 5.0), F.P(2.2 * math.cos(7 * math.pi / 8), 0.62, g + 5.0 + 2.2 * math.sin(7 * math.pi / 8)), F.P(-2.2, 0.62, g + 5.0), DARK, o)
    for x in (-6.2, -3.2, 3.2, 6.2):   # pilastres
        k.box(F.P(x, 0.75, g + H / 2), (0.7, H, 0.3), STONE, yaw=F.yaw())
    window_grid(k, F.p(-7, 0.6), F.p(-3.2, 0.6), g + 8.5, 2, 3.2, 3.8, 1.3, 2.4, n)
    window_grid(k, F.p(3.2, 0.6), F.p(7, 0.6), g + 8.5, 2, 3.2, 3.8, 1.3, 2.4, n)
    k.lod = (0, 0)
    k.box(F.P(0, 0.7, g + 7.8), (6.0, 0.8, 0.3), GOLD, yaw=F.yaw())   # bandeau d'inscription
    # verrière du passage : deux pans vitrés sur 40 m vers l'intérieur de l'îlot
    k.lod = (0, 2)
    for s in (-1, 1):
        k.quad(F.P(-2.6 * s, -1.0, g + H - 1.0), F.P(-2.6 * s, -40.0, g + H - 1.0), F.P(0, -40.0, g + H + 1.5), F.P(0, -1.0, g + H + 1.5), GLASS, v3(0, 1, 0))
    k.lod = (0, 1)
    for d in np.arange(-3.0, -40.0, -3.0):
        k.seg_box(F.P(-2.6, d, g + H - 1.0), F.P(0, d, g + H + 1.5), 0.1, 0.12, IRON)
        k.seg_box(F.P(0, d, g + H + 1.5), F.P(2.6, d, g + H - 1.0), 0.1, 0.12, IRON)
    return finish(k, [], [[list(map(list, ccw(F.ring(-7.2, 7.2, 0, 1.0)))), g, H + 3.0]], tuple(m), city)


def elephant():
    """Grand Éléphant des Machines de l'île (2007, 12 m de haut, 21 m de long, 8 m de large) : silhouette en bois et
    acier (corps, pattes, tête, trompe, oreilles, défenses, terrasse sur le dos à garde-corps)."""
    city = geo.City("nantes"); k = Kit()
    p = np.array(geo.ll2xy(47.20675, -1.56425, city.origin)); g = city.ground(*p)
    u = np.array([1.0, 0.0]); v = np.array([0.0, 1.0]); F = Frame2(p, u, v)
    k.lod = (0, 2)
    # corps : sections circulaires balayées (ellipsoïde aplati) le long de l'axe
    prof = [(-8.5, 1.5), (-7.0, 3.0), (-4.0, 3.8), (0.0, 4.0), (4.0, 3.8), (6.5, 3.0), (7.5, 2.0)]
    seg = 14
    rings = []
    for (a, r) in prof:
        rings.append([F.P(a, r * math.cos(2 * math.pi * i / seg), g + 7.5 + r * 0.85 * math.sin(2 * math.pi * i / seg)) for i in range(seg)])
    for j in range(len(rings) - 1):
        for i in range(seg):
            A, B, C, D = rings[j][i], rings[j][(i + 1) % seg], rings[j + 1][(i + 1) % seg], rings[j + 1][i]
            k.quad(A, B, C, D, WOOD, norm((A + C) / 2 - F.P((prof[j][0] + prof[j + 1][0]) / 2, 0, g + 7.5)))
    for e, (a, _) in ((0, prof[0]), (-1, prof[-1])):
        cc = F.P(a, 0, g + 7.5)
        for i in range(seg):
            k.tri(rings[e][i], rings[e][(i + 1) % seg], cc, WOOD, norm(rings[e][i] - F.P(0, 0, g + 7.5)))
    # pattes
    for a in (-5.0, 4.5):
        for s in (-1, 1):
            k.cyl(F.P(a, s * 2.4, g), F.P(a, s * 2.4, g + 6.0), 1.0, WOOD, 10, r2=1.2)
            k.cyl(F.P(a, s * 2.4, g), F.P(a, s * 2.4, g + 0.6), 1.15, METAL, 10)
    # tête, trompe, oreilles, défenses
    hd = F.P(9.0, 0, g + 9.5)
    k.lathe(hd - UP * 2.6, [(0.1, 0.0), (2.0, 0.6), (2.6, 2.2), (2.2, 3.8), (0.1, 4.6)], WOOD, seg=12)
    path = [F.P(10.8, 0, g + 9.0), F.P(12.0, 0, g + 7.0), F.P(12.5, 0, g + 4.5), F.P(12.2, 0, g + 2.5), F.P(12.9, 0, g + 1.2)]
    for i in range(len(path) - 1):
        k.cyl(path[i], path[i + 1], 0.9 - i * 0.15, WOOD, 10, r2=0.75 - i * 0.15)
    for s in (-1, 1):
        k.quad(F.P(8.6, s * 2.4, g + 11.5), F.P(8.0, s * 5.6, g + 11.0), F.P(7.6, s * 5.4, g + 6.8), F.P(8.4, s * 2.4, g + 7.6), "lm_toile#6b5a45", v3(0.6, 0, s))
        k.cyl(F.P(10.6, s * 1.2, g + 7.2), F.P(12.6, s * 1.6, g + 6.4), 0.22, WHITE, 8, r2=0.08)
    # terrasse sur le dos
    k.prism(F.ring(-6.0, 5.0, -3.0, 3.0), g + 11.1, g + 11.4, WOOD)
    k.lod = (0, 1)
    rr = F.ring(-6.0, 5.0, -3.0, 3.0)
    for i in range(4):
        a3 = v3(rr[i][0], g + 12.4, rr[i][1]); b3 = v3(rr[(i + 1) % 4][0], g + 12.4, rr[(i + 1) % 4][1])
        k.lod = (0, 1)
        k.seg_box(a3, b3, 0.08, 0.08, METAL)
        k.lod = (0, 0)
        L = int(np.linalg.norm(b3 - a3) / 1.0)
        for j in range(L + 1):
            q = a3 + (b3 - a3) * j / max(L, 1)
            k.cyl(q - UP * 1.0, q, 0.04, METAL, 4, caps=False)
    return finish(k, [], [[list(map(list, ccw(F.ring(-9, 13.5, -3.5, 3.5)))), g, 13.0]], tuple(p), city)


SPECS = [
    # (id, ville, fichier, constructeur, portées LOD, extra)
    ("angers_chateau", "angers", "angers/chateau", chateau_angers, [0, 300, 1000, 6000], {"landmark": "Château d'Angers"}),
    ("angers_gare_saint_laud", "angers", "angers/gare_saint_laud", gare_saint_laud, [0, 220, 700, 2500], {"landmark": "Gare Saint-Laud"}),
    ("angers_hotel_de_ville", "angers", "angers/hotel_de_ville", hotel_de_ville_angers, [0, 220, 700, 2500], {"landmark": "Hôtel de ville"}),
    ("nantes_chateau_ducs", "nantes", "nantes/chateau_ducs", chateau_nantes, [0, 300, 1000, 6000], {"landmark": "Château des ducs de Bretagne"}),
    ("nantes_cathedrale", "nantes", "nantes/cathedrale", cathedrale_nantes, [0, 300, 1100, 8000], {"landmark": "Cathédrale Saint-Pierre-et-Saint-Paul"}),
    ("nantes_tour_bretagne", "nantes", "nantes/tour_bretagne", tour_bretagne, [0, 400, 1500, 12000], {"landmark": "Tour Bretagne"}),
    ("nantes_gare", "nantes", "nantes/gare", gare_nantes, [0, 250, 800, 3000], {"landmark": "Gare de Nantes"}),
    ("nantes_tour_lu", "nantes", "nantes/tour_lu", tour_lu, [0, 220, 800, 3000], {"landmark": "Tour LU"}),
    ("nantes_passage_pommeraye", "nantes", "nantes/passage_pommeraye", passage_pommeraye, [0, 150, 450, 1200], {"landmark": "Passage Pommeraye"}),
    ("nantes_elephant", "nantes", "nantes/elephant", elephant, [0, 150, 450, 1500], {"landmark": "Grand Éléphant"}),
]


def _specs():
    """Monuments P3 (Angers, Nantes) puis P4 (26 autres villes, monuments_p4.SPECS_P4)."""
    import monuments_p4
    return SPECS + monuments_p4.SPECS_P4


def main(only=None):
    """Construit les monuments P3 et les fusionne dans assets/models/landmark_models.json (entrées P1 conservées)."""
    import json, sys
    from meshkit import translate
    from build_all import local, OUT
    path = OUT / "landmark_models.json"
    doc = json.loads(path.read_text())
    models = {m["id"]: m for m in doc["models"]}
    import monuments_p4
    for mid, cname, stem, fn, ranges, extra in _specs():
        if only and mid not in only and cname not in only: continue
        k, a, meta = fn()
        city = geo.City(cname)
        if extra.get("lot") == "P4": monuments_p4.gauge_check(k, a, monuments_p4.city_of(cname), mid)
        (OUT / stem).parent.mkdir(parents=True, exist_ok=True)
        lat, lon = geo.xy2ll(a[0], a[2], city.origin)
        translate(k, a)
        tris, files = [], []
        for lod in range(3):
            p = OUT / f"{stem}_lod{lod}.glb"
            tris.append(k.export(p, lod))
            files.append(f"res://assets/models/{stem}_lod{lod}.glb")
        m = {"id": mid, "city": cname, "anchor": [round(lat, 8), round(lon, 8)], "anchor_y": round(float(a[1]), 3),
             "lods": files, "ranges_m": ranges, "triangles": tris, "lot": "P3", "budget_lod0": 150000, "budget_mobile": 60000}
        m.update(extra); m.update(local(meta, a))
        models[mid] = m
        print(mid, "triangles LOD0-2", tris, "remplace", len(m["replace"]))
    doc["models"] = list(models.values())
    path.write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    import sys
    main(sys.argv[1:] or None)
