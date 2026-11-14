# Cinématique et effets gratuits — 0.13.1

## Rendu

L'ancien `CityScene.lite` omettait le mobilier final mais construisait encore le sol détaillé, les arbres et les façades. La caméra demandait jusqu'à quatre tuiles synchrones par image, en plus des mises à jour de `Main`.

- `AerialCityLOD` prépare la géographie complète pendant la sélection de la ville : relief à 40 m, voirie, rivières, occupation du sol et véritables emprises/couleurs de toits. Maillages indexés par secteurs de 800 m, matériaux sans éclairage, sans arbres ni fenêtres. Le survol ne construit aucune tuile.
- `CityScene.enable_async_lod()` utilise un constructeur isolé hors de l'arbre, avec son propre cache de terrain/décompression. Les nœuds sont adoptés sur le fil principal après achèvement ; les profils de voies, portails, dépôts et ponts sont conservés. Une seule tâche à la fois ; une tâche encore active à la fermeture est récupérée sur les images suivantes, sans attendre sous le verrou de l’arbre de scène. La fermeture de l’application laisse aussi ces tâches se terminer avant de quitter.
- Les détails de rue sont masqués pendant le survol, préparés dès son début, puis affichés au dernier rapprochement. Le rayon initial est limité à 450 m. La simulation reste figée, sans double mise à jour du décor.
- Le voile de nuages échantillonne une texture de bruit préparée au chargement, et disparaît de l'arbre de rendu lorsqu'il est transparent. Plus de bruit trigonométrique par pixel.
- Pendant l'intro : résolution 3D à 65 % au maximum, sans MSAA, contours ni ombres. L'interface reste à sa résolution normale ; les réglages de conduite sont restitués à la fin ou au passage. Le LOD est aussi préparé si le fond d'accueil est désactivé et l'intro activée.

Mesures de lecture **naturelle** à 1280 × 720, Mesa llvmpipe sans GPU et quota de 2 vCPU. Ces chiffres ne constituent pas une mesure sur téléphone :

| Cas | Durée réelle | Image médiane du survol | P95 du survol | Appels de rendu max. du survol |
|---|---:|---:|---:|---:|
| Première itération LOD, Angers | 24,88 s | 292,58 ms | 456,64 ms | 13 |
| Version finale, Angers | 10,63 s | 137,63 ms | 308,33 ms | 21 |
| Version finale, Nantes | 10,65 s | 122,57 ms | 396,91 ms | 30 |

Le rendu logiciel reste lent. Un essai matériel Android est nécessaire pour annoncer une cadence réelle. Les délais de préparation des détails peuvent prolonger un palier ; il n'y a plus de génération synchrone de tuiles sur le trajet aérien.

## Sons sans service payant

Sound Effects/Megascenes ne disposait d'aucun crédit. Les brouillons n'ont produit aucun son ; aucun achat effectué. Le remplacement utilise **Kenney Interface Sounds (CC0)** et **Réveil des oiseaux de Joseph Sardin (CC0)**, ainsi qu'un souffle synthétisé localement. Liens, empreintes et traitements : `data/audio/free_sfx/SOURCES.json`, `CREDITS.md`.

Clics uniquement sur les actions confirmées, sans son au survol ou au défilement, anti-répétition de 80 ms et option « Sons d'interface ». Les oiseaux diminuent en roulant et disparaissent la nuit/en tunnel ; le souffle augmente avec la vitesse et sur les ponts. Le trafic désactivé réduit le fond urbain sans supprimer les oiseaux. Les captations et banques de traction existantes sont conservées.

Reproduction avec ffmpeg et Python standard :

```sh
python tools/audio/build_free_sfx.py --originals /chemin/vers/les/originaux
```

Fichiers attendus : `click_001.wav`, `back_001.wav`, `confirmation_001.wav`, `birds-original.ogg`, aux URL du manifeste. Aucun compte ni API nécessaire.

## Vérifications

- `test_app_close` : fermeture de l’application pendant les chargements, avec vidage des tâches avant de quitter.
- `test_lod_shutdown` : destruction d’une ville pendant la préparation d’une tuile, sans blocage ni tâche orpheline.
- `test_free_sfx` : actions, répétitions, désactivation, glissement tactile, boucles, jour/nuit, tunnel et trafic.
- `test_audio`, `test_audio_families` : mixage, traction progressive, freinage, portes, gong, pause, alimentation et acoustique des 20 familles.
- `test_city_preload` : cache, absence de relecture après lancement, erreurs et reprise.
- `test_arrival_transition` : fondu, continuité du survol, frein F3, pose finale et passage de l'intro.
- `test_cinematic_lod` : lecture naturelle, mesures de durée/cadence, constructeur asynchrone et restitution de qualité. `LOD_CITY=Nantes`, `LOD_NO_BACKGROUND=1` et `LOD_SHOTS=/dossier` permettent d'étendre le parcours.

Les petits avertissements de textures GL à la fermeture existaient déjà dans les tests précédents. Aucun APK n'a été mesuré sur téléphone dans cet environnement.
