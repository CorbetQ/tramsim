# Sources de données

| Source | Version / date | Licence | Utilisée pour | État |
|---|---|---|---|---|
| GTFS de 29 réseaux (liste et URL : `data/sources/gtfs_catalogue.json`, licences : `CREDITS.md`) | téléchargés le 11/11/2026 | voir CREDITS | tracés (shapes, sinon segments droits entre arrêts), arrêts, horaires, temps d'arrêt et de parcours | **intégré** |
| OpenStreetMap / Overpass | — | ODbL | aiguillages, voies de service, topologie fine | **inaccessible** depuis l'environnement cloud (connexion coupée par le proxy) |
| IGN – BD TOPO® (WFS data.geopf.fr) | extraction du 11/11/2026 | Licence Ouverte 2.0 | décor réel dans un corridor de 220 m autour des voies : bâtiments (emprise, hauteur, usage), tronçons de route (largeur), surfaces en eau, végétation, terrains de sport, cimetières, voies ferrées | **intégré** (`tools/import/ign_scene.py`) |
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
- Arbres : dispersés aléatoirement (tirage stable) dans les zones de végétation réelles ; pas d'arbres d'alignement.
- Couleurs de façades et de toitures : palettes régionales choisies par le projet (`data/city_styles.json`), pas les couleurs réelles de chaque bâtiment.
- Livrées : `data/rolling_stock/liveries.json` (approximations documentées par réseau ; `route` = couleur officielle de la ligne).
