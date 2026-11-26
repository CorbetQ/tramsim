"""Textures des rames HD (générées, CC0 production du projet ; métal dérivé de Poly Haven CC0) :
- atlas de livrée 4096×2048 (flancs en coordonnées (zf, y), face avant en (x, y)) + réductions 2048 / 512 / 256 ;
- sol voyageurs (albédo + normale), tissu de siège par réseau, métal de bogie (couche rusty_metal_02 de la
  bibliothèque P1, désaturée). Les UV des maillages suivent ATLAS (voir side_uv / front_uv)."""
import math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from specs import hex2rgb, ROOT

AW, AH = 4096, 2048
SIDE_H = 1280            # bande des flancs : v ∈ [0, SIDE_H/AH]
YMAX = 3.4
FRONT = (0, 1280, 768, 768)   # x, y, w, h (pixels) : face avant
XF = 1.3                 # |x| couvert par la face avant
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_R = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def side_uv(zf, y, L):
    u = np.asarray(zf, float) / L
    v = (YMAX - np.asarray(y, float)) / YMAX * (SIDE_H / AH)
    return np.stack([u, v], -1)


def front_uv(x, y):
    fx, fy, fw, fh = FRONT
    u = (fx + (np.asarray(x, float) + XF) / (2 * XF) * fw) / AW
    v = (fy + (YMAX - np.asarray(y, float)) / YMAX * fh) / AH
    return np.stack([u, v], -1)


def _rgb(h):
    return np.array(hex2rgb(h)) * 255.0


