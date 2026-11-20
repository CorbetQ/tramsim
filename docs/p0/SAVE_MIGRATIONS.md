# Lot P0-A — sauvegardes non destructives

Base auditée : 974d15c ; API de SaveGame conservée. VERSION passe de 1 à 2.
Une migration idempotente ajoute `migration_log` et complète les options manquantes,
sans supprimer les champs inconnus ni les résultats. `.bak` contient les octets du
primaire avant remplacement. Une version future, y compris dans `.tmp` ou `.bak`,
interdit l'écriture : pas de rétrogradation. L'interface affiche une erreur non
destructive ; la partie peut rester consultable sans remplacer la progression.

Ordre de récupération : primaire valide, temporaire complet, puis backup. Un primaire
corrompu est conservé sous `.corrupt-<sha256 court>` avant restauration. Les copies
intermédiaires `.copying` et le save `.tmp` sont distincts ; une erreur de backup,
validation ou rename conserve l'original. `flush` précède la fermeture/renommage ;
ce n'est pas une promesse de résistance à une panne matérielle sans garantie fsync
du stockage/OS. Les fichiers futurs ou irrécupérables ne sont jamais supprimés.

SaveResume est un adaptateur, pas un changement de graphe. Le checkpoint enrichi
conserve ID réseau/arête, direction, source OSM, empreinte d'arête et ancre lat/lon.
Reprise : identité inchangée, alias explicite (scale/shift_m/direction), puis projection
conservative à 12 m maximum. Voies ambiguës ou éloignées : refus, checkpoint conservé.
Le rayon est un garde-fou configurable, pas une précision cartographique mesurée.
Un changement de sens de géométrie est résolu à partir du cap mémorisé. Les anciennes
sauvegardes sans ancre ne sont pas projetées au hasard.

Alias facultatifs déclarés, jamais inventés :

```json
{"save_aliases":{"networks":["res://data/free/old.json"],"edges":{"old_edge":{"edge":"new_edge","scale":1,"shift_m":0,"direction":1}}}}
```

`save_aliases` est une extension du document réseau. Un import peut aussi déclarer
`data/save_aliases.json` : `{"networks":{"ancien_chemin":"res://data/...json"}}`.
Aucun fichier de géographie existant n'est modifié par ce lot. Les nouveaux checkpoints
sont retrouvés par ID stable dans l'index commercial ou les réseaux libres.

## Vérifications réellement exécutées

- Import Godot 4.6.3 avant/après ; test_save original : succès.
- test_save_migrations : 27 assertions réussies, avec fichiers réels, fixtures v1/future,
  corruption, quarantaine, temporaire interrompu, backup impossible, types invalides,
  alias, inversion d'arête, voies parallèles et checkpoint réel FreeSession.
- test_power_routing existant : succès.
- test_free_starts : 3 échecs du catalogue existant (tram-train/dépôts Nantes), sans
  modification de ses données/implémentation. Ne pas les effacer pour verdir la CI.
- Contrôle de gabarit initial existant : 2 634 970 vérifications, zéro échec ; il ne
  couvre pas l'intérieur des tunnels. Aucun FPS ou gain de performance revendiqué.
- CI ciblée ajoutée sur Linux et Windows. Android : logique portable, mais pas de
  téléphone connecté ; l'export de la CI existante ne vaut pas un essai physique.

Commandes : `godot --headless --path . --import`, puis `-s tests/test_save.gd`,
`-s tests/test_save_migrations.gd`, `-s tests/test_power_routing.gd`.
Les résultats CI distants sont à consulter dans la PR, distincts des succès locaux.

## Retour arrière

Revenir au code antérieur ne doit pas provoquer de sauvegarde par l'ancien chargeur
(version inconnue -> valeurs par défaut). Fermer le jeu, conserver save.json et toutes
ses copies, puis restaurer explicitement la `.bak` v1 si elle est disponible pour jouer
avec l'ancien build. Le nouveau code refuse les sauvegardes futures. Ne pas fusionner
une ancienne version du chargeur sans cette précaution. Les données réseau et les
assets sont identiques ; le commit de ce lot est réversible indépendamment des lots QA
et Android. La sauvegarde n'est pas un chiffrement ni une protection anti-triche.
