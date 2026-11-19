#!/usr/bin/env python3
"""Sol continu d'une ville : relief et voirie dans un seul maillage par tuile (data/scenes/<ville>_ground.bin, « TGR2 »).

Chaque tuile de 400 m est une triangulation de Delaunay contrainte (Triangle, J. R. Shewchuk) dont les arêtes
contraintes sont les limites des surfaces de tools/import/road_mesh.py (chaussées, carrefours, trottoirs, îlots,
plateforme tram, marquages, eau, végétation…) et dont les points libres échantillonnent le MNT (treillis global de
40 m, 20 puis 10 m là où le relief se courbe). La voirie est donc drapée exactement sur le relief : un seul maillage, pas de
couche superposée. Les sommets des bords de tuile sont communs aux deux tuiles voisines (mêmes intersections,
quantification au 1/64 m dans le repère de la ville, même fonction d'altitude) : raccords sans déchirure.

Altitude (m, relative à alt0 de <ville>_terrain.json) : MNT IGN RGE ALTI® ; nivelé sous les voies au sol du
réseau physique (data/free/<ville>.json, rail - 0,13 m jusqu'à 6 m de l'axe puis talus jusqu'à 16 m), lit des
rivières sous le plan d'eau BD TOPO avec berge en pente. Les tabliers BD TOPO (ponts routiers et ferroviaires)
et les niveaux d'eau sont conservés tels que lus par city_scene.gd (_decks, _water_lv).

Couronne lointaine : grille de 100 m sur l'emprise des tuiles élargie de 8 km (MNT RGE ALTI ~100 m), pour
l'horizon (src/rendering/terrain_view.gd).

Format (little endian) :
  "TGR2", u32 version (2), f32 tile_m, u32 n, u32 far_off, u32 far_csize, u32 far_raw, u32 meta_off, u32 meta_csize,
  u32 meta_raw, puis n x [i32 tx, i32 tz, u32 off, u32 csize, u32 raw, f32 ymin].
  Tuile (Brotli) : f32 base, u32 nv, u32 nt ; i16[nv] x, i16[nv] z (1/64 m, repère tuile, codage delta) ;
  i32[nv] y (cm au-dessus de base, delta ; évite les débordements sur les reliefs) ; i16[nt] a (delta), i16[nt] b - a, i16[nt] c - b (a < b < c :
  orientation recalculée à la lecture) ; u8[nt] matériau (bits 0-4, road_mesh.MAT) | bordure (bit 5 + k : arête (k, k+1 mod 3)
  bordée d'une surface non surélevée).
  Méta (Brotli), par tuile dans l'ordre de la table : u8 nb niveaux d'eau [i16 x, i16 z, i16 niveau] (dm, repère
  tuile) ; u16 nb tabliers [u8 type (0 route, 1 fer), u8 largeur*5, u8 n, n x (i16 x, i16 z, i16 y)].
  Couronne (Brotli) : f32 x0, f32 z0, f32 pas, u16 nx, u16 nz, i16[nz][nx] altitude (dm).

Usage : terrain_mesh.py VILLE [VILLE...]   (après ign_scene.py et terrain.py ; caches TERRAIN_CACHE)
"""
import json, math, os, struct, sys, time

import brotli
from collections import defaultdict

import numpy as np
import shapely
from shapely.geometry import LineString, Polygon, box
from scipy.spatial import cKDTree
import triangle as tr

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import terrain as T                     # noqa: E402
import road_mesh as RM                  # noqa: E402

ROOT = T.ROOT
TILE_M = T.TILE_M
Q = 64.0                                # quantification des sommets : 1/64 m
CURV = 0.25                             # m, écart au plan qui densifie le treillis de relief (40 -> 20 -> 10 m)
SIMPLIFY = 0.3                          # tolérance de simplification des limites de surfaces (m)
FAR_STEP = 100.0
FAR_MARGIN = 8000.0
FAR_BLOCK = 25600.0                     # m par requête WMS de la couronne (264 px ~ 97 m)


