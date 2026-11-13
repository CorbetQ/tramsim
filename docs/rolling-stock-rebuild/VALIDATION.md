# Vérification de l’aperçu des rames

Intégration sur les cartes de Claude : commit `67bde9395be3eabd06ea645ccc0d9f0f5f6af06f`. Les fichiers de terrain, voirie et scènes géographiques de cette version sont conservés.

- 25 scripts de test applicatifs réussis lors du passage complet ; catalogue et modèles rejoués après la dernière correction du guidage.
- Nouveau parcours graphique du catalogue : 8 contrôles réussis à 640 × 360, sélection de la variante et du réseau, filtrage pneus/rails et disposition mobile.
- 21 tests Python réussis et 149 fichiers réseau validés.
- Gabarit : 28 villes, 2 634 970 contrôles sans échec. Le premier passage global avait dépassé sa limite de quatre minutes ; le contrôle a été repris ville par ville, avec le même échantillonnage, les mêmes assertions et la même limite interne par exécution.
- Galerie : 76 entrées, 272 fichiers de captures référencés vérifiés ; recherche, filtres et changement de vue testés sous Chromium, sans erreur de page ni débordement horizontal à 390 px.
- Captures WebP sans perte, comparaison des pixels décodés avec les PNG de capture.

## Reproduire

Godot 4.6.3 et un affichage OpenGL pour les tests graphiques :

```sh
GODOT=godot PYTHON=python3 tests/run_all.sh
python3 tools/stock/build_preview.py
```

Les dépendances Python géographiques figurent dans les fichiers de dépendances du dépôt. Les exports nécessitent les modèles d’export Godot, le SDK Android et Java. `TRAMSIM_PREVIEW_KEYSTORE` permet de fournir une clé de développement ; à défaut, le script en génère une si la clé locale historique est absente.

Le script construit dans un répertoire temporaire et ne change pas la configuration du jeu principal. L’APK utilise `fr.tramsim.stockpreview` pour cohabiter avec lui. `BUILD.json` identifie le commit et `SHA256.json` les binaires. Cet aperçu utilise une signature de développement.

Les contrôles sur émulateur de rendu Linux, navigateur et Wine ne remplacent pas un essai sur un téléphone Android physique ou un PC Windows natif. Les motifs complexes, certains paramètres et plusieurs banques sonores restent des approximations signalées dans le catalogue.
