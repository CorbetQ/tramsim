#!/usr/bin/env python3
"""Décor réel d'une ville à partir de la BD TOPO® de l'IGN (WFS data.geopf.fr, Licence Ouverte 2.0).

Corridor = voies de toutes les lignes de la ville, tampon de CORRIDOR_M mètres.
Couches : bâtiments (emprise + hauteur), tronçons de route (largeur), surfaces en eau, végétation,
terrains de sport, cimetières, voies ferrées. Tout est projeté dans le repère local de la ville,
découpé en tuiles de TILE_M mètres et écrit dans un binaire compact lu par src/rendering/city_scene.gd.

Usage : ign_scene.py CITY_ID NETWORKS_DIR OUT_DIR CACHE_DIR [ORTHO_CACHE_DIR]
Avec ORTHO_CACHE_DIR : analyse des orthophotos IGN (toits, houppiers, sol vert) et OUT_DIR/<ville>_track.json
(nature des plateformes). Dépend de numpy, shapely, mapbox_earcut, Pillow, scipy.
Format (little endian) : "TSC4", uint32 nb_tuiles, table [int32 tx, int32 tz, uint32 offset, uint32 taille
compressée, uint32 taille], puis par tuile (Brotli) : bâtiments, polygones, lignes, ponctuels, étiquettes (TSC2),
toits, arbres, sol vert (TSC3) ; voir write_tile. Le jeu lit aussi TSC1 à TSC3 (non compressés, table de 16 octets).
ign_scene.py --tsc4 FICHIER... : convertit un TSC3 existant en TSC4 sans réimport.
"""
import gzip, json, math, os, struct, subprocess, sys, time, urllib.parse
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
    if os.path.exists(path + ".gz"):          # cache compressé (périphérie : volumes 3 à 5 fois plus grands)
        return json.loads(gzip.decompress(open(path + ".gz", "rb").read()))
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
    tmp = path + ".gz.part"
    open(tmp, "wb").write(gzip.compress(json.dumps(feats, separators=(",", ":")).encode(), 6))
    os.replace(tmp, path + ".gz")
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
    # TSC3 : couleurs de toits (RGB444 + bit 15, 0 = style), houppiers détectés, cellules de sol vert
    roofs = tile.get("rf") or [0] * len(blds)
    out += struct.pack("<H", len(roofs)) + struct.pack("<%dH" % len(roofs), *roofs)
    trees = tile.get("tr", [])
    out += struct.pack("<H", len(trees))
    for x, z, r, kind in trees:
        out += struct.pack("<hh", *q((x, z), ox, oz)) + struct.pack("<BB", max(1, min(255, int(round(r * 10)))), kind)
    runs = tile.get("gr", [])
    out += struct.pack("<H", len(runs))
    for row, s0, n in runs:
        out += struct.pack("<BBB", row, s0, n)
    return bytes(out)


# ----------------------------------------------------------------------------------------- orthophotos IGN
# BD ORTHO® IGN (Licence Ouverte 2.0), WMTS data.geopf.fr, Web Mercator. z17 (~0,8 m/px réel) pour le corridor
# (couleur des toits, houppiers, sol vert/minéral), z18 (~0,4 m/px) le long de l'axe des voies (nature de plateforme).
WMTS = ("https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=ORTHOIMAGERY.ORTHOPHOTOS"
        "&STYLE=normal&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/jpeg")
Z_AREA, Z_TRACK = 17, 18
GREEN_CELL = 4.0          # m, cellules de sol vert (100 x 100 par tuile)
TRACK_CELL = 8.0          # m, cellules de nature de plateforme
TRACK_CLEAR = 3.6         # m, demi-largeur de plateforme interdite aux bâtiments (2 voies à ±1,75 m)
TREE_CLEAR = 4.5          # m, distance minimale tronc / axe des voies
BED_GRASS, BED_ROAD, BED_PAVED = 1, 2, 3


