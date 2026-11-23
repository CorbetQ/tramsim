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
