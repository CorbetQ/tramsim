# Tram Sim France

Simulateur de tramway 3D (Godot 4.6.3, GDScript, Android 10+, paysage, hors ligne).

## Version 0.10.0

Nouvelle génération visuelle commune aux **28 villes** : matériaux métriques filtrés (pierre, brique, enduit, enrobé, dallage et toitures), vitrines, stores et balcons, végétation à plusieurs strates et profils régionaux. Les routes utilisent des raccords continus, des trottoirs surélevés interrompus aux croisements et une meilleure association aux tabliers. Les caténaires évitent les gabarits des voies voisines et séparent les niveaux aux intersections.

La physique ajoute l’adhérence des essieux moteurs, le patinage en traction forte et le recul réel au neutre en rampe. Le HUD signale **PATINAGE** et **RECUL** ; les portes ouvertes enclenchent le frein de maintien. Voir [les changements et leurs limites](docs/CHANGEMENTS_0_10.md).

Les zones d’arrêt couvrent les quais OSM et les stations de transition disposent de **LAC + APS**, notamment dans les deux sens à Foch–Maison Bleue. Voir [0.9.3](docs/CHANGEMENTS_0_9_3.md).

Les 28 réseaux libres utilisent les voies physiques OpenStreetMap, leurs nœuds de connexion, les voies de service et les emprises de quais disponibles. Le décor IGN est étendu autour des nouveaux tracés ; les bâtiments de maintenance suivent les emprises BD TOPO. Les missions conservent leur graphe et leurs horaires GTFS, avec une altimétrie raccordée aux ouvrages cartographiés.

Le rendu corrige les stries d'ombre des rames, les raccords de terrain et les collisions de caméra. Les tunnels disposent de tubes, portails, éclairage proche et réverbération. Le HUD, les fenêtres et le catalogue s'adaptent aux petites fenêtres ; le plan accepte le pincement Android natif.

