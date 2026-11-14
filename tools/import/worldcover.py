#!/usr/bin/env python3
"""Occupation du sol ESA WorldCover 10 m (v200, 2021, CC BY 4.0) hors de France, où l'orthophoto IGN manque
(Kehl, Belgique, Suisse) : lecture par requêtes partielles (HTTP Range) des dalles COG publiques
(esa-worldcover.s3.eu-central-1.amazonaws.com), tuiles TIFF 1024 x 1024 compressées deflate, mises en cache.
Utilisé par tools/import/landcover.py. Aucune donnée WorldCover n'est embarquée : seulement les classes dérivées.
"""
import math, os, struct, subprocess, zlib

import numpy as np

URL = "https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_{}_Map.tif"
N = 36000                    # pixels par côté (3 degrés)
TS = 1024                    # tuiles TIFF
# classes WorldCover -> classes de landcover.CLASSES
MAP = {10: 7, 20: 3, 30: 2, 40: 4, 50: 1, 60: 9, 70: 9, 80: 8, 90: 2, 95: 7, 100: 3}


def _get(url, a, b, path):
    if not os.path.exists(path):
        r = subprocess.run(["curl", "-sS", "--fail", "-m", "120", "-r", f"{a}-{b}", "-o", path + ".part", url], capture_output=True)
        if r.returncode != 0:
            raise RuntimeError("WorldCover : " + r.stderr.decode()[:200])
        os.replace(path + ".part", path)
    return open(path, "rb").read()


class WorldCover:
    def __init__(self, cache):
        self.cache = os.path.join(cache, "worldcover")
        os.makedirs(self.cache, exist_ok=True)
        self.index, self.tiles = {}, {}

    @staticmethod
    def name(lat0, lon0):
        return f"{'N' if lat0 >= 0 else 'S'}{abs(lat0):02d}{'E' if lon0 >= 0 else 'W'}{abs(lon0):03d}"

    def _ifd(self, nm):
        if nm not in self.index:
            url = URL.format(nm)
            try:
                b = _get(url, 0, 131071, os.path.join(self.cache, nm + "_head.bin"))
            except RuntimeError:
                self.index[nm] = None
                return None
            off = struct.unpack_from("<I", b, 4)[0]
            tags = {}
            for i in range(struct.unpack_from("<H", b, off)[0]):
                tag, typ, cnt, val = struct.unpack_from("<HHII", b, off + 2 + i * 12)
                tags[tag] = (typ, cnt, val)
            assert tags[259][2] == 8 and tags[322][2] == TS, "format WorldCover inattendu"
            n = tags[324][1]
            offs = struct.unpack_from(f"<{n}I", b, tags[324][2])
            cnts = struct.unpack_from(f"<{n}I", b, tags[325][2])
            self.index[nm] = (url, offs, cnts)
        return self.index[nm]

    def _tile(self, nm, tx, ty):
        k = (nm, tx, ty)
        if k not in self.tiles:
            ix = self._ifd(nm)
            arr = None
            if ix is not None:
                url, offs, cnts = ix
                i = ty * math.ceil(N / TS) + tx
                raw = _get(url, offs[i], offs[i] + cnts[i] - 1, os.path.join(self.cache, f"{nm}_{tx}_{ty}.bin"))
                arr = np.frombuffer(zlib.decompress(raw), np.uint8).reshape(TS, TS)
            if len(self.tiles) > 400:
                self.tiles.clear()
            self.tiles[k] = arr
        return self.tiles[k]

    def sample(self, lat, lon):
        """Classes landcover (255 : inconnue) aux points (lat, lon)."""
        lat = np.asarray(lat, np.float64).ravel(); lon = np.asarray(lon, np.float64).ravel()
        out = np.full(lat.shape, 255, np.uint8)
        lat0 = (np.floor(lat / 3) * 3).astype(int); lon0 = (np.floor(lon / 3) * 3).astype(int)
        px = ((lon - lon0) * N / 3).astype(int).clip(0, N - 1)
        py = ((lat0 + 3 - lat) * N / 3).astype(int).clip(0, N - 1)
        key = (lat0 + 90) * 1000 + (lon0 + 180)
        lut = np.full(256, 255, np.uint8)
        for a, b in MAP.items():
            lut[a] = b
        for k in np.unique(key):
            sel = key == k
            nm = self.name(int(k // 1000) - 90, int(k % 1000) - 180)
            tx, ty = px[sel] // TS, py[sel] // TS
            tk = tx * 100 + ty
            idx = np.nonzero(sel)[0]
            for t in np.unique(tk):
                s2 = tk == t
                arr = self._tile(nm, int(t // 100), int(t % 100))
                if arr is None:
                    continue
                ii = idx[s2]
                out[ii] = lut[arr[py[ii] % TS, px[ii] % TS]]
        return out
