# Sources de données

| Source | Version / date | Licence | Utilisée pour | État |
|---|---|---|---|---|
| GTFS Irigo (transport.data.gouv.fr, ressource 32f30b64…) | 24/10/2026 (validité 11/11/2026 → 09/02/2027) | ODbL | Angers A, B, C : tracés (shapes), arrêts, horaires, temps d'arrêt | **intégré** |
| OpenStreetMap / Overpass | — | ODbL | aiguillages, voies de service, topologie fine | **inaccessible** depuis l'environnement cloud (connexion coupée par le proxy) |
| IGN (MNT) | — | Licence Ouverte 2.0 | pentes | non intégré |

## Valeurs estimées (signalées dans chaque fichier, champ `estimated`)
- **Pentes** : 0 partout (pas de MNT).
- **Limites de vitesse** : 50 km/h par défaut ; zones réduites autour des courbes, calculées à partir du rayon mesuré sur le tracé GTFS (accélération latérale 0,9 m/s²). Ce ne sont pas les limitations réelles de l'exploitant.
- **Alimentation** : caténaire supposée partout. L'APS du centre d'Angers n'est pas localisé dans les données publiques utilisées.
- **Terminus** : rebroussement simplifié (fin d'un sens raccordée à l'approche de l'autre).
- **Tronçons communs** (A/C, B/C) : chaque ligne est un réseau séparé ; les voies partagées ne sont pas fusionnées.
- **Matériel** : masse, puissance, effort et freinage du Citadis 302 sont estimés (`VehicleProfile.estimated`).

Régénération : `python3 tools/import/gtfs_to_network.py <dossier_gtfs> A data/networks/angers_a.json --id angers_a --city Angers --source-date 2026-10-24 --publisher "Irigo / Angers Loire Métropole" --licence ODbL`.
