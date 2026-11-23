# Manifeste des rames HD (P2) — schéma v1

Contrat entre le **modélisateur** (produit `assets/models/rolling_stock/`) et l'**ingénieur**
(`src/rendering/stock_hd.gd`, `cab_*.gd`). Tout ce qui n'est pas listé ici est ignoré par le code ;
tout ce qui est marqué *requis* est vérifié par `tests/test_stock_hd.gd` (une variante invalide
retombe sur le modèle actuel `TramModel` + `CitadisMeshy`, jamais un mélange).

## Arborescence

```
assets/models/rolling_stock/
  manifest.json
  <dir>/lod0.glb  lod1.glb  lod2.glb  lod3.glb   # extérieur, un fichier par LOD
  <dir>/cab.glb                                  # cabine de conduite (vue conducteur)
  <dir>/textures/…                               # embarquées ou référencées par les glb
```

## Repères (identiques au rig `TramModel.Rig`)

- Unités : mètre. **Y vers le haut, 0 = dessus du rail. -Z = avant (cabine A), +X = droite** dans le sens de marche.
- Chaque glb LOD contient un nœud racine par caisse : `module_00` … `module_NN` (0 = caisse de tête A).
  **Origine de `module_XX` = centre de la caisse** (milieu en Z de sa longueur dans `modules`), à Y = 0.
  Les maillages de la caisse sont des enfants (transformations appliquées ou non : le code ne lit que la hiérarchie).
- Extrémité **A** = avant de `module_00` (-Z) ; extrémité **B** = arrière du dernier module (+Z).
- `cab.glb` est exprimé **dans le repère de `module_00`** (cabine A). Le code l'instancie aussi en cabine B
  (dernier module, rotation 180° autour de Y) quand la cabine B est active.

## Nœuds nommés

