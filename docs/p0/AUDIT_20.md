# Audit des 20 exigences — état initial et lots P0

Spécification lue intégralement (205 lignes) : `docs/TramSim_Specification_Codex.md`,
blob `f881a10c55ccb688a9299d537d3a6fcc9e403f80`. Révision distante vérifiée :
`974d15c36c08f0fbe8f521aa9b3be57e98954e51`, branche `ccr-73402276-ntwr5h`.
Le commit précédent est `be7eda97` (WIP Claude) ; `311b8b5` intègre les carrefours.
Le dernier commit ajoute uniquement la spécification. Inventaire/hachages : baseline.json.

Un checkout local contenait des modifications de rendu non commises : conservé intact.
Travail dans un checkout séparé, sans fusion automatique. PR #11 (stations d'Angers)
et #12 (Audio Studio) ouvertes, non incluses dans le HEAD par défaut. La préversion
audio ne signifie pas que cette PR a été fusionnée. Ne pas remplacer ses travaux.
README/ROADMAP/AUDIT_0_8/AUDIT_VISUEL_0_11 ont été consultés ; leurs chiffres anciens
ne sont pas des mesures actuelles. Comptage actuel : 120 fichiers commerciaux,
28 graphes libres, 20 familles, 28 catalogues de missions. Le nombre de scénarios
n'est pas assimilé au nombre de lignes/variantes.

## Matrice statique réévaluée avant modifications

