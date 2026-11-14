# Révision 2 — pourquoi les deux démos semblent identiques

## Résultat principal : la démo « 305 » jouait réellement la banque 302

Le problème de comparaison précède le mixage. `tools/audio/capture_driving_audio.gd` reçoit l'argument `citadis_305` et le transmet à `TramAudio`. Or :

1. `data/rolling_stock/plans/citadis_305.json` n'existe pas ; le plan canonique est `citadis_x05.json`.
2. `TramAudio.profile_for` appelle `TramModel.family_id` pour résoudre la famille.
3. `TramModel.family_id` retourne `citadis_302` pour tout nom de plan inconnu.
4. Aucun `variant_profiles.toulouse__citadis_305` dans `families.json` ne rétablit la banque attendue.
5. Le profil effectivement sélectionné est donc `citadis_302`, banque `citadis302`, avec ses deux captations traitées de Moscou.

Les deux noms de fichiers ne prouvent pas deux contenus de familles différentes. L'intitulé `family` enregistré dans le JSON est l'argument demandé, pas le profil effectivement résolu. Le catalogue confirme pourtant `toulouse__citadis_305.family = citadis_x05`, comme `brest__citadis_305` et `nantes__concept_citadis_305`.

Preuve indépendante dans les anciennes captures : à 12 s, `motor_hum` vaut 0,034265 pour 302 et 0,034875 pour la prétendue 305, et `motor` vaut environ 0,998 dans les deux. C'est le fondu par vitesse de la branche **recorded** à ~15,6 km/h. Le vrai profil `citadis_x05 → citadis305_model` a `recorded=false` : à cette vitesse et en pleine traction, son gain `motor_hum` doit être voisin de 1. Les écarts minuscules observés correspondent aux différences de chronométrage, pas à deux stratégies de moteur.

**Action prioritaire :** refaire la capture à partir de l'entrée réelle du catalogue, avec `citadis_x05` et l'identifiant de variante souhaité. Journaliser la famille demandée, la famille canonique, `sound_profile.bank`, `sound_bank.recorded`, les chemins des flux résolus et leurs hachages. Vérifier explicitement `bank == citadis305_model` avant de lancer le scénario. Le test de toutes les variantes utilise `entry.family`, donc ses parcours peuvent sélectionner correctement la 305 alors que cette démo spécifique la sélectionnait mal.

Cela invalide la comparaison précédente « 302 contre 305 », mais ne prouve pas à lui seul que toute sélection 305 dans l'interface joue mal. Le parcours jeu doit être vérifié séparément avec le profil réellement résolu. Les fichiers spectraux précédents restent des mesures valides des fichiers produits ; leur attribution à deux banques différentes était erronée.

## Masquage réel : présent surtout au départ et en roue libre

Les estimations ci-dessous additionnent RMS du fichier décodé, niveau de banque, correction cabine et `20 log10(gain)` tiré des journaux. Elles se situent **avant** filtrage de bus, compression, panoramique et distance 3D. Elles ne sont pas des stems capturés individuellement, et leurs sommes ne reproduisent pas exactement le Master. La cabine coupe notamment le moteur à 1,6 kHz, alors que HVAC et hum évitent ce passe-bas.

| Moment dans l'ancienne démo 302 | Couche principale estimée | Autres couches | Lecture |
| --- | --- | --- | --- |
| 8,5 s, 4,7 km/h, cabine, traction partielle | HVAC −37,5 dBFS | Ambiance −42,2 ; moteur 302 −43,4 ; roulement −68,9 | HVAC domine le début de mouvement de ~6 dB sur le moteur distinctif. |
| 12 s, 15,6 km/h, cabine, traction | Moteur 302 −38,0 | HVAC −40,0 ; ambiance −42,2 ; roulement −51,5 | Le moteur est présent, mais son passe-bas cabine l'atténue davantage que HVAC. |
| 16 s, 28,1 km/h, cabine, traction | Hum 302 −36,7 | Moteur −40,0 ; HVAC −41,8 ; ambiance −42,2 ; roulement −43,6 | La texture enregistrée devient majoritaire ; « tout est masqué par roulement » serait faux. |
| 20 s, 40,9 km/h, cabine, traction | Hum 302 −33,1 | Roulement −38,5 ; HVAC −41,8 ; ambiance −42,2 | Bonne présence relative de la banque, mais elle contient déjà du bruit de passage/roulement. |
| 24 s, 49 km/h, extérieur, roue libre | Roulement commun −32,8 | Ambiance commune −36,2 ; HVAC −44,8 ; hum 302 −47,6 | L'identité du moteur est ~15 dB sous le roulement ; deux matériels se ressemblent par construction. |
| 29 s, 38,3 km/h, extérieur, freinage | Roulement commun −35,4 | Hum 302 −40,3 ; HVAC −44,8 ; regen commun −50,7 | Le nouveau frein électrique est très faible, ~15 dB sous le roulement. |
| 35 s, 15,3 km/h, cabine, freinage | HVAC −40,9 | Moteur 302 −42,2 ; ambiance −42,2 ; roulement −47,3 ; regen −48,2 | HVAC et ambiance reprennent la place dominante ; identité du frein électrique faible. |

