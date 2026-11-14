#!/usr/bin/env python3
"""Vues aériennes verticales du décor (jeu) par ville : 1 vue globale + 1 vue par commune (arrondissement pour Paris,
Lyon, Marseille) traversée par le tram, comparées à l'orthophoto IGN de même cadrage.

  aerial_views.py prepare VILLE DOSSIER   -> DOSSIER/<Ville>/views.json (cadres, tracés et couleurs des lignes)
  godot ... -s tests/audit/aerial_shots.gd -- DOSSIER/<Ville>/views.json   -> DOSSIER/<Ville>/raw_*.png
  aerial_views.py compose VILLE DOSSIER   -> 00_globale.png, <commune>.png (légende), <commune>_ortho.jpg,
                                             <commune>_comparaison.jpg (jeu | orthophoto), planche.jpg (< 3 Mo)
  tests/audit/run_aerial.sh <godot> <dossier> [villes...] enchaîne les trois étapes.
Communes : BD TOPO IGN (WFS data.geopf.fr, couches commune et arrondissement_municipal), cache TERRAIN_CACHE/ign_cache.
Orthophotos : WMTS IGN (cache TERRAIN_CACHE/ortho), zoom choisi pour ~1 px d'image par pixel de vue.
"""
import json, math, os, re, sys, unicodedata

import numpy as np
from shapely.geometry import LineString, box, shape
from shapely.ops import unary_union

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools/import"))
import terrain as T                                   # noqa: E402
from ign_scene import Ortho, fetch, frame_inv_np, project_geom   # noqa: E402

PX = 1600
MIN_KM, MAX_KM = 1.2, 4.0          # côté des vues de commune
SECTOR = 3000.0                     # m, secteurs des grandes communes


