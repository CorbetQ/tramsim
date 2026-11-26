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
        # P4 : loge à plancher haut (TFS) : pupitre/siège modelés au plancher de référence puis remontés de dy
        self.dy = max(0.0, train.floor - 0.40); self.fl = train.floor - self.dy
        B.base = np.array([0, 0, m0["zc"]])
        self.meta = {}
        self.controls = {}; self.screens = {}; self.lamps = []
        self.labels = []      # (x, d, texte) pour la texture du pupitre
        self._mats()

    def _mats(self):
        B = self.B
        B.material("cab_lining", color=lin("#bfc3c6"), rough=0.65, tex="textures/cab_grain.png")
        B.material("cab_plastic", color=lin("#3a3e42"), rough=0.55)
        B.material("cab_plastic_light", color=lin(self.t.spec.get("cab_plastic", "#b4b9bd")), rough=0.55, tex="textures/cab_grain.png")
        B.material("cab_panel", color=lin("#2b2e31"), rough=0.6)
        B.material("cab_desk", color=(1, 1, 1, 1), tex="textures/cab_desk_mobile.png" if self.q else "textures/cab_desk.png", rough=0.6)
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
            B.material("screen_" + s, color=lin("#07090b"), emissive=(0.01, 0.025, 0.04), rough=0.12)
        B.material("lamp_lens_off", color=lin("#dfe3e6"), rough=0.05)

    # ------------------------------------------------------------------ géométrie du pupitre
    DS = 0.12     # recul du pupitre vers le conducteur (coordonnées de mise en page -> réelles)

    def zk(self, d):
        return self.tip + d + self.DS

    def zd(self, d):
        return self.tip + d

    # Pupitre enveloppant : profil (d, y) balayé en X avec un retour des ailes vers le conducteur (wrap(x)).
    PROF = [(0.12, 1.05), (0.30, 1.055), (0.60, 1.075), (0.645, 1.085), (0.68, 1.100), (1.04, 1.200), (1.085, 1.214), (1.13, 1.214),
            (1.165, 1.196), (1.185, 1.16), (1.19, 1.12), (1.17, 0.98), (1.10, 0.70), (1.00, 0.36)]
    PANEL = (4, 5)          # indices du plan incliné principal (d 0.68 -> 1.04)

    def wrap(self, x):
        return float(self.t.spec.get("cab", {}).get("wrap", 0.20)) * (min(abs(x), 1.0) / 0.95) ** 2.4

    def desk_profile(self):
        P = np.array(self.PROF, float); P[-1, 1] = self.fl + 0.02
        return P

    def desk_y(self, x, d):
        P = self.desk_profile(); dd = d - self.wrap(x)
        i0, i1 = self.PANEL
        if dd >= P[i0][0]:
            (d0, y0), (d1, y1) = P[i0], P[i1]
        else:
            (d0, y0), (d1, y1) = P[2], P[3]
        return y0 + (y1 - y0) * (dd - d0) / (d1 - d0)

    def desk_point(self, x, d):
        """Point et normale du plan incliné du pupitre (surface galbée)."""
        e = 0.005
        p = np.array([x, self.desk_y(x, d), self.zk(d)])
        px = np.array([x + e, self.desk_y(x + e, d), self.zk(d)]) - np.array([x - e, self.desk_y(x - e, d), self.zk(d)])
        pd = np.array([x, self.desk_y(x, d + e), self.zk(d + e)]) - np.array([x, self.desk_y(x, d - e), self.zk(d - e)])
        n = nz(np.cross(pd, px))
        if n[1] < 0: n = -n
        return p, n

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
        B.fan(t.cab_horizontal_ring(fl+self.dy+.005,self.zj,-1,zb),"cab_floor",normal=(0,1,0))
        yc = 2.42
        B.fan(t.cab_horizontal_ring(yc,self.zj,-1,zb),"cab_lining",normal=(0,-1,0))
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
        first = len(B.order)
        B.node("desk", root, (0, 1.1, self.zd(0.9)))
        self.desk_body()
        self.hood()
        # ---------------------------------------------------------- commandes
        self.controls_layout()
        self.overhead()
        self.side_console()
        # ---------------------------------------------------------- siège et pédales
        self.seat()
        self.pedals()
        # ---------------------------------------------------------- point de vue
        if self.dy > 0:
            moved = set(B.order[first:])
            for n in moved: B.nodes[n]["pos"] = np.asarray(B.nodes[n]["pos"], float) + np.array([0, self.dy, 0])
            for (n, mname), pieces in B.geo.items():
                if n in moved:
                    for piece in pieces: piece[0][:, 1] += self.dy
        eye = np.array([0.0, fl + self.dy + 1.37, self.zd(1.86)])
        B.node("cam_driver", root, eye, rot=rot_x(-11.0))
        self.meta_build(eye)
        self.desk_texture(texdir)
        return B

    def desk_body(self):
        """Tablette galbée : grille (profil × largeur) à normales lissées, plan incliné texturé (légendes)."""
        t, B, q = self.t, self.B, self.q
        P = self.desk_profile()
        nxc = 28 if q == 0 else 14
        xs = np.sin(np.linspace(-1, 1, nxc + 1) * math.pi / 2) * 0.97
        # subdivision des congés : points du profil interpolés
        prof = []
        for i in range(len(P) - 1):
            k = 3 if (i >= 4 and i <= 9 and q == 0) else 1
            for j in range(k): prof.append(P[i] + (P[i + 1] - P[i]) * j / k)
        prof.append(P[-1]); prof = np.array(prof)
        G = np.zeros((len(prof), nxc + 1, 3)); UV = np.zeros((len(prof), nxc + 1, 2))
        for r, (d, y) in enumerate(prof):
            for c, x in enumerate(xs):
                dd = d + self.wrap(x)
                hw = self.half_width(dd + self.DS, y)
                xx = float(np.clip(x, -hw, hw))
                G[r, c] = (xx, y, self.zk(dd)); UV[r, c] = self.duv(xx, dd)
        N = grid_normals(G, away=(0, 0.8, self.zk(0.80)))
        R = len(prof)
        top = np.zeros((R - 1, nxc), bool)
        top[:int(np.argmin(np.abs(prof[:, 0] - 1.04) + np.abs(prof[:, 1] - 1.2)))] = True
        emit(B, G, N, UV, top, "cab_desk")
        emit(B, G, N, np.stack([G[..., 0], G[..., 1]], -1) * 2, ~top, "cab_plastic_light")
        # joues latérales
        for c, s in ((0, -1), (nxc, 1)):
            B.fan(G[:, c], "cab_plastic_light", normal=np.array([s, 0, 0.0]))
        # bourrelet de bord (caoutchouc) suivant le galbe
        path = [(x, 1.218, self.zk(1.11 + self.wrap(x))) for x in np.linspace(-0.9, 0.9, 19 if q == 0 else 9)]
        B.tube(path, 0.016, "cab_rubber", seg=10 if q == 0 else 6, caps=True)
        # grille de dégivrage sur le rebord
        for k in range(16 if q == 0 else 6):
            x = -0.75 + 1.5 * k / (15 if q == 0 else 5)
            B.box((x, 1.068, self.zd(0.45)), (0.075, 0.006, 0.22), "cab_rubber")
        # plaques rapportées sombres (aile gauche, aile droite, clavier central)
        self.plates = []
        for (xa, xb, da, db) in ((-0.88, -0.40, 0.70, 1.04), (0.40, 0.88, 0.70, 1.04), (-0.30, 0.30, 0.965, 1.035)):
            self.plate(xa, xb, da, db)

    def plate(self, xa, xb, da, db):
        """Plaque sombre (1 cm) épousant le plan incliné, coins arrondis."""
        B, q = self.B, self.q
        n = 10 if q == 0 else 5
        xs = np.linspace(xa, xb, n + 1); ds = np.linspace(da, db, 4)
        G = np.array([[self.desk_point(x, d)[0] + self.desk_point(x, d)[1] * 0.008 for x in xs] for d in ds])
        N = np.array([[self.desk_point(x, d)[1] for x in xs] for d in ds])
        UVp = np.array([[self.duv(x, d) for x in xs] for d in ds])
        emit(B, G, N, UVp, np.ones((3, n), bool), "cab_desk")
        # chants
        for row in (G[0], G[-1]):
            ring = np.vstack([row, row[::-1] - N[0][: len(row)] * 0.008])
        for edge in (G[0], G[-1], G[:, 0], G[:, -1]):
            E = np.array([edge, edge - np.array([0, 0.008, 0])])
            emit(B, E, grid_normals(E, away=(0, 0.8, self.zk(0.8))), np.zeros(E.shape[:2] + (2,)), np.ones((1, len(edge) - 1), bool), "cab_panel")
        self.plates.append((xa, xb, da, db))

    def half_width(self, d, y):
        return self.t.half_width_at(d, y, inset=WALL) - 0.03

    def duv(self, x, d):
        x0, x1, d0, d1 = DESK_UV
        return ((x - x0) / (x1 - x0), (d - d0) / (d1 - d0))

    def hood(self):
        """Capot d'instruments galbé : écrans encastrés sur la face inclinée."""
        B, q = self.B, self.q
        lay = self.t.spec.get("cab_layout", "tri")
        prof = [(0.56, 1.08), (0.56, 1.30), (0.585, 1.335), (0.63, 1.345), (0.67, 1.335), (0.95, 1.19), (0.95, 1.17)]
        w = {"tri": 0.52, "duo": 0.53, "classic": 0.44}[lay]; nx = 16 if q == 0 else 8
        if lay == "duo":      # Bombardier/Siemens/CAF/Stadler : capot plus bas et plus large, deux grands écrans
            prof = [(0.58, 1.08), (0.58, 1.26), (0.60, 1.29), (0.64, 1.30), (0.68, 1.29), (0.97, 1.18), (0.97, 1.16)]
        elif lay == "classic":  # Citadis 1re génération, Dualis, TFS, Vevey, Breda : bloc d'instruments à cadrans
            prof = [(0.56, 1.08), (0.56, 1.33), (0.58, 1.36), (0.62, 1.37), (0.66, 1.36), (0.90, 1.22), (0.90, 1.19)]
        xs = np.linspace(-w, w, nx + 1)
        G = np.array([[(x, y - 0.03 * (x / w) ** 2, self.zk(d + 0.06 * (x / w) ** 2)) for x in xs] for d, y in prof])
        N = grid_normals(G, away=(0, 1.1, self.zk(0.75)))
        emit(B, G, N, np.stack([G[..., 0], G[..., 1]], -1) * 3, np.ones((len(prof) - 1, nx), bool), "cab_plastic_light")
        for c, s in ((0, -1), (nx, 1)):
            B.fan(G[:, c], "cab_plastic_light", normal=np.array([s, 0, 0.0]))
        a = np.array([0, prof[4][1], self.zk(prof[4][0])]); b = np.array([0, prof[5][1], self.zk(prof[5][0])])
        up = nz(a - b); n = nz(np.cross(np.array([1.0, 0, 0]), up))
        if n[2] < 0: n = -n
        self.hood_n = n; self.hood_up = up
        screens = {"tri": (("speed", -0.30, 0.25, 0.17, 0.5), ("info", 0.0, 0.27, 0.18, 0.5), ("next_stop", 0.30, 0.25, 0.17, 0.5)),
                   "duo": (("info", -0.215, 0.36, 0.19, 0.52), ("speed", 0.215, 0.36, 0.19, 0.52), ("next_stop", 0.0, 0.1, 0.05, 0.92)),
                   "classic": (("speed", -0.27, 0.15, 0.15, 0.5), ("info", 0.0, 0.2, 0.13, 0.5), ("next_stop", 0.27, 0.15, 0.15, 0.5))}[lay]
        for name, xc, ww, hh, f in screens:
            c = b + (a - b) * f + np.array([xc, -0.03 * (xc / w) ** 2, 0.06 * (xc / w) ** 2]) + n * 0.004
            self.screen(name, c, ww, hh, up, n, px=(320, 200), recess=True)
            if lay == "classic" and name != "info":   # cadran rond chromé autour de l'afficheur
                B.use("desk")
                B.cyl(c - n * 0.02, c + n * 0.0005, 0.112, "cab_metal", seg=24 if q == 0 else 12, cap_mat="btn_black")
        # rangée de voyants sous les écrans
        for i, lid in enumerate(("doors", "panto", "power", "emergency", "sand", "headlights", "autopilot")):
            x = -0.27 + i * 0.09
            p = b + (a - b) * 0.12 + np.array([x, 0, 0]) + n * 0.002
            self.lamp(lid, p, n)
        # écran signal sur le dessus du capot
        top_n = nz(np.array([0, 1.0, 0.18]))
        c = np.array([0.0, 1.344, self.zk(0.62)]) + top_n * 0.004
        up2 = nz(np.cross(top_n, [1, 0, 0]) * -1)
        if up2[2] > 0: up2 = -up2
        self.screen("signal", c, 0.12, 0.07, up2, top_n, px=(160, 96))
        # écrans caméras de rétrovision : petits, à la base des montants
        for s, lr in ((-1, "L"), (1, "R")):
            c = np.array([s * 0.74, 1.30, self.zk(0.62)])
            nn_ = nz(np.array([-s * 0.35, 0.15, 1.0]))
            upv = nz(np.cross(nn_, np.cross([0, 1.0, 0], nn_)))
            B.use("desk")
            B.rbox(c - nn_ * 0.02, (0.15, 0.11, 0.03), 0.01, "cab_plastic", basis=(nz(np.cross(upv, nn_)), upv, nn_), seg=2)
            B.cyl(c - nn_ * 0.035, c - nn_ * 0.035 - np.array([0, 0.12, 0]), 0.01, "cab_metal", seg=6)
            self.screen("mirror_" + lr, c + nn_ * 0.0, 0.125, 0.085, upv, nn_, px=(256, 180))

    def screen(self, name, c, w, h, up, n, px, recess=False):
        B = self.B
        X = nz(np.cross(up, n))
        nd = "screen_" + name
        B.use("desk")
        if recess:   # cadre encastré : quatre bords biseautés
            for sx, sy, ww, hh in ((0, 1, w + 0.04, 0.02), (0, -1, w + 0.04, 0.02), (1, 0, 0.02, h + 0.04), (-1, 0, 0.02, h + 0.04)):
                cc = c + X * sx * (w / 2 + 0.01) + up * sy * (h / 2 + 0.01) + n * 0.004
                B.box(cc, (ww, hh, 0.012), "btn_black", basis=(X, up, n))
            B.box(c - n * 0.004, (w + 0.01, h + 0.01, 0.004), "btn_black", basis=(X, up, n))
        else:
            B.box(c - n * 0.012, (w + 0.03, h + 0.03, 0.022), "btn_black", basis=(X, up, n))
        B.node(nd, "desk", c + n * 0.0015, rot=np.stack([X, up, n], 1))
        P = np.array([c - X * w / 2 - up * h / 2, c + X * w / 2 - up * h / 2, c + X * w / 2 + up * h / 2, c - X * w / 2 + up * h / 2]) + n * 0.0015
        B.add(P, np.tile(n, (4, 1)), [(0, 1), (1, 1), (1, 0), (0, 0)], [[0, 1, 2], [0, 2, 3]], "screen_" + name)
        B.use("desk")
        self.screens[nd] = {"px": list(px), "size_m": [round(w, 3), round(h, 3)]}

    # ------------------------------------------------------------------ commandes
    def controls_layout(self):
        L = self.labels
        # aile gauche (main gauche) : manipulateur, sablage, klaxon, portes gauche, inverseur, clé
        self.lever("notch", -0.62, 0.88)
        L += [(-0.62, 1.03, "MANIPULATEUR"), (-0.70, 0.73, "T"), (-0.62, 0.73, "0"), (-0.54, 0.73, "F")]
        self.button("horn", -0.80, 0.80, 0.020, "btn_white", label="KLAXON", square=True)
        self.button("sand", -0.80, 0.92, 0.018, "btn_yellow", label="SABLAGE", square=True)
        self.button("doors_left", -0.47, 0.80, 0.020, "btn_green", label="PORTES G", square=True)
        self.rotary("reverser", -0.47, 0.94, label="AV 0 AR", positions=[-45, 0, 45])
        self.screen_notch()
        # clavier central (12 touches) + clé
        cols = ["btn_white", "btn_white", "btn_white", "btn_yellow", "btn_yellow", "btn_green", "btn_red", "btn_white"]
        for i in range(2):
            for j in range(8):
                self.small_key(-0.25 + j * 0.065, 0.985 + i * 0.03, cols[(i * 3 + j) % len(cols)])
        self.key("key", 0.27, 1.0)
        # aile droite : portes, urgence, pilote auto, pantographe, alimentation, phares, essuie-glace, rétros
        self.mushroom("emergency", 0.70, 0.98)
        L.append((0.70, 1.07, "URGENCE"))
        self.button("doors", 0.47, 0.98, 0.026, "btn_green", label="PORTES QUAI")
        self.button("doors_right", 0.47, 0.86, 0.020, "btn_green", label="PORTES D", square=True)
        self.button("doors_close", 0.58, 0.86, 0.020, "btn_red", label="FERMETURE", square=True)
        self.button("autopilot", 0.58, 0.98, 0.019, "btn_blue", label="PILOTE", square=True)
        self.toggle("pantograph", 0.70, 0.86, label="PANTO")
        self.rotary("power_mode", 0.81, 0.86, label="APS  LAC", positions=[-40, 40])
        self.rotary("headlights", 0.47, 0.75, label="PHARES", positions=[-30, 0, 30])
        self.rotary("wiper", 0.60, 0.75, label="ESS.-GL.", positions=[-30, 0, 30])
        self.toggle("mirrors", 0.72, 0.75, label="RETROS")
        # rangées de commandes secondaires (non liées : éclairage, chauffage, annonces...)
        for i, (x, d, m) in enumerate([(0.82, 0.75, "btn_white"), (0.82, 0.98, "btn_orange"), (-0.70, 0.98, "btn_white"),
                                       (-0.70, 0.80, "btn_white"), (-0.80, 1.00, "btn_blue")]):
            self.small_key(x, d, m)

    def small_key(self, x, d, mat):
        """Touche carrée à bord arrondi (décor : non reliée à une action)."""
        B = self.B
        p, n = self.desk_point(x, d)
        F = np.stack([np.array([1.0, 0, 0]), nz(np.cross(n, [1.0, 0, 0])), n], 1)
        B.use("desk")
        B.rbox(p + n * 0.012, (0.045, 0.024, 0.008), 0.005, "btn_black", basis=(F[:, 0], F[:, 1], F[:, 2]), seg=1)
        B.rbox(p + n * 0.0175, (0.036, 0.017, 0.004), 0.004, mat, basis=(F[:, 0], F[:, 1], F[:, 2]), seg=1)

    def _panel_frame(self, x, d):
        p, n = self.desk_point(x, d)
        X = np.array([1.0, 0, 0]); Y = nz(np.cross(n, X)); Z = n
        return p, np.stack([X, Y, Z], 1)

    def _ctl(self, action, p, R, kind, **params):
        name = "ctl_" + action
        self.B.node(name, "desk", p, rot=R)
        self.controls[name] = dict(kind=kind, **params)
        return name

    def button(self, action, x, d, r, mat, label=None, travel=0.006, square=False):
        B, q = self.B, self.q
        p, R = self._panel_frame(x, d); n = R[:, 2]
        seg = 20 if q == 0 else 12
        B.use("desk")
        if square:   # bouton-poussoir carré lumineux (enjoliveur + calotte translucide)
            bas = (R[:, 0], R[:, 1], R[:, 2])
            B.rbox(p + n * 0.006, (2.6 * r + 0.012, 2.0 * r + 0.012, 0.012), 0.004, "btn_black", basis=bas, seg=1)
            self._ctl(action, p, R, "button", axis="z", travel_m=-travel)
            B.rbox(p + n * 0.015, (2.6 * r, 2.0 * r, 0.008), 0.003, mat, basis=bas, seg=2)
            if label: self.labels.append((x, d + 0.05, label))
            return
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
        p, R = self._panel_frame(-0.70, 1.0)
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

    def overhead(self):
        """Pupitre de plafond (au-dessus du pare-brise) : interrupteurs à bascule, voyants, haut-parleur."""
        B, t, q = self.B, self.t, self.q
        B.use("cab_shell")
        y0 = 2.42; d0, d1 = 0.95, 1.30
        a = np.array([0, y0 - 0.20, self.zd(d0)]); b = np.array([0, y0, self.zd(d1)])
        n = nz(np.array([0, -(b[2] - a[2]), (b[1] - a[1])]))
        if n[2] < 0: n = -n
        up = nz(a - b)
        X = np.array([1.0, 0, 0])
        c = (a + b) / 2
        B.box(c - n * 0.03, (1.1, np.linalg.norm(b - a), 0.06), "cab_plastic", basis=(X, up, n))
        for i in range(10 if q == 0 else 5):
            x = -0.45 + i * (0.9 / (9 if q == 0 else 4))
            p = c + X * x + up * 0.03
            B.box(p + n * 0.006, (0.03, 0.05, 0.012), "btn_black", basis=(X, up, n))
            B.box(p + n * 0.014 + up * 0.008, (0.024, 0.02, 0.006), "btn_white" if i % 3 else "btn_orange", basis=(X, up, n))
            lp = c + X * x - up * 0.07
            B.lathe(lp, n, [(0.008, 0), (0.008, 0.003), (0.0005, 0.005)], "lamp_lens_off", seg=8)
        # haut-parleur / micro
        B.lathe(c + X * 0.62, n, [(0.06, 0), (0.06, 0.01), (0.0005, 0.012)], "btn_black", seg=16 if q == 0 else 8)

    def side_console(self):
        """Console latérale droite : radio sol-train avec combiné, porte-documents."""
        B, t, q = self.B, self.t, self.q
        B.use("desk")
        x = 0.93; d = 1.45; y = 1.05
        B.rbox((x, y - 0.25, self.zd(d)), (0.16, 0.5, 0.42), 0.02, "cab_plastic", seg=2)
        top = np.array([x, y + 0.005, self.zd(d)])
        B.box(top + np.array([0, 0.01, 0]), (0.15, 0.02, 0.4), "cab_desk")
        B.rbox(top + np.array([-0.02, 0.04, -0.08]), (0.06, 0.05, 0.2), 0.02, "btn_black", basis=(np.array([1.0, 0, 0]), np.array([0, 0, 1.0]), np.array([0, -1.0, 0])), seg=2)
        B.cyl(top + np.array([0.03, 0.03, -0.12]), top + np.array([0.03, 0.03, 0.08]), 0.004, "cab_rubber", seg=6)
        for k in range(4):
            B.box(top + np.array([-0.03 + 0.02 * k, 0.025, 0.1]), (0.015, 0.006, 0.015), "btn_white")
        B.box(top + np.array([0.0, 0.03, 0.13]), (0.1, 0.03, 0.05), "screen_info" if False else "btn_black")
        # porte-documents sur la cloison latérale gauche
        B.box((-0.98, 1.35, self.zd(1.5)), (0.02, 0.3, 0.25), "cab_plastic_light")
        B.box((-0.965, 1.33, self.zd(1.5)), (0.005, 0.24, 0.2), "btn_white")

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
        im = Image.new("RGB", (W, H), tuple(self.t.spec.get("cab", {}).get("desk", (168, 172, 176))))
        d = ImageDraw.Draw(im)
        rng = np.random.default_rng(3)
        a = np.asarray(im, np.float32) + rng.normal(0, 2.2, (H, W, 3))
        im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)); d = ImageDraw.Draw(im)
        x0, x1, d0, d1 = DESK_UV
        px = lambda x, dd: (int((x - x0) / (x1 - x0) * W), int((dd - d0) / (d1 - d0) * H))
        # panneaux rapportés (ailes) et vis
        for (xa, xb, da, db) in getattr(self, "plates", []):
            A = px(xa, da); Bp = px(xb, db)
            d.rounded_rectangle([A, Bp], radius=16, fill=(44, 47, 51), outline=(20, 22, 24), width=5)
            for (xx, dd) in ((xa + 0.015, da + 0.012), (xb - 0.015, da + 0.012), (xa + 0.015, db - 0.012), (xb - 0.015, db - 0.012)):
                c = px(xx, dd); d.ellipse([c[0] - 7, c[1] - 7, c[0] + 7, c[1] + 7], fill=(120, 124, 128))
        f = ImageFont.truetype(TX.FONT, 22); fs = ImageFont.truetype(TX.FONT, 30)
        for (x, dd, txt) in self.labels:
            c = px(x, dd)
            font = fs if len(txt) == 1 else f
            w = d.textlength(txt, font=font)
            on_plate = any(xa <= x <= xb and da <= dd <= db for xa, xb, da, db in getattr(self, "plates", []))
            dark_desk = sum(self.t.spec.get("cab", {}).get("desk", (168, 172, 176))) < 360
            d.text((c[0] - w / 2, c[1] - 12), txt, fill=(228, 230, 232) if (on_plate or dark_desk) else (35, 37, 40), font=font)
        # graduations du manipulateur
        for k in range(-4, 5):
            c = px(-0.70 + 0.075 * 0.0, 0.93 + k * 0.026)
            d.line([(c[0] + 45, c[1]), (c[0] + 70 if k % 2 == 0 else c[0] + 60, c[1])], fill=(230, 230, 230), width=3)
        im.save(os.path.join(texdir, "cab_desk.png"), optimize=True)
        im.resize((1024, 512), Image.Resampling.LANCZOS).save(os.path.join(texdir, "cab_desk_mobile.png"), optimize=True)
        # grain de plastique (habillage, pupitre clair) : albédo neutre + normale
        n = 512
        g = TX._noise(n, 2, 5) * 0.6 + TX._noise(n, 16, 6) * 0.4
        Image.fromarray((226 + (g - 0.5) * 14).clip(0, 255).astype(np.uint8)).convert("RGB").save(os.path.join(texdir, "cab_grain.png"), optimize=True)


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
                       "pitch_deg": -11.0, "fov_deg": 62.0, "near_m": 0.05,
                       "note": "cabine B : même cab.glb sous le dernier module, rotation 180° Y"},
        }