Voir [l'audit et ses limites](docs/AUDIT_0_8.md), [la couverture calculée](docs/world-quality.json) et [les sources](CREDITS.md). Sept familles disposent de captations libres, cinq utilisent une captation apparentée et huit une synthèse de remplacement explicitement indiquée. L'APK de développement utilise une clé de test ; une ancienne APK signée avec une autre clé doit être désinstallée avant installation.

La version 0.9 recale les arrêts sur les nœuds OSM, importe aussi les quais ouverts, rétablit les sections APS et ajoute LAC / rails APS visibles, départ en F3, pente au HUD, freinage sur coupure, limites locales en courbe et capture du défilement tactile. Voir [les changements et leurs limites](docs/CHANGEMENTS_0_9.md).

## Structure
- `src/catalogue` ressources versionnées (matériels, réseaux, lignes, stations)
- `src/simulation` physique, graphe de voies, aiguillages
- `src/modes` missions, mode libre
- `src/rendering`, `src/ui` rendu Compatibility et interface tactile
- `data/` données importées ; `tools/import` outils d'import et sources versionnées
- `tests/` : `godot --headless --path . -s tests/run_tests.gd`

## Compilation APK (vérifiée)
Godot 4.6.3 + modèles d'export, JDK 21, Android SDK (platform 36, build-tools 36.0.0, platform-tools). Réglages éditeur :
`export/android/android_sdk_path`, `java_sdk_path`, `debug_keystore(_user/_pass)`. Le projet doit avoir
`rendering/textures/vram_compression/import_etc2_astc=true` (sinon l'export échoue avec une erreur vide). Si `sdkmanager`/`java` affichent
« Picked up JAVA_TOOL_OPTIONS », faire `unset JAVA_TOOL_OPTIONS`. Commandes : `godot --headless --export-debug Android build/tramsim.apk` et `godot --headless --export-pack Windows build/win-x64/TramSimFrance.pck` (puis ajout du moteur signé via `tools/windows/prepare_runtime.py`, voir `docs/windows/LISEZMOI.md`).
Le workflow `.github/workflows/release.yml` exporte l’APK et les PCK Windows, ajoute le moteur officiel signé, construit les MSI natifs avec WiX 5, puis teste les paquets sur Windows x64 et ARM64 avant publication. Voir [l’installation Windows](docs/windows/LISEZMOI.md) et [la fabrication des MSI](installer/README.md).

## Ancienne note de compilation
Prérequis : Godot 4.6.3 + modèles d'export, JDK 17, Android SDK (platform 34, build-tools 34, NDK r28),
keystore de développement (`keytool -genkey -v -keystore dev.keystore -alias dev -keyalg RSA -keysize 2048 -validity 10000`).
Puis `godot --headless --export-debug Android build/tramsim.apk`. Voir `docs/ROADMAP.md`.

## Jouer
- **Mission horaire** : ville → ligne → service réel (GTFS) → matériel ; ponctualité évaluée à chaque arrêt.
- **Mode libre** : ville → station de départ → matériel. Toutes les lignes de la ville sont fusionnées (`data/free/`) ;
  le panneau **Plan** (touches M ou A) affiche le plan du réseau, l'itinéraire prévu et permet de choisir chaque branche.
- **Commandes** : manipulateur à gauche (ou Z/↑ et S/↓), X neutre, Espace urgence, O portes, K cloche, C caméra
  (glisser pour tourner, molette pour zoomer), M ou A plan, P alimentation, V changer de sens (aux terminus et terminus partiels, communication de voies en ciseaux), R remise sur voie, T trafic, Échap pause, F11 plein écran.
- **Matériels** : chaque réseau propose sa flotte (`data/rolling_stock/liveries.json`, rames générées depuis `data/rolling_stock/plans/`, ex. Citadis « arc-en-ciel » d'Irigo, TFS et Incentro à Nantes,
  TFS à Grenoble, Eurotram à Strasbourg) ; les autres matériels restent jouables (mode d'adaptation en mode libre).
- **Installation Windows** : `TramSimFrance-arm64.msi` sur Snapdragon/ARM64 ou `TramSimFrance-x64.msi` sur Intel/AMD ; ZIP portable disponible pour chaque architecture. Raccourci dans le menu Démarrer, installation pour le compte courant.

## Direction artistique
Low poly et cel shading (shaders `src/rendering/shaders/`) : facettes plates, éclairage en paliers, contours encrés des rames,
eau animée, fenêtres éclairées la nuit, lampadaires, phares. Cycle jour/nuit (`DayNight`) calé sur l'heure GTFS du service.
Rames générées par famille (Citadis, X05, Eurotram, Flexity, Translohr, Urbos, Avanto, Dualis, Incentro, Tango, Breda…)
avec livrées par réseau et par ligne. Décor réel BD TOPO IGN chargé par tuiles (`CityScene`).

## État actuel
- Réseaux livrés : **120 lignes et variantes de 29 réseaux français** importées des GTFS officiels — voir `docs/COUVERTURE.md`, `CREDITS.md`, `docs/SOURCES.md`.
- Import complet : `tools/import/fetch_gtfs.py`, `import_catalogue.py`, `build_index.py`, `merge_city.py` (réseaux libres), `turnbacks.py` (arrêts de retournement GTFS), `ign_scene.py` (décor BD TOPO v2 : bâtiments typés, monuments nommés, clochers), `stations.py` (types de stations et quais centrés, data/stations), `terrain.py` (relief RGE ALTI, profil en long des voies, ponts, plans d'eau ; ordre : stations.py, terrain.py, merge_city.py, turnbacks.py, terrain.py --free), `coverage_report.py`.
- Rames : `data/rolling_stock/` (recherche sourcée, plans, livrées) → `src/rendering/tram_model.gd` ; schéma `docs/rolling_stock_schema.md`.
- `tests/fixtures/schema_test.json` : petit réseau inventé servant uniquement aux tests.
- Tests : `GODOT=/chemin/godot tests/run_all.sh`. Captures : `xvfb-run godot --path . --rendering-driver opengl3 -s tests/screenshot.gd -- <dossier>`.
- Inventaire national : `docs/INVENTAIRE.md` (brouillon à vérifier).
