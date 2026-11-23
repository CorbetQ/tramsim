#!/usr/bin/env python3
"""Planche de contrôle : références (photos, ref_cts) en colonne de gauche, captures TramSim à droite.
python3 planche.py <sortie.png> <titre> ref1.jpg:cap1.png[:légende] [ref2:cap2 ...]  (ref vide = case blanche)"""
import sys
from PIL import Image, ImageDraw, ImageFont

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
W, H = 720, 405


def fit(path, w, h):
    im = Image.open(path).convert("RGB")
    r = min(w / im.width, h / im.height)
    im = im.resize((max(1, int(im.width * r)), max(1, int(im.height * r))), Image.LANCZOS)
    out = Image.new("RGB", (w, h), (24, 26, 28)); out.paste(im, ((w - im.width) // 2, (h - im.height) // 2))
    return out


def main():
    out, title, pairs = sys.argv[1], sys.argv[2], sys.argv[3:]
    f = ImageFont.truetype(FONT, 20); ft = ImageFont.truetype(FONT, 26)
    sheet = Image.new("RGB", (2 * W + 30, 60 + len(pairs) * (H + 34)), (18, 20, 22))
    d = ImageDraw.Draw(sheet)
    d.text((10, 14), title, fill=(240, 240, 240), font=ft)
    for i, p in enumerate(pairs):
        parts = p.split(":")
        ref, cap = parts[0], parts[1]; lab = parts[2] if len(parts) > 2 else ""
        y = 60 + i * (H + 34)
        if ref: sheet.paste(fit(ref, W, H), (10, y + 28))
        sheet.paste(fit(cap, W, H), (W + 20, y + 28))
        d.text((10, y + 2), "Référence" + (" — " + ref.split("/")[-1] if ref else ""), fill=(200, 200, 200), font=f)
        d.text((W + 20, y + 2), "TramSim P2 — " + lab, fill=(200, 230, 255), font=f)
    sheet.save(out, optimize=True)
    print(out)


if __name__ == "__main__":
    main()
