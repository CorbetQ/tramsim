# Textures par caisse

`livery/<livrée>` contient les atlas normalisés par prototype de caisse ; `materials` les palettes
sans perte et textures techniques ; `interior` les textures intérieures disponibles.
Les sources actuelles de feux sont géométriques/émissives : pas de fausse texture dans `lights`.
Les styles nommés du joueur restent dans `user://liveries.json`, sans modifier ces originaux.

Index unique : `data/rolling_stock/parts_manifest.json`, section `liveries`.
Les variantes 205/305/405 réutilisent les mêmes atlas et les mêmes modèles.
L’éditeur permet de surcharger un rôle ou une caisse précise, indépendamment des autres.
