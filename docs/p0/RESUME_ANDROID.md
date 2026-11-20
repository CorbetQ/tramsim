# Reprise du lot P0-C

Révision distante vérifiée à la reprise : dc56265433e0f21be66d7011ed9a22bd6332c2b6.
Les PR #14 (sauvegardes) et #15 (géométrie) restent ouvertes. Leurs CI ciblées ont
réussi ; la suite générale et les dépôts d'artefacts ont eu des échecs documentés.
Leur code n'est pas assimilé au HEAD par défaut ni fusionné automatiquement.

Depuis la baseline 974d15c, le diff des modules runtime concerne CityScene, le shader
d'eau et ExploreMode, avec de nouveaux assets géographiques/rendu. SaveGame reste en
version 1 au HEAD. Main, les API de session/pilote et le projet Godot n'ont pas changé.
Le document de spécification est inchangé. Les métriques géométriques de la PR #15
restent attachées à sa propre baseline ; elles ne certifient pas les nouvelles cartes.
Les 20 statuts de l'audit initial restent des statuts de cette révision historique,
avec progrès concurrents du rendu à réexaminer dans un lot visuel ultérieur.

L'espace temporaire du brouillon P0-C a été perdu au redémarrage. Le lot est reconstruit
sur le HEAD actuel, en gardant le checkout local de rendu intact. ADB est présent mais
aucun appareil physique n'est connecté. Aucun FPS téléphone ne sera revendiqué.
