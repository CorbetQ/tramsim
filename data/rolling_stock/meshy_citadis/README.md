# Citadis — ensemble stylisé V2

Caisses reconstruites localement depuis l'étude photo et les contours des bases
Meshy ; sièges conservant leur géométrie Meshy. Aucun triangle des anciennes
caisses du jeu, aucun placage photographique. Le rig mathématique d'origine reste
l'autorité des animations et des points d'articulation.

Chaque fichier `*_body.glb` contient le jeu complet : `Module00…`, `Door000…`,
`PantoLower`, `PantoUpper`, `PantoHead`. Ces maillages remplacent tous ceux du rig,
en une opération validée avant mutation. Pas de coque historique ajoutée au-dessus.
Si un élément manque ou si les dimensions ne correspondent pas, toute la rame
utilise son ancien ensemble ; aucune substitution partielle.

Une surface par pièce : palette via `COLOR_0`, propriétés de matériau via `UV.x`,
aucune image embarquée. Unités métriques, -Z vers l'avant dans Godot. LOD activés.
Conversion linéaire / sRGB adaptée au renderer dans le shader commun.

Les trois variantes sont activées par défaut sur cette branche.
`TRAMSIM_CITADIS_LEGACY=1` permet la comparaison avec l'ensemble historique complet.
Les intérieurs sont générés à l'embarquement, avec aménagement estimé depuis les
photos et pièces regroupées en MultiMesh. Autres variantes et cartes inchangées.

[Galerie, commandes et limites](../../../docs/rolling-stock-meshy/README.md)
· [Provenance V2](../meshy_sources/reconstruction.json)
· [Licences et attributions](../meshy_sources/CREDITS.md).

Reconstruction des caisses sans requête Meshy :

```sh
blender -b --python tools/rolling_stock/retopologize_citadis.py
godot --headless --editor --path . --import
python tools/rolling_stock/audit_citadis.py --write-manifest
```

`contour_study.json` permet cette reconstruction hors ligne même sans les GLB bruts
Meshy. Le rendu n'est pas certifié conforme à des plans constructeur. Ne pas
présenter la reconstruction locale V2 comme une nouvelle génération Meshy.
