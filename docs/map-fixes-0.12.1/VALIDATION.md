# Validation 0.12.1

- Passage complet : 30 scripts applicatifs réussis, gabarit validé dans 28 villes, 23 tests Python et 149 fichiers réseau valides.
- Après les ajustements du chargement annulable et du cache d’affichage : tests ciblés du terrain (10 contrôles) et de l’accueil (35 contrôles) rejoués avec succès.
- Audit de données : 28 villes, 11 168 tuiles, aucune anomalie aux tolérances documentées dans le rapport.
- Captures du décor avant/après à trois points de Nantes, de l’accueil vertical et de trois instants de la transition. Même caméra et éclairage pour les comparaisons.
- Les exports Android/Windows ont également compilé dans GitHub Actions avant fusion. La branche fusionnée repasse les contrôles avant publication automatique de ses binaires.

Le rendu graphique a été vérifié sous Linux avec OpenGL logiciel. Aucun essai sur téléphone Android physique ou Windows natif.

## Parcours d’accueil

```text
Godot Engine v4.6.3.stable.official.7d41c59c4 - https://godotengine.org
WARNING: Could not set V-Sync mode, as changing V-Sync mode is not supported by the graphics driver.
     at: set_use_vsync (platform/linuxbsd/x11/gl_manager_x11.cpp:364)
OpenGL API 4.5 (Core Profile) Mesa 25.0.7-2+deb13u1 - Compatibility - Using Device: Mesa - llvmpipe (LLVM 19.1.7, 256 bits)

ok: accueil : cartes de mode
ok: accueil : réglages accessibles
ok: accueil : fond 3D de la ville créé
ok: accueil : Bordeaux vue du ciel chargée
chargement fond Bordeaux : 20134 ms
ok: un seul calque après le fondu
ok: accueil : vue verticale orthographique orientée au nord
ok: l'accueil reste fluide pendant le survol
ok: lignes de tram en surbrillance
ok: accueil : cibles tactiles >= 44 px (0 trop petites)
ok: touche 1 : configuration d'une mission
ok: ville courante présélectionnée
ok: recherche + Entrée : Angers choisie
ok: changement de ville demandé au fond
ok: fond : Angers chargée
ok: fondu enchaîné entre les deux villes
ok: ancienne ville libérée après le fondu
ok: résumé de la sélection visible
ok: configuration : cibles tactiles >= 44 px
ok: Échap : retour à l'accueil
ok: Entrée : partie lancée avec l'intro
ok: fond d'accueil libéré au lancement
ok: décor de la zone de départ chargé avant l'intro
ok: durée de l'intro 4.8 s
ok: caméra d'intro active
ok: HUD masqué pendant l'intro
ok: intro terminée seule (44.6 s réelles)
ok: zoom du ciel (2190 m) vers la rame
ok: descente continue, sans à-coup
ok: session figée pendant l'intro
ok: passage fluide à la caméra de jeu
ok: HUD affiché après l'intro
ok: accueil : « Reprendre la dernière partie »
ok: R : reprise avec intro
ok: touche : intro passée
ok: la touche de passage n'actionne pas la rame
TOTAL_ECHECS|0
```
