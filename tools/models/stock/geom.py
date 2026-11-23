"""Noyau géométrique des rames HD (numpy, sans Blender) : hiérarchie de nœuds nommés (pivots d'animation),
primitives lissées à UV explicites, écriture glTF 2.0 binaire (.glb) avec matériaux PBR et textures externes
partagées entre LOD. Repère du jeu : Y haut (0 = rail), -Z = avant, +X = droite.

Les sommets sont donnés dans le repère de la RAME (ou du module courant, voir Builder.frame) ; à l'export ils
sont ramenés dans le repère local de leur nœud (translation pure : les pivots n'ont pas de rotation)."""
import json, math, struct
import numpy as np

UP = np.array([0.0, 1.0, 0.0])


def nz(v):
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-12)


class Builder:
    def __init__(self, name="root"):
        self.nodes = {}          # name -> {parent, pos(global np3), extras}
        self.order = []
        self.geo = {}            # (node, mat) -> list of (P, N, UV, I)
        self.cur = None
        self.uvf = None          # fonction UV par défaut (P, N) -> UV
        self.mats = {}           # nom -> définition glTF (voir material())
        self.images = {}         # uri -> index
        self.base = np.zeros(3)  # origine du fichier (repère dans lequel les nœuds racines sont exprimés)

    # ---------------------------------------------------------------- nœuds
    def node(self, name, parent=None, pos=(0, 0, 0), select=True, extras=None, rot=None):
        """rot : matrice 3×3 (colonnes = axes locaux X, Y, Z exprimés dans le repère rame), défaut identité."""
        if name in self.nodes:
            raise ValueError("nœud en double : " + name)
        self.nodes[name] = {"parent": parent, "pos": np.array(pos, float), "extras": extras or {},
                            "rot": np.eye(3) if rot is None else np.asarray(rot, float)}
        self.order.append(name)
        if select: self.cur = name
        return name

    def use(self, name):
        self.cur = name
        return name

    # ---------------------------------------------------------------- matériaux
    def material(self, name, **kw):
        """kw : color (rgba 0..1), rough, metal, tex (uri couleur), normal (uri), orm (uri), emissive (rgb),
        emissive_strength, alpha ('OPAQUE'|'BLEND'|'MASK'), double, clearcoat (0..1), clearcoat_rough, extras."""
        self.mats.setdefault(name, kw)
        return name

    # ---------------------------------------------------------------- ajout brut
    def add(self, P, N, UV, I, mat, node=None):
        node = node or self.cur
        assert node in self.nodes, node
        P = np.asarray(P, np.float64).reshape(-1, 3); N = np.asarray(N, np.float64).reshape(-1, 3)
        UV = np.asarray(UV, np.float64).reshape(-1, 2); I = np.asarray(I, np.int64).reshape(-1, 3)
        if len(I) == 0: return
        # orientation des triangles alignée sur les normales fournies (culling cohérent avec l'éclairage)
        fn = np.cross(P[I[:, 1]] - P[I[:, 0]], P[I[:, 2]] - P[I[:, 0]])
        bad = (fn * (N[I[:, 0]] + N[I[:, 1]] + N[I[:, 2]])).sum(1) < 0
        if bad.any():
            I = I.copy(); I[bad] = I[bad][:, ::-1]
        self.geo.setdefault((node, mat), []).append((P, N, UV, I))

    def _uv(self, P, N, uv=None):
        if uv is not None:
            return np.asarray(uv, float).reshape(-1, 2)
        if self.uvf is not None:
            return self.uvf(P, N)
        return metric_uv(P, N)

    # ---------------------------------------------------------------- grille lissée
    def grid(self, G, mat, uv=None, closed_u=False, flip=False, smooth=True):
        """G : tableau (R, C, 3) de points ; triangles entre lignes/colonnes consécutives. uv : (R, C, 2) ou None."""
        G = np.asarray(G, float); R, C, _ = G.shape
        if closed_u:
            G = np.concatenate([G, G[:, :1]], axis=1)
            if uv is not None: uv = np.concatenate([uv, uv[:, :1] + (uv[:, -1:] - uv[:, -2:-1])], axis=1)
            C += 1
        idx = np.arange(R * C).reshape(R, C)
        a = idx[:-1, :-1].ravel(); b = idx[1:, :-1].ravel(); c = idx[1:, 1:].ravel(); d = idx[:-1, 1:].ravel()
        I = np.concatenate([np.stack([a, b, c], 1), np.stack([a, c, d], 1)])
        if flip: I = I[:, ::-1]
        P = G.reshape(-1, 3)
        # suppression des triangles dégénérés
        e = np.cross(P[I[:, 1]] - P[I[:, 0]], P[I[:, 2]] - P[I[:, 0]])
        I = I[np.linalg.norm(e, axis=1) > 1e-10]
        if not smooth:
            return self.tris(P[I.ravel()].reshape(-1, 3, 3), mat, uv=None if uv is None else np.asarray(uv).reshape(-1, 2)[I.ravel()])
        N = vertex_normals(P, I)
        UV = np.asarray(uv, float).reshape(-1, 2) if uv is not None else self._uv(P, N)
        self.add(P, N, UV, I, mat)

    def tris(self, T, mat, uv=None):
        """Triangles à facettes : T (n, 3, 3)."""
        T = np.asarray(T, float).reshape(-1, 3, 3)
        n = nz(np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]))
        P = T.reshape(-1, 3); N = np.repeat(n, 3, axis=0)
        UV = self._uv(P, N) if uv is None else np.asarray(uv, float).reshape(-1, 2)
        self.add(P, N, UV, np.arange(len(P)).reshape(-1, 3), mat)

    def quad(self, a, b, c, d, mat, uv=None):
        """Quadrilatère a-b-c-d (sens trigonométrique vu de la face avant)."""
        P = np.array([a, b, c, d], float)
        n = nz(np.cross(P[1] - P[0], P[2] - P[0]) + np.cross(P[2] - P[0], P[3] - P[0]))
        N = np.tile(n, (4, 1))
        UV = self._uv(P, N) if uv is None else np.asarray(uv, float)
        self.add(P, N, UV, [[0, 1, 2], [0, 2, 3]], mat)

    def fan(self, ring, mat, normal=None, uv=None):
        """Polygone convexe (ou étoilé depuis son centre) en éventail."""
        ring = np.asarray(ring, float); c = ring.mean(axis=0)
        P = np.vstack([c, ring]); n = len(ring)
        I = [[0, 1 + i, 1 + (i + 1) % n] for i in range(n)]
        nn = normal if normal is not None else nz(sum(np.cross(ring[i] - c, ring[(i + 1) % n] - c) for i in range(n)))
        if normal is not None:
            t = np.cross(ring[0] - c, ring[1] - c)
            if np.dot(t, normal) < 0: I = [[a, cc, b] for a, b, cc in I]
        N = np.tile(nz(np.asarray(nn, float)), (n + 1, 1))
        UV = self._uv(P, N) if uv is None else np.asarray(uv, float)
        self.add(P, N, UV, I, mat)

    # ---------------------------------------------------------------- solides
    def box(self, c, size, mat, basis=None, uv_scale=1.0):
        """Pavé à faces planes. basis = (X, Y, Z) axes unitaires (défaut : repère monde)."""
        c = np.asarray(c, float); hx, hy, hz = np.asarray(size, float) / 2
        X, Y, Z = (np.eye(3) if basis is None else np.asarray(basis, float))
        faces = [(X, Y, Z, hx, hy, hz), (-X, Z, Y, hx, hz, hy), (Y, Z, X, hy, hz, hx), (-Y, X, Z, hy, hx, hz),
                 (Z, X, Y, hz, hx, hy), (-Z, Y, X, hz, hy, hx)]
        for n, u, v, dn, du, dv in faces:
            o = c + n * dn
            P = np.array([o - u * du - v * dv, o + u * du - v * dv, o + u * du + v * dv, o - u * du + v * dv])
            if np.dot(np.cross(P[1] - P[0], P[2] - P[0]), n) < 0: P = P[::-1]
            uv = np.array([[0, 0], [2 * du, 0], [2 * du, 2 * dv], [0, 2 * dv]]) * uv_scale
            if np.dot(np.cross(P[1] - P[0], P[2] - P[0]), n) < 0: uv = uv[::-1]
            self.add(P, np.tile(n, (4, 1)), uv, [[0, 1, 2], [0, 2, 3]], mat)

    def rbox(self, c, size, r, mat, basis=None, seg=3, caps=True, uv=None):
        """Pavé à arêtes arrondies autour de son axe Z local (profil rectangle arrondi extrudé, faces Z planes)."""
        c = np.asarray(c, float); sx, sy, sz = size
        X, Y, Z = (np.eye(3) if basis is None else np.asarray(basis, float))
        prof = rounded_rect(sx, sy, min(r, sx / 2 - 1e-4, sy / 2 - 1e-4), seg)
        self.prism(prof, -sz / 2, sz / 2, mat, origin=c, basis=(X, Y, Z), caps=caps)

    def prism(self, prof, z0, z1, mat, origin=(0, 0, 0), basis=None, caps=True, smooth=True, cap_mat=None):
        """Profil 2D fermé (x, y) (sens trigonométrique) extrudé selon Z local de z0 à z1."""
        o = np.asarray(origin, float); X, Y, Z = (np.eye(3) if basis is None else np.asarray(basis, float))
        prof = np.asarray(prof, float); n = len(prof)
        ring = lambda z: o + prof[:, :1] * X + prof[:, 1:2] * Y + z * Z
        A = ring(z0); B = ring(z1)
        per = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(np.vstack([prof, prof[:1]]), axis=0), axis=1))])
        if smooth:
            # normales 2D lissées du profil ; arêtes vives si l'angle dépasse 50°
            e_prev = prof - np.roll(prof, 1, 0); e_next = np.roll(prof, -1, 0) - prof
            np_ = nz(np.stack([e_prev[:, 1], -e_prev[:, 0]], 1)); nn_ = nz(np.stack([e_next[:, 1], -e_next[:, 0]], 1))
            sharp = (np_ * nn_).sum(1) < math.cos(math.radians(50))
            P = []; N = []; U = []; I = []
            for i in range(n):
                j = (i + 1) % n
                ni = nn_[i] if sharp[i] else nz(np_[i] + nn_[i]); nj = np_[j] if sharp[j] else nz(np_[j] + nn_[j])
                Ni = ni[0] * X + ni[1] * Y; Nj = nj[0] * X + nj[1] * Y
                b = len(P)
                P += [A[i], A[j], B[j], B[i]]; N += [Ni, Nj, Nj, Ni]
                U += [[per[i], z0], [per[i + 1], z0], [per[i + 1], z1], [per[i], z1]]
                I += [[b, b + 1, b + 2], [b, b + 2, b + 3]]
            self.add(P, N, U, I, mat)
        if caps:
            cm = cap_mat or mat
            for R, nrm in ((A, -Z), (B, Z)):
                self.fan(R, cm, normal=nrm, uv=np.vstack([prof.mean(0), prof]))

    def cyl(self, a, b, r, mat, seg=12, caps=True, r2=None, cap_mat=None):
        a = np.asarray(a, float); b = np.asarray(b, float); d = nz(b - a); r2 = r if r2 is None else r2
        t = nz(np.cross(d, [1, 0, 0] if abs(d[0]) < 0.9 else [0, 0, 1])); s = np.cross(d, t)
        ang = np.linspace(0, 2 * math.pi, seg + 1)
        o = np.cos(ang)[:, None] * t + np.sin(ang)[:, None] * s
        L = np.linalg.norm(b - a)
        G = np.stack([a + o * r, b + o * r2])
        circ = ang * (r + r2) / 2
        uv = np.stack([np.stack([circ, np.zeros_like(circ)], 1), np.stack([circ, np.full_like(circ, L)], 1)])
        self.grid(G, mat, uv=uv, flip=True)
        if caps:
            for c, rr, dn in ((a, r, -d), (b, r2, d)):
                if rr > 1e-4:
                    self.fan(c + o[:-1] * rr, cap_mat or mat, normal=dn,
                             uv=np.vstack([[0.5, 0.5], 0.5 + 0.5 * np.stack([np.cos(ang[:-1]), np.sin(ang[:-1])], 1)]))

    def tube(self, path, r, mat, seg=8, caps=False):
        """Tube lissé le long d'une polyligne (repères de transport parallèle)."""
        path = np.asarray(path, float); n = len(path)
        T = np.zeros_like(path)
        T[1:-1] = nz(path[2:] - path[:-2]); T[0] = nz(path[1] - path[0]); T[-1] = nz(path[-1] - path[-2])
        ref = np.array([0, 1, 0]) if abs(T[0][1]) < 0.9 else np.array([1, 0, 0])
        Nn = nz(np.cross(T[0], ref)); rings = []
        ang = np.linspace(0, 2 * math.pi, seg + 1)
        for i in range(n):
            if i > 0:
                Nn = nz(Nn - T[i] * np.dot(Nn, T[i]))
            Bn = np.cross(T[i], Nn)
            rings.append(path[i] + (np.cos(ang)[:, None] * Nn + np.sin(ang)[:, None] * Bn) * r)
        L = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(path, axis=0), axis=1))])
        uv = np.stack(np.meshgrid(ang * r, L), -1)
        self.grid(np.array(rings), mat, uv=uv, flip=True)
        if caps:
            self.fan(rings[0][:-1], mat, normal=-T[0]); self.fan(rings[-1][:-1], mat, normal=T[-1])

    def lathe(self, c, axis, prof, mat, seg=16, uv=None):
        """Révolution du profil [(rayon, hauteur)] autour de l'axe (c, axis)."""
        c = np.asarray(c, float); d = nz(np.asarray(axis, float))
        t = nz(np.cross(d, [1, 0, 0] if abs(d[0]) < 0.9 else [0, 0, 1])); s = np.cross(d, t)
        ang = np.linspace(0, 2 * math.pi, seg + 1)
        prof = np.asarray(prof, float)
        G = np.array([[c + d * h + (math.cos(a) * t + math.sin(a) * s) * r for a in ang] for r, h in prof])
        UVg = np.array([[[a * max(r, 0.01), h] for a in ang] for r, h in prof])
        self.grid(G, mat, uv=UVg, flip=True)

    # ---------------------------------------------------------------- simplification des appels de rendu
    def remap(self, keep_mat, target_mat, uv_of):
        """Remplace les matériaux non conservés par target_mat (UV constantes = pastille de l'atlas uv_of(mat))."""
        new = {}
        for (node, m), parts in self.geo.items():
            if keep_mat(m) or m == target_mat:
                new.setdefault((node, m), []).extend(parts); continue
            uv = np.asarray(uv_of(m), float)
            for P, N, UV, I in parts:
                new.setdefault((node, target_mat), []).append((P, N, np.tile(uv, (len(P), 1)), I))
        self.geo = new

    def merge_into_parents(self, keep_node):
        """Déplace la géométrie des nœuds non conservés vers leur plus proche ancêtre conservé (racine incluse)."""
        new = {}
        for (node, m), parts in self.geo.items():
            n = node
            while not keep_node(n) and self.nodes[n]["parent"] is not None:
                n = self.nodes[n]["parent"]
            new.setdefault((n, m), []).extend(parts)
        self.geo = new
        used = {n for (n, m) in self.geo}
        def needed(n):
            return keep_node(n) or n in used or any(self.nodes[c]["parent"] == n and needed(c) for c in self.order)
        self.order = [n for n in self.order if needed(n)]
        for n in list(self.nodes):
            if n not in self.order: del self.nodes[n]

    # ---------------------------------------------------------------- statistiques
    def tri_count(self, prefix=None):
        n = 0
        for (node, m), parts in self.geo.items():
            if prefix is None or self.is_under(node, prefix):
                n += sum(len(p[3]) for p in parts)
        return n

    def is_under(self, node, anc):
        while node is not None:
            if node == anc: return True
            node = self.nodes[node]["parent"]
        return False

    # ---------------------------------------------------------------- export
    def export(self, path, generator="tram-sim tools/models/stock", keep_empty=True):
        bin_ = bytearray(); views = []; accs = []
        def add(arr, target, comp, typ, minmax=False):
            raw = arr.tobytes()
            while len(bin_) % 4: bin_.append(0)
            v = {"buffer": 0, "byteOffset": len(bin_), "byteLength": len(raw)}
            if target: v["target"] = target
            views.append(v); bin_.extend(raw)
            acc = {"bufferView": len(views) - 1, "componentType": comp, "count": int(arr.shape[0]), "type": typ}
            if minmax:
                acc["min"] = arr.min(axis=0).tolist(); acc["max"] = arr.max(axis=0).tolist()
            accs.append(acc); return len(accs) - 1
        mat_idx = {}; meshes = []; node_mesh = {}
        by_node = {}
        for (node, m), parts in self.geo.items():
            by_node.setdefault(node, []).append((m, parts))
        for node, lst in by_node.items():
            origin = self.nodes[node]["pos"]; R = self.nodes[node]["rot"]
            prims = []
            for m, parts in sorted(lst, key=lambda x: x[0]):
                P = (np.concatenate([p[0] for p in parts]) - origin) @ R
                N = np.concatenate([p[1] for p in parts]) @ R; UV = np.concatenate([p[2] for p in parts])
                off = 0; II = []
                for p in parts:
                    II.append(p[3] + off); off += len(p[0])
                I = np.concatenate(II)
                N = nz(N)
                key = np.round(np.hstack([P * 1e4, N * 1e3, UV * 1e4]), 0)
                _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
                P, N, UV = P[first], N[first], UV[first]; I = inv.reshape(-1)[I]
                if m not in mat_idx: mat_idx[m] = len(mat_idx)
                it = (np.uint16, 5123) if len(P) < 65535 else (np.uint32, 5125)
                prims.append({"attributes": {"POSITION": add(P.astype(np.float32), 34962, 5126, "VEC3", True),
                                             "NORMAL": add(N.astype(np.float32), 34962, 5126, "VEC3"),
                                             "TEXCOORD_0": add(UV.astype(np.float32), 34962, 5126, "VEC2")},
                              "indices": add(I.reshape(-1).astype(it[0]), 34963, it[1], "SCALAR"), "material": mat_idx[m]})
            meshes.append({"name": node, "primitives": prims}); node_mesh[node] = len(meshes) - 1
        names = [n for n in self.order if keep_empty or n in node_mesh or self._has_desc_mesh(n, node_mesh)]
        nidx = {n: i for i, n in enumerate(names)}
        nodes = []
        for n in names:
            nd = self.nodes[n]; par = nd["parent"]
            ppos = self.nodes[par]["pos"] if par else self.base
            prot = self.nodes[par]["rot"] if par else np.eye(3)
            e = {"name": n}
            t = prot.T @ (nd["pos"] - ppos)
            if np.linalg.norm(t) > 1e-9: e["translation"] = [round(float(x), 6) for x in t]
            Rr = prot.T @ nd["rot"]
            if np.abs(Rr - np.eye(3)).max() > 1e-9: e["rotation"] = [round(float(x), 7) for x in mat2quat(Rr)]
            if n in node_mesh: e["mesh"] = node_mesh[n]
            if nd["extras"]: e["extras"] = nd["extras"]
            nodes.append(e)
        for n in names:
            par = self.nodes[n]["parent"]
            if par:
                nodes[nidx[par]].setdefault("children", []).append(nidx[n])
        roots = [nidx[n] for n in names if not self.nodes[n]["parent"]]
        images = []; textures = []; tex_of = {}
        def tex(uri):
            if uri not in tex_of:
                images.append({"uri": uri}); textures.append({"source": len(images) - 1, "sampler": 0})
                tex_of[uri] = len(textures) - 1
            return {"index": tex_of[uri]}
        materials = [None] * len(mat_idx); used_ext = set()
        for m, i in mat_idx.items():
            d = self.mats.get(m, {})
            col = list(d.get("color", (0.7, 0.7, 0.7, 1.0)))
            if len(col) == 3: col.append(1.0)
            pbr = {"baseColorFactor": [round(float(c), 4) for c in col], "metallicFactor": float(d.get("metal", 0.0)),
                   "roughnessFactor": float(d.get("rough", 0.6))}
            if d.get("tex"): pbr["baseColorTexture"] = tex(d["tex"])
            if d.get("orm"): pbr["metallicRoughnessTexture"] = tex(d["orm"])
            mm = {"name": m, "pbrMetallicRoughness": pbr}
            if d.get("normal"): mm["normalTexture"] = tex(d["normal"])
            if d.get("orm"): mm["occlusionTexture"] = tex(d["orm"])
            if d.get("emissive") is not None:
                mm["emissiveFactor"] = [float(min(1.0, c)) for c in d["emissive"]]
                if d.get("emissive_strength", 1.0) != 1.0:
                    mm.setdefault("extensions", {})["KHR_materials_emissive_strength"] = {"emissiveStrength": float(d["emissive_strength"])}
                    used_ext.add("KHR_materials_emissive_strength")
                if d.get("emissive_tex"): mm["emissiveTexture"] = tex(d["emissive_tex"])
            if d.get("alpha"): mm["alphaMode"] = d["alpha"]
            if d.get("double"): mm["doubleSided"] = True
            if d.get("clearcoat"):
                mm.setdefault("extensions", {})["KHR_materials_clearcoat"] = {"clearcoatFactor": float(d["clearcoat"]),
                                                                              "clearcoatRoughnessFactor": float(d.get("clearcoat_rough", 0.08))}
                used_ext.add("KHR_materials_clearcoat")
            if d.get("extras"): mm["extras"] = d["extras"]
            materials[i] = mm
        doc = {"asset": {"version": "2.0", "generator": generator}, "scene": 0, "scenes": [{"nodes": roots}],
               "nodes": nodes, "meshes": meshes, "materials": materials, "accessors": accs, "bufferViews": views,
               "buffers": [{"byteLength": len(bin_)}]}
        if images:
            doc["images"] = images; doc["textures"] = textures
            doc["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
        if used_ext: doc["extensionsUsed"] = sorted(used_ext)
        js = json.dumps(doc, separators=(",", ":"), ensure_ascii=False).encode()
        while len(js) % 4: js += b" "
        while len(bin_) % 4: bin_.append(0)
        out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bin_))
        out += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(bin_), 0x004E4942) + bytes(bin_)
        open(path, "wb").write(out)
        return sum(len(p[3]) for parts in self.geo.values() for p in parts)

    def _has_desc_mesh(self, n, node_mesh):
        return any(k in node_mesh and self.is_under(k, n) for k in node_mesh)


