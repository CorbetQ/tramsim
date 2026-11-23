"""Loge de conduite Citadis (cab.glb), exprimée dans le repère de module_00 (cabine A, nez vers -Z).
Pupitre en trois parties (aile gauche : manipulateur, aile droite : portes / pantographe / urgence, capot central
d'écrans), siège conducteur, pédales, store, cloison, habillage du nez. Chaque commande du jeu = nœud ctl_<action>
(pivot = axe d'animation ; repère local : Z = normale sortante du panneau, X = largeur du pupitre). Les écrans sont
des quads screen_<contenu> (UV (0,0) en haut à gauche) ; les voyants em_lamp_<id>."""
import math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from geom import Builder, nz, frame_from_z, rot_x, rot_y
from layout import WALL
from citadis import lin, lining, emit, grid_normals
import textures as TX

# (action du jeu, nœud, type, paramètres) — actions de src/input/cab_actions.gd (schéma v1) + commandes annexes
DESK_UV = (-1.0, 1.0, 0.55, 1.35)      # x0, x1, d0, d1 : zone du pupitre couverte par la texture cab_desk.png


class Cab:
    def __init__(self, train, q=0):
        self.t = train; self.q = q
        B = self.B = Builder()
        m0 = train.mods[0]
        self.tip = m0["zs"]; self.zj = m0["zA"]; self.fl = train.floor
        B.base = np.array([0, 0, m0["zc"]])
        self.meta = {}
        self.controls = {}; self.screens = {}; self.lamps = []
        self.labels = []      # (x, d, texte) pour la texture du pupitre
        self._mats()

    def _mats(self):
        B = self.B
        B.material("cab_lining", color=lin("#c9cdd0"), rough=0.6)
        B.material("cab_plastic", color=lin("#3a3e42"), rough=0.55)
        B.material("cab_plastic_light", color=lin("#8e9499"), rough=0.5)
        B.material("cab_desk", color=(1, 1, 1, 1), tex="textures/cab_desk.png", rough=0.6)
        B.material("cab_floor", color=lin("#3b3f42"), tex="textures/floor_albedo.png", normal="textures/floor_normal.png", rough=0.8)
        B.material("cab_seat", color=(0.55, 0.55, 0.55, 1), tex="textures/fabric_%s.png" % self.t.spec["seat"]["fabric"], rough=0.95)
        B.material("cab_metal", color=lin("#9ea3a8"), rough=0.3, metal=1.0)
        B.material("cab_rubber", color=lin("#1c1d1e"), rough=0.9)
        B.material("btn_red", color=lin("#c8191e"), rough=0.35)
        B.material("btn_green", color=lin("#1d9a46"), rough=0.35)
        B.material("btn_blue", color=lin("#1f5fbf"), rough=0.35)
        B.material("btn_yellow", color=lin("#f0c419"), rough=0.35)
        B.material("btn_white", color=lin("#e8e8e4"), rough=0.35)
        B.material("btn_black", color=lin("#1a1b1c"), rough=0.4)
        B.material("btn_orange", color=lin("#f07d10"), rough=0.35)
        B.material("glass_cab", color=(0.05, 0.06, 0.07, 0.35), rough=0.05, alpha="BLEND", double=True)
        B.material("int_wall", color=lin(self.t.spec["interior"]["wall"]), rough=0.45)
        B.material("em_interior", color=lin("#f6f7f2"), emissive=(1.0, 0.98, 0.92), emissive_strength=1.2)
        for lid, col in (("doors", "#22d36a"), ("panto", "#3b8cff"), ("power", "#f2f2f2"), ("emergency", "#ff2a2a"),
                         ("sand", "#ffb020"), ("headlights", "#22d36a"), ("autopilot", "#3b8cff")):
            c = lin(col)
            B.material("em_lamp_" + lid, color=(c[0] * 0.25, c[1] * 0.25, c[2] * 0.25, 1), emissive=(0, 0, 0), rough=0.1,
                       extras={"on_color": col})
        for s in ("speed", "notch", "next_stop", "signal", "info", "mirror_L", "mirror_R"):
            B.material("screen_" + s, color=lin("#07090b"), emissive=(0, 0, 0), rough=0.12)
        B.material("lamp_lens_off", color=lin("#dfe3e6"), rough=0.05)

    # ------------------------------------------------------------------ géométrie du pupitre
    def zd(self, d):
        return self.tip + d

    def desk_profile(self):
        """Profil (d, y) du pupitre : rebord sous le pare-brise -> tablette inclinée -> bord arrondi -> genoux."""
        fl = self.fl
        return np.array([(0.30, 1.07), (0.70, 1.10), (1.10, 1.22), (1.19, 1.215), (1.25, 1.19), (1.28, 1.14),
                         (1.28, 1.05), (1.20, 0.80), (1.10, 0.55), (0.95, fl + 0.02)])

    def desk_point(self, x, d):
        """Point et normale de la tablette inclinée (0.70 <= d <= 1.10) ou du rebord (d < 0.70)."""
        P = self.desk_profile()
        if d >= 0.70:
            (d0, y0), (d1, y1) = P[1], P[2]
        else:
            (d0, y0), (d1, y1) = P[0], P[1]
        y = y0 + (y1 - y0) * (d - d0) / (d1 - d0)
        tz = np.array([0, y1 - y0, d1 - d0]); tz = tz / np.linalg.norm(tz)
        n = np.cross(tz, [1, 0, 0]) * -1
        n = n if n[1] > 0 else -n
        return np.array([x, y, self.zd(d)]), nz(n)

    def build(self, texdir):
        t, B, q = self.t, self.B, self.q
        B.node("cab", None, (0, 0, t.mods[0]["zc"]))
        root = "cab"
        # ---------------------------------------------------------- habillage, plancher, plafond, cloison
        B.node("cab_shell", root, (0, 0, t.mods[0]["zc"]))
        lining(B, t, self.zj, -1, "cab_lining", q=0 if q == 0 else 1)
        zb = self.tip + t.cab_len() - 0.03
        xw = t.hw - WALL - 0.003
        fl = self.fl
        B.quad((-xw, fl + 0.005, self.zd(0.45)), (-xw, fl + 0.005, zb), (xw, fl + 0.005, zb), (xw, fl + 0.005, self.zd(0.45)), "cab_floor",
               uv=[(0, 0), (0, 1.2), (1.6, 1.2), (1.6, 0)])
        yc = 2.42
        B.quad((-xw, yc, self.zd(0.85)), (xw, yc, self.zd(0.85)), (xw, yc, zb), (-xw, yc, zb), "cab_lining")
        B.node("em_interior_cab", "cab_shell", (0, yc - 0.01, self.zd(1.6)))
        B.box((0, yc - 0.012, self.zd(1.6)), (0.7, 0.012, 0.22), "em_interior")
        B.use("cab_shell")
        # cloison arrière : porte, vitre, armoire électrique
        B.box((0, (fl + yc) / 2, zb + 0.02), (2 * xw, yc - fl, 0.04), "cab_lining")
        B.box((0.35, 1.38, zb - 0.002), (0.64, 1.95, 0.012), "cab_plastic_light")
        B.box((0.10, 1.25, zb - 0.02), (0.03, 0.18, 0.03), "cab_metal")
        B.box((-0.55, 1.75, zb - 0.003), (0.48, 0.4, 0.01), "glass_cab")
        B.rbox((-0.78, 1.0, zb - 0.16), (0.36, 1.35, 0.3), 0.02, "cab_plastic_light", basis=(np.array([1.0, 0, 0]), np.array([0, 0, 1.0]), np.array([0, -1.0, 0])), seg=2)
        B.box((-0.78, 1.0, zb - 0.312), (0.30, 1.2, 0.004), "cab_plastic")
        # extincteur
        B.lathe((0.80, fl + 0.05, zb - 0.12), (0, 1, 0), [(0.001, 0), (0.07, 0.0), (0.075, 0.03), (0.075, 0.45), (0.05, 0.5), (0.02, 0.55), (0.001, 0.56)], "btn_red", seg=16 if q == 0 else 10)
        # store pare-soleil (enrouleur) en haut du pare-brise
        p, n = t.face_point(0, t.ws_hi - 0.02, self.zj, -1)
        zs_ = p[2] + 0.12
        B.cyl((-0.85, t.ws_hi - 0.03, zs_), (0.85, t.ws_hi - 0.03, zs_), 0.035, "cab_plastic", seg=12)
        B.box((0, t.ws_hi - 0.09, zs_ - 0.02), (1.6, 0.12, 0.004), "cab_plastic") if q == 0 else None
        # ---------------------------------------------------------- pupitre
        B.node("desk", root, (0, 1.1, self.zd(0.9)))
        self.desk_body()
        self.hood()
        # ---------------------------------------------------------- commandes
        self.controls_layout()
        # ---------------------------------------------------------- siège et pédales
        self.seat()
        self.pedals()
        # ---------------------------------------------------------- point de vue
        eye = np.array([0.0, fl + 1.36, self.zd(1.68)])
        B.node("cam_driver", root, eye, rot=rot_x(-9.0))
        self.meta_build(eye)
        self.desk_texture(texdir)
        return B

    def desk_body(self):
        t, B, q = self.t, self.B, self.q
        P = self.desk_profile()
        x0, x1 = -0.98, 0.98
        nseg = 2
        # tablette : prisme du profil le long de X ; la face supérieure (segments 0-1, 1-2) reçoit la texture
        for i in range(len(P) - 1):
            (da, ya), (db, yb) = P[i], P[i + 1]
            xa = self.half_width(da, ya); xb = self.half_width(db, yb)
            a0 = (-xa, ya, self.zd(da)); a1 = (xa, ya, self.zd(da)); b1 = (xb, yb, self.zd(db)); b0 = (-xb, yb, self.zd(db))
            mat = "cab_desk" if i < 2 else "cab_plastic"
            uv = None
            if i < 2:
                uv = [self.duv(-xa, da), self.duv(xa, da), self.duv(xb, db), self.duv(-xb, db)]
            Pq = np.array([a0, a1, b1, b0])
            nn = nz(np.cross(Pq[1] - Pq[0], Pq[3] - Pq[0]))
            if nn[1] < -0.2 or (abs(nn[1]) <= 0.2 and nn[2] < 0): nn = -nn
            B.add(Pq, np.tile(nn, (4, 1)), uv if uv is not None else Pq[:, ::2] * 2, [[0, 1, 2], [0, 2, 3]], mat)
        # joues latérales
        for s in (1, -1):
            ring = [(s * self.half_width(d, y), y, self.zd(d)) for d, y in P]
            B.fan(np.array(ring), "cab_plastic", normal=np.array([s, 0, 0.0]))
        # baguette de bord (main courante chromée)
        path = [(-self.half_width(1.19, 1.215) + 0.02, 1.225, self.zd(1.20)), (self.half_width(1.19, 1.215) - 0.02, 1.225, self.zd(1.20))]
        B.cyl(path[0], path[1], 0.018, "cab_rubber", seg=10)
        # grille de dégivrage sur le rebord
        for k in range(14 if q == 0 else 6):
            x = -0.7 + 1.4 * k / (13 if q == 0 else 5)
            B.box((x, 1.085, self.zd(0.48)), (0.07, 0.006, 0.2), "cab_rubber")

    def half_width(self, d, y):
        t = self.t
        s = np.clip(1.0 - d / max(t.Lfz, 1e-3), 0, float(t.smax(y)))
        return float(t.prof_x(y)) * float(t.plan_w(s)) - WALL - 0.03

    def duv(self, x, d):
        x0, x1, d0, d1 = DESK_UV
        return ((x - x0) / (x1 - x0), (d - d0) / (d1 - d0))

    def hood(self):
        """Capot central d'écrans : face inclinée vers le conducteur."""
        B, q = self.B, self.q
        prof = [(0.55, 1.12), (0.55, 1.33), (0.64, 1.355), (0.96, 1.205), (0.96, 1.19)]
        w = 0.56
        pts = lambda x: np.array([(x, y, self.zd(d)) for d, y in prof])
        L = pts(-w); R = pts(w)
        G = np.array([L, R])
        for i in range(len(prof) - 1):
            Pq = np.array([L[i], R[i], R[i + 1], L[i + 1]])
            nn = nz(np.cross(Pq[1] - Pq[0], Pq[3] - Pq[0]))
            c = Pq.mean(0)
            if np.dot(nn, c - np.array([0, 1.25, self.zd(0.75)])) < 0: nn = -nn
            B.add(Pq, np.tile(nn, (4, 1)), Pq[:, ::2] * 3, [[0, 1, 2], [0, 2, 3]], "cab_plastic")
        for s, R_ in ((-1, L), (1, R)):
            B.fan(R_, "cab_plastic", normal=np.array([s, 0, 0.0]))
        # visière
        B.box((0, 1.365, self.zd(0.67)), (2 * w + 0.04, 0.02, 0.12), "cab_plastic")
        # écrans sur la face inclinée (d 0.66 -> 0.96)
        a = np.array([0, 1.355, self.zd(0.64)]); b = np.array([0, 1.205, self.zd(0.96)])
        up = nz(a - b); n = nz(np.cross(np.array([1.0, 0, 0]), up))
        if n[2] < 0: n = -n
        self.hood_n = n; self.hood_up = up
        for name, xc, ww, hh, f in (("speed", -0.34, 0.30, 0.20, 0.48), ("info", 0.0, 0.32, 0.22, 0.48), ("next_stop", 0.34, 0.30, 0.20, 0.48)):
            c = b + (a - b) * f + np.array([xc, 0, 0]) + n * 0.003
            self.screen(name, c, ww, hh, up, n, px=(320, 200))
        # écran signal sur le haut du capot
        top_n = np.array([0, 1.0, 0.25]); top_n = top_n / np.linalg.norm(top_n)
        c = np.array([0.0, 1.345, self.zd(0.6)]) + top_n * 0.004
        up2 = nz(np.cross(top_n, [1, 0, 0]) * -1)
        if up2[2] > 0: up2 = -up2
        self.screen("signal", c, 0.14, 0.08, up2, top_n, px=(160, 96))
        # écrans caméras de rétrovision (montants)
        for s, lr in ((-1, "L"), (1, "R")):
            c = np.array([s * 0.82, 1.62, self.zd(0.62)])
            nn_ = nz(np.array([-s * 0.45, 0.1, 1.0]))
            upv = nz(np.cross(nn_, np.cross([0, 1.0, 0], nn_)))
            B.use("desk")
            B.box(c - nn_ * 0.025, (0.2, 0.15, 0.04), "cab_plastic", basis=(nz(np.cross(upv, nn_)), upv, nn_))
            B.cyl(c - nn_ * 0.04, np.array([s * 0.86, 1.25, self.zd(0.55)]), 0.012, "cab_metal", seg=6)
            self.screen("mirror_" + lr, c + nn_ * 0.0, 0.17, 0.12, upv, nn_, px=(256, 180))

    def screen(self, name, c, w, h, up, n, px):
        B = self.B
        X = nz(np.cross(up, n))
        nd = "screen_" + name
        B.use("desk")
        B.box(c - n * 0.012, (w + 0.03, h + 0.03, 0.022), "btn_black", basis=(X, up, n))
        B.node(nd, "desk", c + n * 0.0015, rot=np.stack([X, up, n], 1))
        P = np.array([c - X * w / 2 - up * h / 2, c + X * w / 2 - up * h / 2, c + X * w / 2 + up * h / 2, c - X * w / 2 + up * h / 2]) + n * 0.0015
        B.add(P, np.tile(n, (4, 1)), [(0, 1), (1, 1), (1, 0), (0, 0)], [[0, 1, 2], [0, 2, 3]], "screen_" + name)
        B.use("desk")
        self.screens[nd] = {"px": list(px), "size_m": [round(w, 3), round(h, 3)]}

    # ------------------------------------------------------------------ commandes
    def controls_layout(self):
        L = self.labels
        # aile gauche : manipulateur et commandes de la main gauche
        self.lever("notch", -0.70, 0.93)
        L += [(-0.70, 1.06, "MANIPULATEUR"), (-0.78, 0.74, "T"), (-0.70, 0.74, "0"), (-0.62, 0.74, "F")]
        self.button("horn", -0.90, 0.80, 0.022, "btn_black", label="KLAXON")
        self.button("sand", -0.50, 0.80, 0.020, "btn_yellow", label="SABLAGE")
        self.button("doors_left", -0.90, 1.02, 0.024, "btn_green", label="PORTES G")
        self.screen_notch()
        self.rotary("reverser", -0.42, 1.04, label="INVERSEUR AV 0 AR", positions=[-45, 0, 45])
        self.key("key", -0.26, 1.06)
        # aile droite
        self.mushroom("emergency", 0.86, 1.00)
        L.append((0.86, 1.10, "URGENCE"))
        self.button("doors_right", 0.62, 1.04, 0.024, "btn_green", label="PORTES D")
        self.button("doors_close", 0.74, 1.04, 0.024, "btn_red", label="FERMETURE")
        self.button("doors", 0.68, 0.92, 0.028, "btn_green", label="PORTES QUAI")
        self.button("autopilot", 0.52, 0.92, 0.02, "btn_blue", label="PILOTE AUTO")
        self.toggle("pantograph", 0.80, 0.86, label="PANTO")
        self.rotary("power_mode", 0.93, 0.86, label="APS  LAC", positions=[-40, 40])
        self.rotary("headlights", 0.58, 0.78, label="PHARES", positions=[-30, 0, 30])
        self.rotary("wiper", 0.72, 0.76, label="ESSUIE-GL.", positions=[-30, 0, 30])
        self.toggle("mirrors", 0.86, 0.75, label="RETROS")
        # voyants sur la visière du capot
        for i, lid in enumerate(("doors", "panto", "power", "emergency", "sand", "headlights", "autopilot")):
            x = -0.30 + i * 0.1
            p = np.array([x, 1.29, self.zd(0.552)])
            self.lamp(lid, p, np.array([0, 0.25, 1.0]))
        # radio (combiné)
        B = self.B; B.use("desk")
        p, n = self.desk_point(0.30, 1.0)
        B.rbox(p + n * 0.02 + np.array([0.0, 0, 0]), (0.07, 0.04, 0.2), 0.015, "btn_black", basis=frame_from_z(n).T[[0, 2, 1]].T if False else None, seg=2)

    def _panel_frame(self, x, d):
        p, n = self.desk_point(x, d)
        X = np.array([1.0, 0, 0]); Y = nz(np.cross(n, X)); Z = n
        return p, np.stack([X, Y, Z], 1)

    def _ctl(self, action, p, R, kind, **params):
        name = "ctl_" + action
        self.B.node(name, "desk", p, rot=R)
        self.controls[name] = dict(kind=kind, **params)
        return name

    def button(self, action, x, d, r, mat, label=None, travel=0.006):
        B, q = self.B, self.q
        p, R = self._panel_frame(x, d); n = R[:, 2]
        seg = 20 if q == 0 else 12
        B.use("desk")
        B.lathe(p, n, [(r + 0.008, 0.0), (r + 0.006, 0.006), (r + 0.001, 0.006), (r + 0.001, 0.0)], "cab_metal", seg=seg)
        self._ctl(action, p, R, "button", axis="z", travel_m=-travel)
        B.lathe(p, n, [(r, -0.004), (r, 0.008), (r * 0.92, 0.011), (r * 0.5, 0.0125), (0.0005, 0.0128)], mat, seg=seg)
        if label: self.labels.append((x, d + 0.055, label))

    def mushroom(self, action, x, d):
        B, q = self.B, self.q
        p, R = self._panel_frame(x, d); n = R[:, 2]
        seg = 24 if q == 0 else 14
        B.use("desk")
        B.lathe(p, n, [(0.05, 0.0), (0.05, 0.012), (0.03, 0.014), (0.03, 0.0)], "btn_yellow", seg=seg)
        self._ctl(action, p, R, "button", axis="z", travel_m=-0.012, latching=True)
        B.lathe(p, n, [(0.016, 0.0), (0.016, 0.03), (0.04, 0.035), (0.042, 0.045), (0.036, 0.058), (0.02, 0.064), (0.0005, 0.066)], "btn_red", seg=seg)

    def toggle(self, action, x, d, label=None):
        B, q = self.B, self.q
        p, R = self._panel_frame(x, d); n = R[:, 2]
        B.use("desk")
        B.rbox(p + n * 0.006, (0.05, 0.07, 0.012), 0.008, "cab_metal", basis=(R[:, 0], R[:, 1], R[:, 2]), seg=2)
        # capot de protection (rabattable : statique ici)
        B.box(p + n * 0.03 - R[:, 1] * 0.032, (0.056, 0.004, 0.04), "glass_cab", basis=(R[:, 0], R[:, 1], R[:, 2]))
        self._ctl(action, p + n * 0.012, R, "toggle", axis="x", on_deg=30.0, off_deg=-30.0)
        a = p + n * 0.012; tip = a + nz(n * 0.04 - R[:, 1] * 0.02 * 0)
        B.cyl(a, a + n * 0.035, 0.004, "cab_metal", seg=8)
        B.lathe(a + n * 0.033, n, [(0.0065, 0), (0.007, 0.006), (0.004, 0.012), (0.0005, 0.013)], "btn_black", seg=10)
        if label: self.labels.append((x, d + 0.06, label))

    def rotary(self, action, x, d, label=None, positions=(-30, 0, 30)):
        B, q = self.B, self.q
        p, R = self._panel_frame(x, d); n = R[:, 2]
        seg = 24 if q == 0 else 12
        B.use("desk")
        B.lathe(p, n, [(0.03, 0.0), (0.03, 0.003), (0.001, 0.003)], "cab_metal", seg=seg)
        self._ctl(action, p, R, "rotary", axis="z", positions_deg=list(positions))
        prof = [(0.022, 0.0), (0.022, 0.016), (0.019, 0.022), (0.0005, 0.023)]
        B.lathe(p, n, prof, "btn_black", seg=seg)
        B.box(p + n * 0.03, (0.009, 0.045, 0.016), "btn_black", basis=(R[:, 0], R[:, 1], R[:, 2]))       # index
        B.box(p + n * 0.0385 + R[:, 1] * 0.016, (0.004, 0.01, 0.002), "btn_white", basis=(R[:, 0], R[:, 1], R[:, 2]))
        if label: self.labels.append((x, d + 0.06, label))

    def key(self, action, x, d):
        B = self.B
        p, R = self._panel_frame(x, d); n = R[:, 2]
        B.use("desk")
        B.lathe(p, n, [(0.02, 0.0), (0.02, 0.008), (0.012, 0.01), (0.001, 0.01)], "cab_metal", seg=16)
        self._ctl(action, p, R, "rotary", axis="z", positions_deg=[0, 90])
        B.box(p + n * 0.025, (0.004, 0.018, 0.03), "cab_metal", basis=(R[:, 0], R[:, 1], R[:, 2]))
        B.box(p + n * 0.045, (0.006, 0.03, 0.022), "btn_black", basis=(R[:, 0], R[:, 1], R[:, 2]))
        self.labels.append((x, d + 0.05, "CLE"))

    def lever(self, action, x, d):
        """Manipulateur traction/freinage : pivot 4 cm sous la tablette, rotation autour de X local."""
        B, q = self.B, self.q
        p, R = self._panel_frame(x, d); n = R[:, 2]
        seg = 20 if q == 0 else 10
        B.use("desk")
        # platine à secteur (fente)
        B.rbox(p + n * 0.004, (0.14, 0.30, 0.008), 0.02, "cab_metal", basis=(R[:, 0], R[:, 1], R[:, 2]), seg=3)
        B.box(p + n * 0.0085, (0.018, 0.24, 0.002), "btn_black", basis=(R[:, 0], R[:, 1], R[:, 2]))
        piv = p - n * 0.04
        self._ctl(action, piv, R, "lever", axis="x", range_deg=[24.0, -24.0], game_range=[-1.0, 1.0],
                  note="cran -1 (freinage max, tiré vers le conducteur) -> +24° ; +1 (traction max, poussé) -> -24°")
        top = piv + n * 0.22
        B.cyl(piv, top, 0.011, "cab_metal", seg=seg // 2)
        B.lathe(piv + n * 0.045, n, [(0.03, 0.0), (0.028, 0.012), (0.012, 0.02), (0.011, 0.02)], "cab_rubber", seg=seg)  # soufflet
        # poignée en T avec gâchette d'homme mort
        X = R[:, 0]
        B.cyl(top - X * 0.055, top + X * 0.055, 0.017, "btn_black", seg=seg)
        B.lathe(top + X * 0.055, X, [(0.017, 0), (0.019, 0.006), (0.01, 0.015), (0.0005, 0.016)], "btn_black", seg=seg)
        B.lathe(top - X * 0.055, -X, [(0.017, 0), (0.019, 0.006), (0.01, 0.015), (0.0005, 0.016)], "btn_black", seg=seg)
        B.box(top - n * 0.03 + R[:, 1] * 0.015, (0.07, 0.012, 0.035), "btn_yellow", basis=(R[:, 0], R[:, 1], R[:, 2]))

    def screen_notch(self):
        p, R = self._panel_frame(-0.50, 1.02)
        n = R[:, 2]
        self.screen("notch", p + n * 0.012, 0.12, 0.07, R[:, 1], n, px=(160, 96))

    def lamp(self, lid, p, n):
        B = self.B
        n = nz(n); name = "em_lamp_" + lid
        B.use("desk")
        B.lathe(p - n * 0.002, n, [(0.013, 0), (0.013, 0.004), (0.009, 0.004)], "cab_metal", seg=12)
        B.node(name, "desk", p)
        B.lathe(p, n, [(0.009, 0), (0.009, 0.003), (0.005, 0.0065), (0.0005, 0.007)], name, seg=12)
        B.use("desk")
        self.lamps.append(name)

    # ------------------------------------------------------------------ siège, pédales
    def seat(self):
        B, q = self.B, self.q
        fl = self.fl
        z = self.zd(1.82)
        B.node("driver_seat", "cab", (0, fl, z))
        seg = 3 if q == 0 else 2
        B.cyl((0, fl, z), (0, fl + 0.36, z), 0.05, "cab_metal", seg=14)
        B.rbox((0, fl + 0.02, z), (0.5, 0.04, 0.5), 0.05, "cab_plastic", basis=(np.array([1.0, 0, 0]), np.array([0, 0, 1.0]), np.array([0, -1.0, 0])), seg=seg)
        B.rbox((0, fl + 0.44, z - 0.02), (0.52, 0.5, 0.11), 0.05, "cab_seat", basis=(np.array([1.0, 0, 0]), np.array([0, 0, 1.0]), np.array([0, -1.0, 0])), seg=seg)
        tilt = math.radians(14); Y = np.array([0, math.cos(tilt), math.sin(tilt)]); Zb = np.array([0, -math.sin(tilt), math.cos(tilt)])
        cb = np.array([0, fl + 0.86, z + 0.30])
        B.rbox(cb, (0.5, 0.7, 0.12), 0.06, "cab_seat", basis=(np.array([1.0, 0, 0]), Y, -Zb), seg=seg)
        B.rbox(cb + Y * 0.47 + Zb * 0.02, (0.3, 0.2, 0.1), 0.05, "cab_seat", basis=(np.array([1.0, 0, 0]), Y, -Zb), seg=seg)
        for s in (1, -1):
            B.rbox((s * 0.3, fl + 0.68, z + 0.02), (0.06, 0.06, 0.36), 0.025, "cab_plastic", seg=seg)
            B.box((s * 0.3, fl + 0.58, z + 0.18), (0.03, 0.18, 0.03), "cab_metal")

    def pedals(self):
        B = self.B; fl = self.fl
        B.use("cab")
        # repose-pieds incliné
        B.box((0, fl + 0.08, self.zd(1.12)), (0.7, 0.03, 0.32), "cab_rubber", basis=(np.array([1.0, 0, 0]), nz(np.array([0, 1, 0.5])), nz(np.array([0, -0.5, 1]))))
        # pédale de veille (homme mort, statique) et pédale de gong (ctl_bell)
        B.box((-0.18, fl + 0.13, self.zd(1.15)), (0.14, 0.02, 0.24), "cab_metal", basis=(np.array([1.0, 0, 0]), nz(np.array([0, 1, 0.45])), nz(np.array([0, -0.45, 1]))))
        piv = np.array([0.2, fl + 0.06, self.zd(1.25)])
        R = np.stack([np.array([1.0, 0, 0]), nz(np.array([0, 1, 0.45])), nz(np.array([0, -0.45, 1]))], 1)
        B.node("ctl_bell", "cab", piv, rot=R)
        self.controls["ctl_bell"] = {"kind": "pedal", "axis": "x", "on_deg": -8.0, "note": "gong au pied"}
        B.box(piv + np.array([0, 0.07, -0.12]), (0.12, 0.02, 0.22), "btn_yellow", basis=(np.array([1.0, 0, 0]), nz(np.array([0, 1, 0.45])), nz(np.array([0, -0.45, 1]))))
        B.use("cab")

    # ------------------------------------------------------------------ texture du pupitre
    def desk_texture(self, texdir):
        W, H = 2048, 1024
        im = Image.new("RGB", (W, H), (46, 49, 53))
        d = ImageDraw.Draw(im)
        rng = np.random.default_rng(3)
        a = np.asarray(im, np.float32) + rng.normal(0, 2.2, (H, W, 3))
        im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)); d = ImageDraw.Draw(im)
        x0, x1, d0, d1 = DESK_UV
        px = lambda x, dd: (int((x - x0) / (x1 - x0) * W), int((dd - d0) / (d1 - d0) * H))
        # panneaux rapportés (ailes) et vis
        for (xa, xb) in ((-0.97, -0.46), (0.46, 0.97)):
            A = px(xa, 0.70); Bp = px(xb, 1.13)
            d.rounded_rectangle([A, Bp], radius=14, fill=(58, 62, 67), outline=(30, 32, 35), width=4)
            for (xx, dd) in ((xa + 0.02, 0.72), (xb - 0.02, 0.72), (xa + 0.02, 1.11), (xb - 0.02, 1.11)):
                c = px(xx, dd); d.ellipse([c[0] - 7, c[1] - 7, c[0] + 7, c[1] + 7], fill=(120, 124, 128))
        f = ImageFont.truetype(TX.FONT, 22); fs = ImageFont.truetype(TX.FONT, 30)
        for (x, dd, txt) in self.labels:
            c = px(x, dd)
            font = fs if len(txt) == 1 else f
            w = d.textlength(txt, font=font)
            d.text((c[0] - w / 2, c[1] - 12), txt, fill=(225, 228, 230), font=font)
        # graduations du manipulateur
        for k in range(-4, 5):
            c = px(-0.70 + 0.075 * 0.0, 0.93 + k * 0.026)
            d.line([(c[0] + 45, c[1]), (c[0] + 70 if k % 2 == 0 else c[0] + 60, c[1])], fill=(230, 230, 230), width=3)
        im.save(os.path.join(texdir, "cab_desk.png"), optimize=True)

    # ------------------------------------------------------------------ manifeste
    def meta_build(self, eye):
        acts = {"ctl_notch": ("notch", "W/Z/↑, S/↓, X"), "ctl_emergency": ("emergency", "Espace"), "ctl_doors": ("doors", "O"),
                "ctl_horn": ("horn", "K"), "ctl_pantograph": ("pantograph", "P"), "ctl_reverser": ("reverser", "V"),
                "ctl_sand": ("sand", "B"), "ctl_headlights": ("headlights", "H"), "ctl_wiper": ("wiper", "E"),
                "ctl_mirrors": ("mirrors", "N"), "ctl_autopilot": ("autopilot", "L"),
                "ctl_bell": ("bell", None), "ctl_doors_left": ("doors_left", None), "ctl_doors_right": ("doors_right", None),
                "ctl_doors_close": ("doors_close", None), "ctl_power_mode": ("power_mode", "P (sélecteur APS/LAC)"), "ctl_key": ("cab_key", None)}
        for k, v in self.controls.items():
            if k in acts:
                v["action"] = acts[k][0]
                if acts[k][1]: v["key"] = acts[k][1]
        self.meta = {
            "controls": self.controls,
            "control_aliases": {"ctl_traction_lever": "ctl_notch", "ctl_reverse": "ctl_reverser"},
            "screens": self.screens,
            "lamps": self.lamps,
            "camera": {"node": "cam_driver", "frame": "module_00", "position": [round(float(v), 3) for v in (eye - self.B.base)],
                       "pitch_deg": -9.0, "fov_deg": 62.0, "near_m": 0.05,
                       "note": "cabine B : même cab.glb sous le dernier module, rotation 180° Y"},
        }
