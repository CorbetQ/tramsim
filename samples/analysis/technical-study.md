# Étude acoustique des sons de tramway

## Méthode et portée

Analyse objective réalisée sur les 34 fichiers OGG présents avant modification et les **19 captations** fournies dans `samples/raw`. Aucun outil d'écoute perceptive ou de transcription n'était disponible : **aucune écoute n'est revendiquée**. Les raies mesurées ne prouvent ni un moteur isolé, ni l'absence de paroles, de gong, de trafic ou de vent. Aucune plage n'est certifiée sans voix. Les recommandations de confort sont des hypothèses DSP à valider par écoute réelle, idéalement au casque et en cabine/extérieure.

Reproduction depuis la racine :

```
/workspace/tram-geo-venv/bin/python tools/audio/analyze_samples.py data/audio --output samples/analysis/current.json
/workspace/tram-geo-venv/bin/python tools/audio/analyze_samples.py samples/raw --windows --output samples/analysis/raw-windows.json
```

`baseline.json` conserve les hachages et mesures antérieurs aux modifications ; `baseline-families.json` conserve les déclarations initiales de famille. Décodage ffmpeg mono 16 kHz, Welch 4096 points, STFT 2048 points ; énergie des bandes relative au total. RMS dBFS différent de LUFS. Crête suréchantillonnée ×4 après conversion mono : indicateur, pas mesure de conformité exhaustive du master multicanal original. La conversion exclut les fréquences au-dessus de 8 kHz. Une analyse du mix et une écoute restent nécessaires pour les effets du moteur Godot, les gains cumulés, la perspective et les transitions.

## Causes quantifiées avant modification

| Élément | Résultat objectif | Conséquence et correction proposée |
| --- | --- | --- |
| Moteur synthétique | Bin principal 300,78 Hz : 53,79 % de l'énergie ; RMS −19,12 dBFS | Tonalité quasi sinusoïdale pouvant dominer comme une note fixe. Réduire la part sinusoïdale, conserver un bruit brun électromécanique, ajouter des harmoniques faibles et élargies ; un simple passe-bas n'enlève pas cette tonalité. |
| Hum synthétique | 121,09 Hz : 42,29 % dans le bin principal ; harmoniques 238/359/480 Hz | Bourdon très régulier. Réduire la fondamentale par rapport au fond mécanique, variation lente faible, sans vibrato marqué. |
| Porteuse synthétique | 421,88 Hz : 22,99 % dans le bin principal | Ne jouer qu'en charge à basse vitesse, enveloppe progressive, niveau faible. |
| Citadis 302 Moscou motor | Bin max 2,04 % ; 7,73 % en 3–6 kHz ; crête −7,41 dBFS | Le défaut probable est davantage un souffle/grain aigu qu'une raie fixe. Passe-bas doux 2,6–3 kHz et éventuelle réduction large 1,5–3 kHz ; ne pas enlever tout le détail de traction. |
| Citadis 302 Moscou hum | Bin max 0,72 % ; 3,73 % en 3–6 kHz | Déjà large bande ; débruitage modéré seulement, sans gate ni soustraction agressive. |
| Le Mans 302 | Pics motor 246/262/289 Hz, hum 293/340 Hz ; 0,68/0,56 % en 3–6 kHz | Captation de passage, ne démontre pas une traction pure ni un 305. Préserver la dynamique sans amplifier les événements parasites. |
| TFS hum | Bin max 24,19 % vers 347,66 Hz ; crête −1,57 dBFS | Événement étroit ou transitoire potentiellement gênant ; fenêtre source 8–12 s très instable. Éviter comme hum stationnaire. |
| Crissement | Pic 2398 Hz ; 16,09 % bin max ; 7,98 % en 3–6 kHz | Source volontairement étroite : déclenchement rare en courbe, très bas, aucun fond permanent. |
| Real rail | Saut de raccord 27 dB au-dessus du pas typique ; crête −1,14 dBFS | Raccord à traiter avant activation. La banque enregistrée l'atténuait à −90 dB, donc ce défaut seul n'explique pas le son 302 actuel. |

