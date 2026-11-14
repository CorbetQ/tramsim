# Atelier sonore — proposition à écouter

Les quatre rôles demandés ont produit les sources, l’étude, les banques et les tests. Le moteur est intégré sur la branche de travail `codex/tram-audio-design`, en attente du retour sur le timbre avant fusion et publication.

## Écouter les prototypes

- [Citadis 302 — MP3](listening/citadis_302_ecoute.mp3) : base enregistrée puis traitée.
- [Citadis 305 — MP3](listening/citadis_305_ecoute.mp3) : restitution modélisée, sans captation exacte réutilisable trouvée.

Environ 48 secondes : portes, gong, accélération progressive, roue libre, freinage, tunnel/pont, arrêt et pause/reprise. Les MP3 reçoivent uniquement un gain constant de présentation de +9,6 dB (niveau voisin de −20 LUFS), puis sont encodés. [Détails du niveau](listening/README.md).

## Dossiers

- `raw/` : 19 captations, 17 min 22 s environ ; fichiers et licences dans [sources.json](sources.json). La matrice couvre les 76 variantes / 20 familles du registre canonique, avec les absences et apparentements signalés. Ces références ne sont pas toutes intégrées au jeu.
- `references/` : provenance et limites des recherches.
- `analysis/` : [étude objective](analysis/technical-study.md), fenêtres candidates, spectres/niveaux et défauts de raccord. Aucun jugement d’écoute humaine n’est inventé.
- `designed/` et `data/audio/` : banques conçues, traitements reproductibles et crédits. [Notes de conception](design-notes.md).
- `demos/` : véritables enregistrements du bus Master Godot, WAV maîtres et OGG bruts, scénario et instrumentation. La vitesse est prescrite pour la comparaison ; ce n’est pas une conduite manuelle.
- `tests/` : [76 parcours et contrôles supplémentaires](tests/README.md), sans échec d’assertion ; vérifications PCM des deux captures. Les captures audio réelles complètent les tests de logique effectués avec Dummy.

L’atelier et les captures sont exclus de l’import du jeu par `.gdignore` ; seules les banques intégrées dans `data/audio` sont utilisées à l’exécution.
