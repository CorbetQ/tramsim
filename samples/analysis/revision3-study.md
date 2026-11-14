# Révision 3 — la banque contient-elle une motrice identifiable ?

## Conclusion technique

Les banques Moscou et Le Mans contiennent principalement des **textures de passage** : bruit large bande, roulement, enveloppe de distance et quelques composantes tonales. Elles ne constituent pas des enregistrements de moteur de traction isolé et calibré en vitesse. Égaliser, augmenter le volume ou transposer ces textures ne peut pas recréer une séquence électrique qui n'y est pas clairement capturée.

La référence Rotterdam 14279 est plus prometteuse pour étudier une motrice : la description de l'auteur indique un Citadis quittant le quai, et son spectrogramme montre plusieurs rampes tonales avec changements de branche. Elle reste une référence de Citadis de Rotterdam, **pas une captation française 302/305 authentifiée**. Les différences de génération et d'équipement de traction ne sont pas établies. La source Paris T7 présente aussi des composantes structurées, mais ses droits n'autorisent actuellement que l'étude ; aucun extrait audio dérivé n'en est exporté.

Cette étude repose sur le signal et les spectrogrammes, sans écoute perceptive. Une séparation harmonique est un outil d'inspection, pas un certificat de « moteur pur ». Les voix, cloches, annonces, ventilateurs et certaines raies de roue peuvent être conservés par le même masque.

## Livrables et reproduction

```
/workspace/tram-geo-venv/bin/python tools/audio/traction_study.py --export-candidates
```

Le script écrit uniquement dans `samples/analysis/revision3/` : neuf spectrogrammes, les mesures et trois trajectoires spectrales par extrait dans `revision3-traction.json`, six petits OGG candidats harmoniques et le trio de comparaison décrit ci-dessous. Aucun asset du jeu, moteur, banque ou réglage n'est modifié. Extraits source étudiés : Moscou 30–48 s et 98–114 s, Le Mans 3–17 s, T7 6–28 s, Rotterdam départ 0–13,8 s, courbe 0–13,1 s, embarqué 0–30 s, et les deux boucles actuelles 302. Les candidats ne reçoivent pas de normalisation individuelle : un candidat plus faible n'est pas automatiquement plus propre. Le trio Rotterdam reçoit un seul gain commun pour éviter une surcharge numérique.

Spectrogrammes : horizontal = temps de l'extrait ; vertical = fréquence, 0 Hz en bas, 3500 Hz en haut ; couleur = magnitude relative, plage 65 dB. Pour retrouver les temps source, ajouter `start_s` du JSON. Les images ne sont pas des captures d'écoute. Les hachages des fichiers effectivement analysés sont conservés dans le JSON.

## Qualité et identité des sources

| Source | Ce qui est établi | Ce qui ne l'est pas |
| --- | --- | --- |
| Moscou `citadis302-full.ogg` | Titre Commons « Alstom Citadis 302 in Moscow » ; matériel déclaré 302 ; provenance libre documentée. | Équipement de traction, régime, vitesse, position exacte du microphone, absence de trafic/paroles ; le titre seul ne prouve pas une signature commune à tous les 302 français. |
| Le Mans `lemans302-original.mp3` | Auteur SamuelGremaud : tram du Mans, captation de passage. | La description ne nomme pas explicitement 302 ; cette attribution vient du code/manifeste historique. À exprimer comme probable/héritée, **pas 302 exact certifié** et encore moins 305. |
| Rotterdam LG 14279 | Auteur : Citadis quittant un quai ; Olympus VN480, mono 22,05 kHz ; aperçu complet ~13,93 s ; CC BY 4.0 selon manifeste de recherche. | Modèle de traction/onduleur, vitesse, équivalence 302/305 France. |
| Rotterdam LG 18723 | Auteur : Citadis dans une courbe, 4 mai 2005, Olympus VN480. | Les raies peuvent provenir de la courbe/roue, donc ne pas les classer d'emblée comme moteur. |
| Rotterdam LG 56878 | Captation intérieure RET Weena–Stadhuis–Coolsingel, PCM-D50, ~122 s ; freinage/accélération/arrêts/portes et passagers selon description. | Pas un stem moteur ; annonces et voix à localiser par écoute avant utilisation. |
| Paris T7 DesCoulam | Article d'essais à Villejuif en 2013, Citadis 302 explicitement nommé ; audio ~73,34 s décodé. | Pas de licence de redistribution établie, vitesse/moteur isolé non documentés ; référence d'étude seulement, hors assets. |

