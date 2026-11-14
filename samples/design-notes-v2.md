# Révision2 — correction de comparaison et préservation du302

Le premier extrait305 sélectionnait en réalité la banque302 : identifiant `citadis_305` non canonique, repli silencieux du résolveur. Le script de capture refuse désormais toute famille inconnue, toute variante incohérente et toute banque inattendue. Les rapports contiennent la famille résolue, la banque et les chemins des flux. Le305 utilise `citadis_x05` / `citadis305_model`. La302Angers utilise `citadis302`, contrairement à l’ancienne note erronée qui annonçait LeMans ; les JSON de provenance font autorité.

`tools/audio/design_samples_v2.py` génère quatre nouveaux dérivés pour les deux banques302 existantes (Moscou et LeMans). Il conserve le spectre des fichiers source, leurs raies naturelles et leur bande passante, avec recouvrement180ms et garde de raccord8ms. La réduction uniforme des pics spectraux et le filtre fichier2600Hz de lav1 sont retirés pour ces dérivés. Les originaux et lav1 ne sont pas écrasés ; les licences sont répétées dans `data/audio/design-manifest-v2.json`.

Les niveaux de banque302 réduisent l’empilement de roulements communs et l’ambiance/HVAC. Le modèle305 existant conserve exactement ses fichiers : seul le mixage réduit les fonds communs. Aucun nouveau modèle305 prétendument fidèle n’est inventé. Le passe-bas cabine passe de1600 à2400Hz pour conserver davantage de détail ; égaliseur et limiteur de sortie restent actifs.

Les captations passantes ne sont pas des moteurs isolés calibrés à une vitesse. Leur transposition reste bornée. Portes et gong restent communs et synthétiques. L’accès audio des deux vidéos fournies par le joueur étant bloqué, ces changements ne peuvent pas être présentés comme leur reproduction.

Reproduction : Python NumPy/SciPy, `tools/audio/design_samples_v2.py`, puis importGodot et captures avec banques attendues. Lav1 correcte des deux matériels a été capturée avant générationv2. Voir `samples/demos/v2_before_provenance.json` si disponible ou `samples/tests/v2_before_provenance.json`.
