# Audit et révision 0.8

Revue du dépôt privé `CorbetQ/tramsim`, à partir de `3d05c732` (0.7). Les changements sont isolés dans `codex/world-audio-mobile-overhaul`.

## Résultat livré

- 28 réseaux libres reconstruits sur les axes et les nœuds de voies OpenStreetMap : **14 205 sections**, dont **3 924 de service**. Les connexions suivent les identifiants OSM ; un simple voisinage ou un croisement ne crée plus un aiguillage.
- **1 485 emprises de quai**, **90 sites de dépôt ou faisceaux** (plusieurs peuvent appartenir au même établissement), **142 bâtiments de maintenance distincts** dont les emprises et hauteurs sont issues de BD TOPO.
- **677 tuiles de décor IGN ajoutées**, avec voirie, bâti, eau et végétation autour des nouvelles voies. Le relief est étendu aux secteurs manquants.
- Les 120 fichiers de lignes commerciales conservent le graphe et les horaires GTFS. Leur profil vertical et leurs ouvrages sont rapprochés du réseau physique. Les axes horizontaux GTFS restent une limite : **42 590 sommets sur 285 073** sont à plus de 25 m des voies disponibles dans l'extrait utilisé. Les lignes concernées sont listées dans `world-quality.json` ; il ne s'agit pas d'une reconstitution exhaustive au mètre près de toutes les missions.

## Défauts constatés et corrections

| Priorité | Constat dans la 0.7 | Correction / comportement 0.8 |
|---|---|---|
| P0 | Les réseaux libres fusionnaient des tracés commerciaux et des raccordements estimés ; les voies de service manquaient. | Graphe de voies physiques OSM, vrais embranchements cartographiés, distinction des losanges sans aiguille, recherche de dépôts et points de départ en remisage. |
| P0 | Les valeurs MNT absentes devenaient zéro. | Petits trous interpolés depuis une mesure valide ; import refusé si plus de 20 % d'une dalle manque. |
| P0 | Les tuiles de relief quantifiaient séparément leurs hauteurs, avec jusqu'à **1,78 m** d'écart sur une frontière. | Format TTR2 float32 et sommets communs soudés ; le test compare les bords de toutes les tuiles. La résolution d'origine reste environ 10 m. |
| P0 | L'altitude d'un pont était interpolée selon l'indice des sommets. | Interpolation selon les distances. Les profils des voies utilisent les altitudes Z BD TOPO disponibles ; les rampes estimées sont bornées sur le graphe entier. |
| P0 | Une route pouvait récupérer le plus haut tablier voisin, y compris un pont qui la croise. | Le drapage choisit un ouvrage de même type, aligné avec la route. |
| P0 | Les tunnels courts ou sous une faible couverture n'avaient pas de tube ; des déblais profonds étaient assimilés à des tunnels. | Ouvrages d'après les attributs cartographiés, tubes et portails, ouvertures du terrain, phares et quatre lumières proches, ambiance intérieure et réverbération. Les nouveaux imports ne déduisent plus un tunnel de la seule profondeur d'un déblai. |
| P0 | La caméra pouvait entrer dans un arbre ou un bâtiment et masquer presque toute la scène. | Rapprochement automatique de la caméra avant l'obstacle et distance adaptée en tunnel. |
| P1 | Stries d'ombre sur les rames et les rubans de voie. | Normales de facette fournies aux maillages pour le biais des ombres. Les vues OpenGL avant/après confirment la disparition des stries. |
| P1 | La transformation du décor entre repères de lignes ne corrigeait que la translation. | Échelle est/ouest corrigée avec la latitude, y compris pour les requêtes de relief et les zones de dégagement. |
| P1 | Le son reposait sur une raie 300–1 000 Hz, des harmoniques et une porteuse à 1 050 Hz. | Timbre électromécanique plus grave, régimes 140–620 Hz, porteuse atténuée, transitions amorties, grave moteur renforcé et joints moins fréquents. |
| P1 | L'APS coupait le son de traction avec le pantographe baissé. | L'alimentation effective et le mode de captage pilotent le son. La bascule cabine/extérieur conserve aussi les sons ponctuels. |
| P1 | HUD, aperçu de rame et fenêtres à tailles fixes. | Dimensions logiques adaptées à la densité, HUD compact, marges de sécurité Android, ruban défilant, menus, catalogue, fiches et fenêtres scrollables. Les boutons et conteneurs laissent passer le début du geste, et les listes de choix s’ouvrent au relâchement. Icônes SVG importées en plus haute définition. |
| P1 | Le plan mélangeait glisser natif et souris tactile émulée ; le pincement Android était absent. | Propriété du geste par doigt, sélection au relâchement, annulation après glisser/pincer, zoom ancré et liste repliable sur petit écran. |
| P1 | Les quais étaient systématiquement déplacés pour créer des îlots, même sur une géométrie physique. | Les emprises OSM remplacent les quais estimés disponibles ; les voies physiques ne sont pas écartées artificiellement. |
| P1 | Certains tests pouvaient masquer un échec Python ou un compteur de missions en erreur. | Codes de sortie et erreurs de script propagés, contrôles de géographie, de jonctions et d'interface ajoutés. |

## Limites conservées et suite recommandée

