# Citadis Meshy — lot expérimental

Trois caisses, trois kits de sièges, unités métriques. Origines et transformations
dans `../meshy_sources/`, crédits et licences dans `../meshy_sources/CREDITS.md`.

**Caisses désactivées par défaut** : surfaces et livrées générées encore irrégulières,
articulations photographiques ne coïncidant pas toujours avec le découpage mécanique,
arrières inventés par l'IA. Ce ne sont pas des modèles constructeur validés.

Les sièges sont intégrés aux intérieurs spécifiques via `CitadisInterior`, avec
matériaux propres remplaçant l'éclairage bruité des textures générées. Les deux
modèles angevins partagent des caractéristiques visuelles observées ; les petites
différences de maillage entre générations ne constituent pas des différences
techniques établies entre séries.

Le rig historique reste l'autorité des animations, les plans historiques restent
l'autorité des positions de portes. Leur exactitude photographique doit encore
être affinée ; ce lot ne les présente pas comme de nouveaux relevés.

Reconstruction hors ligne :

```sh
blender -b --python tools/rolling_stock/prepare_meshy_citadis.py
godot --headless --editor --path . --import
python tools/rolling_stock/audit_citadis.py --write-manifest
```

Les GLB bruts des tâches enregistrées doivent être placés au préalable dans
`meshy_output/<composant>/model.glb`. La commande Blender ne contacte pas Meshy.
Les `.glb.import` conservent les LOD automatiques et les textures embarquées
compressées Basis Universal. Ne pas versionner les caches Godot ni les URL signées.
