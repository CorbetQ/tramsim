# Audio dérivé et modélisé

Les crédits, pages sources, auteurs, licences et empreintes des captations originales sont dans `families.json`. Chaque fichier `banks/*_designed.ogg` est une adaptation de son homonyme sans `_designed`, par `tools/audio/design_samples.py` : contrôle de résonances, filtre circulaire, raccord et normalisation. Les fichiers dérivés conservent la licence de leur source. Le manifeste `design-manifest.json` répète auteur, page source et licence, et fournit les empreintes des dérivés.

Les banques `citadis305_motor.ogg` et `citadis305_motor_hum.ogg`, ainsi que motor, motor_hum, carrier et regen, sont des créations procédurales du projet sous la licence du code. Elles ne sont pas des captations de Citadis 305, ni des dérivés du 403. Leurs paramètres sont des estimations artistiques.

Voir `samples/design-notes.md` pour le protocole reproductible, les limites et les démos réelles de conduite.

## Révision2

Les quatre fichiers `v2/*302*.ogg` sont dérivés des originaux de banque302 ; auteur, page, licence et SHA256 figurent dans `design-manifest-v2.json`. Traitement : préservation spectrale, recouvrement et normalisation. La banque305 garde ses créations procédurales précédentes. Aucune piste YouTube fournie par le joueur n’est intégrée.