# -------------------------------------------------------------------- utilitaires
def mat2quat(R):
    """Quaternion glTF (x, y, z, w) d'une matrice de rotation."""
    t = np.trace(R)
    if t > 0:
        s = math.sqrt(t + 1.0) * 2; w = 0.25 * s
        x = (R[2, 1] - R[1, 2]) / s; y = (R[0, 2] - R[2, 0]) / s; z = (R[1, 0] - R[0, 1]) / s
    elif R[0, 0] > R[1, 1] and R[0, 0] > R[2, 2]:
        s = math.sqrt(1.0 + R[0, 0] - R[1, 1] - R[2, 2]) * 2
        w = (R[2, 1] - R[1, 2]) / s; x = 0.25 * s; y = (R[0, 1] + R[1, 0]) / s; z = (R[0, 2] + R[2, 0]) / s
    elif R[1, 1] > R[2, 2]:
        s = math.sqrt(1.0 + R[1, 1] - R[0, 0] - R[2, 2]) * 2
        w = (R[0, 2] - R[2, 0]) / s; x = (R[0, 1] + R[1, 0]) / s; y = 0.25 * s; z = (R[1, 2] + R[2, 1]) / s
    else:
        s = math.sqrt(1.0 + R[2, 2] - R[0, 0] - R[1, 1]) * 2
        w = (R[1, 0] - R[0, 1]) / s; x = (R[0, 2] + R[2, 0]) / s; y = (R[1, 2] + R[2, 1]) / s; z = 0.25 * s
    q = np.array([x, y, z, w]); return q / np.linalg.norm(q)


