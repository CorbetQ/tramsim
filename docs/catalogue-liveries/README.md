# Catalogue par famille et éditeur de livrée

Le catalogue utilise maintenant **famille → type → livrée et face d’origine → peinture**.
La famille de présentation est distincte du plan géométrique et du profil audio : aucun
identifiant historique de matériel ou de sauvegarde n’est remplacé par un identifiant de groupe.
Les 302/402 et leurs faces Tours/Reims sont regroupés dans X02 ; les 205/305/405 dans X05.
Les 403 sont dans X03. Flexity Link est séparé d’Avanto malgré leur ancien maillage donneur partagé.

## Utilisation

1. Ouvrir le catalogue depuis l’accueil, choisir une famille et un type.
2. Choisir la livrée d’origine : cette sélection choisit **aussi la vraie forme de cabine** de cette variante.
3. Conserver la peinture d’origine ou ouvrir « Créer une livrée ».
4. Choisir toute la rame, un rôle ou une caisse précise ; régler couleurs, deux bandes et inscription.
5. Enregistrer sous un nom, modifier ou enregistrer une copie. La suppression demande deux actions.
6. Choisir un réseau compatible et conduire en mode libre.

L’éditeur est un outil de peinture, pas un sculpteur de nez. Un changement de couleur ne transforme
pas une face Naolib en face Irigo. Les vues de face, de profil et de trois quarts montrent le modèle réel du jeu.
Les couleurs précises s’entrent en `#RRGGBB`. Les commandes restent dans le formulaire tactile défilant.
L’import d’images/décalcomanies et l’échange de livrées entre joueurs ne font pas partie de ce lot.

Les peintures nommées sont dans `user://liveries.json` : écriture atomique, copie de secours et
protection des fichiers corrompus ou de version future via SaveGame. Les créations ne changent pas
les originaux. La reprise de partie contient une copie de la peinture, utilisable même après suppression
de l’entrée dans la bibliothèque. Les anciennes sauvegardes sans cette extension restent utilisables.

L’APS, le guidage et la physique restent ceux du matériel. Les concepts ne sont pas ajoutés aux flottes
réelles de mission. Choisir une ville ou une peinture ne confère pas l’APS à une rame incompatible.

## Exemples demandés : réel et fictif

| Famille/type | Irigo / TAN | Naolib / RATP |
|---|---|---|
| Citadis 205 | Irigo, concept fictif, 24 m / 3 caisses | Naolib, concept fictif, 24 m / 3 caisses |
| Citadis 305 | Irigo réel, 33 m / 5 caisses | Naolib, concept fictif, 33 m / 5 caisses |
| Citadis 405 | Irigo, concept fictif, 44,5 m / 7 caisses | Naolib réel, 45,6 m / 7 caisses |
| TFS 1 | TAN réel, 36,5 m | RATP, concept fictif, 36,5 m |
| TFS 2 | TAN, concept fictif, 29,4 m | RATP réel, ligne T1, 29,4 m |

« T1 » désigne une ligne de la RATP ; sa rame est de génération **TFS 2**.
Bibus conserve les 302 et 305 documentés par le registre : le 205 n’est pas artificiellement attribué à Brest.

## Faces spécifiques

Les Citadis Irigo et Naolib HD ont des profils de silhouette séparés dans
`data/rolling_stock/front_profiles.json`. La reconstruction utilise des photographies déjà référencées
dans le dépôt, sans plaquer les photos sur les modèles. Irigo conserve ses optiques rondes dans le bouclier
blanc ; Naolib son masque large, ses joues blanches, son panneau alvéolé à gradient de tailles, sa couronne
incurvée et son essuie-glace asymétrique. Les limites du vitrage sont courbées dans la géométrie.
Le vitrage extérieur est teinté ; la cabine garde son réglage de transparence spécifique.

Les générations TFS ont des paramètres de nez, de vitrage, d’optiques et d’essuie-glaces distincts dans
`StockGeometry`. La troisième optique haute et les logements ovales du TFS 2 sont modélisés séparément.
Les autres matériels conservent leurs adaptations de cabine existantes : ce lot ne prétend pas avoir
remodélisé chaque rame française depuis des plans industriels.

