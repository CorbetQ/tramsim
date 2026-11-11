# Feuille de route et état de couverture

| Étape | État |
|---|---|
| 1. SDK/modèles d'export/signature, APK technique | **Préparé** : `export_presets.cfg` (arm64, hors ligne). **Non produit** : dl.google.com inaccessible depuis le cloud (SDK Android), à compiler en local |
| 2. Parcours complet | **Fait côté logique, sur données provisoires** : conduite, missions (ponctualité), aiguillages, signaux, occupation, trafic routier + feux, mode libre (remise sur voie, trafic désactivable, mode d'adaptation), APS/pantographe, sauvegarde, carte, tutoriel, HUD tactile. 5 suites de tests + chaîne d'import testée sur fixtures. **Manque** : données réelles Angers (réseau bloqué), vue cabine réelle, modèles 3D, signalisation par itinéraires, test téléphone |
| 3. Angers / Nantes / Bordeaux (APS), pneus, tram-train | À faire |
| 4. Inventaire national | À faire (inventaire daté à produire d'abord : `docs/INVENTAIRE.md`) |
| 5. Optimisation et livraison | À faire |

Perf (30 i/s, 4 Go) : à mesurer sur téléphone réel ; non validable en CI.
