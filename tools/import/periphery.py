#!/usr/bin/env python3
"""Décor élargi d'une ville : agglomération visible depuis les voies et depuis la vue aérienne de l'accueil.

Régénère data/scenes/<ville>.bin (ign_scene.py) sur des tuiles de 400 m ENTIÈRES (plus de bords de corridor
coupés en arc) qui touchent :
- un tampon de PERIPH_M autour de toutes les voies (lignes commerciales data/networks et réseau physique data/free) ;
- le cadre de la vue aérienne de l'accueil (src/ui/home_background.gd : centre = médiane des tracés urbains,
  distance d = clamp(étendue × 0,12 ; 700 ; 1300), cadre ±2,0 d × ±1,0 d, écrans jusqu'au 21:9) ;
- un disque de LANDMARK_M autour des monuments emblématiques de data/landmarks.json ;
- au-delà, décor lointain allégé (light_tiles : bâti simplifié, routes, eau, végétation BD TOPO ; sol = relief
  lointain teinté par l'occupation du sol) sur le cadre de la vue globale de l'agglomération.
Orthophotos IGN z17 dans le corridor historique de 220 m, z16 au-delà. Le fichier <ville>_track.json (nature des
plateformes) n'est pas touché. Puis sol continu (terrain_mesh.build) sur la nouvelle emprise.

Usage : TERRAIN_CACHE=<cache> periphery.py [--scene-only|--ground-only] VILLE...   (sans ville : toutes)
Cache : TERRAIN_CACHE/ign_cache (WFS BD TOPO, gzip), TERRAIN_CACHE/ortho (WMTS), TERRAIN_CACHE/dem (RGE ALTI).
"""
import json, math, os, shutil, sys, tempfile, time

import numpy as np
from shapely.geometry import Point, box

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ign_scene                      # noqa: E402
import terrain as T                   # noqa: E402

ROOT = T.ROOT
PERIPH_M = {"default": 850.0, "idf": 550.0, "lyon": 700.0, "nantes": 700.0, "bordeaux": 700.0, "strasbourg": 700.0,
            "grenoble": 750.0, "montpellier": 750.0, "lille": 700.0, "marseille": 750.0, "toulouse": 750.0}
LANDMARK_M = 320.0
# décor lointain allégé : cadre de la vue globale, à au plus LIGHT_M des voies (0 : tout le cadre)
LIGHT_M = {"default": 0, "idf": 2500.0, "lyon": 4000.0, "mulhouse": 3000.0, "valenciennes": 3000.0, "bordeaux": 4000.0}


def city_lines(city):
    """[(chemin, réseau)] : lignes commerciales puis réseau physique (data/free)."""
    out = [(p, d) for p, d in T.city_nets(city)]
    sc = json.load(open(os.path.join(ROOT, "data/scenes", city + ".json")))["origin"]
    out.sort(key=lambda pd: list(pd[1]["origin"]) != list(sc))     # origine de la scène en tête
    fp = os.path.join(ROOT, "data/free", city + ".json")
    if os.path.exists(fp):
        d = json.load(open(fp))
        if d.get("origin"):
            out.append((fp, d))
    return out


def home_frame(nets, frame):
    """Cadre de la vue d'accueil (repère de la ville), comme HomeBackground._load."""
    pts, urban = [], []
    for _, d in nets:
        if d.get("free_only") or d.get("kind") == "free":
            continue
        nf = T.Frame(*d["origin"])
        for e in d["edges"]:
            a = np.array(e.get("pts", []), dtype=np.float64)
            if len(a) < 2:
                continue
            lat, lon = nf.inv(a[:, 0], a[:, 1])
            x, z = frame.fwd(lat, lon)
            q = np.stack([x, z], 1)
            pts.append(q)
            if d.get("kind", "tram") != "tram-train":
                urban.append(q)
    if not pts:
        return None
    allp = np.concatenate(pts); cen = np.concatenate(urban or pts)
    cx, cz = float(np.median(cen[:, 0])), float(np.median(cen[:, 1]))
    ext = float(max(np.ptp(allp[:, 0]), np.ptp(allp[:, 1])))
    d = min(max(ext * 0.12, 700.0), 1300.0)
    return box(cx - 2.0 * d, cz - 1.0 * d, cx + 2.0 * d, cz + 1.0 * d)


def landmark_areas(city, frame):
    p = os.path.join(ROOT, "data/landmarks.json")
    if not os.path.exists(p):
        return []
    out = []
    for lm in json.load(open(p)).get("cities", {}).get(city, []):
        x, z = frame.fwd(lm["lat"], lm["lon"])
        out.append(Point(float(x), float(z)).buffer(LANDMARK_M, 8))
    return out


