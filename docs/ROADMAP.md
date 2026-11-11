# Feuille de route et état de couverture

| Étape | État |
|---|---|
| 1. SDK/modèles d'export/signature, APK technique | **Fait** : APK debug arm64 signée (clé de développement), `package=fr.tramsim.game`, ~27 Mo, hors ligne. Reste à tester sur téléphone |
| 2. Parcours complet | **Fait sur données réelles** : Angers A, B, C importées du GTFS Irigo (vrais arrêts, tracés, horaires) ; une mission réelle de la ligne A (25 arrêts) est réussie au pilote automatique dans les temps GTFS. Conduite, ponctualité, signaux, trafic, mode libre, APS (logique), sauvegarde, carte, rendu 3D avec rame articulée et bâtiments génériques (captures vérifiées sous Xvfb). **Manque** : aiguillages/voies de service réels (OSM bloqué), pentes, APS localisé, test sur téléphone |
| 3. Diversité technique | **Fait (données)** : Nantes, Bordeaux, tram-trains (Mulhouse TT, IDF T4/T11/T12/T13), pneus (Clermont A, IDF T5/T6, guidage marqué « à vérifier »), tram express (Rhônexpress). APS : mécanique testée, mais sections APS réelles **non localisées** (aucune donnée publique utilisée) |
| 4. Inventaire national | **120 lignes/variantes, 29 réseaux** importés des GTFS officiels (transport.data.gouv.fr) ; mission réelle réussie au pilote automatique sur 115/120 (5 avec quelques retards). Voir `docs/COUVERTURE.md`. Manque : Annemasse (GTFS TPG), aiguillages/voies de service réels, pentes, flottes réelles par réseau |
| 5. Optimisation et livraison | À faire |

Perf (30 i/s, 4 Go) : à mesurer sur téléphone réel ; non validable en CI.
