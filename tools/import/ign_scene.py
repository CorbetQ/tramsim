#!/usr/bin/env python3
"""Décor réel d'une ville à partir de la BD TOPO® de l'IGN (WFS data.geopf.fr, Licence Ouverte 2.0).

Corridor = voies de toutes les lignes de la ville, tampon de CORRIDOR_M mètres.
Couches : bâtiments (emprise + hauteur), tronçons de route (largeur), surfaces en eau, végétation,
terrains de sport, cimetières, voies ferrées. Tout est projeté dans le repère local de la ville,
découpé en tuiles de TILE_M mètres et écrit dans un binaire compact lu par src/rendering/city_scene.gd.

Usage : ign_scene.py CITY_ID NETWORKS_DIR OUT_DIR CACHE_DIR
Format (little endian) : "TSC1", uint32 nb_tuiles, table [int32 tx, int32 tz, uint32 offset, uint32 taille],
puis par tuile : bâtiments, polygones, lignes (voir write_tile).
"""
import json, math, os, struct, subprocess, sys, time, urllib.parse
from collections import defaultdict

import mapbox_earcut as earcut
import numpy as np
from shapely.geometry import LineString, MultiPolygon, Polygon, box, shape
from shapely.ops import unary_union

CORRIDOR_M = 220.0
TILE_M = 400.0
R = 6371008.8
WFS = "https://data.geopf.fr/wfs/ows"
LAYERS = {
    "batiment": "BDTOPO_V3:batiment",
    "route": "BDTOPO_V3:troncon_de_route",
    "eau": "BDTOPO_V3:surface_hydrographique",
    "vegetation": "BDTOPO_V3:zone_de_vegetation",
    "sport": "BDTOPO_V3:terrain_de_sport",
    "cimetiere": "BDTOPO_V3:cimetiere",
    "fer": "BDTOPO_V3:troncon_de_voie_ferree",
    "ponctuel": "BDTOPO_V3:construction_ponctuelle",
    "zone": "BDTOPO_V3:zone_d_activite_ou_d_interet",
    "transport": "BDTOPO_V3:equipement_de_transport",
}
# classes de polygones au sol
P_WATER, P_FOREST, P_GRASS, P_SPORT, P_CEMETERY = 1, 2, 3, 4, 5
# classes de lignes
L_MAJOR, L_ROAD, L_SMALL, L_PATH, L_RAIL = 0, 1, 2, 3, 10


class Frame:
    def __init__(self, lat0, lon0):
        self.lat0, self.lon0, self.k = lat0, lon0, math.cos(math.radians(lat0))

    def fwd(self, lat, lon):
        return (math.radians(lon - self.lon0) * R * self.k, -math.radians(lat - self.lat0) * R)

    def inv(self, x, z):
        return (self.lat0 - math.degrees(z / R), self.lon0 + math.degrees(x / (R * self.k)))


def fetch(layer, bbox_ll, cache):
    """Toutes les entités d'une couche dans une emprise (lat_min, lon_min, lat_max, lon_max), avec pagination et cache."""
    key = f"{layer.split(':')[1]}_{bbox_ll[0]:.5f}_{bbox_ll[1]:.5f}_{bbox_ll[2]:.5f}_{bbox_ll[3]:.5f}.json"
    path = os.path.join(cache, key)
    if os.path.exists(path):
        return json.load(open(path))
    feats, start = [], 0
    while True:
        q = {"SERVICE": "WFS", "VERSION": "2.0.0", "REQUEST": "GetFeature", "TYPENAMES": layer,
             "BBOX": "%f,%f,%f,%f,urn:ogc:def:crs:EPSG::4326" % bbox_ll, "COUNT": "5000", "STARTINDEX": str(start),
             "OUTPUTFORMAT": "application/json"}
        url = WFS + "?" + urllib.parse.urlencode(q)
        page, err = None, ""
        for attempt in range(6):
            r = subprocess.run(["curl", "-sS", "--fail", "-m", "180", url], capture_output=True)
            if r.returncode == 0:
                try:
                    page = json.loads(r.stdout).get("features", [])
                    break
                except json.JSONDecodeError:
                    err = "réponse non JSON: " + r.stdout[:200].decode(errors="replace")
            else:
                err = r.stderr.decode()[:200]
            time.sleep(2 ** attempt)
        if page is None:
            raise RuntimeError(f"WFS {layer}: {err}")
        feats += page
        if len(page) < 5000:
            break
        start += 5000
    json.dump(feats, open(path, "w"))
    return feats


