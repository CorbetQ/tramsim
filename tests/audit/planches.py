#!/usr/bin/env python3
"""Planches-contacts de l'audit visuel : par ville, points x (ext, cab, aérien 250 m, orthophoto IGN) + nuit.
Usage : planches.py <dossier_audit> <dossier_cache_ortho> [villes...]  (lit <ville>.log produit par audit_shots.gd)"""
import io, math, os, sys, time, urllib.request
from PIL import Image, ImageDraw

WMTS = ("https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=ORTHOIMAGERY.ORTHOPHOTOS"
        "&STYLE=normal&TILEMATRIXSET=PM&TILEMATRIX=18&TILEROW={y}&TILECOL={x}&FORMAT=image/jpeg")
Z = 18
AERIAL_M = 250.0
H = 300


def tile(cache, x, y):
    p = os.path.join(cache, f"{Z}_{x}_{y}.jpg")
    if not os.path.exists(p):
        req = urllib.request.Request(WMTS.format(x=x, y=y), headers={"User-Agent": "tramsim-audit/0.11"})
        for _ in range(3):
            try:
                data = urllib.request.urlopen(req, timeout=10).read()
                Image.open(io.BytesIO(data)).verify()
                open(p, "wb").write(data)
                break
            except Exception as e:
                print("ortho", x, y, e, file=sys.stderr); time.sleep(1)
        else:
            return Image.new("RGB", (256, 256), (90, 0, 90))
    return Image.open(p).convert("RGB")


def ortho(cache, lat, lon, meters=AERIAL_M, px=H):
    n = 2 ** Z
    fx = (lon + 180) / 360 * n
    fy = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n
    mpp = 156543.03392 * math.cos(math.radians(lat)) / n  # m / pixel de tuile
    half = meters / 2 / mpp  # demi-emprise en pixels de tuile
    x0, y0, x1, y1 = fx * 256 - half, fy * 256 - half, fx * 256 + half, fy * 256 + half
    tx0, ty0, tx1, ty1 = int(x0 // 256), int(y0 // 256), int(x1 // 256), int(y1 // 256)
    mos = Image.new("RGB", ((tx1 - tx0 + 1) * 256, (ty1 - ty0 + 1) * 256))
    for tx in range(tx0, tx1 + 1):
        for ty in range(ty0, ty1 + 1):
            mos.paste(tile(cache, tx, ty), ((tx - tx0) * 256, (ty - ty0) * 256))
    box = tuple(int(round(v)) for v in (x0 - tx0 * 256, y0 - ty0 * 256, x1 - tx0 * 256, y1 - ty0 * 256))
    return mos.crop(box).resize((px, px), Image.LANCZOS)


def load(d, city, name, size, crop_square=False):
    p = os.path.join(d, f"{city}_{name}.png")
    if not os.path.exists(p):
        return Image.new("RGB", size, (40, 0, 0))
    im = Image.open(p).convert("RGB")
    if crop_square:
        w, h = im.size
        im = im.crop(((w - h) // 2, 0, (w + h) // 2, h))
    return im.resize(size, Image.LANCZOS)


def planche(d, cache, city):
    pts = []
    for l in open(os.path.join(d, f"{city}.log"), encoding="utf-8", errors="replace"):
        f = l.strip().split("|")
        if l.startswith("AUDIT|point|"):
            pts.append({"name": f[3], "lat": float(f[6]), "lon": float(f[7]), "info": f[10] if len(f) > 10 else ""})
    W1 = H * 16 // 9
    width = 2 * W1 + 2 * H
    rows = len(pts) + 1
    sheet = Image.new("RGB", (width, rows * (H + 18)), (20, 20, 20))
    dr = ImageDraw.Draw(sheet)
    for i, p in enumerate(pts):
        y = i * (H + 18)
        dr.text((4, y + 2), f"{city} / {p['name']} : {p['info']}  ({p['lat']:.5f}, {p['lon']:.5f})  | ext | cab | aerien 250 m | ortho IGN", fill=(255, 255, 0))
        sheet.paste(load(d, city, p["name"] + "_ext", (W1, H)), (0, y + 18))
        sheet.paste(load(d, city, p["name"] + "_cab", (W1, H)), (W1, y + 18))
        sheet.paste(load(d, city, p["name"] + "_aer", (H, H), True), (2 * W1, y + 18))
        sheet.paste(ortho(cache, p["lat"], p["lon"]), (2 * W1 + H, y + 18))
    y = len(pts) * (H + 18)
    dr.text((4, y + 2), f"{city} / dense : nuit 22h30", fill=(255, 255, 0))
    sheet.paste(load(d, city, "dense_nuit", (W1, H)), (0, y + 18))
    ref = os.path.join(os.path.dirname(cache.rstrip("/")), "refs_commons", f"{city}.jpg")
    if os.path.exists(ref):  # photo libre géolocalisée près du point dense (refs_commons.py)
        im = Image.open(ref).convert("RGB"); im.thumbnail((W1, H))
        sheet.paste(im, (W1, y + 18))
        dr.text((W1 + 4, y + 2), "photo Wikimedia Commons proche du point dense (voir attributions.json)", fill=(0, 255, 255))
    out = os.path.join(d, "planches", f"planche_{city}.jpg")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet.save(out, quality=85)
    return out


if __name__ == "__main__":
    d, cache = sys.argv[1], sys.argv[2]
    os.makedirs(cache, exist_ok=True)
    cities = sys.argv[3:] or sorted(f[:-4] for f in os.listdir(d) if f.endswith(".log"))
    for c in cities:
        print(planche(d, cache, c))
