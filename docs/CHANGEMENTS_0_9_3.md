# 0.9.3 — quais de transition et zones d'arrêt

Les stations associées à un quai OSM disposent d'une zone d'arrêt sur toute sa
longueur projetée sur la voie, avec 1 m de marge. Elle peut traverser plusieurs
arêtes du graphe. Le repère OSM existant est inclus lorsqu'il est proche de
l'emprise. Le HUD reste « à quai » et conserve le nom de la station tant que le
nez de la rame est dans cette zone, même après le repère d'arrêt. Les portes
permettent alors de valider la desserte en mission. Un arrêt non desservi n'est
compté oublié qu'après sortie complète de la zone du nez. Le repositionnement
après un cycle de portes ne passe pas prématurément à la station suivante.
La validation de la station desservie attend la sortie, mais le score conserve
l'heure du début du départ ; horaires et tolérance de retard GTFS inchangés.
Le terminus continue à terminer la mission après fermeture des portes.

Les quais précédant une limite LAC/APS disposent des deux alimentations. Le rail
APS et la LAC sont dessinés simultanément sur cette emprise et chacun des modes
peut alimenter la rame. La commutation exige toujours l'arrêt et prend 0,6 s.
Après sortie de la zone de recouvrement, le mode de la section redevient seul
autorisé. L'affichage précise « LAC + APS », avant le nombre de voyageurs pour
rester lisible sur petit écran. Le moteur sonore suit le mode réellement choisi.

L'import détecte aussi les limites sur une branche d'aiguillage : à Foch–Maison
Bleue, la branche vers la section APS diverge d'une continuité restant sous LAC.
Les deux quais et leurs raccords jusqu'à cet aiguillage sont couverts ; aucune
extension n'est ajoutée à la branche LAC qui continue au-delà de l'aiguillage.
Les coupures de maillage suivent les bornes exactes des zones, plutôt que de
déborder par pas de 5 m.

Les zones sont calculées par `tools/import/platform_zones.py` depuis les emprises
OSM déjà livrées. Les limites proches (dans le quai ou à moins de 30 m) déclenchent
un recouvrement, incluant le court raccord jusqu'à la limite. Il s'agit d'une
déduction cartographique, pas d'un relevé des équipements de chaque exploitant.
Sans quai associé de manière fiable, la tolérance ponctuelle antérieure est
conservée. Aucun quai, tracé de voie, hauteur ou horaire n'a été déplacé.
`station_power.py` relance désormais cette étape après réimport.

Couverture : 6 568 enregistrements d'arrêt associés à une emprise de quai et 111
enregistrements de transition, dans les graphes libres et les missions (avec
doublons entre lignes et modes). Détail dans `docs/platform-zones.json`.

Tests : quai traversant un nœud, desserte et oubli aux deux extrémités, parcours
inverse, repositionnement et score de départ, alimentation dans les deux modes,
coupure hors recouvrement, maintien du délai, Foch dans les deux directions,
branche APS à l'aiguillage, absence d'extension sur la continuité LAC, import
idempotent, géométrie inchangée et contrôles de bornes sur les 149 fichiers.
Capture OpenGL à Foch–Maison Bleue et suite complète de régression. Aucun essai
sur téléphone physique.
