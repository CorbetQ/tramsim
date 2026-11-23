"""Rame Citadis HD (extérieur, intérieur voyageurs, aménagement simplifié de cabine) depuis layout.Train.
Niveaux de détail q : 0 = LOD0 PC, 1 = LOD1 PC / LOD0 mobile (lod0_m), 2 = LOD1 mobile, 3 = LOD2, 4 = LOD3.
Nœuds et matériaux selon docs/refonte-visuelle/stock_manifest.md."""
import math
import numpy as np
from geom import Builder, nz, vertex_normals, frame_from_z, rot_y, rounded_rect
from layout import GAP, TUCK, WALL
from specs import hex2rgb, srgb2lin
import textures as TX

SEG = {0: 1.0, 1: 0.6, 2: 0.45, 3: 0.3, 4: 0.2}
BEV = 0.07        # longueur du congé d'extrémité de caisse
BEV_IN = 0.04     # rentrée du congé


def lin(h, a=1.0):
    return srgb2lin(hex2rgb(h)) + (a,)


SWATCH_FALLBACK = {"bogie_metal": "#3d4043", "wheel_steel": "#7d8083", "int_floor": "#62676b", "int_seat": "#3f4348",
                   "trim_alu": "#a9adb0", "trim_chrome": "#c4c7ca"}


def swatch_colors(B):
    """Couleurs sRGB des matériaux unis (pastilles de l'atlas pour les LOD fusionnés)."""
    out = {}
    for m, d in sorted(B.mats.items()):
        if m.startswith(("livery", "glass", "em_", "screen_")): continue
        out[m] = d.get("srgb") or SWATCH_FALLBACK.get(m, "#808080")
    return out


