# TramSim France : spécification technique et prompt Codex

Date : 15 novembre 2026. Dépôt privé : `CorbetQ/tramsim`. Branche observée : `ccr-73402276-ntwr5h`. Dernier commit observé : `be7eda97e5de6b4cdd1cedc9ee16e911537313d3` (WIP 0.13, 14 novembre 2026).

> Audit statique partiel : les fichiers et historiques ont été consultés via GitHub. Aucune compilation ni exécution de benchmark n'a été réalisée pour cette spécification. Les fichiers de documentation historiques décrivent parfois des défauts qui peuvent avoir été corrigés depuis. Codex doit réévaluer l'état exact du code avant chaque lot.

## Objectif et contraintes transversales

- Conserver Godot 4.6.3, GDScript, Android/Windows, le fonctionnement hors ligne, la direction artistique low-poly/cel-shading, les 28 réseaux libres, les 120 missions/variantes documentées, les données GTFS/OSM/IGN, les profils de matériels, les modes mission/libre/exploration, le pilotage automatique, les sons, les sauvegardes et les tests.
- Ne pas supprimer ou réécrire un système existant sans preuve de nécessité. Préférer extensions, adaptateurs et migrations.
- Séparer données géographiques sourcées, données estimées et enrichissements procéduraux. Conserver licences, crédits, provenance et reproductibilité des imports.
- Simulations déterministes avec graine configurable et pas fixe ; rendu, audio et interface découplés des règles métier.
- Chaque lot doit produire : état initial, fichiers modifiés, conception, tests, métriques avant/après, risques, captures si visuel, instructions de retour arrière.
- Exécuter `tests/run_all.sh` lorsque l'environnement le permet, tests ciblés à chaque PR, vérification import Godot et exports Android/Windows dans la CI adaptée.
- Aucune valeur chiffrée de performance ou de précision ne doit être présentée comme mesurée avant test réel.

## Lot 0 : état des lieux, architecture et instrumentation

1. Vérifier `git status`, branche, SHA, README, `docs/ROADMAP.md`, `docs/AUDIT_0_8.md`, `docs/AUDIT_VISUEL_0_11.md`, derniers commits et tickets.
2. Inventorier `src/catalogue`, `src/simulation`, `src/modes`, `src/rendering`, `src/audio`, `src/ui`, `tools/import`, `tests`, `data` ; établir une matrice existant/partiel/absent pour les 20 exigences.
3. Créer `docs/architecture/` avec diagramme des dépendances et contrats des systèmes. Établir des tests de non-régression avant toute modification.
4. Définir un format de rapport machine lisible pour performances, topologie, rendu, missions et provenance des données.

## Lot 1 : fondations et fiabilité (P0)

### 1. Migrations des sauvegardes
**Existant :** `src/catalogue/save_game.gd` stocke `version=1`, fusionne les valeurs par défaut, écrit via `.tmp`, mais revient à une sauvegarde neuve pour une version inconnue. `tests/test_save.gd` existe.
**À réaliser :** migration incrémentale `v1 -> v2 -> ...`, validation de schéma, sauvegarde préalable `.bak`, lecture tolérante des champs inconnus, reprise des identifiants de réseaux et des arêtes lors des changements de graphe, récupération après interruption d'écriture. Version future inconnue : afficher une erreur non destructive, ne jamais écraser le fichier.
**Tests :** fixtures de sauvegardes anciennes, JSON corrompu, coupure pendant écriture, version future, reprise de session sur réseau modifié, compatibilité Android/Windows.
**Acceptation :** aucune progression valide perdue ; migration idempotente et traçable.

### 2. Tests de gabarit et de géométrie
**Existant :** tests de clearance et de géographie, `tests/run_clearance.sh`, `tools/qa/audit_ground.py`, `tools/import/validate_networks.py` ; audits historiques de ponts, trémies, terrain et caténaires.
**À réaliser :** pipeline géométrique systématique : enveloppe de rame balayée sur voie, dégagement des tabliers, piles, poteaux, caténaires, tunnels, quais, obstacles ; continuité verticale/horizontale, intersections routières, maillages d'eau, joints de tuiles, raccords d'aiguillage. Distinguer vrais positifs, incertitude cartographique et exclusions documentées.
**Tests :** fixtures synthétiques de collision, profils courbes et rampes, échantillons de tous les réseaux, rapport JSON/HTML géolocalisé.
**Acceptation :** aucune collision de gabarit non justifiée dans les parcours de référence ; rapport reproductible.