def _fill_nodata(a):
    """Comme terrain.fill_nodata, mais une dalle surtout en mer (Brest, Le Havre, Nice) n'interrompt pas l'import :
    les mesures absentes y valent le niveau de la mer (0 m), sinon la mesure valide la plus proche.
    Les valeurs sous -20 m sont des anomalies littorales pour ce MNT de surface de France métropolitaine."""
    a = np.array(a, dtype=np.float64, copy=True)
    missing = ~np.isfinite(a) | (a < -20) | (a > 9000)
    if missing.mean() > 0.2:
        a[missing] = 0.0
        return a
    a[missing] = np.nan
    return _strict_fill(a)


_strict_fill = T.fill_nodata
T.fill_nodata = _fill_nodata


class CoarseDem(T.Dem):
    """MNT à ~100 m pour la couronne lointaine (requêtes de 25,6 km)."""

    def __init__(self, frame, cache, tag):
        super().__init__(frame, cache, tag + "_far")

    def _block(self, bx, bz):
        save = T.BLOCK
        T.BLOCK = FAR_BLOCK
        try:
            return super()._block(bx, bz)
        finally:
            T.BLOCK = save

    def __call__(self, x, z):
        save = T.BLOCK
        T.BLOCK = FAR_BLOCK
        try:
            return super().__call__(x, z)
        finally:
            T.BLOCK = save


class Height:
    """Altitude du sol (relative à alt0) en tout point du repère de la ville."""

    def __init__(self, dem, alt0, tracks, water):
        self.dem, self.alt0 = dem, alt0
        self.tp, self.ty = tracks           # échantillons des voies au sol (x, z), altitude du rail
        self.tree = cKDTree(self.tp) if len(self.tp) else None
        self.water = [(p, lv - alt0) for p, lv in water if np.isfinite(lv) and lv >= -20]
        self.wtree = shapely.STRtree([p for p, _ in self.water]) if self.water else None

    def __call__(self, x, z):
        x = np.asarray(x, dtype=np.float64); z = np.asarray(z, dtype=np.float64)
        h = self.dem(x, z) - self.alt0
        if self.wtree is not None and len(x):
            pts = shapely.points(x, z)
            for i in np.unique(self.wtree.query(pts, predicate="within")[1]):
                p, lv = self.water[int(i)]
                inside = shapely.contains_xy(p, x, z)
                if not inside.any():
                    continue
                d = shapely.distance(p.exterior, pts[inside])
                bed = lv - 0.4 - 1.0 * np.clip(d / 6.0, 0.0, 1.0)      # berge en pente sous le plan d'eau
                h[inside] = np.minimum(h[inside], bed)
        if self.tree is not None and len(x):
            d, i = self.tree.query(np.stack([x, z], 1), distance_upper_bound=16.0)
            ok = np.isfinite(d)
            if ok.any():
                w = np.clip((16.0 - d[ok]) / 10.0, 0.0, 1.0)
                w = w * w * (3 - 2 * w)                                  # talus adouci
                h[ok] = h[ok] * (1 - w) + (self.ty[i[ok]] - 0.13) * w
        return h


def free_tracks(city, frame):
    """Voies physiques au sol (data/free) : échantillons tous les 2 m hors ponts et tunnels, repère de la ville."""
    path = os.path.join(ROOT, "data/free", city + ".json")
    if not os.path.exists(path):
        return np.zeros((0, 2)), np.zeros(0), [], []
    d = json.load(open(path))
    nf = T.Frame(*d["origin"])
    P, Y, axes, tunnels = [], [], [], []
    for e in d["edges"]:
        pts, ys = e.get("pts", []), e.get("y", [])
        if len(pts) < 2 or len(ys) != len(pts):
            continue
        a = np.array(pts, dtype=np.float64)
        lat, lon = nf.inv(a[:, 0], a[:, 1])
        x, z = frame.fwd(lat, lon)
        xz = np.stack([x, z], 1)
        seg = np.linalg.norm(np.diff(xz, axis=0), axis=1)
        s = np.concatenate([[0], np.cumsum(seg)])
        L = float(e.get("length", s[-1])) or s[-1]
        k = s[-1] / L if L > 0 else 1.0
        n = max(2, int(math.ceil(s[-1] / 2.0)) + 1)
        ss = np.linspace(0, s[-1], n)
        px = np.interp(ss, s, xz[:, 0]); pz = np.interp(ss, s, xz[:, 1]); py = np.interp(ss, s, np.array(ys, dtype=np.float64))
        off = ss / k if k > 0 else ss
        bad = np.zeros(n, bool); tun = np.zeros(n, bool)
        for a0, a1, *_ in e.get("bridge", []):
            bad |= (off >= a0 - 1) & (off <= a1 + 1)
        for a0, a1, *_ in e.get("tunnel", []):
            tun |= (off >= a0) & (off <= a1)
        bad |= tun
        P.append(np.stack([px[~bad], pz[~bad]], 1)); Y.append(py[~bad])
        # axes au sol par morceaux (plateforme intégrée à la voirie), axes en tunnel (découpe fine des portails)
        for mask, out in ((~bad, axes), (tun, tunnels)):
            i = 0
            while i < n:
                if mask[i]:
                    j = i
                    while j + 1 < n and mask[j + 1]:
                        j += 1
                    if j > i:
                        out.append(np.stack([px[i:j + 1], pz[i:j + 1], py[i:j + 1]], 1))
                    i = j + 1
                else:
                    i += 1
    if not P:
        return np.zeros((0, 2)), np.zeros(0), [], []
    return np.concatenate(P), np.concatenate(Y), axes, tunnels


