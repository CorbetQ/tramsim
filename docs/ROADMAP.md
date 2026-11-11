# Feuille de route et état de couverture

| Étape | État |
|---|---|
| 1. SDK/modèles d'export/signature, APK technique | **Fait** : APK debug arm64 signée (clé de développement), `package=fr.tramsim.game`, ~27 Mo, hors ligne. Reste à tester sur téléphone |
| 2. Parcours complet | **Fait côté logique, sur données provisoires** : conduite, missions (ponctualité), aiguillages, signaux (cantonnement automatique par occupation), occupation, trafic routier + feux, mode libre (remise sur voie, trafic désactivable, mode d'adaptation), APS/pantographe, sauvegarde, registre de réseaux, secteurs de rendu par distance de vue, carte, tutoriel, HUD tactile. 5 suites de tests + chaîne d'import testée sur fixtures. **Manque** : données réelles Angers (réseau bloqué), vue cabine réelle, modèles 3D, signalisation par itinéraires, test téléphone |
| 3. Angers / Nantes / Bordeaux (APS), pneus, tram-train | À faire |
| 4. Inventaire national | À faire (inventaire daté à produire d'abord : `docs/INVENTAIRE.md`) |
| 5. Optimisation et livraison | À faire |

Perf (30 i/s, 4 Go) : à mesurer sur téléphone réel ; non validable en CI.
