#!/usr/bin/env python3
"""Relief, profil en long des voies, plans d'eau et ponts d'une ville.

Sources : MNT IGN RGE ALTI® (WMS GeoTIFF float32 data.geopf.fr, ~10 m) et BD TOPO® (cache WFS de ign_scene.py :
altitudes Z des surfaces en eau, tronçons de route / voie ferrée avec position_par_rapport_au_sol), Licence Ouverte 2.0.

1. Profil des voies : altitude du MNT le long de l'axe (pas de 5 m) ; ponts (tronçons BD TOPO au-dessus du sol,
   surfaces en eau traversées) : altitude Z BD TOPO du tablier, sinon interpolation entre culées ; tunnels
   (tram BD TOPO sous le sol) : interpolation entre portails, sous le terrain. Lissage spatial
   bilatéral (sigma 20 m, identique pour les deux sens et toutes les lignes), rampes bornées à 8 %.
   Écrit dans chaque arête : "y" (altitude relative à "alt0" par sommet de "pts", pas <= 12 m), "grade"
   (pente moyenne), "bridge" / "tunnel" / "trench" (intervalles d'abscisse [s0, s1(, prof0, prof1)]).
2. Scène : data/scenes/<ville>_terrain.bin ("TTR1") = par tuile de 400 m (tuiles du décor + une couronne) une grille
   41 x 41 (10 m) d'altitudes relatives à alt0 (sol nivelé sous les voies au niveau du rail, lit des
   rivières sous le plan d'eau), niveaux d'eau, tabliers de ponts routiers / ferroviaires (polylignes 3D).
   Format (little endian) : "TTR1", u32 n, table [i32 tx, i32 tz, u32 off, u32 taille] ; par tuile :
   i16 base (dm), u8 pas (cm), 41*41 u8 ; u8 nb niveaux d'eau [i16 x, i16 z, i16 niveau] (dm, repère tuile) ;
   u16 nb ponts [u8 type (0 route, 1 fer), u8 largeur*5, u8 n, n x (i16 x, i16 z, i16 y)] (dm, repère tuile).

Usage : terrain.py CITY            (data/networks de la ville + scène)
        terrain.py CITY --free     (data/free/<ville>.json, après merge_city.py et turnbacks.py)
        terrain.py CITY --nets     (profils de data/networks seulement, scène inchangée)
Caches : SCRATCH/dem (GeoTIFF), SCRATCH/ign_cache (BD TOPO) ; variable TERRAIN_CACHE pour les changer.
"""
import json, math, os, struct, subprocess, sys, time
from collections import defaultdict

import numpy as np
from PIL import Image
from scipy.spatial import cKDTree
from scipy.ndimage import distance_transform_edt
import shapely
from shapely.geometry import LineString, Polygon, box, shape
from shapely.ops import unary_union, linemerge

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SCRATCH = os.environ.get("TERRAIN_CACHE", os.path.join(ROOT, ".cache", "geography"))
R = 6371008.8
TILE_M = 400.0
GRID = 41                 # sommets par côté de tuile (pas de 10 m)
BLOCK = 2560.0            # m, emprise d'une requête WMS (256 px ~ 10 m)
STEP = 5.0                # m, échantillonnage des voies
MAX_GRADE = 0.08
WMS = ("https://data.geopf.fr/wms-r?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&LAYERS=ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES"
       "&STYLES=&CRS=EPSG:4326&BBOX={:.6f},{:.6f},{:.6f},{:.6f}&WIDTH=264&HEIGHT=264&FORMAT=image/geotiff")


class Frame:
    def __init__(self, lat0, lon0):
        self.lat0, self.lon0, self.k = lat0, lon0, math.cos(math.radians(lat0))

    def fwd(self, lat, lon):
        return (np.radians(np.asarray(lon) - self.lon0) * R * self.k, -np.radians(np.asarray(lat) - self.lat0) * R)

    def inv(self, x, z):
        return (self.lat0 - np.degrees(np.asarray(z) / R), self.lon0 + np.degrees(np.asarray(x) / (R * self.k)))