Les deux références vidéo précises fournies par l'utilisateur (`S24ij5gZQkU`, `f0bF9B_WLEc`) n'ont pas de PCM disponible dans cette étude. Aucune comparaison acoustique avec ces références n'est donc revendiquée. Aucune captation authentifiée de 305 n'est disponible pour certifier son rendu.

## Ce que montrent les mesures locales

| Extrait | Observations utiles | Limite pratique |
| --- | --- | --- |
| Moscou 30–48 s | Fond large bande important ; les lignes graves deviennent plus persistantes vers 40–46 s. Part HPSS harmonique ~31–38 % sur 30–40 s, ~50–72 % vers 40–48 s. Le suivi le plus proéminent est surtout ~100–390 Hz et ne forme pas une accélération électrique monotone sur tout l'extrait. | Les 4,3 s historiques 37,066–41,366 s se situent dans une texture composite, pas dans une trajectoire de moteur isolée. Fin 40–46 s à écouter séparément : harmonique ne veut pas dire traction. |
| Moscou hum 98–114 s | Énergie 800–1600 Hz ~49–51 % dans 98–104 s, puis ~32–38 % ; HPSS harmonique ~28–32 %. Spectrogramme largement diffus ; pas de famille de rampes propre nettement isolée par ce traitement. | La boucle 101,932–106,232 s retient beaucoup de texture médium, mais son étiquette `motor_hum` ne prouve pas une véritable raie moteur. Un gain plus fort amplifiera aussi le roulement/environnement. |
| Le Mans 3–17 s | Enveloppe de passage très marquée ; énergie 800–1600 Hz seulement ~11–16 % ; part HPSS harmonique ~35–43 %. Une trajectoire grave varie autour de 140–328 Hz, et une autre raie demeure proche de 2,5 kHz. | Ni fréquence statorique ni origine moteur/rail ne sont établies. La raie 2,5 kHz peut être gênante et ne doit pas être transformée en « signature de motrice » sans écoute/contexte. |
| Rotterdam départ 0–13,8 s | Bande 800–1600 Hz passe d'environ 19 % (0–4 s) à 41 % (4–8 s), puis 51 % (6–12 s). Plusieurs lignes obliques sont visibles sur le spectrogramme, avec changements de branche. Une trajectoire candidate passe vers 562,5 Hz à 4,10 s, 625 Hz à 5,12 s, puis 468,8 Hz à 5,89 s et 375 Hz à 6,91 s ; elle remonte ensuite vers 516 Hz à 9,98 s. | Ce suivi peut changer de composante entre deux points : **ne pas en déduire des modes d'onduleur constructeur**. Il démontre un mouvement spectral réel à conserver, pas un tableau de fréquences exactes à coder. |
| Rotterdam courbe 0–13,1 s | Beaucoup de médium : ~29–41 % dans 800–1600 Hz. HPSS harmonique ~24–27 %, suivi instable à plusieurs fréquences. | Ce contexte de courbe rend l'attribution des tons à la traction particulièrement incertaine. Référence de crissement/roulement à examiner, pas première source de moteur. |
| Rotterdam embarqué 0–30 s | Début dominé par grave/roulement : les analyses précédentes des quatre secondes initiales donnent ~82 % sous 250 Hz. Dans les fenêtres 0–30 s, seulement ~1–3 % dans 800–1600 Hz. | Capture embarquée utile pour contexte et transitions, pas nécessairement meilleure pour isoler une motrice. Les passages/paroles ne sont pas exclus par ces chiffres. |
| Paris T7 6–28 s | Tons persistants autour de 1,4 kHz et plus haut, événement étroit marqué vers 9–10 s ; HPSS harmonique 72–80 % dans les fenêtres 8–14 s. Composantes graves autour de 140/285/426/711 Hz ensuite, avec fond large bande. | L'événement très harmonique peut être signal/gong, pas moteur. Rien ne permet de l'appeler départ de traction sur les seules métriques. Aucun extrait exploitable en jeu sans droits. |