def frame_from_z(zaxis, up=(0, 1, 0)):
    """Repère (colonnes X, Y, Z) dont Z = zaxis et Y au plus près de up."""
    Z = nz(np.asarray(zaxis, float)); X = np.cross(np.asarray(up, float), Z)
    if np.linalg.norm(X) < 1e-6: X = np.cross([1.0, 0, 0], Z)
    X = nz(X); Y = np.cross(Z, X)
    return np.stack([X, Y, Z], 1)


def rot_x(deg):
    a = math.radians(deg); c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def rot_y(deg):
    a = math.radians(deg); c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def vertex_normals(P, I):
    fn = np.cross(P[I[:, 1]] - P[I[:, 0]], P[I[:, 2]] - P[I[:, 0]])
    N = np.zeros_like(P)
    for k in range(3): np.add.at(N, I[:, k], fn)
    # sommets confondus (coutures) : on moyenne par position
    key = np.round(P * 1e5).astype(np.int64)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    acc = np.zeros((inv.max() + 1, 3)); np.add.at(acc, inv, N)
    N2 = acc[inv]
    # ne pas fusionner à travers des arêtes vives (> 60°)
    ok = (nz(N2) * nz(N)).sum(1) > 0.5
    N = np.where(ok[:, None], N2, N)
    return nz(N)


