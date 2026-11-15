# TramSim Audio Studio

Chaîne de production locale. Le jeu n'utilise ni Python, ni API, ni inférence IA.
Point d'intégration conservé : `src/audio/tram_audio.gd`.

## Installation

Python 3.12, FFmpeg/ffprobe, Godot 4.6.3 ; GCC + ALSA + flock uniquement pour les
captures Linux. Dépendances Python : `tools/audio/requirements.txt` (NumPy/SciPy).

```sh
python -m venv .venv-audio
. .venv-audio/bin/activate
python -m pip install -r tools/audio/requirements.txt
python tools/audio/studio.py doctor
python tools/audio/studio.py --help
```

Les dépendances ont été trouvées et réellement utilisées dans l'environnement de
livraison, sans installation de torch ni de poids. Sur un disque saturé, placer
l'environnement et le checkout sur un volume disposant d'espace. Les captures WAV
occupent environ 9 Mo par scénario ; les caches originaux peuvent être bien plus gros.
Le traitement nécessite NumPy/SciPy ; recherche/licences utilisent la bibliothèque
standard. Aucun abonnement requis. Le réseau ne sert qu'aux recherches/téléchargements.

## Recherche et droits

```sh
python tools/audio/studio.py research --family all --limit 2
python tools/audio/studio.py search commons 'Citadis 302' --limit 3 --output .cache/audio-studio/results.json
python tools/audio/studio.py inspect 'File:Alstom Citadis 302 in Moscow.webm' --output .cache/audio-studio/moscow.json
python tools/audio/studio.py fetch .cache/audio-studio/moscow.json --family citadis_302 --event traction --kind recorded_exact
```

`inspect` affiche auteur, licence, URL légale et métadonnées officielles. `fetch`
revérifie via le fournisseur (nouvelle vérification des métadonnées avant téléchargement), refuse une licence
inconnue, NC, ND ou nouvelle BY-SA et télécharge **l'original**, sans substituer une
version réduite. Budget par téléchargement : 128 Mio. Le contenu est sondé avant
publication atomique ; cache adressé par SHA-256, `.part` effacé après interruption,
redémarrage complet plutôt qu'une reprise Range non vérifiable. Le cache existant
est rehaché avant réutilisation. User-Agent descriptif, temporisation, retries
bornés et Retry-After (attente longue : arrêt explicite, sans réessayer trop tôt). Le verrou du Studio sérialise les commandes du même checkout.

Les résultats de recherche ne certifient pas le modèle : Commons peut renvoyer une
rame différente ou une vidéo sans intérêt sonore. La validation humaine des
images, du contexte et du son reste obligatoire avant une affectation de famille.
Les durées Commons viennent de videoinfo quand disponibles, pas d'une hypothèse
sur imageinfo. Les CC0 publiées avec une ancienne URL HTTP de licence sont reconnues ;
les téléchargements de médias restent exclusivement HTTPS vers les hôtes autorisés.

Freesound : définir `FREESOUND_API_KEY` pour la recherche officielle. Les originaux
nécessitent **aussi** un jeton OAuth `FREESOUND_ACCESS_TOKEN` ayant l'autorisation
requise. Jamais de clé dans Git ni dans les commandes de documentation.

```sh
python tools/audio/studio.py search freesound 'tram doors' --min-duration .3 --max-duration 12
# Sélectionner une seule entrée officielle dans candidate.json, puis :
python tools/audio/studio.py fetch candidate.json --family generic --event door_open
# --preview : consentement explicite à un aperçu autorisé par l'API ; qualité marquée lossy_preview.
```

Kenney, OpenGameArt et Europeana sont proposés en mode **revue uniquement** :
`search kenney interface`, `search opengameart tram`, `search institutional railway`.
Pas d'API de téléchargement stable vérifiée, donc aucun téléchargement automatique
à partir de ces liens. Le pack Kenney déjà intégré conserve sa licence CC0 et son
crédit. Les anciennes banques BY-SA restent présentes avec leurs obligations ; elles
ne deviennent pas CC0 par leur import dans le catalogue.

## Catalogue unique et traitement

`data/audio/sources.json` → `catalogue` est l'autorité pour les **octets actuels**,
licences, classification et mesures. `files`, `segments` historiques et autres
manifestes préexistants restent des descriptions de leurs anciennes transformations.
`families.json` conserve le routage du moteur, sans recopier un second catalogue.
Les originaux en cache sont facultatifs pour jouer et tester la CI, obligatoires
pour reconstruire les dérivés. Leur absence produit un avertissement ; un asset
runtime absent ou altéré fait échouer la validation. Les dates de récupération
historiques inconnues restent `null`, pas une date inventée.