Tous les petits événements sont communs : gong, portes, fermeture 1 kHz, frein mécanique, desserrage et joints. Les deux scénarios commencent par sept secondes de ces sons communs ou d'ambiance avant la traction. Les quinze dernières secondes sont également riches en événements communs et faibles charges. Cette construction réduit la part temporelle de comparaison utile.

La prétendue 305 précédente utilise les mêmes couches que le tableau ci-dessus. Calculer ses niveaux à partir de `citadis305_model` donnerait une fausse preuve : la démo ne chargeait pas cette banque.

## Prévision pour une vraie sélection 305 : différence attendue mais non encore capturée

À charge maximale stabilisée et en cabine, sans correction de bus :

| Vitesse | Captation 302 | Modèle 305 correctement résolu | Couche commune |
| --- | --- | --- | --- |
| 4 m/s (14,4 km/h) | Moteur ~−37,9 dBFS ; hum presque nul | Moteur ~−41,7 ; hum ~−32,7 | HVAC ~−40 ; roulement 302 ~−51,9, 305 ~−49,9 |
| 8 m/s (28,8 km/h) | Moteur ~−41,0 ; hum ~−35,9 | Moteur ~−41,7 ; hum ~−32,7 | HVAC ~−41,8 ; roulement 302 ~−42,9, 305 ~−40,9 |
| 12 m/s (43,2 km/h) | Hum ~−32,9 ; moteur disparaissant | Hum ~−32,7 ; moteur ~−41,7 | Roulement 302 ~−37,6, 305 ~−35,6 |

Les boucles isolées sont différentes objectivement : hum 302 traité, bin principal ~0,74 % de l'énergie et pics variables ; hum 305 modélisé, bin principal ~6,94 % et composantes périodiques explicites. Le même modèle 305 a toutefois été construit avec la même fonction de bruit mécanique que les remplacements génériques ; ses différences supplémentaires à 450 Hz sont très faibles. La nouvelle capture correcte doit déterminer si sa différence effective est suffisante avant une autre refonte aveugle.

En roue libre, le gain 302 tombe à 0,025 et celui du hum synthétique à 0,07. Le fond de roulement commun domine donc même avec un bon routage. Cette ressemblance est partiellement physique, mais un silence quasi total de toute texture propre au matériel efface aussi le grain mécanique enregistré.

## Actions de mixage proposées, avec critères de vérification

