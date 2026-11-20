# Rust, météo, effets et mode passager — première tranche

Base : dc56265433e0f21be66d7011ed9a22bd6332c2b6, Godot 4.6.3.
Branche : codex/rust-weather-passenger. Pas de fusion automatique.
Le checkout de rendu modifié et les données cartographiques de Claude sont conservés.

## Périmètre réellement implémenté

Ce lot démarre une migration progressive, **pas une réécriture complète du jeu en Rust**.
Godot conserve rendu, interfaces, imports et exports ; la dynamique longitudinale
et l'évolution numérique de la météo disposent maintenant d'une implémentation Rust
réellement compilée et appelée par GDExtension. Routage, IA, modes et UI restent GDScript.
Le repli GDScript conserve le jeu utilisable sans bibliothèque native installée.
L'intégration des bibliothèques natives aux APK/EXE de release reste une étape distincte.

- `native/core` : noyau Rust sans dépendance, IO, réseau ou objets Godot.
- `native/godot` : adaptateur godot-rust 0.4.5, API 4.3 compatible avec Godot 4.6.3.
- `NativeSimulation` : détection de classe/ABI, option de désactivation et repli.
- `TrainPhysics` : même API publique, paramètres et équations, backend Rust si disponible.
  Les anciens modèles, données et sauvegardes ne sont pas remplacés.
- `WeatherState` : sec, pluie, brouillard, forte pluie, cycle dynamique à graine fixe.
  Transitions progressives, humidification puis séchage lent, adhérence estimée 0.26–0.12.
  Une mission déjà glissante reste glissante ; la météo ne supprime pas ses conditions.
  Les événements locaux (feuilles/inondation) continuent de s'appliquer.
- Météo utilisée en conduite, exploration et passager. Choix dans Réglages ; état et RNG
  conservés avec le checkpoint libre, sans changer la version du format SaveGame.
- `WeatherView` : précipitations proches bornées (160 mobile / 320 desktop), brouillard,
  ciel couvert et atténuation du soleil ; précipitations masquées à bord/en tunnel de conduite.
- `VisualEffects` : profils économie, équilibré, cinématique. Économie par défaut mobile.
  Une sonde de réflexion locale en mode UPDATE_ONCE, déplacement >60 m / délai 12 s.
  Reflets PBR sur le vitrage intérieur ; SSR uniquement si le jeu utilise Forward+.
  Aucun changement forcé de renderer : Compatibility reste le défaut Android/PC.
  Halo LDR discret en Compatibility, glow HDR existant conservé sur les backends compatibles.
  Flou directionnel de caméra facultatif, avant HUD, coupé lors des sauts de caméra.
  **Ce n'est pas un motion blur par objet à vecteurs de mouvement, ni un reflet universel des routes.**
- `AiTramView` : culling par sphère/frustum conservateur ; LOD distant simplifié avec
  hystérésis 170/205 m ; la rame occupée conserve le détail. Simulation et réservations
  continuent hors champ. Les anciens LOD/streaming de la ville sont réutilisés.
- Intérieurs construits seulement pour une rame visitée : sols, plafonds, sièges,
  montants, barres, vitrage et éclairage local, géométrie répétitive en MultiMesh.
  Variante de coque passager avec intercirculations ouvertes et couche extérieure
  distincte ; modèle extérieur historique conservé par défaut.
- Mode passager depuis l'accueil : marche à hauteur humaine, regard souris/tactile,
  commandes tactiles, proximité des bâtiments contrôlée par les volumes existants,
  évitement des caisses proches, montée/descente uniquement à proximité d'une porte
  ouverte et à l'arrêt. La caméra suit les modules articulés de la **véritable rame IA**.
  Marche dans l'allée, sièges proches utilisables. Moteur audio existant réutilisé à bord,
  avec libération des voix à la descente. Pas de duplication du trafic tramway.
  L'horloge passager respecte les heures fixes et le cycle normal/accéléré des réglages.

## Utilisation

Godot 4.6.3 suffit pour le backend GDScript. Installer Rust via rustup (profil minimal)
pour le backend natif ; version réellement utilisée ici : rustc 1.100.0.
Les dépendances sont gratuites et verrouillées dans `native/Cargo.lock`.

```sh
cargo test --manifest-path native/Cargo.toml --locked -p tramsim-core
python tools/build_native.py --release
godot --headless --path . --import
python tools/qa/run_godot_check.py tests/test_native_weather.gd -- --require-native
godot --path .
```

Réglages → Météo et Effets ; accueil → Mode passager.
ZQSD/WASD : marche ; bouton droit + souris : regard ; E : monter/descendre ; F : siège ;
Échap : accueil. Sur mobile : flèches de marche, glisser hors des boutons pour regarder,
boutons de montée/descente et de siège. Le service existant s'arrête et ouvre ses portes.
Le menu « Stations » permet de rejoindre un arrêt à pied (hors rame).

Le descripteur et les binaires générés sont ignorés sous `addons/tramsim_native/`.
Installation atomique ; redémarrer Godot après compilation. Pour désactiver, fermer
Godot, lancer `python tools/build_native.py --disable`, puis réimporter le projet.
Le dossier généré appartient uniquement à cet outil ; les autres addons restent intacts.

