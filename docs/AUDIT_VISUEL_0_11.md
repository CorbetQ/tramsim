# Audit visuel 0.11 (sur la base 0.10.0)

Audit des 28 villes, sur la ligne tram la plus longue de chaque réseau. Quatre points sont choisis automatiquement par ville : centre dense, franchissement, pente ou trémie, terminus. Chaque point a une vue 3e personne (13 h 30), une vue cabine et une vue aérienne verticale de 250 m au sol, sans brouillard. Le centre dense a aussi une vue de nuit (22 h 30). Au total : **364 captures** OpenGL 1280×720 sous xvfb (llvmpipe). Chaque vue aérienne est comparée à l'orthophoto IGN de la même emprise (WMTS, zoom 18).

Outils (`tests/audit/`) :
- `audit_shots.gd` et `run_audit.sh` : captures et choix des points ;
- `planches.py` : planches-contacts et orthophotos ;
- `refs_commons.py` : photos libres géolocalisées.

Les journaux `AUDIT|…` donnent les coordonnées, l'altitude du rail et du sol, les primitives et les appels de rendu.

## 1. Synthèse

L'impression « baveuse » n'a pas une cause unique. Trois défauts systémiques se cumulent :

1. **La chaîne de couleur du décor est faussée.** Sans brouillard, l'enrobé sort en noir pur (0,0,0) et la pelouse en vert saturé (7,161,0). Le brouillard est réglé à 0,00065 mais il est fortement amplifié par le brouillard de hauteur, calé sur une altitude absolue. C'est lui qui remonte ces couleurs en voile gris-bleu uniforme. Résultat : un contraste plat et des teintes délavées au loin, avec des noirs bouchés dès que le voile s'amincit. En aérien, cela donne des routes noires et des toits bleu marine ou lavande.
2. **La voirie est faite de rubans indépendants.** Il n'y a ni polygone de carrefour ni trottoir continu. Les onglets s'étendent jusqu'à 2× la largeur. On voit donc des éclats d'enrobé en éventail aux carrefours, des bords en dents de scie et des rubans superposés.
3. **Le sol est grossier.** La grille de relief est de 10 m, la pelouse issue de l'orthophoto est en cellules de 4 m, et le décalage anti-z-fighting ne fonctionne qu'autour de l'altitude 0. Conséquences : pelouses en escalier, terrain déchiré aux rampes de pont et z-fighting des couches de sol dans la plupart des villes.

