#!/usr/bin/env python3
"""Occupation du sol réelle d'une ville (data/scenes/<ville>_land.bin, « TLC1 ») par classification des orthophotos IGN.

Deux rasters de classes, alignés sur le repère de la ville :
- détail : cellules de 25 m sur l'emprise des tuiles de sol (<ville>_ground.bin), orthophoto z15 (~3 m/px),
  moyenne de 5 x 5 échantillons par cellule ; teinte le sol nu (matériau GROUND) dans le shader du sol, filtrée
  bilinéairement (transitions douces, contour bruité), sous le masque de pelouse à 4 m de ign_scene.py ;
- lointain : cellules de 100 m sur l'emprise de la couronne lointaine (tuiles + 8 km, comme terrain_mesh.far_blob),
  orthophoto z13 (~13 m/px) ; couleur des sommets de l'horizon (src/rendering/terrain_view.gd).
Hors de France (Kehl, Belgique, Suisse : pas d'orthophoto IGN) : ESA WorldCover 10 m (2021, CC BY 4.0), voir
tools/import/worldcover.py.
Classes : règles sur la couleur moyenne de la cellule (indice de verdure, luminance, chroma), puis filtre modal 3 x 3 (pas de pixels isolés). Le jeu affiche la couleur de rendu
de la classe (palette cel shading), pas l'image : aucune orthophoto n'est embarquée.

Format (little endian) : "TLC1", u32 version (1), u8 n classes, n x (u8 r, g, b, drapeaux : bit 0 culture à sillons,
bit 1 boisé, bit 2 minéral), puis 2 rasters (détail, lointain) : f32 x0, f32 z0, f32 pas, u16 nx, u16 nz, u32 taille
compressée, u8[nz][nx] classe (255 = hors emprise) compressé Brotli.

Usage : TERRAIN_CACHE=<cache> landcover.py [VILLE...]   (après terrain_mesh.py ; cache des dalles : TERRAIN_CACHE/ortho)
"""
import json, math, os, struct, sys, time

import brotli
import numpy as np
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import terrain as T                     # noqa: E402
from ign_scene import Ortho, frame_inv_np   # noqa: E402
from worldcover import WorldCover           # noqa: E402

WC = WorldCover(T.SCRATCH)

ROOT = T.ROOT
TILE_M = T.TILE_M
CELL = 25.0
FAR_STEP = 100.0
FAR_MARGIN = 8000.0
Z_DETAIL, Z_FAR = 15, 13

# nom, couleur de rendu (sRGB), drapeaux (bit 0 sillons, bit 1 boisé, bit 2 minéral)
CLASSES = [
    ("urbain clair", "#a7a39a", 4),
    ("urbain dense", "#85817a", 4),
    ("pelouse, prairie", "#76874f", 0),
    ("prairie sèche, friche", "#9c9a6c", 0),
    ("champ moissonné", "#c4b183", 1),
    ("terre labourée", "#8e7a60", 1),
    ("culture verte", "#7c9248", 1),
    ("bois, forêt", "#4a5938", 2),
    ("eau", "#4a6670", 0),
    ("sable, roche, carrière", "#cbc2ab", 4),
    ("garrigue, vigne", "#958d6b", 0),
]