### 3. Caméra, eau et ouvrages
**Existant :** `src/rendering/city_scene.gd`, `line_view.gd`, `day_night.gd`, tests de monde ; `docs/AUDIT_VISUEL_0_11.md` rapporte historiquement caméra bloquée, eau au-dessus des voies, ponts et tunnels incohérents.
**À réaliser :** collisions caméra contre surfaces réelles, rayon de sécurité et orbite alternative ; niveaux d'eau géoréférencés et exclusion des ouvrages couverts ; gestion explicite des tabliers, piles, portails et trémies ; correction des incohérences par ville sans masquer les défauts avec le brouillard.
**Tests :** captures jour/nuit/cabine sur cas documentés, test de gabarit 3D et non-régression multi-villes.
**Acceptation :** aucun obstacle majeur devant la caméra ni eau traversant une voie sur les cas tests.

### 4. Mesures de performance Android
**Existant :** réglages mobiles, LOD et streaming ; `docs/ROADMAP.md` et audits signalent l'absence de mesures physiques concluantes.
**À réaliser :** scénario de benchmark reproductible (chargement, conduite dense, caméra libre, nuit, pluie, terminus), export JSON/CSV des frametimes CPU/GPU si disponibles, FPS P50/P95/P99, mémoire, chargements, draw calls, nombre d'objets et consommation/thermique si accessible via Android. Identifier appareil, OS, mode d'alimentation et build.
**Tests :** automatisation du parcours, validation de la télémétrie, comparaison baseline/candidat ; profils qualité mobile.
**Acceptation :** budgets explicitement configurés et résultats mesurés sur au moins deux gammes d'appareils avant toute promesse de FPS.

## Lot 2 : géographie et exploitation (P0/P1)

### 5. Recalage des missions sur les voies OSM
**Existant :** `tools/import/gtfs_to_network.py`, `merge_city.py`, `src/catalogue/network_loader.gd`, `src/modes/mission_catalog.gd` ; `docs/AUDIT_0_8.md` signalait 42 590 sommets de tracés commerciaux sur 285 073 à plus de 25 m des voies physiques utilisées à l'époque.
**À réaliser :** projection des arrêts GTFS vers le graphe physique OSM, routage contraint par sens, aiguillages et accès quais, pénalités d'écart, validation des distances et de la topologie. Conserver horaires et géométrie de référence dans des champs distincts. Repli explicite si OSM incomplet, sans fabriquer une voie silencieusement.
**Tests :** cohérence arrêt/voie/quai, absence de téléportation, trajets aller-retour, points de retournement, écarts métriques par réseau.
**Acceptation :** toutes les missions existantes restent jouables et les écarts sont mesurés ; progression démontrée par rapport à la baseline.

### 6. Itinéraires et aiguillages
**Existant :** `src/modes/interlocking.gd`, `src/simulation/normal_routing.gd`, graphe d'occupation et signalisation.
**À réaliser :** état explicite des aiguilles, itinéraires réservés et libérés derrière la queue, incompatibilités et conflits, approche verrouillée, manœuvres de retournement, protections contre deadlocks, priorités configurables. Ne pas autoriser une connexion parce que deux lignes se croisent géométriquement.
**Tests :** deux rames concurrentes, cisaillements, voie unique, rebroussement, libération de canton, reprise après incident.
**Acceptation :** pas de collisions ou réservations contradictoires dans les scénarios de stress.

### 7. Horaires exacts des tramways IA
**Existant :** `src/simulation/ai_trams.gd` estime les intervalles selon l'heure, plafonne à 10 rames PC / 5 mobile et peut retirer une rame bloquée.
**À réaliser :** import de courses GTFS (`trips`, `stop_times`, `calendar`, `calendar_dates`, `frequencies`), identifiants de service et dates, courses enchaînées, terminus, retards et régulation. LOD de simulation sans disparition arbitraire : rames hors champ conservées dans un état logique léger.
**Tests :** heure >24 h GTFS, jours fériés, changements de jour, retards, dépassement de capacité, redémarrage et reproductibilité.
**Acceptation :** départs et arrêts conformes aux horaires source lorsque la simulation n'introduit pas d'aléas.

