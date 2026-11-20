# Angers — arrêt par arrêt et dépôt Raymond-Perron

Reconstruction stylisée du réseau d’Angers, relevé documentaire du **14 novembre 2026**.

**42 arrêts, 79 emprises de quai OSM, 78 abris / verrières, 44 bâtiments de voisinage et 54 éléments de site** sont décrits individuellement. Le dépôt reprend les deux empreintes IGN de ses bâtiments, les portails correspondant aux voies de service, la toiture ouverte et ses façades intérieures rouges, la verrière et son lanterneau ovale, l’administration et ses panneaux photovoltaïques, l’abri ovale, la clôture et le marquage de stationnement.

[Galerie complète : avant, après et orthophoto](index.html). Les vues du jeu sont des captures **Godot 4.6.3**, sans retouche de décor. Les vues verticales sont orthographiques, nord en haut, à 13 h 30 ; brouillard désactivé pour le contrôle. Les poses avant/après sont identiques. Quelques vues aériennes obliques complètent les vues verticales.

## Sources et précision

- **IGN BD ORTHO** : deux emprises de référence par arrêt (170 et 360 m). La date de prise de vue n’est pas fournie par le WMS ; le 14 novembre 2026 est la date de consultation.
- **Panoramax** : vues de rue géolocalisées, auteurs, dates et licences dans le [registre](../../tools/import/angers_station_references.json). Les vues postérieures à l’ouverture des lignes B/C sont privilégiées. Plusieurs vues servent à lire la forme du mobilier et les façades, pas à plaquer une photographie sur un bâtiment.
- **OpenStreetMap** : emprises physiques de quais et d’abris, conservées dans le repère propre à chaque ligne. Les doublons d’abris se recouvrant sont éliminés.
- **IGN BD TOPO** : empreintes et hauteurs des bâtiments. Les bâtiments personnalisés remplacent leur extrusion générique dans CityScene.
- [Charte municipale du mobilier](https://cpu.angers.fr/product/abri-tramway) : abri type de 8,40 m sur 2,54 m de haut, métal anthracite et parois vitrées.
- [CMR — verrières](https://www.cmrsa.fr/projet/auvents-des-stations-ralliement-et-les-gares-du-tramway-dangers) : Ralliement, Gares et pavillon de Saint-Gilles. Aux Gares, un auvent cartographié d’environ 19 m et un auvent de 40 m, posés à la hauteur du pont.
- [Dépôt — vues de juillet 2019, Édouard Paris](https://tramwaydemontpellier.net/2019/07/24/24-juillet-2019-a-angers-vues-aeriennes-du-centre-technique-des-transports-ctt-raymond-perron/) et [CAUE](https://www.caue-observatoire.fr/ouvrage/centre-technique-des-transports/).
- [Maison Bleue — PA49000016](https://pop.culture.gouv.fr/notice/merimee/PA49000016), et [place Molière](https://adila.fr/nos-projets/place-moliere/) pour les cercles de schiste rappelant le cirque-théâtre.

Les implantations cartographiques sont documentées ; les moulures, mosaïques, vitrages, végétaux et autres petits détails sont **des reconstructions stylisées**, pas un relevé architectural ou une photogrammétrie. Les façades voisines servent de repères visuels, sans prétendre reproduire chaque ouverture à l’identique. Les photos privées d’architecture servent uniquement de référence et ne sont pas distribuées.

**Limites documentaires :** Bascule dispose d’une photo de rue spécifique de 2012, complétée par deux vues aériennes et la charte commune du mobilier ; il manque une deuxième vue de rue spécifique vérifiée. Les deux vues spécifiques de Saint-Gilles datent de 2021. L’occupation des places du dépôt de 2019 n’est pas reproduite comme une situation actuelle. Les stations déplacées Saint-Serge et Molière utilisent leur implantation actuelle, et non leurs anciens quais.

## Choix techniques

- Quais dessinés sur leurs polygones OSM ; bandes tactiles du côté des rails, mobilier en dimensions métriques.
- Abri standard à toiture opaque anthracite ; verrières uniquement aux sites documentés.
- Sols piétons tracés individuellement et découpés contre les bâtiments, les chaussées et les voies. Triangulation contrainte pour ne pas créer de trous dans les surfaces concaves ni refermer la cour du dépôt.
- Verrières des Gares posées sur l’altimétrie des quais du pont, indépendamment du terrain SNCF inférieur.
- Revêtement minéral des voies de service à l’intérieur du périmètre du dépôt ; les parcours, aiguillages et contraintes de conduite restent issus du réseau physique.
- Conservation des voyageurs en attente, de l’éclairage du mobilier et des obstacles de caméra des bâtiments remplacés.
- Calcul de visibilité des tuiles depuis leur emprise, pour éviter un décor vide à faible rayon de LOD.
- Détails de façade limités à 190 m, volumes et toitures caractéristiques gardés plus loin ; culling indépendant du mobilier et matériaux partagés. Les données sont préchargées dès le choix de la ville.

## Reproduire

```sh
python -m pip install -r tools/import/requirements.txt
python tools/import/angers_station_models.py --fetch-aerials
# Affichage OpenGL disponible :
STATION_MODELS=0 STATION_SHOTS=res://docs/angers-stations/before godot --path . --audio-driver Dummy --rendering-driver opengl3 --resolution 1280x960 --script tools/qa/capture_angers_stations.gd
STATION_SHOTS=res://docs/angers-stations/after godot --path . --audio-driver Dummy --rendering-driver opengl3 --resolution 1280x960 --script tools/qa/capture_angers_stations.gd
STATION_OBLIQUE=1 STATION_FILTER=7,8,13,20,29,35,37,43 STATION_SHOTS=res://docs/angers-stations/oblique godot --path . --audio-driver Dummy --rendering-driver opengl3 --resolution 1280x960 --script tools/qa/capture_angers_stations.gd
python tools/qa/angers_station_gallery.py
```

Les sources de placement sont dans `data/station_models/angers_landmarks.source.json`. Le compilateur retrouve les empreintes d’abris dans le relevé OSM archivé, les quais du réseau physique et les emprises routières / bâties du TSC4. Les orthophotos téléchargées sont gardées dans `.cache/station-references`, hors du jeu.

## Contrôles

- `tests/test_station_models.py` : couverture exhaustive, sources par site, dimensions des deux verrières des Gares, intégrité de la toiture avec cour ouverte et géométrie finie.
- `tests/test_station_identities.gd` : intégration dans le moteur, 42 / 79 / 78 / 44 éléments, LOD sur les maillages, altimétrie des Gares, dépôt minéral, cache, mode mission et absence d’injection dans les autres villes.
- Galerie : comparaison visuelle de tous les arrêts et du dépôt avec les orthophotos, plus vues obliques des sites caractéristiques.
