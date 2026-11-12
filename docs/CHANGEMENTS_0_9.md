# Tram Sim France 0.9 — conduite, stations et tactile

Le geste de défilement tactile reste attaché au conteneur où il a commencé,
y compris en traversant un bouton ou en sortant du panneau. Le clic est annulé
après le seuil de glissement et une inertie est appliquée une seule fois. Les
scrollers imbriqués et l'axe des curseurs restent distincts.

## Stations et énergie

`tools/import/station_power.py` enrichit les 28 réseaux libres et les 120 fichiers
de lignes depuis leurs instantanés OSM versionnés. Les identifiants GTFS des
nœuds `stop_position` sont prioritaires ; à défaut, le nom et la proximité dans
le même quartier servent au rapprochement. 2 953 arrêts libres sur 3 371 portent
une référence à un nœud OSM. Les autres positions restent issues du GTFS.
Les départs de mission sont replacés avant le premier arrêt ; un quai au nœud
entre deux tronçons est reconnu depuis le tronçon précédent.

3 113 quais sont rendus dans leur repère géographique. Les surfaces fermées
conservent leurs sommets OSM ; les lignes ouvertes gardent le tracé cartographié,
avec largeur estimée lorsque `width` est absent (1 626 cas). La largeur estimée
est placée du côté opposé aux voies si un tampon centré les recouvrirait.
Hauteur de quai : 30 cm estimés. Aucun quai procédural de remplacement n'est
ajouté aux réseaux enrichis. Bordures, abris lorsque `shelter=yes` et bancs
suivent les empreintes ; les détails architecturaux restent stylisés. Le côté
des portes est déterminé à partir du quai le plus proche.

Les tags OSM `electrified` remplacent les anciennes suppositions : notamment
281 sections APS dans les réseaux libres. Les missions conservent des zones
électriques locales lorsque plusieurs modes traversent une même arête GTFS.
Une voie non électrifiée n'est pas assimilée à une alimentation APS. Nice
conserve ses sections autonomes sur batterie.

Le pantographe est initialisé selon la section de départ. Sur les matériels
hybrides, levé = LAC, abaissé = APS ou alimentation autonome. Une incompatibilité
coupe la traction et applique au moins F3 jusqu'à l'arrêt : la rame en mouvement
freine progressivement ; à l'arrêt elle reste immobilisée dans une pente de
8 %. L'adaptation du matériel en mode libre garde cet interverrouillage.
Au début d’une ligne sans historique derrière la rame, le modèle prolonge
visuellement la tangente pour garder les caisses espacées, sans ajouter de voie.
Le manipulateur apparaît en F3 (-75 %) ; la pente signée dans le sens de marche
est affichée séparément à côté du compteur, en ‰.

## Rendu, son et vitesse

Les sections LAC ont poteaux, consoles, isolateurs, contact et porteur,
pendules et suspensions aux nœuds d'aiguillage. Chaque branche rejoint le même
point de contact, sans relier les croisements dénivelés. L'APS utilise des
segments de contact centraux séparés par des joints isolants. L'implantation
des poteaux et les pièces de jonction sont procédurales, non un relevé des
équipements réels.

Les vitres ont des reflets stylisés du ciel et des éclats dépendant du regard.
Il s'agit d'un ciel analytique, pas de reflets géométriques de toute la ville.
Le champ de vision s'ouvre progressivement avec la vitesse ; des traînées
périphériques discrètes ne recouvrent pas le HUD.

Une captation libre de tramway lyonnais de Glaneur de sons (CC BY 3.0) complète
les couches synthétiques. La recette d'extraction, le fichier original et les
crédits sont versionnés. Les ponts renforcent les résonances graves ; les tunnels
appliquent de la réverbération et atténuent l'ambiance extérieure, également en
cabine. Ce n'est pas une banque enregistrée propre à chaque modèle de rame.

Les limites locales sont calculées depuis les rayons de courbe (fenêtre de
16 m, accélération latérale estimée de 0,9 m/s², arrondi inférieur à 5 km/h),
ainsi que les changements de direction aux jonctions. La branche sélectionnée
et la queue du tram sont prises en compte. Une restriction à venir est annoncée
jusqu'à 220 m devant lorsque le conducteur doit ralentir. Ces limites calculées
ne remplacent pas un relevé officiel des panneaux du réseau.

## Vérification et limites

Tests de conduite sur les 120 lignes : fin de mission atteinte sans arrêt oublié
ni départ anticipé. Certains horaires GTFS restent serrés avec les limites et
matériels estimés ; la ponctualité parfaite n'est pas garantie sur chaque service.
Contrôles supplémentaires : freinage et maintien en pente après coupure,
rayon connu de 20 m, portes selon empreinte, correspondance GTFS/OSM, capture
et inertie tactile, HUD 640×360 / 800×450 / 1280×720, routage sonore.

L'APK local est signé et contient les 28 réseaux hors ligne, sans les archives
sources géographiques ni le fichier audio original. L'EXE Windows est démarré
sous Wine en mode headless. Les captures OpenGL vérifient aussi les shaders.
Aucun essai sur un téléphone Android physique n'a été effectué ici.

La géométrie des missions reste celle du GTFS, projetée sur les arrêts OSM dans
une tolérance de 30 m ; elle peut encore différer des rails physiques dans les
zones recensées dans `world-quality.json`. Les altitudes restent les estimations
IGN de la version précédente. Les dates OSM sont celles des instantanés livrés,
pas une promesse de cartographie à jour en temps réel.
