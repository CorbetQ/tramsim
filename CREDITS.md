# Crédits et licences

- Moteur : Godot Engine 4.6.3 (MIT).
- **Voies physiques, aiguillages, voies de service, emprises de quais et de dépôts** : © les contributeurs [OpenStreetMap](https://www.openstreetmap.org/copyright), [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/). Les bases dérivées `data/free` conservent cette attribution. Extraits Overpass, métadonnées et requêtes : `data/geography/osm`; complément d'emprise de Besançon : API OpenStreetMap. La date de la base est conservée dans chaque extrait, distincte de la date de téléchargement.
- **Altitudes des ouvrages et bâtiments de maintenance** : IGN BD TOPO®, [Licence Ouverte 2.0](https://www.etalab.gouv.fr/licence-ouverte-open-licence/), sources compressées dans `data/geography/ign_rail` et `data/geography/depot_buildings`. Les profils interpolés, hauteurs de quai estimées et limites de vitesse par défaut sont distingués des mesures source dans les métadonnées.

- **Décor (bâtiments, routes, eau, végétation, terrains de sport, cimetières, voies ferrées)** : Source : IGN – BD TOPO®,
  service WFS data.geopf.fr, **Licence Ouverte 2.0** (Etalab). Fichiers dérivés : `data/scenes/*.bin` (+ `.json` : date d'extraction).
- Modèles de rames, livrées, palettes de façades : créations originales du projet (aucune image ni marque reproduite) ;
  les couleurs d'accent sont les couleurs officielles des lignes publiées dans les GTFS.
- Données d'offre de transport (tracés, arrêts, horaires) issues des GTFS publiés sur transport.data.gouv.fr. Les fichiers `data/networks/*.json` sont des bases dérivées ; celles issues de jeux sous ODbL restent sous **ODbL**.

| Réseau | Producteur | Licence |
|---|---|---|
| Angers | Irigo / Angers Loire Métropole | ODbL |
| Nantes | Naolib / Nantes Métropole | Licence Ouverte 2.0 |
| Bordeaux | TBM / Bordeaux Métropole | Licence Ouverte |
| Clermont-Ferrand | T2C / SMTC-AC | Licence Ouverte 2.0 |
| Mulhouse | Soléa | Licence Ouverte 2.0 |
| Grenoble | M réso / SMMAG | ODbL |
| Toulouse | Tisséo | ODbL |
| Strasbourg | CTS | Licence Ouverte 2.0 |
| Montpellier | TaM | ODbL |
| Lille | Ilévia / MEL | Licence Ouverte 2.0 |
| Lyon | TCL / Sytral Mobilités | Licence Mobilités (vérifier les conditions) |
| Marseille | RTM / Métropole Aix-Marseille-Provence | Licence Ouverte 2.0 |
| Nice | Lignes d'Azur | Licence Ouverte 2.0 |
| Rouen | Astuce / Métropole Rouen Normandie | Licence Ouverte 2.0 |
| Reims | Grand Reims Mobilités | Licence Ouverte 2.0 |
| Dijon | DiviaMobilités | Licence Ouverte 2.0 |
| Tours | Fil Bleu / SMT | Licence Ouverte 2.0 |
| Orléans | TAO / Orléans Métropole | Licence Ouverte 2.0 |
| Le Mans | SETRAM | Licence Ouverte 2.0 |
| Caen | Twisto / Caen la Mer | non précisée sur le portail (à vérifier) |
| Brest | Bibus / Brest Métropole | Licence Ouverte 2.0 |
| Le Havre | LiA | ODbL |
| Saint-Étienne | STAS | Licence Ouverte 2.0 |
| Besançon | Ginko | Licence Ouverte 2.0 |
| Avignon | Orizo | Licence Ouverte 2.0 |
| Valenciennes | Transvilles / SIMOUV | Licence Ouverte 2.0 |
| Île-de-France | Île-de-France Mobilités | Licence Mobilités (vérifier les conditions) |
| Aubagne | Les lignes de l'agglo / Métropole Aix-Marseille-Provence | Licence Ouverte 2.0 |

Deux jeux (Lyon TCL, Île-de-France Mobilités) sont sous « Licence Mobilités » : conditions de réutilisation à vérifier avant toute diffusion publique.
Caen : licence non précisée sur le portail — à vérifier avant diffusion publique.

## Sons

Les sons de base sont des synthèses originales (`data/audio/make_audio.py`), complétées par
les captations ci-dessous. `data/audio/sources.json` décrit chaque fichier distribué ;
`data/audio/families.json` indique les familles exactes, apparentées ou synthétiques.
Les extraits conservent la licence de leur source, indépendamment de celle du code.

Calibrage des synthèses : D. Thompson, *Railway Noise and Vibration* (Elsevier, 2009),
principes publics des onduleurs de traction et méthode de mesure ISO 3095.

### Captations intégrées en 0.9.2

Les sources Wikimedia Commons sont liées dans la table. Chaque banque utilise deux
extraits, mono 32 kHz, passe-bande 65–3800 Hz, raccord croisé de 250 ms et sonie proche
de −20 LUFS. Les temps, mesures réelles, liens de licence, auteurs et empreintes SHA-256
des originaux sont conservés dans `data/audio/families.json`. Les OGG transformés sont
réutilisables sous la licence indiquée, y compris les obligations de partage à l’identique.
Les originaux vidéo ne sont pas embarqués.

| Captation / source | Auteur | Licence |
|---|---|---|
| [File:Alstom Citadis 302 in Moscow.webm](https://commons.wikimedia.org/wiki/File:Alstom_Citadis_302_in_Moscow.webm) | trolleway | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0) |
| [File:Départ d'une rame Citadis 402 de la station Porte d'Ivry.ogg](https://commons.wikimedia.org/wiki/File:D%C3%A9part_d%27une_rame_Citadis_402_de_la_station_Porte_d%27Ivry.ogg) | Litlok | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) |
| [File:Citadis 403 n°2040 CTS, ligne A, Langstross - Porte de l'Hôpital.ogg](https://commons.wikimedia.org/wiki/File:Citadis_403_n%C2%B02040_CTS,_ligne_A,_Langstross_-_Porte_de_l%27H%C3%B4pital.ogg) | Kevin.B | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) |
| [File:T4 Bondy - Aulnay 07.ogv](https://commons.wikimedia.org/wiki/File:T4_Bondy_-_Aulnay_07.ogv) | Clicsouris | [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0) |
| [File:Arrivée du tram.webm](https://commons.wikimedia.org/wiki/File:Arriv%C3%A9e_du_tram.webm) | Clément Bucco-Lechat | [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0) |
| [File:Tramway de Marseille - Ligne 2 - Boulevard Philippon.ogv](https://commons.wikimedia.org/wiki/File:Tramway_de_Marseille_-_Ligne_2_-_Boulevard_Philippon.ogv) | Clicsouris | [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0) |
| [File:Luxembourg tram testing August 2017 (1).webm](https://commons.wikimedia.org/wiki/File:Luxembourg_tram_testing_August_2017_(1).webm) | GilPe | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) |

Identification : Nantes M2 324 est un TFS ; le véhicule marseillais est un Flexity Outlook, malgré la légende Commons qui indique Citadis. Les autres profils emploient un apparentement documenté ou une synthèse ; aucune captation de Translohr n’est revendiquée.

## Images du catalogue

Vignettes `data/rolling_stock/thumbs/*.png` : rendus des modèles 3D du projet (`tools/render_thumbs.gd`), aucune photo reproduite.
Les photos Wikimedia Commons citées dans `data/rolling_stock/research.json` (« references ») ont servi de référence de forme et de
couleur uniquement ; elles ne sont pas distribuées.

## Interface

- **Police Atkinson Hyperlegible** (Regular, Bold) — © 2020 Braille Institute of America, Inc., licence
  SIL Open Font License 1.1 (`data/ui/fonts/OFL.txt`). Source : https://github.com/googlefonts/atkinson-hyperlegible
  (commit 1cb3116), fichiers `fonts/ttf/AtkinsonHyperlegible-{Regular,Bold}.ttf` copiés dans `data/ui/fonts/`.
- **Icônes** `data/ui/icons/*.svg` : dessinées pour le projet (même licence que le code).

## Captation de tramway (0.9)

« Tram sound in Lyon, France », Glaneur de sons, 20 mars 2007.
Source : https://commons.wikimedia.org/wiki/File:Tram_sound_in_Lyon,_France.ogg
Licence : CC BY 3.0, https://creativecommons.org/licenses/by/3.0/ .
Modifications : extrait 8–12 s, filtrage 85–1500 Hz, raccord et normalisation ;
utilisé comme texture de roulement, complété par les moteurs synthétiques.
Original et recette conservés dans `data/audio/reference/` et `tools/import/recorded_audio.py`.

## Génération visuelle 0.10

Les textures procédurales et détails architecturaux de 0.10 sont des créations du projet, sans échantillons photographiques externes ajoutés. Les profils régionaux sont des choix artistiques. Les niveaux routiers supplémentaires (`data/scenes/*_road_levels.json`) sont dérivés du champ IGN BD TOPO `position_par_rapport_au_sol`, Licence Ouverte 2.0, dans les extraits en cache de l’import géographique existant. Couverture et absences : `docs/world-010-coverage.json`.

### Captation de tram du Mans

[TRAM - 1, SamuelGremaud](https://freesound.org/people/SamuelGremaud/sounds/458858/), [CC0](https://creativecommons.org/publicdomain/zero/1.0/). Source : aperçu public haute qualité, captation extérieure de passage. Extraits filtrés et bouclés ; niveaux et régime de simulation estimés. Métadonnées, empreintes et points de coupe dans `data/audio/families.json`, reproduction avec `tools/stock/import_lemans_audio.py`.

### Photographies de référence des rames

Les photographies du dossier documentaire sont créditées individuellement dans [PHOTO-CREDITS.md](docs/rolling-stock-rebuild/PHOTO-CREDITS.md). Elles sont distinctes des maillages du jeu et exclues de ses exports. Les références externes restent hébergées sur leurs sites sources.

### Tram-trains nantais et contrôle du terrain 0.12.1

Les arrêts TER T1/T2 proviennent des relations OpenStreetMap [19515572](https://www.openstreetmap.org/relation/19515572) et [19513724](https://www.openstreetmap.org/relation/19513724), consultées le 13 novembre 2026, © contributeurs OpenStreetMap, ODbL. Coordonnées et identifiants : `data/sources/nantes_tram_train.json`. Les corrections ponctuelles du relief réutilisent le MNT IGN RGE ALTI®, Licence Ouverte 2.0. [Rapport et captures](docs/map-fixes-0.12.1/README.md).

### Atelier audio du 14 novembre 2026

Les références collectées, leurs auteurs/licences et les limites d'attribution par matériel sont documentés dans [samples/sources.json](samples/sources.json). Les adaptations intégrées et la restitution modélisée du Citadis 305 sont détaillées dans [data/audio/DESIGN-CREDITS.md](data/audio/DESIGN-CREDITS.md) et [samples/design-notes.md](samples/design-notes.md). Les captures du bus Master du jeu et les copies d'écoute sont distinctes des enregistrements de rames réelles ; voir [samples/README.md](samples/README.md).

### Traction Citadis apparentée — Rotterdam

LG, « Streetcar04.wav », https://freesound.org/people/LG/sounds/14279/ , Creative Commons Attribution4.0 (https://creativecommons.org/licenses/by/4.0/). Préview public de départ à Rotterdam ; dérivés : séparation harmonique candidate, trois fenêtres courtes, raccords et normalisation. Utilisée comme source apparentée pour les quinze variantesCitadis302, sans certification de motrice française. Crédits et traitements : `data/audio/ROTTERDAM-CREDITS.md`, `data/audio/rotterdam-traction-manifest.json`.

### Effets gratuits — interface et environnement (0.13.1)

- **Kenney, Interface Sounds 1.0**, [CC0](https://creativecommons.org/publicdomain/zero/1.0/) : clic, retour et confirmation. [Banque originale](https://kenney.nl/assets/interface-sounds), [miroir des originaux utilisé](https://github.com/Calinou/kenney-interface-sounds/tree/master/addons/kenney_interface_sounds). Filtrage et fondus courts. Licence incluse dans `data/audio/free_sfx/KENNEY-LICENSE.txt`.
- **Joseph Sardin, Réveil des oiseaux**, [CC0](https://commons.wikimedia.org/wiki/File:Réveil_des_oiseaux.ogg) : extrait 8–40 s, mono 32 kHz, filtrage, raccord croisé 2 s, sonie −20 LUFS. Ambiance générique de jardin européen ; aucune attribution à une ville particulière.
- Souffle d'air : synthèse originale locale de bruit brun filtré. Aucune captation constructeur, voix ni musique.

Provenance, empreintes des originaux et traitements : `data/audio/free_sfx/SOURCES.json`. Reproduction : `tools/audio/build_free_sfx.py`. Aucun service de génération payant utilisé pour ces effets.

### Stations d’Angers et dépôt Raymond-Perron

Relevé documentaire du 14 novembre 2026 : empreintes OSM (ODbL), IGN BD TOPO et BD ORTHO
(Licence Ouverte 2.0), vues de rue Panoramax avec auteur/date/licence par image.
Les photographies de mobilier de la Ville d’Angers, de CMR et d’Édouard Paris servent uniquement
à la reconstruction de géométrie originale. Références et limites :
[relevé des stations](docs/angers-stations/README.md) et
[registre des sources](tools/import/angers_station_references.json).

## Audio Studio

Le catalogue normalisé dans `data/audio/sources.json` conserve les licences,
provenances, classifications et empreintes des fichiers actuels. Les anciennes
attributions ci-dessus restent valables. Voir
[attributions générées](docs/audio-studio/ATTRIBUTIONS.md) et
[rapport Audio Studio](docs/audio-studio/REPORT.md).

Le candidat `studio_citadis302_reference_v1` utilise l'original Commons
« Alstom Citadis 302 in Moscow », trolleway, CC BY 3.0 :
https://commons.wikimedia.org/wiki/File:Alstom_Citadis_302_in_Moscow.webm .
Modifications : extraits 37,066–41,366 s et 101,932–106,232 s, mono 32 kHz,
filtrage 65–12 000 Hz, recouvrement 180 ms, gain constant vers -20 LUFS,
mesure après encodage. Captation extérieure de famille exacte, pas une motrice
isolée ni une captation d'Angers. Candidat non activé dans les profils de jeu.
Les démos reprennent aussi les sources du moteur actuel (notamment LG/Rotterdam,
CC BY 4.0, Joseph Sardin/CC0 et les synthèses du projet), sans supprimer leurs droits.
Aucun son IA ni poids de modèle ajouté.

## Noyau Rust optionnel et intérieurs passager

Le noyau numérique et l'aménagement procédural des intérieurs de cette tranche sont
créés pour TramSim ; les aménagements sont estimés, sans asset Meshy téléchargé.
Les plans, livrées et références antérieurs conservent leurs crédits ci-dessus.
La liaison godot-rust 0.4.5 et les données d'API associées sont sous **MPL-2.0**.
Notices, versions exactes, sources correspondantes et textes de licences :
[native/THIRD_PARTY.md](native/THIRD_PARTY.md) et [native/licenses/](native/licenses/).
Ces notices doivent accompagner toute distribution du module natif.


## Citadis Meshy : Angers 302 / 305 et Nantes 405 (expérimental)

Model created with Meshy – CC BY 4.0 License. https://creativecommons.org/licenses/by/4.0/

Caisses adaptées depuis des photos libres, redistribution des adaptations sous
CC BY-SA 4.0 : https://creativecommons.org/licenses/by-sa/4.0/.
Crédits des images effectivement envoyées à Meshy :

- File:3,52 Verneau Citadis n°1016 (tram Angers) par Cramos.JPG — Cramos, CC BY-SA 3.0. https://commons.wikimedia.org/wiki/File:3,52_Verneau_Citadis_n%C2%B01016_(tram_Angers)_par_Cramos.JPG ; https://creativecommons.org/licenses/by-sa/3.0
- File:0,00 Ardennes Citadis n°1014 (tram Angers) par Cramos.JPG — Cramos, CC BY-SA 3.0. https://commons.wikimedia.org/wiki/File:0,00_Ardennes_Citadis_n%C2%B01014_(tram_Angers)_par_Cramos.JPG ; https://creativecommons.org/licenses/by-sa/3.0
- File:4,76 Jean Moulin Citadis n°1004 (tram Angers) par Cramos.JPG — Cramos, CC BY-SA 3.0. https://commons.wikimedia.org/wiki/File:4,76_Jean_Moulin_Citadis_n%C2%B01004_(tram_Angers)_par_Cramos.JPG ; https://creativecommons.org/licenses/by-sa/3.0
- File:Citadis 305.jpg — Blauer Pfeil, CC BY-SA 4.0. https://commons.wikimedia.org/wiki/File:Citadis_305.jpg ; https://creativecommons.org/licenses/by-sa/4.0
- File:Tramway à la station Farcy, Angers, 2026.jpg — Antimuonium, CC BY-SA 4.0. https://commons.wikimedia.org/wiki/File:Tramway_%C3%A0_la_station_Farcy,_Angers,_2026.jpg ; https://creativecommons.org/licenses/by-sa/4.0
- File:Angers - 15 boulevard du Maréchal-Foch 02.jpg — Fab5669, CC0. https://commons.wikimedia.org/wiki/File:Angers_-_15_boulevard_du_Mar%C3%A9chal-Foch_02.jpg ; http://creativecommons.org/publicdomain/zero/1.0/deed.en
- File:Nantes tram 2026 04.jpg — Smiley.toerist, CC BY-SA 4.0. https://commons.wikimedia.org/wiki/File:Nantes_tram_2026_04.jpg ; https://creativecommons.org/licenses/by-sa/4.0
- File:Alstom Citadis X05 - 405.jpg — JFGChenel, CC0. https://commons.wikimedia.org/wiki/File:Alstom_Citadis_X05_-_405.jpg ; http://creativecommons.org/publicdomain/zero/1.0/deed.en
- File:Nantes - Bouffay 20250726-02.jpg — Pymouss, CC BY-SA 4.0. https://commons.wikimedia.org/wiki/File:Nantes_-_Bouffay_20250726-02.jpg ; https://creativecommons.org/licenses/by-sa/4.0

Les sièges proviennent de rendus de travail originaux et de générations Meshy ;
matériaux, adaptation métrique, découpe, assemblage et rig par TramSim/Codex.
Les photos institutionnelles à droits réservés n’ont été ni redistribuées ni
envoyées à Meshy. Dossier complet : `data/rolling_stock/meshy_sources/CREDITS.md`.
