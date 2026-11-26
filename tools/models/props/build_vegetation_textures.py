#!/usr/bin/env python3
"""Textures de la végétation et des decals (refonte P3, docs/CDC_REFONTE_VISUELLE.md §6).

Entrées : feuilles scannées CC0 ambientCG (LeafSet024, LeafSet027, LeafSet019, LeafSet009 en 1K-PNG), téléchargées par
`--fetch` dans un cache hors dépôt. Tout le reste (rameaux, palmes, graminées, imposteurs, decals) est généré ici.

Sorties (assets/textures/vegetation/) :
- foliage_{2k,1k}.png  : atlas 4 x 2 de cartes de rameaux RGBA (alpha découpé) :
  0 tilleul, 1 platane/érable (feuilles lobées), 2 marronnier (feuilles palmées), 3 pin (aiguilles),
  4 palme, 5 graminées, 6 vivaces fleuries, 7 haie (petites feuilles denses) ;
- impostors_{1k,512}.png : atlas 4 x 2 de silhouettes d'arbres (imposteurs lointains) :
  0 tilleul, 1 conifère, 2 érable, 3 pin parasol, 4 palmier, 5 peuplier, 6 platane, 7 marronnier ;
- decal_{grime,oil,manhole,patch}.png (512², albédo RGBA) + decal_manhole_n.png (normale OpenGL) : salissure,
  tache d'huile, plaque d'égout, rapiéçage d'enrobé et marquage usé (Decal Godot, Forward+/Mobile).
Usage : python3 -I tools/models/props/build_vegetation_textures.py --cache <dossier> [--fetch]
"""
import argparse
import json
import math
import os
import random
import subprocess
import zipfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

SETS = ["LeafSet024", "LeafSet027", "LeafSet019", "LeafSet009"]
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "..", "assets", "textures", "vegetation")
CELL = 512
SPECIES = os.path.join(os.path.dirname(__file__), "..", "..", "..", "data", "vegetation_species.json")


def fetch(cache):
    os.makedirs(cache, exist_ok=True)
    for s in SETS:
        z = os.path.join(cache, s + ".zip")
        if not os.path.exists(z):
            subprocess.run(["curl", "-sL", "-o", z, f"https://ambientcg.com/get?file={s}_1K-PNG.zip"], check=True)
        with zipfile.ZipFile(z) as f:
            for n in f.namelist():
                if n.endswith("_Color.png") or n.endswith("_Opacity.png"):
                    f.extract(n, os.path.join(cache, s))


def sprites(cache, s, min_px=400):
    """Feuilles isolées (composantes connexes du masque d'opacité), RGBA recadrées, tige vers le bas."""
    col = np.asarray(Image.open(os.path.join(cache, s, f"{s}_1K-PNG_Color.png")).convert("RGB"))
    op = np.asarray(Image.open(os.path.join(cache, s, f"{s}_1K-PNG_Opacity.png")).convert("L"))
    lab, n = ndimage.label(op > 100)
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        if sl is None:
            continue
        m = lab[sl] == i + 1
        if m.sum() < min_px:
            continue
        rgba = np.dstack([col[sl], (op[sl] * m).astype(np.uint8)])
        out.append(Image.fromarray(rgba, "RGBA"))
    return out


def recolor(im, hue_rgb, keep=0.25):
    """Teinte verte uniforme (feuilles d'automne de LeafSet027 ramenées à l'été), modelé conservé."""
    a = np.asarray(im).astype(np.float32)
    lum = (a[..., 0] * 0.3 + a[..., 1] * 0.59 + a[..., 2] * 0.11) / 255.0
    tgt = np.array(hue_rgb, np.float32)[None, None, :] * (0.55 + 0.9 * lum[..., None])
    rgb = a[..., :3] * keep + tgt * (1.0 - keep)
    return Image.fromarray(np.dstack([np.clip(rgb, 0, 255), a[..., 3]]).astype(np.uint8), "RGBA")


def shade(im, k):
    a = np.asarray(im).astype(np.float32)
    a[..., :3] *= k
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def paste_rot(dst, im, ctr, size, ang):
    w, h = im.size
    sc = size / max(w, h)
    im = im.resize((max(1, int(w * sc)), max(1, int(h * sc))), Image.LANCZOS).rotate(ang, expand=True, resample=Image.BICUBIC)
    dst.alpha_composite(im, (int(ctr[0] - im.size[0] / 2), int(ctr[1] - im.size[1] / 2)))


