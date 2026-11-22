"""Petit noyau de modélisation procédurale (sans Blender) : primitives à UV métriques, niveaux de LOD, export glTF 2.0
binaire (.glb). Les UV sont en mètres (u horizontal, v vertical sur les parois ; x/z sur les faces horizontales) : le
matériau applique l'échelle `uv_scale_m` de sa fiche (data/materials). Chaque primitive est nommée par l'identifiant
du matériau de la bibliothèque PBR (src/rendering/pbr_materials.gd), qui la remplace au chargement."""
import json, math, struct
import numpy as np
import mapbox_earcut as earcut

UP = np.array([0.0, 1.0, 0.0])


def v3(*a):
    return np.array(a[0] if len(a) == 1 else a, dtype=float)


def norm(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v


class Kit:
    """Accumulateur : parts[(lod_lo, lod_hi, group, mat)] -> listes de sommets (p, n, uv) et d'indices."""

    def __init__(self):
        self.parts = {}
        self.lod = (0, 2)       # niveaux où la géométrie ajoutée est visible (inclus)
        self.group = "static"
        self.cols = []          # boîtes de collision (centre, taille, base)

    def _buf(self, mat):
        k = (self.lod[0], self.lod[1], self.group, mat)
        if k not in self.parts:
            self.parts[k] = {"p": [], "n": [], "uv": [], "i": []}
        return self.parts[k]

    # ------------------------------------------------------------------ primitives de base
    @staticmethod
    def _uv(p, n):
        if abs(n[1]) > 0.7:
            return (p[0], p[2])
        t = norm(np.cross(UP, n))
        return (float(np.dot(p, t)), p[1])

    def tri(self, a, b, c, mat, hint=None, uvs=None, normals=None):
        a, b, c = v3(a), v3(b), v3(c)
        n = np.cross(b - a, c - a)
        if np.linalg.norm(n) < 1e-10:
            return
        n = norm(n)
        if hint is not None and np.dot(n, hint) < 0:
            b, c = c, b; n = -n
            if uvs is not None: uvs = (uvs[0], uvs[2], uvs[1])
            if normals is not None: normals = (normals[0], normals[2], normals[1])
        B = self._buf(mat)
        base = len(B["p"]) // 3
        for k, p in enumerate((a, b, c)):
            B["p"].extend(p)
            nn = normals[k] if normals is not None else n
            B["n"].extend(nn)
            B["uv"].extend(uvs[k] if uvs is not None else self._uv(p, n))
        B["i"].extend((base, base + 1, base + 2))

    def quad(self, a, b, c, d, mat, hint=None, uvs=None):
        if uvs is None:
            self.tri(a, b, c, mat, hint); self.tri(a, c, d, mat, hint)
        else:
            self.tri(a, b, c, mat, hint, (uvs[0], uvs[1], uvs[2])); self.tri(a, c, d, mat, hint, (uvs[0], uvs[2], uvs[3]))

    def mesh(self, P, idx, mat, N=None, UV=None):
        """Maillage indexé à normales lissées (P : Nx3, idx : triangles)."""
        P = np.asarray(P, float)
        if N is None:
            N = np.zeros_like(P)
            for t in idx:
                a, b, c = P[t[0]], P[t[1]], P[t[2]]
                fn = np.cross(b - a, c - a)
                for j in t: N[j] += fn
            N = np.array([norm(x) for x in N])
        B = self._buf(mat)
        base = len(B["p"]) // 3
        for k in range(len(P)):
            B["p"].extend(P[k]); B["n"].extend(N[k])
            B["uv"].extend(UV[k] if UV is not None else self._uv(P[k], N[k]))
        for t in idx:
            B["i"].extend((base + t[0], base + t[1], base + t[2]))

    def poly(self, pts3, mat, hint=UP, holes=()):
        """Polygone plan (anneau 3D) triangulé (earcut) dans son plan."""
        pts3 = [v3(p) for p in pts3]
        n = np.zeros(3)
        for i in range(len(pts3)):
            n += np.cross(pts3[i], pts3[(i + 1) % len(pts3)])
        n = norm(n) if np.linalg.norm(n) > 1e-9 else norm(v3(hint))
        if abs(n[1]) > 0.9:
            ax, ay = v3(1, 0, 0), v3(0, 0, 1)
        else:
            ax = norm(np.cross(UP, n)); ay = norm(np.cross(n, ax))
        rings = [pts3] + [[v3(p) for p in h] for h in holes]
        flat = []; ends = []; allp = []
        for r in rings:
            for p in r:
                flat.append((np.dot(p, ax), np.dot(p, ay))); allp.append(p)
            ends.append(len(flat))
        idx = earcut.triangulate_float64(np.array(flat, dtype=np.float64), np.array(ends, dtype=np.uint32))
        for k in range(0, len(idx), 3):
            self.tri(allp[idx[k]], allp[idx[k + 1]], allp[idx[k + 2]], mat, hint)

    # ------------------------------------------------------------------ volumes
    def box(self, c, size, mat, yaw=0.0, basis=None, faces="all"):
        """Boîte orientée : `basis` (3 vecteurs unitaires) ou lacet `yaw` (rad, autour de y)."""
        c = v3(c); sx, sy, sz = size
        if basis is None:
            ca, sa = math.cos(yaw), math.sin(yaw)
            basis = (v3(ca, 0, sa), UP, v3(-sa, 0, ca))
        X, Y, Z = [v3(b) for b in basis]
        hx, hy, hz = X * sx / 2, Y * sy / 2, Z * sz / 2
        P = lambda i, j, k: c + hx * i + hy * j + hz * k
        F = [((1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1), X), ((-1, -1, 1), (-1, 1, 1), (-1, 1, -1), (-1, -1, -1), -X),
             ((-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1), Y), ((-1, -1, 1), (-1, -1, -1), (1, -1, -1), (1, -1, 1), -Y),
             ((-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1), Z), ((1, -1, -1), (-1, -1, -1), (-1, 1, -1), (1, 1, -1), -Z)]
        for i, f in enumerate(F):
            if faces != "all" and i not in faces: continue
            self.quad(P(*f[0]), P(*f[1]), P(*f[2]), P(*f[3]), mat, f[4])

    def seg_box(self, a, b, w, h, mat, up=UP):
        """Poutre de section w×h de a à b."""
        a, b = v3(a), v3(b); d = b - a; L = np.linalg.norm(d)
        if L < 1e-6: return
        X = d / L; Z = norm(np.cross(X, up)); Y = np.cross(Z, X)
        self.box((a + b) / 2, (L, h, w), mat, basis=(X, Y, Z))

    def cyl(self, a, b, r, mat, seg=12, caps=True, r2=None):
        """Cylindre (ou tronc de cône si r2) lissé de a à b."""
        a, b = v3(a), v3(b); d = norm(b - a)
        r2 = r if r2 is None else r2
        t = norm(np.cross(d, v3(1, 0, 0) if abs(d[0]) < 0.9 else v3(0, 0, 1))); s = np.cross(d, t)
        P, N, UV, I = [], [], [], []
        L = np.linalg.norm(b - a)
        for i in range(seg + 1):
            ang = 2 * math.pi * i / seg; o = t * math.cos(ang) + s * math.sin(ang)
            slope = (r - r2) / max(L, 1e-6)
            nn = norm(o + d * slope)
            P += [a + o * r, b + o * r2]; N += [nn, nn]; u = ang * (r + r2) / 2
            UV += [(u, 0.0), (u, L)]
        for i in range(seg):
            k = 2 * i; I += [(k, k + 2, k + 1), (k + 1, k + 2, k + 3)]
        self.mesh(P, I, mat, np.array(N), UV)
        if caps:
            for c, rr, dn in ((a, r, -d), (b, r2, d)):
                if rr < 1e-4: continue
                ring = [c + (t * math.cos(2 * math.pi * i / seg) + s * math.sin(2 * math.pi * i / seg)) * rr for i in range(seg)]
                for i in range(seg):
                    self.tri(c, ring[i], ring[(i + 1) % seg], mat, dn)

    def lathe(self, c, prof, mat, seg=16, yaw0=0.0, smooth=True):
        """Révolution autour de l'axe vertical passant par c : prof = [(rayon, hauteur)] de bas en haut."""
        c = v3(c); P, I, UV = [], [], []
        m = len(prof)
        for i in range(seg + 1):
            a = yaw0 + 2 * math.pi * i / seg
            for (r, y) in prof:
                P.append(c + v3(math.cos(a) * r, y, math.sin(a) * r)); UV.append((a * max(r, 0.2), y))
        for i in range(seg):
            for j in range(m - 1):
                k = i * m + j; k2 = (i + 1) * m + j
                I += [(k, k + 1, k2), (k2, k + 1, k2 + 1)]
        if smooth:
            self.mesh(P, I, mat, None, UV)
        else:
            for t in I:
                self.tri(P[t[0]], P[t[1]], P[t[2]], mat, norm(P[t[0]] - c - UP * (P[t[0]] - c)[1] + UP * 1e-3))

    def prism(self, ring, y0, y1, mat, top=None, bottom=False, walls=True):
        """Prisme vertical sur un anneau 2D (x, z)."""
        ring = [tuple(p) for p in ring]
        cx = sum(p[0] for p in ring) / len(ring); cz = sum(p[1] for p in ring) / len(ring)
        if walls:
            for i in range(len(ring)):
                p, q = ring[i], ring[(i + 1) % len(ring)]
                mid = v3((p[0] + q[0]) / 2 - cx, 0, (p[1] + q[1]) / 2 - cz)
                e = v3(q[0] - p[0], 0, q[1] - p[1]); n = norm(v3(e[2], 0, -e[0]))
                if np.dot(n, mid) < 0: n = -n
                self.quad((p[0], y0, p[1]), (q[0], y0, q[1]), (q[0], y1, q[1]), (p[0], y1, p[1]), mat, n)
        if top is not False:
            self.poly([(p[0], y1, p[1]) for p in ring], top or mat, UP)
        if bottom:
            self.poly([(p[0], y0, p[1]) for p in ring], mat, -UP)

    def sweep(self, path, prof, mat, closed=False, up=UP):
        """Profil 2D (x latéral, y vertical) balayé le long d'une polyligne 3D, raccords en onglet."""
        path = [v3(p) for p in path]; n = len(path)
        frames = []
        for i in range(n):
            if closed:
                d0 = norm(path[i] - path[i - 1]); d1 = norm(path[(i + 1) % n] - path[i])
            else:
                d0 = norm(path[i] - path[max(i - 1, 0)]) if i > 0 else norm(path[1] - path[0])
                d1 = norm(path[min(i + 1, n - 1)] - path[i]) if i < n - 1 else d0
            t = norm(d0 + d1)
            side = norm(np.cross(t, up)); scale = 1.0 / max(0.35, float(np.dot(side, norm(np.cross(d1, up)))))
            frames.append((side * scale, up))
        rows = []
        m = len(prof)
        P, I, UV = [], [], []
        L = 0.0
        for i in range(n):
            if i > 0: L += np.linalg.norm(path[i] - path[i - 1])
            s, u = frames[i]
            for j, (x, y) in enumerate(prof):
                P.append(path[i] + s * x + u * y); UV.append((L, j * 0.1))
        cnt = n if closed else n - 1
        for i in range(cnt):
            i2 = (i + 1) % n
            for j in range(m - 1):
                a = i * m + j; b = i2 * m + j
                I.append((a, b, a + 1)); I.append((a + 1, b, b + 1))
        # facettes : sommets dupliqués par triangle (arêtes vives du profil)
        for t in I:
            self.tri(P[t[0]], P[t[1]], P[t[2]], mat)

    def collider(self, c, size, yaw=0.0):
        self.cols.append((tuple(map(float, c)), tuple(map(float, size)), float(yaw)))

    # ------------------------------------------------------------------ statistiques et export
    def tris(self, lod):
        return sum(len(B["i"]) // 3 for (lo, hi, g, m), B in self.parts.items() if lo <= lod <= hi)

    def export(self, path, lod, extra_nodes=None, with_cols=False):
        """Écrit un .glb : un nœud par groupe, une primitive par matériau (nommée par l'identifiant de fiche)."""
        groups = {}
        for (lo, hi, g, m), B in self.parts.items():
            if lo <= lod <= hi and B["i"]:
                groups.setdefault(g, {}).setdefault(m, []).append(B)
        bin_ = bytearray(); views = []; accs = []; meshes = []; nodes = []; mats = {}
        def add(arr, target, comp, typ, minmax=False):
            raw = arr.tobytes()
            while len(bin_) % 4: bin_.append(0)
            views.append({"buffer": 0, "byteOffset": len(bin_), "byteLength": len(raw), "target": target})
            bin_.extend(raw)
            acc = {"bufferView": len(views) - 1, "componentType": comp, "count": int(arr.shape[0]), "type": typ}
            if minmax:
                acc["min"] = arr.min(axis=0).tolist(); acc["max"] = arr.max(axis=0).tolist()
            accs.append(acc); return len(accs) - 1
        cols = self.cols if with_cols else []
        for g, bym in sorted(groups.items()):
            prims = []
            for m, bufs in sorted(bym.items()):
                p = np.concatenate([np.array(B["p"], np.float32).reshape(-1, 3) for B in bufs])
                nn = np.concatenate([np.array(B["n"], np.float32).reshape(-1, 3) for B in bufs])
                uv = np.concatenate([np.array(B["uv"], np.float32).reshape(-1, 2) for B in bufs])
                off = 0; ii = []
                for B in bufs:
                    ii.append(np.array(B["i"], np.uint32) + off); off += len(B["p"]) // 3
                ii = np.concatenate(ii)
                # soudure des sommets identiques (position, normale, UV) : fichiers plus légers, cache de sommets
                key = np.round(np.hstack([p, nn * 1000, uv * 100]).astype(np.float64), 3)
                _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
                p, nn, uv = p[first], nn[first], uv[first]; ii = inv.reshape(-1).astype(np.uint32)[ii]
                if m not in mats: mats[m] = len(mats)
                prims.append({"attributes": {"POSITION": add(p, 34962, 5126, "VEC3", True), "NORMAL": add(nn, 34962, 5126, "VEC3"),
                                             "TEXCOORD_0": add(uv, 34962, 5126, "VEC2")},
                              "indices": add(ii, 34963, 5125, "SCALAR"), "material": mats[m]})
            meshes.append({"name": g, "primitives": prims}); nodes.append({"name": g, "mesh": len(meshes) - 1})
        if cols:
            k = Kit()
            for c, s, yaw in cols: k.box(c, s, "collision", yaw)
            B = k.parts[(0, 2, "static", "collision")]
            p = np.array(B["p"], np.float32).reshape(-1, 3); ii = np.array(B["i"], np.uint32)
            mats.setdefault("collision", len(mats))
            meshes.append({"name": "collision", "primitives": [{"attributes": {"POSITION": add(p, 34962, 5126, "VEC3", True)},
                                                                  "indices": add(ii, 34963, 5125, "SCALAR"), "material": mats["collision"]}]})
            nodes.append({"name": "collision-colonly", "mesh": len(meshes) - 1})
        materials = [None] * len(mats)
        for m, i in mats.items():
            materials[i] = {"name": m, "pbrMetallicRoughness": {"baseColorFactor": [0.7, 0.7, 0.7, 1.0], "metallicFactor": 0.0, "roughnessFactor": 0.8}}
        doc = {"asset": {"version": "2.0", "generator": "tram-sim tools/models/meshkit.py"}, "scene": 0,
               "scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes, "meshes": meshes, "materials": materials,
               "accessors": accs, "bufferViews": views, "buffers": [{"byteLength": len(bin_)}]}
        js = json.dumps(doc, separators=(",", ":")).encode()
        while len(js) % 4: js += b" "
        while len(bin_) % 4: bin_.append(0)
        out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bin_))
        out += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(bin_), 0x004E4942) + bytes(bin_)
        open(path, "wb").write(out)
        return sum(len(B["i"]) // 3 for g in groups.values() for bl in g.values() for B in bl)


def translate(k: Kit, d):
    """Décale toute la géométrie (et les collisions) de -d (passage au repère local de l'ancre)."""
    d = np.asarray(d, float)
    for B in k.parts.values():
        p = np.array(B["p"], float).reshape(-1, 3) - d
        B["p"] = p.reshape(-1).tolist()
    k.cols = [(tuple(np.array(c) - d), s, y) for c, s, y in k.cols]
