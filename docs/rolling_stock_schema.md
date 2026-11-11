# Plans de rames — schéma (contrat entre recherche, ingénierie et modélisation)

Fichiers :
- `data/rolling_stock/research.json` — faits sourcés (agent recherche).
- `data/rolling_stock/plans/<famille>.json` — plan de modélisation (agent ingénieur), un par famille/variante.
- `data/rolling_stock/liveries.json` — livrées par réseau / ligne (agent ingénieur) ; seule source des livrées (`data/liveries.json` supprimé).
- Code : `src/rendering/tram_model.gd` (générateur), animations dans le même fichier (agent modélisateur).

Repère : x latéral (droite +), y vertical (0 = dessus du rail), z longitudinal, **-z = avant** de la rame. Unités : mètres, degrés, secondes.

## research.json
```json
{"families": {"citadis_302": {
   "name": "Alstom Citadis 302", "manufacturer": "Alstom", "networks": ["angers", "lyon"],
   "length_m": 32.4, "width_m": 2.4, "height_m": 3.27, "floor_height_m": 0.35, "max_speed_kmh": 70,
   "mass_t": 40.0, "power_kw": 720, "capacity": 200,
   "modules": [{"kind": "cab", "length_m": 7.9}, {"kind": "suspended", "length_m": 5.0}],
   "doors_per_side": 4, "door_type": "louvoyante|coulissante|pivotante", "door_width_m": 1.3,
   "front": "description courte des traits distinctifs (forme du nez, pare-brise, feux, jupe)",
   "references": [{"url": "...", "local": "chemin image", "licence": "CC BY-SA 4.0", "author": "..."}],
   "sources": ["url fiche technique"], "estimated": ["mass_t"]}},
 "liveries": {"angers": {"family": "citadis_302", "description": "...", "colors": {"base": "#...", "...": "#..."}, "sources": ["..."]}}}
```

## plans/<famille>.json
```json
{"id": "citadis_302", "name": "Alstom Citadis 302", "length_m": 32.4, "width_m": 2.4, "height_m": 3.27,
 "floor_m": 0.35,
 "body": {"skirt_top_m": 0.45, "window_bottom_m": 1.05, "window_top_m": 2.45, "cant_m": 2.85,
          "roof_shoulder_m": 0.28, "tumblehome_m": 0.0},
 "modules": [{"kind": "cab|middle|suspended", "length_m": 7.9, "bogie": true,
              "doors": [{"z_m": 3.2, "width_m": 1.3, "leaves": 2}],
              "windows": [{"z0_m": 0.5, "z1_m": 2.6}],
              "roof": [{"type": "pantograph|hvac|box|fairing", "z_m": 3.0, "size": [1.4, 0.3, 2.0]}]}],
 "front": {"length_m": 1.6,
           "plan": [[0.0, 1.0], [0.5, 0.97], [1.0, 0.78]],
           "side": [[0.30, 0.0], [1.0, 0.15], [2.6, 0.55], [3.27, 0.9]],
           "windshield": {"bottom_m": 1.15, "top_m": 2.75, "wrap": 0.3},
           "headlights": {"shape": "round|strip|rect", "y_m": 0.85, "x_m": 0.85, "w_m": 0.35, "h_m": 0.12},
           "destination": {"y_m": 2.85, "w_m": 1.4, "h_m": 0.22},
           "bumper_m": 0.05},
 "door_anim": {"type": "plug|sliding|swing", "open_s": 2.5, "travel_m": 0.65, "out_m": 0.06},
 "pantograph": {"down_m": 0.25, "up_m": 1.6, "raise_s": 4.0},
 "sources": ["research.json#citadis_302"], "estimated": ["front.plan"]}
```
- `front.plan` : demi-largeur relative (0..1) en fonction de l'avancée relative du nez (0 = début du nez, 1 = pointe), vue de dessus.
- `front.side` : silhouette latérale `[y_m, recul relatif 0..1]` : recul de la face avant à la hauteur y (0 = pointe la plus avancée).

## liveries.json
```json
{"angers": {"family": "citadis_302", "name": "Citadis 302 Irigo", "base": "#f6f6f4", "window": "#1b232b",
            "door": "#f6f6f4", "front": "#1b232b", "roof": "#c9cdd0", "skirt": "#30353a",
            "elements": [{"type": "stripes", "colors": ["#e2231a", "#f18a00"], "y": [0.45, 1.05], "zone": "sides+front"},
                         {"type": "diagonal|band|gradient|front_mask|panel", "colors": ["#..."], "y": [lo, hi], "z": [lo, hi], "angle_deg": 30, "zone": "sides|front|doors"}],
            "lines": {"b": {"...": "surcharges par ligne"}},
            "approximation": "ce qui est approché"}}
```
Clés de réseau : identifiants de `data/sources/gtfs_catalogue.json` (`angers`, `idf`…) ; lignes : nom court en minuscules (`t3a`, `1`, `tt`).
