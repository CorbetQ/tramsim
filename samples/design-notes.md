# Proposition de timbre — 14 novembre 2026

Cette proposition est à écouter avant déploiement. Les démos capturées par Godot dans `samples/demos/` utilisent réellement `TramAudio.update_state` et les banques intégrées. Les banques isolées ne sont pas des démos de conduite.

Le Citadis 302 conserve les enregistrements identifiés Moscou / Le Mans selon la variante. Ce sont des textures de passage, contenant potentiellement roulement et environnement, pas un moteur isolé ni des régimes mesurés. Les sources originales et les droits restent dans `data/audio/families.json` ; les dérivés ont leurs empreintes et traitements dans `data/audio/design-manifest.json`.

Le Citadis 305 utilise une **restitution modélisée sans captation exacte**. Elle ne provient pas d'un 403 rebaptisé. Son corps mécanique large bande, ses composantes magnétiques faibles et sa modulation lente créent une proposition distincte. Fréquences et modes sont des choix de design, sans prétention de reproduire une électronique constructeur déterminée. Les profils x05 et x05 Nantes sont explicitement étiquetés `modeled`.

## Causes et corrections

Les anciennes synthèses concentraient 54 % (motor) et 42 % (hum) de leur énergie dans une seule raie spectrale : un passe-bas ou un simple volume réduit ne change pas ce caractère. Les nouvelles synthèses gardent le même objectif de sonie (-20 LUFS) mais donnent la priorité au bruit mécanique coloré, avec des sinusoïdes atténuées et des harmoniques amorties. La hauteur est bornée et toutes les couches variables sont lissées sur 300 ms, y compris les changements de mode précédemment instantanés.

Les captations reçoivent un contrôle modéré de proéminence spectrale (plafond local à +9 dB au-dessus de la médiane 55 Hz, correction partielle à 65 %), un filtrage circulaire 65–2600 Hz et un recouvrement de 180 ms. Le roulement réel reçoit également un raccord, car son saut de boucle dépassait nettement les pas d'échantillons ordinaires. Sur TFS hum et Urbos motor seulement, un microfondu cosinus de 8 ms supprime une pente résiduelle au raccord. Les originaux sont conservés.

La traction se retire en roue libre ; le freinage électrique apporte une couche `regen` séparée, puis le frein mécanique ponctuel intervient à basse vitesse. Les gains ont une attaque de 280 ms et un relâchement de 600 ms. Portes, alarme de fermeture, gong, desserrage, frein mécanique, joint et urgence restent des événements distincts. Les bus cabine, tunnel et pont sont routés en vue extérieure et intérieure, avec leur filtrage/réverbération existants. Compresseur et limiteur restent en sortie ; aucune normalisation des démos ne doit se faire passer pour le niveau réel du moteur.

## Reproduction

`/workspace/tram-geo-venv/bin/python tools/audio/design_samples.py`

Exécuter après toute reconstruction avec `data/audio/make_audio.py`, qui est le générateur historique. Dépendances : numpy, scipy, ffmpeg/libvorbis. Seed 305302. Les dérivés sont encodés mono 32 kHz Vorbis q5 ; originaux inchangés. `design-manifest.json` est la référence des fichiers redessinés et `sources.json` référence ce manifeste. Les dérivés enregistrés héritent de la licence de chaque captation : CC BY 3.0, CC BY-SA 3.0/4.0 ou CC0 selon la banque. Les traitements ne retirent aucune obligation d'attribution ou de partage à l'identique.

## Limites

L'amélioration spectrale et les contrôles automatiques ne remplacent pas l'écoute humaine. Aucun relevé de vitesse ne permet de calibrer les captations à une fréquence exacte : leur transposition reste donc limitée à environ deux demi-tons. Les familles sans captation exacte gardent leur statut estimé/apparenté, et les variantes héritent de leur profil explicite. Les petits événements et ambiances sont des synthèses communes, pas des sons spécifiques certifiés pour chaque matériel.

## Références d'événements supplémentaires examinées

`tram-doors-cologne-original.ogg` (13,9 s, domaine public, stephan) est la piste prioritaire pour une future découpe de portes : il contient ouverture, fermeture, souffle et bips mais aucun matériel français identifié. Le gong historique d'Amsterdam (Beeld en Geluid, 1984, CC BY-SA 3.0) et le freinage d'urgence du même fonds sont des références de mécanique ; leur époque et matériel non identifié ne justifient pas un remplacement uniforme des événements Citadis. Les annonces et craquements de la captation Urbos Birmingham empêchent de la traiter comme une banque d'événements isolés. Ces fichiers restent dans les sources à écouter, sans substitution silencieuse dans le moteur.

Mesures après traitement : l'énergie de la raie la plus forte passe de 53,8 à 6,1 % pour motor, 42,3 à 6,1 % pour hum et 23,0 à 4,5 % pour carrier. La bande 3–6 kHz du 302 motor passe de 7,73 à 0,79 %. Le saut de raccord mesuré par rapport aux différences entre échantillons typiques passe de +27 à −13 dB pour real_rail. Les raccords TFS hum et Urbos motor après microfondu sont à −31,6 dB. Voir `samples/analysis/` pour les mesures automatisées ; elles ne constituent pas un avis d'écoute.
