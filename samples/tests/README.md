# Vérifications audio

- `audio_variants.log` et `.json` : 76 parcours, zéro échec. Pour chaque variante : arrêt, portes ouverture/fermeture différée, gong, montée graduelle 0–50 km/h, roue libre, freinage progressif jusqu'à arrêt, arrêt sans alimentation/pantographe, cabine/extérieur, tunnel/pont, pause/reprise urgence prioritaire sur un manipulateur resté en traction (consigne nulle et événement unique), et transmission depuis une MissionSession avec sa physique réellement avancée. Les dernières commandes de traction à l'arrêt vérifient le silence après quatre secondes de relâchement, cohérent avec la constante de temps du moteur.
- `audio_interlocks.log` : vérifications supplémentaires de la consigne instantanée de traction en mouvement (portes ouvertes, alimentation coupée, pantographe baissé, alimentation APS, urgence avec cran positif). Les gains déjà présents peuvent décroître progressivement ; ils ne constituent pas une nouvelle commande de traction.
- `audio_engine.log` : suite moteur historique, adaptée au relâchement du crissement ; aucun échec d'assertion.
- `audio_families.log` : 20 familles, zéro échec. Classification actuelle : 7 exact_family, 3 related_family, 2 modeled, 8 synthetic.
- `godot_mix_pcm_checks.json` : contrôle des deux vrais WAV Master. Aucun échantillon clippé ; pause centrale strictement silencieuse et reprise non nulle. Maximum de pas adjacent ~0,02 amplitudeFS ; cet indicateur seul n'établit pas l'absence de clic perceptible.

Reproduction depuis la racine :

```sh
godot --headless --path . --script tests/test_audio_variants.gd
godot --headless --path . --script tests/test_audio_interlocks.gd
godot --headless --path . --script tests/test_audio.gd
godot --headless --path . --script tests/test_audio_families.gd
```

La couverture automatisée principale utilise le pilote Dummy : elle établit le chargement, le routage, les états et les événements, pas l'audibilité. Les captures ALSA/Master séparées, documentées dans `samples/demos/README.md`, prouvent une véritable sortie mixée pour les deux exemples. Le scénario capture impose les vitesses à une MissionSession : il ne simule pas les touches clavier ni une conduite manuelle F3. Le parcours de physique vérifie sa transmission indépendamment du scénario d'écoute. La suite des familles produit encore à la sortie un avertissement ObjectDB / deux ressources conservées ; ses assertions et son code de sortie réussissent.