def fill_nodata(a):
    """Ne jamais confondre une absence de mesure avec une altitude au niveau de la mer.

    Petits trous réparés par la mesure valide la plus proche ; dalle majoritairement
    absente refusée. Les plans d'eau ont leur propre altitude BD TOPO.
    """
    a = np.array(a, dtype=np.float64, copy=True)
    missing = ~np.isfinite(a) | (a < -500) | (a > 9000)
    if missing.mean() > 0.2:
        raise ValueError("MNT : plus de 20 % de mesures absentes ; import interrompu")
    if missing.any():
        nearest = distance_transform_edt(missing, return_distances=False, return_indices=True)
        a[missing] = a[tuple(nearest[:, missing])]
    return a


def interpolate_elevation(vertices, samples):
    """Altitude interpolée selon les mètres parcourus, jamais l'indice des sommets."""
    arc = np.r_[0., np.cumsum(np.linalg.norm(np.diff(vertices[:, :2], axis=0), axis=1))]
    dst = np.r_[0., np.cumsum(np.linalg.norm(np.diff(samples, axis=0), axis=1))]
    valid = np.isfinite(vertices[:, 2]) & (vertices[:, 2] > -500)
    return np.interp(dst, arc[valid], vertices[valid, 2]) if valid.any() else np.full(len(samples), np.nan)


# ------------------------------------------------------------------------------------------------ MNT
class Dem:
    def __init__(self, frame, cache, tag):
        self.frame, self.cache, self.tag, self.blocks = frame, cache, tag, {}
        os.makedirs(cache, exist_ok=True)

    def _block(self, bx, bz):
        k = (bx, bz)
        if k in self.blocks:
            return self.blocks[k]
        m = 20.0
        lat_a, lon_a = self.frame.inv(bx * BLOCK - m, (bz + 1) * BLOCK + m)
        lat_b, lon_b = self.frame.inv((bx + 1) * BLOCK + m, bz * BLOCK - m)
        bb = (float(min(lat_a, lat_b)), float(min(lon_a, lon_b)), float(max(lat_a, lat_b)), float(max(lon_a, lon_b)))
        path = os.path.join(self.cache, "%s_%d_%d.tif" % (self.tag, bx, bz))
        if not os.path.exists(path):
            for attempt in range(6):
                r = subprocess.run(["curl", "-sS", "--fail", "-m", "120", "-o", path + ".part", WMS.format(*bb)], capture_output=True)
                if r.returncode == 0:
                    try:
                        Image.open(path + ".part").load()
                        os.replace(path + ".part", path)
                        break
                    except Exception:
                        pass
                time.sleep(2 ** attempt)
            else:
                raise RuntimeError("MNT indisponible : " + r.stderr.decode()[:200])
        a = np.array(Image.open(path), dtype=np.float64)
        a = fill_nodata(a)
        self.blocks[k] = (bb, a)
        return self.blocks[k]

    def __call__(self, x, z):
        x = np.asarray(x, dtype=np.float64); z = np.asarray(z, dtype=np.float64)
        out = np.zeros(x.shape)
        bx = np.floor(x / BLOCK).astype(int); bz = np.floor(z / BLOCK).astype(int)
        lat, lon = self.frame.inv(x, z)
        for k in set(zip(bx.ravel().tolist(), bz.ravel().tolist())):
            sel = (bx == k[0]) & (bz == k[1])
            (la0, lo0, la1, lo1), a = self._block(*k)
            h, w = a.shape
            fy = (la1 - lat[sel]) / (la1 - la0) * h - 0.5
            fx = (lon[sel] - lo0) / (lo1 - lo0) * w - 0.5
            ix = np.clip(np.floor(fx).astype(int), 0, w - 2); iy = np.clip(np.floor(fy).astype(int), 0, h - 2)
            tx = np.clip(fx - ix, 0, 1); ty = np.clip(fy - iy, 0, 1)
            out[sel] = (a[iy, ix] * (1 - tx) * (1 - ty) + a[iy, ix + 1] * tx * (1 - ty)
                        + a[iy + 1, ix] * (1 - tx) * ty + a[iy + 1, ix + 1] * tx * ty)
        return out


# ------------------------------------------------------------------------------------------------ BD TOPO (cache)
def cached_features(layer, cache, ll_box):
    """Entités d'une couche BD TOPO déjà téléchargées par ign_scene.py dont l'emprise touche ll_box."""
    pre = layer + "_"
    feats = {}
    for f in os.listdir(cache):
        if not f.startswith(pre) or not f.endswith(".json"):
            continue
        try:
            a = [float(v) for v in f[len(pre):-5].split("_")]
        except ValueError:
            continue
        if len(a) != 4 or a[2] < ll_box[0] or a[0] > ll_box[2] or a[3] < ll_box[1] or a[1] > ll_box[3]:
            continue
        for ft in json.load(open(os.path.join(cache, f))):
            feats[ft["id"]] = ft
    return list(feats.values())


