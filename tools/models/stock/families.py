"""P4 : spécifications HD automatiques pour tout le parc (une par kit de caisse canonique).

La géométrie vient du plan coté adapté à la variante (audit_stock.fitted_plan), la silhouette du nez est dérivée
du plan (front.side -> avancée D(y), front.plan -> exposant de superellipse), la livrée est résolue comme
TramModel.livery_for (réseau -> surcharge de famille -> data/rolling_stock/variants/livery_overrides.json).
Les particularités de famille (feux, rétroviseurs, pupitre) sont regroupées par constructeur (MAKER)."""
import copy, hashlib, json, os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


def _json(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return json.load(f)


# famille (plan) -> groupe de conception : feux, rétroviseurs, pupitre, tissu
MAKER = {
    "citadis_302": "citadis1", "citadis_402": "citadis1", "citadis_x01": "citadis1", "citadis_reims": "citadis1",
    "citadis_tours": "citadis1", "citadis_403_strasbourg": "citadis2", "citadis_compact": "citadis2",
    "citadis_x05": "citadis2", "citadis_x05_nantes": "citadis2", "citadis_dualis": "dualis",
    "tfs": "tfs", "vevey_saint_etienne": "vevey", "eurotram": "bombardier", "flexity_marseille": "bombardier",
    "incentro": "bombardier", "avanto": "siemens", "urbos": "caf", "translohr": "translohr",
    "breda_vlc": "breda", "tango_rhonexpress": "stadler",
}
# pupitre (RGB sRGB), décalage de hauteur, enveloppement ; rétroviseur classique (bras) ou caméra carénée
DESIGN = {
    "citadis1": {"desk": (86, 92, 102), "classic_mirror": True, "lamp": "c302"},
    "citadis2": {"desk": (160, 165, 170), "classic_mirror": False, "lamp": "plan"},
    "dualis": {"desk": (70, 76, 84), "classic_mirror": True, "lamp": "plan"},
    "tfs": {"desk": (112, 104, 92), "classic_mirror": True, "lamp": "plan", "desk_wrap": 0.08},
    "vevey": {"desk": (96, 98, 92), "classic_mirror": True, "lamp": "plan", "desk_wrap": 0.06},
    "bombardier": {"desk": (58, 62, 68), "classic_mirror": True, "lamp": "plan", "desk_wrap": 0.26},
    "siemens": {"desk": (128, 132, 138), "classic_mirror": True, "lamp": "plan", "desk_wrap": 0.14},
    "caf": {"desk": (46, 50, 56), "classic_mirror": False, "lamp": "plan", "desk_wrap": 0.24},
    "translohr": {"desk": (150, 152, 150), "classic_mirror": False, "lamp": "plan", "desk_wrap": 0.3},
    "breda": {"desk": (92, 96, 104), "classic_mirror": True, "lamp": "plan", "desk_wrap": 0.12},
    "stadler": {"desk": (60, 64, 70), "classic_mirror": True, "lamp": "plan", "desk_wrap": 0.18},
}
COLOR_KEYS = ("base", "window", "door", "front", "roof", "skirt")
DEFAULT_COLORS = {"base": "#f1f2f2", "window": "#1d2a33", "door": "#f1f2f2", "front": "#f1f2f2", "roof": "#c9cdd0", "skirt": "#3a3f44"}
ROUTE = "#2f6db5"      # couleur « route » (ligne GTFS) figée dans l'atlas : bleu neutre ; la caisse unie suit le réseau


def entries():
    return _json("data/rolling_stock/variants/index.json")["entries"]


def entry(vid):
    for e in entries():
        if e["id"] == vid:
            return e
    raise KeyError(vid)


def _col(c):
    return ROUTE if c == "route" or not isinstance(c, str) or not c.startswith("#") else c


def resolve_livery(e):
    """Couleurs + éléments de la variante (sans ligne : atlas partagé par toutes les lignes)."""
    livs = _json("data/rolling_stock/liveries.json"); net = livs.get(e["network"], {})
    fam = e["family"]; raw = dict(DEFAULT_COLORS); raw["elements"] = []
    layers = []
    if net:
        layers.append(net)
        fo = net.get("families", {}).get(fam)
        if fo: layers.append(fo)
    for layer in layers:
        for k in COLOR_KEYS + ("elements",):
            if k in layer: raw[k] = copy.deepcopy(layer[k])
    patch = _json("data/rolling_stock/variants/livery_overrides.json").get(e["id"], {})
    for k, v in patch.items():
        if k in COLOR_KEYS or k == "elements": raw[k] = copy.deepcopy(v)
    if e["network"] == "angers": raw["elements"] = [x for x in raw["elements"] if x.get("type") != "front_mask"]
    for k in COLOR_KEYS: raw[k] = _col(raw[k])
    for el in raw["elements"]: el["colors"] = [_col(c) for c in el.get("colors", [])] or [ROUTE]
    return raw


def livery_key(e):
    return hashlib.sha1(json.dumps(resolve_livery(e), sort_keys=True).encode()).hexdigest()[:10]


def nose_from_plan(P):
    """Profil de nez (style « gen ») dérivé du plan : D(y) = 1 - front.side(y) ; p selon la largeur en pointe."""
    fr = P["front"]; h = float(P.get("height_m", 3.3))
    side = sorted([float(a), float(b)] for a, b in fr.get("side", [[0, 0]]))
    D = [(max(y, 0.25), round(max(0.0, min(1.0, 1.0 - s)), 3)) for y, s in side if y < h - 0.05]
    if not D or D[0][0] > 0.26: D.insert(0, (0.25, D[0][1] * 0.9 if D else 0.9))
    D.append((h, 0.0))
    tip = float(sorted(fr.get("plan", [[1, 0.6]]))[-1][1])
    p = max(1.9, min(6.5, 1.9 + 4.6 * (tip - 0.45)))
    wrap = float(fr.get("windshield", {}).get("wrap", 0.3))
    tw = max(0.3, min(0.66, 0.64 - 0.42 * wrap))
    return {"style": "gen", "p": round(p, 3), "theta_w": round(tw, 3), "D": D,
            "windshield": {"bottom_m": float(fr["windshield"]["bottom_m"]), "top_m": float(fr["windshield"]["top_m"]),
                           "lower_curve_m": 0.03, "upper_curve_m": 0.10}}


def auto_spec(vid, kid=None):
    e = entry(vid); fam = e["family"]; maker = MAKER.get(fam, "citadis1"); dz = DESIGN[maker]
    liv = resolve_livery(e)
    mask = next((x["colors"][0] for x in liv["elements"] if x.get("type") == "front_mask"), liv["window"])
    accent = next((x["colors"][0] for x in liv["elements"] if x.get("type") in ("band", "diagonal", "stripes")), liv["door"])
    c = {k: liv[k] for k in COLOR_KEYS}; c["mask"] = mask; c["accent"] = accent
    from build_kits import kit_id
    kid = kid or kit_id(e)
    return {
        "dir": kid, "plan": fam, "network": e["network"], "family": fam, "label": e["name"],
        "front_style": "gen_" + maker, "maker": maker, "lamp_style": dz["lamp"], "classic_mirror": dz["classic_mirror"],
        "colors": c, "livery_rule": "elements", "livery_res": liv,
        "seat": {"fabric": "net_" + e["network"], "fabric_colors": [accent, liv["base"], liv["door"], liv["skirt"]],
                 "shell": "#4b5056", "pole": "#c9ced2" if maker != "citadis2" else accent, "pole_accent": accent},
        "fleet_number": "", "cab": {"desk": dz["desk"], "wrap": dz.get("desk_wrap", 0.20)},
        "interior": {"wall": "#eceeef", "ceiling": "#f2f3f3", "floor": "#6b7074"},
    }
