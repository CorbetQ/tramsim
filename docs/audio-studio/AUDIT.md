# Audit avant modifications — TramSim Audio Studio

Référence : `be7eda97e5de6b4cdd1cedc9ee16e911537313d3`, branche dédiée
`codex/tramsim-audio-studio`. Inventaire SHA-256 et formats : [baseline.json](baseline.json).
Les WAV `studio_baseline_302` et `studio_baseline_305` ont été capturés avant
modification par le véritable mixeur Godot 4.6.3 / ALSA, à 48 kHz (47,84 s).
Le scénario impose les vitesses : il teste le moteur audio, pas la physique de conduite.

## Existant réutilisé

Inspection de TramAudio, UiAudio, make_audio.py, families.json, sources.json,
DESIGN-CREDITS.md, design_samples.py et v2, build_free_sfx.py, capture_driving_audio
(GDScript/shell/C), render_approved_demo.py, find_audio_sources.py,
build_audio_banks.py, recorded_audio.py, CREDITS.md, project.godot et tests audio.

20 familles, 76 variantes, 10 banques, 66 OGG (3 423 605 octets). Six profils
classés exact_family, quatre apparentés, huit synthétiques et deux modélisés.
Les 302 de production utilisent la captation apparentée Rotterdam (LG, CC BY 4.0),
non certifiée comme 302, isolée par traitement harmonique. Les 305 sont modélisés,
pas des captations authentiques. Préserver ces distinctions et routages approuvés.

TramAudio possède déjà spatialisation 3D, couches d'effort/vitesse, réverbération
tunnel, résonance pont, filtrage cabine, protections portes/APS/pantographe et
lissage des régimes. UiAudio limite les répétitions et ignore les gestes de drag.
Aucune raison de remplacer ces moteurs. Génération et traitement restent hors jeu.

## Défauts observés

- Métadonnées dispersées ; mesures/hachages historiques de segments devenus obsolètes
  après redesign. Le test Python échoue réellement : 8 échecs de SHA, 2 erreurs de
  schéma (305 modélisé, Rotterdam). Les quatre autres tests Python passent.
- Générateurs historiques réécrivant les manifestes : risque de perdre des réglages
  récents. `design_samples.py` exécute des transformations dès son import : interdit
  de l'importer dans le Studio.
- Recherche Commons supposant une durée dans imageinfo : peut ignorer des fichiers.
  Téléchargements sans validation atomique, provenance/licences peu structurées.
- Bascule cabine/extérieur arrête brutalement l'ancien lecteur. Flux spécifique
  manquant : pas de repli par couche. Pause ne suspend pas le gong.
- Anchor 3D attaché à la vue : reste présent si seul TramAudio est détruit.
- Mesure LUFS historique approximative, pas un calcul EBU intégré complet.
  Boucles courtes et façonnage spectral peuvent gommer des détails ; aucune mesure
  automatique ne certifie l'authenticité perceptive d'une motrice.
- 33 lecteurs alloués + gong, nombre fixe ; pas de budget explicite des ponctuels.
  Les bus d'environnement sont partagés : moteur prévu pour une rame principale.

Tests Godot initiaux audio, families, interlocks, Rotterdam et variants exécutés ;
voir rapport final pour résultats/temps. Les sorties JSON de tests sont des produits
reproductibles, pas des modifications intentionnelles du contenu du jeu.

## Ressources et IA

2 cœurs CPU (quota), RAM cgroup 8 Gio, aucun GPU. Python 3.12, NumPy/SciPy et FFmpeg
(ebur128/loudnorm/afftdn) disponibles ; torch absent. Disque racine saturé, travail
et caches dans /dev/shm (~3,4 Gio libres après captures).
Soundbox : application MIT, licences des poids indépendantes, API locale disponible.
Stable Audio Open Small : métadonnées officielles Hugging Face accessibles,
poids ~1,68 Go, accès conditionné (`gated: auto`), README/LICENSE raw renvoient 401.
Licence Community conditionnelle, pas une autorisation commerciale inconditionnelle.
AudioGen : poids CC BY-NC 4.0, exclus du contenu redistribuable commercialement.
Aucun poids téléchargé, aucune inférence effectuée. Backend local désactivé par
 défaut tant que ressources, poids et droits ne sont pas explicitement validés.
