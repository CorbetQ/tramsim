#!/usr/bin/env python3
"""Voirie en polygones fusionnés (P1), surfaces au sol d'une tuile pour tools/import/terrain_mesh.py.

Source : tronçons de route BD TOPO® (cache WFS de ign_scene.py : nature, largeur de chaussée, importance, sens,
urbain, position par rapport au sol), voies ferrées BD TOPO, réseau tram physique (data/free), nature des
plateformes (<ville>_track.json, orthophoto), surfaces et sol vert de la scène (<ville>.bin). OSM ne contient dans le
dépôt que les voies ferrées et les quais : la voirie vient de la BD TOPO.

Surfaces (identifiants MAT, priorité décroissante dans tile_parts) :
- marquages en décalques (pas dans la triangulation) : axe discontinu (3 m / 7 m) des chaussées à double sens
  >= 5,5 m, lignes de rive des grands axes, passages piétons (bandes de 0,5 m) et lignes d'arrêt aux branches des
  carrefours urbains ; posés par src/rendering/road_view.gd sur le maillage du sol ;
- plateforme tram intégrée (TRAM_GRASS / TRAM_ASPHALT / TRAM_PAVED selon la nature relevée) ;
- chaussées (union des tampons, jonctions arrondies : fermeture de 3,5 m limitée aux carrefours) ;
- îlots et terre-pleins surélevés (ISLAND, ISLAND_GRASS) : terre-pleins étroits entre chaussées, centres de
  giratoires, enclaves de voirie ;
- trottoirs surélevés en anneau autour des îlots bâtis (SIDEWALK), arrêtés aux façades ;
- voies ferrées (BALLAST, RAIL), chemins (PATH), eau (WATERBED, lit sous le plan d'eau), sport, cimetières,
  bois, pelouses BD TOPO ; le reste est GROUND (sol nu, où le shader applique le masque lissé des pelouses
  d'orthophoto). lawn_polygon (contours vectorisés) reste disponible mais n'est plus maillé.
Les tronçons en pont ou en tunnel sont exclus (tabliers : city_scene._deck).
"""
import json, math, os, struct, sys
from collections import defaultdict

import numpy as np
import shapely
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import substring

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import terrain as T          # noqa: E402

TILE_M = 400.0
MAT = {"GROUND": 0, "ASPHALT": 1, "SIDEWALK": 2, "GRASS": 3, "FOREST": 4, "SPORT": 5, "CEMETERY": 6,
       "WATERBED": 7, "TRAM_GRASS": 8, "TRAM_ASPHALT": 9, "TRAM_PAVED": 10, "PAINT": 11, "ISLAND": 12,
       "ISLAND_GRASS": 13, "PATH": 14, "BALLAST": 15, "RAIL": 16, "LAWN": 17, "ASPHALT_MAJOR": 18}
RAISED = {MAT["SIDEWALK"], MAT["ISLAND"], MAT["ISLAND_GRASS"]}
PAVED = {MAT[k] for k in ("ASPHALT", "ASPHALT_MAJOR", "SIDEWALK", "PAINT", "TRAM_GRASS", "TRAM_ASPHALT",
                          "TRAM_PAVED", "ISLAND", "ISLAND_GRASS", "RAIL", "BALLAST")}
CORRIDOR_M = 220.0
FILLET = 3.5            # rayon des bordures de carrefour
QS = 2                  # segments par quart de cercle
BED = {1: MAT["TRAM_GRASS"], 2: MAT["TRAM_ASPHALT"], 3: MAT["TRAM_PAVED"]}
PATHS = ("Sentier", "Chemin", "Route empierrée")
SKIP = ("Escalier", "Bac ou liaison maritime", "Bac auto", "Bac piéton")