def metric_uv(P, N):
    """UV métriques : faces horizontales -> (x, z), parois -> (abscisse horizontale, y)."""
    P = np.asarray(P, float); N = np.asarray(N, float)
    hor = np.abs(N[:, 1]) > 0.7
    t = nz(np.cross(UP, N + (np.abs(N[:, 1:2]) > 0.999) * np.array([1e-3, 0, 0])))
    u = np.where(hor, P[:, 0], (P * t).sum(1)); v = np.where(hor, P[:, 2], P[:, 1])
    return np.stack([u, v], 1)


def rounded_rect(w, h, r, seg=3):
    pts = []
    cs = [(w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)]
    for cx, cy, a0 in cs:
        if r <= 1e-5:
            pts.append((cx, cy)); continue
        for k in range(seg + 1):
            a = math.radians(a0 + 90 * k / seg)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return np.array(pts)


def smooth_interp(pts, x):
    """Interpolation monotone (Hermite, pentes Fritsch-Carlson simplifiées) comme TramModel._sm."""
    pts = np.asarray(pts, float)
    xs, ys = pts[:, 0], pts[:, 1]
    x = np.asarray(x, float)
    if len(xs) == 1: return np.full_like(x, ys[0])
    d = np.diff(ys) / np.maximum(np.diff(xs), 1e-9)
    m = np.zeros_like(ys); m[0] = d[0]; m[-1] = d[-1]
    for i in range(1, len(ys) - 1):
        m[i] = 0.0 if d[i - 1] * d[i] <= 0 else 2.0 / (1.0 / d[i - 1] + 1.0 / d[i])
    out = np.empty_like(x)
    for k, xv in np.ndenumerate(x):
        if xv <= xs[0]: out[k] = ys[0]; continue
        if xv >= xs[-1]: out[k] = ys[-1]; continue
        i = min(np.searchsorted(xs, xv), len(xs) - 1)
        h = xs[i] - xs[i - 1]; t = (xv - xs[i - 1]) / h
        h00 = 2 * t ** 3 - 3 * t ** 2 + 1; h10 = t ** 3 - 2 * t ** 2 + t; h01 = -2 * t ** 3 + 3 * t ** 2; h11 = t ** 3 - t ** 2
        out[k] = h00 * ys[i - 1] + h10 * h * m[i - 1] + h01 * ys[i] + h11 * h * m[i]
    return out


def check_winding(B, thr=0.0):
    """Part des triangles dont l'orientation (ordre des sommets) contredit les normales de sommets, par (nœud, matériau)."""
    out = {}
    for (node, m), parts in B.geo.items():
        bad = tot = 0
        for P, N, UV, I in parts:
            fn = np.cross(P[I[:, 1]] - P[I[:, 0]], P[I[:, 2]] - P[I[:, 0]])
            vn = N[I[:, 0]] + N[I[:, 1]] + N[I[:, 2]]
            d = (fn * vn).sum(1)
            bad += int((d < thr).sum()); tot += len(I)
        if bad: out[(node, m)] = (bad, tot)
    return out