def twig_card(leaves, rng, n=46, size=(70, 120), bark=(92, 74, 56), spread=0.42, compound=0):
    """Carte de rameau : tige + rameaux latéraux, feuilles orientées vers l'extérieur, ombrées en profondeur."""
    c = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    d = ImageDraw.Draw(c)
    base = (CELL * 0.5, CELL * 0.98)
    tip = (CELL * 0.5 + rng.uniform(-30, 30), CELL * 0.08)
    d.line([base, tip], fill=bark + (255,), width=9)
    twigs = []
    for k in range(7):
        t = 0.25 + 0.1 * k
        p = (base[0] + (tip[0] - base[0]) * t, base[1] + (tip[1] - base[1]) * t)
        side = -1 if k % 2 else 1
        q = (p[0] + side * CELL * spread * rng.uniform(0.6, 1.0), p[1] - CELL * rng.uniform(0.08, 0.2))
        d.line([p, q], fill=bark + (255,), width=5)
        twigs.append((p, q))
    twigs.append((base, tip))
    order = sorted(range(n), key=lambda _: rng.random())
    for j, _ in enumerate(order):
        p, q = twigs[rng.randrange(len(twigs))]
        t = rng.uniform(0.15, 1.0)
        x = p[0] + (q[0] - p[0]) * t + rng.uniform(-14, 14)
        y = p[1] + (q[1] - p[1]) * t + rng.uniform(-14, 14)
        out = math.degrees(math.atan2(-(x - base[0]), -(y - base[1]) + 1e-3))
        leaf = leaves[rng.randrange(len(leaves))]
        depth = 0.62 + 0.38 * j / n          # feuilles du fond plus sombres
        if compound:
            # feuille composée palmée (marronnier) : 5 à 7 folioles en éventail
            for f in range(compound):
                a = out + (f - (compound - 1) / 2) * 26
                r = rng.uniform(*size) * 0.5
                cx = x + math.sin(math.radians(-a)) * r * 0.45
                cy = y - math.cos(math.radians(-a)) * r * 0.45
                paste_rot(c, shade(leaf, depth), (cx, cy), r * 1.25, a + rng.uniform(-6, 6))
        else:
            paste_rot(c, shade(leaf, depth * rng.uniform(0.9, 1.05)), (x, y), rng.uniform(*size), out + rng.uniform(-35, 35))
    return c


def palm_card(rng):
    c = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    d = ImageDraw.Draw(c)
    pts = [(CELL * 0.5 + 40 * math.sin(t * 1.6) * t, CELL * (0.97 - 0.9 * t)) for t in np.linspace(0, 1, 40)]
    for i in range(1, len(pts), 2):
        t = i / len(pts)
        for side in (-1, 1):
            L = CELL * 0.33 * math.sin(math.pi * min(1.0, t * 1.15)) + 6
            a = math.radians(55 + 20 * t)
            q = (pts[i][0] + side * L * math.sin(a), pts[i][1] - L * math.cos(a) * 0.55 + L * 0.35)
            g = int(rng.uniform(95, 125) * (0.8 + 0.2 * t))
            d.line([pts[i], q], fill=(int(g * 0.55), g, int(g * 0.35), 255), width=4)
    d.line(pts, fill=(130, 120, 70, 255), width=7)
    return c


def grass_card(rng, flowers=False):
    c = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    d = ImageDraw.Draw(c)
    for _ in range(140):
        x0 = CELL * 0.5 + rng.gauss(0, 60)
        h = rng.uniform(0.45, 0.95) * CELL
        bend = rng.uniform(-90, 90)
        g = rng.uniform(80, 150)
        col = (int(g * 0.62), int(g), int(g * 0.38), 255) if rng.random() < 0.85 else (int(g * 0.95), int(g * 0.9), int(g * 0.5), 255)
        pts = [(x0 + bend * (t ** 2), CELL - 1 - h * t) for t in np.linspace(0, 1, 8)]
        for i in range(len(pts) - 1):
            d.line([pts[i], pts[i + 1]], fill=col, width=max(1, int(6 * (1 - i / 8))))
        if flowers and rng.random() < 0.3:
            fc = rng.choice([(222, 180, 205), (180, 140, 210), (240, 230, 200), (230, 200, 70)])
            x, y = pts[-1]
            for k in range(5):
                a = k * 1.256
                d.ellipse([x + 9 * math.cos(a) - 7, y + 9 * math.sin(a) - 7, x + 9 * math.cos(a) + 7, y + 9 * math.sin(a) + 7], fill=fc + (255,))
            d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(240, 200, 60, 255))
    return c


def hedge_card(leaves, rng):
    c = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    for j in range(260):
        x, y = rng.uniform(20, CELL - 20), rng.uniform(20, CELL - 20)
        paste_rot(c, shade(leaves[rng.randrange(len(leaves))], 0.55 + 0.45 * j / 260), (x, y), rng.uniform(34, 52), rng.uniform(0, 360))
    return c