def read_scene(path):
    """Tuiles TSC1 à TSC4 de <ville>.bin : bâtiments (polygones), surfaces (classe, polygone), cellules vertes."""
    from ign_scene import read_tiles
    tiles, magic = read_tiles(open(path, "rb").read())
    v2 = magic != b"TSC1"; v3 = magic in (b"TSC3", b"TSC4")
    out = {}
    for (tx, tz), buf in tiles.items():
        o = 0
        blds, polys, runs = [], [], []
        nb = struct.unpack_from("<H", buf, o)[0]; o += 2
        for _ in range(nb):
            k = buf[o]; o += 5 if v2 else 4
            ring = np.frombuffer(buf, "<i2", 2 * k, o).reshape(-1, 2) / 10.0; o += 4 * k
            nt = buf[o]; o += 1 + nt * 3
            if k >= 3:
                blds.append(Polygon(ring + (tx * TILE_M, tz * TILE_M)))
        np_ = struct.unpack_from("<H", buf, o)[0]; o += 2
        for _ in range(np_):
            cls, nv, ntr = struct.unpack_from("<BHH", buf, o); o += 5
            v = np.frombuffer(buf, "<i2", 2 * nv, o).reshape(-1, 2) / 10.0 + (tx * TILE_M, tz * TILE_M); o += 4 * nv
            idx = np.frombuffer(buf, "<u2", 3 * ntr, o).reshape(-1, 3); o += 6 * ntr
            tris = shapely.polygons(v[idx])
            polys.append((cls, shapely.union_all(shapely.make_valid(tris))))
        nl = struct.unpack_from("<H", buf, o)[0]; o += 2
        for _ in range(nl):
            cnt = struct.unpack_from("<H", buf, o + 2)[0]; o += 4 + 4 * cnt
        if v2:
            npt = struct.unpack_from("<H", buf, o)[0]; o += 2 + 7 * npt
            nlb = struct.unpack_from("<H", buf, o)[0]; o += 2
            for _ in range(nlb):
                o += 6 + buf[o + 5]
        if v3:
            nr = struct.unpack_from("<H", buf, o)[0]; o += 2 + 2 * nr
            ntr = struct.unpack_from("<H", buf, o)[0]; o += 2 + 6 * ntr
            ng = struct.unpack_from("<H", buf, o)[0]; o += 2
            runs = [tuple(buf[o + 3 * j:o + 3 * j + 3]) for j in range(ng)]
        out[(tx, tz)] = {"b": blds, "p": polys, "gr": runs}
    return out


def lawn_polygon(t, runs):
    """Cellules vertes de 4 m (orthophoto) -> contour vectorisé lissé (pas d'escalier)."""
    if not runs:
        return None
    ox, oz = t[0] * TILE_M, t[1] * TILE_M
    cells = []
    for row, s0, n in runs:
        z0 = oz + row * 4.0; x0 = ox + s0 * 4.0; x1 = x0 + n * 4.0
        if x0 <= ox + 0.1: x0 -= 4.0
        if x1 >= ox + TILE_M - 0.1: x1 += 4.0
        z1 = z0 + 4.0
        if z0 <= oz + 0.1: z0 -= 4.0
        if z1 >= oz + TILE_M - 0.1: z1 += 4.0
        cells.append(box(x0, z0, x1, z1))
    g = shapely.union_all(cells)
    g = g.buffer(2.5, quad_segs=2).buffer(-4.5, quad_segs=2).buffer(2.0, quad_segs=2)   # fermeture + ouverture
    g = _union([p for p in T.polys_of(g.simplify(1.5)) if p.area > 120.0])
    return g.intersection(box(ox, oz, ox + TILE_M, oz + TILE_M))


def _union(gs):
    gs = [g for g in gs if g is not None and not g.is_empty]
    if not gs:
        return Polygon()
    try:
        return shapely.union_all(gs)
    except shapely.errors.GEOSException:   # géométrie presque dégénérée : réparation, puis tampon de 1 mm
        gs = [shapely.make_valid(g).buffer(0) for g in gs]
        try:
            return shapely.union_all(gs)
        except shapely.errors.GEOSException:
            return shapely.union_all([g.buffer(0.001, quad_segs=1) for g in gs])


def _safe(op, a, b):
    try:
        return op(a, b)
    except shapely.errors.GEOSException:
        return op(shapely.make_valid(a).buffer(0), shapely.make_valid(b).buffer(0))