Le relief est peu lisible : rayon de décor de 650 m, sans horizon lointain (pas d'Alpes à Grenoble, pas de collines à Saint-Étienne). Les matériaux procéduraux existent mais s'estompent au-delà de ~10 m. Il reste donc de grands aplats beiges, gris ou verts.

## 2. Défauts (classés par gravité, puis fréquence)

Les preuves sont nommées `<ville>_<point>_<vue>.png` dans le dossier de captures (liste en fin de document).

| # | Gravité | Catégorie | Défaut | Fréquence / villes | Preuve | Cause probable (code) | Piste |
|---|---|---|---|---|---|---|---|
| 1 | Bloquant | Éclairage, couleur | Couleurs du décor écrasées : enrobé noir pur, herbe sursaturée (B=0), toits marine ou lavande. Seul le brouillard masque le défaut. | 28/28 | `angers_dense_ext` comparé avec `AUDIT_FOG=0` ; tous les `*_aer` | `toon_building.gdshader` `to_linear` (`color_gamma` 2.2 et `saturation` 1.16) sur des couleurs de sommet que `toon.gdshader` dit déjà linéaires en Compatibility (rames : `color_gamma` 1.0). Il s'y ajoute `day_night.gd` : `adjustment_contrast` 1.12, `saturation` 1.10, glow de niveaux 1 à 4 et `fog_height` 30 en absolu. | Une seule conversion sRGB vers linéaire, palette recalibrée sur photos, contraste et saturation à 1.0, brouillard relatif au sol (ou à `alt0`), glow réduit. |
| 2 | Bloquant | Caméra | La caméra 3e personne est collée à un mur, dans la rame ou dans un houppier. | 15 vues sur 112, dont 9 centres denses : Avignon, Bordeaux, Brest, Caen, Grenoble, Lyon, Orléans, Toulouse, Valenciennes, Saint-Étienne, Tours, Marseille, Clermont, Lille, Rouen | `bordeaux_dense_ext`, `brest_dense_ext`, `saintetienne_pente_ext`, `grenoble_dense_ext` | `city_scene.gd` `avoid_camera` : boîtes alignées sur les axes (`_camera_boxes`) très surdimensionnées pour les bâtiments obliques, recul à 2 m. Les houppiers et la rame ne sont pas pris en compte. | Lancer de rayon sur les murs réels (polygones), rotation de l'orbite plutôt que rapprochement, rame et houppiers en obstacles, distance minimale de 6 m. |
| 3 | Bloquant | Eau | Plan d'eau au-dessus de la voie ou d'une chaussée. | Mulhouse (pont), Strasbourg (pont), Dijon (pont), Nice (trémie) | `mulhouse_pont_cab`, `strasbourg_pont_ext`, `dijon_pont_cab`, `nice_pente_cab` | `_water_level` : un seul niveau par polygone et repli « berge la plus basse **+1,2 m** ». Les polygones BD TOPO couverts ou en souterrain ne sont pas exclus. | Niveau sous la berge (−0,5 m), découpe sous les tabliers et dans les tranchées, polygones « eau couverte » ignorés. |
| 4 | Bloquant | Ouvrages | Voie sous ou à travers un tablier routier : piles devant la cabine, plafond. Tunnel sans tube : caméra sous le terrain, vue inversée. | Rouen (pont Jeanne-d'Arc), Le Havre (trémie), Aubagne (tablier 31 m), Lille (trémie : dalle opaque) | `rouen_pont_cab`, `lehavre_pente_cab`, `aubagne_pont_cab`, `lille_pente_ext` | `_deck` (piles à ±hw/2 sur les tabliers larges) et `_decks` BD TOPO non rapprochés du profil `y` de la ligne. `line_view.gd` `_structures` : portails et ouvertures pour les trémies longues. | Fusionner tablier rail et route quand la ligne emprunte le pont. Supprimer les piles dans le gabarit. Contrôler automatiquement le dégagement de la rame (test de gabarit sur 3 m au-dessus du rail). |
| 5 | Majeur | Voirie | Éclats d'enrobé en éventail aux carrefours, rubans superposés, bords en dents de scie, trottoirs coupés en segments de 2,5 m. | Toutes les villes ; très visible à Valenciennes, Clermont, Nantes, Caen | `valenciennes_pont_ext`, `clermont_dense_ext`, `caen_pont_cab` ; `rev/details.png` | `_ribbon` (onglet jusqu'à 2×), `_line` (un ruban par polyligne, sans jonction), `_street_edges` (trottoir en tronçons, `_crossroad`). | Refaire la voirie en polygones fusionnés (voir §4). |
| 6 | Majeur | Relief, sol | Terrain déchiré ou en marches autour des rampes de pont et des portails. Talus verticaux le long de la voie. | Nantes, Lille, Dijon, Bordeaux (le viaduc de 923 m n'est pas lisible) | `nantes_pont_ext`, `lille_pont_cab`, `dijon_pente_ext` | `_terrain_mesh` (pas de 10 m, `TSTEP`), `_bridge_approach`, `_portal_cut` (pas de 2,5 m seulement autour des portails) | Terrain continu drapé, en contraintes (§4). |
| 7 | Majeur | Sol | Pelouses en escalier (cellules de 4 m), patchwork vert fluo et beige. | 28/28 ; très visible au Mans, à Angers et Besançon | `angers_pente_ext`, `lemans_pente_cab` | `_build_tile` : quads `runs` de 4 m (`lawn`) | Masque de végétation lissé (contours vectorisés, ou texture de masque filtrée bilinéairement) et transition douce. |
| 8 | Majeur | Z-fighting | Bandes claires et sombres sur la plateforme et les couches de sol hors altitude 0. | Les villes dont le sol n'est pas à `y≈0` (Angers −17 m, etc.) | `lille_pont_cab` (bandes) | `cel.gdshaderinc` `cel_layer_clip` : `y = (model*vtx).y` est l'altitude absolue, donc pas de décalage hors de 0 à 2,5 m. Les couches ne sont séparées que de 3,5 à 7 cm. | Passer la hauteur au-dessus du terrain (attribut `CUSTOM0` ou UV2.y) ou utiliser une vraie priorité de rendu par couche. |
| 9 | Majeur | Eau | Eau très claire, sans berge ni profondeur. Reflet spéculaire en seuil dur qui sature tout le plan en blanc face au soleil. | 15 vues aériennes avec eau (14 villes), et en vue rasante à Orléans et Tours | `angers_pont_aer`, `tours_pont_ext`, `orleans_pont_ext` | `water.gdshader` `light()` : `smoothstep(0.975,0.98,nh)` sur une normale facettée ; couleurs `deep` et `shallow` claires | Spéculaire borné (GGX ou Blinn plafonné), couleur selon la profondeur (MNT), berges et enrochements. |
| 10 | Majeur | Végétation | Arbres plantés dans l'eau (Garonne, Loire, Maine, Doubs). | Toulouse, Tours, Orléans, Angers, Besançon | `toulouse_pont_ext`, `tours_pont_aer` | `_build_tile` : `otrees` et `runs` (orthophoto) placés sans masque `P_WATER` | Filtrer les houppiers et l'herbe par les polygones d'eau et de voirie. |
| 11 | Majeur | Relief, ciel | Pas d'horizon lointain : la ville finit à ~650 m. Relief régional invisible (Grenoble, Saint-Étienne, Clermont, Brest, Nice). | 28/28 | `grenoble_pont_ext`, `saintetienne_pont_ext` | `CityScene.radius = 650`, terrain limité aux tuiles de décor | Anneau de relief lointain à faible résolution (MNT à 25–75 m) et silhouette de montagnes en carte de ciel. |
| 12 | Majeur | Écart au réel | Sol beige uniforme là où l'orthophoto montre enrobé gris, voitures, cours et parkings. Densité de bâti et de mobilier bien inférieure. | 28/28 | colonnes « aérien » et « ortho » de toutes les planches | Couleur `ground` de `city_styles.json` appliquée à tout le non-classé | Classifier le sol (enrobé, parking, cour, terre) à partir de l'orthophoto. Textures d'enrobé et marquages de stationnement. |
| 13 | Majeur | Textures | Aplats « simplistes » : grain d'enrobé et pierre effacés au-delà de ~10 m (`grain` estompé par `fwidth`), façades répétitives à grandes fenêtres. | 28/28 | `besancon_dense_ext`, `mulhouse_pente_ext` ; `det_angers.png` | `toon_building.gdshader` : `grain()` (estompé de 0,2 à 0,8 px), `bay_w` et `floor_h` uniformes | Détails macro stables (variation d'albédo à 2–10 m, usure, flaques, raccords) plutôt que micro-grain. Atlas de façades par époque et région. |
| 14 | Mineur | Textures | Dallage : hachage par carreau non estompé, d'où du moiré à distance moyenne. | Trottoirs, places | `marseille_pont_cab`, `valenciennes_pont_ext` | Branche 0,29 : `hash(floor(tile))` sans fondu | Fondu vers la teinte moyenne selon `fwidth`. |
| 15 | Mineur | Codage des matériaux | Matériau codé dans `COLOR.a` (fenêtres de 0,01) : fragile en cas de compression ou d'interpolation. | — | — | `toon_building.gdshader` | Identifiant de matériau dans `CUSTOM0` ou des surfaces séparées. |
| 16 | Mineur | Bâtiments | Toits plats ou uniformes. Ardoise `SLATE` rendue lavande. Pas de balcons ni de corniches visibles au-delà de 30 m. Rez-de-chaussée commerciaux rares. | Brest, Nantes, Angers, Le Mans | `brest_dense_aer`, `nantes_dense_aer` | `SLATE` `#4c5562` combiné au défaut n° 1 ; `_building` | Palette des toits recalée sur l'orthophoto. LOD de façade. |
| 17 | Mineur | Nuit | Fenêtres en grands carrés uniformes et très lumineux. Chaussée noire sans halo de lampadaire au sol. Rames bleu saturé. | 28/28 | `besancon_dense_nuit`, `marseille_dense_nuit` | `toon_building` `em_near` et `em_far` ; pas de décalques de lumière au sol | Halos projetés (décalques additifs), variété d'intensité et de rideaux, tonalité plus fine. |
| 18 | Mineur | Repères | Étiquettes 3D de monuments flottant à 34 m dans le ciel. | Angers, Dijon, Toulouse, Lille | `angers_pente_ext`, `dijon_term_cab` | `_build_tile` : `Label3D` à `34.0 + sol` | Masquer en vue de conduite, ou placer sur le monument. |
| 19 | Mineur | Voies, quais | Plateforme en aplat gris, rails noyés sans pavés ni joints. Quais minimalistes. Totem jaune ou objet au premier plan en cabine (Besançon : panneau noir). | Nombreuses villes | `besancon_term_cab`, `angers_term_ext` | `line_view.gd` `_platform`, `_station` | Modèles de quai régionaux (abri, mobilier, bande podotactile) ; contrôle du gabarit de la caméra cabine. |
| 20 | Mineur | Mobilier | Pas de passages piétons, feux, panneaux, voitures en stationnement ni potelets réalistes (comparaison photos). | 28/28 | `rev/refs4.jpg` | Pas de données ou de génération correspondantes | Génération depuis les nœuds OSM (`crossing`, `traffic_signals`) et les bandes de stationnement. |
| 21 | Mineur | Performance | Primitives par image (ombres comprises) : médiane 1,1–1,2 M, maximum 4,1 M (Bordeaux, aérien) et 3 M (Bordeaux, 3e personne). Appels de rendu : médiane 342 en 3e personne, maximum 538. | — | `audit_points.txt` (`prims=`, `draws=`) | Tuiles fusionnées mais très denses (sous-découpe à 10 m, 4 cascades d'ombre) | LOD par tuile et cascades réduites. Mesure sur appareil réel nécessaire (llvmpipe ne donne pas d'image par seconde utile). |

## 3. Comparaison au réel

- **Orthophoto (28 villes, 112 emprises).** Le géoréférencement est bon : tracés, ponts et carrefours se superposent. Les écarts sont des écarts de matière :
  - sol beige au lieu de gris ;
  - enrobé noir au lieu de gris moyen ;
  - toits marine ou lavande au lieu d'ardoise gris foncé, sauf dans le Sud (tuiles orangées correctes à Marseille, Nice, Toulouse) ;
  - végétation en pastilles vert fluo au lieu de canopées sombres continues (Le Mans, Strasbourg) ;
  - eau blanche au lieu de verte ou brune ;
  - aucune voiture ni marquage au sol ;
  - largeur de voirie cohérente, mais grands vides là où l'orthophoto montre cours, parkings et jardins.
- **Niveau rue.** Street View n'a pas été utilisé (conditions d'utilisation, clé). Mapillary est bloqué par le proxy et demande un jeton. Des photos Wikimedia Commons géolocalisées (à moins de 400 m du point dense) ont été récupérées par `refs_commons.py`. L'API limite fortement le débit (HTTP 429) : seulement **7 villes sur 28** obtenues (Angers, Aubagne, Besançon, Bordeaux, Brest, Clermont, Dijon), détaillées dans `refs_commons/attributions.json` (titre, distance, lien ; auteur et licence sur la page Commons). Les 21 autres villes n’ont pas pu être comparées au niveau rue. Sur Angers, Brest, Clermont et Dijon (`rev/refs4.jpg`), le réel montre :
  - un enrobé sombre contrasté ;
  - des passages piétons, feux, potelets et panneaux ;
  - des pierres régionales (andésite sombre à Clermont) ;
  - une plateforme en dalles avec bande podotactile (Dijon).

  Le jeu montre au contraire une palette pâle et uniforme, des pelouses fluo et aucun mobilier.