def bleed(im):
    """Couleur étendue sous l'alpha nul (pas de liseré sombre aux mipmaps)."""
    a = np.asarray(im).astype(np.float32)
    alpha = a[..., 3] > 8
    if alpha.any():
        idx = ndimage.distance_transform_edt(~alpha, return_distances=False, return_indices=True)
        rgb = a[..., :3][idx[0], idx[1]]
        a[..., :3] = np.where(alpha[..., None], a[..., :3], rgb)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def impostor_side(sp):
    """Côté (m) du carré de l'imposteur : hauteur totale ou largeur du houppier (+15 %). Même formule que Vegetation."""
    cy, rx, ry = sp["crown"]
    return max(cy + ry, 2.0 * rx) * 1.15


def impostor(sp, cells, rng, S=512):
    """Silhouette d'arbre pour l'imposteur (cellule S x S, pied en bas au centre), à l'échelle de l'espèce
    (data/vegetation_species.json) : le quad de Vegetation a le même côté, la silhouette coïncide avec le maillage."""
    c = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(c)
    side = impostor_side(sp)
    k = S / side
    cy, rx, ry = sp["crown"]
    th, tr = sp["trunk"]
    bark = tuple(int(sp["bark"][i:i + 2], 16) for i in (1, 3, 5))
    top = cy if sp["shape"] in ("palm", "cone") else th + (cy - th) * 0.6
    w = max(2.0, tr * k)
    d.polygon([(S / 2 - w, S), (S / 2 + w, S), (S / 2 + w * 0.6, S - top * k), (S / 2 - w * 0.6, S - top * k)], fill=bark + (255,))
    src = cells[sp["cell"]]
    if sp["shape"] == "palm":
        for j in range(16):
            a = -180 + j * 12 + rng.uniform(-5, 5)
            L = 3.0 * k
            ex = S / 2 + math.cos(math.radians(a)) * L * 0.5
            ey = S - cy * k - math.sin(math.radians(a)) * L * 0.25 + L * 0.12
            paste_rot(c, src, (ex, ey), L * 0.9, -a - 90 + (40 if a > -90 else -40) * 0.5)
        return c
    n = 260
    for j in range(n):
        u, v = rng.uniform(-1, 1), rng.uniform(-1, 1)
        if sp["shape"] == "cone":
            u *= (1 - v) / 2
        elif u * u + v * v > 1:
            continue
        x = S / 2 + u * rx * 0.85 * k
        y = S - (cy + v * ry * 0.85) * k
        lit = 0.5 + 0.35 * (v * 0.7 - u * 0.3 + 1) / 2 + 0.25 * j / n
        paste_rot(c, shade(src, lit), (x, y), sp["card"] * k * rng.uniform(0.9, 1.2), rng.uniform(-40, 40))
    return c


