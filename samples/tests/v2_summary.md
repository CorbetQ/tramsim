# Vérifications de la révision 2

- 76 variantes : scénario de conduite, accélération et freinage progressifs, roue libre, portes, gong, alimentation, pause, cabine/extérieur, tunnel et pont. 0 échec.
- 76 variantes : interverrouillages de traction, 0 échec.
- Tests moteur et 20 familles : succès.
- 4 tests de capture : famille305 non canonique rejetée, variante incohérente rejetée, banque inattendue rejetée, profils et fichiers302/305 distincts réellement sélectionnés.
- 4 captures Master Godot avant/après : banque et chemins enregistrés ; durée47,8–48,1s ; 0 échantillon écrêté. Voir `v2_pcm_checks.json`.
- Comparaisons MP3 : gain constant par partie, cible−20LUFS, borne−1dBTP avant encodage. Voir `../listening/v2_levels.json`.

Les suites historiques signalent des ressources encore référencées à la fermeture. Les codes de retour et assertions sont corrects ; ces avertissements ne sont pas cachés dans les logs. Aucun test automatisé ne valide la fidélité à une rame réelle ou le confort subjectif. Les vidéos YouTube fournies n’ont pas été écoutées dans cet environnement.