### 8. Priorité tramway aux carrefours
**Existant :** `src/simulation/road_traffic.gd`, `src/simulation/signal_model.gd`, `tools/import/crossings.py` et récent commit d'intégration `data/crossings.json`.
**À réaliser :** contrôleur de carrefour à états, demandes de priorité anticipées, phases de sécurité et temps de dégagement, priorité conditionnelle, conflits tram/voiture/piéton, feux routiers et signaux ferroviaires synchronisés. Respecter les données réelles disponibles ; marquer comme simulées les séquences inconnues.
**Tests :** arrivées simultanées, passage d'une rame longue, rame immobilisée, carrefour en défaut, prévention des conflits.
**Acceptation :** absence de feux incompatibles et circulation non bloquée indéfiniment.

## Lot 3 : immersion (P1)

### 9. Météo et adhérence
**Existant :** `TrainPhysics` gère l'adhérence et le sablage, mais la météo jouable n'est pas confirmée.
**À réaliser :** `WeatherState` indépendant du rendu : pluie, brouillard, vent, feuilles et humidité, transitions progressives, adhérence dépendant de l'état rail, essuie-glaces, éclairage et audio. Valeurs par matériel/conditions documentées, sans présenter des estimations comme mesures constructeur.
**Tests :** distance de freinage sec/humide, transitions, sauvegarde, reproductibilité.
**Acceptation :** effets physiques cohérents et réglables, mode météo désactivable.

### 10. Voyageurs et affluence
**Existant :** `MissionSession` gère embarquement/débarquement simplifiés ; `TrainPhysics` utilise la masse des voyageurs.
**À réaliser :** matrice origine-destination simplifiée, demande par arrêt/heure/jour, capacité par rame, flux portes, correspondances, occupation, temps d'arrêt variable, visualisation optionnelle à faible coût. Les données estimées doivent être signalées.
**Tests :** conservation du nombre de voyageurs, capacité, charge, temps de stationnement et performances.
**Acceptation :** aucune création/disparition incohérente de voyageurs et influence mesurable sur la marche.

### 11. Cabines interactives
**Existant :** HUD et commandes, profils matériels, caméra cabine ; ne pas remplacer l'interface actuelle.
**À réaliser :** système `CabControl` data-driven par famille de rame : manipulateur, portes, pantographe, éclairage, sablage, avertisseur, écrans et diagnostics. Entrées tactile/clavier/manette synchronisées, niveaux de réalisme et accessibilité.
**Tests :** mêmes commandes par tous les modes d'entrée, interverrouillages et UI petite résolution.
**Acceptation :** au moins une cabine pilote complète puis généralisation sans duplication.

### 12. Banques sonores
**Existant :** `src/audio/tram_audio.gd`, `data/audio/`, banques et outils d'analyse, tests audio ; certains sons sont des synthèses ou des captations apparentées.
**À réaliser :** manifestes de provenance/licence, couches traction-onduleur/roulement/vent/compresseur/portes/courbes/joints, crossfades continus selon vitesse, effort et adhérence, vues cabine/extérieure, acoustique tunnel et réverbération. Pipeline d'import FFmpeg hors runtime, normalisation et boucles propres. Génération IA facultative, jamais substituée sans attribution ou vérification de licence.
**Tests :** absence de clics, saturation, trous lors du changement de régime, transitions APS/LAC, usage CPU/mémoire.
**Acceptation :** banques distinctes, auditées, dégradations gracieuses si ressource manquante.

## Lot 4 : rendu et performances (P1)

### 13. Colorimétrie et brouillard
**Existant :** shaders cel/toon et `day_night.gd` ; audit visuel historique de double correction gamma et brouillard de hauteur absolu.
**À réaliser :** une seule chaîne de conversion colorimétrique, calibration sur photos et orthophotos, brouillard relatif au terrain/altitude locale, profils jour/nuit/pluie, réglages de saturation et glow mesurés.
**Tests :** captures de référence sur 28 villes, histogrammes et comparaison visuelle, contrôles des matériaux.
**Acceptation :** suppression des noirs bouchés et du voile uniforme dans les cas de référence.

