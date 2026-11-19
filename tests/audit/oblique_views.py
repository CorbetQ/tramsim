#!/usr/bin/env python3
"""Vues en perspective des zones complexes (ponts, viaducs, trémies, échangeurs, quais) : jeu vs référence réelle.

  oblique_views.py prepare VILLE DOSSIER [N]  -> DOSSIER/<ville>/sites.json + ref_<site>.npz (référence : MNS LiDAR HD
                                                 à 2 m, sinon MNT RGE ALTI + orthophoto IGN z17 drapée)
  godot ... -s tests/audit/oblique_shots.gd -- DOSSIER/<ville>/sites.json  -> jeu_<site>_<vue>.png, ref_<site>_<vue>.png
  oblique_views.py compose VILLE DOSSIER       -> <site>_<vue>.jpg (jeu | référence) et planche.jpg
Sites : ouvrages BD TOPO (tronçons de route et de voie ferrée au-dessus ou au-dessous du sol, fusionnés), les plus
longs, à 700 m les uns des autres, dans le décor détaillé ; plus les sites manuels de tests/audit/oblique_sites.json.
Vues : « obl » (caméra à 38°, 170 m de recul, perpendiculaire à l'ouvrage), « haut » (60°, 320 m), « rue » (1,8 m,
dans l'axe, à 60 m de l'ouvrage).
"""
import json, math, os, sys

import numpy as np
from shapely.geometry import LineString
from shapely.ops import linemerge

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools/import"))
import terrain as T                                   # noqa: E402
from ign_scene import Ortho, frame_inv_np            # noqa: E402

HALF = 450.0            # m, demi-côté de la référence
MNS = ("https://data.geopf.fr/wms-r?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap"
       "&LAYERS=IGNF_LIDAR-HD_MNS_ELEVATION.ELEVATIONGRIDCOVERAGE.WGS84G&STYLES=normal&CRS=EPSG:4326"
       "&BBOX={:.7f},{:.7f},{:.7f},{:.7f}&WIDTH={}&HEIGHT={}&FORMAT=image/geotiff")