class Painter:
    def __init__(self, train):
        self.t = train; s = train.spec; self.c = s["colors"]
        self.img = np.zeros((AH, AW, 3), np.float32)
        L = train.L
        self.Z = (np.arange(AW) + 0.5) / AW * L                       # zf par colonne
        self.Y = YMAX - (np.arange(SIDE_H) + 0.5) / SIDE_H * YMAX      # y par ligne
        fx, fy, fw, fh = FRONT
        self.FX = -XF + (np.arange(fw) + 0.5) / fw * 2 * XF
        self.FY = YMAX - (np.arange(fh) + 0.5) / fh * YMAX

    # -------------------------------------------------------------- primitives de flanc
    def side_fill(self, mask, col):
        self.img[:SIDE_H][mask] = _rgb(col)

    def rect(self, z0, z1, y0, y1, col, r=0.0):
        Zg, Yg = np.meshgrid(self.Z, self.Y)
        m = (Zg >= z0) & (Zg <= z1) & (Yg >= y0) & (Yg <= y1)
        if r > 0:
            cz = np.clip(Zg, z0 + r, z1 - r); cy = np.clip(Yg, y0 + r, y1 - r)
            m &= (Zg - cz) ** 2 + (Yg - cy) ** 2 <= r * r
        self.side_fill(m, col)

    def rainbow(self, z0, z1, y0, y1, colors, angle_deg=70.0, lean=1.0, clip=None):
        """Bloc de bandes obliques : bords z = zb + lean*(y - y0)/tan(angle)."""
        Zg, Yg = np.meshgrid(self.Z, self.Y)
        sh = lean * (Yg - y0) / math.tan(math.radians(angle_deg))
        zz = Zg - sh
        m = (zz >= z0) & (zz < z1) & (Yg >= y0) & (Yg <= y1)
        if clip is not None: m &= clip(Zg, Yg)
        k = np.clip(((zz - z0) / (z1 - z0) * len(colors)).astype(int), 0, len(colors) - 1)
        if lean < 0: k = len(colors) - 1 - k
        for i, c in enumerate(colors):
            self.side_fill(m & (k == i), c)

    # -------------------------------------------------------------- face avant
    def front_fill(self, fn):
        fx, fy, fw, fh = FRONT
        Xg, Yg = np.meshgrid(self.FX, self.FY)
        out = fn(Xg, Yg)
        if out is not None:
            for col, m in out:
                self.img[fy:fy + fh, fx:fx + fw][m] = _rgb(col)

    # -------------------------------------------------------------- livrée complète
    def paint(self):
        t = self.t; c = self.c; L = t.L
        Zg, Yg = np.meshgrid(self.Z, self.Y)
        self.side_fill(np.ones_like(Zg, bool), c["base"])
        self.side_fill(Yg > t.cant + 0.02, c.get("roof_side", c["base"]))
        self.side_fill(Yg < 0.31, c["skirt"])
        rule = t.spec["livery_rule"]
        # baies et portes (visibles en LOD2/3 ; masquées par la géométrie en LOD0/1)
        win = c["window"]
        if rule == "naolib":
            # bandeau vitré continu entre les portes
            for m in t.mods:
                self.rect(t.zf(m["zA"]) + 0.05, t.zf(m["zB"]) - 0.05, t.wb - 0.03, t.wt + 0.05, win)
        for m in t.mods:
            for a, b in m["windows"]:
                self.rect(t.zf(a) - 0.03, t.zf(b) + 0.03, t.wb - 0.03, t.wt + 0.03, win, r=0.06)
        if rule == "irigo_x05":
            self._irigo_x05()
        elif rule == "liveries_json":
            self._liveries_json()
        elif rule == "naolib":
            self._naolib()
        elif rule == "elements":
            self._elements()
        for m in t.mods:
            for d in m["doors"]:
                z0, z1 = t.zf(d["z0"]), t.zf(d["z1"])
                self.rect(z0, z1, t.door_bot, t.door_top, c["door"])
                self.rect(z0 + 0.03, z1 - 0.03, t.door_bot, t.door_top, "#4a4f52")   # joints de vantaux
                for k in range(d["leaves"]):
                    a = z0 + (z1 - z0) * k / d["leaves"]; b = z0 + (z1 - z0) * (k + 1) / d["leaves"]
                    self.rect(a + 0.07, b - 0.07, 0.62, t.door_top - 0.12, win, r=0.05)
        self._front()
        self._seams()
        self._marks()
        return self

    def _seams(self):
        """Joints de caisse fins (portes, extrémités, jupe) et ombre de bas de caisse."""
        t = self.t
        Zg, Yg = np.meshgrid(self.Z, self.Y)
        img = self.img[:SIDE_H]
        line = np.zeros_like(Zg, bool)
        for m in t.mods:
            for d in m["doors"]:
                for z in (t.zf(d["z0"]) - 0.025, t.zf(d["z1"]) + 0.025):
                    line |= (np.abs(Zg - z) < 0.006) & (Yg > 0.3) & (Yg < t.door_top + 0.03)
                line |= (np.abs(Yg - (t.door_top + 0.03)) < 0.005) & (Zg > t.zf(d["z0"]) - 0.025) & (Zg < t.zf(d["z1"]) + 0.025)
        line |= (np.abs(Yg - (t.skirt + 0.0)) < 0.005) & (Yg > 0)
        img[line] *= 0.72
        ao = 0.72 + 0.28 * np.clip((Yg - 0.25) / 0.35, 0, 1) ** 0.7
        img *= ao[..., None]

    def _irigo_x05(self):
        t = self.t; L = t.L; rb = t.spec["rainbow"]
        for m in t.mods:
            for d in m["doors"]:
                z0, z1 = t.zf(d["z0"]), t.zf(d["z1"])
                front_half = (z0 + z1) / 2 < L / 2
                lean = 1.0 if front_half else -1.0
                # blocs bas de part et d'autre de la porte (jupe -> allège)
                self.rainbow(z0 - 1.02, z0 - 0.08, 0.31, t.wb - 0.06, rb, 72, lean)
                self.rainbow(z1 + 0.08, z1 + 0.80, 0.31, t.wb - 0.06, rb, 72, lean)
                # bandeau haut, au-dessus de la porte, jusqu'au pavillon
                self.rainbow(z0 - 0.35, z1 + 0.35, t.wt + 0.06, YMAX, rb, 60, lean)

    def _liveries_json(self):
        t = self.t; L = t.L; liv = t.spec["livery_json"]
        for el in liv.get("elements", []):
            if el.get("type") != "diagonal" or "sides" not in el.get("zone", ""):
                continue
            y0, y1 = el["y"]; zr = el.get("z", [0, 1]); cols = el["colors"]
            spans = [(zr[0] * L, zr[1] * L, 1.0, cols)]
            if el.get("symmetric"):
                spans.append(((1 - zr[1]) * L, (1 - zr[0]) * L, -1.0, cols[::-1]))
            for a, b, lean, cc in spans:
                a = max(a, t.Lf * 0.5)
                b = min(b, L - t.Lf * 0.5) if lean < 0 else b
                self.rainbow(a, b, y0, min(y1, t.wb - 0.04) if el.get("zone") == "sides" else y1, cc,
                             float(el.get("angle_deg", 60)), lean)

    def _elements(self):
        """Livrée générique (P4) : éléments résolus de liveries.json (bandes, obliques, filets, dégradés)."""
        t = self.t; L = t.L
        Zg, Yg = np.meshgrid(self.Z, self.Y)
        for el in t.spec["livery_res"].get("elements", []):
            typ = el.get("type"); zone = el.get("zone", "sides"); cols = el["colors"]
            if "sides" not in zone: continue
            y0, y1 = [float(v) for v in el.get("y", [0.45, 0.6])]
            if typ == "band":
                n = len(cols)
                for i, col in enumerate(cols):
                    a = y0 + (y1 - y0) * i / n; b = y0 + (y1 - y0) * (i + 1) / n
                    self.side_fill((Yg >= a) & (Yg <= b), col)
            elif typ == "stripes":
                n = max(1, len(cols)); hh = (y1 - y0) / (2 * n - 1)
                for i, col in enumerate(cols):
                    a = y0 + 2 * i * hh
                    self.side_fill((Yg >= a) & (Yg <= a + hh), col)
            elif typ == "gradient":
                if len(cols) == 1: cols = cols + [self.c["base"]]
                k = np.clip((Yg - y0) / max(y1 - y0, 1e-3), 0, 1) * (len(cols) - 1)
                i0 = np.clip(k.astype(int), 0, len(cols) - 2); f = (k - i0)[..., None]
                ca = np.array([_rgb(c) for c in cols])
                m = (Yg >= y0) & (Yg <= y1)
                self.img[:SIDE_H][m] = (ca[i0] * (1 - f) + ca[i0 + 1] * f)[m]
            elif typ == "diagonal":
                zr = el.get("z", [0, 1]); spans = [(zr[0] * L, zr[1] * L, 1.0, cols)]
                if el.get("symmetric"): spans.append(((1 - zr[1]) * L, (1 - zr[0]) * L, -1.0, cols[::-1]))
                for a, b, lean, cc in spans:
                    self.rainbow(max(a, t.Lf * 0.5), min(b, L - t.Lf * 0.5), y0, y1, cc, float(el.get("angle_deg", 60)), lean)
            elif typ == "panel" and el.get("pattern") == "visuals":
                # vitrophanies : panneaux de couleur entre les portes (évocation, sans motif)
                for m in t.mods:
                    for a, b in m["windows"][::2]:
                        self.rect(t.zf(a) + 0.2, t.zf(b) - 0.2, max(y0, t.skirt + 0.05), min(y1, t.wb - 0.06), cols[0], r=0.08)

    def _naolib(self):
        t = self.t; c = self.c; L = t.L
        # joues avant blanches jusqu'à la première porte, tablier vert
        for zf0, zf1 in ((0.0, t.zf(t.mods[0]["doors"][0]["z0"]) - 0.12), (t.zf(t.mods[-1]["doors"][-1]["z1"]) + 0.12, L)):
            self.rect(zf0, zf1, 0.31, t.cant, c["front"])
            self.rect(zf0, zf1, t.wb - 0.03, t.wt + 0.05, c["window"])
        Zg, Yg = np.meshgrid(self.Z, self.Y)
        self.side_fill(Yg > t.cant - 0.04, c["roof"])
        self.side_fill((Yg > t.cant - 0.07) & (Yg <= t.cant - 0.04), c["accent"])

    def _front(self):
        t = self.t; c = self.c; st = t.spec["front_style"]
        def fn(X, Y):
            out = [(c["front"], np.ones_like(X, bool)), (c["skirt"], Y < 0.31)]
            if st == "x05":
                out.append((c["mask"], (Y > t.ws_lo - 0.05) & (Y < 3.17) & (np.abs(X)<1.055)))
                out.append(("#2a2e31", (Y > 0.31) & (Y < 0.40)))
            elif st == "x05_nantes":
                out.append((c["apron"], (Y < 0.64) & (Y > 0.31) & (np.abs(X)<1.06)))
                out.append((c["mask"], (Y>0.64) & (Y<1.20) & (np.abs(X)<1.035)))
                out.append((c["mask"], (Y>1.25) & (Y<3.18) & (np.abs(X)<1.035)))
            elif t.spec.get("livery_rule") == "elements":
                out.append((c["mask"], (Y > t.ws_lo - 0.08) & (Y < t.ws_hi + 0.12) & (np.abs(X) < 1.12)))
                for el in t.spec["livery_res"].get("elements", []):
                    zone = el.get("zone", ""); y0, y1 = [float(v) for v in el.get("y", [0.45, 0.6])]
                    if el.get("type") == "front_mask":
                        out.append((el["colors"][0], (Y > max(y0, t.skirt)) & (Y < min(y1, t.ws_hi + 0.12)) & (np.abs(X) < 1.12)))
                    elif "front" in zone and el.get("type") in ("band", "stripes", "diagonal", "gradient"):
                        out.append((el["colors"][0], (Y >= y0) & (Y <= min(y1, t.ws_lo - 0.1))))
                    elif el.get("type") == "panel" and el.get("pattern") == "ring":
                        out.append((el["colors"][0], ((X / 0.95) ** 2 + ((Y - 0.5 * (y0 + y1)) / (0.5 * (y1 - y0))) ** 2 < 1.0)
                                    & ((X / 0.80) ** 2 + ((Y - 0.5 * (y0 + y1)) / (0.42 * (y1 - y0))) ** 2 > 1.0)))
                    elif el.get("type") == "panel" and el.get("pattern") == "led_bars":
                        out.append((el["colors"][0], (np.abs(np.abs(X) - 0.7) < 0.22) & (Y > y0) & (Y < y0 + 0.06)))
                out.append((c["roof"], Y > t.ws_hi + 0.25))
            else:
                out.append((c["mask"], (Y > t.ws_lo - 0.08) & (Y < t.ws_hi + 0.25)))
                out.append((c["roof"], Y > t.ws_hi + 0.25))
            return out
        self.front_fill(fn)
        # flancs du nez (zone flanc du maillage) : même masque autour du pare-brise
        Zg, Yg = np.meshgrid(self.Z, self.Y)
        L = t.L
        for near in ((Zg < t.Lf + 0.02), (Zg > L - t.Lf - 0.02)):
            if st in ("x05", "x05_nantes"):
                self.side_fill(near & (Yg > t.ws_lo - 0.12) & (Yg < t.cant), c["mask"])
            else:
                self.side_fill(near & (Yg > t.ws_lo - 0.08) & (Yg < t.ws_hi + 0.25), c["mask"])

    def _marks(self):
        """Numéro de parc (flanc avant et face), petites inscriptions."""
        t = self.t; num = t.spec.get("fleet_number", "")
        im = Image.fromarray(np.clip(self.img, 0, 255).astype(np.uint8))
        d = ImageDraw.Draw(im)
        f = ImageFont.truetype(FONT, 30)
        px = lambda zf, y: (int(zf / t.L * AW), int((YMAX - y) / YMAX * SIDE_H))
        for zf in (t.Lf + 0.35, t.L - t.Lf - 0.75):
            d.text(px(zf, 0.95), num, fill=(40, 44, 48), font=f)
        fx, fy, fw, fh = FRONT
        fx0 = fx + int((-0.85 + XF) / (2 * XF) * fw); fy0 = fy + int((YMAX - (t.ws_hi + 0.32)) / YMAX * fh)
        d.text((fx0, fy0), num, fill=(235, 238, 240), font=ImageFont.truetype(FONT, 22))
        self.pil = im
        return im

    def swatches(self, colors):
        """Pastilles unies (64 px) des matériaux fusionnés dans l'atlas (zone x >= 768, y >= 1280)."""
        d = ImageDraw.Draw(self.pil)
        for i, (m, hx) in enumerate(sorted(colors.items())):
            x = 800 + (i % 50) * 64; y = 1312 + (i // 50) * 64
            d.rectangle([x - 16, y - 16, x + 80, y + 80], fill=tuple(int(v * 255) for v in hex2rgb(hx)))
        return self

    def save(self, outdir, name):
        os.makedirs(outdir, exist_ok=True)
        im = self.pil.filter(ImageFilter.GaussianBlur(0.6))
        files = {}
        for tag, size in (("4k", (AW, AH)), ("2k", (AW // 2, AH // 2)), ("512", (512, 256)), ("256", (256, 128))):
            p = os.path.join(outdir, "%s_%s.png" % (name, tag))
            im.resize(size, Image.LANCZOS).save(p, optimize=True)
            files[tag] = p
        return files


# ------------------------------------------------------------------ textures de matériaux
def _noise(n, scale, seed):
    rng = np.random.default_rng(seed)
    a = rng.random((n // scale + 2, n // scale + 2)).astype(np.float32)
    im = Image.fromarray((a * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)
    return np.asarray(im, np.float32) / 255.0


def normal_from_height(h, strength=2.0):
    gx = np.roll(h, -1, 1) - np.roll(h, 1, 1); gy = np.roll(h, -1, 0) - np.roll(h, 1, 0)
    n = np.stack([-gx * strength, gy * strength, np.ones_like(h)], -1)   # OpenGL (Y+)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8))


def floor_textures(outdir, base_hex):
    n = 1024; rng = np.random.default_rng(7)
    base = np.array(hex2rgb(base_hex)) * 255
    h = _noise(n, 64, 1) * 0.5 + _noise(n, 8, 2) * 0.3
    spk = rng.random((n, n)) > 0.985
    alb = np.ones((n, n, 3)) * base * (0.92 + 0.12 * h[..., None])
    alb[spk] = alb[spk] * 0.55 + np.array([235, 235, 230]) * 0.45
    # grains antidérapants
    hh = h * 0.3
    yy, xx = np.mgrid[0:n, 0:n]
    dots = (((xx % 32) - 16) ** 2 + ((yy % 32) - 16) ** 2) < 9
    hh = hh + dots * 0.6
    Image.fromarray(np.clip(alb, 0, 255).astype(np.uint8)).save(os.path.join(outdir, "floor_albedo.png"), optimize=True)
    hb = np.asarray(Image.fromarray((np.clip(hh, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)), np.float32) / 255.0
    normal_from_height(hb, 3.0).save(os.path.join(outdir, "floor_normal.png"), optimize=True)


def fabric_texture(outdir, kind, colors=None):
    n = 512; rng = np.random.default_rng(11)
    yy, xx = np.mgrid[0:n, 0:n]
    weave = (np.sin(xx * math.pi / 2) * np.sin(yy * math.pi / 2)) * 0.06
    if colors:   # P4 : tissu de réseau (fond sombre + mouchetis aux couleurs de la livrée)
        base = np.array([42, 46, 52.0]) * 0.6 + np.array(hex2rgb(colors[0])) * 255 * 0.4 * 0.5
        cols = [hex2rgb(c) for c in colors]
    elif kind == "irigo":
        base = np.array([52, 55, 60.0]); cols = [hex2rgb(c) for c in ("#6a2c91", "#0096d6", "#5cb531", "#ffd500", "#f18a00", "#e2231a")]
    else:
        base = np.array([30, 64, 58.0]); cols = [hex2rgb(c) for c in ("#00a77e", "#7fcab4", "#e8efe9", "#1d2b28")]
    img = np.ones((n, n, 3)) * base * (1 + weave[..., None]) * (0.9 + 0.2 * _noise(n, 4, 3)[..., None])
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)); d = ImageDraw.Draw(im)
    for _ in range(170):
        x, y = rng.integers(0, n, 2); c = cols[rng.integers(len(cols))]
        w = int(rng.integers(10, 34)); hgt = int(rng.integers(3, 7))
        for ox in (0, -n, n):
            for oy in (0, -n, n):
                d.rectangle([x + ox, y + oy, x + ox + w, y + oy + hgt], fill=tuple(int(v * 255) for v in c))
    im = im.filter(ImageFilter.GaussianBlur(0.7))
    p = os.path.join(outdir, "fabric_%s.png" % kind); im.save(p, optimize=True)
    return p


def metal_textures(outdir):
    """Couche « acier_rail » (Poly Haven rusty_metal_02, CC0) de la bibliothèque P1, désaturée et assombrie."""
    src = os.path.join(ROOT, "assets/textures/pbr")
    k = 6
    for name, kind in (("albedo_1k.jpg", "albedo"), ("normal_1k.jpg", "normal"), ("orm_1k.jpg", "orm")):
        im = Image.open(os.path.join(src, name)).crop((0, k * 1024, 1024, (k + 1) * 1024)).resize((512, 512), Image.LANCZOS)
        if kind == "albedo":
            g = np.asarray(im.convert("L"), np.float32)
            g = (g - g.mean()) * 0.6 + 128
            im = Image.fromarray(np.clip(np.stack([g, g, g * 1.02], -1), 0, 255).astype(np.uint8))
        im.save(os.path.join(outdir, "metal_%s.png" % kind), optimize=True)