### 14. Carrefours et trottoirs continus
**Existant :** générateur de voirie dans `city_scene.gd` ; audit historique de rubans superposés.
**À réaliser :** jonctions polygonales robustes, triangulation des intersections, trottoirs et bordures continus, traversées piétonnes, détection des niveaux séparés et des franchissements tram.
**Tests :** carrefours à 3/4/5 branches, angles aigus, ponts, trémies, triangulation sans auto-intersection.
**Acceptation :** aucun éventail de rubans ni trottoir traversant une chaussée dans les captures de contrôle.

### 15. Façades et éclairage nocturne
**Existant :** matériaux régionaux, vitrines, balcons, fenêtres éclairées ; audit de répétitivité et d'éclairage nocturne.
**À réaliser :** atlas et variations de façades par époque/typologie, vitrines cohérentes, fenêtres et occultations variées, halos de lampadaires économes, éclairage adapté aux rames et stations, profil nuit mobile.
**Tests :** captures jour/nuit, limites de draw calls et mémoire, pas de scintillement à distance.
**Acceptation :** meilleure diversité visuelle sans régression du profil mobile.

### 16. Optimisations LOD
**Existant :** `CityScene`, `AerialCityLOD`, préchargement et streaming.
**À réaliser :** budgets par appareil, cache de tuiles et annulation sûre des tâches, instancing des objets répétitifs, génération asynchrone lorsque possible, LOD géométrique et de matériaux, culling, transitions sans popping excessif. Ne pas sacrifier la précision des voies et signaux.
**Tests :** stress caméra rapide, téléportation, fermeture pendant chargement, mesure frametimes/mémoire.
**Acceptation :** amélioration prouvée des métriques sur scènes de référence sans fuite ni crash.

## Lot 5 : nouveaux modes (P2)

### 17. Missions de dépôt
**Existant :** données de voies de service et de dépôts, `MissionCatalog`, `MissionEvents` et `Interlocking`.
**À réaliser :** scénario de prise de service, préparation cabine, mise sous tension, vérifications, départ dépôt, insertion sur ligne, service commercial, retour et remisage. Réutiliser les contrôles de mission et la signalisation.
**Tests :** mission complète, interruptions, départs impossibles, objectifs et sauvegarde.
**Acceptation :** un parcours bout en bout sur un dépôt cartographié et correctement connecté.

### 18. Éditeur de scénarios
**Existant :** missions JSON et outils de génération ; éditeur visuel complet non confirmé.
**À réaliser :** format versionné de scénarios (réseau, matériel, date, météo, départ, itinéraire, événements, objectifs, difficulté), éditeur PC et consultation mobile, validation topologique, prévisualisation, import/export local, sandbox des données sans exécution de scripts arbitraires.
**Tests :** roundtrip JSON, scénarios invalides, compatibilité des versions et validation avant lancement.
**Acceptation :** création et partage d'une mission sans modifier les fichiers internes du jeu.

### 19. Incidents et dépannage
**Existant :** `MissionEvents`, défaillances et états d'échec ; couverture exacte à réévaluer.
**À réaliser :** moteur d'incidents déterministe : panne de porte, coupure de courant, défaut pantographe, défaut frein, aiguille bloquée, obstacle, retard, perte d'adhérence ; procédures guidées, modes dégradés et possibilités de secours. Éviter la simulation de manipulations dangereuses non documentées comme procédures réelles.
**Tests :** chaque incident récupérable ou terminal selon sa définition, aucun softlock, sauvegarde et reprise.
**Acceptation :** incidents compréhensibles, testables et compatibles avec le pilote automatique et l'IA.

### 20. Mode régulateur PCC
**Existant :** carte réseau, `AiTrams`, `Interlocking`, horaires et états de signalisation.
**À réaliser :** modèle `OperationsState` partagé conduite/PCC, synoptique des voies, positions et retards, missions et conflits, commandes de régulation (retenue, départ, terminus partiel, déviation autorisée, suppression de course), journal d'événements, droits et validation des commandes. Commencer hors ligne et en solo.
**Tests :** cohérence PCC/rame, ordre contradictoire, retards en cascade, scénario de perturbation, replay déterministe.
**Acceptation :** réguler un réseau de démonstration sans désynchroniser simulation et carte.

## Ordonnancement conseillé