def slug(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return re.sub(r"[^A-Za-z0-9]+", "_", s).strip("_")


def city_lines(city, frame):
    out, name = [], city
    for p, d in T.city_nets(city):
        name = d.get("city", name)
        nf = T.Frame(*d["origin"])
        for e in d["edges"]:
            a = np.array(e.get("pts", []), dtype=np.float64)
            if len(a) < 2:
                continue
            lat, lon = nf.inv(a[:, 0], a[:, 1])
            x, z = frame.fwd(lat, lon)
            out.append((d.get("color") or "#3377cc", np.stack([x, z], 1)))
    return name, out


def prepare(city, outdir):
    meta = json.load(open(os.path.join(ROOT, "data/scenes", city + ".json")))
    frame = T.Frame(*meta["origin"])
    name, lines = city_lines(city, frame)
    allp = np.concatenate([l for _, l in lines])
    lo, hi = allp.min(0), allp.max(0)
    geo = unary_union([LineString(l) for _, l in lines])
    # communes : emprise des tracés (lat/lon)
    la, lb = frame.inv(lo[0] - 500, hi[1] + 500), frame.inv(hi[0] + 500, lo[1] - 500)
    bb = (min(la[0], lb[0]), min(la[1], lb[1]), max(la[0], lb[0]), max(la[1], lb[1]))
    cache = os.path.join(T.SCRATCH, "ign_cache")
    polys = []
    for layer in ("BDTOPO_V3:commune", "BDTOPO_V3:arrondissement_municipal"):
        for ft in fetch(layer, bb, cache):
            if ft.get("geometry"):
                pr = ft["properties"]
                polys.append((layer.endswith("municipal"), pr.get("nom_officiel") or pr.get("nom") or "?",
                              pr.get("code_insee") or pr.get("code_insee_de_l_arrondissement") or "", ft))
    arr_parent = {n.split(" ")[0] for m, n, _, _ in polys if m}      # « Paris 5e Arrondissement » -> Paris
    views = []
    side = max(hi - lo) + 1200.0
    views.append({"file": "00_globale", "name": name + " — agglomération", "cx": float((lo[0] + hi[0]) / 2),
                  "cz": float((lo[1] + hi[1]) / 2), "size": float(side)})
    seen = set()
    for mun, cname, insee, ft in sorted(polys, key=lambda p: p[1]):
        if not mun and cname in arr_parent:
            continue                                     # commune découpée en arrondissements
        g = project_geom(shape(ft["geometry"]), frame)
        g = unary_union(g) if isinstance(g, list) else g
        part = geo.intersection(g)
        if part.is_empty or part.length < 150.0 or cname in seen:
            continue
        seen.add(cname)
        x0, z0, x1, z1 = part.bounds
        ext = max(x1 - x0, z1 - z0)
        if ext + 600.0 <= MAX_KM * 1000:
            s = max(ext + 600.0, MIN_KM * 1000)
            views.append({"file": slug(cname), "name": cname, "cx": (x0 + x1) / 2, "cz": (z0 + z1) / 2, "size": s,
                          "km": round(part.length / 1000, 2)})
            continue
        # grande commune : un cadre de SECTOR m par secteur traversé (« quartier »), nommé par sa direction
        n = math.ceil((ext + 600.0) / SECTOR)
        cx0, cz0 = (x0 + x1) / 2 - n * SECTOR / 2, (z0 + z1) / 2 - n * SECTOR / 2
        mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
        for i in range(n):
            for j in range(n):
                cell = part.intersection(box(cx0 + i * SECTOR, cz0 + j * SECTOR, cx0 + (i + 1) * SECTOR, cz0 + (j + 1) * SECTOR))
                if cell.is_empty or cell.length < 400.0:
                    continue
                c = ((cx0 + (i + 0.5) * SECTOR), (cz0 + (j + 0.5) * SECTOR))
                dx, dz = c[0] - mx, c[1] - mz
                if math.hypot(dx, dz) < SECTOR * 0.5:
                    where = "centre"
                else:
                    a = (math.degrees(math.atan2(-dz, dx)) + 360) % 360       # 0 = est, 90 = nord
                    where = ["est", "nord-est", "nord", "nord-ouest", "ouest", "sud-ouest", "sud", "sud-est"][int((a + 22.5) // 45) % 8]
                label = f"{cname} {where}"
                k = 2
                while any(v["name"] == label for v in views):
                    label = f"{cname} {where} {k}"; k += 1
                views.append({"file": slug(label), "name": label, "cx": c[0], "cz": c[1], "size": SECTOR + 400.0,
                              "km": round(cell.length / 1000, 2)})
    d = os.path.join(outdir, name)
    os.makedirs(d, exist_ok=True)
    js = {"city": city, "name": name, "origin": meta["origin"], "px": PX, "views": views,
          "lines": [{"color": c, "pts": [[round(float(x), 1), round(float(z), 1)] for x, z in l[:: max(1, len(l) // 400)]]}
                    for c, l in lines]}
    json.dump(js, open(os.path.join(d, "views.json"), "w"), ensure_ascii=False)
    print(f"{city}: {len(views)} vues -> {d}")
    return d


def font(sz):
    from PIL import ImageFont
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


def caption(img, text, sub=""):
    from PIL import ImageDraw
    d = ImageDraw.Draw(img, "RGBA")
    f, f2 = font(max(18, img.width // 40)), font(max(13, img.width // 70))
    w = d.textlength(text, font=f)
    h = f.size + (f2.size + 8 if sub else 0) + 18
    d.rectangle([0, 0, w + 40, h], fill=(10, 14, 20, 175))
    d.text((20, 9), text, font=f, fill=(255, 250, 235))
    if sub:
        d.text((20, 13 + f.size), sub, font=f2, fill=(220, 220, 210))
    return img


def ortho_view(frame, v, px, ortho):
    lat0 = frame.inv(v["cx"], v["cz"])[0]
    mpp = v["size"] / px
    z = int(min(18, max(10, round(math.log2(156543.03 * math.cos(math.radians(lat0)) / mpp)))))
    s = (np.arange(px) + 0.5) / px * v["size"] - v["size"] / 2
    X, Z = np.meshgrid(v["cx"] + s, v["cz"] + s)
    lat, lon = frame_inv_np(frame, X, Z)
    ortho.prefetch(z, ortho.keys_for(z, lat[::16, ::16], lon[::16, ::16]))
    rgb, ok = ortho.sample(z, lat, lon)
    from PIL import Image
    return Image.fromarray((rgb * 255).astype(np.uint8)), z


def compose(city, outdir):
    from PIL import Image
    meta = json.load(open(os.path.join(ROOT, "data/scenes", city + ".json")))
    frame = T.Frame(*meta["origin"])
    name, _ = city_lines(city, frame)
    d = os.path.join(outdir, name)
    js = json.load(open(os.path.join(d, "views.json")))
    ortho = Ortho(os.path.join(T.SCRATCH, "ortho"))
    thumbs = []
    for v in js["views"]:
        raw = os.path.join(d, "raw_" + v["file"] + ".png")
        final = os.path.join(d, v["file"] + ".png")
        if not os.path.exists(raw):
            if os.path.exists(final):        # vue déjà composée : reprise dans la planche
                thumbs.append(Image.open(final).convert("RGB").resize((400, 400), Image.LANCZOS))
            else:
                print("  absente :", raw)
            continue
        img = Image.open(raw).convert("RGB")
        sub = f"vue verticale du jeu, {v['size'] / 1000:.1f} km de côté" + (f", {v['km']} km de voies" if v.get("km") else "")
        caption(img, v["name"], sub).save(os.path.join(d, v["file"] + ".png"), optimize=True)
        os.remove(raw)
        try:
            o, z = ortho_view(frame, v, js["px"], ortho)
            caption(o, v["name"] + " — orthophoto IGN", f"BD ORTHO® IGN z{z}, même cadrage").save(os.path.join(d, v["file"] + "_ortho.jpg"), quality=85)
            cmp_ = Image.new("RGB", (1600, 800))
            cmp_.paste(img.resize((800, 800), Image.LANCZOS), (0, 0)); cmp_.paste(o.resize((800, 800), Image.LANCZOS), (800, 0))
            cmp_.save(os.path.join(d, v["file"] + "_comparaison.jpg"), quality=85)
        except Exception as e:      # orthophoto indisponible : pas de comparaison
            print("  orthophoto :", e)
        thumbs.append(img.resize((400, 400), Image.LANCZOS))
    if thumbs:
        n = len(thumbs); cols = min(5, n); rows = math.ceil(n / cols)
        sheet = Image.new("RGB", (cols * 400, rows * 400), (20, 22, 26))
        for i, t in enumerate(thumbs):
            sheet.paste(t, ((i % cols) * 400, (i // cols) * 400))
        q = 85
        while True:
            sheet.save(os.path.join(d, "planche.jpg"), quality=q)
            if os.path.getsize(os.path.join(d, "planche.jpg")) < 2.9e6 or q < 40:
                break
            q -= 10
    print(f"{city}: {len(thumbs)} vues composées -> {d}")


if __name__ == "__main__":
    mode, city, out = sys.argv[1:4]
    {"prepare": prepare, "compose": compose}[mode](city, out)