- **Photos de rames** (`refs/*.jpg`, `research.json`) : les livrées restent le point fort, hors des ombres et de la nuit bleutée. Elles n'ont pas été recomparées ici.
- **Non comparé :** intérieurs de stations souterraines (Nice, Rouen) ; relief lointain (aucune référence panoramique) ; nuit réelle.

## 4. Plan de refonte priorisé

**P0 – Correctifs rapides (sans remodélisation)**
1. Chaîne de couleur :
   - une seule linéarisation des couleurs de sommet du décor ;
   - contraste et saturation de l'environnement à 1.0, glow limité au ciel et aux lumières ;
   - brouillard de hauteur relatif au sol ;
   - recalibrer les palettes (`city_styles.json`, `_line`, `SLATE`) sur des échantillons d'orthophoto et de photos.
2. Caméra : obstacles réels (polygones, houppiers, rame), rotation de l'orbite, test automatique « pas plus de 45 % d'une couleur à l'écran » dans `audit_shots.gd`.
3. Eau :
   - niveau toujours sous la berge ;
   - découpe sous les tabliers, les trémies et les polygones couverts ;
   - spéculaire borné ;
   - pas d'arbres ni d'herbe dans l'eau.
4. `cel_layer_clip` sur la hauteur relative au terrain.
5. Gabarit : test de dégagement de la rame (piles, tabliers, terrain, plans d'eau) sur toutes les lignes, puis correction de Rouen, Le Havre, Aubagne, Mulhouse et Lille.

**P1 – Remodéliser la voirie depuis zéro**
- Graphe routier OSM, avec des polygones fusionnés par union booléenne (Clipper ou équivalent hors ligne, dans l'import Python) :
  - chaussée ;
  - carrefours (polygone de jonction avec arrondis) ;
  - bordures extrudées continues ;
  - trottoirs en anneau autour des îlots ;
  - plateformes tram intégrées au polygone ;
  - passages piétons et marquages en décalques.
- Précalcul dans `data/scenes` (géométrie triangulée, UV métriques), drapé exact sur le terrain (triangulation contrainte commune).
- Supprimer `_ribbon`, `_street_edges` et `_crossroad` du décor.

**P2 – Terrain continu drapé**
- Maillage par tuile en TIN contraint : arêtes de voirie, de quais, de berges et de pieds de bâtiment. Le MNT (RGE ALTI au pas de 1–5 m, si disponible) est rééchantillonné sous la voirie.
- Talus générés au lieu de murs verticaux. Rampes de pont intégrées au maillage.
- Couronne lointaine à LOD (2–8 km) pour l'horizon.

**P3 – Matériaux procéduraux stables**
- Identifiant de matériau hors `COLOR.a`.
- Triplanaire métrique avec trois octaves (macro 8 m, méso 1 m, micro 10 cm) et fondu par `fwidth` vers la moyenne de l'octave suivante : aucun aplat, aucun moiré.
- Masques d'usure : bord de trottoir, traces de roues, taches.
- Végétation du sol en masque lissé.
- Toits et sol teintés depuis l'orthophoto (texture de teinte basse résolution par tuile, 1–2 m/px), ce qui corrige aussi les aplats beiges.

**P4 – Densité et immersion**
- Mobilier OSM (feux, passages, abris, panneaux, potelets).
- Voitures en stationnement.
- Façades par époque et région (haussmannien, brique du Nord, pierre de Bourgogne, andésite).
- Rez-de-chaussée commerciaux, balcons.
- Halos d'éclairage nocturne.
- Stations souterraines habillées.

**P5 – Performance**
- LOD de tuile (HLOD), ombres à 2 cascades au-delà de 60 m, instanciation du mobilier.
- Mesure sur 3 appareils Android.

## 5. Limites de l'audit

- Le choix « centre dense » utilise la taille en octets de la tuile de décor. Les tuiles riches en arbres d'orthophoto peuvent passer devant (Strasbourg « Ducs d'Alsace », Montpellier « Les Arceaux »).
- Sur les lignes sans pont, le point « pont » est remplacé par la station médiane : Avignon, Marseille, Montpellier, Nice et Le Havre.
- La vue aérienne est rendue sans brouillard pour être comparable à l'orthophoto : elle montre les couleurs brutes, plus sombres qu'en jeu.
- Les 16 premières villes ont été capturées avec une caméra aérienne orthographique, les suivantes avec une focale longue en perspective. Le résultat est identique : vérifié sur Angers.
- Le rendu est logiciel (llvmpipe) : les durées par image ne sont pas des mesures de performance.

## 6. Planches et fichiers produits

Dossier des captures : `/tmp/claude-0/-home-user/15938488-7e5b-5b2f-adb2-1826d968f007/scratchpad/audit/`. On y trouve :
- 364 PNG `<ville>_<point>_<vue>.png` ;
- `<ville>.log` et `audit_points.txt` ;
- `rev/*.jpg` : revues réduites, `rev/details.png` (recadrages à 100 %), `rev/refs4.jpg` (comparaison avec les photos Commons).

Planches (`audit/planches/`) : une par ville, avec quatre lignes de points (3e personne, cabine, aérien, orthophoto IGN) et une ligne nuit plus photo Commons quand elle existe.

`planche_angers.jpg`, `planche_aubagne.jpg`, `planche_avignon.jpg`, `planche_besancon.jpg`, `planche_bordeaux.jpg`, `planche_brest.jpg`, `planche_caen.jpg`, `planche_clermont.jpg`, `planche_dijon.jpg`, `planche_grenoble.jpg`, `planche_idf.jpg`, `planche_lehavre.jpg`, `planche_lemans.jpg`, `planche_lille.jpg`, `planche_lyon.jpg`, `planche_marseille.jpg`, `planche_montpellier.jpg`, `planche_mulhouse.jpg`, `planche_nantes.jpg`, `planche_nice.jpg`, `planche_orleans.jpg`, `planche_reims.jpg`, `planche_rouen.jpg`, `planche_saintetienne.jpg`, `planche_strasbourg.jpg`, `planche_toulouse.jpg`, `planche_tours.jpg`, `planche_valenciennes.jpg`.

Cache de l'orthophoto IGN : `scratchpad/ortho/`. Photos Commons : `scratchpad/refs_commons/`.

Pour reproduire :

```
<godot> --headless --path . --import
tests/audit/run_audit.sh <godot> <dossier> [villes]
python3 tests/audit/planches.py <dossier> <cache_ortho>
python3 -I tests/audit/refs_commons.py <dossier> <cache_refs>
```

Options de diagnostic : `AUDIT_FOG=0` (désactive le brouillard), `AUDIT_AER_FOG=1` (conserve le brouillard en vue aérienne).