def project_geom(g, frame):
    def tr(coords):
        return [frame.fwd(c[1], c[0]) for c in coords]
    if g.geom_type == "Polygon":
        return Polygon(tr(g.exterior.coords), [tr(i.coords) for i in g.interiors])
    if g.geom_type == "MultiPolygon":
        return MultiPolygon([project_geom(p, frame) for p in g.geoms])
    if g.geom_type == "LineString":
        return LineString(tr(g.coords))
    if g.geom_type == "Point":
        from shapely.geometry import Point
        return Point(*frame.fwd(g.y, g.x))
    if g.geom_type == "MultiPoint" and len(g.geoms):
        from shapely.geometry import Point
        return Point(*frame.fwd(g.geoms[0].y, g.geoms[0].x))
    if g.geom_type == "MultiLineString":
        return [LineString(tr(l.coords)) for l in g.geoms]
    return None


def polys_of(g):
    if g is None or g.is_empty:
        return []
    if g.geom_type == "Polygon":
        return [g]
    if hasattr(g, "geoms"):
        out = []
        for p in g.geoms:
            out += polys_of(p)
        return out
    return []


def lines_of(g):
    if g is None or g.is_empty:
        return []
    if g.geom_type == "LineString":
        return [g]
    if hasattr(g, "geoms"):
        out = []
        for p in g.geoms:
            out += lines_of(p)
        return out
    return []


# types remarquables (zone d'intérêt nommée contenant le bâtiment)
K_NONE, K_CHURCH, K_CATHEDRAL, K_CASTLE, K_CIVIC, K_STATION, K_SCHOOL = 0, 1, 2, 3, 4, 5, 6
CIVIC = ("Mairie", "Préfecture", "Hôtel de département", "Hôtel de région", "Musée", "Monument", "Salle de spectacle ou conférence",
         "Palais de justice", "Administration centrale de l'Etat", "Siège d'EPCI", "Bibliothèque", "Opéra")
SCHOOL = ("Lycée", "Collège", "Enseignement supérieur", "Enseignement primaire", "Autre établissement d'enseignement")
PRIORITY = {K_CATHEDRAL: 6, K_CASTLE: 5, K_STATION: 4, K_CHURCH: 3, K_CIVIC: 2, K_SCHOOL: 1}
P_KIND = {"Clocher": 1, "Minaret": 2, "Tour": 2, "Phare": 3, "Cheminée": 4, "Calvaire": 5, "Croix": 5}


def zone_kind(p):
    nat = p.get("nature") or ""
    name = (p.get("toponyme") or "").lower()
    noise = ("château d'eau", "piscine", "parc", "complexe", "stade", "colline", "rue ", "résidence", "école", "lycée",
             "collège", "gymnase", "salle", "centre", "quartier", "cité", "place")
    if (name.startswith(("château", "citadelle", "forteresse", "fort ")) or "château de" in name or "château des" in name) \
            and not any(k in name for k in noise):
        return K_CASTLE
    if nat.startswith("Culte"):
        return K_CATHEDRAL if any(k in name for k in ("cathédrale", "basilique", "abbatiale", "collégiale")) else K_CHURCH
    if "Gare" in nat:
        return K_STATION
    if nat in CIVIC:
        return K_CIVIC
    if nat in SCHOOL:
        return K_SCHOOL
    return K_NONE


def building_class(p):
    nat = (p.get("nature") or "").lower()
    use = (p.get("usage_1") or "").lower()
    if any(k in nat for k in ("église", "chapelle", "religieux")):
        return 3
    if any(k in nat for k in ("château", "monument", "tour", "fort", "arc", "remarquable")):
        return 4
    if p.get("construction_legere"):
        return 5
    if "industriel" in nat or "agricole" in nat or "industriel" in use or "agricole" in use:
        return 2
    if "résidentiel" in use:
        return 0
    if any(k in use for k in ("commercial", "services", "sportif", "religieux")):
        return 1
    return 0


def building_height(p, cls):
    h = p.get("hauteur")
    if h:
        return max(2.5, min(150.0, float(h)))
    if p.get("nombre_d_etages"):
        return 3.0 * float(p["nombre_d_etages"]) + 1.0
    return {0: 9.0, 1: 10.0, 2: 8.0, 3: 18.0, 4: 15.0, 5: 3.0}[cls]