1. **Recaler les itinéraires des missions sur les voies physiques**, avec itinéraires orientés, prises d'aiguillages et horaires indépendants de la géométrie. Le rapprochement vertical actuel préserve la jouabilité des horaires et expose les écarts ; il ne remplace pas ce travail de routage.
2. **Vérifier les profils ferroviaires et les ouvrages sensibles** : RGE ALTI est un modèle du sol, BD TOPO fournit des mesures dont la précision varie. Certaines altitudes sont interpolées et lissées ; le rapport indique l'ajustement maximal par réseau, jusqu'à 9,324 m dans les données estimées d'Île-de-France. Un tablier ne doit pas être présenté comme un relevé de rail certifié.
3. **Compléter les sites non documentés et les voies non cartographiées**. Les faisceaux sont jouables, les bâtiments sans hauteur exploitable ne sont pas inventés. Les façades, portails et intérieurs de hangar restent stylisés.
4. **Importer la signalisation et le trafic d'exploitation**. Les simulations existent, mais les fichiers de cartes n'offrent pas une implantation réelle complète des signaux et des circulations automobiles.
5. **Constituer une bibliothèque sonore par famille** à partir d'enregistrements réutilisables. Les nouveaux sons restent des synthèses originales, sans promesse de reproduction exacte d'un Citadis, d'un TFS ou d'un Urbos.
6. **Stabiliser la signature Android de distribution**. La compilation CI existante génère une clé de développement à chaque exécution ; elle ne permet pas une mise à jour signée compatible avec toutes les anciennes APK. La clé locale de test reste hors du dépôt. La reprise de sauvegarde entre graphes anciens et nouveaux nécessite également une migration dédiée.
7. **Mesurer les performances sur plusieurs appareils Android** : les essais de rendu OpenGL et les petites fenêtres ne remplacent pas des mesures de température, de mémoire et de fréquence d'images sur téléphone réel.

## Vérification

- Missions : les 120 services de contrôle terminent sans échec (`TOTAL_ECHECS|0`).
- Données : 149 réseaux et fixtures validés ; extrémités physiques conformes aux nœuds OSM, continuité des jonctions et des bords de terrain contrôlée.
- Audio : chargement, pause, changements de régime, APS et changements de vue testés.
- Interface : clics et gestes dans des fenêtres 640×360, 800×450 et 1280×720, ouverture des panneaux, commandes et placement des fenêtres.
- Exports : APK Android arm64 et EXE Windows x64 avec Godot 4.6.3. La validation finale et les empreintes des exécutables figurent dans les artefacts de construction.

Les sources compressées, requêtes, dates de base et empreintes sont répertoriées dans `world-quality.json`. Les archives de sources restent dans Git et sont exclues du jeu exporté. Le jeu fonctionne hors ligne. Les caches de téléchargement et la clé de test ne sont pas versionnés.

## Couverture calculée

| Ville | Sections | Service | Quais OSM | Dépôts / faisceaux | Bâtiments de maintenance | Tuiles ajoutées |
|---|---:|---:|---:|---:|---:|---:|
| Angers | 326 | 64 | 0 | 1 | 2 | 0 |
| Aubagne | 71 | 21 | 6 | 1 | 1 | 16 |
| Avignon | 96 | 31 | 2 | 1 | 0 | 0 |
| Besançon | 165 | 0 | 0 | 1 | 1 | 0 |
| Bordeaux | 907 | 279 | 19 | 3 | 7 | 12 |
| Brest | 326 | 67 | 76 | 1 | 4 | 0 |
| Caen | 225 | 51 | 2 | 1 | 1 | 0 |
| Clermont-Ferrand | 173 | 85 | 0 | 1 | 1 | 0 |
| Dijon | 163 | 63 | 17 | 1 | 3 | 5 |
| Grenoble | 671 | 198 | 116 | 2 | 6 | 6 |
| Île-de-France | 3055 | 761 | 478 | 26 | 41 | 64 |
| Le Havre | 101 | 57 | 42 | 3 | 3 | 0 |
| Le Mans | 305 | 56 | 14 | 3 | 2 | 0 |
| Lille | 341 | 95 | 63 | 1 | 3 | 22 |
| Lyon | 1442 | 357 | 17 | 6 | 10 | 65 |
| Marseille | 270 | 137 | 12 | 3 | 2 | 0 |
| Montpellier | 781 | 217 | 48 | 4 | 6 | 9 |
| Mulhouse | 196 | 47 | 63 | 1 | 1 | 5 |
| Nantes | 1131 | 347 | 13 | 4 | 6 | 461 |
| Nice | 366 | 152 | 90 | 3 | 6 | 0 |
| Orléans | 256 | 96 | 8 | 2 | 3 | 0 |
| Reims | 192 | 47 | 13 | 1 | 1 | 0 |
| Rouen | 238 | 102 | 54 | 1 | 10 | 0 |
| Saint-Étienne | 178 | 57 | 7 | 1 | 1 | 0 |
| Strasbourg | 1467 | 344 | 195 | 14 | 14 | 9 |
| Toulouse | 261 | 56 | 48 | 1 | 2 | 0 |
| Tours | 236 | 38 | 8 | 1 | 1 | 3 |
| Valenciennes | 266 | 99 | 74 | 2 | 4 | 0 |
