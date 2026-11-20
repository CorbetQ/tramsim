# Lot P0-C — instrumentation Android opt-in

Base de reprise : dc56265433e0f21be66d7011ed9a22bd6332c2b6 (Godot 4.6.3).
Les progrès concurrents du rendu sont conservés ; voir RESUME_ANDROID.md.
Ce lot n'applique pas les 20 fonctionnalités en bloc et ne fusionne pas les PR #14/#15.

## Ce qui est implémenté

- Autoload `PerformanceProbe` : aucune collecte sans requête explicite. Sans requête,
  le nœud se supprime après démarrage. Ni téléchargement, ni réseau, ni IA dans le jeu.
- Scénario : chargement, conduite, caméra libre indépendante, nuit, pluie si disponible,
  terminus. La physique, le pilote automatique, FreeSession et FreeCamera existants sont
  réutilisés. La propriété de caméra réutilise le mécanisme de la cinématique.
- Pas fixe 1/60 s et graine explicite pendant le benchmark uniquement ; limite de rattrapage
  de 240 pas par frame, backlog consigné sans effacement silencieux. La boucle normale du
  jeu reste inchangée lorsqu'aucun benchmark n'est actif. Aucun replay rendu bit-identique
  n'est revendiqué : le streaming asynchrone et les frames dépendent du matériel.
- JSON/CSV : frametimes muraux, FPS P50/P95/P99 calculés sur les FPS individuels (pas
  l'inverse d'un percentile de frametime), temps CPU de traitement Godot, GPU si disponible,
  allocations statiques, appels de rendu, objets/nœuds/ressources, événements et trajet.
- Échauffement exclu configurable et comptabilisé, mémoire bornée à 20 000 frames,
  arrêt explicite en cas de limite ou passage en arrière-plan. Pas de zéros inventés pour
  les compteurs non disponibles ; phases sans samples : percentiles null.
- Budgets configurables, mesurés et évalués par phase, jamais présentés comme une promesse.
- Identité du build embarquée par la CI (`tools/perf/write_build_info.py`), empreinte réseau,
  modèle/OS/backend et mode d'alimentation déclaré. Un build local non estampillé reste
  explicitement non identifié. Les timesteps, la qualité et le réseau sont dans la requête.
- Contrôleur ADB local : appareil autorisé/debuggable, requête one-shot par `run-as`,
  extraction des rapports, batterie/thermique/mémoire disponibles et comparaison A/B.
  Le processus externe ne lance aucune commande fournie dans la requête JSON.
- Sauvegardes : données éphémères au démarrage d'un benchmark, écritures de profil
  centralisées et bloquées, persistance à la fermeture bloquée, entrées utilisateur ignorées
  pour ne pas modifier le protocole. Le scénario n'écrit jamais la progression du joueur.

## Résultats réellement exécutés

Godot 4.6.3 installé et import sans erreur de script. 24 assertions Godot et 11 tests
Python ciblés réussis, avec vérification du mode désactivé :

```sh
godot --headless --path . -s tests/test_performance_disabled.gd
godot --headless --path . -s tests/test_performance_telemetry.gd
python -m unittest discover -s tests -p test_android_benchmark.py
python tools/perf/run_headless_smoke.py --output .cache/p0/smoke
```

Le smoke exécute le véritable jeu dans un projet et un répertoire utilisateur de test
isolés. Une sauvegarde v1 avec progression et extension inconnue est injectée ; ses
**octets avant/après sont identiques**. Chargement/conduite/caméra/nuit/terminus exécutés,
JSON/CSV réellement produits, pluie explicitement `skipped`. GPU null en headless.
Les tests existants `test_save`, `test_adhesion`, `test_power_routing`,
`test_autopilot`, `test_lod_shutdown` et `test_app_close` passent également dans un
profil utilisateur distinct. Reçu : `android-smoke/regression-checks.json`.
Les reçus de `android-smoke/` sont des preuves d'exécution de la chaîne desktop headless,
**pas des performances Android**. Les tests synthétiques restent marqués comme fixtures.

ADB disponible, `adb devices` sans appareil connecté. Aucun essai physique, aucune
mesure de consommation réelle, aucun objectif de FPS sur deux gammes n'est validé.
La CI ajoutée vérifie l'import, les fixtures, le mode désactivé et le vrai smoke.
Les résultats Linux/Windows des migrations de la PR #14 ne sont pas assimilés à un
benchmark Android de cette PR. Les limites de stockage GitHub ne justifient pas la
suppression d'anciens artefacts : les petits reçus utiles sont versionnés ici.

