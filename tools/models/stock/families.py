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
    "citadis1": {"cab": "classic", "plastic": "#8c949c", "desk": (86, 92, 102), "classic_mirror": True, "lamp": "c302"},
    "citadis2": {"cab": "tri", "plastic": "#b4b9bd", "desk": (160, 165, 170), "classic_mirror": False, "lamp": "plan"},
    "dualis": {"cab": "classic", "plastic": "#7d858d", "desk": (70, 76, 84), "classic_mirror": True, "lamp": "plan"},
    "tfs": {"cab": "classic", "plastic": "#9a948a", "desk": (112, 104, 92), "classic_mirror": True, "lamp": "plan", "desk_wrap": 0.08},
    "vevey": {"cab": "classic", "plastic": "#8f918a", "desk": (96, 98, 92), "classic_mirror": True, "lamp": "plan", "desk_wrap": 0.06},
    "bombardier": {"cab": "duo", "plastic": "#4a4f55", "desk": (58, 62, 68), "classic_mirror": True, "lamp": "plan", "desk_wrap": 0.26},
    "siemens": {"cab": "duo", "plastic": "#c3c7cb", "desk": (128, 132, 138), "classic_mirror": True, "lamp": "plan", "desk_wrap": 0.14},
    "caf": {"cab": "duo", "plastic": "#3a3e44", "desk": (46, 50, 56), "classic_mirror": False, "lamp": "plan", "desk_wrap": 0.24},
    "translohr": {"cab": "tri", "plastic": "#c8cac8", "desk": (150, 152, 150), "classic_mirror": False, "lamp": "plan", "desk_wrap": 0.3},
    "breda": {"cab": "classic", "plastic": "#8a9098", "desk": (92, 96, 104), "classic_mirror": True, "lamp": "plan", "desk_wrap": 0.12},
    "stadler": {"cab": "duo", "plastic": "#555a60", "desk": (60, 64, 70), "classic_mirror": True, "lamp": "plan", "desk_wrap": 0.18},
}
# Faces calées sur photos (docs/rolling-stock-rebuild/references) quand le plan donneur est trop générique :
# nez (D(y) relatif, p, theta_w, pare-brise), feux, toiture carénée ; clé = cab_profile du catalogue.
FACE = {
    # Dualis : nez « bulle » très bombé, grand pare-brise galbé descendant bas, doubles optiques rondes
    "dualis": {"nose": {"p": 2.35, "theta_w": 0.42, "D": [(0.25, 0.86), (0.45, 0.97), (0.8, 1.0), (1.15, 0.98), (1.5, 0.92),
                         (1.9, 0.80), (2.3, 0.63), (2.7, 0.43), (3.0, 0.24), (3.2, 0.09), (3.35, 0.0)],
                         "windshield": {"bottom_m": 1.12, "top_m": 2.95, "lower_curve_m": 0.16, "upper_curve_m": 0.18}},
               "lamps": {"shape": "double_round", "x_m": 0.62, "y_m": 0.86, "w_m": 0.15, "h_m": 0.15}},
    # Flexity Outlook Marseille : face haute presque verticale, pare-brise panoramique arrondi, masque noir,
    # phares ronds latéraux bas, carénages de toiture continus
    "marseille": {"nose": {"p": 3.4, "theta_w": 0.34, "D": [(0.25, 0.80), (0.45, 0.93), (0.8, 1.0), (1.2, 0.99), (1.8, 0.95),
                           (2.4, 0.87), (2.9, 0.74), (3.15, 0.55), (3.3, 0.25), (3.4, 0.0)],
                           "windshield": {"bottom_m": 1.0, "top_m": 3.02, "lower_curve_m": 0.10, "upper_curve_m": 0.20}},
                  "lamps": {"shape": "round", "x_m": 0.80, "y_m": 0.72, "w_m": 0.17, "h_m": 0.17}, "roof_covered": True},
}
FACE["tpg_cityrunner"] = FACE["flexity_basel"] = FACE["marseille"]
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


def nose_profile(P, face):
    if face.get("nose"):
        n = copy.deepcopy(face["nose"]); n["style"] = "gen"; return n
    return nose_from_plan(P)


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
    face = FACE.get(e.get("cab_profile", ""), {})
    return {"face": face, "roof_covered": bool(face.get("roof_covered")), "cab_layout": dz.get("cab", "tri"),
            "cab_plastic": dz.get("plastic", "#b4b9bd"),
        "dir": kid, "plan": fam, "network": e["network"], "family": fam, "label": e["name"],
        "front_style": "gen_" + maker, "maker": maker, "lamp_style": dz["lamp"], "classic_mirror": dz["classic_mirror"],
        "colors": c, "livery_rule": "elements", "livery_res": liv,
        "seat": {"fabric": "net_" + e["network"], "fabric_colors": [accent, liv["base"], liv["door"], liv["skirt"]],
                 "shell": "#4b5056", "pole": "#c9ced2" if maker != "citadis2" else accent, "pole_accent": accent},
        "fleet_number": "", "cab": {"desk": dz["desk"], "wrap": dz.get("desk_wrap", 0.20)},
        "interior": {"wall": "#eceeef", "ceiling": "#f2f3f3", "floor": "#6b7074"},
    }