Les fréquences proviennent d'une STFT de résolution 7,8125 Hz ; elles ne constituent pas des mesures mécaniques constructeur. Une raie ascendante peut aussi appartenir au Doppler, à la roue ou à un autre véhicule : le contexte de la source et une écoute restent indispensables.

## Séparation expérimentale : ce qu'elle apporte et ce qu'elle détruit

Méthode : STFT 2048 points à 16 kHz, hop 256 (16 ms). Médiane temporelle 31 trames (~0,5 s) et médiane fréquentielle 31 bins (~242 Hz), masque doux `H²/(H²+P²)`. Trois trajectoires sont obtenues par programmation dynamique sur la proéminence spectrale locale entre 100 et 3000 Hz, avec continuité maximale de 31,25 Hz par trame et pénalité de saut. Le masque candidat combine une partie HPSS faible et des couloirs autour des trajectoires proéminentes, limité à 80–3500 Hz.

| Candidat | Énergie totale conservée | Interprétation |
| --- | --- | --- |
| Moscou 30–48 s | 33,76 % | Reste un fond + des lignes graves, pas preuve de moteur extrait. |
| Moscou hum 98–114 s | 11,94 % | Forte perte ; la texture initiale est majoritairement diffuse pour ce critère. |
| Le Mans 3–17 s | 20,98 % | Met en avant des résonances du passage et la raie aiguë incertaine. |
| Rotterdam départ | 15,43 % | Candidat à écouter pour les lignes mobiles ; la perte du corps mécanique est attendue. |
| Rotterdam courbe | 10,41 % | Peut conserver des raies de roue plutôt que de traction. |
| Rotterdam embarqué | 8,27 % | Très sélectif ; ne pas amplifier de 10–15 dB et prétendre avoir isolé un moteur. |

Pour comparaison, la même méthode conserve ~21,79 % de la boucle motor 302 actuelle et ~13,57 % du hum. Ces pourcentages dépendent du masque ; ce ne sont **pas** des proportions physiques « moteur / parasites ». Le filtre HPSS favorise les tons stationnaires, peut rejeter une vraie montée rapide comme percussive, et conserve les voix harmoniques. Le suivi de crête peut sauter entre composants. Les OGG candidats sont des références d'inspection avec ces défauts ; ils ne doivent pas remplacer directement les banques en production.

## Recommandations concrètes pour faire entendre la motrice