- Phase A : lot 0 + sauvegardes + géométrie + instrumentation Android.
- Phase B : recalage OSM, interlocking, IA GTFS, carrefours.
- Phase C : météo, voyageurs, cabine, audio.
- Phase D : colorimétrie, voirie, façades, LOD, en parallèle des phases B/C si tests suffisants.
- Phase E : missions dépôt, incidents, scénarios, PCC. Le PCC dépend du modèle d'exploitation stabilisé.
- PR petites et atomiques ; aucun regroupement des 20 fonctionnalités dans un seul commit.

## Qualité et critères de livraison

- Chaque PR : tests unitaires + intégration, fixtures, changelog, captures ou enregistrements si pertinent, mesures avant/après.
- Maintenir compatibilité des anciennes sauvegardes et données ; toute rupture nécessite une migration et une justification.
- Exécuter la suite existante `GODOT=/chemin/godot tests/run_all.sh` lorsque disponible ; ne jamais prétendre l'avoir exécutée si ce n'est pas le cas.
- Vérifier les 120 missions documentées et les réseaux de référence ; faire une validation mobile réelle avant de déclarer les objectifs de performance atteints.
- Ne pas remplacer des données sources par des hypothèses silencieuses ; chaque estimation porte sa provenance et son niveau de confiance.
- Feature flags pour météo, nouveaux systèmes de voyageurs, PCC, rendu expérimental et autres chantiers à risque.
- Aucun téléchargement runtime nécessaire : conserver le fonctionnement hors ligne.

---

# Prompt Codex prêt à copier

Tu es l'ingénieur principal chargé de faire évoluer le dépôt GitHub privé `CorbetQ/tramsim` sans casser l'existant.

**Mission :** appliquer progressivement les 20 améliorations détaillées dans `TramSim_Specification_Codex.md`, en commençant par un audit du HEAD réel, une matrice de couverture et un plan de PR. Tu ne dois pas implémenter les 20 fonctionnalités dans un seul changement.

**Étape 1, obligatoire avant toute écriture :**
1. Inspecte la branche par défaut, son SHA, l'état Git, les derniers commits, README, ROADMAP, audits, CI, tests, modèles de données et modules concernés.
2. Vérifie pour chaque exigence : existant, partiel, absent, régression potentielle ; cite fichiers et fonctions exacts.
3. Recherche les modifications concurrentes, notamment le WIP 0.13 et l'intégration récente des carrefours dans `data/crossings.json`.
4. Établis une baseline de tests et de performances si l'environnement le permet. Si une commande ou un outil manque, note précisément le blocage ; n'invente aucun résultat.
5. Propose une architecture incrémentale, les dépendances entre fonctionnalités, les risques, les migrations et un plan de PR priorisé.

**Étape 2, implémentation contrôlée :**
- Commence uniquement par le premier lot cohérent et peu risqué : migrations non destructives des sauvegardes, validation géométrique et instrumentation de performance.
- Pour chaque lot : présente le plan, implémente les changements minimaux, ajoute les tests, exécute les contrôles possibles, inspecte les diffs, documente les résultats et les limitations.
- Préserve les API et les formats existants, les 28 réseaux libres, les missions, les modes de conduite, les assets, les licences, les crédits et le fonctionnement Android/Windows hors ligne.
- Ne remplace pas les systèmes `TrainPhysics`, `MissionSession`, `Interlocking`, `AiTrams`, `RoadTraffic`, `CityScene`, `AerialCityLOD`, `TramAudio` ou `SaveGame` sans nécessité démontrée.
- Ne supprime pas de tests pour obtenir une CI verte. Ne modifie pas les données géographiques réelles sans provenance ni vérification.
- Garde le simulateur jouable après chaque PR et fournis un rollback documenté.

**Livrables de chaque lot :**
1. Rapport état initial et références de code.
2. Spécification des interfaces et changements.
3. Code et migrations.
4. Tests ajoutés et commandes exécutées avec résultats réels.
5. Rapport de performances/qualité avant-après si mesurable.
6. Liste des risques, limites, régressions possibles et prochaines PR.

**Critère de succès :** une amélioration vérifiable, réversible, documentée, compatible avec l'existant et sans régression des parcours de référence.

Commence maintenant par l'audit du HEAD et la matrice des 20 exigences, puis prépare la première PR. N'engage pas les lots suivants sans bilan du précédent.