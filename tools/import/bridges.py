#!/usr/bin/env python3
"""Ouvrages d'art cohérents : un tablier unique par pont (route, voie ferrée, tram, vélo, piétons réunis).

Remplace terrain.road_decks (un tablier par couple type/largeur, extrémités forcées au MNT : tabliers séparés et
décalés sur un même pont, raccords qui plongent au sol au milieu de l'ouvrage) :
1. tronçons BD TOPO au-dessus du sol (troncon_de_route hors sentiers/escaliers/bacs, troncon_de_voie_ferree, tram
   compris) découpés en segments de 4 m ;
2. regroupement par ouvrage : segments parallèles (|cos| >= 0,9), à moins de (l1 + l2) / 2 + 2,5 m l'un de l'autre et
   d'altitudes BD TOPO compatibles (< 2,5 m), composantes connexes (union-find) ;
3. axe = plus longue ligne fusionnée de l'ouvrage, tablier = enveloppe latérale de tous les tronçons projetés
   (largeur constante = 90e centile, axe décalé au centre de l'enveloppe, lissé) ;
4. altitude = médiane des Z BD TOPO par tranche de 5 m (sinon raccord linéaire entre culées au MNT), jamais sous
   la corde entre culées, lissée sur
   ± 10 m, au moins 0,25 m au-dessus du MNT (LiDAR HD), pente <= 8 % ; extrémités à moins de 2 m du sol raccordées au MNT,
   extrémités en l'air prolongées dans l'axe par une rampe continue (<= 6 %, 60 m au plus) jusqu'au MNT ;
5. type : 0 route, 1 voie ferrée, 2 mixte (route + rail/tram) ; ouvrages uniquement tram : laissés aux voies
   (LineView), mais leur emprise élargit les ouvrages mixtes.

Usage : TERRAIN_CACHE=<cache> bridges.py [VILLE...]   réécrit les tabliers de data/scenes/<ville>_ground.bin
(méta TGR, niveaux d'eau et tuiles inchangés) ; sans ville : toutes. Rapport : data/scenes/<ville>_bridges.json.
"""
import json, math, os, struct, sys
from collections import defaultdict

import brotli
import numpy as np
from scipy.spatial import cKDTree
from shapely.geometry import LineString
from shapely.ops import linemerge

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import terrain as T                   # noqa: E402

ROOT = T.ROOT
TILE_M = 400.0
SEG = 4.0          # m, découpage des tronçons
BIN = 5.0          # m, tranches le long de l'axe
GAP = 2.5          # m, écart latéral maximal entre voies d'un même ouvrage
DZ = 2.5           # m, écart d'altitude maximal (ouvrages superposés : échangeurs)
RAMP = 0.06
RAMP_MAX = 60.0
SKIP_NATURE = ("Sentier", "Escalier", "Bac ou liaison maritime", "Bac ou liaison fluviale")


def segments(frame, cache, llb):
    """[(x0, z0, x1, z1, y0, y1, demi-largeur, type)] ; type 0 route, 1 voie ferrée, 3 tram."""
    out = []
    for layer in ("troncon_de_route", "troncon_de_voie_ferree"):
        for f in T.cached_features(layer, cache, llb):
            pr = f["properties"]
            if not f.get("geometry") or T.pos_sol(pr) <= 0:
                continue
            if layer == "troncon_de_route":
                if pr.get("nature") in SKIP_NATURE:
                    continue
                w = pr.get("largeur_de_chaussee") or {"Type autoroutier": 14.0, "Route à 2 chaussées": 12.0,
                                                      "Piste cyclable": 2.0, "Chemin": 2.5}.get(pr.get("nature"), 6.0)
                w, kd = float(w) + (1.0 if pr.get("nature") in ("Piste cyclable", "Chemin") else 3.0), 0
            else:
                kd = 3 if pr.get("nature") == "Tramway" else 1
                try:
                    n = max(1, int(pr.get("nombre_de_voies") or 1))
                except (TypeError, ValueError):
                    n = 1
                w = 5.0 + 3.8 * (n - 1)        # entraxe ~3,8 m, banquettes comprises
            for l in T.lines3d(f["geometry"], frame):
                if len(l) < 2:
                    continue
                q = np.array(T.densify(l[:, :2].tolist(), SEG))
                s0 = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(l[:, :2], axis=0), axis=1))])
                sq = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(q, axis=0), axis=1))])
                zz = l[:, 2]
                ok = np.isfinite(zz)
                yq = np.interp(sq, s0[ok], zz[ok]) if ok.sum() >= 2 else np.full(len(q), np.nan)
                for i in range(len(q) - 1):
                    if np.hypot(*(q[i + 1] - q[i])) < 0.2:
                        continue
                    out.append((q[i, 0], q[i, 1], q[i + 1, 0], q[i + 1, 1], yq[i], yq[i + 1], w * 0.5, kd))
    return np.array(out, dtype=np.float64).reshape(-1, 8)