# ------------------------------------------------------------------------------------------------ triangulation
def qz(v):
    return np.round(np.asarray(v, dtype=np.float64) * Q) / Q


EDGE = 10.0                             # m, points canoniques des bords de tuile


def _edge_chain(V, S, ox, oz):
    """Ajoute les points canoniques des bords (pas EDGE) et remplace les segments de bord par les chaînes triées."""
    on = [np.abs(V[:, 0] - ox) < 0.5 / Q, np.abs(V[:, 0] - ox - TILE_M) < 0.5 / Q,
          np.abs(V[:, 1] - oz) < 0.5 / Q, np.abs(V[:, 1] - oz - TILE_M) < 0.5 / Q]
    border = on[0] | on[1] | on[2] | on[3]
    keep = ~(border[S[:, 0]] & border[S[:, 1]] & np.array([any(o[a] and o[b] for o in on) for a, b in S]) if len(S) else np.zeros(0, bool))
    S = S[keep] if len(S) else S
    ts = np.arange(0, TILE_M + 0.01, EDGE)
    add = np.concatenate([np.stack([np.full_like(ts, ox), oz + ts], 1), np.stack([np.full_like(ts, ox + TILE_M), oz + ts], 1),
                          np.stack([ox + ts, np.full_like(ts, oz)], 1), np.stack([ox + ts, np.full_like(ts, oz + TILE_M)], 1)])
    allv = np.concatenate([V, qz(add)])
    key = np.round(allv * Q).astype(np.int64)
    _, first, inv = np.unique(key[:, 0] * 10_000_000 + key[:, 1], return_index=True, return_inverse=True)
    order = np.sort(first)
    remap = np.empty(len(first), np.int64); remap[np.argsort(first)] = np.arange(len(first))
    newid = remap[inv]
    V2 = allv[order]
    S = newid[S] if len(S) else S
    segs = [S] if len(S) else []
    for axis, val in ((0, ox), (0, ox + TILE_M), (1, oz), (1, oz + TILE_M)):
        idx = np.nonzero(np.abs(V2[:, axis] - val) < 0.5 / Q)[0]
        idx = idx[np.argsort(V2[idx, 1 - axis])]
        segs.append(np.stack([idx[:-1], idx[1:]], 1))
    S = np.concatenate(segs)
    S = S[S[:, 0] != S[:, 1]]
    return V2, np.unique(np.sort(S, 1), axis=0)


