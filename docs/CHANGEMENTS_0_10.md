# 0.10.0 — décors, ouvrages et adhérence

La génération visuelle est commune aux 28 villes : chaque tuile est reconstruite
à l’exécution avec les nouveaux matériaux, détails et raccords. Les emprises IGN,
les voies OSM, les hauteurs et les arrêts restent les références géographiques.
Les façades et le mobilier ajoutés sont procéduraux ; ils ne sont pas des relevés
architecturaux individuels.

## Matériaux et architecture

Les textures sont calculées en mètres : brique, joints de pierre, enduit, tuiles,
ardoise, enrobé et dallage. Les dérivées du shader filtrent les petits motifs à
la distance, pour réduire moiré et scintillement. Une graine de façade constante
par triangle évite que le dessin des fenêtres change entre pixels. Les
menuiseries, appuis, vitrines et lumières de nuit varient par bâtiment ; les
stores et balcons sont modélisés sur la façade orientée vers la voirie.
Les teintes de toiture issues des orthophotos restent utilisées lorsqu’elles
existent. Les profils régionaux privilégient pierre, brique, enduit ou granite,
avec des accents de mobilier et des dallages par ville.

Les éclairages du décor mélangent paliers et diffusion douce, les contours du
monde sont plus discrets et le ciel fournit les réflexions d’environnement. Le
rendu mobile active MSAA 2× et le filtrage des ombres ; les budgets mobiles
restent distincts des réglages PC. Les tramways conservent leurs livrées.

## Végétation et voirie

Aux sept silhouettes d’arbres s’ajoutent arbustes, graminées et vivaces fleuries.
Le feuillage des arbres est plus détaillé et les petites plantes enrichissent
aussi les tuiles disposant déjà d’arbres issus des orthophotos. Les chaussées,
chemins et voies sont exclus des implantations. Il s’agit d’une diversification
visuelle, sans inventaire écologique des espèces.

Les bandes routières partagent leurs raccords : elles ne dépassent plus d’une
demi-largeur à chaque sommet. Les trottoirs disposent d’une bordure verticale,
d’un dallage surélevé et de mobilier ponctuel. Ils sont interrompus aux routes
transversales pour éviter les trottoirs traversant le carrefour.

La recherche de pont échantillonne les routes longues : un court tablier près
d’une extrémité peut être suivi. Les routes perpendiculaires restent au niveau
inférieur. Les approches raccordent progressivement le tablier au terrain.
Les niveaux IGN supplémentaires sont exploités dans les **11 villes couvertes
par le cache disponible** ; ailleurs, l’association géométrique reste utilisée.
La couverture exacte figure dans [world-010-coverage.json](world-010-coverage.json).
Les ambiguïtés d’altimétrie ou les ouvrages absents des sources peuvent encore
nécessiter une correction locale.

## Caténaires

Les poteaux proches des aiguillages sont remplacés par des suspensions en retrait.
Un index spatial vérifie le gabarit des voies voisines, avec prise en compte de
leur altitude. Les raccords de fils rejoignent les extrémités réellement rendues ;
les branches de niveaux différents restent séparées. Un nœud mixte LAC/APS ne
supprime plus l’équipement des branches LAC. Les recouvrements de station et les
rails APS introduits en 0.9.3 restent actifs.

## Physique

La vitesse interne est signée dans le sens de la cabine. Au neutre en rampe,
la gravité peut donc provoquer un vrai recul, y compris à travers un nœud de voie,
sans inverser la cabine. Le HUD et les portes utilisent la valeur absolue de la
vitesse ; une alerte **RECUL** invite à appliquer le frein.

La traction est limitée par l’adhérence et la masse sur les essieux moteurs.
Une demande trop forte déclenche **PATINAGE**, réduit l’effort utile et fait
varier le son de traction. Réduire le manipulateur rétablit l’adhérence. Les
coefficients (rail sec 0,26 ; fraction motorisée 0,55 ; paramètres modifiables)
sont des estimations du simulateur, pas des mesures par constructeur. Le
coefficient humide est couvert par les tests, sans nouvelle météo jouable.

F3 et le frein d’urgence agissent dans les deux sens. Le frein de maintien
s’enclenche portes ouvertes, ce qui évite le recul pendant une desserte. Le
départ reste en F3 ; les horaires GTFS et la tolérance de retard sont inchangés.
Le freinage n’introduit pas de risque supplémentaire d’enrayage dans cette version.

## Vérification et livraison

Tests d’adhérence, de recul, de maintien portes ouvertes, de traversée de nœud,
de raccords routiers, d’association des tabliers, de niveaux IGN, de gabarit des
poteaux et de séparation des fils en altitude. La suite complète contrôle aussi
les 120 missions, les 149 fichiers de réseau, les stations et l’interface tactile.
Captures OpenGL à Angers (jour et ombres), Toulouse et Nice (nuit). Aucun essai sur
un téléphone physique ; le coût graphique mobile doit encore être mesuré sur
les appareils des joueurs.

Version Android 0.10.0, code 13 ; export Windows 0.10.0. Les tags de livraison
reprennent désormais la version du jeu et le numéro de build, par exemple
`v0.10.0-build.N`, sans modifier les anciennes releases.
