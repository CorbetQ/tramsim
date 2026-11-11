# Feuille de route et état de couverture

| Étape | État |
|---|---|
| 1. SDK/modèles d'export/signature, APK technique | **Bloqué** : dl.google.com inaccessible depuis l'environnement cloud (SDK Android non installable) |
| 2. Parcours complet (conduite, missions, aiguillages, trafic) | **Partiel** : chargeur de réseau JSON, session de mission (arrêts, portes, charge, signaux, occupation, fin de voie, collision, ponctualité), scène 3D schématique + HUD tactile ; testés sans écran. **Données Angers provisoires** (OSM/GTFS inaccessibles depuis le cloud). Reste : import réel, trafic routier/feux, mode libre, tutoriel, carte, vue cabine réelle, test sur téléphone |
| 3. Angers / Nantes / Bordeaux (APS), pneus, tram-train | À faire |
| 4. Inventaire national | À faire (inventaire daté à produire d'abord : `docs/INVENTAIRE.md`) |
| 5. Optimisation et livraison | À faire |

Perf (30 i/s, 4 Go) : à mesurer sur téléphone réel ; non validable en CI.
