# Reprise P2 : intégration des rames HD

Base : commit Claude Code `caf73cb952189a54994dc68b7fb1a170425297b1` du 23 novembre 2026.
Contrat : [CDC_REFONTE_VISUELLE.md](../../CDC_REFONTE_VISUELLE.md), notamment §5, §7 et §11,
et [stock_manifest.md](../stock_manifest.md).

Cette livraison poursuit **le lot P2**, sans réécrire P0/P1, sans revenir au cel shading et sans
remplacer la géométrie HD de Claude. Les trois variantes conservées sont les Citadis 305/302
d'Angers et le Citadis 405 de Nantes. La validation artistique du réalisme reste humaine.

## Défauts reproduits et corrections

| Défaut au commit de départ | Correction |
|---|---|
| Le rig choisissait ses fichiers avant l'application du profil graphique. Le contrôle Mobile chargeait le LOD0 PC. | Profil de contenu appliqué avant `LineView.build`; budget mobile également actif sur Android en repli GLES et dans l'audit `low_quality`. |
| Le budget Mobile échouait en extérieur, avec plusieurs rames et la nuit. | Bons modèles mobiles dès la construction, avec leurs intérieurs et portes animées ; seuil de 600 appels conservé. |
| `reset_cache` abandonnait des scènes `Node` hors arbre sans les détruire. | Libération explicite des gabarits, également à la fermeture ; les instances vivantes conservent leurs ressources partagées. |
| La validation chargeait aussi les modèles PC invisibles dans le cache Mobile. | Le runtime ne valide/charge que le profil actif ; l'audit CI continue de valider les deux profils. |
| La cabine mobile et le pantographe incomplet pouvaient échapper à la validation. | Contrôle des deux cabines, des budgets réels, des identifiants de portes et de la chaîne articulée du pantographe avant habillage. |
| L'essuie-glace coupé en cours de balayage sautait à sa butée après un délai fixe. | Fin du cycle courant avant stationnement. |
| Un changement de couleur du signal sans changement de texte ne rafraîchissait pas le SubViewport. | Invalidation du rendu aussi sur la couleur. |
| Les noms d'arrêts longs débordaient des écrans du pupitre. | Taille de texte ajustée à la largeur, puis ellipse au seuil minimal. |
| La couronne verte du 405 n'était pas pilotée sur PC, et son nœud était fusionné dans les LOD mobiles. | Signature lumineuse reliée à l'extrémité active, couleur du modèle préservée ; nœuds conservés dans les LOD mobiles reconstruits. |
| La cabine mobile référençait le pupitre 2048 px. | Dérivé 1024×512 et `cab_m.glb` régénéré pour chaque variante, géométrie et commandes conservées. |
| Les textures HD étaient importées sans mipmaps ni compression GPU. | Import VRAM et mipmaps sur toute la banque ; générateur et audit imposent ces réglages. Test Godot sur les vraies textures chargées. |
| L'anisotropie des atlas à pastilles de couleurs provoquait des pointillés noirs en rendu GLES logiciel. | Filtrage trilinéaire pour les atlas de livrée (UV constants sur certains aplats), anisotrope pour les autres textures. Régression mesurée sur une zone uniforme : 4,08 % de pixels sombres avant, 0 % dans l'essai corrigé ; seuil bloquant de 2 % dans les captures Mobile. |

## Mesures de rendu

Godot 4.6.3, Compatibility/OpenGL, Mesa llvmpipe, fenêtre 1280×720. Le contenu Mobile est
simulé sur cette machine ; **ce ne sont pas des FPS ni des mesures Android**. Point d'audit :
St-Serge Université à Angers. Ombres et scène identiques, seuils de tests inchangés.

| Cadrage Mobile | Appels avant → après | Triangles avant → après |
|---|---:|---:|
| Extérieur | 816 → 383 | 565 917 → 517 655 |
| Quatre rames supplémentaires | 873 → 440 | 574 833 → 526 571 |
| Cabine | 369 → 369 | 492 903 → 492 903 |
| Vue aérienne | 384 → 174 | 191 580 → 182 060 |
| Nuit | 1 069 → 447 | 658 845 → 587 337 |

Le test de rendu passe ses 48 contrôles, dont les plafonds Mobile de 600 appels / 800 000 triangles
et les histogrammes. Le rapport [mesures.json](mesures.json) conserve les deux relevés complets.

## Validation finale locale

- 48 suites GDScript couvertes ; 167 contrôles dédiés HD, 251 pour le catalogue.
- 28 villes contrôlées en gabarit : **2 634 970 points, zéro échec**.
- 84 tests Python réussis ; audit du sol : 28 villes, 5 879 tuiles, zéro erreur.
- 149 réseaux validés par schéma ; 640 contrôles du repli Citadis et 24 du mode passager réussis.
- 18 captures réelles produites (9 PC, 9 au contenu Mobile), avec contrôle des pointillés.

