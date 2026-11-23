# Validation du catalogue, des kits et des portes — 23 novembre 2026

Branche : `codex/family-catalogue-livery-editor`. Aucun changement de carte ni fusion dans la principale.
Les captures du dossier `captures` proviennent du véritable moteur Godot, sans illustration générée.
Les six configurations X05 en trois quarts ont été présentées avant le commit final.

## Résultat de l’inventaire

- 80 variantes du catalogue, représentant 418 emplacements de caisse.
- 60 kits de design, dont trois HD et 57 issus des modèles natifs existants.
- 290 fichiers de modèles partagés, cabines et équipements compris : 20 674 984 octets.
- 503 textures référencées : 1 999 054 octets, hors sources HD complètes conservées.
- Audits binaires et chemins : zéro erreur ; 10 tests Python d’assets réussis.

Les dimensions 205/305/405 sont des paramètres. Pour chaque réseau, le test compare le chemin réel
du modèle d’extrémité : c’est le même fichier dans les trois configurations. Les fichiers géométriques
par variante ajoutés lors du premier essai ont été supprimés, ainsi que les quatre banques complètes
de concepts. Les trois sources HD réelles et les anciennes sources passager restent disponibles.

## Contrôles exécutés

Environnement : Godot 4.6.3, rendu OpenGL Compatibility sur Mesa llvmpipe, affichage Xorg virtuel.
Les profils PC et Mobile sélectionnent réellement des ressources et budgets différents.

| Test | Résultat local |
|---|---|
| `test_tram_parts.gd` | 546 assertions, zéro échec |
| `test_stock_catalog.gd` | 410 assertions, zéro échec, 80 variantes construites |
| `test_livery_catalogue.gd` | 59 assertions, zéro échec |
| `test_livery_ui.gd` | 23 assertions, zéro échec, y compris petits écrans et reprise en conduite |
| `test_family_fronts.gd` | 76 assertions, zéro échec, six X05 en PC/Mobile |
| `test_stock_hd.gd` | 167 assertions, zéro échec |
| `test_citadis_meshy.gd` | 667 assertions, zéro échec, anciennes coques passager régénérées |
| `test_passenger_families.gd` | 20 familles, zéro échec |
| `test_render_budgets.gd` | 48 assertions, zéro échec |

Les tests existants de flotte, sélection, interface de fiche et migration des sauvegardes ont également
été exécutés sans échec. Les mesures structurées et empreintes des captures sont dans `validation.json`.
Les logs de travail sont dans `.cache/livery/` ; la CI publie ses propres logs et captures en artefacts.

Les tests vérifient les modèles effectivement utilisés, les portes visibles animées, le pantographe
relié aux commandes, la séparation des atlas d’extrémités, l’application d’une peinture à plusieurs
tailles, les vitrages personnalisés natifs et le maintien du bandeau TAN dans l’atlas frontal.
Les tests Python rejettent aussi les modèles absents, chemins sortants et ordres de caisses invalides.

## Correction des portes

- Irigo 302 : `1–2–0–2–1` par face ; portes simples aux extrémités.
- Irigo 305 : `1–2–0–2–1` par face ; portes doubles aux extrémités.
- Naolib 405 : `2–0–2–0–2–0–2` par face, architecture différente.

La porte d’extrémité Irigo est vers la cabine ; aucune porte sur la motrice centrale.
Les corps et portes ont été régénérés ensemble, avec leurs textures et LOD. Les coques de la vue
passager suivent aussi les plans corrigés. Leur chargeur refuse désormais une coque dont les
longueurs de caisses ne correspondent pas, même si la longueur totale est identique.
La génération Blender utilise les contours enregistrés et ne contacte pas Meshy.
Les 90 crédits affichés par l’ancien audit sont son historique, aucune nouvelle consommation.

## Performance et limites

La scène dense de nuit avec contenu Mobile mesure **455 appels de rendu / 586 827 triangles**,
contre des budgets de 600 / 800 000. Les atlas personnalisés restent bornés à 1024×512 avec mipmaps ;
la déformation des prototypes est faite au chargement et partagée dans un cache borné.
Aucun traitement de texture ni génération IA à chaque image de conduite.

Ces chiffres ne sont pas une mesure de FPS sur téléphone. Aucun test thermique, export APK/EXE
ni validation sur appareil Android physique n’a été réalisé pour ce lot. Le rendu Forward+ et ses
effets ne sont pas validés par ces captures OpenGL. Les avertissements FXAA/FSR du renderer
Compatibility sont distincts d’erreurs de script ; les tests terminent sans erreur.

Les silhouettes et longueurs intermédiaires restent des estimations visuelles. Les références ciblées
Irigo/Naolib/TFS sont listées dans `assets.csv` ; les 80 matériels n’ont pas tous fait l’objet d’un nouvel
audit photographique exhaustif. Les concepts sont explicitement fictifs. L’import de décalcomanies
personnelles et l’échange de livrées entre joueurs ne sont pas implémentés dans ce lot.

## CI et livraison

Le workflow `stock-hd-pbr` exécute les audits Python, l’import Godot, les tests HD, catalogue,
caisses, éditeur, passager et les captures PC/Mobile. Les générations Blender ne sont pas exécutées
à chaque commit. L’override d’import PC est limité au poste de validation ; les paramètres Android
de `project.godot` sont conservés. Livraison par commit sur la branche, sans nouvelle pull request.
