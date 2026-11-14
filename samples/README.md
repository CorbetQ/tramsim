# Révision 3 — sources réelles et diagnostic de traction

- [Citadis Rotterdam : départ enregistré](listening/v3_citadis_depart_captation.mp3).
- [Composante harmonique candidate](listening/v3_citadis_depart_harmoniques.mp3).
- [Résidu retiré](listening/v3_citadis_depart_residu.mp3).

Les trois extraits couvrent exactement0–13,8s de Streetcar04, auteurLG, [source](https://freesound.org/people/LG/sounds/14279/), [CC BY4.0](https://creativecommons.org/licenses/by/4.0/). Traitement : mono16kHz, séparation spectrale douce des harmoniques/trajectoires, même gain fixe pour les trois ; copieMP3 avec−2dB supplémentaires identiques. Pas de synthèse de motrice ni de transposition. Le candidat peut conserver voix, ventilation ou rail ; le résidu peut contenir une partie de traction. Ce n’est pas un moteur pur certifié, ni un302/305Angers identifié.

Les maîtresFLAC vérifient source=harmoniques+résidu avec erreur0LSB en PCM24. LeMP3 n’a pas cette égalité sans perte. Voir `analysis/revision3/revision3-rotterdam-reconstruction.json`.

[Étude des sources et trajectoires](analysis/revision3-study.md), [inventaire des76variantes](analysis/traction-coverage.md), [recherche des20familles](references/revision3-research-report.md). Cette passe inventorie5médias de référence dont la captation embarquéeNantes nouvellement récupérée ; quatre étaient collectés durant la passe précédente. Le matériel nantais n’est pas identifié. Aucun vrai305 ou302Angers accessible n’a été obtenu. Les deux vidéos du joueur restent des références non écoutées, car YouTube retourneCONNECT403 malgré la politique réseau ouverte.

Le script de capture dispose maintenant de `traction_solo`, qui coupe les couches communes et journalise la banque, les fichiers, les bus et les volumes effectifs. Les deux capturesSolo302 et305modélisé sont des diagnostics du jeu actuel ; elles ne constituent pas une nouvelle banque fidèle. Le moteur et les banques de production restent en révision2 pendant l’identification de sources adaptées.

---

# Révision2 — écouter et comparer

- [Citadis302 avant/après](listening/v2_citadis_302_avant_apres.mp3).
- [Citadis305 avant/après, modèle synthétique correctement sélectionné](listening/v2_citadis_305_avant_apres.mp3).

Chaque comparaison dure33secondes :16secondes de départ avant,1seconde de silence,16secondes après, avec correction constante de sonie par extrait. La vitesse prescrite est identique0–50km/h. Les traitements de niveau et mesures sont dans `listening/v2_levels.json` ; aucune synthèse ni effet n’est ajouté aux captures pour les extraits.

Scénarios complets : [302](listening/v2_citadis_302_ecoute.mp3), [305 modélisé](listening/v2_citadis_305_ecoute.mp3).

**Erreur précédente corrigée :** l’ancien fichier étiqueté305 jouait une302 ; la nouvelle capture valide famille, variante, banque et chemins avant l’enregistrement. Les tests du catalogue ne présentaient pas cette erreur du script spécifique.

La302 préserve maintenant les partiels de la source et réduit les fonds qui la masquaient. La305 garde sa synthèse préexistante ; son mixage est moins masqué. Aucune captation exacte305 n’a été intégrée. Les deux vidéos d’Angers fournies par le joueur ont été référencées mais leur audio reste inaccessible ici. Voir [recherche de spotting](references/spotting-v2.md), [diagnostic](analysis/revision2-study.md), [conceptionv2](design-notes-v2.md).

Les premières notes annonçaient à tort LeMans pour la variante302Angers : cette variante utilise en fait la banque `citadis302` dont le titre source est Moscou. Les rapports de capture contiennent désormais le profil et les chemins réellement sélectionnés. Ne pas présenter ces sources comme des sons enregistrés à Angers.

---

> **Correction — deuxième passe :** le premier extrait intitulé Citadis 305 utilisait par erreur la banque du 302 (identifiant non canonique dans le script de capture). Cet ancien extrait ne démontre donc pas le modèle sonore 305. Les captures corrigées sont identifiées v2 ; voir `analysis/revision2-study.md`.

# Atelier sonore — proposition à écouter

Les quatre rôles demandés ont produit les sources, l’étude, les banques et les tests. Le moteur est intégré sur la branche de travail `codex/tram-audio-design`, en attente du retour sur le timbre avant fusion et publication.

## Écouter les prototypes

- [Citadis 302 — MP3](listening/citadis_302_ecoute.mp3) : base enregistrée puis traitée.
- Ancien [MP3 étiqueté Citadis 305](listening/citadis_305_ecoute.mp3) : **chargement erroné de la banque 302**, extrait invalidé.

Environ 48 secondes : portes, gong, accélération progressive, roue libre, freinage, tunnel/pont, arrêt et pause/reprise. Les MP3 reçoivent uniquement un gain constant de présentation de +9,6 dB (niveau voisin de −20 LUFS), puis sont encodés. [Détails du niveau](listening/README.md).

## Dossiers

- `raw/` : 19 captations, 17 min 22 s environ ; fichiers et licences dans [sources.json](sources.json). La matrice couvre les 76 variantes / 20 familles du registre canonique, avec les absences et apparentements signalés. Ces références ne sont pas toutes intégrées au jeu.
- `references/` : provenance et limites des recherches.
- `analysis/` : [étude objective](analysis/technical-study.md), fenêtres candidates, spectres/niveaux et défauts de raccord. Aucun jugement d’écoute humaine n’est inventé.
- `designed/` et `data/audio/` : banques conçues, traitements reproductibles et crédits. [Notes de conception](design-notes.md).
- `demos/` : véritables enregistrements du bus Master Godot, WAV maîtres et OGG bruts, scénario et instrumentation. La vitesse est prescrite pour la comparaison ; ce n’est pas une conduite manuelle.
- `tests/` : [76 parcours et contrôles supplémentaires](tests/README.md), sans échec d’assertion ; vérifications PCM des deux captures. Les captures audio réelles complètent les tests de logique effectués avec Dummy.

L’atelier et les captures sont exclus de l’import du jeu par `.gdignore` ; seules les banques intégrées dans `data/audio` sont utilisées à l’exécution.
