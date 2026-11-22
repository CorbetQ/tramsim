#!/usr/bin/env python3
"""Bibliothèque de matériaux PBR (refonte P1) : construit les tableaux de textures (Texture2DArray Godot) à partir des
textures CC0 téléchargées (Poly Haven), et met à jour les fiches data/materials/*.json (couche, moyennes).

Entrée : DL/<asset>/{Diffuse,nor_gl,arm}.jpg + info.json (tools/materials/fetch_polyhaven.sh).
Sortie : assets/textures/pbr/{albedo,normal,orm}_{2k,1k}.jpg — couches empilées verticalement (une couche par
matériau, ordre de LAYERS), importées par Godot en Texture2DArray VRAM compressée (S3TC/BPTC PC, ETC2/ASTC Android).
ORM = AO (R), rugosité (G), métal (B) : c'est le format « arm » de Poly Haven. Normales au format OpenGL (Y+).

usage : build_texture_arrays.py DL_DIR REPO_DIR
"""
import json, sys, os
from PIL import Image, ImageStat

# (couche, fiche data/materials, asset Poly Haven, taille du motif en m si différente des dimensions déclarées)
LAYERS = [
    ("enrobe", "asphalt_02", 3.0),
    ("dallage", "concrete_pavers_02", 2.0),
    ("gazon", "grass_ground", 2.0),
    ("toiture", "roof_slates_02", 3.0),
    ("facade_enduit", "beige_wall_001", 3.0),
    ("sol_nu", "dirt", 2.0),
    ("acier_rail", "rusty_metal_02", 1.0),
    ("beton_dalle", "concrete_pavement", 1.8),
    ("ballast", "gravel_stones", 1.5),
    ("paves_granit", "cobblestone_square", 1.0),
    ("facade_tuffeau", "white_sandstone_blocks_02", 2.0),
    ("facade_brique", "brick_wall_001", 3.0),
    ("bordure_granit", "granite_tile", 2.3),
    ("beton_banche", "concrete_slab_wall", 2.3),
    ("mobilier_metal", "green_metal_rust", 1.5),
    ("pierre_taille", "large_sandstone_blocks", 3.0),
    ("lm_ecorce", "bark_platanus", 2.0),
    ("lm_bois", "weathered_brown_planks", 2.0),
]
MAPS = {"albedo": ("Diffuse", 86), "normal": ("nor_gl", 88), "orm": ("arm", 84)}
SIZES = {"2k": 2048, "1k": 1024}


def main(dl, repo):
    out = os.path.join(repo, "assets/textures/pbr")
    os.makedirs(out, exist_ok=True)
    stats = {}
    for slot, (src, q) in MAPS.items():
        for tag, px in SIZES.items():
            sheet = Image.new("RGB", (px, px * len(LAYERS)))
            for i, (mid, asset, _) in enumerate(LAYERS):
                im = Image.open(os.path.join(dl, asset, src + ".jpg")).convert("RGB").resize((px, px), Image.LANCZOS)
                sheet.paste(im, (0, i * px))
                if tag == "1k":
                    st = ImageStat.Stat(im)
                    stats.setdefault(mid, {})[slot] = [round(v / 255.0, 4) for v in st.mean]
            sheet.save(os.path.join(out, f"{slot}_{tag}.jpg"), quality=q, optimize=True, subsampling=0 if slot == "normal" else 2)
            print(slot, tag, os.path.getsize(os.path.join(out, f"{slot}_{tag}.jpg")) // 1024, "Ko")
    credits = []
    for i, (mid, asset, uv_m) in enumerate(LAYERS):
        info = json.load(open(os.path.join(dl, asset, "info.json")))
        path = os.path.join(repo, "data/materials", mid + ".json")
        e = json.load(open(path)) if os.path.exists(path) else {}
        e.setdefault("id", mid)
        e["textures"] = {s: f"res://assets/textures/pbr/{s}_2k.jpg" for s in MAPS}
        e["textures_mobile"] = {s: f"res://assets/textures/pbr/{s}_1k.jpg" for s in MAPS}
        e["layer"] = i
        e["uv_scale_m"] = uv_m
        m = stats[mid]
        e["albedo_mean"] = "#%02x%02x%02x" % tuple(round(v * 255) for v in m["albedo"])
        e["roughness_mean"] = m["orm"][1]
        e["ao_mean"] = m["orm"][0]
        authors = ", ".join(info.get("authors", {}).keys())
        prev = str(e.get("source", ""))
        keep = "Modèles dédiés P1 (tools/models, agent modélisateur) ; texture : " if prev.startswith("Modèles dédiés") else ""
        e["source"] = keep + f"Poly Haven « {info.get('name', asset)} » ({asset}), {authors}, CC0 — https://polyhaven.com/a/{asset}"
        json.dump(e, open(path, "w"), ensure_ascii=False, indent=1)
        open(path, "a").write("\n")
        credits.append({"layer": i, "material": mid, "asset": asset, "name": info.get("name"), "authors": list(info.get("authors", {}).keys()),
                        "license": "CC0 1.0", "url": f"https://polyhaven.com/a/{asset}", "real_size_m": uv_m})
    json.dump(credits, open(os.path.join(out, "credits.json"), "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
