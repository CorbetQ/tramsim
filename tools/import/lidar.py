#!/usr/bin/env python3
"""Produits dérivés LiDAR HD de l'IGN (WMS-R data.geopf.fr, Licence Ouverte 2.0) : MNH (hauteur du sursol) par tuile
de décor, pour ign_scene.py :
- hauteur mesurée des bâtiments BD TOPO (médiane du MNH dans l'emprise érodée ; faîtage = 90e centile, égout =
  25e centile : toit plat si l'écart est < 1,2 m, sinon pente de l'écart mesuré) ;
- arbres réels : sommets locaux du MNH (>= 3 m) hors bâti, rayon de houppier = demi-largeur de la tache de
  végétation haute autour du sommet, hauteur mesurée.
Couverture : LiDAR HD n'est pas encore national (en 2026 : absent à Lille, Valenciennes, partiel à Toulouse,
Bordeaux, Strasbourg, Tours) ; une tuile sans mesure valide (>= 60 % de pixels) renvoie None et ign_scene garde
les hauteurs BD TOPO et les houppiers de l'orthophoto.
Cache : TERRAIN_CACHE/lidar/<z>_<tx>_<tz>.npz (MNH en dm, uint16, compressé). Résolution : 1 m (décor détaillé),
2 m (décor lointain).
"""
import math, os, subprocess, time

import numpy as np

URL = ("https://data.geopf.fr/wms-r?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap"
       "&LAYERS=IGNF_LIDAR-HD_MNH_ELEVATION.ELEVATIONGRIDCOVERAGE.WGS84G&STYLES=normal&CRS=EPSG:4326"
       "&BBOX={:.7f},{:.7f},{:.7f},{:.7f}&WIDTH={}&HEIGHT={}&FORMAT=image/geotiff")
MARGIN = 8.0
NODATA = 65535


class Lidar:
    def __init__(self, cache, frame, tile_m=400.0):
        self.cache = os.path.join(cache, "lidar")
        os.makedirs(self.cache, exist_ok=True)
        self.frame, self.tile_m = frame, tile_m
        self.stats = {"tuiles_lidar": 0, "tuiles_sans_lidar": 0}

    def tile(self, t, step=1.0):
        """MNH (m, float32, NaN hors couverture) sur la tuile t élargie de MARGIN, pas `step` ; (array, x0, z0) ou None."""
        x0, z0 = t[0] * self.tile_m - MARGIN, t[1] * self.tile_m - MARGIN
        size = self.tile_m + 2 * MARGIN
        n = int(round(size / step))
        path = os.path.join(self.cache, f"{step:g}_{t[0]}_{t[1]}.npz")
        if os.path.exists(path):
            q = np.load(path)["h"]
        else:
            la, lo = self.frame.inv(x0, z0 + size); lb, lob = self.frame.inv(x0 + size, z0)
            url = URL.format(float(min(la, lb)), float(min(lo, lob)), float(max(la, lb)), float(max(lo, lob)), n, n)
            tmp = path + ".tif"
            arr = None
            for attempt in range(4):
                r = subprocess.run(["curl", "-sS", "--fail", "-m", "120", "-o", tmp, url], capture_output=True)
                if r.returncode == 0:
                    try:
                        from PIL import Image
                        arr = np.array(Image.open(tmp), dtype=np.float32)
                        break
                    except Exception:
                        pass
                time.sleep(2 ** attempt)
            if os.path.exists(tmp):
                os.remove(tmp)
            if arr is None or arr.shape != (n, n):
                return None
            bad = ~np.isfinite(arr) | (arr < -5) | (arr > 400)
            q = np.where(bad, NODATA, np.clip(np.round(np.maximum(arr, 0) * 10), 0, 65000)).astype(np.uint16)
            np.savez_compressed(path, h=q)
        h = np.where(q == NODATA, np.nan, q.astype(np.float32) / 10.0)
        if np.isfinite(h).mean() < 0.6:
            self.stats["tuiles_sans_lidar"] += 1
            return None
        self.stats["tuiles_lidar"] += 1
        return h, x0, z0, step


def _raster(poly, x0, z0, step, shape):
    from PIL import Image, ImageDraw
    im = Image.new("L", (shape[1], shape[0]), 0)
    ImageDraw.Draw(im).polygon([((x - x0) / step, (z - z0) / step) for x, z in poly.exterior.coords], fill=1)
    return np.asarray(im, bool)


def building_measure(poly, mnh):
    """(hauteur d'égout, hausse du toit) mesurées, ou None (emprise trop petite ou sans mesure)."""
    h, x0, z0, step = mnh
    a, b, c, d = poly.bounds
    i0, i1 = max(0, int((b - z0) / step) - 1), min(h.shape[0], int((d - z0) / step) + 2)
    j0, j1 = max(0, int((a - x0) / step) - 1), min(h.shape[1], int((c - x0) / step) + 2)
    if i1 <= i0 or j1 <= j0:
        return None
    sub = h[i0:i1, j0:j1]
    m = _raster(poly, x0 + j0 * step, z0 + i0 * step, step, sub.shape)
    from scipy import ndimage
    me = ndimage.binary_erosion(m, iterations=1)
    if me.sum() >= 4:
        m = me
    v = sub[m & np.isfinite(sub)]
    if len(v) < 3:
        return None
    top, eave = float(np.percentile(v, 90)), float(np.percentile(v, 25))
    if top < 2.0:
        return None
    if top - eave < 1.2:
        return max(2.5, float(np.median(v))), 0.0
    return max(2.5, eave), min(10.5, top - eave)


def trees(mnh, built, water=None, keep=None):
    """Arbres du MNH : [(x, z, rayon, hauteur)] (repère ville). built : masque bâti (même grille), à exclure.
    keep(x, z) -> bool : filtre (plateformes de voie, eau)."""
    from scipy import ndimage
    h, x0, z0, step = mnh
    g = np.nan_to_num(h, nan=0.0)
    veg = (g >= 3.0) & ~ndimage.binary_dilation(built, iterations=max(1, int(round(1.5 / step))))
    if water is not None:
        veg &= ~water
    if not veg.any():
        return []
    sm = ndimage.gaussian_filter(np.where(veg, g, 0.0), 0.8 / step)
    win = max(3, int(round(4.0 / step)) | 1)
    peaks = veg & (sm == ndimage.maximum_filter(sm, size=win)) & (sm >= 3.0)
    dist = ndimage.distance_transform_edt(veg) * step
    out = []
    zz, xx = np.nonzero(peaks)
    m = int(round(MARGIN / step))
    for i, j in zip(zz, xx):
        if not (m <= i < h.shape[0] - m and m <= j < h.shape[1] - m):
            continue
        x, z = x0 + (j + 0.5) * step, z0 + (i + 0.5) * step
        if keep is not None and not keep(x, z):
            continue
        hh = float(g[i, j])
        r = float(np.clip(max(dist[i, j], 0.22 * hh), 1.2, 9.0))
        out.append((x, z, r, min(hh, 45.0)))
    return out