## Requête et exécution

Exemple de requête locale (chemin passé après `--`) :

```json
{"schema_version":1,"run_id":"baseline_device_a","request_id":"r_unique_01",
 "network":"res://data/free/angers.json","phase_seconds":8,"warmup_frames":10,
 "seed":7,"phases":["dense_driving","free_camera","night","rain","terminus"],
 "gpu_timing":true,"view_distance":400,"power_mode":"balanced",
 "budgets":{"frametime_p95_ms":33.3333,"draw_calls":1500}}
```

Ces budgets sont des objectifs de configuration, pas une mesure ni une garantie de
30 FPS. Choisir un run_id inédit. Le collecteur refuse de remplacer un ancien rapport.
Sorties : `user://benchmarks/<run_id>.json` et `.csv`. Publication du JSON après le CSV.
Les requêtes ne prennent ni script, ni commande, ni réseau externe. Le fichier one-shot
Android `user://benchmark_request.json` est consommé après validation.

```sh
godot --path . -- --perf-request=res://.cache/my_request.json
python tools/perf/android_benchmark.py --adb /chemin/adb devices
```

Android physique, après installation d'une APK debug de cette branche et autorisation
ADB par son propriétaire : terminer la partie en cours avant `--restart`, qui arrête
explicitement l'application. Le contrôleur conserve localement les octets initiaux du
profil et compare leur empreinte après exécution ; il ne restaure rien silencieusement.

```sh
python tools/perf/android_benchmark.py --adb /chemin/adb capture --serial APPAREIL --restart --run-id baseline_device_a --output .cache/android/baseline_device_a --power-mode balanced --gpu-timing
python tools/perf/android_benchmark.py --adb /chemin/adb capture --serial APPAREIL --restart --run-id candidate_device_a --output .cache/android/candidate_device_a --power-mode balanced --gpu-timing
python tools/perf/android_benchmark.py compare .cache/android/baseline_device_a/capture.json .cache/android/candidate_device_a/capture.json --output .cache/android/comparison.json
```

L'exécution A/B exige même appareil/OS, réseau, paramètres, alimentation et couverture
mesurée. Build et assets doivent être examinés : une scène différente n'est pas une
optimisation démontrée. Les empreintes et les positions sont fournies ; l'inventaire
complet de tous les assets n'est pas un fingerprint certifié du workload.
Le détecteur distingue les indices d'émulateur ; Android seul ne prouve pas un appareil
physique. Étiqueter deux gammes avec preuves matérielles avant toute conclusion générale.

Les snapshots ADB sont externes (~2 s), ajoutent une charge non soustraite, et leur
format dépend du système. Température batterie ≠ SoC ; allocations Godot ≠ PSS/RSS ;
current_now/voltage_now concernent la batterie entière, pas la consommation de l'app.
Une permission refusée ou un compteur absent reste indisponible, jamais une mesure zéro.
Le fichier `save-before.private.json` éventuel reste local : ne pas le commettre.

## Couverture et limites

Le point de départ est la première arête du graphe ; le label dense_driving ne certifie
pas le maximum de densité urbaine. Choisir des réseaux/scénarios de référence documentés
pour des comparaisons de densité concluantes. Le terminus est un endpoint topologique,
pas un quai commercial certifié. La pluie n'est pas simulée par ce lot : phase sautée,
sans fabriquer un effet météo ni des mesures. Le benchmark fixe la simulation, pas les
horaires exacts de l'IA (autre lot). L'identité de build manque avant estampillage.
Les modes de chargement/source-fingerprint contribuent au temps loading ; appliquer
exactement le même protocole pour une baseline et un candidat.

## Retour arrière

Revert du commit P0-C : retirer l'autoload et ses fichiers/outils, le booléen de délégation
et le garde de persistance dans Main, l'étape d'estampillage de build. Aucune migration
n'est nécessaire pour les sauvegardes normales, aucun réseau/asset n'est modifié. Les
rapports utilisateur peuvent être conservés hors du jeu. Les deux autres lots sont
indépendants. Aucune fusion automatique ni publication de release n'est effectuée ici.