class CityRoads:
    def __init__(self, city, frame, cache, llb, tram_axes):
        self.frame = frame
        # corridor du décor (comme ign_scene.py) : voirie dessinée jusqu'à 25 m au-delà
        lines = []
        for _, d in T.city_nets(city):
            nf = T.Frame(*d["origin"])
            for e in d["edges"]:
                pts = e.get("pts", [])
                if len(pts) >= 2:
                    a = np.array(pts, dtype=np.float64)
                    lat, lon = nf.inv(a[:, 0], a[:, 1])
                    x, z = frame.fwd(lat, lon)
                    lines.append(LineString(np.stack([x, z], 1)))
        self.zone = shapely.union_all([l.buffer(CORRIDOR_M + 25.0, quad_segs=4) for l in lines]).simplify(5.0) if lines else None
        if self.zone is not None:
            shapely.prepare(self.zone)
        self.roads = []      # (ligne, mat, largeur, trottoir, double sens, urbain, majeur)
        for ft in T.cached_features("troncon_de_route", cache, llb):
            pr = ft["properties"]
            if not ft.get("geometry") or T.pos_sol(pr) != 0 or pr.get("fictif"):
                continue
            nat = pr.get("nature") or ""
            if nat in SKIP:
                continue
            w = pr.get("largeur_de_chaussee")
            imp = str(pr.get("importance") or "6")
            urb = bool(pr.get("urbain"))
            if nat in PATHS:
                mat, w, ws = MAT["PATH"], max(float(w or (3.5 if nat == "Route empierrée" else 2.0)), 1.5), 0.0
            elif nat in ("Piste cyclable",):
                mat, w, ws = MAT["ASPHALT"], max(float(w or 2.0), 1.6), 0.0
            else:
                major = nat in ("Type autoroutier", "Route à 2 chaussées") or imp in ("1", "2")
                dw = 9.0 if major else (6.0 if nat in ("Route à 1 chaussée", "Rond-point", "Bretelle") else 3.5)
                w = max(float(w or dw), 3.0)
                mat = MAT["ASPHALT_MAJOR"] if major else MAT["ASPHALT"]
                ws = (3.0 if imp in ("1", "2", "3") else 2.2) if urb and nat != "Type autoroutier" and nat != "Bretelle" else 0.0
            two_way = (pr.get("sens_de_circulation") or "Double sens") == "Double sens"
            for l in T.lines3d(ft["geometry"], frame):
                ls = LineString(l[:, :2]).simplify(0.3)
                if ls.length < 0.5:
                    continue
                if self.zone is not None and not self.zone.intersects(ls):
                    continue
                self.roads.append((ls, mat, w, ws, two_way, urb, mat == MAT["ASPHALT_MAJOR"]))
        self.tree = shapely.STRtree([r[0] for r in self.roads]) if self.roads else None
        # carrefours : extrémités communes à au moins 3 branches
        ends = defaultdict(list)
        for i, r in enumerate(self.roads):
            if r[1] == MAT["PATH"]:
                continue
            c = r[0].coords
            for e, p in ((0, c[0]), (1, c[-1])):
                ends[(round(p[0] * 2), round(p[1] * 2))].append((i, e))
        self.nodes = []      # (point, rayon du disque de jonction, branches)
        for k, arms in ends.items():
            if len(arms) >= 3:
                p = self.roads[arms[0][0]][0].coords[0 if arms[0][1] == 0 else -1]
                wmax = max(self.roads[i][2] for i, _ in arms)
                self.nodes.append((Point(p), wmax * 0.5 + 4.0, arms))
        self.ntree = shapely.STRtree([n[0] for n in self.nodes]) if self.nodes else None
        # voies ferrées au sol (hors tram)
        self.rails = []
        for ft in T.cached_features("troncon_de_voie_ferree", cache, llb):
            pr = ft["properties"]
            if not ft.get("geometry") or T.pos_sol(pr) != 0 or pr.get("nature") == "Tramway":
                continue
            for l in T.lines3d(ft["geometry"], frame):
                ls = LineString(l[:, :2])
                if ls.length > 1 and (self.zone is None or self.zone.intersects(ls)):
                    self.rails.append(ls)
        self.rtree = shapely.STRtree(self.rails) if self.rails else None
        # plateforme tram : axes au sol (data/free) découpés par nature de plateforme
        self.tram = []       # (segment, matériau)
        nat = {}
        tp = os.path.join(T.ROOT, "data/scenes", city + "_track.json")
        cell = 8.0
        if os.path.exists(tp):
            tj = json.load(open(tp)); cell = float(tj.get("cell_m", 8.0))
            nat = {(c[0], c[1]): c[2] for c in tj.get("cells", [])}
        for ax in tram_axes:
            run, cur = [ax[0][:2]], None
            for a, b in zip(ax[:-1], ax[1:]):
                m = (a[:2] + b[:2]) * 0.5
                k = (int(math.floor(m[0] / cell)), int(math.floor(m[1] / cell)))
                v = nat.get(k, 0)
                if not v:
                    for dk in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        v = nat.get((k[0] + dk[0], k[1] + dk[1]), 0)
                        if v:
                            break
                mat = BED.get(v, MAT["TRAM_PAVED"])
                if cur is not None and mat != cur:
                    self.tram.append((LineString(run).simplify(0.05), cur))
                    run = [a[:2]]
                cur = mat
                run.append(b[:2])
            if cur is not None and len(run) >= 2:
                self.tram.append((LineString(run).simplify(0.05), cur))
        self.ttree = shapely.STRtree([s for s, _ in self.tram]) if self.tram else None

    # ------------------------------------------------------------------------------------------- marquages
    def _markings(self, idx, cut, tb):
        """Décalques linéaires : (type 0 axe discontinu | 1 rive continue, coordonnées, phase des tirets en m)."""
        out = []
        for i in idx:
            ls, mat, w, ws, two, urb, major = self.roads[i]
            if mat == MAT["PATH"] or w < 5.0:
                continue
            lines = []
            if two and w >= 5.5:
                lines.append((0, ls))
            if major and w >= 7.0:
                for side in (-1, 1):
                    try:
                        oc = ls.offset_curve(side * (w * 0.5 - 0.35), quad_segs=2)
                    except Exception:
                        continue
                    if oc.geom_type == "LineString" and not oc.is_empty:
                        lines.append((1, oc))
            for kind, l in lines:
                g = l.intersection(tb)
                if not cut.is_empty:
                    g = g.difference(cut)
                for piece in shapely.get_parts(shapely.line_merge(g) if g.geom_type == "MultiLineString" else g):
                    if piece.geom_type != "LineString" or piece.length < 1.0:
                        continue
                    piece = piece.simplify(0.1)
                    phase = l.project(Point(piece.coords[0])) if kind == 0 else 0.0
                    out.append((kind, np.array(piece.coords), phase))
        return out

    def _crossings(self, nodes, tb):
        """Décalques de carrefour : (0 passage piéton | 1 ligne d'arrêt, centre x, z, direction (vers l'extérieur du
        carrefour), largeur transversale, longueur) ; passages piétons sur les branches des carrefours urbains."""
        out = []
        for p, r, arms in nodes:
            for i, e in arms:
                ls, mat, w, ws, two, urb, major = self.roads[i]
                if not urb or w < 4.5 or mat == MAT["PATH"]:
                    continue
                L = ls.length
                s0 = r + 0.5
                if L < s0 + 9.0:
                    continue
                s = s0 if e == 0 else L - s0
                q = ls.interpolate(s)
                q2 = ls.interpolate(min(s + 1.0, L) if e == 0 else max(s - 1.0, 0.0))
                t = np.array([q2.x - q.x, q2.y - q.y]); n_ = np.linalg.norm(t)
                if n_ < 1e-6:
                    continue
                t /= n_
                c0 = np.array([q.x, q.y])
                ang = math.atan2(t[1], t[0])
                cw = c0 + t * 1.5
                if tb.contains(Point(cw)):
                    out.append((0, cw[0], cw[1], ang, w - 0.8, 3.0))
                    if two:      # demi-chaussée des véhicules qui arrivent au carrefour (à droite)
                        right = np.array([t[1], -t[0]])
                        cs = c0 + t * 4.15 + right * (w * 0.25)
                        out.append((1, cs[0], cs[1], ang, w * 0.5 - 0.4, 0.3))
        return out

    # ------------------------------------------------------------------------------------------- tuile
    def tile_parts(self, t, scene, in_scene):
        ox, oz = t[0] * TILE_M, t[1] * TILE_M
        tb = box(ox, oz, ox + TILE_M, oz + TILE_M)
        tbm = tb.buffer(45.0, join_style="mitre")
        zone = tbm.intersection(self.zone) if (self.zone is not None and in_scene) else (tbm if in_scene else Polygon())
        P = defaultdict(list)
        blds = _union(scene["b"]) if scene else Polygon()
        nodes = []
        discs = Polygon()
        decals = {"lines": [], "rects": []}
        if not zone.is_empty and self.tree is not None:
            idx = [int(i) for i in self.tree.query(tbm)]
            road = [i for i in idx if self.roads[i][1] != MAT["PATH"]]
            if self.ntree is not None:
                nodes = [self.nodes[int(j)] for j in self.ntree.query(tbm)]
            discs = _union([p.buffer(r + 2.0, quad_segs=QS) for p, r, _ in nodes])
            major = _union([self.roads[i][0].buffer(self.roads[i][2] * 0.5, quad_segs=QS, join_style="mitre", mitre_limit=2.0) for i in road if self.roads[i][6]])
            minor = _union([self.roads[i][0].buffer(self.roads[i][2] * 0.5, quad_segs=QS, join_style="mitre", mitre_limit=2.0) for i in road if not self.roads[i][6]])
            asph = _union([major, minor])
            if not asph.is_empty and not discs.is_empty:   # bordures arrondies aux carrefours
                fil = asph.buffer(FILLET, quad_segs=QS).buffer(-FILLET, quad_segs=QS).intersection(discs)
                asph = _union([asph, fil])
            side = _union([self.roads[i][0].buffer(self.roads[i][2] * 0.5 + self.roads[i][3], quad_segs=QS, join_style="mitre", mitre_limit=2.0)
                           for i in road if self.roads[i][3] > 0])
            if not side.is_empty and not discs.is_empty:
                fil = side.buffer(FILLET + 1.5, quad_segs=QS).buffer(-(FILLET + 1.5), quad_segs=QS).intersection(discs.buffer(3.0))
                side = _union([side, fil])
            tram = defaultdict(list)
            if self.ttree is not None:
                for j in self.ttree.query(tbm):
                    s, m = self.tram[int(j)]
                    tram[m].append(s.buffer(2.35, cap_style="flat", join_style="mitre", mitre_limit=2.0))
            tram = {m: _union(v) for m, v in tram.items()}
            tram_all = _union(list(tram.values()))
            # terre-pleins étroits et enclaves : îlots surélevés
            isl = []
            if not asph.is_empty:
                closed = asph.buffer(4.0, quad_segs=QS).buffer(-4.0, quad_segs=QS)
                gap = closed.difference(asph).difference(tram_all)
                ab = asph.boundary
                for g in T.polys_of(gap):
                    if g.area < 4.0:
                        continue
                    touch = g.boundary.intersection(ab.buffer(0.05)).length / max(g.boundary.length, 1e-6)
                    if touch > 0.75:
                        isl.append(g)
            paved = _union([asph, side, tram_all])
            for g in T.polys_of(paved):
                for h in g.interiors:
                    hp = Polygon(h)
                    if 4.0 < hp.area < 2500.0 and hp.intersection(blds).area < 0.2 * hp.area:
                        isl.append(hp)
            isl = _union(isl).intersection(zone)
            big = _union([g for g in T.polys_of(isl) if g.area > 80.0])
            if in_scene:
                decals["lines"] = self._markings(road, _union([discs, tram_all]), tb.intersection(zone))
                decals["rects"] = self._crossings(nodes, tb)
            for m, g in tram.items():
                P[[k for k, v in MAT.items() if v == m][0]].append(g)
            P["ASPHALT_MAJOR"].append(major)
            P["ASPHALT"].append(asph)
            P["ISLAND_GRASS"].append(big)
            P["ISLAND"].append(isl)
            P["SIDEWALK"].append(side)            # les façades se posent sur le trottoir
            P["PATH"].append(_union([self.roads[i][0].buffer(self.roads[i][2] * 0.5, quad_segs=2, join_style="mitre", mitre_limit=2.0)
                                     for i in idx if self.roads[i][1] == MAT["PATH"]]))
            if self.rtree is not None:
                rl = [self.rails[int(j)] for j in self.rtree.query(tbm)]
                rails = []
                for l in rl:
                    for side_ in (-0.72, 0.72):
                        try:
                            oc = l.offset_curve(side_, quad_segs=2)
                            rails.append(oc.buffer(0.05, cap_style="flat", quad_segs=1))
                        except Exception:
                            pass
                P["RAIL"].append(_union(rails))
                P["BALLAST"].append(_union([l.buffer(1.9, cap_style="flat", quad_segs=2) for l in rl]))
            for k in list(P):
                P[k] = [_safe(shapely.intersection, g, zone) for g in P[k]]
        if scene:
            names = {1: "WATERBED", 2: "FOREST", 3: "GRASS", 4: "SPORT", 5: "CEMETERY"}
            for cls, g in scene["p"]:
                P[names.get(cls, "GRASS")].append(g)
            # pelouses d'orthophoto : masque de végétation lissé du shader du sol (veg_mask), pas de géométrie
        order = ["RAIL", "TRAM_PAVED", "TRAM_ASPHALT", "TRAM_GRASS", "ASPHALT_MAJOR", "ASPHALT", "ISLAND_GRASS",
                 "ISLAND", "SIDEWALK", "BALLAST", "PATH", "WATERBED", "SPORT", "CEMETERY", "FOREST", "GRASS", "LAWN"]
        parts, claimed = [], Polygon()
        for name in order:
            g = _union(P.get(name, []))
            if g.is_empty:
                continue
            g = _safe(shapely.intersection, g, tb)
            if not claimed.is_empty:
                g = _safe(shapely.difference, g, claimed)
            g = _union([p for p in T.polys_of(g) if p.area > 0.02])
            if g.is_empty:
                continue
            parts.append((MAT[name], g))
            claimed = _union([claimed, g])
        return parts, decals