def light_tiles(city, nets, frame):
    """Tuiles du cadre de la vue globale (emprise des lignes commerciales + 600 m, carré centré, comme
    tests/audit/aerial_views.py), limitées à LIGHT_M des voies : décor lointain allégé (ign_scene light_tiles).
    Les tuiles du décor détaillé en sont retirées par ign_scene (zone élargie prioritaire)."""
    pts = []
    for _, d in nets:
        if d.get("kind") == "free":
            continue
        nf = T.Frame(*d["origin"])
        for e in d["edges"]:
            a = np.array(e.get("pts", []), dtype=np.float64)
            if len(a) >= 2:
                lat, lon = nf.inv(a[:, 0], a[:, 1])
                x, z = frame.fwd(lat, lon)
                pts.append(np.stack([x, z], 1))
    if not pts:
        return set()
    P = np.concatenate(pts); lo, hi = P.min(0), P.max(0)
    half = max(hi - lo) / 2 + 600.0; c = (lo + hi) / 2
    from shapely.geometry import LineString
    from shapely.ops import unary_union
    from shapely.prepared import prep
    zone = box(c[0] - half, c[1] - half, c[0] + half, c[1] + half)
    lm = LIGHT_M.get(city, LIGHT_M["default"])
    if lm:
        zone = zone.intersection(unary_union([LineString(p).buffer(lm, resolution=4) for p in pts]))
    zp = prep(zone)
    T_ = T.TILE_M
    return {(tx, tz) for tx in range(int(math.floor((c[0] - half) / T_)), int(math.floor((c[0] + half) / T_)) + 1)
            for tz in range(int(math.floor((c[1] - half) / T_)), int(math.floor((c[1] + half) / T_)) + 1)
            if zp.intersects(box(tx * T_, tz * T_, (tx + 1) * T_, (tz + 1) * T_))}


def scene(city):
    t0 = time.time()
    meta_path = os.path.join(ROOT, "data/scenes", city + ".json")
    old = json.load(open(meta_path))
    frame = T.Frame(*old["origin"])
    nets = city_lines(city)
    extra = landmark_areas(city, frame)
    hf = home_frame(nets, frame)
    if hf is not None:
        extra.append(hf)
    light = light_tiles(city, nets, frame)
    cache = os.path.join(T.SCRATCH, "ign_cache"); ortho = os.path.join(T.SCRATCH, "ortho")
    with tempfile.TemporaryDirectory(dir=T.SCRATCH) as td:
        nd = os.path.join(td, "nets"); od = os.path.join(td, "out")
        os.makedirs(nd); os.makedirs(od)
        # le premier réseau (ordre alphabétique) fixe l'origine : celle de la scène existante
        for i, (p, d) in enumerate(nets):
            d = dict(d, source_id=city)
            if i == 0 and list(d["origin"]) != list(old["origin"]):
                raise SystemExit(f"{city}: origine {d['origin']} différente de la scène {old['origin']}")
            json.dump(d, open(os.path.join(nd, "%03d.json" % i), "w"))
        ign_scene.main(city, nd, od, cache, ortho, periphery_m=PERIPH_M.get(city, PERIPH_M["default"]),
                       extra_areas=extra, track_json=False, light_tiles=light)
        new = json.load(open(os.path.join(od, city + ".json")))
        # mesures de plateforme et d'enrobé du corridor historique conservées (le *_track.json n'est pas régénéré)
        for k, v in old.get("stats", {}).items():
            if k.startswith("plateforme_") or k == "luminance_enrobe":
                new["stats"][k] = v
        new["landmarks"] = len(extra) - (1 if hf is not None else 0)
        new["light_tiles_count"] = len(new.get("light_tiles", []))
        shutil.copyfile(os.path.join(od, city + ".bin"), os.path.join(ROOT, "data/scenes", city + ".bin.part"))
        os.replace(os.path.join(ROOT, "data/scenes", city + ".bin.part"), os.path.join(ROOT, "data/scenes", city + ".bin"))
        json.dump(new, open(meta_path, "w"), ensure_ascii=False, indent=1)
    print(f"{city}: scène {new['tiles']} tuiles (avant {old['tiles']}), "
          f"{os.path.getsize(os.path.join(ROOT, 'data/scenes', city + '.bin')) / 1e6:.1f} Mo, {time.time() - t0:.0f} s", flush=True)


def ground(city):
    import terrain_mesh
    terrain_mesh.build(city)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    cities = args or sorted(p[:-5] for p in os.listdir(os.path.join(ROOT, "data/free")) if p.endswith(".json"))
    for c in cities:
        if "--ground-only" not in sys.argv:
            scene(c)
        if "--scene-only" not in sys.argv:
            ground(c)