def swatch_uv(names):
    idx = {m: i for i, m in enumerate(sorted(names))}
    def uv(m):
        i = idx.get(m, 0)
        x = 800 + (i % 50) * 64 + 32; y = 1312 + (i // 50) * 64 + 32
        return (x / TX.AW, y / TX.AH)
    return uv


def materials(B, t, q, tex_tag):
    c = t.spec["colors"]; sp = t.spec
    _mat = B.material
    def material(name, **kw):
        col = kw.get("color")
        if col is not None and "tex" not in kw:
            kw["srgb"] = "#%02x%02x%02x" % tuple(int(round(255 * (x * 12.92 if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055))) for x in col[:3])
        return _mat(name, **kw)
    B.material = material
    liv = "textures/livery_%s.png" % tex_tag
    B.material("livery_" + sp["dir"], color=(1, 1, 1, 1), tex=liv, rough=0.32, clearcoat=1.0, clearcoat_rough=0.06,
               extras={"clearcoat": 1.0, "clearcoat_roughness": 0.06})
    for z in ("base", "front", "door", "roof", "skirt", "window"):
        cc = {"window": c["window"], "skirt": c["skirt"]}.get(z, c.get(z, c["base"]))
        B.material("paint_" + z, color=lin(cc), rough=0.35 if z != "skirt" else 0.6, clearcoat=0.8 if z not in ("skirt", "window") else 0.0)
    B.material("glass_side", color=(0.04, 0.05, 0.055, 0.5), rough=0.04, alpha="BLEND", double=True, metal=0.0)
    B.material("glass_door", color=(0.05, 0.06, 0.065, 0.42), rough=0.04, alpha="BLEND", double=True)
    B.material("glass_windshield", color=(0.04, 0.05, 0.055, 0.28), rough=0.03, alpha="BLEND", double=True)
    B.material("trim_black", color=lin("#151718"), rough=0.75)
    B.material("trim_rubber", color=lin("#202224"), rough=0.9)
    B.material("trim_alu", color=lin("#a9adb0"), rough=0.35, metal=1.0)
    B.material("trim_chrome", color=lin("#d0d3d6"), rough=0.15, metal=1.0)
    B.material("trim_grey", color=lin("#6c7175"), rough=0.5)
    B.material("bellows_rubber", color=lin("#26292b"), rough=0.85)
    B.material("bogie_metal", color=lin("#3a3d40"), rough=0.7, metal=0.6, tex="textures/metal_albedo.png",
               normal="textures/metal_normal.png", orm="textures/metal_orm.png")
    B.material("wheel_steel", color=lin("#8a8d90"), rough=0.4, metal=1.0, tex="textures/metal_albedo.png", normal="textures/metal_normal.png")
    B.material("roof_equipment", color=lin(c.get("roof", "#cfd3d5")), rough=0.45)
    B.material("roof_grille", color=lin("#2c2f31"), rough=0.6, metal=0.5)
    B.material("insulator", color=lin("#7a3b2a"), rough=0.3)
    B.material("panto_metal", color=lin("#5a5f63"), rough=0.4, metal=0.8)
    B.material("panto_carbon", color=lin("#1b1b1b"), rough=0.6)
    B.material("em_head", color=lin("#f4f4f0"), emissive=(1.0, 0.97, 0.9), emissive_strength=4.0, rough=0.1)
    B.material("em_tail", color=lin("#7a0a0a"), emissive=(1.0, 0.05, 0.03), emissive_strength=3.0, rough=0.1)
    B.material("em_dest", color=lin("#0c0c0c"), emissive=(0.02, 0.015, 0.0), rough=0.2)
    B.material("em_drl", color=lin("#9fe8d2"), emissive=(0.2, 1.0, 0.75), emissive_strength=2.0, rough=0.2)
    B.material("em_door", color=lin("#1a7a3c"), emissive=(0.1, 0.8, 0.3), emissive_strength=1.5)
    B.material("lamp_lens_off", color=lin("#dfe3e6"), rough=0.05, metal=0.2)
    if True:
        it = sp["interior"]; st = sp["seat"]
        B.material("int_wall", color=lin(it["wall"]), rough=0.45)
        B.material("int_ceiling", color=lin(it["ceiling"]), rough=0.55)
        B.material("int_floor", color=(1, 1, 1, 1), tex="textures/floor_albedo.png", normal="textures/floor_normal.png", rough=0.7)
        B.material("int_seat", color=(1, 1, 1, 1), tex="textures/fabric_%s.png" % st["fabric"], rough=0.95)
        B.material("int_seat_shell", color=lin(st["shell"]), rough=0.4)
        B.material("int_pole", color=lin(st["pole"]), rough=0.25, metal=1.0)
        B.material("int_accent", color=lin(st["pole_accent"]), rough=0.4)
        B.material("int_rail", color=lin("#c4c9cd"), rough=0.22, metal=1.0)
        B.material("int_dark", color=lin("#2a2d30"), rough=0.6)
        B.material("em_interior", color=lin("#f6f7f2"), emissive=(1.0, 0.98, 0.92), emissive_strength=1.5)
        B.material("screen_pis", color=lin("#0a0c0e"), emissive=(0.0, 0.0, 0.0), rough=0.15)
    B.material = _mat


def emit(B, G, N, UV, qmask, mat):
    """Quads (r, c) de la grille G (R, C, 3) où qmask (R-1, C-1) est vrai, normales et UV par sommet."""
    R, C = G.shape[:2]
    idx = np.arange(R * C).reshape(R, C)
    rr, cc = np.nonzero(qmask)
    if len(rr) == 0: return
    a = idx[rr, cc]; b = idx[rr + 1, cc]; c = idx[rr + 1, cc + 1]; d = idx[rr, cc + 1]
    I = np.concatenate([np.stack([a, b, c], 1), np.stack([a, c, d], 1)])
    P = G.reshape(-1, 3); Nn = N.reshape(-1, 3); U = UV.reshape(-1, 2)
    e = np.linalg.norm(np.cross(P[I[:, 1]] - P[I[:, 0]], P[I[:, 2]] - P[I[:, 0]]), axis=1)
    I = I[e > 1e-10]
    used, inv = np.unique(I.ravel(), return_inverse=True)
    B.add(P[used], Nn[used], U[used], inv.reshape(-1, 3), mat)


def grid_normals(G, flip=False, away=None, toward=None):
    """Normales lissées ; away/toward : point (ou axe z si seul x,y) dont elles doivent s'éloigner / se rapprocher."""
    N = _grid_normals(G, flip)
    ref = away if away is not None else toward
    if ref is not None:
        ref = np.asarray(ref, float)
        D = G - (ref if ref.shape == (3,) else np.array([ref[0], ref[1], 0.0]))
        if ref.shape != (3,): D[..., 2] = 0
        sgn = (N * D).sum(-1).mean()
        if (away is not None and sgn < 0) or (toward is not None and sgn > 0): N = -N
    return N


def _grid_normals(G, flip=False):
    R, C = G.shape[:2]
    idx = np.arange(R * C).reshape(R, C)
    a = idx[:-1, :-1].ravel(); b = idx[1:, :-1].ravel(); c = idx[1:, 1:].ravel(); d = idx[:-1, 1:].ravel()
    I = np.concatenate([np.stack([a, b, c], 1), np.stack([a, c, d], 1)])
    if flip: I = I[:, ::-1]
    return vertex_normals(G.reshape(-1, 3), I).reshape(R, C, 3)


class Citadis:
    def __init__(self, train, q, tex_tag="4k"):
        self.t = train; self.q = q; self.B = Builder()
        self.livmat = "livery_" + train.spec["dir"]
        materials(self.B, train, q, tex_tag)
        self.mod_nodes = []

    # ================================================================== assemblage
    def build(self):
        t, B, q = self.t, self.B, self.q
        for m in t.mods:
            name = "module_%02d" % m["i"]
            B.node(name, None, (0, 0, m["zc"])); self.mod_nodes.append(name)
            self.body(m)
            if m["front_cab"]: self.nose(m, m["zA"], -1, "A")
            if m["rear_cab"]: self.nose(m, m["zB"], 1, "B")
            self.doors(m)
            self.roof(m)
            if m["bogie_z"] is not None and q <= 3: self.bogie(m)
            if m["i"] < len(t.mods) - 1: self.bellows(m)
            if q <= 1: self.interior(m)
        if q >= 1: self.simplify()
        return B

    KEEP = ("module_", "door_", "panto_", "em_head", "em_tail", "em_dest", "em_drl", "sign_dest", "wiper_", "mirror_", "cab_proxy", "em_interior")

    def simplify(self):
        """LOD fusionnés : matériaux unis -> pastilles de l'atlas de livrée ; sous-nœuds statiques -> caisse."""
        B, q = self.B, self.q
        names = swatch_colors(B)
        uv = swatch_uv(names)
        keep_mat = lambda m: m.startswith(("glass", "em_", "screen_"))
        B.remap(keep_mat, self.livmat, uv)
        # un seul verre
        g = {}
        for (n, m), parts in B.geo.items():
            mm = "glass_side" if m.startswith("glass") else m
            g.setdefault((n, mm), []).extend(parts)
        B.geo = g
        keep = self.KEEP if q <= 2 else ("module_", "em_head", "em_tail", "em_dest", "sign_dest", "panto_")
        if q >= 4: keep = ("module_", "em_head", "em_tail", "sign_dest")
        B.merge_into_parents(lambda n: n.startswith(keep))

    # ================================================================== caisse
    def side_uv(self, P):
        return TX.side_uv(self.t.zf(P[:, 2]), P[:, 1], self.t.L)

    def body(self, m):
        t, B, q = self.t, self.B, self.q
        name = "module_%02d" % m["i"]; B.use(name)
        zA, zB = m["zA"], m["zB"]
        openings_w = m["windows"] if q <= 1 else []
        openings_d = [(d["z0"], d["z1"]) for d in m["doors"]] if q <= 2 else []
        y_lo = 0.42
        nrow = {0: 14, 1: 7, 2: 5, 3: 3, 4: 2}[q]
        ys = set(np.round(np.linspace(y_lo, t.cant, nrow), 4)) | {t.wb, t.wt, t.door_top, t.cant, y_lo}
        ys = np.array(sorted(ys))
        zs = {zA, zB} | set(self.bev_breaks(m))
        for a, b in openings_w + openings_d: zs |= {a, b}
        zs = np.array(sorted(z for z in zs if zA - 1e-6 <= z <= zB + 1e-6))
        Zc = (zs[:-1] + zs[1:]) / 2; Yc = (ys[:-1] + ys[1:]) / 2
        ZZ, YY = np.meshgrid(Zc, Yc)
        hole = np.zeros_like(ZZ, bool)
        for a, b in openings_w: hole |= (ZZ > a) & (ZZ < b) & (YY > t.wb) & (YY < t.wt)
        for a, b in openings_d: hole |= (ZZ > a) & (ZZ < b) & (YY > y_lo) & (YY < t.door_top)
        Zg, Yg = np.meshgrid(zs, ys)
        for s in (1, -1):
            X = s * t.prof_x(Yg)
            G = self.bev(np.stack([X, Yg, Zg], -1), m)
            N = grid_normals(G, away=(0.0, 1.6))
            if s < 0: G2, N2, H = G[:, ::-1], N[:, ::-1], hole[:, ::-1]
            else: G2, N2, H = G, N, hole
            UV = TX.side_uv(t.zf(G2[..., 2]), G2[..., 1], t.L)
            emit(B, G2, N2, UV, ~H, self.livmat)
            # habillage intérieur
            if q <= 1:
                Xi = s * (t.prof_x(Yg) - WALL)
                ys_in = Yg.copy()
                Gi = np.stack([Xi, ys_in, Zg], -1)
                Ni = -N
                Gi2, Ni2, Hi = (Gi, Ni, hole) if s < 0 else (Gi[:, ::-1], Ni[:, ::-1], hole[:, ::-1])
                UVi = np.stack([Gi2[..., 2], Gi2[..., 1]], -1)
                emit(B, Gi2, Ni2, UVi, ~Hi, "int_wall")
                # bas de l'habillage : du plancher à y_lo
                self.quadv((s * (t.prof_x(y_lo) - WALL), y_lo), (s * (t.prof_x(y_lo) - WALL), t.floor), zA, zB, "int_wall", s < 0)
            # tableaux des baies et des portes
            for a, b in openings_w:
                self.reveal(s, a, b, t.wb, t.wt, "trim_black")
                gx = lambda y: s * (t.prof_x(y) - 0.014)
                yy = np.linspace(t.wb, t.wt, 4)
                Gg = np.array([[[gx(y), y, z] for z in ((b, a) if s > 0 else (a, b))] for y in yy])
                Ng = grid_normals(Gg, away=(0.0, 1.6))
                emit(B, Gg, Ng, np.stack([Gg[..., 2], Gg[..., 1]], -1), np.ones((3, 1), bool), "glass_side")
                if q == 0:   # joint périphérique
                    for (y0, y1, z0, z1) in ((t.wb, t.wb + 0.025, a, b), (t.wt - 0.025, t.wt, a, b), (t.wb, t.wt, a, a + 0.025), (t.wb, t.wt, b - 0.025, b)):
                        xo = s * (t.prof_x((y0 + y1) / 2) - 0.006)
                        self.quadv((xo, y0), (xo, y1), z0, z1, "trim_rubber", s < 0)
            for a, b in openings_d:
                self.reveal(s, a, b, y_lo, t.door_top, "trim_grey")
        # bas de caisse rentrant (jupe) et seuils de porte
        nt = {0: 5, 1: 3, 2: 2, 3: 2, 4: 1}[q]
        yt = np.linspace(t.yb, y_lo, nt + 1)
        segs = []; cur = zA
        for a, b in sorted(openings_d):
            segs.append((cur, a, self.livmat)); segs.append((a, b, "trim_alu")); cur = b
        segs.append((cur, zB, self.livmat))
        for s in (1, -1):
            for a, b, mat in segs:
                if b - a < 1e-4: continue
                zl = sorted({a, b} | {z for z in self.bev_breaks(m) if a < z < b})
                Zg, Yg = np.meshgrid(zl, yt)
                G = self.bev(np.stack([s * t.prof_x(Yg), Yg, Zg], -1), m)
                N = grid_normals(G, away=(0.0, 1.6))
                UV = TX.side_uv(t.zf(Zg), Yg, t.L) if mat == self.livmat else np.stack([Zg, Yg * 4], -1)
                emit(B, G, N, UV, np.ones((nt, len(zl) - 1), bool), mat)
        # dessous
        x0 = t.hw - TUCK
        B.quad((-x0, t.yb, zA), (x0, t.yb, zA), (x0, t.yb, zB), (-x0, t.yb, zB), "trim_black")
        # pavillon : épaulements (livrée) + toit (peinture)
        nr = {0: 10, 1: 6, 2: 4, 3: 3, 4: 2}[q]
        a = np.linspace(0, math.pi / 2, nr + 1)
        ysh = t.cant + (t.h - t.cant) * np.sin(a)
        zl = sorted({zA, zB} | set(self.bev_breaks(m)))
        for s in (1, -1):
            xs = s * t.prof_x(ysh)
            G = self.bev(np.array([[[x, y, z] for x, y in zip(xs, ysh)] for z in zl]), m)
            N = grid_normals(G, away=(0.0, 1.6))
            emit(B, G, N, TX.side_uv(t.zf(G[..., 2]), G[..., 1], t.L), np.ones((len(zl) - 1, nr), bool), self.livmat)
        xr = float(t.prof_x(t.h))
        G = self.bev(np.array([[[xr, t.h, z], [-xr, t.h, z]] for z in zl]), m)
        N = grid_normals(G, away=(0.0, 1.6))
        emit(B, G, N, np.stack([G[..., 0], G[..., 2]], -1), np.ones((len(zl) - 1, 1), bool), "paint_roof")
        # collerettes d'extrémité (côté soufflet)
        for zz, d, isnose in ((zA, -1, m["front_cab"]), (zB, 1, m["rear_cab"])):
            if isnose or q >= 4: continue
            sec_o = t.section({0: 16, 1: 10}.get(q, 6), {0: 6, 1: 4}.get(q, 3))
            dv = sec_o - np.array([0, 1.6]); sec_o = sec_o - dv / np.linalg.norm(dv, axis=1, keepdims=True) * BEV_IN
            if q <= 1:
                sec_i = np.stack([sec_o[:, 0] * (1 - WALL / t.hw), t.floor + (sec_o[:, 1] - t.yb) * ((2.45 - t.floor) / (t.h - t.yb))], 1)
                ring_o = np.column_stack([sec_o, np.full(len(sec_o), zz)]); ring_i = np.column_stack([sec_i, np.full(len(sec_i), zz)])
                G = np.array([ring_o, ring_i]) if d > 0 else np.array([ring_i, ring_o])
                G = np.concatenate([G, G[:, :1]], 1)
                Nn = np.zeros_like(G); Nn[..., 2] = d
                emit(B, G, Nn, np.stack([G[..., 0], G[..., 1]], -1), np.ones((1, G.shape[1] - 1), bool), "trim_grey")
            else:
                ring = np.column_stack([sec_o, np.full(len(sec_o), zz)])
                B.fan(ring, "trim_grey", normal=np.array([0, 0, d], float))

    def bev_breaks(self, m):
        out = []
        if not m["front_cab"]: out.append(m["zA"] + BEV)
        if not m["rear_cab"]: out.append(m["zB"] - BEV)
        if self.q <= 1:
            if not m["front_cab"]: out.append(m["zA"] + BEV * 0.35)
            if not m["rear_cab"]: out.append(m["zB"] - BEV * 0.35)
        return out

    def bev(self, G, m):
        """Congé d'extrémité de caisse (côté soufflet) : rentrée radiale en quart de cercle sur BEV mètres."""
        if self.q >= 4: return G
        G = G.copy(); z = G[..., 2]
        t_ = np.zeros(z.shape)
        if not m["front_cab"]: t_ = np.maximum(t_, 1 - (z - m["zA"]) / BEV)
        if not m["rear_cab"]: t_ = np.maximum(t_, 1 - (m["zB"] - z) / BEV)
        t_ = np.clip(t_, 0, 1)
        ins = BEV_IN * (1 - np.sqrt(1 - t_ ** 2))
        d = G[..., :2] - np.array([0, 1.6]); d = d / np.maximum(np.linalg.norm(d, axis=-1, keepdims=True), 1e-9)
        G[..., :2] -= d * ins[..., None]
        return G

    def quadv(self, p0, p1, z0, z1, mat, flip):
        """Quad vertical entre (x, y) p0 et p1, de z0 à z1."""
        a = (p0[0], p0[1], z0); b = (p1[0], p1[1], z0); c = (p1[0], p1[1], z1); d = (p0[0], p0[1], z1)
        if flip: self.B.quad(a, b, c, d, mat)
        else: self.B.quad(d, c, b, a, mat)

    def reveal(self, s, z0, z1, y0, y1, mat):
        """Tableau d'ouverture (épaisseur de paroi) : 4 faces tournées vers l'ouverture."""
        t, B = self.t, self.B
        xo = lambda y: s * float(t.prof_x(y)); xi = lambda y: s * (float(t.prof_x(y)) - WALL)
        # appui (bas) : normale +Y ; linteau (haut) : -Y ; jambages : ±Z
        quads = [((xo(y0), y0, z0), (xo(y0), y0, z1), (xi(y0), y0, z1), (xi(y0), y0, z0), (0, 1, 0)),
                 ((xo(y1), y1, z0), (xi(y1), y1, z0), (xi(y1), y1, z1), (xo(y1), y1, z1), (0, -1, 0))]
        for a, b, c, d, n in quads:
            P = np.array([a, b, c, d]); nn = np.cross(P[1] - P[0], P[2] - P[0])
            if np.dot(nn, n) < 0: P = P[::-1]
            B.add(P, np.tile(n, (4, 1)), np.stack([P[:, 2], P[:, 0]], 1) * 4, [[0, 1, 2], [0, 2, 3]], mat)
        for zz, n in ((z0, 1), (z1, -1)):
            ys = np.linspace(y0, y1, 5)
            G = np.array([[[xo(y), y, zz], [xi(y), y, zz]] for y in ys])
            nn = np.zeros_like(G); nn[..., 2] = n
            P = G
            # orientation
            tst = np.cross(G[1, 0] - G[0, 0], G[1, 1] - G[0, 0])
            if np.sign(tst[2]) != np.sign(n): G = G[:, ::-1]
            emit(B, G, nn, np.stack([G[..., 1], G[..., 0]], -1) * 4, np.ones((4, 1), bool), mat)

    # ================================================================== nez
    def nose(self, m, zj, dirz, end):
        t, B, q = self.t, self.B, self.q
        mod = "module_%02d" % m["i"]; B.use(mod)
        G, S, part, ys = t.nose_grid(zj, dirz, q)
        N = grid_normals(G, away=(0, 1.4, zj - dirz * 4.0))
        R, C = G.shape[:2]
        sideUV = TX.side_uv(t.zf(G[..., 2]), G[..., 1], t.L)
        frontUV = TX.front_uv(G[..., 0] * (-dirz), G[..., 1])
        pc = part.astype(bool)
        qfront = np.tile(pc[:-1] & pc[1:], (R - 1, 1))
        rowin = ((ys[:-1] >= t.ws_lo - 1e-6) & (ys[1:] <= t.ws_hi + 1e-6))[:, None]
        glass = qfront & rowin & (q <= 2)
        flip = dirz > 0
        def em(mask, UV, mat):
            if flip:
                emit(B, G[:, ::-1], N[:, ::-1], UV[:, ::-1], mask[:, ::-1], mat)
            else:
                emit(B, G, N, UV, mask, mat)
        em(~qfront, sideUV, self.livmat)
        em(qfront & ~glass, frontUV, self.livmat)
        if q <= 2:
            Gg = G - N * 0.004
            if flip: emit(B, Gg[:, ::-1], N[:, ::-1], frontUV[:, ::-1], glass[:, ::-1], "glass_windshield")
            else: emit(B, Gg, N, frontUV, glass, "glass_windshield")
        # plancher du nez (fond)
        row = G[0]
        ring = np.vstack([row, [[row[-1][0], t.yb, zj], [row[0][0], t.yb, zj]]])
        B.fan(ring, "trim_black", normal=np.array([0, -1.0, 0]))
        self.lamps(m, zj, dirz, end)
        if q <= 2:
            self.destination(m, zj, dirz, end)
        if q <= 1:
            self.wiper(m, zj, dirz, end)
            self.mirrors(m, zj, dirz, end)
            self.cab_proxy(m, zj, dirz, end, G, N, ys, part)

    def surf(self, x, y, zj, dirz):
        return self.t.face_point(x, y, zj, dirz)

    def disc_on_face(self, x, y, zj, dirz, r, mat, depth=0.0, seg=16, bezel=None, bezel_w=0.012, dome=0.012):
        t, B = self.t, self.B
        if self.q >= 3: seg = min(seg, 6); bezel = None; dome = 0
        if self.q >= 4 and mat.startswith("trim"): return
        p, n = self.surf(x, y, zj, dirz)
        p = p + n * depth
        F = frame_from_z(n)
        ang = np.linspace(0, 2 * math.pi, seg + 1)[:-1]
        ring = np.array([p + (math.cos(a) * F[:, 0] + math.sin(a) * F[:, 1]) * r for a in ang])
        B.fan(ring, mat, normal=n)
        c = p + n * dome
        if dome > 0:
            B.lathe(p, n, [(r, 0.0), (r * 0.8, dome * 0.6), (r * 0.4, dome * 0.95), (0.001, dome)], mat, seg=seg)
        if bezel:
            B.lathe(p - n * 0.004, n, [(r + bezel_w, 0.0), (r + bezel_w * 0.6, 0.008), (r, 0.006)], bezel, seg=seg)

    def lamps(self, m, zj, dirz, end):
        t, B, q = self.t, self.B, self.q
        mod = "module_%02d" % m["i"]
        st = t.spec["front_style"]; seg = max(8, int(20 * SEG[q]))
        hn = "em_head_" + end; tn = "em_tail_" + end
        B.node(hn, mod, (0, 0.9, zj + dirz * t.Lf)); B.node(tn, mod, (0, 0.9, zj + dirz * t.Lf)); B.use(mod)
        hl = t.fr.get("headlights", {})
        y0 = float(hl.get("y_m", 0.9))
        if st == "x05":
            # Irigo: three separate round optics in a white bumper, no generic
            # black almond shared with other Citadis networks.
            for sx in (1, -1):
                for k, xx in enumerate((0.66, 0.82, 0.96)):
                    yy=0.79+k*0.035; radius=(0.060,0.053,0.040)[k]
                    B.use(mod); self.disc_on_face(sx*xx,yy,zj,dirz,radius+0.012,"trim_chrome",depth=0.004,seg=seg,dome=0)
                    B.use(hn if k<2 else tn); self.disc_on_face(sx*xx,yy,zj,dirz,radius,"em_head" if k<2 else "em_tail",depth=0.008,seg=seg,dome=0.008)
        elif st == "x05_nantes":
            # panneau alvéolé : 68 hexagones (4 rangées × 17)
            B.use(mod)
            rows, cols = 5, 14
            for i in range(rows):
                y = 0.695 + i * 0.109
                for j in range(cols):
                    xx = (j-6.5)*0.14+(i%2)*0.07
                    rr = 0.026+0.039*min(1,max(0,(abs(xx)-0.18)/0.55))
                    if abs(xx)+rr>1.005: continue
                    lit = abs(xx)>0.25
                    if q >= 3 and not lit: continue
                    if q >= 4 and j not in (3, 13): continue
                    B.use(hn if lit else mod)
                    self.disc_on_face(xx, y, zj, dirz, rr, "em_head" if B.cur == hn else "lamp_lens_off", depth=0.003, seg=6, dome=0)
            for sx in (1, -1):
                B.use(tn); self.disc_on_face(sx * 0.76, 0.64, zj, dirz, 0.03, "em_tail", depth=0.003, seg=6, dome=0)
                B.use(tn); self.disc_on_face(sx * 0.76, 0.71, zj, dirz, 0.03, "em_tail", depth=0.003, seg=6, dome=0)
            # couronne lumineuse autour du pare-brise
            if q <= 2:
                B.node("em_drl_" + end, mod, (0, t.ws_hi, zj + dirz * t.Lf))
                xsr = np.linspace(-0.98, 0.98, int(40 * SEG[q]) + 4)
                xr = 1.015
                pts = [self.surf(x*xr,t.ws_hi+0.055-0.16*abs(x)**6,zj,dirz) for x in xsr]
                P = np.array([p + n * 0.004 for p, n in pts]); Nn = np.array([n for p, n in pts])
                G = np.array([P - np.array([0, 0.018, 0]), P + np.array([0, 0.018, 0])])
                NN = np.array([Nn, Nn])
                if dirz < 0: G = G[:, ::-1]; NN = NN[:, ::-1]
                emit(B, G, NN, np.zeros(G.shape[:2] + (2,)), np.ones((1, G.shape[1] - 1), bool), "em_drl")
        else:   # 302 : groupes de trois feux inclinés
            for sx in (1, -1):
                for k in range(3):
                    x = sx * (0.52 + 0.085 * k); y = y0 + 0.02 + 0.035 * k
                    B.use(mod); self.disc_on_face(x, y, zj, dirz, 0.05, "trim_black", depth=0.002, seg=seg, bezel="trim_chrome", dome=0)
                    if k == 2: B.use(tn); self.disc_on_face(x, y, zj, dirz, 0.036, "em_tail", depth=0.004, seg=seg)
                    else: B.use(hn); self.disc_on_face(x, y, zj, dirz, 0.04, "em_head", depth=0.004, seg=seg)
        B.use(mod)

    def almond(self, xc, yc, w, h, rot_deg, zj, dirz, mat, depth, seg=24):
        """Boîtier en amande projeté sur la face (contour lenticulaire incliné)."""
        a = math.radians(rot_deg)
        pts = []
        for u in np.linspace(0, 2 * math.pi, seg, endpoint=False):
            x = w / 2 * math.cos(u); y = h / 2 * math.sin(u) * (1 - 0.35 * math.cos(u) ** 2)
            xr = x * math.cos(a) - y * math.sin(a); yr = x * math.sin(a) + y * math.cos(a)
            p, n = self.surf(xc + xr, yc + yr, zj, dirz)
            pts.append(p + n * depth)
        c, nc = self.surf(xc, yc, zj, dirz)
        self.B.fan(np.array(pts), mat, normal=nc)

    def destination(self, m, zj, dirz, end):
        t, B = self.t, self.B
        mod = "module_%02d" % m["i"]
        d = t.fr.get("destination", {}); w = min(float(d.get("w_m", 1.4)), 1.3); hgt = float(d.get("h_m", 0.22))
        yc = min(float(d.get("y_m", 2.85)), t.ws_hi - hgt / 2 - 0.05)
        pe, ne = self.surf(w / 2, yc, zj, dirz)
        pc, nc = self.surf(0.0, yc, zj, dirz)
        zq = pe[2] - dirz * 0.035                  # derrière le vitrage, au retrait des bords
        B.node("em_dest_" + end, mod, (0, yc, zq))
        x0, x1 = (-w / 2, w / 2) if dirz < 0 else (w / 2, -w / 2)
        B.quad((x0, yc - hgt / 2, zq), (x1, yc - hgt / 2, zq), (x1, yc + hgt / 2, zq), (x0, yc + hgt / 2, zq), "em_dest",
               uv=[(0, 1), (1, 1), (1, 0), (0, 0)])
        # caisson de girouette
        B.use(mod)
        B.box((0, yc, zq - dirz * 0.06), (w + 0.06, hgt + 0.06, 0.1), "trim_black")
        rot = None if dirz < 0 else rot_y(180)
        B.node("sign_dest_" + end, mod, (0, yc, zq + dirz * 0.003), rot=rot,
               extras={"width_m": w, "height_m": hgt})
        B.use(mod)

    def wiper(self, m, zj, dirz, end):
        t, B = self.t, self.B
        mod = "module_%02d" % m["i"]
        st = t.spec["front_style"]
        px = 0.42*dirz if st=="x05_nantes" else (0.74*dirz if st=="x05" else 0.0)
        py = t.ws_lo + 0.06
        p, n = self.surf(px, py, zj, dirz)
        p = p + n * 0.02
        F = frame_from_z(n)        # Z local = normale du vitrage (axe de balayage)
        name = "wiper_%s_0" % end
        B.node(name, mod, p, rot=F)
        # bras au repos : couché vers la gauche du conducteur (-X local), légèrement relevé
        ang = math.radians(66 if st=="x05_nantes" else 145)
        d = math.cos(ang) * F[:, 0] + math.sin(ang) * F[:, 1]
        L1 = 0.95 if st != "c302" else 0.85
        seg = 6 if self.q == 0 else 4
        B.cyl(p - n * 0.01, p + n * 0.03, 0.025, "trim_black", seg=seg * 2)
        tip = p + d * L1
        B.cyl(p + n * 0.02, tip + n * 0.012, 0.009, "trim_black", seg=seg)
        nb = np.cross(n, d)
        a, b = tip - d * 0.42 + n * 0.006, tip + d * 0.38 + n * 0.006
        B.box((a + b) / 2, (0.02, 0.012, np.linalg.norm(b - a)), "trim_rubber", basis=(nz(nb), n, nz(b - a)))
        B.use(mod)

    def mirrors(self, m, zj, dirz, end):
        t, B = self.t, self.B
        mod = "module_%02d" % m["i"]
        st = t.spec["front_style"]
        y = 2.45 if st != "c302" else 2.3
        zh = zj - dirz * 0.25
        for sx, lr in ((-1, "L"), (1, "R")):
            name = ("mirror_%s" % lr) if end == "A" else ("mirror_B_%s" % lr)
            xh = sx * float(t.prof_x(y))
            B.node(name, mod, (xh, y, zh))
            if st == "c302":   # rétroviseur classique
                B.cyl((xh, y, zh), (xh + sx * 0.28, y + 0.05, zh + dirz * 0.06), 0.015, "trim_black", seg=6)
                B.rbox((xh + sx * 0.33, y - 0.05, zh + dirz * 0.07), (0.16, 0.30, 0.06), 0.03, "trim_black", seg=2)
                B.box((xh + sx * 0.33, y - 0.05, zh + dirz * 0.105), (0.13, 0.26, 0.004), "trim_chrome")
            else:              # caméra de rétrovision carénée
                B.cyl((xh, y, zh), (xh + sx * 0.09, y, zh), 0.02, "paint_base", seg=8)
                c = np.array([xh + sx * 0.13, y, zh])
                B.lathe(c - np.array([0, 0, dirz * 0.12]), (0, 0, dirz), [(0.001, 0), (0.035, 0.03), (0.045, 0.1), (0.04, 0.2), (0.02, 0.24)], "paint_base", seg=10)
                B.cyl(c + np.array([0, 0, dirz * 0.115]), c + np.array([0, 0, dirz * 0.125]), 0.018, "trim_black", seg=8)
        B.use(mod)

    def cab_proxy(self, m, zj, dirz, end, G, N, ys, part):
        """Aménagement simplifié de la loge (vu de l'extérieur) ; masqué quand cab.glb est instancié."""
        t, B = self.t, self.B
        mod = "module_%02d" % m["i"]
        name = "cab_proxy_" + end
        B.node(name, mod, (0, t.floor, zj))
        lining(B, t, zj, dirz, "int_dark", q=2)
        tip = zj + dirz * t.Lf
        zb = tip - dirz * t.cab_len()
        # pupitre, siège, cloison
        B.box((0, 1.0, tip - dirz * 1.0), (1.9, 0.22, 0.55), "int_dark")
        B.box((0, 0.65, tip - dirz * 1.0), (1.7, 0.6, 0.35), "int_dark")
        B.box((0, 0.75, tip - dirz * 1.7), (0.5, 0.12, 0.5), "int_dark")
        B.box((0, 1.15, tip - dirz * 1.98), (0.5, 0.7, 0.1), "int_dark")
        B.box((0, (t.floor + 2.45) / 2, zb + dirz * 0.025), (2 * (t.hw - WALL), 2.45 - t.floor, 0.05), "int_wall")
        x = t.hw - WALL
        B.quad((-x, t.floor, tip - dirz * 0.6), (x, t.floor, tip - dirz * 0.6), (x, t.floor, zb), (-x, t.floor, zb), "int_dark")
        ycl = 2.45
        B.quad((-x, ycl, zb), (x, ycl, zb), (x, ycl, tip - dirz * 0.5), (-x, ycl, tip - dirz * 0.5), "int_ceiling") if dirz < 0 else \
            B.quad((x, ycl, zb), (-x, ycl, zb), (-x, ycl, tip - dirz * 0.5), (x, ycl, tip - dirz * 0.5), "int_ceiling")
        B.use(mod)

    # ================================================================== portes
    def doors(self, m):
        t, B, q = self.t, self.B, self.q
        if q >= 3: return
        mod = "module_%02d" % m["i"]
        for d in m["doors"]:
            for s, side in ((-1, "L"), (1, "R")):
                n = d["n"]; nl = d["leaves"]
                for k in range(nl):
                    z0 = d["z0"] + (d["z1"] - d["z0"]) * k / nl; z1 = d["z0"] + (d["z1"] - d["z0"]) * (k + 1) / nl
                    if nl == 1: name = "door_%d_%s" % (n, side)
                    else: name = "door_%d_%s_%s" % (n, side, "a" if k == 0 else "b")
                    zc = (z0 + z1) / 2; yc = (0.43 + t.door_top) / 2
                    B.node(name, mod, (s * (float(t.prof_x(yc)) - 0.03), yc, zc))
                    self.leaf(s, z0 + 0.004, z1 - 0.004, 0.43, t.door_top - 0.005, center_edge=(z1 if k == 0 else z0) if nl > 1 else z0)
                    B.use(mod)
                if q <= 1:   # bouton d'ouverture extérieur (sur le dormant)
                    B.use(mod)
                    zb = d["z1"] + 0.07
                    if zb < m["zB"] - 0.05:
                        x = s * float(t.prof_x(1.2)) + s * 0.004
                        B.node("em_door_%d_%s" % (d["n"], side), mod, (x, 1.2, zb))
                        B.cyl((x - s * 0.006, 1.2, zb), (x + s * 0.006, 1.2, zb), 0.03, "em_door", seg=12 if q == 0 else 8)
                        B.use(mod)

    def leaf(self, s, z0, z1, y0, y1, center_edge):
        """Vantail : cadre peint, grand vitrage, joint central ; faces extérieure et intérieure."""
        t, B, q = self.t, self.B, self.q
        xo = lambda y: s * (float(t.prof_x(y)) - 0.012)
        th = 0.035
        fw = 0.065; gy0 = 0.62 if t.spec["front_style"] != "x05_nantes" else 0.55; gy1 = y1 - 0.11
        if q >= 2:
            ym = (y0 + y1) / 2
            B.box((xo(ym) - s * 0.015, ym, (z0 + z1) / 2), (0.03, y1 - y0, z1 - z0), "paint_door")
            return
        # cadre extérieur (4 bandes) et vitrage
        zs = [z0, z0 + fw, z1 - fw, z1]; ys = [y0, gy0, gy1, y1]
        for i in range(3):
            for j in range(3):
                if i == 1 and j == 1: continue
                self.quadv((xo(ys[j]), ys[j]), (xo(ys[j + 1]), ys[j + 1]), zs[i], zs[i + 1], "paint_door", s < 0)
        self.quadv((xo(gy0) - s * 0.008, gy0), (xo(gy1) - s * 0.008, gy1), zs[1], zs[2], "glass_door", s < 0)
        # face intérieure
        xi = lambda y: xo(y) - s * th
        for i in range(3):
            for j in range(3):
                if i == 1 and j == 1: continue
                self.quadv((xi(ys[j]), ys[j]), (xi(ys[j + 1]), ys[j + 1]), zs[i], zs[i + 1], "int_wall" if q <= 1 else "paint_door", s > 0)
        # chants
        for zz, nn in ((z0, -1), (z1, 1)):
            mat = "trim_rubber" if abs(zz - center_edge) < 0.01 else "trim_grey"
            P = np.array([(xo(y0), y0, zz), (xi(y0), y0, zz), (xi(y1), y1, zz), (xo(y1), y1, zz)])
            if np.dot(np.cross(P[1] - P[0], P[2] - P[0]), (0, 0, nn)) < 0: P = P[::-1]
            B.add(P, np.tile((0, 0, nn), (4, 1)), P[:, 1:] * 4, [[0, 1, 2], [0, 2, 3]], mat)
        # chants du vitrage (épaisseur)
        for (ya, yb_, za, zb_) in ((gy0, gy0, zs[1], zs[2]), (gy1, gy1, zs[1], zs[2])):
            pass
        # poignée de secours intérieure / main courante verticale
        if q == 0:
            zc = center_edge - (0.09 if center_edge > (z0 + z1) / 2 else -0.09)
            B.cyl((xi(1.0) - s * 0.05, 1.0, zc), (xi(1.6) - s * 0.05, 1.6, zc), 0.014, "int_pole", seg=8)
            for yy in (1.0, 1.6):
                B.cyl((xi(yy), yy, zc), (xi(yy) - s * 0.05, yy, zc), 0.01, "int_pole", seg=6, caps=False)

    # ================================================================== toiture
    def roof(self, m):
        t, B, q = self.t, self.B, self.q
        mod = "module_%02d" % m["i"]; B.use(mod)
        h = t.h
        has_panto = any(r["type"] == "pantograph" for r in m["roof"])
        # carénages latéraux de toiture (X05, caisse à pantographe) : panneaux bas le long des épaulements
        if has_panto and q <= 2:   # coffres bas et goulottes de câbles autour du pantographe
            for zc_, ln in ((m["zA"] + 0.55, 0.6), (m["zB"] - 0.55, 0.6)):
                B.rbox((0, h + 0.09, zc_), (1.3, 0.18, ln), 0.04, "roof_equipment", seg=2 if q == 0 else 1)
            for s in (1, -1):
                B.box((s * 0.25, h + 0.03, (m["zA"] + m["zB"]) / 2), (0.08, 0.06, m["zB"] - m["zA"] - 0.6), "roof_grille")
        if False:
            za, zb = m["zA"] + (0.45 if not m["front_cab"] else 0.1), m["zB"] - (0.45 if not m["rear_cab"] else 0.1)
            if True:
                for s in (1, -1):
                    prof = np.array([(0.80, h - 0.01), (0.83, h + 0.24), (0.88, h + 0.28), (0.99, h + 0.26), (1.05, h + 0.12), (1.06, h - 0.02)])
                    if s < 0: prof = prof[::-1] * np.array([-1, 1])
                    pr = np.vstack([prof, prof[:1]]) if False else prof
                    zz = np.array([za, zb])
                    G = np.array([[[x, y, z] for x, y in pr] for z in zz])
                    N = grid_normals(G, away=(0.0, t.h - 0.3))
                    UV = TX.side_uv(t.zf(G[..., 2]), np.full(G.shape[:2], t.h + 0.2), t.L)
                    emit(B, G, N, UV, np.ones((1, len(pr) - 1), bool), "paint_base")
                    for zz_, dd in ((za, -1), (zb, 1)):
                        ring = np.array([(x, y, zz_) for x, y in pr])
                        B.fan(ring, "paint_base", normal=np.array([0, 0, dd], float))
        covered = t.spec["front_style"] in ("x05", "x05_nantes") and not has_panto
        if covered:
            z0 = (m["zs"] + t.Lf * 0.45) if m["front_cab"] else m["zA"] + 0.30
            z1 = (m["ze"] - t.Lf * 0.45) if m["rear_cab"] else m["zB"] - 0.30
            self.roof_cover(z0, z1, 1.80, 0.30, m["front_cab"], m["rear_cab"])
        for r in m["roof"]:
            w, hh, l = r["size"]; zc = r["zg"]; typ = r["type"]
            if covered and typ != "pantograph": continue
            if typ == "pantograph":
                if q <= 3: self.pantograph(m, zc)
                continue
            if typ == "fairing":
                self.fairing(m, zc, w, hh, l)
                continue
            seg = 3 if q <= 1 else 1
            B.rbox((0, h + hh / 2, zc), (w, hh, l), 0.06 if q <= 2 else 0.0, "roof_equipment", seg=seg)
            if typ == "hvac" and q <= 1:
                for s in (1, -1):
                    x = s * (w / 2 + 0.001)
                    for k in range(3):
                        z0 = zc - l / 2 + 0.25 + k * (l - 0.5) / 3; z1 = z0 + (l - 0.5) / 3 - 0.06
                        self.quadv((x, h + 0.06), (x, h + hh - 0.08), z0, z1, "roof_grille", s < 0)
                for k in (-1, 1):
                    c = np.array([0, h + hh + 0.002, zc + k * l * 0.22])
                    B.lathe(c, (0, 1, 0), [(0.28, 0), (0.27, 0.01), (0.001, 0.012)], "roof_grille", seg=16 if q == 0 else 10)

    def roof_cover(self, z0, z1, w, hh, long_front, long_rear):
        """Carénage de toiture continu (couvre climatisation et coffres) : section en superellipse, extrémités
        arrondies ; long biseau côté cabine. Prises d'air sombres sur les flancs."""
        t, B, q = self.t, self.B, self.q
        h = t.h
        if q >= 4 and not (long_front or long_rear): return
        nx = {0: 18, 1: 10, 2: 8, 3: 6, 4: 3}[q]; nzz = {0: 26, 1: 12, 2: 8, 3: 6, 4: 3}[q]
        L = z1 - z0
        lf = 1.1 if long_front else 0.35; lr = 1.1 if long_rear else 0.35
        u = np.linspace(0, 1, nzz + 1)
        zz = z0 + u * L
        def prof_h(z):
            a = np.clip((z - z0) / lf, 0, 1); b = np.clip((z1 - z) / lr, 0, 1)
            return np.minimum(np.sin(a * math.pi / 2) ** (0.8 if long_front else 0.5), np.sin(b * math.pi / 2) ** (0.8 if long_rear else 0.5))
        ang = np.linspace(-1, 1, nx + 1)
        G = []
        for z in zz:
            f = float(prof_h(z))
            row = []
            for a_ in ang:
                x = w / 2 * np.sign(a_) * abs(a_) ** 0.8
                e = max(1 - abs(a_) ** 3.0, 0) ** 0.33
                row.append([x * (0.82 + 0.18 * f), h - 0.01 + hh * f * e, z])
            G.append(row)
        G = np.array(G)
        N = grid_normals(G, away=(0.0, h - 1.5))
        emit(B, G, N, np.stack([G[..., 0], G[..., 2]], -1), np.ones((nzz, nx), bool), "paint_base")
        if q <= 1:   # grilles d'aspiration latérales
            for s in (1, -1):
                for zc in np.arange(z0 + lf + 0.4, z1 - lr - 0.4, 1.3):
                    x = s * (w / 2 * 0.93); y = h + hh * 0.45
                    p0 = np.array([x, y, zc])
                    B.box(p0, (0.012, hh * 0.38, 0.7), "roof_grille")

    def fairing(self, m, zc, w, hh, l):
        """Carénage de bout de toit (cabine) : coque arrondie qui prolonge la face."""
        t, B, q = self.t, self.B, self.q
        h = t.h
        front = zc < 0
        d = -1 if front else 1
        nx = {0: 10, 1: 6}.get(q, 4); nz_ = {0: 8, 1: 5}.get(q, 3)
        xs = np.linspace(-w / 2, w / 2, nx + 1)
        us = np.linspace(0, 1, nz_ + 1)
        G = []
        for u in us:
            z = zc - d * (l / 2) + d * u * l
            hgt = hh * (np.sin(np.clip(u, 0, 1) * math.pi / 2) ** 0.6 if True else 1)
            row = []
            for x in xs:
                e = 1 - (2 * x / w) ** 4
                row.append([x, h - 0.01 + hgt * max(e, 0) ** 0.35, z])
            G.append(row)
        G = np.array(G)
        if d < 0: G = G[::-1]
        G = G[:, ::-1] if d < 0 else G
        N = grid_normals(G, away=(0.0, t.h - 1.0))
        emit(B, G, N, np.stack([G[..., 0], G[..., 2]], -1), np.ones((nz_, nx), bool), "paint_base")

    def pantograph(self, m, zp):
        t, B, q = self.t, self.B, self.q
        mod = "module_%02d" % m["i"]
        h = t.h
        geo = panto_geometry(t, zp)
        self.panto = geo
        seg = {0: 10, 1: 6, 2: 5, 3: 4}[q]
        B.node("panto_base", mod, (0, h, zp))
        # châssis + isolateurs
        for s in (1, -1):
            for zz in (zp - 0.55, zp + 0.55):
                c = np.array([s * 0.42, h, zz])
                if q <= 1:
                    B.lathe(c, (0, 1, 0), [(0.06, 0), (0.05, 0.02)] + sum([[(0.045, 0.03 + k * 0.05), (0.08, 0.045 + k * 0.05), (0.045, 0.06 + k * 0.05)] for k in range(4)], []) + [(0.04, 0.24), (0.001, 0.25)], "insulator", seg=seg)
                else:
                    B.cyl(c, c + (0, 0.25, 0), 0.06, "insulator", seg=seg)
        yb = h + 0.27
        B.box((0, yb, zp), (0.95, 0.06, 1.25), "panto_metal") if q >= 2 else None
        if q <= 1:
            for s in (1, -1): B.box((s * 0.42, yb, zp), (0.08, 0.07, 1.3), "panto_metal")
            for zz in (zp - 0.55, zp + 0.55, geo["H"][1]): B.box((0, yb, zz), (0.92, 0.06, 0.08), "panto_metal")
        H, K, T = geo["H"], geo["K"], geo["T"]
        # bras inférieur : cadre tubulaire (pivot = articulation basse, rotation X)
        B.node("panto_lower", "panto_base", (0, H[0], H[1]))
        Hp = np.array([0, H[0], H[1]]); Kp = np.array([0, K[0], K[1]]); Tp = np.array([0, T[0], T[1]])
        for s in (1, -1):
            B.tube([Hp + (s * 0.34, 0, 0), Kp + (s * 0.07, 0, 0)], 0.028, "panto_metal", seg=seg)
        B.cyl(Hp + (-0.4, 0, 0), Hp + (0.4, 0, 0), 0.04, "panto_metal", seg=seg)
        if q <= 1:
            for f in (0.35, 0.7):
                a = Hp + (Kp - Hp) * f
                w = 0.34 + (0.07 - 0.34) * f
                B.cyl(a + (-w, 0, 0), a + (w, 0, 0), 0.016, "panto_metal", seg=seg)
            # vérin de levage
            B.cyl(Hp + (0.2, -0.03, -0.15 * (1 if K[1] < H[1] else -1)), Hp + (0.2, 0.06, -0.55 * (1 if K[1] < H[1] else -1)), 0.035, "panto_metal", seg=seg)
        # bras supérieur (pivot = genou)
        B.node("panto_upper", "panto_lower", (0, K[0], K[1]))
        for s in (1, -1):
            B.tube([Kp + (s * 0.06, 0, 0), Tp + (s * 0.11, 0, 0)], 0.018, "panto_metal", seg=seg)
        B.cyl(Kp + (-0.08, 0, 0), Kp + (0.08, 0, 0), 0.035, "panto_metal", seg=seg)
        # tige de guidage (bielle) sous le bras supérieur
        if q <= 1:
            B.tube([Kp + (0, -0.05, 0), Tp + (0, -0.06, 0)], 0.01, "panto_metal", seg=6)
        # archet (pivot = tête)
        B.node("panto_head", "panto_upper", (0, T[0], T[1]))
        for dz in (-0.17, 0.17):
            c = Tp + (0, 0.05, dz)
            path = [c + (-0.98, -0.16, 0), c + (-0.86, -0.04, 0), c + (-0.72, 0, 0), c + (0.72, 0, 0), c + (0.86, -0.04, 0), c + (0.98, -0.16, 0)]
            B.tube(path, 0.022, "panto_metal", seg=seg)
            if q <= 1:
                B.box(c + (0, 0.03, 0), (1.3, 0.03, 0.05), "panto_carbon")
        B.box(Tp + (0, 0.0, 0), (0.36, 0.05, 0.42), "panto_metal")
        B.use(mod)

    # ================================================================== bogies
    def bogie(self, m):
        t, B, q = self.t, self.B, self.q
        mod = "module_%02d" % m["i"]
        k = len([n for n in B.order if n.startswith("bogie_")])
        zc = m["bogie_z"]
        B.node("bogie_%d" % k, mod, (0, 0.30, zc))
        r = 0.295; wb = 1.8; ga = 0.7525
        seg = {0: 28, 1: 16, 2: 12, 3: 8}[q]
        for dz in (-wb / 2, wb / 2):
            for s in (1, -1):
                c = np.array([s * ga, r, zc + dz])
                if q <= 2:
                    # roue : table de roulement, boudin intérieur, voile
                    prof = [(0.001, -0.07), (0.20, -0.07), (0.24, -0.05), (r - 0.005, -0.05), (r + 0.025, -0.035), (r + 0.028, -0.025),
                            (r, -0.012), (r - 0.008, 0.06), (0.22, 0.065), (0.08, 0.05), (0.001, 0.05)]
                    prof = [(rr, -hh * s) for rr, hh in prof] if s < 0 else prof
                    if s < 0: prof = prof[::-1]
                    B.lathe(c, (s, 0, 0), prof if s > 0 else [(rr, -hh) for rr, hh in prof], "wheel_steel", seg=seg) if False else \
                        B.lathe(c, (1, 0, 0), [(rr, hh * s) for rr, hh in [(0.001, -0.07), (0.20, -0.07), (0.24, -0.05), (r - 0.005, -0.05), (r + 0.025, -0.035), (r + 0.028, -0.025), (r, -0.012), (r - 0.008, 0.06), (0.22, 0.065), (0.08, 0.05), (0.001, 0.05)]][::(1 if s > 0 else -1)], "wheel_steel", seg=seg)
                else:
                    B.cyl(c - (0.05, 0, 0), c + (0.05, 0, 0), r, "wheel_steel", seg=seg)
            if q <= 2:
                B.cyl((-ga + 0.06, r, zc + dz), (ga - 0.06, r, zc + dz), 0.07, "bogie_metal", seg=max(6, seg // 3))
            if q <= 1:
                for s in (1, -1):   # disques de frein
                    B.cyl((s * 0.45, r, zc + dz), (s * 0.5, r, zc + dz), 0.21, "wheel_steel", seg=seg)
                    B.rbox((s * 0.47, r + 0.2, zc + dz - 0.1), (0.14, 0.12, 0.2), 0.02, "bogie_metal", seg=1)
        # longerons, traverse, boîtes d'essieu, suspensions
        for s in (1, -1):
            x = s * (ga + 0.09)
            B.rbox((x, r + 0.05, zc), (0.12, 0.2, wb + 0.55), 0.04 if q <= 1 else 0, "bogie_metal", seg=2 if q <= 1 else 1)
            if q <= 1:
                for dz in (-wb / 2, wb / 2):
                    B.rbox((x, r, zc + dz), (0.16, 0.2, 0.26), 0.03, "bogie_metal", seg=2)
                    B.cyl((x, r + 0.1, zc + dz), (x, r + 0.2, zc + dz), 0.07, "trim_rubber", seg=10)
                # suspension secondaire (ressort hélicoïdal)
                if q == 0:
                    hel = [(x + 0.11 * math.cos(a) * 0.0 + 0.09 * math.cos(a), r + 0.17 + a / (2 * math.pi) * 0.045, zc + 0.09 * math.sin(a)) for a in np.linspace(0, 2 * math.pi * 5, 90)]
                    B.tube(hel, 0.016, "bogie_metal", seg=6)
                else:
                    B.cyl((x, r + 0.15, zc), (x, r + 0.4, zc), 0.1, "bogie_metal", seg=8)
        B.rbox((0, r + 0.12, zc), (2 * ga, 0.16, 0.36), 0.03 if q <= 1 else 0, "bogie_metal", seg=1)
        if q <= 1 and (m["kind"] in ("cab", "middle")):   # moteur + réducteur
            for dz in (-wb / 2 + 0.45, wb / 2 - 0.45):
                B.cyl((-0.42, r + 0.02, zc + dz), (0.30, r + 0.02, zc + dz), 0.17, "bogie_metal", seg=14 if q == 0 else 8)
        B.use(mod)

    # ================================================================== soufflets
    def bellows(self, m):
        t, B, q = self.t, self.B, self.q
        mod = "module_%02d" % m["i"]
        zb = m["ze"]
        B.node("bellows_%02d" % m["i"], mod, (0, 0, zb))
        folds = {0: 11, 1: 6, 2: 3, 3: 1, 4: 1}[q]
        if q >= 4:
            B.box((0, 1.6, zb), (2 * t.hw - 0.12, 2.6, 2 * GAP + 0.01), "bellows_rubber")
            B.use(mod); return
        sec = t.section({0: 22, 1: 12, 2: 8}.get(q, 6), {0: 7, 1: 4, 2: 3}.get(q, 2), ybot=0.30)
        cx, cy = 0.0, 1.6
        rings = []
        zz = np.linspace(zb - GAP - 0.005, zb + GAP + 0.005, 2 * folds + 1)
        for i, z in enumerate(zz):
            ins = 0.035 if i % 2 == 0 else 0.085
            if q >= 3: ins = 0.06
            P = sec.copy()
            d = P - np.array([cx, cy]); dn = d / np.linalg.norm(d, axis=1, keepdims=True)
            P = P - dn * ins
            rings.append(np.column_stack([P, np.full(len(P), z)]))
        G = np.array(rings)
        G = np.concatenate([G, G[:, :1]], 1)
        N = grid_normals(G, away=(cx, cy))
        L = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(G[0, :, :2], axis=0), axis=1))])
        UV = np.stack(np.meshgrid(L, zz), -1)
        emit(B, G, N, UV, np.ones((G.shape[0] - 1, G.shape[1] - 1), bool), "bellows_rubber")
        if q <= 1:
            # intercirculation : soufflet intérieur + plaque tournante
            x = t.hw - WALL - 0.06
            for s in (1, -1):
                ys = np.linspace(t.floor, 2.4, 2)
                Gi = []
                for i, z in enumerate(zz):
                    xi = s * (x - (0.0 if i % 2 == 0 else 0.03))
                    Gi.append([[xi, y, z] for y in ys])
                Gi = np.array(Gi)
                if s > 0: Gi = Gi[:, ::-1]
                Ni = grid_normals(Gi, toward=(0.0, 1.4))
                emit(B, Gi, Ni, np.stack([Gi[..., 2], Gi[..., 1]], -1), np.ones((Gi.shape[0] - 1, 1), bool), "int_dark")
            B.quad((-x, t.floor + 0.004, zb - GAP), (-x, t.floor + 0.004, zb + GAP), (x, t.floor + 0.004, zb + GAP), (x, t.floor + 0.004, zb - GAP), "trim_alu")
            B.quad((x, 2.4, zb - GAP), (x, 2.4, zb + GAP), (-x, 2.4, zb + GAP), (-x, 2.4, zb - GAP), "int_dark")
        B.use(mod)

    # ================================================================== intérieur voyageurs
    def interior(self, m):
        t, B, q = self.t, self.B, self.q
        mod = "module_%02d" % m["i"]; B.use(mod)
        z0, z1 = m["zA"], m["zB"]
        if m["front_cab"]: z0 = m["zs"] + t.cab_len()
        if m["rear_cab"]: z1 = m["ze"] - t.cab_len()
        fl = t.floor; xw = t.hw - WALL - 0.002
        # cloisons de loge
        for zz, isb in ((z0, m["front_cab"]), (z1, m["rear_cab"])):
            if not isb: continue
            dd = 1 if zz == z0 else -1
            zc = zz - dd * 0.0
            B.box((0, (fl + 2.45) / 2, zc - dd * 0.025), (2 * xw, 2.45 - fl, 0.05), "int_wall")
            B.box((0.35, 1.4, zc + dd * 0.003), (0.62, 1.9, 0.01), "int_dark")      # porte de loge
            B.box((-0.55, 1.75, zc + dd * 0.004), (0.5, 0.45, 0.01), "glass_side")
        # plancher
        B.quad((-xw, fl, z0), (-xw, fl, z1), (xw, fl, z1), (xw, fl, z0), "int_floor",
               uv=[(-xw / 1.5, z0 / 1.5), (-xw / 1.5, z1 / 1.5), (xw / 1.5, z1 / 1.5), (xw / 1.5, z0 / 1.5)])
        # plafond : voussure depuis le haut des baies
        yc = 2.42
        nx = 12 if q == 0 else 6
        a = np.linspace(0, 1, nx + 1)
        xs_r = (t.hw - WALL) * (1 - a * 0.75)
        ys_r = t.cant - 0.02 + (yc - t.cant + 0.02) * np.sin(a * math.pi / 2) - 0.05 * np.sin(a * math.pi)
        prof = np.concatenate([np.stack([xs_r, ys_r], 1), np.stack([-xs_r[::-1], ys_r[::-1]], 1)])
        top_y = ys_r[-1]
        prof = np.concatenate([prof[:nx + 1], [[0.0, top_y]], prof[nx + 1:]]) if False else prof
        G = np.array([[[x, y, z] for x, y in prof] for z in (z0, z1)])
        N = grid_normals(G, toward=(0.0, 1.4))
        emit(B, G, N, np.stack([G[..., 0], G[..., 2]], -1), np.ones((1, G.shape[1] - 1), bool), "int_ceiling")
        # bandeaux lumineux
        B.node("em_interior_%02d" % m["i"], mod, (0, top_y, (z0 + z1) / 2))
        for s in (1, -1):
            x = s * 0.62; y = float(np.interp(0.62, xs_r[::-1], ys_r[::-1])) - 0.012
            B.quad((x - 0.07, y, z0 + 0.1), (x + 0.07, y, z0 + 0.1), (x + 0.07, y, z1 - 0.1), (x - 0.07, y, z1 - 0.1), "em_interior") if True else None
        B.use(mod)
        # sièges, barres, écrans
        self.seats_and_poles(m, z0, z1)

    def seats_and_poles(self, m, z0, z1):
        t, B, q = self.t, self.B, self.q
        mod = "module_%02d" % m["i"]
        fl = t.floor; xw = t.hw - WALL
        obst = [(d["z0"] - 0.12, d["z1"] + 0.12) for d in m["doors"]]
        spans = []; cur = z0 + 0.08
        for a, b in sorted(obst):
            if a > cur: spans.append((cur, a))
            cur = max(cur, b)
        if z1 - 0.08 > cur: spans.append((cur, z1 - 0.08))
        pod = None
        if m["bogie_z"] is not None: pod = (m["bogie_z"] - 1.25, m["bogie_z"] + 1.25)
        sw = 0.43; pitch = 0.74
        seat_n = 0
        for a, b in spans:
            Ls = b - a
            n = int(Ls // pitch)
            if n == 0: continue
            off = a + (Ls - n * pitch) / 2
            for k in range(n):
                zc = off + pitch * (k + 0.5)
                facing = -1 if (k % 2 == 0) else 1     # -1 : regarde vers l'avant (-Z)
                if n == 1: facing = -1
                base = fl + (0.22 if pod and pod[0] < zc < pod[1] else 0.0)
                for s in (1, -1):
                    for j in range(2):
                        x = s * (xw - 0.03 - sw / 2 - j * (sw + 0.02))
                        self.seat(x, base, zc, facing, aisle=(j == 1), s=s)
                        seat_n += 1
                    if base > fl and q <= 1:
                        B.box((s * (xw - 0.47), fl + 0.11, zc), (0.94, 0.22, pitch), "int_dark")
                if q == 0 and k % 2 == 1:
                    for s in (1, -1):
                        x = s * (xw - 0.03 - 2 * sw - 0.08)
                        B.cyl((x, base + 0.45, zc - pitch / 2), (x, 2.4, zc - pitch / 2), 0.017, "int_pole", seg=10, caps=False)
        # barres verticales de porte et main courante haute
        segp = 10 if q == 0 else 6
        for d in m["doors"]:
            for zz in (d["z0"] - 0.08, d["z1"] + 0.08):
                for s in (1, -1):
                    B.cyl((s * (xw - 0.28), fl, zz), (s * (xw - 0.28), 2.38, zz), 0.017, "int_pole", seg=segp, caps=False)
            B.cyl((0, fl, d["zc"]), (0, 2.38, d["zc"]), 0.019, "int_pole", seg=segp, caps=False)
            if q == 0:
                B.cyl((0, 1.05, d["zc"]), (0, 1.15, d["zc"]), 0.022, "int_accent", seg=segp)     # demande d'arrêt
        for s in (1, -1):
            x = s * 0.42
            B.cyl((x, 2.0, z0 + 0.1), (x, 2.0, z1 - 0.1), 0.016, "int_rail", seg=segp, caps=True)
            if q == 0:
                for zz in np.arange(z0 + 0.6, z1 - 0.3, 1.2):
                    B.cyl((x, 2.0, zz), (x, 2.4, zz), 0.012, "int_rail", seg=6, caps=False)
        # écran d'information voyageurs (double face)
        zc = (z0 + z1) / 2
        k = m["i"]
        B.box((0, 2.24, zc), (0.62, 0.22, 0.07), "int_dark")
        for dd, tag in ((-1, "f"), (1, "b")):
            name = "screen_pis_%02d_%s" % (k, tag)
            zq = zc + dd * 0.036
            B.node(name, mod, (0, 2.24, zq))
            xa, xb = (-0.28, 0.28) if dd < 0 else (0.28, -0.28)
            B.quad((xa, 2.15, zq), (xb, 2.15, zq), (xb, 2.33, zq), (xa, 2.33, zq), "screen_pis", uv=[(0, 1), (1, 1), (1, 0), (0, 0)])
            B.use(mod)
        B.cyl((0, 2.35, zc), (0, 2.42, zc), 0.02, "int_pole", seg=6, caps=False)

    def seat(self, x, base, zc, facing, aisle, s):
        t, B, q = self.t, self.B, self.q
        sw = 0.43
        f = facing      # direction du regard
        if q >= 1:
            B.box((x, base + 0.42, zc), (sw, 0.1, 0.44), "int_seat")
            B.box((x, base + 0.78, zc - f * 0.22), (sw, 0.62, 0.08), "int_seat")
            return
        # coque plastique + coussins
        B.rbox((x, base + 0.40, zc + f * 0.0), (sw, 0.05, 0.46), 0.02, "int_seat_shell", basis=(np.array([1, 0, 0]), np.array([0, 0, 1.0]), np.array([0, -1.0, 0])), seg=2)
        B.rbox((x, base + 0.455, zc + f * 0.01), (sw - 0.02, 0.44, 0.07), 0.03, "int_seat", basis=(np.array([1.0, 0, 0]), np.array([0, 0, 1.0]), np.array([0, -1.0, 0])), seg=2)
        tilt = math.radians(12)
        up = np.array([0, math.cos(tilt), -f * math.sin(tilt)])
        fw = np.array([0, math.sin(tilt) * f, math.cos(tilt) * f * 1.0])
        fw = np.array([0, -up[2] * 0 + math.sin(tilt), 0])  # remplacé ci-dessous
        Z = np.array([0.0, f * math.sin(tilt), f * math.cos(tilt)])  # normale du dossier (vers l'avant du siège)
        Y = np.array([0.0, math.cos(tilt), -f * math.sin(tilt)])
        cb = np.array([x, base + 0.80, zc - f * 0.22])
        B.rbox(cb, (sw - 0.02, 0.6, 0.065), 0.03, "int_seat", basis=(np.array([1.0, 0, 0]), Y, Z), seg=2)
        B.rbox(cb - Z * 0.055, (sw, 0.66, 0.045), 0.025, "int_seat_shell", basis=(np.array([1.0, 0, 0]), Y, Z), seg=2)
        if aisle:
            top = cb + Y * 0.33 - Z * 0.03
            B.tube([top + (-0.12, -0.02, 0), top + (-0.1, 0.05, 0), top + (0.1, 0.05, 0), top + (0.12, -0.02, 0)], 0.013, "int_pole", seg=6)
        # piètement en console (fixé à la paroi)
        B.box((x, base + 0.19, zc), (0.06, 0.38, 0.06), "int_pole")


def panto_geometry(t, zp):
    """Pantographe unijambiste : articulation basse H (à l'arrière du châssis), genou K (vers l'avant), archet T
    au-dessus de H. Coordonnées (y, z). Les angles levés sont des rotations autour de +X local : lower_deg pour
    panto_lower, upper_deg pour panto_upper (relatif au bras inférieur ; le code contre-tourne panto_head)."""
    h = t.h
    l1, l2 = 1.50, 1.60
    H = np.array([h + 0.33, zp + 0.62])
    up = float(t.panto_cfg.get("up_m", 2.6)); down = 0.42
    def solve(yt):
        T = np.array([yt, H[1] + 0.12])
        d = np.linalg.norm(T - H)
        a = math.acos(np.clip((l1 ** 2 + d ** 2 - l2 ** 2) / (2 * l1 * d), -1, 1))
        base = math.atan2(T[0] - H[0], -(T[1] - H[1]))      # angle depuis -Z vers +Y
        best = None
        for a1 in (base - a, base + a):
            K = H + l1 * np.array([math.sin(a1), -math.cos(a1)])
            if best is None or K[1] - H[1] > -0.12 and K[0] < best[1][0] or (best[1][0] - H[0] < -0.12):
                if best is None or (K[0] - H[0] >= -0.12 and K[1] < best[1][1]):
                    best = (a1, K)
        a1, K = best
        a2 = math.atan2(T[0] - K[0], -(T[1] - K[1]))
        return T, K, a1, a2
    Td, Kd, a1d, a2d = solve(h + down)
    Tu, Ku, a1u, a2u = solve(h + up)
    wrap = lambda x: (x + 180.0) % 360.0 - 180.0
    lower = wrap(math.degrees(a1u - a1d))
    upper = wrap(math.degrees((a2u - a1u) - (a2d - a1d)))
    return {"H": H, "K": Kd, "T": Td, "lower_deg": round(lower, 2), "upper_deg": round(upper, 2),
            "l1": l1, "l2": l2, "head_down_y": h + down, "head_up_y": h + up, "K_up": Ku, "T_up": Tu}


def lining(B, t, zj, dirz, mat, q=0):
    """Habillage intérieur du nez (vu depuis la loge) : grille du nez décalée vers l'intérieur, pare-brise exclu."""
    G, S, part, ys = t.nose_grid(zj, dirz, q, inset=WALL)
    N = grid_normals(G, away=(0, 1.4, zj - dirz * 4.0))
    R, C = G.shape[:2]
    rows = (ys[:-1] >= t.floor - 1e-6) & (ys[1:] <= 2.46)
    pc = part.astype(bool)
    qfront = np.tile(pc[:-1] & pc[1:], (R - 1, 1))
    glass = qfront & ((ys[:-1] >= t.ws_lo - 1e-6) & (ys[1:] <= t.ws_hi + 1e-6))[:, None]
    mask = rows[:, None] & ~glass
    Gi = G - N * 0.0
    # retournement : normales vers l'intérieur
    if dirz > 0:
        emit(B, Gi, -N, np.stack([Gi[..., 0], Gi[..., 1]], -1), mask, mat)
    else:
        emit(B, Gi[:, ::-1], -N[:, ::-1], np.stack([Gi[..., 0], Gi[..., 1]], -1)[:, ::-1], mask[:, ::-1], mat)