Aucun fichier décodé ne présente de samples à ≥0,999 ; pas de clipping source détecté. Cela ne garantit pas l'absence de saturation du mix. Les crêtes et bandes de chaque fichier sont dans le JSON ; aucune généralisation « tous les sons sont trop aigus » n'est soutenue par les mesures.

### Hauteur, raccords et enveloppes

Dans l'ancien `motor_hz`, les deux changements de régime font 440→280 Hz (−7,82 demi-tons) et 480→360 Hz (−4,98 demi-tons). Interpoler directement la hauteur d'un même lecteur peut produire un glissement artificiel. Une transition courte de 150–300 ms, idéalement entre couches à phase continue, préserve un changement de régime sans coupure ni sirène. L'inverse au freinage doit être lissé également, avec hystérésis aux seuils pour éviter les allers-retours.

Les captations ont une hauteur déjà mouvante : limiter leur transposition à environ ±3–5 % autour du régime documenté, puis faire porter l'évolution sur les gains de couches et le roulement. L'ancienne plage 0,88–1,15 couvre 4,63 demi-tons et accélère aussi le bruit, les voix et les événements intégrés ; la vitesse de référence de 8 m/s était estimée. Ne pas interpréter la raie dominante d'un passage comme la fréquence statorique.

Séparer charge et vitesse : montée traction 120–250 ms, relâchement 250–500 ms ; résidu très faible en roue libre ; frein électrique progressif en charge négative, disparition sous environ 3–7 km/h puis mécanique brève. À l'arrêt, traction nulle et ventilation discrète ; pas de reset d'une boucle à chaque variation du manipulateur. Crossfade de régime à puissance constante mais gains plafonnés pour éviter +3 dB de renforcement de couches corrélées.

Raccord 302 motor : saut +4,88 dB au-dessus du pas typique ; hum −7,10 dB. Utiliser un raccord de 200–400 ms après choix de deux points compatibles en enveloppe/spectre et vérifier le **fichier OGG décodé**, pas seulement le WAV. Le seuil d'un indicateur de seam ne suffit pas à certifier une boucle inaudible. Éviter le fondu à zéro à chaque tour, qui crée une pulsation.

Débruitage : commencer par passe-haut 50–70 Hz et passe-bas doux, seulement si la composante utile n'est pas dans cette bande. Réduction de bruit spectrale limitée à quelques dB avec lissage temporel/fréquentiel ; éviter masque dur, gate ou soustraction forte causant un bruit musical « aquatique ». Ne jamais retirer une raie de traction simplement parce qu'elle est dominante.

### Gong et portes

Gong actuel entièrement synthétique : deux frappes à 660 puis 550 Hz, partiels 1100/1320/1519/1820 Hz ; pic −7,66 dBFS, énergie haute très faible. Son identité matérielle n'est pas vérifiée. Portes synthétiques : moteurs 120–160 Hz (glissement écrit dans le générateur), sans captation réelle ; bip de fermeture à 1 kHz avec harmonique 2 kHz, bin max 38,66 %, crête −11,89 dBFS. Une tonalité de signal est attendue mais répétition et niveau doivent rester modérés. Ces sons ne peuvent être qualifiés « enregistrés du vrai 302/305 ».

Le générateur contient des coupures d'enveloppe dans le frein mécanique à 2 s et des activations carrées du buzzer d'urgence. Ces événements ponctuels peuvent tolérer une attaque physique, mais les composantes tonales/bruit doivent avoir un fondu de quelques millisecondes pour éviter les clics numériques. Ne pas appliquer les critères de raccord de boucle aux one-shots comme gong ou portes.

## Couverture initiale et limites d'identité

