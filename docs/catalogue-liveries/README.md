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
4. Régler caisse, face, portes, toiture, jupe et bandeau ; ajouter deux bandes et une inscription.
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
Les concepts courts/longs gardent la face du réseau choisi et leurs propres caisses, portes et LOD.
Ils ne sont pas des véhicules réels et leurs caractéristiques ne sont pas des données constructeur.

## Production et vérification

```sh
python tools/models/stock/build_stock.py
python tools/models/stock/export_livery_layouts.py
python tools/models/stock/audit_stock.py --report build/stock-hd/audit.json
python -m unittest discover -s tests -p test_stock_hd_assets.py
godot --headless --editor --path . --import
xvfb-run -a godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/test_family_fronts.gd
xvfb-run -a godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/test_livery_catalogue.gd
xvfb-run -a godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/test_livery_ui.gd
xvfb-run -a godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/audit/family_front_shots.gd -- build/family-fronts
```

Attendre la fin de l’import avant les tests et captures. Les dépendances de génération sont NumPy et Pillow.
L’audit binaire n’utilise que la bibliothèque standard. La CI HD teste les familles, les créations sauvegardées,
le chargement en conduite, les animations et les formats PC/Mobile ; elle archive les captures effectives.
La bibliothèque de couleurs est bornée à 100 entrées, les caches d’aperçu à huit palettes/atlas.
Les atlas personnalisés sont de 1024×512 maximum avec mipmaps ; aucun calcul de peinture par image de conduite.

Voir [VALIDATION.md](VALIDATION.md) pour les mesures et limites du lot, et [assets.csv](assets.csv) pour les sources.

## Captures Godot

- [Citadis : faces](captures/citadis-x05-faces.png)
- [Citadis : longueurs et livrées](captures/citadis-x05-types.png)
- [TFS : faces](captures/tfs-faces.png)
- [TFS : profils](captures/tfs-types.png)
- [Éditeur de livrée](captures/editor-custom.png)
- [Peinture chargée en conduite sur la fixture de test](captures/driving-custom-fixture.png)
