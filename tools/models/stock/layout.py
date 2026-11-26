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
        if q >= 4:
            return np.array(sorted({self.yb, self.skirt, self.ws_lo, self.ws_hi, self.cant + 0.3, self.h}))
        ys = set(np.round(np.linspace(self.yb, self.h, n), 4))
        ys |= {self.ws_lo, self.ws_hi, self.skirt, self.cant, self.h - 0.02, self.yb + 0.02}
        if q <= 1:
            ys |= {self.ws_lo - 0.06, self.ws_hi + 0.06, 0.6, 0.75, 0.9, 1.0}
        return np.array(sorted(ys))

    # Nez modélisé par courbes : en plan, superellipse |x/xw|^p + |dz/D|^p = 1 (angles très arrondis, tangente au
    # flanc) ; en élévation, avancée D(y) interpolée (menton bombé, pare-brise incliné, raccord au pavillon).
    NOSE_STYLE = {
        "x05": {"p": 2.5, "theta_w": 0.40,
                "D": [(0.25, 0.80), (0.33, 0.91), (0.5, 0.985), (0.78, 1.0), (1.02, 0.955), (1.4, 0.83), (1.9, 0.64),
                      (2.4, 0.45), (2.8, 0.29), (3.05, 0.15), (3.22, 0.05), (3.3, 0.0)]},
        "x05_nantes": {"p": 2.7, "theta_w": 0.36,
                       "D": [(0.25, 0.82), (0.33, 0.92), (0.5, 0.99), (0.8, 1.0), (1.0, 0.96), (1.4, 0.85), (1.9, 0.67),
                             (2.4, 0.48), (2.85, 0.30), (3.08, 0.15), (3.24, 0.05), (3.3, 0.0)]},
        "c302": {"p": 2.15, "theta_w": 0.42,
                 "D": [(0.25, 0.80), (0.4, 0.95), (0.7, 1.0), (1.15, 0.95), (1.6, 0.80), (2.1, 0.60), (2.6, 0.40),
                       (2.95, 0.22), (3.15, 0.10), (3.3, 0.0)]},
    }

    def nose_style(self):
        return self.spec.get('nose_profile') or self.NOSE_STYLE[self.spec['front_style']]

    def nose_D(self, y):
        st = self.nose_style()
        return self.Lf * np.clip(smooth_interp(st["D"], y), 0.0, 1.0)

    def nose_thetas(self, q):
        st = self.nose_style(); tw = st["theta_w"]
        n1 = {0: 12, 1: 7, 2: 5, 3: 3, 4: 2}[q]; n2 = {0: 22, 1: 11, 2: 8, 3: 4, 4: 3}[q]
        a = tw * np.sin(np.linspace(0, 1, n1 + 1) * math.pi / 2)              # resserré près du flanc
        b = np.linspace(tw, math.pi / 2, n2 + 1)[1:]
        return np.concatenate([a, b])

    def nose_xz(self, th, y, inset=0.0):
        p = self.nose_style()["p"]
        xw = float(self.prof_x(y)) - inset; D = max(float(self.nose_D(y)) - inset, 0.0)
        c = np.clip(np.cos(th), 0, 1); s_ = np.clip(np.sin(th), 0, 1)
        return xw * c ** (2 / p), D * s_ ** (2 / p)

    def nose_grid(self, zj, dirz, q, inset=0.0):
        """Grille (R, C, 3) : flanc droit (θ = 0) -> pointe (θ = π/2) -> flanc gauche. Renvoie G, Θ, part
        (1 = zone pare-brise possible, θ >= theta_w), ys."""
        ys = self.nose_rows(q)
        th = self.nose_thetas(q); tw = self.nose_style()["theta_w"]
        ths = np.concatenate([th, (math.pi - th[::-1])[1:]])
        rows = []
        for y in ys:
            # Curve both glass boundaries in the actual mesh, without floating
            # overlay masks or clipping the underlying body to a generic rectangle.
            angle = np.minimum(ths, math.pi - ths)
            u = np.clip((angle - tw) / max(math.pi/2-tw, 0.01), 0, 1)
            edge = (1-u)**6
            ws = self.fr.get('windshield', {})
            dl = float(ws.get('lower_curve_m', 0)) * edge
            dh = -float(ws.get('upper_curve_m', 0)) * edge
            if y < self.ws_lo: delta = dl * max(0,(y-self.yb)/(self.ws_lo-self.yb))
            elif y > self.ws_hi: delta = dh * max(0,(self.h-y)/(self.h-self.ws_hi))
            else: delta = dl + (dh-dl)*(y-self.ws_lo)/(self.ws_hi-self.ws_lo)
            yy = y + delta
            # Vector-valued y on a column is evaluated separately; only tens of
            # columns per row, offline authoring, no simulation-time cost.
            points = [self.nose_xz(a, float(hh), inset) for a,hh in zip(angle,yy)]
            x = np.array([p[0] for p in points]); dz = np.array([p[1] for p in points])
            x = np.where(ths <= math.pi / 2, x, -x)
            rows.append(np.stack([x, yy, zj + dirz * dz], 1))
        G = np.array(rows)
        part = (np.minimum(ths, math.pi - ths) >= tw - 1e-9).astype(int)
        S = np.tile(ths, (len(ys), 1))
        if dirz > 0:
            G = G[:, ::-1]; S = S[:, ::-1]; part = part[::-1]
        return G, S, part, ys

    def half_width_at(self, back, y, inset=0.0):
        """Demi-largeur intérieure du nez à `back` m en arrière de la pointe, hauteur y."""
        p = self.nose_style()["p"]; D = float(self.nose_D(y)); xw = float(self.prof_x(y)) - inset
        dz = self.Lf - back
        if dz <= 0: return xw
        if dz >= D: return 0.0
        sn = (dz / D) ** (p / 2); th = math.asin(min(sn, 1.0))
        return xw * math.cos(th) ** (2 / p)

    def face_point(self, x, y, zj, dirz):
        """Point de la surface avant en (x, y) et normale sortante."""
        p = self.nose_style()["p"]
        def zat(xx, yy):
            xw = float(self.prof_x(yy)); D = float(self.nose_D(yy))
            c = min(abs(xx) / xw, 1.0) ** (p / 2)
            th = math.acos(c)
            return zj + dirz * D * math.sin(th) ** (2 / p)
        z = zat(x, y); e = 0.004
        dzx = (zat(x + e, y) - zat(x - e, y)) / (2 * e); dzy = (zat(x, y + e) - zat(x, y - e)) / (2 * e)
        n = np.array([-dzx, -dzy, 1.0]); n = n / np.linalg.norm(n)
        if n[2] * dirz < 0: n = -n
        return np.array([x, y, z]), n

    # ------------------------------------------------------------ utilitaires
    def zf(self, zg):
        return zg + self.L / 2

    def cab_len(self):
        return max(self.Lf + 1.05, 2.25)   # loge : nez + 1,05 m (cloison), au moins 2,25 m (faces plates TFS/Vevey)

    def cab_horizontal_ring(self, y, zj, direction, rear, inset=WALL):
        """Floor/ceiling clipped to the rounded nose; rectangular front corners
        otherwise poke through the windshield after a profile change.
        """
        th = self.nose_thetas(2)
        angles = np.concatenate([th, (math.pi-th[::-1])[1:]])
        points = []
        for angle in angles:
            x, dz = self.nose_xz(min(angle, math.pi-angle), y, inset)
            points.append([x if angle<=math.pi/2 else -x, y, zj+direction*dz])
        width = float(self.prof_x(y))-inset
        points.extend([[-width,y,rear],[width,y,rear]])
        return np.array(points)
