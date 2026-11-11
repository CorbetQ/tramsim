# Sources de données

| Source | Version / date | Licence | Utilisée pour | État |
|---|---|---|---|---|
| GTFS de 29 réseaux (liste et URL : `data/sources/gtfs_catalogue.json`, licences : `CREDITS.md`) | téléchargés le 11/11/2026 | voir CREDITS | tracés (shapes, sinon segments droits entre arrêts), arrêts, horaires, temps d'arrêt et de parcours | **intégré** |
| OpenStreetMap / Overpass | — | ODbL | aiguillages, voies de service, topologie fine | **inaccessible** depuis l'environnement cloud (connexion coupée par le proxy) |
| IGN – BD TOPO® (WFS data.geopf.fr) | extraction du 11/11/2026 | Licence Ouverte 2.0 | décor réel dans un corridor de 220 m autour des voies : bâtiments (emprise, hauteur, usage), tronçons de route (largeur), surfaces en eau, végétation, terrains de sport, cimetières, voies ferrées | **intégré** (`tools/import/ign_scene.py`) |
| IGN – BD ORTHO® (WMTS data.geopf.fr, couche ORTHOIMAGERY.ORTHOPHOTOS, Web Mercator z17/z18) | consultée le 11/11/2026 | Licence Ouverte 2.0 | analyse automatique (aucune image embarquée) : couleur des toits, houppiers, sol vert/minéral, nature des plateformes de tram | **intégré** (`tools/import/ign_scene.py`) |
| IGN (MNT) | — | Licence Ouverte 2.0 | pentes | non intégré |

## Valeurs estimées (signalées dans chaque fichier, champ `estimated`)
- **Pentes** : 0 partout (pas de MNT).
- **Limites de vitesse** : 50 km/h par défaut, relevées (jusqu'à 70 km/h, 100 km/h pour tram-trains et Rhônexpress) quand l'horaire GTFS l'exige ; zones réduites autour des courbes, calculées à partir du rayon mesuré sur le tracé GTFS (accélération latérale 0,9 m/s²). Ce ne sont pas les limitations réelles de l'exploitant.
- **Alimentation** : caténaire supposée partout. L'APS du centre d'Angers n'est pas localisé dans les données publiques utilisées.
- **Terminus** : rebroussement simplifié (fin d'un sens raccordée à l'approche de l'autre).
- **Tronçons communs** (A/C, B/C) : chaque ligne est un réseau séparé ; les voies partagées ne sont pas fusionnées.
- **Matériel** : masse, puissance, effort et freinage du Citadis 302 sont estimés (`VehicleProfile.estimated`).

Géométrie : quand `shapes.txt` manque (IDF, Lille, Montpellier, Le Havre…) ou s'écarte de plus de 50 m des arrêts (Orléans, Clermont), la voie suit des segments droits entre arrêts.

Régénération d'une ligne : `python3 tools/import/gtfs_to_network.py <dossier_gtfs> A data/networks/angers_a.json --id angers_a --city Angers --source-date 2026-10-24 --publisher "Irigo / Angers Loire Métropole" --licence ODbL`.

## Décor
- Hors du corridor de 220 m, le sol est générique (pas de bâtiments).
- Hauteurs : attribut `hauteur` de la BD TOPO, sinon nombre d'étages, sinon valeur par type.
- Toits : à quatre pans pour les petites maisons, plats ailleurs (choix stylistique low poly) ; fenêtres procédurales.
- Arbres : houppiers réels détectés sur orthophoto (scènes TSC3, voir « Décor v3 ») ; à défaut, dispersés aléatoirement (tirage stable) dans les zones de végétation réelles.
- Couleurs de façades : palettes régionales choisies par le projet (`data/city_styles.json`) ; toitures : couleur réelle mesurée sur orthophoto (TSC3), sinon palette régionale.
- Livrées : `data/rolling_stock/liveries.json` (approximations documentées par réseau ; `route` = couleur officielle de la ligne).

## Décor v2 (BD TOPO)
- Bâtiments remarquables : zones d'intérêt nommées (`zone_d_activite_ou_d_interet`, `equipement_de_transport`) → églises, cathédrales/basiliques, châteaux, édifices civiques (mairie, préfecture, musée, monument…), gares, écoles ; nom affiché au-dessus du volume principal.
- Clochers, tours, cheminées : `construction_ponctuelle` (hauteur IGN si renseignée, sinon estimée).
- Toits (deux pans, croupe, mansarde parisienne, sheds), vitrines, balcons haussmanniens, essences d'arbres régionales et arbres d'alignement : choix stylistiques du projet, pas des relevés.
- Plateformes de tram : engazonnée / enrobée / pavée selon la densité de bâti alentour (heuristique, repli si la scène n'a pas d'analyse d'orthophoto).

## Décor v3 (orthophotos IGN, format TSC3)
- Aucune image n'est livrée : `ign_scene.py` (5e argument = cache des dalles WMTS) échantillonne les orthophotos et n'enregistre que des mesures.
- Toits : couleur moyenne des pixels de l'emprise (bord érodé d'1 px), éclaircie et saturée pour le style toon, quantifiée sur 4 bits par canal ; couleur du style si l'emprise est masquée par la végétation.
- Arbres : houppiers détectés (indice de verdure + pixels sombres ou texturés, hors bâti, à plus de 4,5 m de l'axe des voies), maxima de la distance au bord → position et rayon ; remplacent la dispersion aléatoire et les alignements procéduraux de la tuile. Essence : mélange régional du style.
- Sol vert : cellules de 4 m à majorité de végétation (gazon y compris sec), dessinées sous les surfaces BD TOPO et les routes.
- Plateformes : `data/scenes/<ville>_track.json`, cellules de 8 m le long de l'axe des voies (z18, ±4,5 m en travers, lissage 40 m) : 1 gazon (verdure > 38 %, ou pixels minéraux « chauds » rouge − bleu > 0,035 et 75e centile < 0,60 : gazon sec des orthophotos d'été), 3 pavés/béton (75e centile de luminance minérale > luminance médiane des chaussées BD TOPO de la ville + 0,08, bornée à [0,50 ; 0,70]), 2 enrobé/chaussée partagée sinon. Tronçons souterrains (BD TOPO `Tramway` sous le sol) exclus. Limites : ombres portées, arbres surplombant la voie, imprécision des tracés GTFS (1 à 5 m).
- Décor interdit sur les plateformes : bâtiments et constructions ponctuelles à moins de 3,6 m de l'axe retirés à l'import (sauf au-dessus d'un tunnel) ; au rendu, arbres, lampadaires et clochers isolés exclus à moins de 4,2 m de l'axe (`TrackView.KeepOut`) et des quais (houppiers réduits pour ne pas déborder).
- Tracés : `tools/import/smooth_tracks.py` lisse les polylignes de `data/networks` (pics, allers-retours, décrochements supprimés ; Douglas-Peucker 0,35 m ; arrondis de rayon 28 m au plus), jonctions d'arêtes conservées ; relancer `merge_city.py` ensuite pour `data/free`.
- Arrêts de retournement : arrêts GTFS où des services commencent ou finissent (≥ 4 services) ; la géométrie des communications de voies est stylisée.