def decals(rng, S=512):
    al = Image.new("RGBA", (2 * S, 2 * S), (0, 0, 0, 0))
    h = np.zeros((2 * S, 2 * S), np.float32)
    yy, xx = np.mgrid[0:S, 0:S] / S - 0.5
    r = np.sqrt(xx ** 2 + yy ** 2)

    def noise(scale, seed):
        g = np.random.default_rng(seed).random((S // scale + 2, S // scale + 2)).astype(np.float32)
        return np.asarray(Image.fromarray((g * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC)).astype(np.float32) / 255

    # 0 salissure : nappe irrégulière sombre, bords doux
    n = noise(16, 1) * 0.6 + noise(4, 2) * 0.4
    a = np.clip((0.42 - r) * 4.0 + (n - 0.5) * 1.6, 0, 1) * 0.75
    al.paste(Image.fromarray(np.dstack([np.full((S, S), 44), np.full((S, S), 40), np.full((S, S), 34), a * 255]).astype(np.uint8), "RGBA"), (0, 0))
    # 1 tache d'huile : disque sombre irrégulier
    n2 = noise(8, 3)
    a = np.clip((0.33 + (n2 - 0.5) * 0.18 - r) * 9.0, 0, 1) * 0.85
    al.paste(Image.fromarray(np.dstack([np.full((S, S), 22), np.full((S, S), 22), np.full((S, S), 26), a * 255]).astype(np.uint8), "RGBA"), (S, 0))
    # 2 plaque d'égout fonte (Ø 0,8 m dans un carré de 1 m) : motif quadrillé en relief, anneau
    disc = r < 0.40
    ring = (r > 0.36) & (r < 0.40)
    grid = ((np.floor((xx + 0.5) * 22) + np.floor((yy + 0.5) * 22)) % 2 == 0)
    hh = np.where(ring, 1.0, np.where(disc & grid, 0.6, np.where(disc, 0.2, 0.0)))
    base = 52 + 18 * noise(4, 5)
    rgb = np.dstack([base, base * 0.97, base * 0.93]) * np.where(disc, 1.0, 0)[..., None]
    a = np.clip((0.405 - r) * 120, 0, 1)
    al.paste(Image.fromarray(np.dstack([rgb, a * 255]).astype(np.uint8), "RGBA"), (0, S))
    h[S:, :S] = hh
    # 3 rapiéçage d'enrobé + marquage usé : rectangle plus sombre, bande blanche érodée
    n3 = noise(6, 7) * 0.7 + noise(2, 8) * 0.3
    patch = (np.abs(xx) < 0.38) & (np.abs(yy) < 0.30)
    rgb = np.where(patch[..., None], np.dstack([np.full((S, S), 34)] * 3), np.dstack([np.full((S, S), 205)] * 3))
    band = (np.abs(xx + 0.05) < 0.08) & ~patch
    a = np.where(patch, 0.8, np.where(band & (n3 > 0.45), 0.7, 0.0))
    al.paste(Image.fromarray(np.dstack([rgb, a * 255]).astype(np.uint8), "RGBA"), (S, S))
    # normale (OpenGL) depuis la hauteur
    hb = ndimage.gaussian_filter(h, 1.2)
    gy, gx = np.gradient(hb * 6.0)
    nz = 1.0 / np.sqrt(gx ** 2 + gy ** 2 + 1)
    nm = np.dstack([(-gx * nz + 1) * 127.5, (gy * nz + 1) * 127.5, (nz + 1) * 127.5]).astype(np.uint8)
    return al, Image.fromarray(nm, "RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", required=True)
    ap.add_argument("--fetch", action="store_true")
    o = ap.parse_args()
    if o.fetch:
        fetch(o.cache)
    rng = random.Random(1789)
    lime = sprites(o.cache, "LeafSet024")
    maple = [recolor(s, (62, 104, 38), 0.2) for s in sprites(o.cache, "LeafSet027")]
    needles = sprites(o.cache, "LeafSet019", 2000)
    ovals = [recolor(s, (70, 110, 40), 0.45) for s in sprites(o.cache, "LeafSet009")]
    lime = [recolor(s, (78, 118, 46), 0.5) for s in lime]
    cells = [
        twig_card(lime, rng, 54, (64, 104)),
        twig_card(maple, rng, 40, (90, 140), bark=(120, 110, 90)),
        twig_card(ovals, rng, 24, (110, 150), compound=7),
        twig_card(needles, rng, 22, (220, 300), spread=0.3),
        palm_card(rng),
        grass_card(rng),
        grass_card(rng, True),
        hedge_card(lime, rng),
    ]
    cells = [bleed(c) for c in cells]
    os.makedirs(OUT, exist_ok=True)
    atlas = Image.new("RGBA", (4 * CELL, 2 * CELL))
    for i, c in enumerate(cells):
        atlas.paste(c, ((i % 4) * CELL, (i // 4) * CELL))
    atlas.save(os.path.join(OUT, "foliage_2k.png"), optimize=True)
    atlas.resize((2 * CELL, CELL), Image.LANCZOS).save(os.path.join(OUT, "foliage_1k.png"), optimize=True)
    small = [c.resize((128, 128), Image.LANCZOS) for c in cells]
    imp = Image.new("RGBA", (4 * 256, 2 * 256))
    species = json.load(open(SPECIES))["species"]
    for sp in species:
        k = sp["imp"]
        if k >= 0:
            imp.paste(bleed(impostor(sp, small, rng).resize((256, 256), Image.LANCZOS)), ((k % 4) * 256, (k // 4) * 256))
    imp.save(os.path.join(OUT, "impostors_1k.png"), optimize=True)
    imp.resize((512, 256), Image.LANCZOS).save(os.path.join(OUT, "impostors_512.png"), optimize=True)
    al, nm = decals(rng)
    for i, n in enumerate(["grime", "oil", "manhole", "patch"]):
        box = ((i % 2) * 512, (i // 2) * 512, (i % 2) * 512 + 512, (i // 2) * 512 + 512)
        al.crop(box).save(os.path.join(OUT, f"decal_{n}.png"), optimize=True)
    nm.crop((0, 512, 512, 1024)).save(os.path.join(OUT, "decal_manhole_n.png"), optimize=True)
    print("ok", OUT)


if __name__ == "__main__":
    main()