Cross-compilation Android ARM64, avec cible Rust et NDK préalablement installés :

```sh
rustup target add aarch64-linux-android
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=/chemin/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang
python tools/build_native.py --release --target aarch64-linux-android
```

Le descripteur conserve les entrées déjà installées pour les autres plateformes.
Une DLL Windows doit être construite sur Windows ou avec sa chaîne de cross-compilation.
Les exports actuels continuent d'utiliser le repli tant que la bibliothèque correspondante
n'est pas assemblée et validée. Les MSI devront également inclure bibliothèques et notices.

## Tests et preuves

- 6 tests Rust : pente/F3/recul, traction hors tension, patinage/sablage, frein d'urgence,
  entrées invalides et séchage du rail.
- `test_native_weather.gd` : 15 vérifications avec natif, dont concordance sur 6 000 pas
  Rust/GDScript (pentes, freinage, alimentation, adhérence, sablage), concordance météo,
  restauration RNG, séchage, marche et conditions de montée.
- `test_passenger_mode.gd` : véritable réseau et IA d'Angers ; montée, déplacement de la
  rame portant le passager, sièges, descente, voix audio et culling ; captures OpenGL.
- `test_passenger_families.gd` : construction des 20 plans de familles, sièges dans le
  gabarit et instanciation. Ce test ne certifie ni l'aménagement réel ni tous les trajets.
- Tests existants d'adhérence et d'alimentation réussis avec le noyau Rust.
- Tests existants des matériels roulants réussis. Menu, réglage météo, lancement réel,
  sauvegarde du checkpoint météo et préservation d'une extension inconnue vérifiés
  dans un profil utilisateur isolé (6 contrôles). Repli dans une copie fraîche sans
  extension native également exécuté : backend GDScript, 13 contrôles réussis.
- Import Godot et rendu OpenGL exécutés. Captures sous Xorg dummy/Mesa llvmpipe,
  **pas des performances sur une carte graphique ou un téléphone de joueur**.
- Microbenchmark CPU : 3 × 30 000 pas, médiane GDScript 94.731 ms / Rust 74.969 ms
  dans cet environnement. Cela concerne uniquement cette fonction et les appels de
  frontière ; aucune augmentation des FPS du jeu n'en est déduite.
- Comptage géométrique des intérieurs : 2 082 meshes potentiels regroupés en 921
  groupes sur les 20 familles ; module testé à Angers 31 → 12. Ce sont des groupes de
  géométrie, pas une mesure du nombre de passes GPU ni du framerate.
- CI dédiée : repli sans extension, compilation Rust et tests Linux, rendu passager,
  compilation/chargement Windows, cross-compilation et contrôle ELF Android ARM64.
  Son statut réel doit être consulté dans la PR ; une cross-compilation ne teste pas Android.

Reçus et captures : `rust-weather-passenger/`. Les images sont des captures du jeu,
non des références photographiques. La scène de pluie est mise en condition par le test.

## Limites et suite de la migration

Le dépôt et les cartes ne sont pas remodélisés ici. Les intérieurs sont **procéduraux et
estimés depuis les enveloppes/portes existantes**, sans validation photographique par
famille. Aucun asset Meshy n'a été acquis, aucun crédit payant dépensé. La fidélité des
sièges, des habillages et des postes de conduite nécessite encore des références dédiées.

La marche utilise les hauteurs IGN et les obstacles de caméra disponibles, pas encore
un monde physique complet avec trottoirs, escaliers, tabliers superposés, eau et véhicules
solides exhaustifs. Les surfaces de pont restent à traiter avec le contrat de collision
du chantier cartographique. Les pannes/régulations de l'IA existante peuvent terminer un
service : le passager repasse alors à pied, sans nouvelle rame fictive.

La pluie ne tient pas compte de chaque auvent et le lot n'ajoute ni essuie-glaces,
ni sons de pluie dédiés, ni vent simulé, ni textures de chaussée mouillée. Les reflets
de voirie et les occluders cartographiques demanderont une interface convenue avec
les nouveaux matériaux/volumes de Claude. Les effets ont un coût ; pas de promesse FPS.

Les étapes suivantes de la réécriture Rust sont les modules de graphe/routage, les
sessions et événements, puis les adaptateurs de données. Chacun doit conserver un
oracle de comparaison avant bascule ; transférer immédiatement l'UI et le rendu
abandonnerait les systèmes Godot existants et n'est pas réalisé par cette tranche.

## Licences et retour arrière

Voir `native/THIRD_PARTY.md`, les textes sous `native/licenses/` et le relevé des
dépendances. godot-rust/API sont MPL-2.0, pas MIT ; les sources correspondantes et
notices sont requises lors de la distribution native. Les assets du jeu gardent leurs crédits.

Retour arrière : désactiver le backend natif et conserver GDScript, choisir Temps sec /
Économie, puis revert de ce lot si nécessaire. Aucun fichier de carte ou ancienne banque
audio supprimé. Les champs météo additionnels du checkpoint sont ignorables par l'ancien jeu.
Les PR P0 #14/#15/#16 restent indépendantes et ne sont pas fusionnées ici.