```sh
python tools/audio/studio.py catalogue import
python tools/audio/studio.py catalogue list --query citadis
# Ajouter une source locale revue :
python tools/audio/studio.py catalogue add --manifest local-source.json
python tools/audio/studio.py catalogue validate --waveforms
python tools/audio/studio.py catalogue duplicates
python tools/audio/studio.py catalogue credits --output docs/audio-studio/ATTRIBUTIONS.md
python tools/audio/studio.py segments recordings/original.wav --seconds 4
python tools/audio/studio.py process recordings/original.wav .cache/audio-studio/clean.wav --recipe recipe.json
python tools/audio/studio.py loop recordings/original.wav .cache/audio-studio/loop.ogg --recipe recipe.json
python tools/audio/studio.py analyze .cache/audio-studio/loop.ogg
python tools/audio/studio.py compare reference.wav candidate.wav --output .cache/audio-studio/comparison.json
python tools/audio/studio.py rates reference.wav --duration 4
```

Tous les chemins doivent rester dans le checkout sélectionné (`--root` avant la
sous-commande pour un autre checkout), symlinks sortants et `.git` interdits. Pas
 d'exécution de script téléchargé. Le décodage FFmpeg est limité aux protocoles
file/pipe, segments de 300 s maximum, processus à arguments fixes sans shell.

Exemple de recette (secondes, Hz, dB) :

```json
{"start": 2, "duration": 5, "rate": 32000, "channels": 1,
 "highpass": 65, "lowpass": 12000, "target_lufs": -20,
 "max_gain_db": 8, "ceiling_db": -2, "loop_overlap": 0.18}
```

Options : `denoise_db` (FFmpeg afftdn), `compress: true` (compression douce fixe),
`eq: [{"hz": 900, "width_hz": 400, "gain_db": -2}]`, `fade_ms` pour les ponctuels.
Sans ces options, aucune réduction spectrale ni compression imposée. Gain constant
borné, protection crête vraie suréchantillonnée 4×, **LUFS intégré via FFmpeg**, RMS,
crêtes, silence par fenêtres de 20 ms, spectre, raccord et mesures après encodage.
LUFS `null` pour le silence ; un son court n'a pas forcément une sonie significative.
La mesure 4× est une estimation de crête vraie, pas une certification de laboratoire.

Recettes écrites à côté des dérivés, outils/versions/hachages conservés. OGG Vorbis
pour le jeu ; WAV PCM24 ou FLAC pour le travail. Éviter les réencodages successifs.
Le raccord superpose les extrémités puis corrige le petit écart DC, sans fondu
périodique au silence. La durée finale est réduite de la durée du recouvrement.
Un raccord numérique valide ne prouve pas qu'une boucle de démarrage est crédible.
Utiliser `--source-id ID --family ... --event ...` avec process/loop pour enregistrer
un dérivé attribué dans le catalogue, sinon il reste un fichier de travail.

## Banques et écoute dans Godot

```sh
python tools/audio/studio.py bank build tools/audio/recipes/citadis302-reference.json
python tools/audio/studio.py bank validate --waveforms
# Le candidat livré existe déjà : vérifier sa reconstruction, sans écraser le runtime :
python tools/audio/studio.py bank rebuild studio_citadis302_reference_v1
python tools/audio/studio.py demo --name audition_302 --expected-bank studio_citadis302_reference_v1 --audition-bank studio_citadis302_reference_v1
python tools/audio/studio.py demo --family citadis_x05 --variant toulouse__citadis_305 --expected-bank citadis305_model --name audition_305
```

`build` refuse un identifiant déjà présent. Choisir un nouvel ID pour une révision.
`rebuild` traite les originaux dans le cache et compare les SHA aux assets livrés.
Ne pas exécuter les anciens générateurs en masse : certains réécrivent les profils
approuvés et `design_samples.py` exécute son traitement dès l'import Python.

Le candidat Moscou est une **captation extérieure d'un 302**, pas un moteur isolé,
ni une rame d'Angers. Il n'est pas activé par défaut. `audition_bank` est uniquement
un choix explicite avant `_ready()` dans l'outil de capture. Le jeu conserve les
profils approuvés, dont Rotterdam apparenté pour les 302 et synthèse modélisée pour
les 305. Une activation permanente nécessite écoute humaine, puis commande explicite :

