"""Spécifications des rames HD : plan coté (data/rolling_stock/plans), longueur du rig (variants/index.json),
livrée (data/rolling_stock/liveries.json, complétée par les photos de référence docs/rolling-stock-meshy) et
particularités de face avant et de cabine. Coordonnées de livrée : zf = distance au nez A (m), y = hauteur (m)."""
import json, os, copy
from pathlib import Path
from audit_stock import fitted_plan

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
IRIGO_RAINBOW = ["#6a2c91", "#0096d6", "#5cb531", "#ffd500", "#f18a00", "#e2231a"]  # avant -> arrière (photos)


def _json(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return json.load(f)


VARIANTS = {
    "angers__citadis_x05": {
        "dir": "angers_x05", "plan": "citadis_x05", "network": "angers", "family": "citadis_x05",
        "label": "Citadis X05 (305) Irigo", "front_style": "x05",
        "colors": {"base": "#e9ecef", "window": "#16191a", "door": "#e3e8ee", "front": "#e9ecef", "roof": "#d4d8db",
                   "skirt": "#3c4246", "mask": "#141617", "accent": "#1a1d1c"},
        "rainbow": IRIGO_RAINBOW,
        # blocs arc-en-ciel (photos 2015/171177511 : blocs obliques sous les baies, derrière chaque porte, et
        # bandeau oblique au-dessus de la première porte de chaque loge) ; miroir pour l'extrémité B.
        "livery_rule": "irigo_x05",
        "seat": {"fabric": "irigo", "shell": "#4b5056", "pole": "#f2c200", "pole_accent": "#5cb531"},
        "fleet_number": "2015",
        "cab": {"desk": (168, 172, 176)},
        "interior": {"wall": "#eceeef", "ceiling": "#f2f3f3", "floor": "#6b7074"},
    },
    "nantes__citadis_x05_nantes": {
        "dir": "nantes_x05", "plan": "citadis_x05_nantes", "network": "nantes", "family": "citadis_x05_nantes",
        "label": "Citadis X05 (405) Naolib", "front_style": "x05_nantes",
        # photos (reference-nantes405.jpg) : flancs vert sapin, joues avant blanches, toit blanc, tablier vert
        # sombre, couronne lumineuse verte autour du pare-brise, 68 alvéoles hexagonales de feux.
        "colors": {"base": "#2b4842", "window": "#111416", "door": "#2b4842", "front": "#eef0ee", "roof": "#e6e9e7",
                   "skirt": "#1d2b28", "mask": "#121517", "accent": "#00a77e", "apron": "#2a4a43"},
        "livery_rule": "naolib",
        "seat": {"fabric": "naolib", "shell": "#3d4744", "pole": "#00a77e", "pole_accent": "#00a77e"},
        "fleet_number": "417",
        "cab": {"desk": (176, 182, 180)},
        "interior": {"wall": "#eef0ef", "ceiling": "#f3f4f3", "floor": "#5f6563"},
    },
    "angers__citadis_302": {
        "dir": "angers_302", "plan": "citadis_302", "network": "angers", "family": "citadis_302",
        "label": "Citadis 302 Irigo", "front_style": "c302",
        "colors": {"base": "#e3e8ee", "window": "#1a1d1c", "door": "#e3e8ee", "front": "#e3e8ee", "roof": "#c9cdd0",
                   "skirt": "#444b4f", "mask": "#1a1d1c", "accent": "#1a1d1c"},
        "rainbow": IRIGO_RAINBOW,
        "livery_rule": "liveries_json",     # éléments de data/rolling_stock/liveries.json (angers)
        "seat": {"fabric": "irigo", "shell": "#4b5056", "pole": "#f2c200", "pole_accent": "#f18a00"},
        "fleet_number": "1011",
        "cab": {"desk": (86, 92, 102)},      # pupitre 302 : gris-bleu sombre (génération 2000)
        "interior": {"wall": "#e9ebec", "ceiling": "#f0f1f1", "floor": "#6b7074"},
    },
}


def variant_entry(vid):
    for e in _json("data/rolling_stock/variants/index.json")["entries"]:
        if e["id"] == vid:
            return e
    raise KeyError(vid)


def load(vid):
    s = copy.deepcopy(VARIANTS[vid]); s["id"] = vid
    s["plan_data"] = _json("data/rolling_stock/plans/%s.json" % s["plan"])
    e = variant_entry(vid)
    s['family'] = e['family']; s['label'] = e['name']
    s['plan'] = 'citadis_x05_nantes' if e.get('cab_profile')=='naolib' else e['family']
    s['plan_data'] = fitted_plan(Path(ROOT), e)
    seen_panto = False
    for module in s['plan_data']['modules']:
        for roof in module.get('roof', []):
            if roof['type']=='pantograph':
                if seen_panto: roof['type']='box'
                seen_panto=True
    if not seen_panto:
        first=s['plan_data']['modules'][0]
        first.setdefault('roof',[]).append({'type':'pantograph','z_m':first['length_m']*0.65,'size':[1.2,0.3,2.0]})
    profile = _json('data/rolling_stock/front_profiles.json').get(e.get('cab_profile',''))
    if profile:
        s['nose_profile'] = profile
        s['plan_data']['front']['windshield'].update(profile['windshield'])
    s["length"] = float(e["length"]); s["width"] = float(e.get("width", s["plan_data"]["width_m"]))
    liv = _json("data/rolling_stock/liveries.json").get(s["network"], {})
    s["livery_json"] = liv
    return s


def hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def srgb2lin(c):
    return tuple((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)