def pos_sol(p):
    try:
        return int(str(p.get("position_par_rapport_au_sol", "0")))
    except ValueError:
        return 0


def lines3d(geom, frame):
    """Polylignes 3D (x, z, altitude) projetées ; altitude NaN si inconnue."""
    g = geom["coordinates"]
    parts = [g] if geom["type"] == "LineString" else g if geom["type"] == "MultiLineString" else []
    out = []
    for c in parts:
        if len(c) < 2:
            continue
        c = np.array([(p[0], p[1], p[2] if len(p) > 2 else np.nan) for p in c], dtype=np.float64)
        x, z = frame.fwd(c[:, 1], c[:, 0])
        y = c[:, 2]
        y[(y < -100) | (y > 5000)] = np.nan
        out.append(np.stack([x, z, y], 1))
    return out


def polys_of(g):
    if g is None or g.is_empty:
        return []
    if g.geom_type == "Polygon":
        return [g]
    return [q for p in getattr(g, "geoms", []) for q in polys_of(p)]


# ------------------------------------------------------------------------------------------------ voies
def densify(pts, step):
    out = [pts[0]]
    for a, b in zip(pts[:-1], pts[1:]):
        d = math.dist(a, b)
        n = max(1, int(math.ceil(d / step)))
        for k in range(1, n + 1):
            out.append((a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n))
    return out


def resample(pts, step):
    """Points régulièrement espacés (pas <= step) le long de la polyligne."""
    a = np.asarray(pts, dtype=np.float64)
    s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(a, axis=0), axis=1))])
    n = max(1, int(math.ceil(s[-1] / step)))
    t = np.linspace(0, s[-1], n + 1)
    return list(zip(np.interp(t, s, a[:, 0]).tolist(), np.interp(t, s, a[:, 1]).tolist()))


def make_chains(P, seqs):
    """Arêtes mises bout à bout (extrémités confondues) : lissage et rampes continus aux nœuds."""
    key = lambda i: (round(P[i][0] * 2), round(P[i][1] * 2))
    starts = defaultdict(list)
    for k, q in enumerate(seqs):
        starts[key(q[0])].append(k)
    nxt, used = {}, set()
    for k, q in enumerate(seqs):
        for c in starts.get(key(q[-1]), []):
            if c != k and c not in used:
                nxt[k] = c; used.add(c); break
    chains, alias, seen = [], [], set()
    heads = [k for k in range(len(seqs)) if k not in used] + list(range(len(seqs)))
    for h in heads:
        if h in seen:
            continue
        ch, k = list(seqs[h]), h
        seen.add(h)
        while k in nxt and nxt[k] not in seen:
            k = nxt[k]; seen.add(k)
            alias.append((seqs[k][0], ch[-1]))
            ch += list(seqs[k][1:])
        chains.append(ch)
    return chains, alias


def city_nets(city):
    nd = os.path.join(ROOT, "data/networks")
    out = []
    for f in sorted(os.listdir(nd)):
        if f.endswith(".json"):
            p = os.path.join(nd, f)
            d = json.load(open(p))
            if d.get("source_id") == city and d.get("origin"):
                out.append((p, d))
    return out


def runs(mask):
    i, n = 0, len(mask)
    while i < n:
        if mask[i]:
            j = i
            while j + 1 < n and mask[j + 1]:
                j += 1
            yield i, j
            i = j + 1
        else:
            i += 1


