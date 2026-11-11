# Feuille de route et état de couverture

| Étape | État |
|---|---|
| 1. SDK/modèles d'export/signature, APK technique | **Bloqué** : dl.google.com inaccessible depuis l'environnement cloud (SDK Android non installable) |
| 2. Parcours réel complet (conduite, missions, aiguillages, trafic) | Noyau fait : physique 1D, graphe + aiguillages + occupation, scoring de ponctualité (testés) ; reste rendu 3D, signaux, trafic, UI |
| 3. Angers / Nantes / Bordeaux (APS), pneus, tram-train | À faire |
| 4. Inventaire national | À faire (inventaire daté à produire d'abord : `docs/INVENTAIRE.md`) |
| 5. Optimisation et livraison | À faire |

Perf (30 i/s, 4 Go) : à mesurer sur téléphone réel ; non validable en CI.
