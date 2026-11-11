# Tram Sim France

Simulateur de tramway 3D (Godot 4.6.3, GDScript, Android 10+, paysage, hors ligne).

## Structure
- `src/catalogue` ressources versionnées (matériels, réseaux, lignes, stations)
- `src/simulation` physique, graphe de voies, aiguillages
- `src/modes` missions, mode libre
- `src/rendering`, `src/ui` rendu Compatibility et interface tactile
- `data/` données importées ; `tools/import` chaîne d'import reproductible
- `tests/` : `godot --headless --path . -s tests/run_tests.gd`

## Compilation APK
Prérequis : Godot 4.6.3 + modèles d'export, JDK 17, Android SDK (platform 34, build-tools 34, NDK r28),
keystore de développement (`keytool -genkey -v -keystore dev.keystore -alias dev -keyalg RSA -keysize 2048 -validity 10000`).
Puis `godot --headless --export-debug Android build/tramsim.apk`. Voir `docs/ROADMAP.md`.

## État actuel
`data/networks/angers_a.json` est un **schéma provisoire** (noms et distances inventés), pas la vraie ligne A.
Tests : `GODOT=/chemin/godot tests/run_all.sh` (Godot headless + Python). Import : `tools/import/` (OSM, GTFS, validateur).
Inventaire national : `docs/INVENTAIRE.md` (brouillon à vérifier).
