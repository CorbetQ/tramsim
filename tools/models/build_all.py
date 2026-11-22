#!/usr/bin/env python3
"""Génère les modèles dédiés du lot P1 (glTF binaires LOD0-2 + manifeste) :
    python3 tools/models/build_all.py
Sorties : assets/models/angers/*.glb, assets/models/nantes/*.glb, assets/models/landmark_models.json,
fiches data/materials/lm_*.json. Chargement : src/rendering/landmark_models.gd."""
import json
import geo
import materials_lm
import build_ralliement, build_cathedrale, build_tremie
from meshkit import translate

OUT = geo.ROOT / "assets/models"


def local(meta, a):
    def tr(ring): return [[round(p[0] - a[0], 3), round(p[1] - a[2], 3)] for p in ring]
    m = {}
    m["replace"] = [tr(r) for r in meta.get("replace", [])]
    m["blocks"] = [[tr(b[0]), round(b[1] - a[1], 3), round(b[2], 3)] for b in meta.get("blocks", [])]
    m["keepout"] = [[tr([o[0]])[0], tr([o[1]])[0], o[2]] for o in meta.get("keepout", [])]
    if "tunnel_footprint" in meta:
        m["tunnel_footprint"] = tr(meta["tunnel_footprint"])
        pc = meta["portal_cut"]; m["portal_cut"] = [tr([pc[0]])[0], tr([pc[1]])[0], round(pc[2], 2)]
    return m


def main():
    materials_lm.write_fiches()
    (OUT / "angers/textures").mkdir(parents=True, exist_ok=True); (OUT / "nantes").mkdir(parents=True, exist_ok=True)
    materials_lm.leaf_texture(OUT / "angers/textures/lm_feuillage_cartes.png")
    models = []
    specs = [
        ("angers_ralliement", "angers", "angers/ralliement", lambda: build_ralliement.build()[:3], [0, 160, 420, 1100],
         {"station": "Ralliement", "budget_lod0": 250000, "budget_mobile": 80000}),
        ("angers_cathedrale_saint_maurice", "angers", "angers/cathedrale_saint_maurice", build_cathedrale.build, [0, 260, 900, 6000],
         {"landmark": "Cathédrale Saint-Maurice", "budget_lod0": 150000, "budget_mobile": 80000}),
        ("nantes_tremie_l3", "nantes", "nantes/tremie_l3", lambda: build_tremie.build()[:3], [0, 110, 320, 1200],
         {"lightmap": True, "budget_lod0": 120000, "budget_mobile": 60000}),
    ]
    for mid, cname, stem, fn, ranges, extra in specs:
        k, a, meta = fn()
        city = geo.City(cname)
        lat, lon = geo.xy2ll(a[0], a[2], city.origin)
        translate(k, a)
        tris = []
        files = []
        for lod in range(3):
            p = OUT / f"{stem}_lod{lod}.glb"
            tris.append(k.export(p, lod, with_cols=(lod == 0)))
            files.append(f"res://assets/models/{stem}_lod{lod}.glb")
        m = {"id": mid, "city": cname, "anchor": [round(lat, 8), round(lon, 8)], "anchor_y": round(float(a[1]), 3),
             "lods": files, "ranges_m": ranges, "triangles": tris}
        m.update(extra); m.update(local(meta, a))
        models.append(m)
        print(mid, "triangles LOD0-2", tris)
    doc = {"schema": 1, "source": "tools/models/build_all.py (génération procédurale, géoréférencée sur data/ : BD TOPO, sol IGN, OSM, réseaux)",
           "models": models}
    (OUT / "landmark_models.json").write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    main()