def road_class_width(p):
    nat = (p.get("nature") or "")
    w = p.get("largeur_de_chaussee")
    if nat in ("Escalier",):
        return None, None
    if nat in ("Type autoroutier", "Route à 2 chaussées") or p.get("importance") in ("1", "2"):
        c, dw = L_MAJOR, 9.0
    elif nat in ("Route à 1 chaussée", "Rond-point", "Bretelle"):
        c, dw = L_ROAD, 6.0
    elif nat in ("Route empierrée", "Chemin"):
        c, dw = L_SMALL, 3.5
    else:  # sentier, piste cyclable, bac...
        c, dw = L_PATH, 2.0
    return c, float(w) if w else dw


def veg_class(p):
    nat = (p.get("nature") or "").lower()
    if any(k in nat for k in ("forêt", "bois", "zone arborée", "peupleraie")):
        return P_FOREST
    return P_GRASS


def tri(poly):
    """Triangulation (earcut) d'un polygone avec trous. Retourne (sommets Nx2, indices)."""
    rings = [np.array(poly.exterior.coords[:-1], dtype=np.float64)]
    rings += [np.array(i.coords[:-1], dtype=np.float64) for i in poly.interiors]
    verts = np.concatenate(rings)
    ends = np.cumsum([len(r) for r in rings]).astype(np.uint32)
    idx = earcut.triangulate_float64(verts, ends)
    return verts, idx


def q(v, ox, oz):
    return int(round((v[0] - ox) * 10)), int(round((v[1] - oz) * 10))