1. **Choisir d'abord un vrai événement de traction.** Une prise dont le contexte indique un départ et dont le spectrogramme comporte une trajectoire structurée vaut mieux qu'une fenêtre de passage sélectionnée uniquement pour sa stabilité. Rotterdam 14279 est le meilleur candidat redistribuable à étudier ici, avec statut apparenté. Moscou/Le Mans peuvent conserver le corps mécanique et le roulement mais ne doivent pas porter seuls la promesse d'une signature électrique précise.
2. **Préserver la trajectoire au lieu de la moyenner.** Une montée électrique n'est pas une boucle stationnaire de 4 s dont on change globalement le pitch. Garder une séquence de départ à sa vitesse temporelle d'origine, puis rejoindre une boucle de régime compatible par un fondu ; fournir une transition distincte de relâchement et de freinage. À défaut de vitesse source connue, exprimer les plages comme phases estimées, pas km/h calibrés.
3. **Séparer rôle mécanique et rôle électrique.** Une couche enregistrée large bande peut porter le corps ; une couche étroite issue d'une vraie séquence peut porter le contour. Ne pas augmenter tout le bruit de passage pour essayer d'obtenir la motrice. Éviter l'addition de trois roulements (prise de passage + synthèse + real_rail).
4. **Ne pas supprimer indistinctement 800–1600 Hz.** Cette bande contient ~la moitié de l'énergie du départ Rotterdam à mi-séquence. Elle peut être essentielle à l'identité électrique ; choisir un contrôle étroit après écoute au lieu d'une baisse globale des médiums/aigus. Conserver les changements de régime ; un lissage de pitch trop long peut transformer une transition réelle en glissando.
5. **Valider avant de généraliser.** Écouter source complète, candidat, et reconstruction à sonie égale. Rejeter les passages où parole, cloche, signal piéton, crissement ou trafic dominent. Vérifier une sortie Godot réellement chargée avec la bonne famille, puis publier une comparaison courte de traction seule avant d'ajouter portes, HVAC et ambiance.

La limite actuelle est double : les anciennes démos avaient un mauvais routage de famille (audit révision 2), et plusieurs banques utilisées comme moteurs sont des prises de passage composites. Le premier problème se corrige dans le code de sélection ; le second demande une meilleure captation ou une restitution explicitement estimée. Aucun nombre de filtres ne rendra une référence absente authentique.

## Trio de comparaison à soumettre à l'écoute

Fenêtre commune : **0–13,8 s de Rotterdam LG 14279**, à la vitesse temporelle de la source, sans association artificielle à une vitesse du tramway simulé. Fichiers disponibles dans `revision3/` :

- `rotterdam-motor-source.flac` / `.ogg` : captation source, convertie en mono 16 kHz.
- `rotterdam-motor-harmonic-candidate.flac` / `.ogg` : composantes favorisées par le masque harmonique et les trajectoires ; ne constitue pas une motrice pure.
- `rotterdam-motor-residual.flac` / `.ogg` : source moins candidat, avec du bruit, des transitoires **et potentiellement des composantes de traction** écartées par le masque.

Les trois partagent exactement le même gain constant : **0,8070227338, soit −1,8623 dB**, appliqué pour garder de la marge face aux excursions de la source décodée et du résidu. Aucune sonie n'est normalisée séparément. La source est quantifiée en PCM 24 bits, le candidat également, puis le résidu est obtenu par différence entière. Après réouverture des trois FLAC, la reconstruction est vérifiée : **source = candidat + résidu, erreur maximale 0 LSB sur tous les échantillons**. Les OGG sont des copies d'écoute avec pertes : leur somme n'est pas exacte. Pour réencoder des copies MP3, partir des FLAC et garder le même gain pour tous.

Preuve et provenance : `revision3/revision3-rotterdam-reconstruction.json`, hachage SHA256 source `b8110276c7ebb28a85125e3870b59b0a7f9dcfba45f90eddfc9e1a21400a6d1e`. **LG — « Streetcar04.wav »**, [Freesound 14279](https://freesound.org/people/LG/sounds/14279/), licence [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Mentionner l'extrait, la conversion et la séparation comme modifications. Le statut demeure « Citadis de Rotterdam apparenté, sous-type non certifié », sans intégration dans les banques du jeu et sans promesse d'authenticité Angers/302/305.

La comparaison utile est de déterminer si la source contient bien le caractère de motrice recherché, puis si le candidat le préserve. Si la source elle-même ne correspond pas au caractère attendu, ne pas poursuivre sa transformation comme solution supposée exacte. Aucun jugement d'écoute n'a été ajouté par l'agent.