| Profils / variantes | Source initiale | Précision défendable |
| --- | --- | --- |
| Citadis 302 ; banque Le Mans 302 | Moscou / passage Le Mans | Famille 302 enregistrée, équipement de traction et régime non vérifiés ; Le Mans ne prouve pas un 305. |
| Citadis 402 | Porte d'Ivry | Famille 402 enregistrée, contexte extérieur ; pas tous les réseaux ni motorisations. |
| Citadis 403 Strasbourg | Strasbourg 2040 | Famille 403 enregistrée. |
| Citadis Compact / Reims | Banque Moscou 302 | Apparenté, aucune captation exacte de ces variantes. |
| Citadis Tours | Banque 402 | Apparenté, pas de capture propre Tours. |
| Citadis X05 / Nantes X05 | Banque 403 | Apparenté seulement : **aucune vraie captation 305 acquise**. Une synthèse dédiée reste estimée ; ne pas la rebaptiser captation 305. |
| Avanto | T4 Bondy–Aulnay | Famille enregistrée, source transport en environnement. |
| TFS | Nantes rame 324 | Famille enregistrée ; hum initial comporte une fenêtre instable. |
| Flexity Marseille | Marseille | Famille enregistrée ; identification antérieure corrige une légende source erronée. |
| Urbos | Luxembourg essais 2017 | Famille Urbos enregistrée, pas exact pour chaque réseau. |
| Breda VLC, Dualis, Citadis X01, Eurotram, Incentro, Tango Rhônexpress, Vevey Saint-Étienne | Synthèses partagées avec facteurs de pitch | Aucune captation exacte dans les banques initiales. Le facteur de pitch ne recrée pas l'identité d'un onduleur. |
| Translohr | Synthèse, roulement pneus dédié | Aucun véritable enregistrement de traction ; éviter rail/crissement/joint acier. |
| Eurotram Porto nouvellement collecté | Source intégrale distincte | Référence de famille apparentée à Strasbourg/Milan selon variante ; ne vaut pas preuve exacte des autres réseaux. |

Les étiquettes initiales `exact_family` signifient seulement même famille déclarée. Elles ne certifient pas moteur, génération d'onduleur, prise de son cabine, vitesse, ou sous-variante. Provenances, licences et hachages des nouvelles intégrales : `samples/sources.json`.

## Fenêtres sources et exclusions

`raw-windows.json` donne toutes les fenêtres de quatre secondes au pas de deux secondes ; `candidate-windows.json` sélectionne des passages inspectables avec minutages exacts et dispersion du niveau. Ce sont des **candidats objectifs à écouter**, sans certification de traction isolée ou d'absence de paroles. Ne pas intégrer une annonce, une conversation, un gong capturé ou un passage routier répété à une boucle moteur. Leur localisation précise exige une écoute humaine ; aucun minutage de paroles inventé n'est fourni.

| Source | Passages à examiner | Usage / réserve |
| --- | --- | --- |
| 302 Moscou | 2–6 s ; 20–24 s ; 22–26 s | Niveau stable : variations P90−P10 de 0,73 / 0,88 / 0,88 dB, pics 812 / 602 / 602 Hz. Peut être un fond stationnaire ; nature à vérifier. |
| 302 Moscou | 158–162 s ; 160–164 s | Pics 97/211 Hz, énergie 3–6 kHz 1,19 / 1,60 %, variations ≈2 dB : candidats graves plus doux ; contexte de conduite inconnu. |
| 302 Moscou | 37,066–41,366 s ; 101,932–106,232 s | Fenêtres déjà utilisées dans les banques ; la première conserve davantage de grain aigu. Ne pas confondre leur temps source avec le temps de la boucle raccourcie par crossfade. |
| 402 | 4–8 s ; 12–16 s ; 20–24 s | 12–16 s pic 183/203 Hz, variation 1,56 dB ; 20–24 s dominé 51 Hz, probablement fond plutôt que traction utile. |
| 403 | 4–8 s ; 10–14 s ; 12–16 s | 10–14 s stable (variation 1,64 dB, pics 246/258Hz), bon candidat de couche homogène, événement à vérifier. |
| Avanto | 12–16 s ; 34–38 s ; 48–52 s ; 60–64 s | 48–52 s variation 1,36 dB, pics 335/168Hz ; 60–64s variation 1,05 dB, possible fin de séquence/fond. |
| TFS | 4–8 s ; 6–10 s ; 12–16 s | Candidats grave/roulement ; **8–12 s à exclure d'une boucle stationnaire** : variation 9,37 dB, fort événement347 Hz. Événement réel non identifié sans écoute. |
| Flexity | 0–4 s ; 2–6 s ; 6–10 s ; 8–12 s | Captation courte, variations2,9–7,1dB ; extraction d'un cycle homogène difficile, boucle très prudente. |
| Urbos | 0–4 s ; 12–16 s ; 22–26 s ; 28–32 s ; 32–36 s | Début très faible (~−31dBFS) : ne pas normaliser aveuglément du bruit. Comparer milieu de séquence utile. |
| Eurotram Porto | 8–12 s ; 18–22 s ; 20–24 s ; 24–28 s | Variations larges, captation de passage ; 18–22s variation 4,66dB. Éviter un gain de boucle excessif sur la fin faible. |

