# Tram Sim France

Simulateur de tramway 3D (Godot 4.6.3, GDScript, Android 10+, paysage, hors ligne).

## Structure
- `src/catalogue` ressources versionnées (matériels, réseaux, lignes, stations)
- `src/simulation` physique, graphe de voies, aiguillages
- `src/modes` missions, mode libre
- `src/rendering`, `src/ui` rendu Compatibility et interface tactile
- `data/` données importées ; `tools/import` chaîne d'import reproductible
- `tests/` : `godot --headless --path . -s tests/run_tests.gd`

## Compilation APK (vérifiée)
Godot 4.6.3 + modèles d'export, JDK 21, Android SDK (platform 36, build-tools 36.0.0, platform-tools). Réglages éditeur :
`export/android/android_sdk_path`, `java_sdk_path`, `debug_keystore(_user/_pass)`. Le projet doit avoir
`rendering/textures/vram_compression/import_etc2_astc=true` (sinon l'export échoue avec une erreur vide). Si `sdkmanager`/`java` affichent
« Picked up JAVA_TOOL_OPTIONS », faire `unset JAVA_TOOL_OPTIONS`. Commandes : `godot --headless --export-debug Android build/tramsim.apk` et `godot --headless --export-release Windows build/TramSimFrance.exe`.
Le workflow `.github/workflows/release.yml` compile et publie automatiquement l'APK, l'EXE et le MSI (`installer/tramsim.wxs`, wixl) dans une Release GitHub.

## Ancienne note de compilation
Prérequis : Godot 4.6.3 + modèles d'export, JDK 17, Android SDK (platform 34, build-tools 34, NDK r28),
keystore de développement (`keytool -genkey -v -keystore dev.keystore -alias dev -keyalg RSA -keysize 2048 -validity 10000`).
Puis `godot --headless --export-debug Android build/tramsim.apk`. Voir `docs/ROADMAP.md`.

## Jouer
- **Mission horaire** : ville → ligne → service réel (GTFS) → matériel ; ponctualité évaluée à chaque arrêt.
- **Mode libre** : ville → station de départ → matériel. Toutes les lignes de la ville sont fusionnées (`data/free/`) ;
  le panneau **Aiguillages** (touche A) affiche le plan du réseau, l'itinéraire prévu et permet de choisir chaque branche.
- **Commandes** : manipulateur à gauche (ou Z/↑ et S/↓), X neutre, Espace urgence, O portes, K cloche, C caméra
  (glisser pour tourner, molette pour zoomer), M carte, P pantographe, A aiguillages, R remise sur voie, T trafic, Échap pause, F11 plein écran.
- **Matériels** : chaque réseau propose sa flotte (`data/liveries.json`, ex. Citadis « arc-en-ciel » d'Irigo, TFS et Incentro à Nantes,
  TFS à Grenoble, Eurotram à Strasbourg) ; les autres matériels restent jouables (mode d'adaptation en mode libre).
- **Installation Windows** : `TramSimFrance.msi` (raccourcis menu Démarrer et Bureau) ou l'exécutable portable.

## Direction artistique
Low poly et cel shading (shaders `src/rendering/shaders/`) : facettes plates, éclairage en paliers, contours encrés des rames,
eau animée, fenêtres éclairées la nuit, lampadaires, phares. Cycle jour/nuit (`DayNight`) calé sur l'heure GTFS du service.
Rames générées par famille (Citadis, X05, Eurotram, Flexity, Translohr, Urbos, Avanto, Dualis, Incentro, Tango, Breda…)
avec livrées par réseau et par ligne. Décor réel BD TOPO IGN chargé par tuiles (`CityScene`).

## État actuel
- Réseaux livrés : **120 lignes et variantes de 29 réseaux français** importées des GTFS officiels — voir `docs/COUVERTURE.md`, `CREDITS.md`, `docs/SOURCES.md`.
- Import complet : `tools/import/fetch_gtfs.py` puis `import_catalogue.py`, `build_index.py`, `coverage_report.py` (catalogue : `data/sources/gtfs_catalogue.json`).
- `tests/fixtures/schema_test.json` : petit réseau inventé servant uniquement aux tests.
- Tests : `GODOT=/chemin/godot tests/run_all.sh`. Captures : `xvfb-run godot --path . --rendering-driver opengl3 -s tests/screenshot.gd -- <dossier>`.
- Inventaire national : `docs/INVENTAIRE.md` (brouillon à vérifier).
