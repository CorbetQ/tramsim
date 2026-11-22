#!/usr/bin/env python3
"""Planches du lot P1 (CDC §7.2) à partir des captures de tests/audit/p1_shots.gd.

usage : p1_planche.py SHOTS_DIR REFS_DIR OUT_DIR [suffixe ...]
- OUT/planche_<suffixe>.png : référence | TramSim côte à côte pour C1–C3 (lisible) ;
- OUT/aveugle_<suffixe>.png + OUT/cle_<suffixe>.json : mêmes paires étiquetées A/B dans un ordre aléatoire
  (notation à l'aveugle, docs/refonte-visuelle/notation_P1.md).
Références : ref1_cabine_station_couverte.jpg, ref2_rame_exterieur.jpg, ref3_tremie.jpg (hors dépôt).
"""
import json, os, random, sys
from PIL import Image, ImageDraw

REFS = {"C1": "ref1_cabine_station_couverte.jpg", "C2": "ref2_rame_exterieur.jpg", "C3": "ref3_tremie.jpg"}
W, H = 640, 360


def fit(path):
    im = Image.open(path).convert("RGB")
    r = max(W / im.width, H / im.height)
    im = im.resize((round(im.width * r), round(im.height * r)), Image.LANCZOS)
    x, y = (im.width - W) // 2, (im.height - H) // 2
    return im.crop((x, y, x + W, y + H))


def label(im, text):
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 9 * len(text) + 12, 22), fill=(0, 0, 0))
    d.text((6, 5), text, fill=(255, 255, 255))
    return im


def main(shots, refs, out, suffixes):
    os.makedirs(out, exist_ok=True)
    rng = random.Random(20261122)
    for suf in suffixes:
        sheet = Image.new("RGB", (W * 2, H * 3), (20, 20, 20))
        blind = Image.new("RGB", (W * 2, H * 3), (20, 20, 20))
        key = {}
        for i, c in enumerate(["C1", "C2", "C3"]):
            ref = fit(os.path.join(refs, REFS[c]))
            sim_p = os.path.join(shots, f"{c}{suf}.png")
            sim = fit(sim_p) if os.path.exists(sim_p) else Image.new("RGB", (W, H), (60, 0, 0))
            sheet.paste(label(ref.copy(), f"{c} reference"), (0, i * H))
            sheet.paste(label(sim.copy(), f"{c} TramSim {suf.strip('_')}"), (W, i * H))
            pair = [("reference", ref), ("tramsim", sim)]
            rng.shuffle(pair)
            key[c] = {"A": pair[0][0], "B": pair[1][0]}
            blind.paste(label(pair[0][1].copy(), f"{c} A"), (0, i * H))
            blind.paste(label(pair[1][1].copy(), f"{c} B"), (W, i * H))
        sheet.save(os.path.join(out, f"planche{suf}.png"))
        blind.save(os.path.join(out, f"aveugle{suf}.png"))
        json.dump(key, open(os.path.join(out, f"cle{suf}.json"), "w"), indent=1)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:] or [""])