Méthode : un premier `tests/run_all.sh` a révélé l'ancien accès à `module.mesh` du catalogue,
l'observateur du test d'essuie-glace à adapter au nouveau stationnement et des dépendances Python
manquantes. Après correction/installation des dépendances déjà déclarées, ces suites et l'audit
du sol ont été rejoués séparément. **Chaque composant a une exécution finale verte** ; il n'y a pas
eu de deuxième exécution monolithique complète. La CI GitHub a son propre état, distinct des résultats locaux.

Détails : [validation.json](validation.json), [résultats](validation.log),
[inventaire et empreintes des assets](audit-assets.json). Les versions Python utilisées sont consignées
dans le rapport. Pour installer les dépendances d'import dans un environnement virtuel :
`python -m pip install -r tools/import/requirements.txt`.

## Reproduction

Depuis la racine, avec Godot 4.6.3 et un affichage OpenGL (`xvfb-run -a` en CI) :

```sh
python tools/models/stock/audit_stock.py --report build/stock-hd/audit.json
python -m unittest discover -s tests -p test_stock_hd_assets.py
godot --headless --editor --path . --import
godot --path . --rendering-method gl_compatibility --audio-driver Dummy --resolution 1280x720 -s tests/test_stock_hd.gd
godot --path . --rendering-method gl_compatibility --audio-driver Dummy --resolution 1280x720 -s tests/test_render_budgets.gd
godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/audit/stock_hd_shots.gd -- build/stock-hd/pc
godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/audit/stock_hd_shots.gd -- build/stock-hd/mobile mobile
GODOT=godot tests/run_all.sh
```

Reconstruction hors jeu : `python tools/models/stock/build_stock.py` (NumPy et Pillow,
aucun service IA, aucun téléchargement). `--only=cab_m` reconstruit les cabines mobiles seules.
Le manifeste est l'autorité ; les rapports SHA-256/triangles/dimensions de textures sont dérivés,
jamais une seconde configuration de modèles. L'audit refuse textures absentes, chemins sortant du
dossier, GLB tronqués et budgets de triangles/textures dépassés.

Le workflow `stock-hd-pbr` exécute l'audit, les tests de corruption, l'import, les animations et les
captures PC/Mobile ; il joint les résultats en artefact et ne publie pas de release.
Avant son enregistrement sur la branche par défaut, il peut être appelé depuis le workflow
existant : `gh workflow run citadis-meshy.yml --ref <branche>`. Ce lancement manuel vérifie à la
fois le repli historique et l'intégration HD, sans fusion ni publication.

## Captures

Les images de `captures/` viennent de **vrais rigs TramModel + StockHD** dans une scène de contrôle,
avec les matériaux du runtime, les portes/pantographes animés et les écrans en SubViewport.
Elles ne sont pas des images générées par IA ni les cadrages urbains C1–C3 du cahier des charges.
La forme des carrosseries de Claude est conservée dans ce lot ; la couronne lumineuse du 405 est remise en service.

| Matériel | Extérieur | Portes ouvertes / pantographe baissé | Cabine avec écrans | Cabine mobile |
|---|---|---|---|---|
| Angers 305 | [Vue](captures/angers__citadis_x05-exterieur.png) | [Vue](captures/angers__citadis_x05-portes-aps.png) | [Vue](captures/angers__citadis_x05-cabine.png) | [Vue](captures/angers__citadis_x05-cabine-mobile.png) |
| Nantes 405 | [Vue](captures/nantes__citadis_x05_nantes-exterieur.png) | [Vue](captures/nantes__citadis_x05_nantes-portes-aps.png) | [Vue](captures/nantes__citadis_x05_nantes-cabine.png) | [Vue](captures/nantes__citadis_x05_nantes-cabine-mobile.png) |
| Angers 302 | [Vue](captures/angers__citadis_302-exterieur.png) | [Vue](captures/angers__citadis_302-portes-aps.png) | [Vue](captures/angers__citadis_302-cabine.png) | [Vue](captures/angers__citadis_302-cabine-mobile.png) |

Diagnostic mobile, même caméra et mêmes modèles :
[pointillés avant](captures/nantes-mobile-pointilles-avant.png) →
[filtrage corrigé](captures/nantes-mobile-pointilles-corriges.png).
[Capture finale du 405 au contenu Mobile](captures/nantes__citadis_x05_nantes-exterieur-mobile.png).

## Limites et suite du cahier des charges

- LightmapGI : scènes préparées par Claude, cuisson et intégration GPU toujours à terminer.
- Android réel, Windows ARM64, thermique, FPS bas et shader baker : non vérifiés ici.
- Comparaison à l'aveugle C1–C3 : grille P1 encore à remplir ; aucun score de réalisme inventé.
- Tolérance dimensionnelle : plans et métadonnées vérifiés ; pas de certification constructeur.
- Les captures actuelles servent à examiner la continuité d'intégration, pas à déclarer la qualité
  finale PBR acquise. Les cabines et formes demandent encore une revue photographique par modèle.
- Matériels suivants du §5.3 (Dualis, Flexity/TFS), P3 ville dense et P4 généralisation restent à produire.

Retour arrière : désactiver tout habillage HD par `TRAMSIM_STOCK_HD=0` (repli complet existant),
ou revenir sur le commit de cette PR. Les anciens modèles, sauvegardes, cartes et banques audio ne sont pas supprimés.