Les formes sont des relevés visuels **estimés**, pas des géométries certifiées par le constructeur.
Les concepts courts/longs gardent la face du réseau choisi et assemblent les mêmes prototypes de caisse et LOD.
Ils ne sont pas des véhicules réels et leurs caractéristiques ne sont pas des données constructeur.

## Pièces indépendantes et compositions paramétriques

`data/rolling_stock/parts_manifest.json` (schéma 2) est l’index unique des kits,
paramètres de variantes et jeux de textures. Un fichier `tram_parts/compositions/<design>.json`
décrit chaque design. Il existe **un seul kit `angers_x05`, `angers_x02` et `nantes_x05`**,
sans répertoire géométrique `angers_205`, `angers_305` ou `angers_405`.

```text
tram_parts/
  compositions/angers_x05.json       # prototypes, schéma d’assemblage et presets
  extremites/angers_x05/end_a_*.glb   # deux extrémités spécifiques A et B
  extremites/angers_x05/end_b_*.glb
  motrices/angers_x05/powered_*.glb
  suspendues/angers_x05/suspended_*.glb
  equipements/angers_x05/pantograph_*.glb
tram_livery/
  livery/<livree>/<role>_<LOD>.png    # UV normalisées par caisse, réutilisées selon la taille
  materials/<design>/                # matériel, palettes sans perte, normales/ORM
  interior/<reseau>/<design>/        # tissus, sol, cabine quand disponibles
  lights/                           # catégorie réservée : les feux actuels sont géométriques/émissifs
```

Les kits natifs utilisent des scènes Godot `.scn` indépendantes, les trois kits HD des GLB.
Le moteur adapte les longueurs des caisses à la composition choisie en conservant les zones de nez,
portes et bogies autant que possible. L’adaptation est calculée au chargement puis mise en cache,
pas à chaque image. Aucune géométrie 205/305/405 n’est exportée séparément.
Le pantographe HD est monté séparément : une rame courte ne reçoit plus une caisse motrice
sans portes à la place d’une suspendue uniquement pour récupérer son pantographe.

Les modèles sources HD complets des **trois matériels réels** sont conservés comme sources
d’auteur et repli. Les quatre anciens exports complets de concepts et les exports de caisses
par identifiant de variante ont été supprimés après validation des kits. Les identifiants historiques
de variantes restent présents pour le catalogue et les sauvegardes ; ce ne sont pas des noms de modèles.

La peinture personnalisée utilise un atlas par rôle et des surcharges facultatives par caisse.
Une peinture X05 peut être réutilisée en 205/305/405 sans changer la face, l’APS ou les propriétés
techniques du matériel choisi. Les paramètres `end_a`, `end_b`, `powered`, `suspended`
sont indépendants de la longueur. Les surcharges `caisse_N` restent volontairement propres à un emplacement.

## Portes : correction depuis les références

| Matériel réel | Portes par face, dans l’ordre des caisses | Particularité |
|---|---|---|
| Irigo 302 | 1 – 2 – 0 – 2 – 1 | porte simple de 800 mm aux extrémités |
| Irigo 305 | 1 – 2 – 0 – 2 – 1 | porte double de 1 300 mm aux extrémités |
| Naolib 405 | 2 – 0 – 2 – 0 – 2 – 0 – 2 | caisses porteuses de cabine, trois motrices centrales |

Sur les Irigo, la porte de chaque extrémité est vers la cabine ; les suspendues ont deux portes
et la motrice centrale aucune. Les deux côtés utilisent la même distribution, avec animation
indépendante côté quai. Nantes n’hérite pas de la règle Irigo : ses deux longues extrémités
ont chacune deux portes par face. Les concepts appliquent ces prototypes selon leur assemblage fictif.
Les longueurs intermédiaires de Nantes sont estimées pour respecter 45,6 m au total, pas certifiées.

