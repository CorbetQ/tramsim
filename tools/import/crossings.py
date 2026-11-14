#!/usr/bin/env python3
"""Carrefours réels route x voie de tram : data/crossings.json {identifiant de réseau : [carrefours]}, destiné à la
clé meta « crossings » des réseaux lue par src/simulation/signal_model.gd (feux R17 aux vrais carrefours). Les fichiers
de réseau ne sont pas modifiés ici (NetworkLoader peut fusionner data/crossings.json, ou l'intégrateur les copier).

Source : tronçons de route BD TOPO® (cache WFS de ign_scene.py, TERRAIN_CACHE/ign_cache) au sol (position 0), hors
chemins, sentiers et escaliers, non fictifs. Un carrefour = intersection d'un axe de voie au sol (hors pont, tunnel,
tranchée) et d'une route, angle >= 30° (une route qui longe la plateforme n'en est pas un), dédoublonnée à 15 m le
long de l'arête. Format : [{"edge", "offset" (m, abscisse de l'arête comme « length »), "road" (nom ou nature)}].
Usage : TERRAIN_CACHE=<cache> crossings.py [VILLE...]   (sans ville : toutes ; met à jour data/crossings.json)
"""
import glob, json, math, os, sys

import numpy as np
import shapely
from shapely.geometry import LineString, shape

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import terrain as T                     # noqa: E402

ROOT = T.ROOT
SKIP = {"Chemin", "Sentier", "Escalier", "Piste cyclable", "Bac ou liaison maritime", "Route empierrée"}
MIN_ANGLE = math.radians(30)
DEDUP_M = 15.0


def roads_for(frame, bounds):
    x0, z0, x1, z1 = bounds
    la, lo = frame.inv(x0 - 100, z1 + 100); lb, lob = frame.inv(x1 + 100, z0 - 100)
    out = []
    for ft in T.cached_features("troncon_de_route", os.path.join(T.SCRATCH, "ign_cache"),
                                (min(la, lb), min(lo, lob), max(la, lb), max(lo, lob))):
        pr = ft["properties"]
        if not ft.get("geometry") or T.pos_sol(pr) != 0 or pr.get("fictif") or (pr.get("nature") or "") in SKIP:
            continue
        if str(pr.get("importance") or "5") not in ("1", "2", "3", "4") and pr.get("nature") != "Rond-point":
            continue          # dessertes locales, voies de service : pas de feu
        for g in T.lines3d(ft["geometry"], frame):
            if len(g) >= 2:
                out.append((LineString(np.asarray(g)[:, :2]), pr.get("nom_collaboratif_gauche") or pr.get("nature") or "route"))
    return out


def in_spans(s, spans):
    return any(float(a) - 5 <= s <= float(b) + 5 for a, b, *_ in spans)


def process(path):
    d = json.load(open(path))
    if not d.get("origin") or not d.get("edges"):
        return []
    frame = T.Frame(*d["origin"])
    lines = []
    for e in d["edges"]:
        if len(e.get("pts", [])) >= 2:
            lines.append((e, LineString(e["pts"])))
    if not lines:
        return []
    allb = shapely.union_all([l for _, l in lines]).bounds
    roads = roads_for(frame, allb)
    if not roads:
        return []
    tree = shapely.STRtree([r for r, _ in roads])
    out = []
    for e, l in lines:
        geo = l.length
        scale = float(e.get("length", geo)) / geo if geo > 0 else 1.0
        found = []
        for i in tree.query(l):
            r, name = roads[int(i)]
            inter = l.intersection(r)
            for p in getattr(inter, "geoms", [inter]):
                if p.geom_type != "Point":
                    continue
                s = l.project(p)
                # angle entre la voie et la route au point
                a0, a1 = l.interpolate(max(0, s - 2)), l.interpolate(min(geo, s + 2))
                sr = r.project(p); b0, b1 = r.interpolate(max(0, sr - 2)), r.interpolate(min(r.length, sr + 2))
                u = np.array([a1.x - a0.x, a1.y - a0.y]); v = np.array([b1.x - b0.x, b1.y - b0.y])
                if np.linalg.norm(u) < 1e-6 or np.linalg.norm(v) < 1e-6:
                    continue
                ang = math.acos(min(1.0, abs(float(u @ v)) / (np.linalg.norm(u) * np.linalg.norm(v))))
                off = s * scale
                if ang < MIN_ANGLE or in_spans(off, e.get("bridge", []) + e.get("tunnel", []) + e.get("trench", [])):
                    continue
                if any(abs(off - f[0]) < DEDUP_M for f in found):
                    continue
                found.append((off, name))
        out += [{"edge": e["id"], "offset": round(o, 1), "road": n} for o, n in sorted(found)]
    return out


if __name__ == "__main__":
    cities = sys.argv[1:]
    dst = os.path.join(ROOT, "data/crossings.json")
    res = json.load(open(dst)) if os.path.exists(dst) else {"schema": 1, "source": "BD TOPO IGN (troncon_de_route au sol) x axes des voies, tools/import/crossings.py", "networks": {}}
    files = sorted(glob.glob(os.path.join(ROOT, "data/networks/*.json")) + glob.glob(os.path.join(ROOT, "data/free/*.json")))
    for f in files:
        d = json.load(open(f))
        if cities and d.get("source_id") not in cities:
            continue
        out = process(f)
        res["networks"][d.get("id") or os.path.basename(f)[:-5]] = out
        print(os.path.relpath(f, ROOT), len(out), "carrefours", flush=True)
    json.dump(res, open(dst + ".part", "w"), ensure_ascii=False, separators=(",", ":"))
    os.replace(dst + ".part", dst)