class Field:
    """Profil des voies : échantillons (x, z) de l'axe, altitude lissée, nature (0 sol, 1 pont, 2 tunnel, 3 trémie)."""

    def __init__(self, P, Y, H, K, seqs):
        self.P, self.Y, self.H, self.K = P, Y, H, K
        self.tree = cKDTree(P)
        self.prev = np.full(len(P), -1); self.next = np.full(len(P), -1)
        for sq in seqs:
            self.prev[sq[1:]] = sq[:-1]; self.next[sq[:-1]] = sq[1:]

    def on_seq(self, xz, key):
        """Valeurs projetées sur la séquence d'échantillons d'une arête source (pas de mélange entre voies voisines)."""
        sq = self.by_key.get(key)
        if sq is None or len(sq) < 2:
            return self.at(xz)
        A, B = self.P[sq[:-1]], self.P[sq[1:]]
        ab = B - A
        l2 = np.maximum(np.sum(ab * ab, 1), 1e-9)
        out_y, out_k, out_h = np.zeros(len(xz)), np.zeros(len(xz), dtype=int), np.zeros(len(xz))
        last = 0
        for r in range(len(xz)):
            t = np.clip(np.sum((xz[r] - A) * ab, 1) / l2, 0, 1)
            d = np.sum((A + ab * t[:, None] - xz[r]) ** 2, 1)
            if r > 0:   # parcours monotone (boucles : pas de retour sur une partie déjà passée)
                d[:max(0, last - 2)] = np.inf
            i = int(np.argmin(d)); u = t[i]; last = i
            a, b = sq[i], sq[i + 1]
            out_y[r] = self.Y[a] * (1 - u) + self.Y[b] * u
            out_h[r] = self.H[a] * (1 - u) + self.H[b] * u
            out_k[r] = self.K[a] if u < 0.5 else self.K[b]
        return out_y, out_k, out_h

    def at(self, xz):
        """Valeurs interpolées linéairement sur le segment d'échantillons le plus proche."""
        _, near = self.tree.query(xz)
        out_y, out_k, out_h = np.zeros(len(xz)), np.zeros(len(xz), dtype=int), np.zeros(len(xz))
        for r, i in enumerate(near):
            best = (np.inf, i, i, 0.0)
            for a, b in ((self.prev[i], i), (i, self.next[i])):
                if a < 0 or b < 0:
                    continue
                ab = self.P[b] - self.P[a]
                t = float(np.clip(np.dot(xz[r] - self.P[a], ab) / max(np.dot(ab, ab), 1e-9), 0.0, 1.0))
                dd = float(np.linalg.norm(self.P[a] + ab * t - xz[r]))
                if dd < best[0]:
                    best = (dd, a, b, t)
            _, a, b, t = best
            out_y[r] = self.Y[a] * (1 - t) + self.Y[b] * t
            out_h[r] = self.H[a] * (1 - t) + self.H[b] * t
            out_k[r] = self.K[a] if t < 0.5 else self.K[b]
        return out_y, out_k, out_h