class Ortho:
    def __init__(self, cache):
        self.cache = cache
        self.mem = {}

    def path(self, z, x, y):
        return os.path.join(self.cache, str(z), str(x), f"{y}.jpg")

    def prefetch(self, z, keys, workers=12):
        from concurrent.futures import ThreadPoolExecutor
        todo = [k for k in keys if not os.path.exists(self.path(z, *k)) and not os.path.exists(self.path(z, *k) + ".none")]

        def get(k):
            p = self.path(z, *k)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            for attempt in range(5):
                r = subprocess.run(["curl", "-sS", "-m", "60", "-o", p + ".part", "-w", "%{http_code}",
                                    WMTS.format(z=z, x=k[0], y=k[1])], capture_output=True)
                code = r.stdout.decode().strip()
                if code == "200":
                    os.replace(p + ".part", p); return
                if code in ("404", "400"):
                    open(p + ".none", "w").close()
                    if os.path.exists(p + ".part"): os.remove(p + ".part")
                    return
                time.sleep(1.5 * 2 ** attempt)
            print(f"  ortho {z}/{k}: échec", file=sys.stderr)
        if todo:
            print(f"  orthophotos z{z} : {len(todo)} dalles à télécharger", file=sys.stderr, flush=True)
            with ThreadPoolExecutor(workers) as ex:
                list(ex.map(get, todo))

    def tile(self, z, x, y):
        k = (z, x, y)
        if k not in self.mem:
            if len(self.mem) > 1500:
                self.mem.clear()
            p = self.path(z, x, y)
            arr = None
            if os.path.exists(p):
                from PIL import Image
                try:
                    arr = np.asarray(Image.open(p).convert("RGB"), dtype=np.uint8)
                except Exception:
                    arr = None
            self.mem[k] = arr
        return self.mem[k]

    @staticmethod
    def pixel(z, lat, lon):
        n = 256.0 * 2 ** z
        px = (np.asarray(lon) + 180.0) / 360.0 * n
        py = (1.0 - np.arcsinh(np.tan(np.radians(lat))) / math.pi) / 2.0 * n
        return px, py

    def keys_for(self, z, lat, lon):
        px, py = self.pixel(z, lat, lon)
        return set(zip((px // 256).astype(int).ravel().tolist(), (py // 256).astype(int).ravel().tolist()))

    def sample(self, z, lat, lon):
        """RGB (float 0..1, forme (..., 3)) et masque de validité aux points (lat, lon)."""
        px, py = self.pixel(z, lat, lon)
        shp = np.shape(px)
        px, py = px.ravel(), py.ravel()
        tx, ty = (px // 256).astype(np.int64), (py // 256).astype(np.int64)
        ix, iy = np.clip((px - tx * 256).astype(int), 0, 255), np.clip((py - ty * 256).astype(int), 0, 255)
        out = np.zeros((px.size, 3), np.float32)
        ok = np.zeros(px.size, bool)
        key = tx * 10_000_000 + ty
        for k in np.unique(key):
            sel = key == k
            arr = self.tile(z, int(k // 10_000_000), int(k % 10_000_000))
            if arr is None:
                continue
            out[sel] = arr[iy[sel], ix[sel]] / 255.0
            ok[sel] = True
        return out.reshape(shp + (3,)), ok.reshape(shp)


def frame_inv_np(frame, x, z):
    return frame.lat0 - np.degrees(z / R), frame.lon0 + np.degrees(x / (R * frame.k))


def veg_index(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    s = r + g + b + 1e-3
    return (2 * g - r - b) / s, s / 3.0   # indice de verdure normalisé (ExG), luminance


def roof_rgb444(mean):
    """Couleur moyenne d'un toit -> couleur de style (éclaircie, saturée, quantifiée en 4 bits/canal)."""
    import colorsys
    h, s, v = colorsys.rgb_to_hsv(*[float(c) for c in mean])
    v = min(1.0, 0.05 + v * 1.12)   # le rendu toon éclaircit déjà fortement les faces au soleil
    s = min(0.6, s * 1.3)
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    q = [max(0, min(15, int(round(c * 15)))) for c in (r, g, b)]
    return 0x8000 | (q[0] << 8) | (q[1] << 4) | q[2]   # bit 15 : couleur présente


def ortho_tile(ortho, frame, tkey, tile, nb_blds, track_lines, z=None):
    """Analyse d'une tuile : couleurs de toits, houppiers, cellules vertes."""
    from PIL import Image, ImageDraw
    from scipy import ndimage
    M = 40
    N = int(TILE_M) + 2 * M
    gx0, gz0 = tkey[0] * TILE_M - M, tkey[1] * TILE_M - M
    xs = gx0 + 0.5 + np.arange(N)
    zs = gz0 + 0.5 + np.arange(N)
    X, Z = np.meshgrid(xs, zs)
    lat, lon = frame_inv_np(frame, X, Z)
    rgb, ok = ortho.sample(z or Z_AREA, lat, lon)
    if not ok.any():
        return [0] * len(tile["b"]), [], []
    lab = Image.new("I", (N, N), 0)
    bm = Image.new("L", (N, N), 0)
    dl, db = ImageDraw.Draw(lab), ImageDraw.Draw(bm)
    for i, (poly, *_r) in enumerate(tile["b"]):
        ring = [(x - gx0, z - gz0) for x, z in poly.exterior.coords]
        dl.polygon(ring, fill=i + 1)
    for poly in nb_blds:
        db.polygon([(x - gx0, z - gz0) for x, z in poly.exterior.coords], fill=255)
    tm = Image.new("L", (N, N), 0)
    dt = ImageDraw.Draw(tm)
    for coords in track_lines:
        dt.line([(x - gx0, z - gz0) for x, z in coords], fill=255, width=int(2 * TREE_CLEAR + 1), joint="curve")
    tmask = np.asarray(tm) > 0
    lab = np.asarray(lab, dtype=np.int32)
    bmask = (np.asarray(bm) > 0) | (lab > 0)
    # couleurs de toits : moyenne des pixels intérieurs (bord érodé d'1 px), pixels valides
    inner = lab * (ndimage.minimum_filter(lab, 3) == lab) * ok
    cnt = np.bincount(inner.ravel(), minlength=len(tile["b"]) + 1)
    roofs = [0] * len(tile["b"])
    sums = [np.bincount(inner.ravel(), weights=rgb[..., c].ravel(), minlength=len(tile["b"]) + 1) for c in range(3)]
    for i in range(len(tile["b"])):
        n = cnt[i + 1]
        if n >= 6:
            m = (sums[0][i + 1] / n, sums[1][i + 1] / n, sums[2][i + 1] / n)
            if veg_index(np.array(m))[0] < 0.08:   # toit masqué par un arbre : couleur du style
                roofs[i] = roof_rgb444(m)
    # végétation : ExG élevé ; houppiers = végétation sombre ou texturée hors bâti et hors voies
    exg, lum = veg_index(rgb)
    veg = ok & (is_green(rgb) | ((exg > 0.05) & (lum > 0.04))) & ~bmask
    veg = ndimage.binary_opening(veg, iterations=1)
    tex = ndimage.uniform_filter(lum * lum, 5) - ndimage.uniform_filter(lum, 5) ** 2
    treem = veg & ((lum < 0.30) | (tex > 0.0025))
    treem = ndimage.binary_opening(ndimage.binary_closing(treem, iterations=1), iterations=1)
    treem &= ~tmask
    dist = ndimage.distance_transform_edt(treem)
    peaks = (dist >= 1.6) & (dist == ndimage.maximum_filter(dist, size=7))
    trees = []
    zz, xx = np.nonzero(peaks)
    order = np.argsort(-dist[zz, xx])
    taken = []
    for j in order:
        x, z = int(xx[j]), int(zz[j])
        if not (M <= x < M + TILE_M and M <= z < M + TILE_M):
            continue
        r = float(dist[z, x]) + 0.8
        if any((x - a) ** 2 + (z - c) ** 2 < (0.8 * max(r, rr)) ** 2 for a, c, rr in taken[-60:]):
            continue
        taken.append((x, z, r))
        dark = float(lum[z, x])
        trees.append((xs[x], zs[z], min(r, 9.0), 1 if dark < 0.12 else 0))
    # sol vert : cellules de 4 m à majorité de végétation (hors bâti)
    c = int(GREEN_CELL)
    vg = (ok & is_green(rgb) & ~bmask)[M:M + int(TILE_M), M:M + int(TILE_M)]
    nb_ok = (ok & ~bmask)[M:M + int(TILE_M), M:M + int(TILE_M)]
    n = int(TILE_M / GREEN_CELL)
    frac = vg.reshape(n, c, n, c).sum(axis=(1, 3)) / np.maximum(1, nb_ok.reshape(n, c, n, c).sum(axis=(1, 3)))
    green = (frac > 0.5) & (nb_ok.reshape(n, c, n, c).sum(axis=(1, 3)) >= c * c // 2)
    green = ndimage.binary_opening(green) | (green & ndimage.binary_erosion(green, np.ones((1, 3))))
    runs = []
    for row in range(n):
        col = 0
        line = green[row]
        while col < n:
            if line[col]:
                s = col
                while col < n and line[col]:
                    col += 1
                runs.append((row, s, col - s))
            else:
                col += 1
    return roofs, trees, runs


def is_green(rgb):
    """Végétation, y compris gazon sec (orthophotos estivales) : vert >= rouge et nettement > bleu."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    s = r + g + b + 1e-3
    exg = (2 * g - r - b) / s
    return ((exg > 0.04) | ((g >= r * 0.97) & ((g - b) / s > 0.028))) & (s / 3.0 > 0.06) & (s / 3.0 < 0.62)


def asphalt_level(ortho, frame, tiles, lines):
    """Luminance médiane des chaussées BD TOPO (hors voies de tram) : référence « enrobé » propre à chaque ville
    (la radiométrie des orthophotos varie d'un département et d'une campagne à l'autre)."""
    from shapely.strtree import STRtree
    from shapely.geometry import Point
    tl = STRtree(lines)
    pts = []
    for t in tiles.values():
        for cls, w, coords in t["l"]:
            if cls in (L_MAJOR, L_ROAD) and w >= 5.0:
                l = LineString(coords)
                for k in range(0, int(l.length), 25):
                    p = l.interpolate(k)
                    j = tl.nearest(p)
                    if lines[int(j)].distance(p) > 20.0:
                        pts.append((p.x, p.y))
    if len(pts) < 50:
        return 0.40
    pts = np.array(pts[::max(1, len(pts) // 20000)])
    lat, lon = frame_inv_np(frame, pts[:, 0], pts[:, 1])
    rgb, ok = ortho.sample(Z_AREA, lat, lon)
    m = ok & ~is_green(rgb)
    return float(np.median(rgb.mean(axis=-1)[m])) if m.sum() > 50 else 0.40


def track_nature(ortho, frame, lines, under, tram_ref=(), asphalt=0.40):
    """Nature de la plateforme le long de l'axe (z18) : gazon, enrobé/chaussée, pavés/béton. -> {(cx, cz): code}.
    Échantillons en travers sur ±4,5 m (plateforme 7 m + imprécision du tracé GTFS), recentrés sur la voie BD TOPO
    (`tram_ref`, nature Tramway) la plus proche à moins de 10 m ; lissage sur 5 x 5 cellules ;
    luminance minérale : 75e centile (robuste aux ombres portées des façades)."""
    green_n = defaultdict(int)
    tot_n = defaultdict(int)
    lums = defaultdict(list)
    warm = defaultdict(float)   # somme de (rouge - bleu) des pixels minéraux : gazon sec (orthophotos d'été)
    pts, ctr = [], []
    from shapely.strtree import STRtree
    from shapely.geometry import Point
    ref = list(tram_ref)
    rtree = STRtree(ref) if ref else None
    for l in lines:
        n = max(2, int(l.length / 2.0) + 1)
        for k in range(n):
            s = l.length * k / (n - 1)
            p = l.interpolate(s)
            q = l.interpolate(min(l.length, s + 0.5)); q0 = l.interpolate(max(0.0, s - 0.5))
            dx, dz = q.x - q0.x, q.y - q0.y
            L = math.hypot(dx, dz) or 1.0
            pts.append((p.x, p.y, -dz / L, dx / L))
            c = (p.x, p.y)
            if rtree is not None:
                j = rtree.nearest(p)
                if j is not None and ref[int(j)].distance(p) < 10.0:
                    r = ref[int(j)]
                    pp = r.interpolate(r.project(p))
                    c = (pp.x, pp.y)
            ctr.append(c)
    if not pts:
        return {}
    P = np.array(pts)
    C = np.array(ctr)
    offs = np.linspace(-4.5, 4.5, 13)
    X = C[:, 0:1] + P[:, 2:3] * offs
    Z = C[:, 1:2] + P[:, 3:4] * offs
    lat, lon = frame_inv_np(frame, X, Z)
    ortho.prefetch(Z_TRACK, ortho.keys_for(Z_TRACK, lat, lon))
    rgb, ok = ortho.sample(Z_TRACK, lat, lon)
    lum = rgb.mean(axis=-1)
    green = is_green(rgb) & ok
    cx = np.floor(P[:, 0] / TRACK_CELL).astype(int)
    cz = np.floor(P[:, 1] / TRACK_CELL).astype(int)
    for i in range(len(P)):
        if not ok[i].any():
            continue
        c = (int(cx[i]), int(cz[i]))
        green_n[c] += int(green[i].sum())
        tot_n[c] += int(ok[i].sum())
        m = ok[i] & ~green[i]
        lums[c] += lum[i][m].tolist()
        warm[c] += float((rgb[i][m][:, 0] - rgb[i][m][:, 2]).sum())
    under_cells = set()
    if under is not None and not under.is_empty:
        from shapely.geometry import Point
        from shapely.prepared import prep
        up = prep(under)
        under_cells = {c for c in tot_n if up.contains(Point((c[0] + 0.5) * TRACK_CELL, (c[1] + 0.5) * TRACK_CELL))}
    out = {}
    for (x, z) in tot_n:
        if (x, z) in under_cells:
            continue
        g = t = 0
        ls = []
        wm = 0.0
        for dx in range(-2, 3):
            for dz in range(-2, 3):
                k = (x + dx, z + dz)
                if k in tot_n:
                    g += green_n[k]; t += tot_n[k]; ls += lums[k]; wm += warm[k]
        gfrac = g / max(t, 1)
        p75 = float(np.percentile(ls, 75)) if ls else 0.0
        dry = bool(ls) and wm / len(ls) > 0.035 and p75 < 0.60
        out[(x, z)] = BED_GRASS if gfrac > 0.38 or dry else (BED_PAVED if p75 > min(0.70, max(0.50, asphalt + 0.08)) else BED_ROAD)
    return out


def pack_tsc4(blobs):
    """TSC4 : contenu de tuile TSC3 compressé par tuile (Brotli) ; table [i32 tx, i32 tz, u32 offset,
    u32 taille compressée, u32 taille]."""
    import brotli
    keys = sorted(blobs)
    comp = [brotli.compress(blobs[t], quality=11) for t in keys]
    head = b"TSC4" + struct.pack("<I", len(keys))
    off = len(head) + 20 * len(keys)
    table = bytearray()
    for t, c in zip(keys, comp):
        table += struct.pack("<iiIII", t[0], t[1], off, len(c), len(blobs[t]))
        off += len(c)
    return head + bytes(table) + b"".join(comp)


def read_tiles(buf):
    """Contenu (format TSC3) des tuiles d'un fichier TSC1 à TSC4 : {(tx, tz): octets}, et version."""
    magic = buf[:4]
    n = struct.unpack_from("<I", buf, 4)[0]
    out = {}
    for i in range(n):
        if magic == b"TSC4":
            import brotli
            tx, tz, off, cs, size = struct.unpack_from("<iiIII", buf, 8 + i * 20)
            out[(tx, tz)] = brotli.decompress(buf[off:off + cs])
        else:
            tx, tz, off, size = struct.unpack_from("<iiII", buf, 8 + i * 16)
            out[(tx, tz)] = buf[off:off + size]
    return out, magic


def recompress(path):
    """TSC3 -> TSC4 sans réimport (contenu identique)."""
    buf = open(path, "rb").read()
    tiles, magic = read_tiles(buf)
    if magic != b"TSC3":
        return magic.decode()
    open(path, "wb").write(pack_tsc4(tiles))
    return "TSC4"


def main(city, nets_dir, out_dir, cache, ortho_dir=None, periphery_m=0.0, extra_areas=(), track_json=True, light_tiles=()):
    """periphery_m > 0 : emprise élargie aux tuiles entières à moins de periphery_m des voies (et extra_areas, polygones
    du repère de la ville : vue aérienne de l'accueil, monuments). Orthophotos z17 dans le corridor historique,
    z16 (2,4 m/px) au-delà. track_json=False : nature des plateformes non recalculée (fichier *_track.json intact).
    light_tiles : tuiles de décor lointain (vue globale de l'agglomération) : bâtiments >= 30 m² simplifiés à 1 m, sans
    chemins ni analyse d'orthophoto (le sol y vient de l'occupation du sol, tools/import/landcover.py)."""
    light_tiles = set(map(tuple, light_tiles))
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
    inner = corridor
    zone_tiles = None
    if periphery_m > 0:
        wide = unary_union([l.buffer(periphery_m, resolution=4) for l in lines] + list(extra_areas)).simplify(10.0)
        from shapely.prepared import prep as _prep
        wp = _prep(wide)
        x0, z0, x1, z1 = wide.bounds
        zone_tiles = {(tx, tz) for tx in range(int(math.floor(x0 / TILE_M)), int(math.floor(x1 / TILE_M)) + 1)
                      for tz in range(int(math.floor(z0 / TILE_M)), int(math.floor(z1 / TILE_M)) + 1)
                      if wp.intersects(box(tx * TILE_M, tz * TILE_M, (tx + 1) * TILE_M, (tz + 1) * TILE_M))}
        light_tiles -= zone_tiles          # décor détaillé prioritaire
        zone_tiles |= light_tiles
        corridor = unary_union([box(tx * TILE_M, tz * TILE_M, (tx + 1) * TILE_M, (tz + 1) * TILE_M) for tx, tz in zone_tiles])
        print(f"  {city} : périphérie {periphery_m:.0f} m, {len(zone_tiles)} tuiles", file=sys.stderr, flush=True)
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
    # plateformes de tram (hors tronçons souterrains BD TOPO) : aucun bâtiment ni objet ponctuel dessus
    under = []
    for ft in feats["fer"].values():
        p = ft["properties"]
        if ft.get("geometry") and p.get("nature") == "Tramway" and str(p.get("position_par_rapport_au_sol", "0")).startswith("-"):
            g = project_geom(shape(ft["geometry"]), frame)
            under += [x.buffer(15.0) for x in (g if isinstance(g, list) else lines_of(g))]
    under = unary_union(under) if under else None
    track_zone = unary_union([l.buffer(TRACK_CLEAR, resolution=2) for l in lines])
    if under is not None:
        track_zone = track_zone.difference(under)
    from shapely.prepared import prep
    track_zone_p = prep(track_zone)

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
            if p.area < 8 or not (corridor.contains(c) if zone_tiles is None else tile_of(c.x, c.y) in zone_tiles):
                continue
            light = tile_of(c.x, c.y) in light_tiles
            if light and p.area < 30:
                continue
            p = Polygon(p.exterior.coords).simplify(1.0 if light else 0.4)
            if p.is_empty or p.geom_type != "Polygon" or len(p.exterior.coords) < 4:
                continue
            if len(p.exterior.coords) > 33:
                p = p.simplify(1.5)
                if len(p.exterior.coords) > 33:
                    p = p.minimum_rotated_rectangle
            p = Polygon(p.exterior.coords)
            if not p.exterior.is_ccw:
                p = Polygon(list(p.exterior.coords)[::-1])
            if track_zone_p.intersects(p) and p.intersection(track_zone).area > 1.0:
                stats["bâtiments_sur_voie"] += 1
                continue
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
                            if seg.length < 2 or (cls == L_PATH and (tx, tz) in light_tiles):
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
        if g is None or g.geom_type != "Point" or track_zone_p.contains(g) or not (
                corridor.contains(g) if zone_tiles is None else tile_of(g.x, g.y) in zone_tiles):
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
    # orthophotos : toits, houppiers, sol vert ; nature de plateforme
    if not track_json:
        feats.clear()          # entités WFS brutes inutiles désormais (mémoire : Île-de-France)
        import gc; gc.collect()
    if ortho_dir:
        ortho = Ortho(ortho_dir)
        # dalles z17 qui touchent le corridor (échantillonnage à 50 m)
        x0, z0, x1, z1 = corridor.bounds
        gx, gz = np.meshgrid(np.arange(x0 - 60, x1 + 60, 50.0), np.arange(z0 - 60, z1 + 60, 50.0))
        cp = prep(corridor.buffer(60))
        from shapely.geometry import Point
        ip = prep(inner.buffer(460))      # tuiles du corridor historique : z17
        z17 = np.array([ip.contains(Point(a, b)) for a, b in zip(gx.ravel(), gz.ravel())])
        lp = prep(unary_union([tile_box(t) for t in zone_tiles - light_tiles]).buffer(60)) if light_tiles else cp
        sel = np.array([cp.contains(Point(a, b)) and lp.contains(Point(a, b)) for a, b in zip(gx.ravel(), gz.ravel())])
        if zone_tiles is None:
            z17 = sel
        lat, lon = frame_inv_np(frame, gx.ravel()[sel & z17], gz.ravel()[sel & z17])
        ortho.prefetch(Z_AREA, ortho.keys_for(Z_AREA, lat, lon))
        if (sel & ~z17).any():
            lat, lon = frame_inv_np(frame, gx.ravel()[sel & ~z17], gz.ravel()[sel & ~z17])
            ortho.prefetch(Z_AREA - 1, ortho.keys_for(Z_AREA - 1, lat, lon))
        inner_p = prep(inner)
        track_coords = [list(l.coords) for l in lines]
        from shapely.strtree import STRtree as _T
        tl_tree = _T(lines)
        for i, t in enumerate(sorted(tiles)):
            tb = tile_box(t).buffer(48)
            if t in light_tiles or not corridor.intersects(tb):
                continue
            nb_blds = [b[0] for dx in (-1, 0, 1) for dz in (-1, 0, 1) if (dx or dz) and (t[0] + dx, t[1] + dz) in tiles
                       for b in tiles[(t[0] + dx, t[1] + dz)]["b"] if b[0].intersects(tb)]
            tl = [track_coords[j] for j in tl_tree.query(tb)]
            zt = Z_AREA if (zone_tiles is None or inner_p.intersects(tile_box(t))) else Z_AREA - 1
            roofs, trees, runs = ortho_tile(ortho, frame, t, tiles[t], nb_blds, tl, zt)
            tiles[t]["rf"], tiles[t]["tr"], tiles[t]["gr"] = roofs, trees, runs
            stats["toits_ortho"] += sum(1 for r in roofs if r)
            stats["arbres_ortho"] += len(trees)
            stats["cellules_vertes"] += sum(r[2] for r in runs)
            if i % 50 == 0:
                print(f"  ortho tuile {i + 1}/{len(tiles)}", file=sys.stderr, flush=True)
    if ortho_dir and track_json:
        tram_ref = []
        for ft in feats["fer"].values():
            if ft.get("geometry") and ft["properties"].get("nature") == "Tramway":
                g = project_geom(shape(ft["geometry"]), frame)
                tram_ref += g if isinstance(g, list) else lines_of(g)
        asphalt = asphalt_level(ortho, frame, tiles, lines)
        stats["luminance_enrobe"] = round(asphalt, 3)
        nat = track_nature(ortho, frame, lines, under, tram_ref, asphalt)
        cnt = defaultdict(int)
        for v in nat.values():
            cnt[v] += 1
        stats.update({f"plateforme_{k}": v for k, v in {"gazon": cnt[BED_GRASS], "enrobe": cnt[BED_ROAD], "paves": cnt[BED_PAVED]}.items()})
        tj = {"schema": 1, "city": city, "cell_m": TRACK_CELL, "codes": {"1": "gazon", "2": "enrobé / chaussée partagée", "3": "pavés / béton"},
              "source": "BD ORTHO® IGN (Licence Ouverte 2.0), WMTS data.geopf.fr : indice de verdure le long de l'axe des voies",
              "cells": [[k[0], k[1], v] for k, v in sorted(nat.items())]}
        os.makedirs(out_dir, exist_ok=True)
        with open(os.path.join(out_dir, city + "_track.json"), "w") as f:
            json.dump(tj, f, ensure_ascii=False, separators=(",", ":"))
    # écriture (emprise élargie : toutes les tuiles, même vides hors de France ou en mer : sol teinté par
    # l'occupation du sol au lieu de l'horizon lointain)
    if zone_tiles is not None:
        for t in zone_tiles:
            tiles[t]
    keys = sorted(tiles)
    blobs = {t: write_tile(tiles[t], t[0] * TILE_M, t[1] * TILE_M) for t in keys}
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, city + ".bin"), "wb") as f:
        f.write(pack_tsc4(blobs))
    meta = {"schema": 1, "city": city, "origin": list(nets[0]["origin"]), "tile_m": TILE_M, "corridor_m": CORRIDOR_M,
            "tiles": len(keys), **({"periphery_m": periphery_m} if periphery_m > 0 else {}),
            **({"light_tiles": sorted([list(t) for t in light_tiles if t in tiles])} if light_tiles else {}), "source": "BD TOPO® IGN (Licence Ouverte 2.0), WFS data.geopf.fr, extrait du "
            + time.strftime("%Y-%m-%d"), "stats": dict(stats)}
    json.dump(meta, open(os.path.join(out_dir, city + ".json"), "w"), ensure_ascii=False, indent=1)
    size = os.path.getsize(os.path.join(out_dir, city + ".bin"))
    print(f"{city}: {len(keys)} tuiles, {size / 1e6:.1f} Mo, {dict(stats)}")


if __name__ == "__main__":
    if sys.argv[1] == "--tsc4":      # ign_scene.py --tsc4 data/scenes/<ville>.bin...
        for p in sys.argv[2:]:
            print(p, recompress(p))
    else:
        main(*sys.argv[1:6])