def tile_mesh(t, parts, height, curv_dem, extra_pts=(), fine=True, simplify=SIMPLIFY):
    """Triangulation contrainte d'une tuile. parts : [(matériau, géométrie surfacique)] en priorité décroissante,
    déjà résolues (disjointes). Retourne (V (n,3) repère tuile, T (m,3), M (m,) u8)."""
    ox, oz = t[0] * TILE_M, t[1] * TILE_M
    tb = box(ox, oz, ox + TILE_M, oz + TILE_M)
    bnds = [tb.boundary] + [g.boundary for _, g in parts if not g.is_empty]
    try:
        lines = shapely.union_all(bnds)
    except shapely.errors.GEOSException:
        lines = shapely.union_all([shapely.set_precision(b, 1.0 / Q) for b in bnds], grid_size=1.0 / Q)
    lines = shapely.segmentize(shapely.simplify(lines, simplify), 25.0)
    coords, segs = [], []
    for ls in shapely.get_parts(lines):
        c = shapely.get_coordinates(ls)
        if len(c) < 2:
            continue
        coords.append(c)
    allc = qz(np.concatenate(coords)) if coords else np.zeros((0, 2))
    # sommets uniques (quantifiés) et segments
    key = np.round(allc * Q).astype(np.int64)
    uniq, inv = np.unique(key[:, 0] * 10_000_000 + key[:, 1], return_inverse=True)
    V = np.zeros((len(uniq), 2))
    V[inv] = allc
    k = 0
    S = []
    for c in coords:
        idx = inv[k:k + len(c)]; k += len(c)
        a, b = idx[:-1], idx[1:]
        m = a != b
        S.append(np.stack([a[m], b[m]], 1))
    S = np.concatenate(S) if S else np.zeros((0, 2), int)
    S = np.unique(np.sort(S, 1), axis=0)
    # bords de tuile : points canoniques tous les EDGE m (communs aux deux tuiles), arêtes de bord rechaînées
    V, S = _edge_chain(V, S, ox, oz)
    # treillis de relief (positions globales : mêmes points de part et d'autre d'un bord de tuile) : 40 m, puis
    # 20 m et 10 m là où le relief se courbe (écart au plan des voisins > CURV)
    P = []
    for step, base in ((40.0, True), (20.0, False), (10.0, False))[:3 if fine else 2]:
        xs = np.arange(ox + step, ox + TILE_M - 1.0, step)
        gx, gz = np.meshgrid(xs, np.arange(oz + step, oz + TILE_M - 1.0, step))
        gx, gz = gx.ravel(), gz.ravel()
        if not base:   # points du pas plus grossier déjà pris
            odd = (np.round(gx / step).astype(int) % 2 == 1) | (np.round(gz / step).astype(int) % 2 == 1)
            gx, gz = gx[odd], gz[odd]
            h0 = curv_dem(gx, gz)
            lap = np.abs(h0 - 0.25 * (curv_dem(gx + step, gz) + curv_dem(gx - step, gz) + curv_dem(gx, gz + step) + curv_dem(gx, gz - step)))
            sel = lap > (CURV if fine else 2.4 * CURV)
            gx, gz = gx[sel], gz[sel]
        P.append(np.stack([gx, gz], 1))
    P = np.concatenate(P)
    if len(extra_pts):
        E = np.asarray(extra_pts)
        E = E[(E[:, 0] > ox + 0.5) & (E[:, 0] < ox + TILE_M - 0.5) & (E[:, 1] > oz + 0.5) & (E[:, 1] < oz + TILE_M - 0.5)]
        P = np.concatenate([P, E])
    if len(P):
        free = np.ones(len(P), bool)
        hard = [g for m, g in parts if m in RM.PAVED and not g.is_empty]
        if hard:
            free &= ~shapely.contains_xy(shapely.union_all(hard), P[:, 0], P[:, 1])
        free &= ~shapely.dwithin(lines, shapely.points(P[:, 0], P[:, 1]), 1.0)
        P = qz(P[free])
    verts = np.concatenate([V, P]) if len(P) else V
    res = tr.triangulate({"vertices": verts, "segments": S}, "pzQn")
    Vt, Tt, Nb = res["vertices"], res["triangles"], res["neighbors"]
    Vt = qz(Vt)
    # matériau par triangle (centroïde)
    c = Vt[Tt].mean(1)
    M = np.full(len(Tt), RM.MAT["GROUND"], np.uint8)
    done = np.zeros(len(Tt), bool)
    for m, g in parts:
        if g.is_empty or done.all():
            continue
        sel = ~done
        inside = shapely.contains_xy(g, c[sel, 0], c[sel, 1])
        ii = np.nonzero(sel)[0][inside]
        M[ii] = m; done[ii] = True
    # orientation (sens trigonométrique en x, z) et bordures
    a, b, d = Vt[Tt[:, 0]], Vt[Tt[:, 1]], Vt[Tt[:, 2]]
    cross = (b[:, 0] - a[:, 0]) * (d[:, 1] - a[:, 1]) - (b[:, 1] - a[:, 1]) * (d[:, 0] - a[:, 0])
    keep = np.abs(cross) > 1e-6
    raised = np.isin(M, list(RM.RAISED))
    curb = np.zeros(len(Tt), np.uint8)
    for i in range(3):     # Triangle : voisin i opposé au sommet i -> arête (i+1, i+2)
        nb = Nb[:, i]
        other = np.where(nb >= 0, raised[np.maximum(nb, 0)], True)
        flag = raised & ~other
        # arête (i+1, i+2) : bit de l'arête qui commence au sommet i+1
        curb |= (flag.astype(np.uint8) << (5 + (i + 1) % 3)).astype(np.uint8)
    Tt, M, curb = Tt[keep], M[keep], curb[keep]
    H = height(Vt[:, 0], Vt[:, 1])
    # altitude des sommets de bord : profil linéaire entre points canoniques (identique dans la tuile voisine,
    # même si les sommets intermédiaires diffèrent : pas de fente)
    for axis, val in ((0, ox), (0, ox + TILE_M), (1, oz), (1, oz + TILE_M)):
        on = np.abs(Vt[:, axis] - val) < 0.5 / Q
        if on.any():
            other = 1 - axis
            t0 = ox if other == 0 else oz
            ts = t0 + np.arange(0, TILE_M + 0.01, EDGE)
            pts = np.zeros((len(ts), 2)); pts[:, axis] = val; pts[:, other] = ts
            hc = height(pts[:, 0], pts[:, 1])
            H[on] = np.interp(Vt[on, other], ts, hc)
    V3 = np.stack([Vt[:, 0] - ox, H, Vt[:, 1] - oz], 1)
    return V3, Tt, (M | curb).astype(np.uint8)