```sh
python tools/audio/studio.py bank activate ID --family FAMILY --human-reviewed
```

Les overrides de variantes gardent priorité et doivent être examinés séparément.
Ne pas utiliser cette option pour contourner une écoute ou une licence manquante.
Une sauvegarde du routage est créée en cache avant activation.

Le scénario réel dure 48 s : arrêt, portes, gong, accélération, roue libre,
freinage, tunnel, pont, retour cabine, portes, pause/reprise. Il utilise une vraie
MissionSession avec **vitesse imposée**, puis enregistre le bus Master Godot/ALSA
sans normalisation. JSON : chemins réellement chargés, bus, gains et événements.
`--traction-solo` isole les couches du mix, pas la motrice de la captation source.
Les démos livrées sont dans [demos/index.html](demos/index.html).

## IA locale optionnelle

```sh
python tools/audio/studio.py ai status
python tools/audio/studio.py ai models
python tools/audio/studio.py ai generate --prompt 'A sliding metal door in a tram interior' --seed 7 --variations 2
# Dans la configuration livrée : arrêt explicite, backend désactivé, aucun son généré.
```

Voir [AI-MODELS.md](AI-MODELS.md). L'adaptateur Soundbox implémente la **soumission**
locale POST /api/generate et conserve prompt, seed, paramètres, empreinte des poids,
justificatif des droits et job ID. Il n'affirme pas qu'un job soumis a produit du son.
L'inférence et la récupération des résultats n'ont pas été testées : serveur/poids
non installés pour les raisons matérielles et juridiques documentées.

Pour une installation autorisée ultérieure : installer Soundbox depuis sa source
MIT, examiner la licence actuelle du modèle et ses dépendances, télécharger les
poids **explicitement**, puis configurer un JSON local avec `enabled`, `model`,
`weights_path` (dans le workspace), `weights_sha256`, `license_review`,
`model_installed_confirmed`, `url: "http://127.0.0.1:17494"`, `steps`, `cfg`.
`ai configure --config ...` conserve ce JSON hors Git. Vérifier que le modèle est
réellement installé dans Soundbox pour empêcher son téléchargement de premier lancement.
Aucune acceptation automatique de licence, aucun service payant, aucun endpoint cloud.
Exporter les résultats terminés vers le workspace et les traiter comme `ai_generated`,
avec attribution/licence propres ; ne pas les appeler captations authentiques.
`catalogue add --manifest local-source.json` exige kind explicite, id, path, name,
family, event, author, source_url, license et license_url ; pour une ressource tierce,
evidence vérifiable ; pour une création du projet, ownership_review. Les exports IA
exigent aussi ai_metadata {model, prompt, seed, weights_sha256, license_review}.
L’import calcule réellement le SHA et les mesures, sans prétendre avoir exécuté le modèle.

`python tools/audio/studio.py synth .cache/audio-studio/mechanism.wav --seed 7`
produit une **synthèse procédurale de test**, clairement étiquetée ; ce n'est pas l'IA.
Aucun serveur MCP ajouté : la CLI apporte les commandes utiles sans serveur doté
 d'accès aux fichiers ou commandes arbitraires.

## Validation et CI

```sh
python tools/audio/studio.py test --godot
python tools/audio/studio.py report --waveforms --output .cache/audio-studio/report.json
godot --headless --path . -s tools/audio/benchmark_audio.gd
```

Tests Python sans réseau ni modèle : licences, provenance, fichiers altérés, cache,
interruption, sécurité des chemins, vraie DSP, silence, clipping, répétabilité,
boucles, construction de banque, adaptateur IA simulé. Tests Godot : familles,
76 variantes, interverrouillages, Rotterdam approuvé, capture/profils, crossfade,
pause, événements prioritaires, repli et nettoyage. Les boucles de stress laissent
le thread audio vider sa file de commandes pour éviter un faux coût de destruction.

Workflow `Audio Studio` : validations légères, formes d'onde, tests, rapport artifact.
Capture ALSA uniquement sur workflow_dispatch avec option ; aucune IA ni recherche
Internet obligatoire à chaque commit. Les workflows historiques du projet continuent
leurs propres vérifications. Les performances Android/Windows sur appareil, l'écoute
comparative et l'approbation perceptive restent nécessaires avant remplacement.
