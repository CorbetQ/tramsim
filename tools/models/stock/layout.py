"""Implantation d'une rame depuis son plan JSON : modules mis à l'échelle de la longueur du rig (comme
TramModel.Rig), portes, baies, bogies, toiture ; profil de caisse et surface du nez (front.plan / front.side).
Repère rame : Y haut (0 = rail), -Z = avant (extrémité A), +X = droite ; zf = distance au nez A."""
import math
import numpy as np
from geom import smooth_interp

GAP = 0.12        # demi-intervalle d'intercirculation (TramModel.GAP)
TUCK = 0.07       # rentrant de bas de caisse
WALL = 0.075      # épaisseur de paroi (peau extérieure -> habillage intérieur)


class Train:
    def __init__(self, spec):
        P = spec["plan_data"]; self.spec = spec; self.P = P
        self.L = float(spec["length"]); self.hw = float(spec["width"]) * 0.5
        self.h = float(P.get("height_m", 3.3)); self.floor = float(P.get("floor_m", 0.32))
        b = P.get("body", {})
        self.skirt = float(b.get("skirt_top_m", 0.45)); self.wb = float(b.get("window_bottom_m", 1.05))
        self.wt = float(b.get("window_top_m", 2.45)); self.cant = float(b.get("cant_m", 2.75))
        self.sh = float(b.get("roof_shoulder_m", 0.25)); self.yb = 0.25
        self.door_top = min(self.wt, self.cant - 0.12); self.door_bot = 0.36
        fr = P.get("front", {}); self.fr = fr
        self.Lf = float(fr.get("length_m", 1.5))
        ws = fr.get("windshield", {})
        self.ws_lo = float(ws.get("bottom_m", 1.1)); self.ws_hi = float(ws.get("top_m", 2.8)); self.wrap = float(ws.get("wrap", 0.3))
        self.bumper = float(fr.get("bumper_m", 0.05)); self.bulge_r = float(fr.get("bulge", 0.22))
        sp = [list(map(float, p)) for p in fr.get("side", [[0, 0]])]
        if sp[-1][0] < self.h - 0.02: sp.append([self.h, 1.0])
        self.side_pts = sp; self.plan_pts = [list(map(float, p)) for p in fr.get("plan", [[0, 1], [1, 0.8]])]
        self.Lfz = max(self.Lf - self.bulge_r * self.hw * float(self.plan_w(1.0)) - self.bumper, self.Lf * 0.6)
        self.door_anim = P.get("door_anim", {"travel_m": 0.65, "out_m": 0.06, "open_s": 2.5})
        self.panto_cfg = P.get("pantograph", {"down_m": 0.25, "up_m": 2.6})
        # modules mis à l'échelle (rig) : toutes les longueurs et positions en z proportionnelles
        mods = P["modules"]; plen = sum(float(m["length_m"]) for m in mods)
        self.scale = self.L / plen
        self.mods = []; cur = 0.0; door_n = 0
        for i, m in enumerate(mods):
            Lm = float(m["length_m"]) * self.scale
            md = {"i": i, "kind": m["kind"], "Lm": Lm, "z0f": cur, "zc": -self.L / 2 + cur + Lm / 2,
                  "front_cab": i == 0 and m["kind"] == "cab", "rear_cab": i == len(mods) - 1 and m["kind"] == "cab"}
            zs = -self.L / 2 + cur          # z global de l'extrémité avant du module
            md["zs"] = zs; md["ze"] = zs + Lm
            md["zA"] = zs + (self.Lf if md["front_cab"] else GAP)
            md["zB"] = zs + Lm - (self.Lf if md["rear_cab"] else GAP)
            md["bogie_z"] = zs + float(m["bogie_z_m"]) * self.scale if m.get("bogie") else None
            md["doors"] = []
            for d in m.get("doors", []):
                zc = zs + float(d["z_m"]) * self.scale; w = float(d["width_m"])
                md["doors"].append({"n": door_n, "zc": zc, "w": w, "leaves": int(d.get("leaves", 2)),
                                    "z0": zc - w / 2, "z1": zc + w / 2}); door_n += 1
            md["windows"] = []
            for w in m.get("windows", []):
                a = max(zs + float(w["z0_m"]) * self.scale, md["zA"] + 0.08)
                c = min(zs + float(w["z1_m"]) * self.scale, md["zB"] - 0.08)
                if c - a > 0.15: md["windows"].append((a, c))
            md["roof"] = [dict(r, zg=zs + float(r["z_m"]) * self.scale) for r in m.get("roof", [])]
            self.mods.append(md); cur += Lm
        self.n_doors = door_n

    # ------------------------------------------------------------ profil de caisse (demi-largeur x en fonction de y)
    def prof_x(self, y):
        y = np.asarray(y, float); hw = self.hw
        x = hw - 0.018 * ((y - 1.75) / 1.0) ** 2                         # flanc légèrement galbé
        t = np.clip((y - self.yb) / (0.42 - self.yb), 0, 1)
        x = np.where(y < 0.42, (hw - TUCK) + (x - hw + TUCK) * (1 - (1 - t) ** 2), x)
        a = np.arcsin(np.clip((y - self.cant) / (self.h - self.cant), 0, 1))
        xc = hw - 0.018 * ((self.cant - 1.75) / 1.0) ** 2
        x = np.where(y > self.cant, xc - self.sh + self.sh * np.cos(a), x)
        return x

    def prof_slope(self, y, e=1e-3):
        return (self.prof_x(y + e) - self.prof_x(y - e)) / (2 * e)

    def section(self, n_side=14, n_roof=6, inset=0.0, ybot=None):
        """Section fermée (x, y) dans le sens trigonométrique vu depuis -Z : bas droit -> haut -> bas gauche -> fond."""
        yb = self.yb if ybot is None else ybot
        ys = list(np.linspace(yb, self.cant, n_side)) + [self.cant + (self.h - self.cant) * math.sin(math.pi / 2 * k / n_roof) for k in range(1, n_roof + 1)]
        right = [(float(self.prof_x(y)) - inset, y - (inset if y >= self.h - 1e-6 else 0)) for y in ys]
        right.append((0.0, self.h - inset))
        left = [(-x, y) for x, y in right[-2::-1]]
        return np.array(right + left)

    # ------------------------------------------------------------ nez (front.plan / front.side)
    def plan_w(self, s):
        return smooth_interp(self.plan_pts, s)

    def smax(self, y):
        return np.clip(1.0 - smooth_interp(self.side_pts, y), 0.0, 1.0)

    def bump(self, y, s):
        t = np.clip((y - (self.skirt - 0.05)) / 0.3, 0, 1)
        return self.bumper * s * (1 - t * t * (3 - 2 * t))

    def nose_rows(self, q):
        """Hauteurs des lignes de la grille du nez (bords du pare-brise exacts)."""
        n = {0: 64, 1: 30, 2: 18, 3: 10, 4: 6}[q]
        ys = set(np.round(np.linspace(self.yb, self.h, n), 4))
        ys |= {self.ws_lo, self.ws_hi, self.skirt, self.cant, self.h - 0.02, self.yb + 0.02}
        if q <= 1:
            ys |= {self.ws_lo - 0.06, self.ws_hi + 0.06, 0.6, 0.75, 0.9, 1.0}
        return np.array(sorted(ys))

    def nose_grid(self, zj, dirz, q, inset=0.0):
        """Grille (R, C, 3) de la face : pour chaque y, flanc droit (s de 0 à smax), front (arc), flanc gauche.
        dirz = -1 pour l'extrémité A (vers -Z), +1 pour B. Renvoie G, S (paramètre s par point), part (0 flanc, 1 face),
        et l'indice des colonnes."""
        ys = self.nose_rows(q)
        n1 = {0: 10, 1: 6, 2: 4, 3: 3, 4: 2}[q]; n2 = {0: 10, 1: 6, 2: 4, 3: 2, 4: 1}[q]; n3 = {0: 28, 1: 14, 2: 10, 3: 6, 4: 4}[q]
        rows = []; S = []; part = []
        for y in ys:
            sm = float(self.smax(y)); xw = float(self.prof_x(y)) - inset
            sw = max(sm - self.wrap, 0.0)
            s_a = np.linspace(0, sw, n1 + 1)
            s_b = np.linspace(sw, sm, n2 + 1)[1:]
            s_side = np.concatenate([s_a, s_b])
            xs = xw * self.plan_w(s_side)
            zs = zj + dirz * (s_side * self.Lfz + self.bump(y, s_side))
            xt = xs[-1]; zt = zs[-1]
            bul = self.bulge_r * min(1.0, sm / 0.3) * xt
            u = np.linspace(1, -1, n3 + 1)[1:-1]
            # arc frontal : demi-ellipse aplatie, tangente au flanc
            xf = xt * u; zf = zt + dirz * bul * np.sqrt(np.clip(1 - u * u, 0, 1))
            row_x = np.concatenate([xs, xf, -xs[::-1]]); row_z = np.concatenate([zs, zf, zs[::-1]])
            rows.append(np.stack([row_x, np.full_like(row_x, y), row_z], 1))
            ss = np.concatenate([s_side, np.full(len(xf), sm), s_side[::-1]])
            S.append(ss)
        G = np.array(rows); S = np.array(S)
        C = G.shape[1]; nside = n1 + n2 + 1
        part = np.zeros(C, int); part[n1:C - n1] = 1   # 1 : zone pare-brise possible (wrap + front)
        if dirz > 0:
            G = G[:, ::-1]; S = S[:, ::-1]; part = part[::-1]
        return G, S, part, ys

    def face_point(self, x, y, zj, dirz):
        """Point de la surface avant en (x, y) (|x| <= demi-largeur frontale) et normale approchée."""
        def zat(xx, yy):
            sm = float(self.smax(yy)); xw = float(self.prof_x(yy)); xt = xw * float(self.plan_w(sm))
            if abs(xx) >= xt:   # sur le flanc : recherche de s
                lo, hi = 0.0, sm
                for _ in range(30):
                    mid = (lo + hi) / 2
                    if xw * float(self.plan_w(mid)) > abs(xx): lo = mid
                    else: hi = mid
                s = lo
                return zj + dirz * (s * self.Lfz + float(self.bump(yy, s)))
            u = xx / xt; bul = self.bulge_r * min(1.0, sm / 0.3) * xt
            return zj + dirz * (sm * self.Lfz + float(self.bump(yy, sm)) + bul * math.sqrt(max(0.0, 1 - u * u)))
        z = zat(x, y); e = 0.01
        dzx = (zat(x + e, y) - zat(x - e, y)) / (2 * e); dzy = (zat(x, y + e) - zat(x, y - e)) / (2 * e)
        # surface z = f(x, y) ; normale ∝ (-fx, -fy, 1) orientée selon dirz
        n = np.array([-dzx, -dzy, 1.0]); n = n / np.linalg.norm(n)
        if n[2] * dirz < 0: n = -n
        return np.array([x, y, z]), n

    # ------------------------------------------------------------ utilitaires
    def zf(self, zg):
        return zg + self.L / 2

    def cab_len(self):
        return self.Lf + 1.05       # loge de conduite : nez + 1,05 m (cloison)
