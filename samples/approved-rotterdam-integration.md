# Intégration de la base approuvée

La base harmonique du départ de Rotterdam, approuvée dans la conversation, est active pour les15variantes de familleCitadis302. La varianteLeMans est également redirigée. Les autresfamilles et leurs banques restent inchangées, notamment le305modélisé. Le catalogue présente explicitement « Captation apparentée » et la provenanceRotterdam.

Trois fenêtres courtes de la captation approuvée, sourceLG / CC BY4.0, alimentent les lecteurs existants : départ2–2,8s, basrégime4–5,5s, hautrégime10,25–12,75s. Raccords80–180ms, garde8ms, normalisation−20LUFS. Les harmoniques sources sont conservées sans création de nouvelles fréquences. Les empreintes et niveaux sont dans `data/audio/rotterdam-traction-manifest.json`.

L’effort de traction pilote ces couches, avec attaque et relâchement lissés. Des fondus relient les régimes selon la vitesse, avec une transposition bornée0,94–1,16. Les repères de vitesse sont des estimations de design, pas une mesure de vitesse réelle. Les bruits communs restent discrets pour laisser cette base présente.

Les couches issues du départ se retirent en roue libre et au freinage ; une captation d’accélération n’est pas transformée en prétendu freinage réel. La régénération procédurale précédente et le frein mécanique restent séparés. Le retrait acoustique est lissé, les consignes d’effort coupent immédiatement sur portes ouvertes, urgence ou absence d’alimentation.

Reconstruction : `/workspace/tram-geo-venv/bin/python tools/audio/build_rotterdam_bank.py`, puis importGodot. Le scénario de48s est capturé dans `demos/approved_rotterdam_302.*`, en vérifiant la banque `rotterdam_citadis_traction` avant de démarrer. Il s’agit du vrai mixMasterGodot à vitesse prescrite, sans conduite manuelle.

Cette première intégration n’établit pas une fidélité constructeur ni une calibration du réseauAngers ; elle met en jeu la source apparentée approuvée, avec ses limites explicites.
