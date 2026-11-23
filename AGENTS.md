# TramSim

Pour les modifications audio, lire [tools/audio/AGENTS.md](tools/audio/AGENTS.md)
et [docs/audio-studio/README.md](docs/audio-studio/README.md).
La commande de production est `python tools/audio/studio.py`.
Préserver les profils approuvés et les originaux ; les banques candidates ne doivent
pas remplacer une captation existante sans écoute et validation humaine.

Pour le rendu PBR et les rames HD, lire [docs/CDC_REFONTE_VISUELLE.md](docs/CDC_REFONTE_VISUELLE.md),
[le contrat de modèles](docs/refonte-visuelle/stock_manifest.md) et
[le rapport P2](docs/refonte-visuelle/p2/README.md).
Audit hors ligne : `python tools/models/stock/audit_stock.py` ; tests : `tests/test_stock_hd.gd`
et `tests/test_render_budgets.gd` dans Godot 4.6.3 avec affichage OpenGL.
Conserver le profil Mobile dès la construction, le repli complet et les animations.
Les atlas de livrée contiennent des UV constants : conserver leur filtrage trilinéaire pour éviter
les pointillés en GLES ; contrôler les captures PC et Mobile avant livraison.

Catalogue et peinture : lire `docs/catalogue-liveries/README.md`. Tests Godot :
`tests/test_livery_catalogue.gd`, `tests/test_livery_ui.gd`, `tests/test_family_fronts.gd`.
Faces HD : `data/rolling_stock/front_profiles.json` et `tools/models/stock/specs.py`.
Ne pas remplacer une face spécifique par le plan donneur d'un type court/long.
Conserver les concepts signalés comme fictifs, la compatibilité d'alimentation et les originaux.
Après génération HD, lancer `python tools/models/stock/export_livery_layouts.py`.