def clusters(S):
    """Composantes connexes des segments d'un même ouvrage (union-find)."""
    n = len(S)
    parent = list(range(n))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    mid = (S[:, 0:2] + S[:, 2:4]) * 0.5
    d = S[:, 2:4] - S[:, 0:2]
    ln = np.maximum(np.linalg.norm(d, axis=1), 1e-6)
    u = d / ln[:, None]
    ym = (S[:, 4] + S[:, 5]) * 0.5
    tree = cKDTree(mid)
    rmax = float(S[:, 6].max()) * 2 + GAP + SEG
    for i, j in tree.query_pairs(rmax):
        if abs(u[i] @ u[j]) < 0.9:
            continue
        rel = mid[j] - mid[i]
        lat = abs(rel[0] * u[i][1] - rel[1] * u[i][0])
        along = abs(rel @ u[i])
        if lat > S[i, 6] + S[j, 6] + GAP or along > (ln[i] + ln[j]) * 0.5 + 0.5:
            continue
        if np.isfinite(ym[i]) and np.isfinite(ym[j]) and abs(ym[i] - ym[j]) > DZ:
            continue
        a, b = find(i), find(j)
        if a != b:
            parent[a] = b
    groups = defaultdict(list)
    for i in range(n):
        groups[find(i)].append(i)
    return list(groups.values())


def smooth(v, k):
    if len(v) < 3 or k < 1:
        return v
    pad = np.concatenate([np.full(k, v[0]), v, np.full(k, v[-1])])
    ker = np.ones(2 * k + 1) / (2 * k + 1)
    return np.convolve(pad, ker, mode="valid")


