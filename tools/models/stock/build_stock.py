#!/usr/bin/env python3
"""Construit les rames HD : python3 tools/models/stock/build_stock.py [variant_id ...] [--no-pack]
Sorties : assets/models/rolling_stock/<dir>/{lod0,lod0_m,lod1,lod1_m,lod2,lod3,cab,cab_m}.glb, textures/,
assets/models/rolling_stock/manifest.json (schéma docs/refonte-visuelle/stock_manifest.md)."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import specs, layout, textures as TX
from citadis import Citadis
import cab as CAB

OUT = os.path.join(specs.ROOT, "assets/models/rolling_stock")
# fichier -> (q, taille de livrée)
LODS = [("lod0", 0, "4k"), ("lod0_m", 1, "2k"), ("lod1", 1, "2k"), ("lod1_m", 2, "2k"), ("lod2", 3, "512"), ("lod3", 4, "256")]


def build_variant(vid, only=None):
    sp = specs.load(vid); t = layout.Train(sp)
    d = os.path.join(OUT, sp["dir"]); td = os.path.join(d, "textures"); os.makedirs(td, exist_ok=True)
    from geom import Builder
    from citadis import materials, swatch_colors
    Bm = Builder(); materials(Bm, t, 0, "4k")
    TX.Painter(t).paint().swatches(swatch_colors(Bm)).save(td, "livery")
    TX.floor_textures(td, sp["interior"]["floor"])
    TX.fabric_texture(td, sp["seat"]["fabric"])
    TX.metal_textures(td)
    info = {"tris": {}, "nodes": {}}
    for fname, q, tag in LODS:
        if only and fname not in only: continue
        c = Citadis(t, q, tag); B = c.build()
        n = B.export(os.path.join(d, fname + ".glb"))
        info["tris"][fname] = n; info["nodes"][fname] = list(B.order)
        if q == 0: info["panto"] = c.panto
        print("  %-8s %7d tris  %d nœuds" % (fname, n, len(B.order)))
    for fname, q in (("cab", 0), ("cab_m", 1)):
        if only and fname not in only: continue
        cb = CAB.Cab(t, q); B = cb.build(td)
        n = B.export(os.path.join(d, fname + ".glb"))
        info["tris"][fname] = n; info["nodes"][fname] = list(B.order); info["cab"] = cb.meta
        print("  %-8s %7d tris" % (fname, n))
    return sp, t, info


def manifest_entry(sp, t, info):
    import citadis
    pg = info.get("panto") or citadis.panto_geometry(t, 0.0)
    tri = info["tris"]
    e = {
        "dir": sp["dir"], "family": sp["family"], "name": sp["label"],
        "length_m": round(t.L, 3), "width_m": round(2 * t.hw, 3),
        "modules": [round(m["Lm"], 4) for m in t.mods],
        "doors": t.n_doors,
        "lods": {
            "LOD0": {"file": "lod0.glb", "tris": tri.get("lod0"), "mobile_file": "lod0_m.glb", "mobile_tris": tri.get("lod0_m")},
            "LOD1": {"file": "lod1.glb", "tris": tri.get("lod1"), "mobile_file": "lod1_m.glb", "mobile_tris": tri.get("lod1_m")},
            "LOD2": {"file": "lod2.glb", "tris": tri.get("lod2")},
            "LOD3": {"file": "lod3.glb", "tris": tri.get("lod3")},
        },
        "mobile_tris": {"LOD0": tri.get("lod0_m"), "LOD1": tri.get("lod1_m"), "LOD2": tri.get("lod2"), "LOD3": tri.get("lod3")},
        "cab": {"file": "cab.glb", "tris": tri.get("cab"), "mobile_file": "cab_m.glb", "mobile_tris": tri.get("cab_m")},
        "textures": {"pc_px": 4096, "mobile_px": 2048, "cab_px": 2048,
                     "files": {"livery": ["textures/livery_4k.png (LOD0)", "textures/livery_2k.png (LOD0 mobile, LOD1)",
                                          "textures/livery_512.png (LOD2)", "textures/livery_256.png (LOD3)"],
                               "cab": "textures/cab_desk.png", "interior": ["textures/floor_albedo.png", "textures/floor_normal.png",
                                                                            "textures/fabric_%s.png" % sp["seat"]["fabric"]],
                               "metal": ["textures/metal_albedo.png", "textures/metal_normal.png", "textures/metal_orm.png"]}},
        "panto": {"module": next(m["i"] for m in t.mods if any(r["type"] == "pantograph" for r in m["roof"])),
                  "lower_deg": pg["lower_deg"], "upper_deg": pg["upper_deg"], "arm_lower_m": pg["l1"], "arm_upper_m": pg["l2"],
                  "head_down_y": round(pg["head_down_y"], 3), "head_up_y": round(pg["head_up_y"], 3),
                  "note": "rotations autour de +X local (positif = vers le haut pour un bras pointant vers -Z) ; pose du glb = baissé"},
        "wiper": {"axis": "z", "sweep_deg": 95.0, "period_s": 1.6, "direction": 1,
                  "note": "Z local = normale du pare-brise au pivot ; angle positif = balayage vers le haut"},
        "mirror": {"fold_deg": 80.0, "nodes": ["mirror_L", "mirror_R", "mirror_B_L", "mirror_B_R"]},
        "sign": {"width_m": 1.2, "height_m": 0.2},
        "cab_proxy": {"A": "cab_proxy_A", "B": "cab_proxy_B",
                      "note": "aménagement simplifié des loges dans lod0/lod1 : à masquer à l'extrémité où cab.glb est instancié"},
        "bogies": [n for n in info["nodes"].get("lod0", []) if n.startswith("bogie_")],
        "door_anim": t.door_anim,
    }
    e.update(info.get("cab", {}))
    e["sources"] = ["plan data/rolling_stock/plans/%s.json (modules mis à l'échelle de %.2f m)" % (sp["plan"], t.L),
                    "livrée data/rolling_stock/liveries.json#%s + photos docs/rolling-stock-meshy (Commons CC BY-SA, références)" % sp["network"],
                    "textures : générées (CC0, projet) ; métal Poly Haven rusty_metal_02 (CC0)"]
    e["license"] = "CC-BY-SA 4.0 (production du projet, géométrie procédurale tools/models/stock)"
    return e


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    only = None
    for a in sys.argv[1:]:
        if a.startswith("--only="): only = a[7:].split(",")
    vids = args or list(specs.VARIANTS)
    mp = os.path.join(OUT, "manifest.json")
    man = json.load(open(mp)) if os.path.exists(mp) else {"version": 1, "variants": {}}
    for vid in vids:
        t0 = time.time(); print(vid)
        sp, t, info = build_variant(vid, only)
        if only is None:
            man["variants"][vid] = manifest_entry(sp, t, info)
        print("  %.1f s" % (time.time() - t0))
    man["version"] = 1
    man["generator"] = "tools/models/stock/build_stock.py"
    man["schema"] = "docs/refonte-visuelle/stock_manifest.md"
    with open(mp, "w", encoding="utf-8") as f:
        json.dump(man, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
