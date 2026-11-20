# Lot P0-B — QA géométrique en lecture seule

Lot indépendant des sauvegardes et de l'instrumentation. Aucune carte, tolérance des
tests existants, donnée OSM/IGN/GTFS ni primitive de rendu n'est modifiée.

## Résultats réellement calculés

- Contrôle existant `test_clearance.gd` : **2 634 970 vérifications, zéro échec** sur
  les lignes commerciales à décor IGN. Ce contrôle saute les tunnels et ne balaie
  pas toute la forme articulée : ce n'est pas un certificat de gabarit national.
- Nouveau préflight : **148 fichiers** (120 commerciaux, 28 libres), **24 765 constats**
  à examiner : 12 808 écarts d'extrémité par rapport aux nœuds OSM locaux, 11 731 écarts
  de longueur déclarée/polyligne, 226 discontinuités de jonction. Seuils explicites
  de politique QA, pas précision des relevés constructeur. Aucune correction cachée.
- Recalcul sur les mêmes sources/configuration : **zéro régression**, mêmes constats.
  Cela valide la répétabilité du contrôle, pas la disparition des 24 765 écarts.
- Export réel `CityScene._decks/deck_piles` après bind_network à Nantes : **916 volumes**.
  Test du corps articulé Citadis 302 sur ce graphe libre : **126 intersections candidates
  de volumes conservatifs**, plus 612 écarts de longueur. Les volumes/profils sont des
  approximations documentées ; aucune de ces 126 entrées n'est présentée comme une
  collision physique confirmée ni corrigée sans examen.
- Audit sol existant : 28 villes, 5 879 tuiles, **1 erreur restante**. Les tests géographie
  existants donnent aussi un écart de 0,097995 m à Angers contre la tolérance 0,0015 m.
  Ces échecs sont préservés. L'environnement Python principal manquait shapely ; la
  vérification a été refaite avec le venv géographique déjà présent, sans installation.
- **14 tests Python** : collisions, séparation en hauteur, rampes, courbe avec déport
  de caisse, continuité, source OSM, route inversée, absence de connexion à un simple
  croisement, données invalides, exclusions contrôlées, échappement HTML et contrôle
  de régression (y compris aggravation d'un même constat et perte de couverture).
- Import Godot et export des volumes exécutés. Aucune capture visuelle ni validation
  humaine des volumes n'est revendiquée.

Rapport intégral reproductible : `geometry-baseline.json.gz` ; résumé JSON et HTML
versionnés. L'HTML du résumé montre cinq exemples par réseau, explicitement signalés.
Le rapport intégral est conservé, sans exclusions implicites. Le rapport candidat de
Nantes est `nantes-swept-baseline.json.gz`. Les rapports complets HTML sont générés
localement par la CLI. Le quota d'artefacts GitHub étant saturé, ces références utiles
au contrôle de régression sont conservées dans le dépôt plutôt que supprimées.

## Interface

```sh
python tools/qa/geometry_audit.py data/networks/*.json data/free/*.json --verify-osm --output .cache/geometry.json
# Code 1 si constats ouverts ; code 2 si données/configuration invalides.
python tools/qa/geometry_audit.py data/networks/*.json data/free/*.json --verify-osm --baseline docs/p0/geometry-baseline.json.gz --output .cache/delta.json
# Code 1 si constat nouveau/aggravé ; le même ensemble de réseaux est obligatoire.
# --report-only produit un inventaire sans prétendre accepter les cartes.

godot --headless --path . -s tools/qa/export_geometry_obstacles.gd -- res://data/free/nantes.json res://.cache/nantes-obstacles.json
python tools/qa/geometry_audit.py data/free/nantes.json --plan data/rolling_stock/plans/citadis_302.json --obstacles .cache/nantes-obstacles.json --output .cache/nantes.json
python -m unittest discover -s tests -p test_geometry_audit.py
```

Le manifeste d'obstacles est lié au SHA du graphe exact ; coordonnées x,z et hauteur
relative au rail en mètres. Chaque obstacle exige ID, polygone, bornes verticales et
provenance. Un index spatial borne les comparaisons ; les caisses rigides sont placées
sur leurs cordes, avec marge de 0,1 m et plancher du plan fourni. Les volumes sont
conservatifs, sans simulation de débattement de suspension ni certification d'enveloppe.

Pour balayer une route multi-arêtes, `--route route.json`, par exemple :
`{"sections":[{"edge":"a","direction":1},{"edge":"b","direction":-1}]}`.
Les connexions doivent être topologiques ; un croisement XY ne connecte jamais les
voies. Sans route explicite, le balayage par arête extrapole ses extrémités ; les
jonctions sont contrôlées séparément. Cette limite figure dans chaque rapport.

## Incertitudes, exclusions et couverture

Incertitude inconnue : null, jamais zéro inventé. Une intersection entre volumes
estimés est une candidate à examiner. L'export courant couvre tabliers/piles et déclare
explicitement absents mâts LAC, fils, maillages tunnels/quais/eau/terrain. Les fixtures
peuvent tester ces classes lorsqu'un manifeste explicite est fourni ; cela ne prouve
pas leur couverture réelle nationale. Les tests natifs du jeu et audit_ground restent
obligatoires et ne sont pas remplacés par une CI synthétique verte.

Une exclusion facultative exige finding_id exact, reason, author, evidence_url,
expires (date UTC) et evidence_sha256 du constat. Modification des preuves, expiration,
ID inconnu ou règle incomplète : rejet. Le constat reste affiché avec sa justification.
Aucune exclusion de production n'est ajoutée ici.

## Risques et suite

Les erreurs ne sont pas 24 765 collisions : séparer erreurs numériques, décalage par
rapport à une source et volumes rendus approximatifs avant correction. Les limites de
polyligne et les raccords de tablier doivent être confirmés sur captures et sources.
Les seuils ne sont pas ceux d'une homologation ferroviaire. Toute évolution du format
ou du calcul doit garder l'identité du rapport et expliquer une nouvelle baseline.

Rollback : revert du commit de ce lot ; supprimer seulement les rapports/caches QA si
souhaité. Aucun effet sur sauvegardes, conduite, interface ou assets. Les anciens tests
restent inchangés. Les étapes de rendu ou de modification des cartes restent des lots
ultérieurs, pas un effet secondaire de l'audit.