1. **Corriger et vérifier la résolution des familles avant toute comparaison.** Produire d'abord trois extraits courts sans portes ni gong : départ cabine 0–30 km/h, vitesse stabilisée 30 km/h en charge puis roue libre, freinage 40–0 km/h. Conserver la même perspective et le même environnement pendant chaque comparaison.
2. **Rendre le départ propre au matériel audible.** Baisser HVAC d'environ 6–8 dB pendant la conduite et l'ambiance d'environ 4–6 dB pour la comparaison. Au départ 302, viser une couche de traction à au moins 6 dB au-dessus du fond commun dans sa bande utile 150–1200 Hz. Ne pas compenser uniquement par hausse du Master.
3. **Éviter le double roulement des banques de passage.** La captation 302 contient déjà roulement et environnement : baisser son roulement synthétique additionnel de 6–10 dB, surtout en charge. Ne pas cumuler un autre `real_rail` avec une captation déjà complète. Pour la synthèse 305 sans captation, conserver un roulement discret mais lui donner un corps/filtrage propre au matériel plutôt que le niveau seul.
4. **Conserver l'articulation réelle du 302.** Ne pas appliquer systématiquement la réduction de proéminence spectrale à 65 % à toutes les raies de la captation : certaines sont précisément la signature électrique recherchée. Comparer la source originale, un simple filtre grave/aigu doux et la version aplatie, à sonie égale. Une atténuation ciblée d'une raie réellement gênante est préférable à l'écrêtage uniforme de tous les pics.
5. **Préserver le détail en cabine.** Le passe-bas fixe 1,6 kHz du moteur, combiné au passe-bas fichier 2,6 kHz et à l'EQ global, empile trois atténuations. Tester un passe-bas cabine plus haut/doux (2,2–3 kHz selon perspective) pour la traction, en gardant un filtrage plus fort pour l'ambiance extérieure. Comparer les bandes 200–800 Hz, 800–1600 Hz et 1600–3000 Hz, pas seulement « pourcentage >3 kHz ».
6. **Freinage reconnaissable sans bruit permanent.** La couche regen actuelle est commune, large bande, et près de 15 dB sous le roulement à 38 km/h. Remonter provisoirement regen de 5–8 dB ou diminuer le fond de roulement au freinage, puis distinguer son enveloppe par famille. Ne pas inventer une fréquence 305 constructeur : aucun enregistrement exact n'est disponible.
7. **Évaluer une différence vérifiable.** Capturer les stems moteur/hum/roulement/HVAC/ambiance séparément dans Godot, puis le mix complet ; comparer l'énergie utile des couches propres au matériel avec celle du fond commun. Conserver crêtes et sonie comparables entre démos. Les tests de gains non nuls ne prouvent pas le bon chargement de banque ou la présence audible de son identité.

## Références utilisables et limites

Pour 302, sources exactes de famille disponibles : Moscou (`citadis302-full.ogg`, fenêtres historiques 37,066–41,366 s et 101,932–106,232 s) et Le Mans (`lemans302-original.mp3`, passage 5–13 s). Les fenêtres Moscou 20–26 s ont une composante stable vers 602 Hz ; 158–164 s sont plus graves. Leur stabilité ne prouve pas qu'elles contiennent une traction isolée. Les consulter comme contextes, en gardant les transitions naturelles plutôt que de transformer tous les passages en ronronnement homogène.

Pour 305, aucune vraie captation identifiée n'a été acquise : la banque reste une proposition modélisée. Les captations 403 ne doivent pas être renommées 305. Le catalogue est la bonne source pour associer l'étiquette commerciale 305 à la famille canonique `citadis_x05`, mais cette association informatique n'authentifie aucun son.

Aucune écoute humaine n'est revendiquée dans cet audit. Le retour de l'utilisateur est cohérent avec le mauvais routage démontré. La première action est de lui fournir deux captures réellement différentes ; les recommandations de confort et d'identité sonore restent à valider ensuite avec les bonnes banques.


## Résultat de la reprisev2

La capture305 a été refaite avant et après modification avec `citadis_x05`, banque `citadis305_model` et chemins305 validés. La révision ne régénère aucun timbre305 : elle corrige la comparaison et le mixage. Les sources302 conservent désormais leur spectre initial, avec raccord et normalisation seulement ; les fonds communs sont réduits. Le passe-bas cabine passe à2400Hz. Les nouvelles sourcesRotterdam et T7 restent des références d’étude ; aucune analyse d’écoute humaine ou localisation temporelle d’événements n’est revendiquée.

La mesure PCM des captures donne pour la302, entre15et23s, une part d’énergie800–3000Hz de21,06% avant contre41,92% après. Cela décrit une modification réelle de l’équilibre spectral, pas une preuve de fidélité ou de confort. Les quatre captures réelles sont sans échantillons écrêtés ; les comparaisonsMP3 reçoivent un gain constant par partie pour comparer à sonie voisine. Voir `samples/tests/v2_pcm_checks.json` et `samples/listening/v2_levels.json`.