Références : [dossier de presse Angers](https://presse.angers.fr/private/uploads/piecesjointes/dossier-de-presse-tramway.pdf),
[photographies Irigo et crédits](../rolling-stock-rebuild/PHOTO-CREDITS.md),
[présentation documentée du 405 Nantes](https://tramwaydemontpellier.net/2024/07/11/11-juillet-2024-nantes-le-point-sur-la-mise-en-service-commercial-des-nouvelles-rames-citadis-x05-alstom/),
[référence frontale Naolib](../rolling-stock-meshy/reference-nantes405-face.jpg).
Les autres modèles gardent leurs spécificités existantes ; leur exactitude exhaustive n’est pas revendiquée.
Les trois anciennes coques de la vue passager ont également été régénérées à partir des plans corrigés
avec `blender -b --python tools/rolling_stock/retopologize_citadis.py`, puis auditées avec
`python tools/rolling_stock/audit_citadis.py --write-manifest`. Cette reconstruction locale réutilise
les contours déjà enregistrés ; aucun nouveau travail Meshy payant. Le chargeur vérifie désormais
les longueurs de chaque caisse, en plus de la longueur totale, avant de remplacer une coque.

## Production et vérification

```sh
python tools/models/stock/build_stock.py
python tools/models/stock/export_livery_layouts.py
python tools/models/stock/build_kits.py
godot --headless --path . -s tools/models/export_native_parts.gd
python tools/models/stock/bake_native_liveries.py
godot --headless --editor --path . --import
python tools/models/stock/audit_stock.py --report build/stock-hd/audit.json
python tools/models/stock/audit_parts.py --report build/stock-hd/parts-audit.json
python -m unittest discover -s tests -p test_stock_hd_assets.py
python -m unittest discover -s tests -p test_tram_parts_assets.py
xvfb-run -a godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/test_tram_parts.gd
xvfb-run -a godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/test_family_fronts.gd
xvfb-run -a godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/test_livery_catalogue.gd
xvfb-run -a godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/test_livery_ui.gd
xvfb-run -a godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/audit/family_front_shots.gd -- build/family-fronts review
```

Attendre la fin de chaque génération puis de l’import avant les tests et captures.
L’exporteur natif désactive les habillages pendant sa génération pour ne pas reboucler sur ses sorties.
Une copie de travail déjà importée est nécessaire pour les ressources Godot communes.
Les dépendances de génération sont NumPy, Pillow et Godot 4.6.3 ; l’audit binaire utilise seulement
la bibliothèque standard. Les banques nécessaires au jeu sont versionnées : le joueur n’a rien à générer.

Sur un poste/runner de validation PC, `python tools/models/stock/prepare_pc_imports.py` évite
la compression CPU ETC2 inutile grâce à un `override.cfg` local. Ne pas utiliser cet override pour
l’export Android ; `project.godot` conserve les paramètres Android. Ce script explicite modifie les
métadonnées locales de cache `.import`, jamais les images ou le code du jeu.

La CI HD exécute les audits, tests de rendu, catalogue, créations sauvegardées et formats PC/Mobile,
puis archive ses captures. La génération de modèles n’est pas relancée à chaque commit.
Les créations sont bornées à 100 entrées, les atlas personnalisés à 1024×512 avec mipmaps.

Voir [VALIDATION.md](VALIDATION.md) pour les mesures et limites du lot et [assets.csv](assets.csv) pour les sources.

## Captures Godot

- [Six configurations X05 corrigées, trois quarts](captures/citadis-x05-review.png)
- [Citadis : faces](captures/citadis-x05-faces.png)
- [TFS : faces](captures/tfs-faces.png)
- [TFS : profils](captures/tfs-types.png)
- [Éditeur de livrée](captures/editor-custom.png)
- [Peinture chargée en conduite sur la fixture de test](captures/driving-custom-fixture.png)

## Contrôle de jonction du toit

Après un changement de nez ou de toiture, exécuter `godot --headless --path . -s tests/test_roof_junction.gd`.
Les carénages hauts doivent reposer sur le pavillon et les plans de cabine doivent être découpés selon
le contour du nez. Captures rapprochées reproductibles :
`godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/audit/roof_junction_shots.gd -- build/roof-review`.
Voir la comparaison [avant](captures/roof-before-pc-front.png) / [après](captures/roof-after-pc-front.png).
