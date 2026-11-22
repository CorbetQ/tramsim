"""Fiches de matériaux propres aux modèles dédiés (préfixe lm_, data/materials) et texture de feuillage (CC0,
générée ici). Couleur unie + scalaires (repli documenté de PbrMaterials) tant que la bibliothèque n'a pas de couche
texturée correspondante."""
import json, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
import geo

SRC = "Modèles dédiés P1 (tools/models, agent modélisateur) : repli documenté, couleur unie et scalaires PBR ; pas de texture tierce."
LM = {
    "lm_vitre": ("Vitrages de façade (fenêtres, vitrines)", "#2b3238", 0.06, 0.0, {"glass": 0.82}),
    "lm_vitrail": ("Vitraux (cathédrale)", "#3a3550", 0.22, 0.0, {}),
    "lm_menuiserie": ("Menuiseries peintes claires", "#e6e2d6", 0.45, 0.0, {}),
    "lm_menuiserie_sombre": ("Menuiseries et devantures sombres", "#2d3134", 0.4, 0.3, {}),
    "lm_ferronnerie": ("Ferronnerie (balcons, garde-corps)", "#1f2123", 0.5, 0.65, {}),
    "lm_zinc": ("Zinc (terrassons, gouttières, glissières)", "#8a9196", 0.42, 0.75, {}),
    "lm_ecorce": ("Écorce (platane, tilleul)", "#6b6253", 0.92, 0.0, {}),
    "lm_feuillage": ("Feuillage en cartes (alpha)", "#5d7f3e", 0.75, 0.0, {"translucency": 0.5, "card_texture": "res://assets/models/angers/textures/lm_feuillage_cartes.png"}),
    "lm_bois": ("Bois des bancs", "#8b6a47", 0.7, 0.0, {}),
    "lm_inox": ("Inox brossé", "#a9adb0", 0.32, 1.0, {}),
    "lm_ecran": ("Écrans d'information (émissifs)", "#14324a", 0.2, 0.0, {"emission": True, "emission_energy": 0.6}),
    "lm_panneau": ("Panneaux d'information (fond clair)", "#eef0ee", 0.5, 0.0, {}),
    "lm_ligne": ("Couleur de ligne Irigo C (vert)", "#379e32", 0.5, 0.0, {}),
    "lm_peinture_blanche": ("Ossature acier laquée blanche (auvents)", "#eceeed", 0.38, 0.15, {}),
    "lm_devanture_a": ("Devanture peinte (vert sombre)", "#24403a", 0.45, 0.1, {}),
    "lm_devanture_b": ("Devanture peinte (bordeaux)", "#5a2229", 0.45, 0.1, {}),
    "lm_podotactile": ("Bande podotactile (résine claire)", "#d9d7cf", 0.6, 0.0, {}),
    "lm_toile": ("Toile de parasol (rouge)", "#b3322c", 0.85, 0.0, {}),
    "lm_led": ("Réglettes LED de trémie (émissives)", "#f2f6ff", 0.3, 0.0, {"emission": True, "emission_energy": 3.0}),
    "lm_marquage": ("Marquage au sol (peinture blanche)", "#e9e9e4", 0.7, 0.0, {}),
    "lm_ardoise_faitage": ("Faîtages et noues (plomb)", "#5b6066", 0.45, 0.6, {}),
    "lm_caniveau": ("Grilles de caniveau (fonte)", "#2a2c2e", 0.6, 0.5, {}),
    "lm_jaune": ("Peinture jaune de signalisation", "#e0b020", 0.55, 0.0, {}),
    "lm_joint": ("Joints de reprise de bétonnage", "#6a6863", 0.9, 0.0, {}),
    "lm_rouge": ("Portes de niche de secours (rouge)", "#a3231d", 0.45, 0.2, {}),
    "lm_secours": ("Signalisation d'évacuation (émissive)", "#1f9a4a", 0.4, 0.0, {"emission": True, "emission_energy": 1.5}),
}


def write_fiches():
    for i, (k, (label, col, rough, metal, extra)) in enumerate(LM.items()):
        d = {"id": k, "label": label, "albedo_color": col, "roughness": rough, "metallic": metal, "specular": 0.5,
             "textures": {"albedo": "", "normal": "", "orm": ""}, "uv_scale_m": 1.0, "normal_scale": 1.0, "source": SRC}
        d.update(extra)
        (geo.ROOT / f"data/materials/{k}.json").write_text(json.dumps(d, ensure_ascii=False, indent=1) + "\n")


def leaf_texture(path, size=512, seed=3):
    """Atlas 2×2 de rameaux feuillus (RGBA), vert de platane/tilleul, bords alpha nets (alpha scissor)."""
    rng = np.random.default_rng(seed)
    img = Image.new("RGBA", (size, size), (70, 95, 45, 0))
    dr = ImageDraw.Draw(img)
    h = size // 2
    for cell in range(4):
        ox, oy = (cell % 2) * h, (cell // 2) * h
        cx, cy = ox + h / 2, oy + h / 2
        # rameau : tige puis feuilles palmées le long
        for b in range(5):
            a = rng.uniform(0, 2 * math.pi); L = rng.uniform(0.25, 0.45) * h
            x1, y1 = cx + math.cos(a) * L, cy + math.sin(a) * L
            dr.line([(cx, cy), (x1, y1)], fill=(72, 60, 40, 255), width=2)
            for j in range(9):
                t = rng.uniform(0.15, 1.0); px, py = cx + (x1 - cx) * t, cy + (y1 - cy) * t
                r = rng.uniform(0.06, 0.11) * h; ang = a + rng.uniform(-1.4, 1.4)
                g = rng.uniform(0.75, 1.15); base = np.array([88, 122, 52]) * g
                if rng.uniform() < 0.25: base = np.array([120, 140, 60]) * g
                col = tuple(int(np.clip(c, 0, 255)) for c in base) + (255,)
                lx, ly = px + math.cos(ang) * r * 0.6, py + math.sin(ang) * r * 0.6
                dr.ellipse([lx - r * 0.55, ly - r * 0.4, lx + r * 0.55, ly + r * 0.4], fill=col)
        for j in range(26):   # feuilles isolées pour remplir
            r = rng.uniform(0.04, 0.08) * h; px, py = cx + rng.normal(0, 0.2) * h, cy + rng.normal(0, 0.2) * h
            if abs(px - cx) > h * 0.46 or abs(py - cy) > h * 0.46: continue
            g = rng.uniform(0.7, 1.1); col = tuple(int(c * g) for c in (82, 116, 50)) + (255,)
            dr.ellipse([px - r, py - r * 0.7, px + r, py + r * 0.7], fill=col)
    # ombrage interne léger (teinte plus sombre vers le centre de chaque vignette)
    a = np.array(img).astype(float)
    yy, xx = np.mgrid[0:size, 0:size]
    d = np.hypot((xx % h) - h / 2, (yy % h) - h / 2) / (h / 2)
    a[..., :3] *= (0.78 + 0.22 * np.clip(d, 0, 1))[..., None]
    Image.fromarray(a.astype(np.uint8)).save(path)


if __name__ == "__main__":
    write_fiches()
    out = geo.ROOT / "assets/models/angers/textures"; out.mkdir(parents=True, exist_ok=True)
    leaf_texture(out / "lm_feuillage_cartes.png")
    print("fiches", len(LM))
