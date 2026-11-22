"""Accès aux données géographiques du jeu pour la modélisation : projection (identique à CityScene / LineView),
sol IGN (TIN TGR2 de data/scenes/<ville>_ground.bin), bâtiments et houppiers (data/scenes/<ville>.bin), réseaux."""
import json, math, struct
from pathlib import Path
import brotli
import numpy as np
from scipy.spatial import Delaunay

ROOT = Path(__file__).resolve().parents[2]
R = 6371008.8


def ll2xy(lat, lon, org):
    return (math.radians(lon - org[1]) * R * math.cos(math.radians(org[0])), -math.radians(lat - org[0]) * R)


def xy2ll(x, z, org):
    return (org[0] - math.degrees(z / R), org[1] + math.degrees(x / (R * math.cos(math.radians(org[0])))))


class City:
    def __init__(self, name):
        self.name = name
        meta = json.loads((ROOT / f"data/scenes/{name}.json").read_text())
        self.origin = meta["origin"]; self.tile = meta["tile_m"]
        self._ground = None; self._scene = None; self._tri = {}

    # ---------------------------------------------------------------- sol
    def _load_ground(self):
        b = (ROOT / f"data/scenes/{self.name}_ground.bin").read_bytes()
        wide = b[:4] == b"TGR2"; tile = struct.unpack_from("<f", b, 8)[0]; n = struct.unpack_from("<I", b, 12)[0]
        self._ground = {}
        for i in range(n):
            x, z, off, cs, raw, ymin = struct.unpack_from("<iiIIIf", b, 40 + 24 * i)
            self._ground[(x, z)] = (off, cs, wide, tile, b)

    def _tile(self, key):
        if key in self._tri: return self._tri[key]
        off, cs, wide, tile, b = self._ground[key]
        data = brotli.decompress(b[off:off + cs])
        base, nv, nt = struct.unpack_from("<fII", data)
        xz = np.frombuffer(data, dtype="<i2", count=nv * 2, offset=12).reshape(2, nv).astype(np.int64).cumsum(axis=1)
        y = np.frombuffer(data, dtype="<i4" if wide else "<i2", count=nv, offset=12 + nv * 4).astype(np.int64).cumsum()
        v = np.column_stack((xz[0] / 64 + key[0] * tile, base + y / 100, xz[1] / 64 + key[1] * tile))
        t = np.frombuffer(data, dtype="<i2", count=nt * 3, offset=12 + nv * (8 if wide else 6)).reshape(3, nt).astype(np.int64)
        t[0] = t[0].cumsum(); t[1] += t[0]; t[2] += t[1]
        self._tri[key] = (v, t.T)
        return self._tri[key]

    def ground(self, x, z):
        """Altitude (repère du jeu) du sol IGN au point (x, z) du repère de la ville."""
        if self._ground is None: self._load_ground()
        key = (math.floor(x / self.tile), math.floor(z / self.tile))
        if key not in self._ground: return 0.0
        v, t = self._tile(key)
        if not hasattr(self, "_grid"): self._grid = {}
        if key not in self._grid:
            # index spatial grossier des triangles (cellules de 8 m)
            g = {}
            a, b, c = v[t[:, 0]], v[t[:, 1]], v[t[:, 2]]
            lo = np.minimum(np.minimum(a, b), c); hi = np.maximum(np.maximum(a, b), c)
            for k in range(len(t)):
                for gx in range(int(lo[k, 0] // 8), int(hi[k, 0] // 8) + 1):
                    for gz in range(int(lo[k, 2] // 8), int(hi[k, 2] // 8) + 1):
                        g.setdefault((gx, gz), []).append(k)
            self._grid[key] = g
        for k in self._grid[key].get((int(x // 8), int(z // 8)), []):
            a, b, c = v[t[k, 0]], v[t[k, 1]], v[t[k, 2]]
            d = (b[2] - c[2]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[2] - c[2])
            if abs(d) < 1e-12: continue
            l1 = ((b[2] - c[2]) * (x - c[0]) + (c[0] - b[0]) * (z - c[2])) / d
            l2 = ((c[2] - a[2]) * (x - c[0]) + (a[0] - c[0]) * (z - c[2])) / d
            l3 = 1 - l1 - l2
            if min(l1, l2, l3) >= -1e-6:
                return float(l1 * a[1] + l2 * b[1] + l3 * c[1])
        return 0.0

    # ---------------------------------------------------------------- décor (bâtiments, houppiers)
    def scene(self):
        if self._scene is not None: return self._scene
        b = (ROOT / f"data/scenes/{self.name}.bin").read_bytes(); out = {"b": [], "t": []}
        for tile in range(struct.unpack_from("<I", b, 4)[0]):
            tx, tz, off, cs, us = struct.unpack_from("<iiIII", b, 8 + tile * 20); q = brotli.decompress(b[off:off + cs])
            P = lambda n, at: [(tx * 400 + struct.unpack_from("<h", q, at + j * 4)[0] * .1, tz * 400 + struct.unpack_from("<h", q, at + j * 4 + 2)[0] * .1) for j in range(n)]
            nb = struct.unpack_from("<H", q, 0)[0]; o = 2
            for j in range(nb):
                nv, cls, h, kind = struct.unpack_from("<BBHB", q, o); o += 5; ring = P(nv, o); o += nv * 4; nt = q[o]; o += 1 + nt * 3
                out["b"].append({"ring": ring, "cls": cls, "h": h / 10, "kind": kind})
            n = struct.unpack_from("<H", q, o)[0]; o += 2
            for j in range(n):
                cls, nv, nt = struct.unpack_from("<BHH", q, o); o += 5 + nv * 4 + nt * 6
            n = struct.unpack_from("<H", q, o)[0]; o += 2
            for j in range(n):
                cls, w, nn = struct.unpack_from("<BBH", q, o); o += 4 + nn * 4
            n = struct.unpack_from("<H", q, o)[0]; o += 2 + 7 * n
            n = struct.unpack_from("<H", q, o)[0]; o += 2
            for j in range(n):
                L = q[o + 5]; o += 6 + L
            n = struct.unpack_from("<H", q, o)[0]; o += 2 + 2 * n
            n = struct.unpack_from("<H", q, o)[0]; o += 2
            for j in range(n):
                v = P(1, o)[0]; r, k = struct.unpack_from("<BB", q, o + 4); out["t"].append({"v": v, "r": r / 10, "kind": k}); o += 6
        self._scene = out
        return out


def network(name):
    return json.loads((ROOT / f"data/networks/{name}.json").read_text())


def edge_axis(net, eid):
    e = next(e for e in net["edges"] if e["id"] == eid)
    pts = e["pts"] if isinstance(e["pts"], list) else json.loads(e["pts"])
    y = e["y"] if isinstance(e["y"], list) else json.loads(e["y"])
    return np.array(pts, float), np.array(y, float), e