Pas d'isolat authentifié de gong/portes/freinage pour chaque matériel à ce stade. Ne pas extraire un signal supposé sur la seule base d'un pic spectral. Les passages accélération/freinage complets sont à conserver comme références d'écoute, pas à superposer en boucle à toutes les vitesses.

## Validation attendue

Les métriques de banque servent à localiser les défauts ; les rendus Godot doivent confirmer comportement en charge, roue libre, frein électrique, arrêt, portes et gong pour 302 et 305. Comparer crêtes, évolution du RMS, raies dominantes et absence de saut d'enveloppe. Toute affirmation « plus naturel », « sans voix », « vrai 305 » ou « agréable au casque » nécessite une preuve différente de ce seul rapport. La mesure ne remplace pas cette validation perceptive.

## Comparaison après conception

`designed.json` mesure les fichiers après première génération du designer, avec les mêmes paramètres que le baseline. L'ajout du bruit mécanique et la baisse des sinusoïdes réduisent fortement la concentration tonale : motor 53,79→6,13 %, hum 42,29→6,10 %, carrier 22,99→4,52 % dans le bin le plus énergétique. Le RMS reste voisin de −19 dBFS : la réduction des raies n'est donc pas un simple abaissement général de niveau.

Le 302 traité passe de 7,73→0,789 % en 3–6 kHz pour motor et de 3,73→0,375 % pour hum. Le raccord motor passe de +4,88→−14,49 dB par rapport au pas typique, hum de −7,10→−10,59 dB. La relative concentration du pic principal ne diminue pas pour ces captations déjà larges bandes : 2,04→2,20 % et 0,72→0,74 %, résultat compatible avec la réduction du souffle aigu. Cela ne prouve pas une identité moteur mieux reproduite.

La nouvelle 305 est **modélisée** : bins dominants 5,54/6,94 % pour motor/hum, crêtes −6,69/−6,57 dBFS. Ce résultat soutient une texture moins sinusoïdale que l'ancienne synthèse partagée ; aucune captation réelle 305 ne permet de valider son timbre exact. Le frein électrique regen a un bin max de 1,97 %, crête −6,87 dBFS.

Le raccord real_rail traité passe de +27→−12,96 dB. Première génération : les raccords TFS hum (+7,54 dB) et Urbos motor (+8,37 dB) se dégradaient ; ces deux points ont été signalés immédiatement au designer puis corrigés. **Vérification finale des deux OGG** (`seam-verification.json`) : −31,57 / −31,56 dB, crêtes −1,85 / −2,52 dBFS. Les sources restantes montrent une forte baisse de la bande 3–6 kHz, sans clipping détecté. TFS hum conserve un pic principal important (24,19→15,74 %), donc la fenêtre transitoire d'origine reste une limite même après égalisation. Une version plus douce peut perdre des détails caractéristiques : validation d'écoute nécessaire avant de qualifier le résultat de fidèle.

## Extension aux onze références complémentaires

L'analyse finale `raw-windows.json` couvre bien les 19 fichiers, sans échec de décodage. Les onze ajouts ci-dessous complètent les catégories de sons. Leur contenu nommé provient du titre et de la description de la source ; les événements sont seulement localisés par énergie, sans reconnaissance perceptive. Les références historiques néerlandaises ne certifient aucun tramway français moderne.