| # | État au HEAD | Preuves exactes | Manque / risque à préserver |
|---|---|---|---|
| 1 Sauvegardes | Partiel, risque de perte | `SaveGame.load_data/save_data/store_free`, `Main._resume_info/_resume`, `tests/test_save.gd` | Version 1 ; version inconnue/corruption deviennent défauts puis peuvent être écrasées. Pas de migration, backup ou reprise d'arête renommée. Conserver l'API statique et les champs inconnus. |
| 2 Géométrie | Partiel | `test_clearance._line/_obstacle`, `tests/run_clearance.sh`, `audit_ground.audit`, `validate_networks.validate`, `test_geography` | Gabarit ponctuel 2 m, tunnels ignorés ; pas de registre unifié de constats/incertitudes/exclusions ni rapport géolocalisé des jonctions. Ne pas cacher les erreurs ni retoucher les sources pour faire passer les tests. |
| 3 Caméra/eau/ouvrages | Partiel, déjà développé | `CityScene.camera_clear/water_at/deck_piles`, `LineView._structures/update_from`, `TerrainClip` | L'audit ancien n'est pas la preuve de défauts encore présents ; vérifier les cas en 3D avant correction. Garder les repères/altimétrie et les données sourcées. |
| 4 Android mesuré | Absent comme chaîne de mesure | `DayNight.low_quality`, réglages `.mobile` de project.godot, `test_cinematic_lod` | LOD/réglages existent, mais aucun collecteur de sessions Android, CSV ni mesure physique sur deux gammes. GPU/thermique doivent rester null si indisponibles. |
| 5 Missions sur OSM | Partiel | `gtfs_to_network.build_network`, `NetworkLoader.load_data/point_on`, `merge_city.py`, `MissionCatalog.create_session` | Tracés GTFS et graphes physiques distincts ; l'écart historique >25 m n'a pas été remesuré ici. Horaires et géométrie source à conserver séparés. |
| 6 Itinéraires | Partiel avancé | `Interlocking.plan_route/_reserve/_release_behind`, `TrackGraph.reserve/lock_switch/occupy`, `NormalRouting.initialize` | Réservations et queue existent ; stress concurrents et protection anti-deadlock à approfondir sans connexions géométriques fictives. |
| 7 IA GTFS exacte | Partiel | `AiTrams.headway_s/create/step/_retire`, `gtfs_schedule.py` | Intervalles estimés ; MAX_PC=10/MAX_MOBILE=5, retrait des rames bloquées. Pas de calendrier/frequencies en exploitation logique complète. |
| 8 Priorité carrefours | Partiel | `RoadTraffic.light_for/step`, `SignalModel._crossing_for/update`, `NetworkLoader._crossings`, `data/crossings.json` | Rouge déclenché par distance/occupation, pas de contrôleur routier multiphase complet ni temporisation de dégagement certifiée. |
| 9 Météo | Partiel physique | `TrainPhysics.effective_adhesion/step`, `MissionEvents.adhesion_at`, événements leaves/flood | Adhérence/sablage existent ; pas de WeatherState ni transitions météo complètes. Éviter un changement de freinage silencieux. |
| 10 Voyageurs | Partiel | `MissionSession._update_dwell`, `TrainPhysics.mass` | Débits et capacité, sans matrice OD ni conservation de files de voyageurs explicites. Ne pas confondre somme de débits avec modèle de demande. |
| 11 Cabines | Partiel (HUD/caméra) | `Main._set_notch/_doors/_power_picker`, `LineView.update_from`, `TramModel` | Pas de CabControl interactif data-driven confirmé ; garder commandes tactiles/clavier existantes. |
| 12 Audio | Partiel, PR indépendante | `TramAudio.update_state/profile_for/_route`, `data/audio/families.json`, outils FFmpeg | Banques exactes/apparentées/modélisées distinctes. PR #12 étend déjà la traçabilité et les fondus ; ne pas recopier son implémentation ni affirmer qu'elle est fusionnée. |
| 13 Couleur/brouillard | Partiel, anciennes causes corrigées en partie | `DayNight.setup/set_hour/set_ground`, `toon_building.gdshader` color_gamma=1 | Ajustement global désactivé, fog_height relatif au terrain déjà présents. Pas de nouvelle calibration 28 villes réalisée ; ne pas réintroduire double gamma. |
| 14 Carrefours/trottoirs | Partiel | `CityScene._road_ribbon/_road_nodes`, `TrackView` | Génération présente ; pas de preuve de triangulation robuste de toutes les jonctions. Tester angles/niveaux avant tout changement. |
| 15 Façades/nuit | Partiel | `CityScene`, `StreetProps`, `Materials`, `DayNight.set_hour`, shader bâtiment | Typologies et fenêtres existent. Absence de budget mesuré sur téléphone ; diversité à vérifier visuellement, pas via promesse chiffrée. |
| 16 LOD | Partiel avancé | `CityPreload`, `AerialCityLOD.warm/update`, `CityScene.enable_async_lod/drain_background_jobs`, tests fermeture/cinématique | Annulation et streaming présents ; pas de budgets validés par appareil. Ne pas toucher à leur cycle de vie dans le premier lot. |
| 17 Missions dépôt | Partiel | `MissionCatalog`, `MissionEvents`, `FreeStartCatalog`, `data/missions`, voies de service | Dépôts/scénarios/retournements existent ; déroulé complet prise/fin de service par dépôt à auditer. |
| 18 Éditeur | Absent comme éditeur visuel | missions JSON, outils d'import, `MissionCatalog.create_session` | Format exploité sans éditeur PC complet confirmé ; futur versionnement/sandbox nécessaires. |
| 19 Incidents | Partiel | `MissionEvents.tick/filter_supplies/flags`, `FreeSession._fail/rerail` | Coupures/obstacles/pantographe/adhérence présents ; pas de modèle universel sauvegardable de dépannage. Ne pas présenter ces règles ludiques comme procédures réelles. |
| 20 PCC | Absent comme mode | `AiTrams`, `Interlocking`, plan réseau UI | Briques réutilisables, mais pas d'OperationsState partagé ni d'interface PCC/opérations validées. Dépend des lots 5–8/18–19. |

« Partiel » ne signifie pas non fonctionnel : les systèmes sont conservés. Les exigences
physiques/visuelles restent non acceptées tant que leurs cas de référence ne sont pas testés.

## Baseline et stratégie

Godot 4.6.3, Python/NumPy/SciPy disponibles ; pas de téléphone Android déclaré.
Le système de fichiers principal est presque plein : checkout/caches sur /dev/shm,
qui consomme de la RAM. `test_save` exécuté avant modification : succès, dont le repli
historique sur JSON invalide (le test n'exige pas son écrasement). Import Godot initial
exécuté. Les autres résultats réels, limites et commandes sont consignés dans les bilans.
Aucune valeur de FPS téléphone n'est déduite d'un test headless.

PR A : sauvegardes v2, backup/récupération, garde des versions futures, reprise
conservative d'identifiants ; tests de fixtures et de fichiers réellement écrits.
PR B indépendante : contrôles géométriques et rapports déterministes JSON/HTML,
sans retoucher les cartes, avec provenance/incertitude/exclusions documentées.
PR C indépendante : télémétrie opt-in et protocole Android, sans promesse de FPS,
avec valeurs indisponibles nulles et tests de schéma/agrégation/scénarios.

Chaque PR a son bilan et son rollback. Les lots 5–20 restent hors de ces changements.
Pas de fusion automatique des PR ouvertes ni de réécriture des moteurs existants.