def build_field(city, frame, dem, cache, alt0=None):
    nets = city_nets(city)
    seqs, keys = [], []         # par arête : indices des échantillons, (réseau, arête)
    P = []
    for _, d in nets:
        nf = Frame(*d["origin"])
        for e in d["edges"]:
            pts = e.get("pts", [])
            if len(pts) < 2 or e.get("raw"):
                continue
            a = np.array(pts, dtype=np.float64)
            lat, lon = nf.inv(a[:, 0], a[:, 1])
            x, z = frame.fwd(lat, lon)
            q = resample(list(zip(x.tolist(), z.tolist())), STEP)
            seqs.append(list(range(len(P), len(P) + len(q))))
            keys.append((d["id"], e["id"]))
            P += q
    P = np.array(P)
    chains, alias = make_chains(P, seqs)
    H = dem(P[:, 0], P[:, 1])
    if alt0 is None:
        alt0 = round(float(np.median(H)), 1)
    lo = P.min(0) - 300; hi = P.max(0) + 300
    la0, lo0 = frame.inv(lo[0], hi[1]); la1, lo1 = frame.inv(hi[0], lo[1])
    llb = (float(la0), float(lo0), float(la1), float(lo1))
    bridges, tunnels, zpts = [], [], []
    for ft in cached_features("troncon_de_voie_ferree", cache, llb):
        if not ft.get("geometry"):
            continue
        pr = ft["properties"]; ps = pos_sol(pr)
        tram = pr.get("nature") == "Tramway"
        if tram and ps != 0:     # tram BD TOPO en ouvrage (pont ou tunnel)
            for l in lines3d(ft["geometry"], frame):
                ls = LineString(l[:, :2])
                if ps > 0:
                    bridges.append(ls.buffer(6.0, cap_style=2))
                    q = densify([tuple(v) for v in l[:, :2]], 4.0)
                    zz = interpolate_elevation(l, np.asarray(q))
                    zpts += [(a[0], a[1], b) for a, b in zip(q, zz) if np.isfinite(b)]
                else:
                    tunnels.append(ls.buffer(6.0, cap_style=2))
    water = []
    for ft in cached_features("surface_hydrographique", cache, llb):
        if ft.get("geometry") and ft["geometry"]["type"] in ("Polygon", "MultiPolygon"):
            g = shape(ft["geometry"])
            for p in polys_of(g):
                c = np.array(p.exterior.coords)
                x, z = frame.fwd(c[:, 1], c[:, 0])
                pp = Polygon(np.stack([x, z], 1)).buffer(0)
                if pp.is_empty:
                    continue
                lv = c[:, 2] if c.shape[1] > 2 else np.array([np.nan])
                lv = lv[(lv > -100) & (lv < 5000)]
                water.append((pp, float(np.median(lv)) if len(lv) else np.nan))
    bmask = np.zeros(len(P), bool); tmask = np.zeros(len(P), bool)
    if bridges:
        bmask |= shapely.contains_xy(unary_union(bridges), P[:, 0], P[:, 1])
    if water:
        bmask |= shapely.contains_xy(unary_union([w[0].buffer(3.0) for w in water]), P[:, 0], P[:, 1])
    if tunnels:
        tmask = shapely.contains_xy(unary_union(tunnels), P[:, 0], P[:, 1])
        bmask &= ~tmask   # un tunnel documenté peut passer sous une rivière
    zt = cKDTree(np.array([(a, b) for a, b, _ in zpts])) if zpts else None
    zv = np.array([c for _, _, c in zpts]) if zpts else None
    Rw = H.copy()
    K = np.zeros(len(P), dtype=int)
    for sq in chains:
        sq = np.array(sq)
        s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P[sq], axis=0), axis=1))])
        for mask, kind in ((bmask[sq], 1), (tmask[sq], 2)):
            for i, j in runs(mask):
                if s[j] - s[i] < 12.0 and kind == 1:
                    continue
                if kind == 1:   # culées : prolongé tant que le sol reste nettement sous la rive opposée (berges basses)
                    n = len(sq)
                    hb, he = H[sq[max(i - 1, 0)]], H[sq[min(j + 1, n - 1)]]
                    i0, j0 = i, j
                    while i > 0 and H[sq[i - 1]] < he - 3.0 and s[i0] - s[i - 1] < 300.0:
                        i -= 1
                    while j < n - 1 and H[sq[j + 1]] < hb - 3.0 and s[j + 1] - s[j0] < 300.0:
                        j += 1
                a = max(i - 1, 0); b = min(j + 1, len(sq) - 1)
                lin = np.interp(s[i:j + 1], [s[a], s[b]], [H[sq[a]], H[sq[b]]])
                if kind == 1:
                    y = lin
                    if zt is not None:
                        dd, ii = zt.query(P[sq[i:j + 1]], distance_upper_bound=12.0)
                        okz = np.isfinite(dd)
                        if okz.any():   # altitudes Z BD TOPO du tablier + culées, interpolées
                            ss = s[i:j + 1]
                            xs = np.concatenate([[s[a]], ss[okz], [s[b]]])
                            ys = np.concatenate([[H[sq[a]]], zv[ii[okz]], [H[sq[b]]]])
                            y = np.interp(ss, xs, ys)
                    y = np.maximum(y, H[sq[i:j + 1]] + 0.3)
                    if np.max(y - H[sq[i:j + 1]]) > 1.5:
                        K[sq[i:j + 1]] = 1
                    Rw[sq[i:j + 1]] = y
                else:
                    if s[j] - s[i] < 50.0:
                        continue
                    Rw[sq[i:j + 1]] = np.minimum(lin, H[sq[i:j + 1]])   # entre portails, jamais au-dessus du sol
                    K[sq[i:j + 1]] = 2
    # lissage bilatéral spatial (commun à tous les sens et lignes)
    tree = cKDTree(P)
    Y = np.empty(len(P))
    nb = tree.query_ball_point(P, 50.0)
    for i, js in enumerate(nb):
        js = np.array(js)
        d2 = np.sum((P[js] - P[i]) ** 2, 1)
        w = np.exp(-d2 / (2 * 20.0 ** 2)) * np.exp(-((Rw[js] - Rw[i]) / 2.5) ** 2)
        Y[i] = np.sum(Rw[js] * w) / np.sum(w)
    # rampes <= 8 % (enveloppe inférieure lipschitzienne : déblais plutôt que remblais)
    for _ in range(3):
        for sq in chains:
            sq = np.array(sq)
            ds = np.linalg.norm(np.diff(P[sq], axis=0), axis=1)
            y = Y[sq]
            for k in range(1, len(y)):
                y[k] = min(y[k], y[k - 1] + MAX_GRADE * 0.93 * ds[k - 1])
            for k in range(len(y) - 2, -1, -1):
                y[k] = min(y[k], y[k + 1] + MAX_GRADE * 0.93 * ds[k])
            Y[sq] = y
    # adoucissement des cassures (noyau positif : la borne de pente est conservée)
    for _ in range(4):
        Z = Y.copy()
        for sq in chains:
            if len(sq) > 2:
                sq = np.array(sq)
                Z[sq[1:-1]] = 0.25 * Y[sq[:-2]] + 0.5 * Y[sq[1:-1]] + 0.25 * Y[sq[2:]]
        Y = Z
    for a, b in alias:
        Y[a] = Y[b]
    # trémies : voie nettement sous le terrain hors tunnel
    depth = H - Y
    K[(K == 0) & (depth > 0.8)] = 3
    # Un déblai profond ne prouve pas la présence d’un tunnel.
    f = Field(P, Y - alt0, H - alt0, K, [np.array(q) for q in seqs])
    f.by_key = {k: np.array(q) for k, q in zip(keys, seqs)}
    return f, alt0, water, seqs