def sites(city, frame, n):
    scene = json.load(open(os.path.join(ROOT, "data/scenes", city + ".json")))
    tiles = T.scene_tiles(city) - {tuple(t) for t in scene.get("light_tiles", [])}
    keys = np.array(sorted(tiles))
    lo, hi = keys.min(0) * 400.0, (keys.max(0) + 1) * 400.0
    la, lo_ = frame.inv(lo[0], hi[1]); lb, lob = frame.inv(hi[0], lo[1])
    llb = (min(la, lb), min(lo_, lob), max(la, lb), max(lo_, lob))
    segs = []
    for layer in ("troncon_de_route", "troncon_de_voie_ferree"):
        for f in T.cached_features(layer, os.path.join(T.SCRATCH, "ign_cache"), llb):
            pr = f["properties"]
            if not f.get("geometry") or T.pos_sol(pr) == 0 or pr.get("nature") in ("Sentier", "Chemin", "Escalier"):
                continue
            for l in T.lines3d(f["geometry"], frame):
                if len(l) >= 2:
                    segs.append((T.pos_sol(pr) > 0, LineString(l[:, :2])))
    out = []
    for up in (True, False):
        m = linemerge([s for u, s in segs if u == up])
        parts = [m] if m.geom_type == "LineString" else list(getattr(m, "geoms", []))
        for g in sorted(parts, key=lambda g: -g.length):
            c = g.interpolate(0.5, normalized=True)
            t = (math.floor(c.x / 400), math.floor(c.y / 400))
            if t not in tiles or g.length < 40:
                continue
            if any(math.hypot(c.x - o["x"], c.y - o["z"]) < 700 for o in out):
                continue
            a, b = g.interpolate(0.4, normalized=True), g.interpolate(0.6, normalized=True)
            out.append({"name": ("pont" if up else "tremie") + f"_{len(out) + 1}", "x": c.x, "z": c.y,
                        "dir": math.atan2(b.y - a.y, b.x - a.x), "len": round(g.length)})
            if sum(1 for o in out if o["name"].startswith("pont" if up else "tremie")) >= (n * 2 // 3 if up else n - n * 2 // 3):
                break
    man = os.path.join(ROOT, "tests/audit/oblique_sites.json")
    if os.path.exists(man):
        for s in json.load(open(man)).get(city, []):
            x, z = frame.fwd(s["lat"], s["lon"])
            out.append({"name": s["name"], "x": float(x), "z": float(z), "dir": math.radians(s.get("dir_deg", 0)), "len": 0})
    return out


def reference(frame, alt0, s, path, cache):
    """Hauteurs (MNS LiDAR HD, sinon MNT) à 2 m et orthophoto à 1 m sur ±HALF autour du site."""
    import subprocess
    from PIL import Image
    n = int(2 * HALF / 2.0)
    x0, z0 = s["x"] - HALF, s["z"] - HALF
    la, lo = frame.inv(x0, z0 + 2 * HALF); lb, lob = frame.inv(x0 + 2 * HALF, z0)
    tif = path + ".tif"
    subprocess.run(["curl", "-sS", "-m", "120", "-o", tif, MNS.format(min(la, lb), min(lo, lob), max(la, lb), max(lo, lob), n, n)])
    h = None
    try:
        h = np.array(Image.open(tif), dtype=np.float32)
        if np.isfinite(h).mean() < 0.8 or np.nanmax(h) > 5000 or np.nanmin(h) < -100:
            h = None
    except Exception:
        h = None
    if os.path.exists(tif):
        os.remove(tif)
    src = "MNS LiDAR HD"
    if h is None:
        dem = T.Dem(frame, os.path.join(T.SCRATCH, "dem"), "ref")
        gx, gz = np.meshgrid(x0 + (np.arange(n) + 0.5) * 2.0, z0 + (np.arange(n) + 0.5) * 2.0)
        h = dem(gx, gz).astype(np.float32); src = "MNT RGE ALTI"
    m = 1000
    gx, gz = np.meshgrid(x0 + (np.arange(m) + 0.5) * 2 * HALF / m, z0 + (np.arange(m) + 0.5) * 2 * HALF / m)
    lat, lon = frame_inv_np(frame, gx, gz)
    o = Ortho(os.path.join(T.SCRATCH, "ortho"))
    o.prefetch(17, o.keys_for(17, lat[::25, ::25], lon[::25, ::25]))
    rgb, ok = o.sample(17, lat, lon)
    Image.fromarray((rgb * 255).astype(np.uint8)).save(path + ".png")
    np.save(path + ".npy", (h - alt0).astype(np.float32))
    return src


def prepare(city, out, n=6):
    meta = json.load(open(os.path.join(ROOT, "data/scenes", city + ".json")))
    frame = T.Frame(*meta["origin"])
    alt0 = json.load(open(os.path.join(ROOT, "data/scenes", city + "_terrain.json")))["alt0"]
    d = os.path.join(out, city); os.makedirs(d, exist_ok=True)
    ss = sites(city, frame, int(n))
    for s in ss:
        s["ref"] = reference(frame, alt0, s, os.path.join(d, "ref_" + s["name"]), T.SCRATCH)
        s["half"] = HALF
    json.dump({"city": city, "origin": meta["origin"], "sites": ss}, open(os.path.join(d, "sites.json"), "w"), indent=1)
    print(f"{city}: {len(ss)} sites -> {d}")


def compose(city, out, tag="apres"):
    from PIL import Image, ImageDraw, ImageFont
    d = os.path.join(out, city)
    js = json.load(open(os.path.join(d, "sites.json")))
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 20)
    rows = []
    for s in js["sites"]:
        for v in ("obl", "haut", "rue"):
            a, b = os.path.join(d, f"jeu_{s['name']}_{v}.png"), os.path.join(d, f"ref_{s['name']}_{v}.png")
            if not (os.path.exists(a) and os.path.exists(b)):
                continue
            ia, ib = Image.open(a).convert("RGB").resize((800, 450)), Image.open(b).convert("RGB").resize((800, 450))
            im = Image.new("RGB", (1600, 450)); im.paste(ia, (0, 0)); im.paste(ib, (800, 0))
            dr = ImageDraw.Draw(im)
            for x, t in ((0, f"{city} {s['name']} {v} — jeu ({tag})"), (800, f"référence : orthophoto IGN sur {s['ref']}")):
                dr.rectangle([x, 0, x + 800, 30], fill=(10, 14, 20)); dr.text((x + 8, 4), t, font=f, fill=(255, 250, 235))
            im.save(os.path.join(d, f"{s['name']}_{v}_{tag}.jpg"), quality=85)
            rows.append(im.resize((1200, 338)))
    if rows:
        sheet = Image.new("RGB", (1200, 338 * len(rows)))
        for i, r in enumerate(rows):
            sheet.paste(r, (0, 338 * i))
        sheet.save(os.path.join(d, f"planche_{tag}.jpg"), quality=80)
    print(f"{city}: {len(rows)} comparaisons -> {d}")


if __name__ == "__main__":
    mode, city, out = sys.argv[1:4]
    if mode == "prepare":
        prepare(city, out, *sys.argv[4:5])
    else:
        compose(city, out, *sys.argv[4:5])