| Fichier / catégorie attribuée à la source | Fenêtres intéressantes, secondes source | Limites / exclusion |
| --- | --- | --- |
| `tram-doors-cologne-original.ogg` — portes, 13,923 s | Série étroite vers 2559Hz : 6,81–7,27 ; 7,58–8,06 ; 8,31–8,73 ; 9,03–9,42 ; 9,75–10,19 ; 10,47–10,93 ; 11,19–11,49 s. Inspecter 6,6–11,8s pour conserver attaques et queues. | Modèle inconnu ; référence apparentée/générique, pas portes Citadis302/305 authentifiées. La zone0–6s comporte surtout une composante très grave ; ne pas augmenter sans filtrage/écoute. One-shot, pas boucle moteur. |
| `diverse-bellen-van-een-tram-soundcloud-beeld-en-geluid.ogg` — cloches/gongs historiques, 76,679 s | Salves d'énergie2,4–3,5kHz à0,95–3,68 ; 9,48–11,39 ; 19,10–20,24 ; 21,42–22,31 ; 35,45–36,86 ; 52,96–53,98 ; 63,64–64,59 ; 70,51–71,73 s. Première frappe candidate 0,8–4,2s, pics 2512/3320/1117Hz. | Plusieurs types de cloches, aucun302/305 certifié. Salves à comparer à l'écoute avant de choisir un one-shot ; garder décroissance et silence, ne pas normaliser les silences inter-frappes. |
| `noodrem-van-een-tram-soundcloud-beeld-en-geluid.ogg` — frein d'urgence historique, 64,707 s | Fond stable 14–18s et16–20s (~−22dBFS), événement plus fort 24–28s /26–30s (~−17dBFS). Examiner23–31s en séquence complète. | Ne peut pas identifier un patin électromagnétique moderne à partir d'un niveau. Pas une boucle permanente ; contenu hors événement et éventuelles voix à vérifier. |
| `arriv-e-d-une-rame-citadis-402-la-station-porte-d-ivry.ogg` — arrivée402, 23 s | 6–10s /8–12s relativement homogènes, pics179/285Hz ;12–18 s plus fort et plus grave. | Référence exacte402 pour séquence d'arrivée ; ne pas l'attribuer au302/305. Associer seulement après écoute les phases au freinage/roulement. |
| `omvormer-en-compressor-van-een-tram-soundcloud-beeld-en-geluid.ogg` — convertisseur/compresseur, 111,616 s | 88–92s /92–96s : variation<0,75 dB, pics 414–422/250–309Hz, candidats de boucle auxiliaire.12–18 s contient une forte excursion et des pics jusqu'à6,8 kHz. | Référence auxiliaire générique historique ; exclure12–18 s d'une boucle stable, éviter ajout permanent du sifflement. |
| `het-vertrekken-van-een-elektrische-tram-soundcloud-beeld-en-geluid.ogg` — départ historique, 32,913 s | 8–12s /10–14s, ~−30dBFS, dominante43–55Hz. | Référence de séquence, beaucoup de grave ; aucune identification d'onduleur français. Ne pas confondre vent/rumble et traction. |
| `het-voorbijrijden-van-een-elektrische-tram-soundcloud-beeld-en-geluid.ogg` — passage historique, 108,776 s | 16–22s, plus fort (~−23dBFS pour18–22s), pics 562/609Hz. | Passage dynamique ; fenêtres de fond12–16s/94–98s ~−43dBFS à ne pas normaliser comme moteur. |
| `ratelend-voetgangerslicht-en-voorbij-rijdende-tram-soundcloud-campos.ogg` — signal piéton + passage, 64,391 s | 20–24s /22–26s : passage grave dominant ;46–52s : raie 1871Hz stable. | Le titre annonce explicitement un signal piéton ; **exclure la raie 1871Hz d'une identité de moteur** et vérifier son recouvrement temporel avant toute utilisation. |
| `urbos3-birmingham-original.ogg` — Urbos3, 42,688 s | 16–22s plus fort, pics 105/152/164Hz ;8–12s plus faible. | Description de source signale annonces, bips et craquements : pas de fenêtre certifiée sans paroles. Référence Urbos3 exacte de famille, apparentée pour Luxembourg ; ne pas boucler l'annonce ou les bips. |
| `lemans302-original.mp3` — passage302, 20 s | 6–10s /8–12s : pics 246–351Hz, variation7–13dB. | Très dynamique, pas un régime stationnaire ; origine302 déclarée, pas305. Fin14–18s faible (~−38dBFS) à ne pas amplifier. |
| `lyon-citadis-original.ogg` — Citadis Lyon, 77,611 s | 10–14s /54–58s : passage plus fort, pics 246–297Hz ;24–28s faible. | Sous-modèle non vérifié ; niveau moyen faible, passages très dynamiques. Ne certifie pas une305 ; prudence bruit de fond/voix. |