def deck_of(S, idx, dem):
    """Tablier unique d'un ouvrage : (type, largeur, polyligne (n, 2), altitudes (n,)) ou None."""
    G = S[idx]
    kinds = set(G[:, 7].astype(int).tolist())
    if kinds == {3}:
        return None                     # pont du tram seul : dessiné par les voies (LineView)
    kd = 0 if kinds <= {0} else (1 if kinds <= {1} else 2)
    lines = [LineString([(g[0], g[1]), (g[2], g[3])]) for g in G]
    m = linemerge(lines)
    parts = [m] if m.geom_type == "LineString" else list(m.geoms)
    axis = max(parts, key=lambda g: g.length)
    if axis.length < 10:
        return None
    # boucle (deux chaussées d'un même pont fusionnées par leurs bretelles) : une seule chaussée sert d'axe, l'autre
    # est reprise dans l'enveloppe latérale ; idem pour un axe qui revient sur lui-même
    from shapely.ops import substring
    for _ in range(3):
        c0, c1 = axis.coords[0], axis.coords[-1]
        if math.hypot(c0[0] - c1[0], c0[1] - c1[1]) < 0.35 * axis.length and axis.length > 40:
            axis = substring(axis, 0, axis.length * 0.5)
        else:
            break
    A = np.array(T.densify(list(axis.simplify(0.5).coords), BIN))
    if len(A) >= 5:                     # axe lissé (± 10 m, extrémités fixes) : pas de cassure aux raccords
        As = np.stack([smooth(A[:, 0], 2), smooth(A[:, 1], 2)], 1)
        As[0], As[-1] = A[0], A[-1]
        A = As
        axis = LineString(A)
    sa = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(A, axis=0), axis=1))])
    # projection de tous les segments (milieux et extrémités) sur l'axe
    P = np.concatenate([G[:, 0:2], G[:, 2:4], (G[:, 0:2] + G[:, 2:4]) * 0.5])
    Y = np.concatenate([G[:, 4], G[:, 5], (G[:, 4] + G[:, 5]) * 0.5])
    W = np.concatenate([G[:, 6]] * 3)
    s = np.array([axis.project(_pt(p)) for p in P])
    tan = np.gradient(A, sa, axis=0)
    tan /= np.maximum(np.linalg.norm(tan, axis=1), 1e-6)[:, None]
    nrm = np.stack([-tan[:, 1], tan[:, 0]], 1)
    ia = np.clip(np.searchsorted(sa, s), 0, len(A) - 1)
    rel = P - A[ia]
    lat = (rel * nrm[ia]).sum(1)
    s0, s1 = float(s.min()), float(s.max())
    nb = max(2, int(math.ceil((s1 - s0) / BIN)) + 1)
    st = np.linspace(s0, s1, nb)
    lo = np.full(nb, np.nan); hi = np.full(nb, np.nan); yz = np.full(nb, np.nan)
    b = np.clip(np.round((s - s0) / BIN).astype(int), 0, nb - 1)
    for k in range(nb):
        sel = b == k
        if not sel.any():
            continue
        lo[k] = (lat[sel] - W[sel]).min(); hi[k] = (lat[sel] + W[sel]).max()
        z = Y[sel][np.isfinite(Y[sel])]
        if len(z):
            yz[k] = np.median(z)
    ok = np.isfinite(lo)
    lo = np.interp(st, st[ok], lo[ok]); hi = np.interp(st, st[ok], hi[ok])
    width = float(np.percentile(hi - lo, 90))
    centre = smooth((lo + hi) * 0.5, 2)
    ax = np.interp(st, sa, A[:, 0]); az = np.interp(st, sa, A[:, 1])
    nx = np.interp(st, sa, nrm[:, 0]); nz = np.interp(st, sa, nrm[:, 1])
    q = np.stack([ax + nx * centre, az + nz * centre], 1)
    hq = dem(q[:, 0], q[:, 1])
    if not np.isfinite(hq).all():       # sans MNT (mer) : sol 5 m sous le tablier BD TOPO
        ref = np.nanmin(yz) - 5.0 if np.isfinite(yz).any() else 0.0
        hq = np.where(np.isfinite(hq), hq, np.nanmin(hq) if np.isfinite(hq).any() else ref)
    okz = np.isfinite(yz)
    if okz.sum() >= max(2, nb // 3):
        y = np.interp(st, st[okz], yz[okz])
    else:
        y = np.interp(st, [s0, s1], [hq[0], hq[-1]])
    y = smooth(y, 2)
    # jamais sous la corde entre culées : les Z BD TOPO interpolés au niveau de l'eau en milieu de travée (tabliers
    # plongeant dans le fleuve) sont relevés ; ponts droits ou bombés
    y = np.maximum(y, np.interp(st, [s0, s1], [y[0], y[-1]]))
    y = np.maximum(y, hq + 0.25)
    if np.max(y - hq) < 2.0:
        return None                     # passage sans franchissement réel (remblai)
    # extrémités : au sol si proches du MNT, sinon rampe dans l'axe jusqu'au MNT
    out_q, out_y = [q], [y]
    for end in (0, -1):
        dy = y[end] - hq[end]
        if abs(dy) < 2.0:
            # culée : extrémité au MNT, écart réparti linéairement (pente <= 4 %, 10 m au moins)
            sd = st - st[0] if end == 0 else st[-1] - st
            L = max(10.0, abs(dy) / 0.04)
            y = y - dy * np.clip(1.0 - sd / L, 0.0, 1.0)
            continue
        t = q[end] - q[1 if end == 0 else -2]
        t /= max(np.linalg.norm(t), 1e-6)
        ext_q, ext_y = [], []
        cur = y[end]
        g0 = hq[end]
        for k in range(1, int(RAMP_MAX / BIN) + 1):
            p = q[end] + t * BIN * k
            g = float(dem(np.array([p[0]]), np.array([p[1]]))[0])
            if not np.isfinite(g) or g < g0 - 1.0:
                ext_q, ext_y = [], []       # sol qui descend (vallée, fleuve) : ouvrage interrompu, pas de rampe
                break
            cur -= BIN * RAMP
            if cur <= g + 0.05:
                ext_q.append(p); ext_y.append(g); break
            ext_q.append(p); ext_y.append(cur)
        if ext_q:
            eq, ey = np.array(ext_q), np.array(ext_y)
            if end == 0:
                out_q.insert(0, eq[::-1]); out_y.insert(0, ey[::-1])
            else:
                out_q.append(eq); out_y.append(ey)
    q = np.concatenate(out_q); y = np.concatenate(out_y)
    # pente bornée à 8 % entre sommets (creux relevés : jamais de marche ni de tablier sous le sol)
    ds = np.linalg.norm(np.diff(q, axis=0), axis=1)
    for _ in range(2):
        for k in range(1, len(y)):
            y[k] = max(y[k], y[k - 1] - 0.08 * ds[k - 1])
        for k in range(len(y) - 2, -1, -1):
            y[k] = max(y[k], y[k + 1] - 0.08 * ds[k])
    return kd, min(width, 50.0), q, y


class SafeDem:
    """MNT tolérant : blocs sans mesure (mer, étranger) -> NaN au lieu d'interrompre l'import."""

    def __init__(self, dem):
        self.dem = dem

    def __call__(self, x, z):
        x = np.atleast_1d(np.asarray(x, dtype=np.float64)); z = np.atleast_1d(np.asarray(z, dtype=np.float64))
        try:
            return self.dem(x, z)
        except (ValueError, RuntimeError):
            out = np.full(x.shape, np.nan)
            for i in range(len(x)):
                try:
                    out[i] = self.dem(x[i:i + 1], z[i:i + 1])[0]
                except (ValueError, RuntimeError):
                    pass
            return out


def _pt(p):
    from shapely.geometry import Point
    return Point(float(p[0]), float(p[1]))


def decks(frame, dem, alt0, cache, llb):
    S = segments(frame, cache, llb)
    if len(S) == 0:
        return [], {"ouvrages": 0}
    out, st = [], defaultdict(int)
    for idx in clusters(S):
        d = deck_of(S, idx, dem)
        if d is None:
            continue
        kd, w, q, y = d
        out.append((kd, w, q, y - alt0))
        st["ouvrages"] += 1; st["type_%d" % kd] += 1
        st["voies_fusionnees"] += int(len(set(np.round(S[idx][:, 6], 1))) > 1 or len(idx) > 2 * len(q))
    return out, dict(st)


# ------------------------------------------------------------------ réécriture des tabliers du fichier de sol
def _read_ground(path):
    b = open(path, "rb").read()
    magic = b[:4]
    ver, tile_m, n, far_off, far_cs, far_raw, meta_off, meta_cs, meta_raw = struct.unpack("<IfIIIIIII", b[4:40])
    table = [struct.unpack("<iiIIIf", b[40 + 24 * i: 64 + 24 * i]) for i in range(n)]
    fz = b[far_off:far_off + far_cs]
    meta = brotli.decompress(b[meta_off:meta_off + meta_cs])
    blobs = [b[o:o + ln] for _, _, o, ln, _, _ in table]
    return magic, ver, tile_m, table, fz, far_raw, meta, blobs


def _water_records(meta, keys):
    """Niveaux d'eau par tuile (octets), dans l'ordre de la table ; tabliers ignorés."""
    q, out = 0, []
    for _ in keys:
        nw = meta[q]
        out.append(meta[q:q + 1 + nw * 6]); q += 1 + nw * 6
        nd = struct.unpack("<H", meta[q:q + 2])[0]; q += 2
        for _ in range(nd):
            npt = meta[q + 2]; q += 3 + npt * 6
    return out


def patch(city):
    gpath = os.path.join(ROOT, "data/scenes", city + "_ground.bin")
    if not os.path.exists(gpath):
        return None
    scene = json.load(open(os.path.join(ROOT, "data/scenes", city + ".json")))
    tmeta = json.load(open(os.path.join(ROOT, "data/scenes", city + "_terrain.json")))
    alt0 = float(tmeta["alt0"])
    frame = T.Frame(*scene["origin"])
    magic, ver, tile_m, table, fz, far_raw, meta, blobs = _read_ground(gpath)
    keys = [(t[0], t[1]) for t in table]
    lo = np.array(keys).min(0) * TILE_M; hi = (np.array(keys).max(0) + 1) * TILE_M
    la0, lo0 = frame.inv(lo[0], hi[1]); la1, lo1 = frame.inv(hi[0], lo[1])
    llb = (float(min(la0, la1)), float(min(lo0, lo1)), float(max(la0, la1)), float(max(lo0, lo1)))
    lidar = "RGE ALTI" not in str(tmeta.get("mnt", ""))
    dem = SafeDem((T.LidarDem if lidar else T.Dem)(frame, os.path.join(T.SCRATCH, "dem"), city))
    dl, st = decks(frame, dem, alt0, os.path.join(T.SCRATCH, "ign_cache"), llb)
    water = _water_records(meta, keys)
    tile_decks = defaultdict(list)
    kset = set(keys)
    for kd, w, q, y in dl:
        # tuile porteuse : celle du milieu si elle a un sol, sinon celle (avec sol) qui porte le plus de sommets
        # (ponts sur un fleuve dont la tuile centrale n'a pas de maillage de sol)
        c = q[len(q) // 2]
        t = (int(math.floor(c[0] / TILE_M)), int(math.floor(c[1] / TILE_M)))
        if t not in kset:
            cnt = defaultdict(int)
            for p in q:
                tp = (int(math.floor(p[0] / TILE_M)), int(math.floor(p[1] / TILE_M)))
                if tp in kset:
                    cnt[tp] += 1
            if cnt:
                t = max(cnt, key=cnt.get)
            else:                       # tuile de sol la plus proche (décor lointain sans maillage de sol)
                ka = np.array(keys, dtype=np.float64) * TILE_M + TILE_M * 0.5
                dd = np.linalg.norm(ka - c, axis=1)
                if dd.min() > 1200.0:
                    continue
                t = keys[int(dd.argmin())]
        tile_decks[t].append((kd, w, q, y))
    kept = 0
    out = bytearray()
    for t, wrec in zip(keys, water):
        out += wrec
        ds = [d for d in tile_decks.get(t, []) if len(d[2]) >= 2]
        out += struct.pack("<H", len(ds))
        ox, oz = t[0] * TILE_M, t[1] * TILE_M
        for kd, w, q, y in ds:
            n = min(len(q), 255)
            out += struct.pack("<BBB", kd, max(1, min(255, int(round(w * 5)))), n)
            for k in range(n):
                out += struct.pack("<hhh", int(round((q[k, 0] - ox) * 10)), int(round((q[k, 1] - oz) * 10)), int(round(y[k] * 10)))
            kept += 1
    mraw = bytes(out)
    mz = brotli.compress(mraw, quality=11)
    head_len = 40 + 24 * len(keys)
    far_off = head_len; meta_off = far_off + len(fz); off = meta_off + len(mz)
    head = magic + struct.pack("<IfIIIIIII", ver, tile_m, len(keys), far_off, len(fz), far_raw, meta_off, len(mz), len(mraw))
    tb = bytearray()
    for (x, z, _, ln, n, ym), blob in zip(table, blobs):
        tb += struct.pack("<iiIIIf", x, z, off, len(blob), n, ym); off += len(blob)
    with open(gpath + ".tmp", "wb") as f:
        f.write(head + bytes(tb) + fz + mz + b"".join(blobs))
    os.replace(gpath + ".tmp", gpath)
    st["tabliers_ecrits"] = kept
    rep = {"schema": 1, "source": "BD TOPO® troncon_de_route / troncon_de_voie_ferree (position_par_rapport_au_sol > 0), "
           "MNT " + ("LiDAR HD" if lidar else "RGE ALTI") + " (IGN, Licence Ouverte 2.0)", "stats": st}
    json.dump(rep, open(os.path.join(ROOT, "data/scenes", city + "_bridges.json"), "w"), ensure_ascii=False, separators=(",", ":"))
    return st


if __name__ == "__main__":
    cities = sys.argv[1:] or sorted(f[:-11] for f in os.listdir(os.path.join(ROOT, "data/scenes")) if f.endswith("_ground.bin"))
    for c in cities:
        try:
            print(c, patch(c), flush=True)
        except Exception as err:          # une ville en échec n'arrête pas les autres
            print(c, "ECHEC", repr(err)[:200], flush=True)