# ------------------------------------------------------------------------------------------------ réseaux
def spans(s, flags, extra=None):
    out = []
    for i, j in runs(flags):
        if s[j] - s[i] < 6.0:
            continue
        r = [round(float(s[max(i - 1, 0)]), 1), round(float(s[min(j + 1, len(s) - 1)]), 1)]
        if extra is not None:
            r += [round(float(extra[i]), 1), round(float(extra[j]), 1)]
        out.append(r)
    return out


def apply(path, frame, field, alt0):
    d = json.load(open(path))
    nf = Frame(*d["origin"])
    st = defaultdict(int)
    node_y = {}
    for e in sorted(d["edges"], key=lambda e: bool(e.get("raw"))):   # communications de voies après les voies
        pts = e.get("pts", [])
        for k in ("y", "bridge", "tunnel", "trench"):
            e.pop(k, None)
        if len(pts) < 2:
            continue
        q = densify([tuple(p) for p in pts], 12.0)
        # sommets colinéaires ajoutés seulement là où l'espacement dépasse 12 m (géométrie inchangée)
        e["pts"] = [[round(a, 2), round(b, 2)] for a, b in q] if len(q) != len(pts) else pts
        a = np.array(e["pts"], dtype=np.float64)
        lat, lon = nf.inv(a[:, 0], a[:, 1])
        x, z = frame.fwd(lat, lon)
        xz = np.stack([x, z], 1)
        eid = e["id"]
        if e.get("raw"):   # communication de voies : rampe linéaire entre les deux voies raccordées
            y, kind, h = field.at(xz[[0, -1]])
            y = np.array([node_y.get(e["from"], y[0]), node_y.get(e["to"], y[1])])
            w = np.linspace(0, 1, len(xz))
            y = y[0] * (1 - w) + y[1] * w; h = h[0] * (1 - w) + h[1] * w
            kind = np.where(w < 0.5, kind[0], kind[1])
        elif ":" in eid and not eid.startswith("X:"):   # réseau libre : arête d'origine "<ligne>:<arête>|k"
            net_id, src = eid.split(":", 1)
            y, kind, h = field.on_seq(xz, (net_id, src.split("|")[0]))
        else:
            y, kind, h = field.on_seq(xz, (d["id"], eid))
        e["y"] = [round(float(v), 2) for v in y]
        if not e.get("raw"):
            node_y.setdefault(e["from"], float(y[0])); node_y.setdefault(e["to"], float(y[-1]))
        geo = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(a, axis=0), axis=1))])
        s = geo * (float(e["length"]) / geo[-1] if geo[-1] > 0 else 1.0)
        e["grade"] = round(float((y[-1] - y[0]) / max(float(e["length"]), 1.0)), 4)
        for name, k in (("bridge", 1), ("tunnel", 2)):
            sp = spans(s, kind == k)
            if sp:
                e[name] = sp
                st[name] += 1
        sp = spans(s, kind == 3, np.maximum(h - y, 0.0))
        if sp:
            e["trench"] = sp
        st["edges"] += 1
        st["max_grade"] = max(st["max_grade"], float(np.max(np.abs(np.diff(y)) / np.maximum(np.diff(geo), 0.5))) if len(y) > 1 else 0)
    d["alt0"] = alt0
    d["estimated"] = [x for x in d.get("estimated", []) if not x.startswith("grade")]
    note = (" Altitudes : MNT IGN RGE ALTI® et BD TOPO® (Licence Ouverte 2.0), profil lissé, rampes <= 8 % "
            "(tools/import/terrain.py).")
    if note.strip() not in d.get("provenance", ""):
        d["provenance"] = d.get("provenance", "") + note
    json.dump(d, open(path, "w"), ensure_ascii=False, separators=(",", ":"))
    return dict(st)