`event-candidates.json` contient les salves énergétiques de portes/gong/frein d'urgence, calculées sur des trames de 10 ms après Butterworth passe-bande ordre 3. Seuils RMS de bande : portes 2400–2700 Hz à −45 dBFS ; gong 2400–3500 Hz à −42 dBFS ; frein 400–3000 Hz à −30 dBFS ; gaps <100 ms réunis, événements <30 ms ignorés. Ces seuils localisent l'énergie, pas une signification sonore. Les temps de salves ne comprennent pas nécessairement les queues faibles : ajouter du contexte avant extraction.

## Vérification des captures réelles Godot

Captures finales fournies par l'agent de test : `samples/demos/citadis_302_godot_mix.wav` (47,957 s) et `citadis_305_godot_mix.wav` (47,925 s), stéréo 48 kHz, `AudioEffectRecord` sur Master, scénario de 48 s avec MissionSession et vitesse imposée. Ce sont des sorties réelles du moteur, pas un rendu DSP Python supposé équivalent. Le scénario comprend portes, traction, roue libre, freinage, perspective et zones acoustiques, puis pause et reprise. Le frein d'urgence n'est pas déclenché dans ce scénario.

| Mesure sur le WAV stéréo natif | 302 | 305 modélisée |
| --- | --- | --- |
| Sonie intégrée EBU R128 / ffmpeg | −29,6 LUFS | −29,6 LUFS |
| LRA | 4,8 LU | 4,7 LU |
| Crête vraie EBU R128 | −15,1 dBFS | −15,7 dBFS |
| Échantillons ≥0,999 | 0 % | 0 % |
| Plus grand saut entre échantillons voisins natifs | −34,42 dBFS | −34,05 dBFS |
| Énergie 3–6 kHz en traction (8–22 s) | 0,154 % | 0,156 % |
| Énergie 3–6 kHz en freinage (27,5–38,5 s) | 0,065 % | 0,064 % |

Preuves : `godot-302-loudness.txt`, `godot-305-loudness.txt`, `godot-mixes.json` et `godot-phases.json`. Les mesures EBU portent sur la stéréo native. Les sections de `godot-phases.json` utilisent la moyenne arithmétique gauche/droite puis un rééchantillonnage à 16 kHz : aucune hausse automatique de 3 dB du downmix ffmpeg. Le diagnostic générique `godot-mixes.json` utilise le downmix ffmpeg annoncé par le script, dont le gain diffère pour les canaux corrélés ; ses niveaux mono ne doivent pas remplacer les crêtes natives ci-dessus.

RMS de section (moyenne arithmétique stéréo) : environ −32,5 dBFS à l'arrêt initial, −30,5 dBFS en traction, −30,5/−30,8 dBFS en roue libre et −31,7 dBFS en freinage. Aucun clipping détecté ; les sauts natifs maximaux restent bien inférieurs aux crêtes globales, sans preuve de discontinuité numérique de pleine échelle. Cela ne certifie pas l'absence de clic faible. À 44,5–45,5 s, les deux captures sont exactement nulles : pause audio effective. La reprise à 46,5–47,5 s contient de nouveau le fond sonore.

La très faible énergie 3–6 kHz du mix et les niveaux similaires entre les deux scénarios confirment un mix doux dans ces conditions ; ils ne démontrent ni une différence perceptible d'identité entre 302/305, ni l'authenticité de la 305, ni l'absence de sons parasites intégrés. Aucune capture du mix antérieur n'a été fournie : la comparaison avant/après disponible concerne les fichiers de banque, pas deux prises Godot identiques. L'écoute humaine reste la limite principale explicitement ouverte.
