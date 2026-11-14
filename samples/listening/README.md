# Écoutev2

Les fichiers `v2_citadis_*_avant_apres.mp3` comparent le même départ0–50km/h : **avant0–16s, silence16–17s, après17–33s**. Chaque partie reçoit un gain constant pour viser−20LUFS, borné si nécessaire pour garder la crête sous−1dBTP. Pas de compression de présentation, de resynthèse ou d’effet ajouté. La sonie est mesurée sur les16secondes utiles. Ce sont les sorties Master de Godot.

Les fichiers `v2_citadis_*_ecoute.mp3` présentent les48secondes du scénario complet après correction, avec un gain constant calculé sur le scénario entier. Les valeurs avant encodage sont dans `v2_levels.json`.

302 : banque de famille302, source nomméeMoscou ; aucune captationAngers intégrée.305 : banque `citadis305_model`, synthétique, correctement sélectionnée. L’avant305v2 est une nouvelle capture correcte du modèle précédent, **pas l’ancien extrait305 erroné**. Portes et gong restent les sons communs précédents.

## Archivesv1

> **Correction — deuxième passe :** le premier extrait intitulé Citadis 305 utilisait par erreur la banque du 302 (identifiant non canonique dans le script de capture). Cet ancien extrait ne démontre donc pas le modèle sonore 305. Les captures corrigées sont identifiées v2 ; voir `analysis/revision2-study.md`.

# Extraits pour écoute comparative

Ces MP3 proviennent des WAV Master capturés dans Godot, avec un gain **constant de +9,6 dB**, puis un encodage stéréo 48 kHz / 96 kbit/s. Le niveau d’écoute est ainsi proche de −20 LUFS pour les deux exemples. Aucun montage, bruit, événement ou effet supplémentaire n’est ajouté ici. Les captures brutes non amplifiées et leur chronologie sont dans `../demos/`.

- Citadis 302 : banque enregistrée du Mans retraitée, utilisée comme source apparentée pour Angers.
- Ancien MP3 Citadis 305 : banque 302 chargée par erreur, **comparaison invalide**. Voir les fichiers v2 corrigés.

Le fichier d’écoute permet de juger le timbre et le mixage relatif à niveau comparable ; son gain de présentation ne prétend pas être le niveau Master du jeu. La mesure numérique ne garantit pas un confort subjectif : ce sont les prototypes proposés à l’utilisateur.