def encode_decals(t, decals):
    ox, oz = t[0] * TILE_M, t[1] * TILE_M
    out = bytearray()
    lines = [(k, c, ph) for k, c, ph in decals["lines"] if 2 <= len(c) <= 255]
    out += struct.pack("<H", len(lines))
    for kind, c, phase in lines:
        out += struct.pack("<BBH", kind, len(c), int(round(phase * 10)) % 65536)
        q = np.round((c - (ox, oz)) * 10).astype("<i2")
        out += q.tobytes()
    out += struct.pack("<H", len(decals["rects"]))
    for kind, x, z, ang, across, along in decals["rects"]:
        out += struct.pack("<BhhHBB", kind, int(round((x - ox) * 10)), int(round((z - oz) * 10)),
                           int(round((ang % (2 * math.pi)) / (2 * math.pi) * 65535)), max(1, min(255, int(round(across * 10)))),
                           max(1, min(255, int(round(along * 10)))))
    return bytes(out)


def encode_tile(V, Tt, M):
    """Tuile -> octets (avant compression). Sommets ordonnés en bandes de 16 m ; sommets de chaque triangle triés
    (a < b < c, l'orientation se recalcule) ; triangles triés par a. Plans i16 et altitudes i32 en codage delta."""
    assert len(V) < 32768, "tuile trop dense"
    xq = np.round(V[:, 0] * Q).astype(np.int64); zq = np.round(V[:, 2] * Q).astype(np.int64)
    order = np.lexsort((xq, zq // int(16 * Q)))
    rank = np.empty(len(order), np.int64); rank[order] = np.arange(len(order))
    xq, zq = xq[order], zq[order]
    base = float(np.floor(V[:, 1].min() * 100) / 100) if len(V) else 0.0
    yq = np.round((V[order, 1] - base) * 100).astype(np.int64)
    Tr = rank[Tt]
    perm = np.argsort(Tr, 1)                       # perm[:, j] = ancien coin en position j
    pos = np.argsort(perm, 1)                      # pos[:, i] = position du coin i
    Tr = np.take_along_axis(Tr, perm, 1)
    cb = (M >> 5) & 7
    nb = np.zeros_like(cb)
    for i in range(3):     # arête (i, i+1) -> paire de positions -> bit k de l'arête (k, k+1 mod 3)
        s_ = pos[:, i] + pos[:, (i + 1) % 3]
        k = np.where(s_ == 1, 0, np.where(s_ == 3, 1, 2))
        nb |= ((((cb >> i) & 1) << k)).astype(np.uint8)
    Mr = (M & 31) | (nb << 5)
    o = np.lexsort((Tr[:, 1], Tr[:, 0]))
    Tr, Mr = Tr[o], Mr[o]
    d = lambda a: np.diff(np.concatenate([[0], a]))
    out = struct.pack("<fII", base, len(V), len(Tr))
    for arr, dtype in ((d(xq), "<i2"), (d(zq), "<i2"), (d(yq), "<i4"),
                       (d(Tr[:, 0]), "<i2"), (Tr[:, 1] - Tr[:, 0], "<i2"), (Tr[:, 2] - Tr[:, 1], "<i2")):
        limits = np.iinfo(dtype)
        assert np.all((arr >= limits.min) & (arr <= limits.max)), "débordement terrain : " + dtype
        out += np.asarray(arr, dtype=dtype).tobytes()
    out += Mr.astype(np.uint8).tobytes()
    return out, base + (yq.min() / 100.0 if len(yq) else 0.0)


# ------------------------------------------------------------------------------------------------ ville
def tile_keys(city):
    """Tuiles de sol : décor détaillé et sa couronne ; les tuiles de décor lointain (« light_tiles » de la scène,
    tools/import/periphery.py) n'ont pas de maillage de sol propre hors de cette couronne (relief lointain)."""
    tiles = T.scene_tiles(city)
    meta = json.load(open(os.path.join(ROOT, "data/scenes", city + ".json")))
    core = tiles - {tuple(t) for t in meta.get("light_tiles", [])}
    return tiles, sorted({(t[0] + dx, t[1] + dz) for t in core for dx in (-1, 0, 1) for dz in (-1, 0, 1)})


def meta_blob(keys, decks, water, alt0):
    wl = [(p, lv - alt0) for p, lv in water if np.isfinite(lv) and lv >= -20]
    wtree = shapely.STRtree([p for p, _ in wl]) if wl else None
    tile_decks = defaultdict(list)
    for kd, w, q, y in decks:
        c = q[len(q) // 2]
        tile_decks[(int(math.floor(c[0] / TILE_M)), int(math.floor(c[1] / TILE_M)))].append((kd, w, q, y))
    out = bytearray(); st = defaultdict(int)
    for t in keys:
        ox, oz = t[0] * TILE_M, t[1] * TILE_M
        levels = []
        if wtree is not None:
            tb = box(ox, oz, ox + TILE_M, oz + TILE_M)
            for i in wtree.query(tb):
                p, lv = wl[int(i)]
                inter = p.intersection(tb)
                for piece in T.polys_of(inter):
                    rp = piece.representative_point()
                    levels.append((rp.x - ox, rp.y - oz, lv))
        levels = levels[:255]
        out += struct.pack("<B", len(levels))
        for x, z, lv in levels:
            out += struct.pack("<hhh", int(round(x * 10)), int(round(z * 10)), int(round(lv * 10)))
        dl = tile_decks.get(t, [])
        out += struct.pack("<H", len(dl))
        for kd, w, q, y in dl:
            n = min(len(q), 255)
            out += struct.pack("<BBB", kd, max(1, min(255, int(round(w * 5)))), n)
            for k in range(n):
                out += struct.pack("<hhh", int(round((q[k, 0] - ox) * 10)), int(round((q[k, 1] - oz) * 10)), int(round(y[k] * 10)))
        st["ponts"] += len(dl); st["niveaux_eau"] += len(levels)
    return bytes(out), dict(st)


def far_blob(frame, keys, alt0, city):
    lo = np.array(keys).min(0) * TILE_M - FAR_MARGIN; hi = (np.array(keys).max(0) + 1) * TILE_M + FAR_MARGIN
    nx = int((hi[0] - lo[0]) // FAR_STEP) + 1; nz = int((hi[1] - lo[1]) // FAR_STEP) + 1
    dem = CoarseDem(frame, os.path.join(T.SCRATCH, "dem"), city)
    gx, gz = np.meshgrid(lo[0] + np.arange(nx) * FAR_STEP, lo[1] + np.arange(nz) * FAR_STEP)
    try:
        h = dem(gx.ravel(), gz.ravel()) - alt0
    except (RuntimeError, ValueError) as err:          # mer, étranger : pas de mesure -> horizon plat
        print(city, "couronne :", err, file=sys.stderr)
        h = np.zeros(gx.size)
    h = np.where(np.isfinite(h), h, 0.0)
    # mer (Brest, Marseille, Nice, Le Havre) : pas de valeur négative profonde
    h = np.maximum(h, -alt0 - 1.0)
    out = struct.pack("<fffHH", float(lo[0]), float(lo[1]), FAR_STEP, nx, nz)
    out += np.clip(np.round(h * 10), -32000, 32000).astype("<i2").tobytes()
    return out


def build(city, workers=1):
    t0 = time.time()
    meta = json.load(open(os.path.join(ROOT, "data/scenes", city + ".json")))
    tmeta_path = os.path.join(ROOT, "data/scenes", city + "_terrain.json")
    tmeta = json.load(open(tmeta_path))
    alt0 = float(tmeta["alt0"])
    frame = T.Frame(*meta["origin"])
    # MNT LiDAR HD (repli RGE ALTI hors couverture) ; TERRAIN_LIDAR=0 : RGE ALTI seul
    st = defaultdict(int)
    dem = (T.Dem if os.environ.get("TERRAIN_LIDAR") == "0" else T.LidarDem)(frame, os.path.join(T.SCRATCH, "dem"), city)
    cache = os.path.join(T.SCRATCH, "ign_cache")
    scene_tiles, keys = tile_keys(city)
    lo = np.array(keys).min(0) * TILE_M; hi = (np.array(keys).max(0) + 1) * TILE_M
    la0, lo0 = frame.inv(lo[0], hi[1]); la1, lo1 = frame.inv(hi[0], lo[1])
    llb = (float(la0), float(lo0), float(la1), float(lo1))
    tp, ty, axes, tunnels = free_tracks(city, frame)
    water = T.water_surfaces(frame, cache, llb)
    # niveau inconnu (Z BD TOPO absent) : estimé sur le MNT RGE ALTI (surface de l'eau), jamais sur le MNT LiDAR
    # HD (interpolé et bruité sur l'eau) ; le lit est alors toujours creusé sous le plan d'eau
    base = getattr(dem, "base", dem)
    fixed = []
    for p, lv in water:
        if not (np.isfinite(lv) and lv >= -20) and p.area > 50:
            x0, z0, x1, z1 = p.bounds
            gx, gz = np.meshgrid(np.linspace(x0, x1, 12), np.linspace(z0, z1, 12))
            ins = shapely.contains_xy(p, gx.ravel(), gz.ravel())
            if ins.sum() >= 3:
                lv = float(np.percentile(base(gx.ravel()[ins], gz.ravel()[ins]), 30))
                st["niveaux_eau_estimés"] += 1
        fixed.append((p, lv))
    water = fixed
    height = Height(dem, alt0, (tp, ty), water)
    wl_chk = [(p, lv - alt0) for p, lv in water if np.isfinite(lv) and lv >= -20]
    wtree_chk = shapely.STRtree([p for p, _ in wl_chk]) if wl_chk else None
    curv = lambda x, z: dem(x, z)
    # points fins autour des portails de tunnel peu profonds (découpe nette par city_scene.add_portal_cut)
    extra = []
    for ax in tunnels:
        for p in ax[:: 2]:
            if dem(p[0:1], p[1:2])[0] - alt0 - p[2] < 7.0:
                for dx in (-6, -3, 0, 3, 6):
                    for dz in (-6, -3, 0, 3, 6):
                        extra.append((p[0] + dx, p[1] + dz))
    roads = RM.CityRoads(city, frame, cache, llb, axes, full_tiles=bool(meta.get("periphery_m")))
    scene = RM.read_scene(os.path.join(ROOT, "data/scenes", city + ".bin"))
    blobs, ymins = [], []
    # périphérie (tools/import/periphery.py) hors corridor historique : pas de maillage de sol propre (relief lointain
    # et voirie en rubans, CityScene._far_ground) ; la couronne lointaine couvre toute l'emprise
    all_keys = keys
    keys = [t for t in keys if not roads.coarse(t)]
    st["tuiles_relief_lointain"] = len(all_keys) - len(keys)
    for i, t in enumerate(keys):
        coarse = False
        parts, decals = roads.tile_parts(t, scene.get(t), t in scene_tiles, coarse)
        V, Tt, M = tile_mesh(t, parts, height, curv, extra, t in scene_tiles and not coarse, 0.8 if coarse else SIMPLIFY)
        if wtree_chk is not None:   # contrôle : aucun sommet de sol au-dessus du plan d'eau dans un polygone d'eau
            ox, oz = t[0] * TILE_M, t[1] * TILE_M
            pts = shapely.points(V[:, 0] + ox, V[:, 2] + oz)
            for wi in np.unique(wtree_chk.query(pts, predicate="within")[1]):
                pw, lvw = wl_chk[int(wi)]
                inn = shapely.contains_xy(pw.buffer(-1.0), V[:, 0] + ox, V[:, 2] + oz)
                st["sol_au_dessus_eau"] += int(np.sum(V[inn, 1] > lvw - 0.05))
        raw, ymin = encode_tile(V, Tt, M)
        raw += encode_decals(t, decals)
        st["décalques"] += len(decals["lines"]) + len(decals["rects"])
        blobs.append((len(raw), brotli.compress(raw, quality=11)))
        ymins.append(ymin)
        st["sommets"] += len(V); st["triangles"] += len(Tt)
        if i % 50 == 0:
            print(f"  {city} tuile {i + 1}/{len(keys)} ({time.time() - t0:.0f} s)", file=sys.stderr, flush=True)
    decks = T.road_decks(frame, dem, alt0, cache, llb)
    mraw, mst = meta_blob(keys, decks, water, alt0)
    st.update(mst)
    fraw = far_blob(frame, all_keys, alt0, city)
    mz, fz = brotli.compress(mraw, quality=11), brotli.compress(fraw, quality=11)
    head_len = 40 + 24 * len(keys)
    far_off = head_len; meta_off = far_off + len(fz); off = meta_off + len(mz)
    head = b"TGR2" + struct.pack("<IfIIIIIII", 2, TILE_M, len(keys), far_off, len(fz), len(fraw), meta_off, len(mz), len(mraw))
    table = bytearray()
    for t, (n, b), ym in zip(keys, blobs, ymins):
        table += struct.pack("<iiIIIf", t[0], t[1], off, len(b), n, ym)
        off += len(b)
    path = os.path.join(ROOT, "data/scenes", city + "_ground.bin")
    with open(path, "wb") as f:
        f.write(head + bytes(table) + fz + mz + b"".join(b for _, b in blobs))
    tmeta.update({"tiles": len(keys), "terrain_format": "TGR2", "ground_file": city + "_ground.bin",
                  "height_encoding": "TIN contraint par la voirie, cm", "shared_vertices": True,
                  "far_ring_m": FAR_MARGIN, "far_step_m": FAR_STEP,
                  "source": "MNT IGN RGE ALTI® (WMS data.geopf.fr) et BD TOPO® IGN, Licence Ouverte 2.0, extrait du " + time.strftime("%Y-%m-%d"),
                  "stats": dict(st)})
    for k in ("grid", "ground_profile_signature", "ground_conformity"):
        tmeta.pop(k, None)
    json.dump(tmeta, open(tmeta_path, "w"), ensure_ascii=False, indent=1)
    if getattr(dem, "coverage", None):
        tmeta["lidar_mnt_coverage"] = round(float(np.mean(dem.coverage)), 3)
        json.dump(tmeta, open(tmeta_path, "w"), ensure_ascii=False, indent=1)
    print(f"{city}: {len(keys)} tuiles, {os.path.getsize(path) / 1e6:.2f} Mo, {dict(st)}, {time.time() - t0:.0f} s", flush=True)


if __name__ == "__main__":
    for c in sys.argv[1:]:
        build(c)
