# Notation à l'aveugle — lot P1 (tranche verticale Angers / Nantes)

À remplir **par le joueur**, sans savoir quelle image est la référence (CDC §7.2 : moyenne ≥ 3/5, aucun axe < 2).

**Préparation (par un tiers)** : `tests/audit/p1_planche.py` produit la planche anonymisée : pour chaque cadrage, deux
images notées **A** et **B** dans un ordre tiré au hasard ; la correspondance est écrite dans un fichier séparé
(`cle.json`), à n'ouvrir qu'après la notation.

Cadrages :

- **C1** : cabine en station couverte (station enterrée de la trémie de la ligne 3, Nantes) ;
- **C2** : rame à l'arrêt à Ralliement (Angers), extérieur, cathédrale Saint-Maurice en fond ;
- **C3** : cabine en approche du portail de la trémie (Nantes, ligne 3).

Barème par axe : 1 très insuffisant, 2 insuffisant, 3 correct, 4 bon, 5 au niveau de la référence.

| Cadrage | Image | Éclairage | Matériaux | Détail | Végétation | Cabine | Moyenne |
|---|---|---|---|---|---|---|---|
| C1 | A | | | | | | |
| C1 | B | | | | | | |
| C2 | A | | | | | | |
| C2 | B | | | | | | |
| C3 | A | | | | | | |
| C3 | B | | | | | | |

Renderer de la planche notée : ☐ Compatibility ☐ Forward+ (lavapipe) ☐ Forward+ (GPU) ☐ Mobile (appareil)

Remarques libres (ce qui fait « jeu vidéo ancien », ce qui fait « réel ») :

-
-

Après notation : ouvrir `cle.json`, reporter ci-dessous la moyenne **TramSim** par axe.

| Axe | C1 | C2 | C3 | Moyenne | ≥ 2 ? |
|---|---|---|---|---|---|
| Éclairage | | | | | |
| Matériaux | | | | | |
| Détail | | | | | |
| Végétation | | | | | |
| Cabine | | | | | |
| **Moyenne générale** | | | | | **≥ 3 ?** |