| Nom | LOD | Rôle / animation faite par le code |
|---|---|---|
| `module_XX` | 0–3 | *requis*, un par caisse, dans l'ordre. |
| `door_<n>_<L\|R>_a`, `door_<n>_<L\|R>_b` | 0–1 | vantaux de la porte `n` (0 = la plus en avant, numérotation continue sur toute la rame), côté L/R. `a` = vantail avant (coulisse vers -Z), `b` = arrière (+Z). Porte à un vantail : `door_<n>_<L\|R>` (coulisse vers +Z). Origine libre : le code **translate** depuis la pose fermée (louvoiement `out_m` puis coulissement `travel_m`, valeurs du plan `door_anim`). *Requis* en LOD0 : autant de portes que le plan. |
| `panto_base`, `panto_lower`, `panto_upper`, `panto_head` | 0–1 (2 : statique) | enfants du module indiqué par `panto.module`. `panto_lower` : pivot = articulation basse, **rotation autour de son X local** ; `panto_upper` enfant de `panto_lower`, pivot = genou, rotation X ; `panto_head` enfant de `panto_upper` (le code le contre-tourne pour garder l'archet horizontal). Pose du glb = **pantographe baissé**, angles levés dans `panto.lower_deg`/`upper_deg`. |
| `wiper_<A\|B>_<k>` | 0 | essuie-glace, pivot à l'origine, rotation autour de l'axe `wiper.axis` (défaut `z` local), amplitude `wiper.sweep_deg`. |
| `mirror_<L\|R>` | 0–1 | rétroviseur/caméra extérieure, pivot = charnière, rotation Y de `mirror.fold_deg` quand rabattu. |
| `em_head_<A\|B>` | 0–2 | phares (émissif blanc) — allumés à l'extrémité active. |
| `em_tail_<A\|B>` | 0–2 | feux arrière (émissif rouge) — allumés à l'extrémité opposée. |
| `em_interior` (préfixe) | 0–1 | plafonniers (émissif), allumés la nuit / en tunnel. Plusieurs nœuds `em_interior*` admis. |
| `em_dest_<A\|B>` | 0–2 | fond de girouette (émissif). |
| `sign_dest_<A\|B>` | 0–2 | **ancre** (Node3D vide) de la girouette : centre du texte, -Z local = normale sortante, largeur utile `sign.width_m`. Le code y pose le texte de destination de la mission. |
| `glass*` (matériau) | 0–2 | surfaces vitrées : le code impose un verre PBR (réfléchissant, ReflectionProbe en Ultra/Haut, intérieur visible). |
| `paint_<zone>` (matériau) | 0–3 | peinture de caisse ; `zone` ∈ `base, front, door, roof, skirt, window` : couleur de la livrée du réseau + **clearcoat**. Un matériau `livery*` texturé garde sa texture et reçoit le clearcoat. |

### Cabine (`cab.glb`)

| Nom | Rôle |
|---|---|
| `cam_driver` | *requis* : point de vue conducteur (Node3D/Marker3D). -Z local = regard. Pare-brise et pupitre doivent être visibles depuis ce point avec un FOV de 62°. |
| `ctl_<action>` | *requis* pour chaque action de `src/input/cab_actions.gd` (liste ci-dessous). Nœud parent de la pièce mobile ; pivot = axe de l'animation. Le code crée une zone cliquable à partir de l'AABB des maillages enfants. |
| `screen_<contenu>` | quad (MeshInstance3D, UV 0..1, UV (0,0) en haut à gauche) qui reçoit un `SubViewport`. Contenus reconnus : `speed`, `notch`, `next_stop`, `signal`, `info` (texte combiné). |
| `em_lamp_<voyant>` | voyant émissif du pupitre : `doors`, `panto`, `power`, `emergency`, `sand`, `headlights`. |

### Actions de cabine (`src/input/cab_actions.gd`)

| Action | Nœud | Touche | Type d'animation (`controls[...].kind`) |
|---|---|---|---|
| `notch` (manipulateur traction/frein) | `ctl_notch` | W/Z/↑, S/↓, X | `lever` : rotation suivant le cran réel -1..1 → `range_deg` |
| `emergency` (arrêt d'urgence, coup de poing) | `ctl_emergency` | Espace | `button` |
| `doors` (portes côté quai) | `ctl_doors` | O | `button` |
| `horn` (gong / klaxon) | `ctl_horn` | K | `button` |
| `pantograph` (LAC / APS, alimentation) | `ctl_pantograph` | P | `toggle` |
| `reverser` (changement de cabine / inverseur) | `ctl_reverser` | V | `toggle` |
| `sand` (sablage) | `ctl_sand` | B | `button` |
| `headlights` (phares : auto / forcés) | `ctl_headlights` | H | `toggle` |
| `wiper` (essuie-glace : auto pluie / forcé) | `ctl_wiper` | E | `toggle` |
| `mirrors` (rétroviseurs / caméras : déployés / rabattus) | `ctl_mirrors` | N | `toggle` |
| `autopilot` (pilote automatique, mode libre) | `ctl_autopilot` | L | `button` |

Les commandes d'interface (caméra C, plan M/A, remise sur voie R, trafic T, aide F1) n'ont pas de nœud de cabine.

## `manifest.json`

```json
{
  "version": 1,
  "variants": {
    "angers__citadis_x05": {
      "dir": "angers_x05",
      "family": "citadis_x05",
      "length_m": 33.0, "width_m": 2.4,
      "modules": [9.24, 4.874, 4.772, 4.874, 9.24],
      "doors": 6,
      "lods": {
        "LOD0": {"file": "lod0.glb", "tris": 180000},
        "LOD1": {"file": "lod1.glb", "tris": 45000},
        "LOD2": {"file": "lod2.glb", "tris": 9000},
        "LOD3": {"file": "lod3.glb", "tris": 1200}
      },
      "mobile_tris": {"LOD0": 78000, "LOD1": 24000, "LOD2": 5800, "LOD3": 900},
      "cab": {"file": "cab.glb", "tris": 60000, "mobile_tris": 38000},
      "textures": {"pc_px": 4096, "mobile_px": 2048, "cab_px": 2048},
      "panto": {"module": 2, "lower_deg": -52.0, "upper_deg": 104.0},
      "wiper": {"axis": "z", "sweep_deg": 95.0, "period_s": 1.6},
      "mirror": {"fold_deg": 80.0},
      "sign": {"width_m": 1.2},
      "controls": {
        "ctl_notch": {"kind": "lever", "axis": "x", "range_deg": [-30.0, 30.0]},
        "ctl_emergency": {"kind": "button", "axis": "y", "travel_m": 0.012},
        "ctl_pantograph": {"kind": "toggle", "axis": "z", "on_deg": 35.0}
      },
      "screens": {"screen_speed": {"px": [256, 160]}, "screen_info": {"px": [320, 200]}},
      "sources": ["plans data/rolling_stock/plans/citadis_x05.json", "photos Commons …"],
      "license": "CC-BY-SA 4.0 (production du projet)"
    }
  }
}
```

- La **clé** de variante = `variant_id` de la livrée (`TramModel.livery_for` → `stock_entry.id`, ex.
  `angers__citadis_x05`, `nantes__citadis_x05_nantes`, `angers__citadis_302`).
- `doors` : nombre de portes **par côté** (plan). `modules` : longueurs **du rig** = plan mis à l'échelle de
  `length_m` (X05 Angers 33,0 m → 9,24 / 4,874 / 4,772 / 4,874 / 9,24 ; X05 Nantes 45,6 m et 302 Angers 32,4 m =
  plan tel quel) (somme = `length_m`, tolérance ±0,02 m par caisse) ; sinon repli.
- `tris` : comptés par le test sur les glb, doivent respecter `budgets.json → rolling_stock_lod`
  (PC LOD0 ≤ 250 k, cabine ≤ 80 k ; LOD1 ≤ 60 k ; LOD2 ≤ 12 k ; LOD3 ≤ 1,5 k). `mobile_tris` déclaratif
  (le profil Mobile utilise le même glb et monte d'un LOD si `mobile_tris` est absent et que le LOD dépasse).
- `controls` : paramètres d'animation par nœud ; absent → défaut du type (`lever` X ±30°, `button` 1 cm en -Z
  local, `toggle` 30° X). `axis` ∈ `x, y, z` (local).
- Champs inconnus ignorés ; `version` incrémentée en cas de rupture.

### Contrôles de production (reprise P2)

`python tools/models/stock/audit_stock.py --report build/stock-hd/audit.json` mesure les GLB,
vérifie leurs textures externes et leurs empreintes, compare les comptes déclarés aux triangles réels
et applique les budgets PC/Mobile. La cabine Mobile possède son pupitre `cab_desk_mobile.png`
(1024×512, dérivé généré du 2048×1024) ; `textures.mobile_cab_px = 1024` et
`textures.files.cab_mobile` décrivent ce fichier. Les originaux PC sont conservés.

La validation Godot contrôle les deux cabines, la chaîne `panto_base/lower/upper/head`, les indices
de portes continus et les longueurs déclarées avant mutation du rig. Le profil de contenu doit être
déterminé **avant** `TramModel.build_rig`, y compris sur Android avec renderer de repli.
En production, `check(..., active_profile_only=true)` valide uniquement les fichiers utilisés ; la
validation complète des deux profils est exécutée par défaut dans les tests et par l'audit CI.

## Comportement du code (pour information)

- Chargement paresseux par variante (`StockHD.load_variant`), cache partagé entre rames ; repli sur le modèle
  actuel si le manifeste, un glb ou un nœud requis manque.
- LOD : LOD0 < 25 m ou vue cabine, LOD1 < 80 m, LOD2 < 250 m, LOD3 au-delà (hystérésis 10 %). Mobile :
  **3 rames au plus en LOD0**, rames IA un cran plus bas. La cabine n'est instanciée que pour la rame du joueur.
- État : portes (côté quai réel), pantographe (`pantograph_up` : LAC/APS), essuie-glace (pluie de `WeatherState`),
  phares/feux arrière selon la cabine active, plafonniers nuit/tunnel, girouette = destination de la mission.