def write_tile(tile, ox, oz):
    out = bytearray()
    blds = tile["b"]
    out += struct.pack("<H", len(blds))
    for poly, cls, h, kind in blds:
        ring = list(poly.exterior.coords)[:-1]
        verts, idx = tri(Polygon(ring))
        out += struct.pack("<BBHB", len(ring), cls, int(round(h * 10)), kind)
        for v in ring:
            out += struct.pack("<hh", *q(v, ox, oz))
        out += struct.pack("<B", len(idx) // 3)
        out += struct.pack("<%dB" % len(idx), *[int(i) for i in idx])
    polys = tile["p"]
    out += struct.pack("<H", len(polys))
    for cls, verts, idx in polys:
        out += struct.pack("<BHH", cls, len(verts), len(idx) // 3)
        for v in verts:
            out += struct.pack("<hh", *q(v, ox, oz))
        out += struct.pack("<%dH" % len(idx), *[int(i) for i in idx])
    lines = tile["l"]
    out += struct.pack("<H", len(lines))
    for cls, w, coords in lines:
        out += struct.pack("<BBH", cls, max(1, min(255, int(round(w * 5)))), len(coords))
        for v in coords:
            out += struct.pack("<hh", *q(v, ox, oz))
    pts = tile.get("pt", [])
    out += struct.pack("<H", len(pts))
    for cls, h, v in pts:
        out += struct.pack("<BH", cls, int(round(min(h, 600.0) * 10))) + struct.pack("<hh", *q(v, ox, oz))
    labels = tile.get("lb", [])
    out += struct.pack("<H", len(labels))
    for kind, v, name in labels:
        b = name.encode("utf-8")[:120]
        out += struct.pack("<B", kind) + struct.pack("<hh", *q(v, ox, oz)) + struct.pack("<B", len(b)) + b
    return bytes(out)


def main(city, nets_dir, out_dir, cache):
    os.makedirs(cache, exist_ok=True)
    nets = []
    for f in sorted(os.listdir(nets_dir)):
        if f.endswith(".json"):
            d = json.load(open(os.path.join(nets_dir, f)))
            if d.get("source_id") == city:
                nets.append(d)
    if not nets:
        raise SystemExit(f"aucune ligne pour {city}")
    frame = Frame(*nets[0]["origin"])
    lines = []
    for d in nets:
        nf = Frame(*d["origin"])
        for e in d["edges"]:
            pts = [frame.fwd(*nf.inv(x, z)) for x, z in e.get("pts", [])]
            if len(pts) >= 2:
                lines.append(LineString(pts))
    corridor = unary_union([l.buffer(CORRIDOR_M, resolution=4) for l in lines]).simplify(5.0)
    minx, minz, maxx, maxz = corridor.bounds
    # requêtes par cellules de 1,5 km qui touchent le corridor
    CELL = 1500.0
    cells = []
    x = math.floor(minx / CELL) * CELL
    while x < maxx:
        z = math.floor(minz / CELL) * CELL
        while z < maxz:
            if corridor.intersects(box(x, z, x + CELL, z + CELL)):
                cells.append((x, z))
            z += CELL
        x += CELL
    feats = defaultdict(dict)
    for i, (x, z) in enumerate(cells):
        lat_a, lon_a = frame.inv(x, z + CELL)
        lat_b, lon_b = frame.inv(x + CELL, z)
        bb = (min(lat_a, lat_b), min(lon_a, lon_b), max(lat_a, lat_b), max(lon_a, lon_b))
        for name, layer in LAYERS.items():
            for ft in fetch(layer, bb, cache):
                feats[name][ft["id"]] = ft
        print(f"  cellule {i + 1}/{len(cells)}", file=sys.stderr, flush=True)
    tiles = defaultdict(lambda: {"b": [], "p": [], "l": [], "pt": [], "lb": []})

    def tile_of(px, pz):
        return (int(math.floor(px / TILE_M)), int(math.floor(pz / TILE_M)))

    def tile_box(t):
        return box(t[0] * TILE_M, t[1] * TILE_M, (t[0] + 1) * TILE_M, (t[1] + 1) * TILE_M)

    stats = defaultdict(int)
    from shapely.strtree import STRtree
    zones, zgeoms = [], []
    for ft in list(feats["zone"].values()) + list(feats["transport"].values()):
        if not ft.get("geometry"):
            continue
        k = zone_kind(ft["properties"])
        if k == K_NONE:
            continue
        g = project_geom(shape(ft["geometry"]), frame)
        if g is None:
            continue
        if isinstance(g, list):
            g = unary_union(g)
        g = g.buffer(12.0) if g.geom_type in ("Point", "LineString", "MultiLineString") else g.buffer(2.0)
        zones.append((k, ft["properties"].get("toponyme") or "", g))
        zgeoms.append(g)
    ztree = STRtree(zgeoms) if zgeoms else None
    zone_best = {}   # index de zone -> (aire, centroïde) du plus grand bâtiment, pour l'étiquette
    # bâtiments : centroïde dans le corridor, emprise simplifiée (<= 32 sommets)
    for ft in feats["batiment"].values():
        if not ft.get("geometry"):
            continue
        g = project_geom(shape(ft["geometry"]), frame)
        for p in polys_of(g):
            c = p.centroid
            if p.area < 8 or not corridor.contains(c):
                continue
            p = Polygon(p.exterior.coords).simplify(0.4)
            if p.is_empty or p.geom_type != "Polygon" or len(p.exterior.coords) < 4:
                continue
            if len(p.exterior.coords) > 33:
                p = p.simplify(1.5)
                if len(p.exterior.coords) > 33:
                    p = p.minimum_rotated_rectangle
            p = Polygon(p.exterior.coords)
            if not p.exterior.is_ccw:
                p = Polygon(list(p.exterior.coords)[::-1])
            cls = building_class(ft["properties"])
            kind, best = K_NONE, None
            if ztree is not None:
                for zi in ztree.query(c):
                    zi = int(zi)
                    if zgeoms[zi].contains(c) and (best is None or PRIORITY[zones[zi][0]] > PRIORITY[zones[best][0]]):
                        best = zi
                if best is not None:
                    kind = zones[best][0]
                    if p.area > zone_best.get(best, (0, None))[0]:
                        zone_best[best] = (p.area, (c.x, c.y), tile_of(c.x, c.y), len(tiles[tile_of(c.x, c.y)]["b"]))
            if cls == 3 and kind == K_NONE:
                kind = K_CHURCH
            if kind == K_CHURCH and p.area > 1500:
                kind = K_CATHEDRAL
            tiles[tile_of(c.x, c.y)]["b"].append((p, cls, building_height(ft["properties"], cls), kind))
            stats["remarquables"] += kind != K_NONE
            stats["bâtiments"] += 1
    # surfaces : découpées par le corridor puis par tuile
    def add_area(g, cls):
        g = g.intersection(corridor)
        for p in polys_of(g):
            x0, z0, x1, z1 = p.bounds
            for tx in range(int(math.floor(x0 / TILE_M)), int(math.floor(x1 / TILE_M)) + 1):
                for tz in range(int(math.floor(z0 / TILE_M)), int(math.floor(z1 / TILE_M)) + 1):
                    piece = p.intersection(tile_box((tx, tz)))
                    for pp in polys_of(piece):
                        pp = pp.simplify(1.0)
                        for ppp in polys_of(pp):
                            if ppp.area < 20:
                                continue
                            verts, idx = tri(ppp)
                            if len(verts) > 60000 or len(idx) == 0:
                                continue
                            tiles[(tx, tz)]["p"].append((cls, verts, idx))
                            stats[f"surfaces_{cls}"] += 1
    for ft in feats["eau"].values():
        if ft.get("geometry"):
            add_area(project_geom(shape(ft["geometry"]), frame), P_WATER)
    for ft in feats["vegetation"].values():
        if ft.get("geometry"):
            add_area(project_geom(shape(ft["geometry"]), frame), veg_class(ft["properties"]))
    for ft in feats["sport"].values():
        if ft.get("geometry"):
            add_area(project_geom(shape(ft["geometry"]), frame), P_SPORT)
    for ft in feats["cimetiere"].values():
        if ft.get("geometry"):
            add_area(project_geom(shape(ft["geometry"]), frame), P_CEMETERY)
    # lignes : routes au sol (pas les tunnels), voies ferrées
    def add_line(g, cls, w):
        for l in (g if isinstance(g, list) else lines_of(g)):
            for piece in lines_of(l.intersection(corridor)):
                x0, z0, x1, z1 = piece.bounds
                for tx in range(int(math.floor(x0 / TILE_M)), int(math.floor(x1 / TILE_M)) + 1):
                    for tz in range(int(math.floor(z0 / TILE_M)), int(math.floor(z1 / TILE_M)) + 1):
                        for seg in lines_of(piece.intersection(tile_box((tx, tz)))):
                            seg = seg.simplify(0.5)
                            if seg.length < 2:
                                continue
                            tiles[(tx, tz)]["l"].append((cls, w, list(seg.coords)))
                            stats[f"lignes_{cls}"] += 1
    for ft in feats["route"].values():
        p = ft["properties"]
        if not ft.get("geometry") or str(p.get("position_par_rapport_au_sol", "0")).startswith("-"):
            continue
        cls, w = road_class_width(p)
        if cls is None:
            continue
        add_line(project_geom(shape(ft["geometry"]), frame), cls, w)
    for ft in feats["fer"].values():
        p = ft["properties"]
        if not ft.get("geometry") or str(p.get("position_par_rapport_au_sol", "0")).startswith("-"):
            continue
        if p.get("nature") == "Tramway":
            continue  # les voies de tram sont dessinées par le jeu à partir du tracé de la ligne
        add_line(project_geom(shape(ft["geometry"]), frame), L_RAIL, 3.0)
    for ft in feats["ponctuel"].values():
        pr = ft["properties"]
        k = P_KIND.get(pr.get("nature") or "")
        if not k or not ft.get("geometry"):
            continue
        g = project_geom(shape(ft["geometry"]), frame)
        if g is None or g.geom_type != "Point" or not corridor.contains(g):
            continue
        h = float(pr.get("hauteur") or {1: 38.0, 2: 30.0, 3: 25.0, 4: 30.0, 5: 4.0}[k])
        tiles[tile_of(g.x, g.y)]["pt"].append((k, h, (g.x, g.y)))
        stats["ponctuels"] += 1
    for zi, (area, cxy, tk, bi) in zone_best.items():
        b = tiles[tk]["b"][bi]
        tiles[tk]["b"][bi] = (b[0], b[1], b[2], b[3] | 0x80)   # volume principal du monument (tours, flèche)
        k, name, _ = zones[zi]
        if name and k != K_SCHOOL:
            tiles[tile_of(*cxy)]["lb"].append((k, cxy, name))
            stats["étiquettes"] += 1
    # écriture
    keys = sorted(tiles)
    blobs = [write_tile(tiles[t], t[0] * TILE_M, t[1] * TILE_M) for t in keys]
    head = b"TSC2" + struct.pack("<I", len(keys))
    off = len(head) + 16 * len(keys)
    table = bytearray()
    for t, b in zip(keys, blobs):
        table += struct.pack("<iiII", t[0], t[1], off, len(b))
        off += len(b)
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, city + ".bin"), "wb") as f:
        f.write(head + bytes(table) + b"".join(blobs))
    meta = {"schema": 1, "city": city, "origin": list(nets[0]["origin"]), "tile_m": TILE_M, "corridor_m": CORRIDOR_M,
            "tiles": len(keys), "source": "BD TOPO® IGN (Licence Ouverte 2.0), WFS data.geopf.fr, extrait du "
            + time.strftime("%Y-%m-%d"), "stats": dict(stats)}
    json.dump(meta, open(os.path.join(out_dir, city + ".json"), "w"), ensure_ascii=False, indent=1)
    size = os.path.getsize(os.path.join(out_dir, city + ".bin"))
    print(f"{city}: {len(keys)} tuiles, {size / 1e6:.1f} Mo, {dict(stats)}")


if __name__ == "__main__":
    main(*sys.argv[1:5])