def classify(rgb, ok, south=False):
    """Règles sur la couleur moyenne de la cellule (orthophotos IGN, peu saturées) : luminance, indice de verdure
    ExG = (2g - r - b) / (r + g + b), chroma rouge-bleu (r - b) / (r + g + b). Seuils relevés sur Angers, Lyon, Nantes."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    s = r + g + b + 1e-6
    lum = 0.3 * r + 0.59 * g + 0.11 * b
    exg = (2 * g - r - b) / s
    rb = (r - b) / s
    cls = np.full(lum.shape, 1, np.uint8)                       # urbain dense (gris)
    cls[(exg < 0.02) & (lum >= 0.42)] = 0                         # urbain clair
    cls[(exg < 0.02) & (lum >= 0.60)] = 9                         # sable, roche, carrière
    cls[(rb >= 0.015) & (exg < 0.045) & (lum < 0.45)] = 5          # terre labourée
    cls[(rb >= 0.02) & (exg < 0.045) & (lum >= 0.45)] = 4          # champ moissonné
    cls[(exg >= 0.02) & (exg < 0.045) & (rb >= -0.01) & (lum >= 0.33)] = 10 if south else 3   # friche / garrigue
    cls[exg >= 0.045] = 2                                         # pelouse, prairie
    cls[(exg >= 0.08) & (lum >= 0.40)] = 6                        # culture verte
    cls[(exg >= 0.05) & (lum < 0.27)] = 7                         # bois (prairies humides sombres : prairie)
    cls[(lum < 0.25) & (exg < 0.05) & (rb < 0.02)] = 8            # eau (sombre, non verte)
    cls[~ok] = 255
    return cls


def modal(cls, n=len(CLASSES)):
    """Filtre modal 3 x 3 (classe majoritaire du voisinage), hors emprise conservée."""
    best = np.zeros(cls.shape, np.float32); out = cls.copy()
    for k in range(n):
        c = ndimage.uniform_filter((cls == k).astype(np.float32), 3, mode="nearest")
        sel = c > best
        best[sel] = c[sel]; out[sel] = k
    out[cls == 255] = 255
    return out


def raster(ortho, frame, z, x0, z0, step, nx, nz, sub, mask=None, south=False):
    """Classe par cellule : moyenne de sub x sub échantillons de l'orthophoto (zoom z)."""
    out = np.full((nz, nx), 255, np.uint8)
    rows = max(1, int(2_000_000 // max(1, nx * sub * sub)))
    offs = (np.arange(sub) + 0.5) / sub * step
    for r0 in range(0, nz, rows):
        r1 = min(nz, r0 + rows)
        cz = z0 + np.arange(r0, r1) * step
        cx = x0 + np.arange(nx) * step
        X = (cx[None, :, None, None] + offs[None, None, None, :]).repeat(r1 - r0, 0).repeat(sub, 2)
        Z = (cz[:, None, None, None] + offs[None, None, :, None]).repeat(nx, 1).repeat(sub, 3)
        if mask is not None:
            m = mask[r0:r1]
            if not m.any():
                continue
        lat, lon = frame_inv_np(frame, X, Z)
        keys = ortho.keys_for(z, lat[:, :, sub // 2, sub // 2] if mask is None else lat[m][:, sub // 2, sub // 2],
                              lon[:, :, sub // 2, sub // 2] if mask is None else lon[m][:, sub // 2, sub // 2])
        ortho.prefetch(z, keys)
        rgb, ok = ortho.sample(z, lat, lon)
        cnt = ok.sum((2, 3))
        mean = (rgb * ok[..., None]).sum((2, 3)) / np.maximum(cnt, 1)[..., None]
        cls = classify(mean, cnt >= sub * sub // 2, south)
        miss = cls == 255
        if mask is not None:
            miss &= mask[r0:r1]
        if miss.any():       # hors de France (pas d'orthophoto IGN) : ESA WorldCover 10 m
            c = sub // 2
            cls[miss] = WC.sample(lat[:, :, c, c][miss], lon[:, :, c, c][miss])
        if mask is not None:
            cls[~mask[r0:r1]] = 255
        out[r0:r1] = cls
    return modal(out)


def pack(x0, z0, step, a):
    c = brotli.compress(a.tobytes(), quality=11)
    return struct.pack("<fffHHI", x0, z0, step, a.shape[1], a.shape[0], len(c)) + c


def build(city):
    t0 = time.time()
    meta = json.load(open(os.path.join(ROOT, "data/scenes", city + ".json")))
    frame = T.Frame(*meta["origin"])
    tiles = T.scene_tiles(city)
    keys = sorted({(t[0] + dx, t[1] + dz) for t in tiles for dx in (-1, 0, 1) for dz in (-1, 0, 1)})
    ortho = Ortho(os.path.join(T.SCRATCH, "ortho"))
    k = np.array(keys)
    lo = k.min(0) * TILE_M; hi = (k.max(0) + 1) * TILE_M
    per = int(TILE_M / CELL)
    nx, nz = int((hi[0] - lo[0]) / CELL), int((hi[1] - lo[1]) / CELL)
    mask = np.zeros((nz, nx), bool)
    for tx, tz in keys:
        ix, iz = int((tx * TILE_M - lo[0]) / CELL), int((tz * TILE_M - lo[1]) / CELL)
        mask[max(0, iz - 1):iz + per + 1, max(0, ix - 1):ix + per + 1] = True
    south = meta["origin"][0] < 44.6
    det = raster(ortho, frame, Z_DETAIL, float(lo[0]), float(lo[1]), CELL, nx, nz, 5, mask, south)
    flo = lo - FAR_MARGIN; fhi = hi + FAR_MARGIN
    fnx = int((fhi[0] - flo[0]) // FAR_STEP) + 1; fnz = int((fhi[1] - flo[1]) // FAR_STEP) + 1
    far = raster(ortho, frame, Z_FAR, float(flo[0]), float(flo[1]), FAR_STEP, fnx, fnz, 4, None, south)
    out = bytearray(b"TLC1" + struct.pack("<IB", 1, len(CLASSES)))
    for _, col, fl in CLASSES:
        out += bytes(int(col[i:i + 2], 16) for i in (1, 3, 5)) + bytes([fl])
    out += pack(float(lo[0]), float(lo[1]), CELL, det) + pack(float(flo[0]), float(flo[1]), FAR_STEP, far)
    path = os.path.join(ROOT, "data/scenes", city + "_land.bin")
    open(path + ".part", "wb").write(out); os.replace(path + ".part", path)
    hist = np.bincount(det[det < 255], minlength=len(CLASSES))
    share = {CLASSES[i][0]: round(float(v) / max(1, hist.sum()), 3) for i, v in enumerate(hist) if v}
    print(f"{city}: occupation du sol {nx}x{nz} + {fnx}x{fnz}, {len(out) / 1e3:.0f} ko, {share}, {time.time() - t0:.0f} s", flush=True)


if __name__ == "__main__":
    cities = sys.argv[1:] or sorted(p[:-5] for p in os.listdir(os.path.join(ROOT, "data/free")) if p.endswith(".json"))
    for c in cities:
        build(c)