# ------------------------------------------------------------------------------------------------ scène
def scene_tiles(city):
    buf = open(os.path.join(ROOT, "data/scenes", city + ".bin"), "rb").read()
    n = struct.unpack_from("<I", buf, 4)[0]
    return {struct.unpack_from("<ii", buf, 8 + i * 16) for i in range(n)}


def write_scene(city, frame, dem, field, alt0, water, cache):
    tiles = scene_tiles(city)
    ring = {(t[0] + dx, t[1] + dz) for t in tiles for dx in (-1, 0, 1) for dz in (-1, 0, 1)}
    keys = sorted(ring)
    # sol nivelé sous les voies (au rail près) hors ponts et tunnels
    flat = field.K != 1
    flat &= field.K != 2
    ft = cKDTree(field.P[flat]); fy = field.Y[flat]
    xs = np.arange(GRID) * 10.0
    gx, gz = np.meshgrid(xs, xs)        # [iz, ix]
    lo = np.array(keys).min(0) * TILE_M; hi = (np.array(keys).max(0) + 1) * TILE_M
    la0, lo0 = frame.inv(lo[0], hi[1]); la1, lo1 = frame.inv(hi[0], lo[1])
    llb = (float(la0), float(lo0), float(la1), float(lo1))
    # ponts routiers et ferroviaires : tronçons BD TOPO au-dessus du sol fusionnés, altitude Z (sinon culées)
    decks = []
    by_kind = defaultdict(list)
    for layer, kd in (("troncon_de_route", 0), ("troncon_de_voie_ferree", 1)):
        for f in cached_features(layer, cache, llb):
            pr = f["properties"]
            if not f.get("geometry") or pos_sol(pr) <= 0 or pr.get("nature") == "Tramway":
                continue
            if kd == 0:
                w = pr.get("largeur_de_chaussee") or {"Type autoroutier": 14.0, "Route à 2 chaussées": 12.0}.get(pr.get("nature"), 6.0)
                if pr.get("nature") in ("Sentier", "Chemin", "Escalier", "Bac ou liaison maritime"):
                    continue
                w = float(w) + 3.0
            else:
                w = 5.0
            for l in lines3d(f["geometry"], frame):
                by_kind[(kd, round(w))].append(l)
    for (kd, w), ls in by_kind.items():
        zz = cKDTree(np.concatenate([l[:, :2] for l in ls]))
        zall = np.concatenate([l[:, 2] for l in ls])
        merged = linemerge([LineString(l[:, :2]) for l in ls])
        for m in ([merged] if merged.geom_type == "LineString" else list(merged.geoms)):
            if m.length < 10:
                continue
            q = np.array(densify(list(m.simplify(0.5).coords), 15.0))
            hq = dem(q[:, 0], q[:, 1])
            s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(q, axis=0), axis=1))])
            lin = np.interp(s, [0, s[-1]], [hq[0], hq[-1]])
            dd, ii = zz.query(q, distance_upper_bound=3.0)
            okz = np.isfinite(dd)
            zq = np.where(okz, zall[np.minimum(ii, len(zall) - 1)], np.nan)
            okz &= np.isfinite(zq)
            y = np.where(okz, zq, lin) if okz.mean() > 0.5 else lin
            # extrémités raccordées au terrain, tablier au-dessus du sol
            y[0], y[-1] = hq[0], hq[-1]
            y = np.maximum(y, hq + 0.25)
            if np.max(y - hq) < 2.0:
                continue        # passage sans franchissement réel (remblai)
            decks.append((kd, w, q, y - alt0))
    wl = []
    for p, lv in water:
        if np.isfinite(lv):
            wl.append((p, lv - alt0))
    wtree = shapely.STRtree([p for p, _ in wl]) if wl else None
    blobs, st = [], defaultdict(int)
    tile_decks = defaultdict(list)
    for kd, w, q, y in decks:
        c = q[len(q) // 2]
        tile_decks[(int(math.floor(c[0] / TILE_M)), int(math.floor(c[1] / TILE_M)))].append((kd, w, q, y))
    for t in keys:
        ox, oz = t[0] * TILE_M, t[1] * TILE_M
        X = gx + ox; Z = gz + oz
        Hg = dem(X.ravel(), Z.ravel()).reshape(X.shape) - alt0
        # lit des rivières : sous le plan d'eau
        levels = []
        if wtree is not None:
            tb = box(ox, oz, ox + TILE_M, oz + TILE_M)
            for i in wtree.query(tb):
                p, lv = wl[int(i)]
                inter = p.intersection(tb)
                if inter.is_empty:
                    continue
                inside = shapely.contains_xy(p, X.ravel(), Z.ravel()).reshape(X.shape)
                Hg = np.where(inside, np.minimum(Hg, lv - 1.2), Hg)
                for piece in polys_of(inter):
                    rp = piece.representative_point()
                    levels.append((rp.x - ox, rp.y - oz, lv))
        d, i = ft.query(np.stack([X.ravel(), Z.ravel()], 1), distance_upper_bound=18.0)
        ok = np.isfinite(d)
        yb = np.where(ok, fy[np.minimum(i, len(fy) - 1)] - 0.12, 0.0)
        wgt = np.where(ok, np.clip((18.0 - d) / 10.0, 0.0, 1.0), 0.0)
        Hf = Hg.ravel() * (1 - wgt) + yb * wgt
        Hg = Hf.reshape(Hg.shape)
        out = bytearray(Hg.astype("<f4").tobytes())
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
        st["ponts"] += len(dl)
        st["niveaux_eau"] += len(levels)
        blobs.append(bytes(out))
    head = b"TTR2" + struct.pack("<I", len(keys))
    off = len(head) + 16 * len(keys)
    table = bytearray()
    for t, b in zip(keys, blobs):
        table += struct.pack("<iiII", t[0], t[1], off, len(b))
        off += len(b)
    path = os.path.join(ROOT, "data/scenes", city + "_terrain.bin")
    open(path, "wb").write(head + bytes(table) + b"".join(blobs))
    meta = {"schema": 1, "city": city, "alt0": alt0, "tile_m": TILE_M, "grid": GRID, "tiles": len(keys),
            "source": "MNT IGN RGE ALTI® (WMS data.geopf.fr) et BD TOPO® IGN, Licence Ouverte 2.0, extrait du " + time.strftime("%Y-%m-%d"),
            "stats": dict(st)}
    json.dump(meta, open(os.path.join(ROOT, "data/scenes", city + "_terrain.json"), "w"), ensure_ascii=False, indent=1)
    return len(keys), os.path.getsize(path), dict(st)


def main(city, *opts):
    meta = json.load(open(os.path.join(ROOT, "data/scenes", city + ".json")))
    frame = Frame(*meta["origin"])
    dem = Dem(frame, os.path.join(SCRATCH, "dem"), city)
    cache = os.path.join(SCRATCH, "ign_cache")
    prev = os.path.join(ROOT, "data/scenes", city + "_terrain.json")
    alt0 = json.load(open(prev))["alt0"] if ("--free" in opts or "--nets" in opts) and os.path.exists(prev) else None
    field, alt0, water, _ = build_field(city, frame, dem, cache, alt0)
    if "--free" in opts:
        print(city, "libre", apply(os.path.join(ROOT, "data/free", city + ".json"), frame, field, alt0))
        return
    for p, _ in city_nets(city):
        print(os.path.basename(p), apply(p, frame, field, alt0))
    if "--nets" in opts:
        return
    print(city, "alt0", alt0, "terrain", write_scene(city, frame, dem, field, alt0, water, cache))


if __name__ == "__main__":
    main(*sys.argv[1:])
