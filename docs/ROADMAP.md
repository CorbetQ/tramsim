# Feuille de route et état de couverture

| Étape | État |
|---|---|
| 1. SDK/modèles d'export/signature, APK technique | **Fait** : APK debug arm64 signée (clé de développement), `package=fr.tramsim.game`, ~27 Mo, hors ligne. Reste à tester sur téléphone |
| 2. Parcours complet | **Fait sur données réelles** : Angers A, B, C importées du GTFS Irigo (vrais arrêts, tracés, horaires) ; une mission réelle de la ligne A (25 arrêts) est réussie au pilote automatique dans les temps GTFS. Conduite, ponctualité, signaux, trafic, mode libre, APS (logique), sauvegarde, carte, rendu 3D avec rame articulée et bâtiments génériques (captures vérifiées sous Xvfb). **Manque** : aiguillages/voies de service réels (OSM bloqué), pentes, APS localisé, test sur téléphone |
| 3. Angers / Nantes / Bordeaux (APS), pneus, tram-train | À faire |
| 4. Inventaire national | À faire (inventaire daté à produire d'abord : `docs/INVENTAIRE.md`) |
| 5. Optimisation et livraison | À faire |

Perf (30 i/s, 4 Go) : à mesurer sur téléphone réel ; non validable en CI.
