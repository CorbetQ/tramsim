# Livraison technique — TramSim Audio Studio

Branche dédiée `codex/tramsim-audio-studio`, base `be7eda97`. Aucune fusion automatique.
Instructions : [README](README.md). État avant modifications : [AUDIT](AUDIT.md) et
[inventaire SHA/formats](baseline.json). [Écoute comparative](demos/index.html).

## Implémenté et exécuté

- CLI de recherche, inspection des droits, téléchargement, catalogue, traitement,
  bouclage, génération procédurale, construction/reconstruction de banque, analyse,
  comparaison, profils de fréquence, captures, packaging des démos, rapports et tests.
- Commons : API officielle effectivement utilisée, recherches sur les **20 familles**
  et vérification de métadonnées. Résultats conservés dans [research-results.json](research-results.json).
  Certains résultats sont hors sujet : candidats de recherche, pas signatures
  acoustiques certifiées. Aucun téléchargement automatique des cas ambigus.
- Deux téléchargements réels d'originaux : Citadis 302 Moscou de trolleway, CC BY 3.0
  (**41 930 379 octets**, SHA `25b04914761b524aa9d3c31814c6f54425cd261cd6bb175905488868625de6f7`),
  et Réveil des oiseaux de Joseph Sardin, CC0 (**10 633 133 octets**).
  Le second confirme le connecteur CC0, sans remplacement inutile de l'ambiance existante.
  Originaux conservés en cache local, empreintes et preuves API dans le catalogue.
- Catalogue normalisé **70 entrées** dans le manifeste existant : 66 anciens fichiers,
  deux originaux acquis et deux dérivés nouveaux. Pas de doublon SHA détecté.
  Dates historiques inconnues conservées comme telles. Import local avec classification
  et droits explicites, y compris exports IA externes sans fausse revendication d'inférence.
- DSP déterministe : PCM flottant, filtres/égalisation, options de débruitage et de
  compression, gain constant borné, LUFS intégré FFmpeg, crête estimée 4×, silences,
  RMS/spectre/raccord, fondus, superposition de boucle. Aucun écrasement des originaux.
  WAV24/FLAC/OGG, mesures sur les octets encodés. Pas de reconstruction inventée de
  détails absents d'une source.
- Banque additive `studio_citadis302_reference_v1`, deux régimes de **4,12 s**,
  mesure après Vorbis ~−20 LUFS. Reconstruction depuis l'original **identique octet
  pour octet** pour les deux couches : [preuve](rebuild-proof.json).
- TramAudio conservé : fondu de vue de 150 ms réutilisant les lecteurs, repli par
  couche si un fichier spécifique manque, gong de banque optionnel, pause du gong
  et des lecteurs actifs, arrêt de fin de session, nettoyage de l'ancre 3D attachée
  à la vue, budget de quatre ponctuels logiques avec priorité à l'urgence/portes.
  Les bus, profils, spatialisation et protections APS/portes restent opérationnels.
- Souffle d'air accidentellement à **192 kHz** réexporté à **32 kHz** ; générateur
  corrigé pour éviter la régression. Les autres banques de production sont conservées.
- Workflow GitHub Actions audio ajouté : syntaxe, droits, SHA, formes d'onde, banques,
  tests Python/Godot, rapport artifact, capture réelle sur déclenchement manuel.
  Pas d'IA/recherche réseau à chaque commit. FFmpeg ajouté explicitement aux workflows
  historiques qui exécutent désormais les tests de formes d'onde.

## Classification des sons et limites de fidélité

| Contenu | Nature réelle | État |
|---|---|---|
| 302 de production | Captation apparentée Rotterdam/LG, modèle non certifié 302 ; régimes estimés, freinage procédural | Conservé, aucune nouvelle affectation automatique |
| 302 candidat | Captation extérieure d'un Citadis 302 à Moscou, modèle identifié dans les métadonnées ; roulement/environnement inclus | Candidat, écoute humaine requise, non activé |
| 305 de production | Modèle procédural existant, sans captation exacte de la motrice | Conservé ; ne pas prétendre qu'une vraie motrice 305 a été ajoutée |
| Autres familles | Banques enregistrées exactes/apparentées ou synthétiques préexistantes selon les profils | Pas de remplacement acoustique global non validé |
| Ambiance oiseaux | Captation CC0 générique, pas une signature d'Angers ou d'une rame | Existant préservé, original vérifié téléchargé |
| Effet de démonstration mécanique | Synthèse procédurale locale déterministe, réellement créée en cache | Pas de captation, pas d'IA, pas intégré automatiquement |
| IA | Aucun son généré | Backend désactivé |

Les anciennes ressources BY-SA conservent leur attribution et leurs obligations.
Les nouveaux téléchargements automatisés refusent BY-SA par défaut, ainsi que NC,
ND et licences inconnues. Les créations du dépôt restent `LicenseRef-TramSim-Original` :
aucune licence MIT fictive n'a été attribuée au projet, qui n'a pas de LICENSE racine.
[Attributions générées](ATTRIBUTIONS.md), crédits originaux conservés dans CREDITS.md.

## Validation réelle

Référence Python : 6 tests exécutés, avec 8 échecs de sous-cas et 2 erreurs du contrôle
historique des banques (SHA dépassés et hypothèse que toutes sont enregistrées).
Ce contrôle mesure désormais les **assets actuels** ; il ne supprime pas la vérification
SHA ni les contrôles de clipping/silence pour rendre les tests artificiellement verts.

Après modifications : **26 tests Python** (20 Studio + 6 existants), suites Godot
`audio`, `audio_families`, `audio_interlocks`, `audio_rotterdam`, `audio_variants`,
`audio_studio`. Le parcours de **76 variantes** conserve les assertions d'accélération,
freinage, portes, gong, vues, tunnel/pont, pause et interverrouillages ; ajout de fenêtres
pour que le thread audio vide ses commandes pendant ce test accéléré. Contrôles de
repli, fondu, budget de ponctuels et absence d'ancre/lecteur orphelin après destruction.
Les tests de profils de capture appellent également Godot avec des cas valides/invalides.
Les tests de réseau et d'IA sont simulés, sans achat ni secret.

Rapport de droits/formats/qualité : [quality-report.json](quality-report.json).
Avertissement restant : marge de crête réduite sur `ui_confirm.ogg` préexistant,
sans clipping détecté. Le gain faible de l'interface reste conservé.

**Cinq véritables captures Godot/ALSA**, ~47,8 s chacune, ont été produites : avant et
après pour 302 et 305, plus candidat 302. WAV Master locaux, aperçus OGG et reçus
versionnés. Elles n'utilisent pas le driver Dummy, ni une reconstruction Python du mix.
Le scénario impose la vitesse à une vraie MissionSession : pas un essai de physique.
Les niveaux ne sont pas normalisés pour donner artificiellement une impression de mieux.

| Capture | LUFS intégré aperçu OGG | Crête estimée 4× | Samples écrêtés |
|---|---:|---:|---:|
| 302 avant | −30,93 | −15,56 dBFS | 0 |
| 302 après, banque conservée | −30,94 | −15,79 dBFS | 0 |
| 302 candidat Moscou | −31,10 | −15,16 dBFS | 0 |
| 305 avant, modélisé | −30,68 | −16,26 dBFS | 0 |
| 305 après, même modèle | −30,70 | −14,96 dBFS | 0 |

Ces chiffres ne prouvent ni le réalisme ni une préférence d'écoute. **Aucune audition
humaine n'est revendiquée.** Comparer les changements de vue à 23 et 33 s ; la faible
variation globale de sonie est attendue puisque les banques de production restent les mêmes.
Les comparaisons spectrales sont livrées avec les démos, sans score d'authenticité inventé.

## Performance et formats

[Mesures avant/après](performance.json), même scénario, deux familles, même rendement
de commandes au thread audio, un seul passage sur CPU partagé à quota deux cœurs.
Le p95 du **contrôleur** est passé de 205 à 123 µs (302), de 191 à 110 µs (305).
Ce n'est pas une preuve de gain stable sur appareil : le benchmark utilise Dummy,
mesure le thread de contrôle, pas le coût de mixage réel, la latence DAC ou le GPU.
Les deux versions du contrôleur utilisent les mêmes assets courants pour cette mesure ;
le coût historique du mixage à 192 kHz n’est pas comparé par ce benchmark.
Le nombre de lecteurs alloués reste fixe. Jusqu'à 21/23 voix actives observées pendant
les chevauchements de vue, contre 15 avant ; le budget des ponctuels borne leur coût.
Aucune inférence ni analyse spectrale n'a lieu pendant une conduite.

Banques OGG : **3 453 772 octets** au total, sous le budget de 10 Mio du test. Les
nouveaux fichiers ne remplacent pas les anciennes banques. Le souffle est six fois
moins élevé en fréquence d'échantillonnage, sans gain mémoire total extrapolé arbitrairement.
Les originaux, démos, outils et poids sont hors exports de jeu selon les règles existantes.

[Comparaison 32/44,1/48 kHz](rate-comparison.json) réellement encodée sur 4,3 s de
l'original 302 : 42 052 / 43 546 / 43 780 octets OGG ; PCM flottant mono estimé
550 400 / 758 520 / 825 600 octets. 32 kHz suffit pour ces couches filtrées à 12 kHz ;
la bande utile et l'écoute priment. Ces nombres ne sont pas généralisables à toute source.

## Implémenté mais non testé en service réel

- Freesound : recherche Token, originaux OAuth, aperçus opt-in, licences : tests de
  contrat/cache/erreurs, mais aucune clé disponible pour un appel authentifié réel.
- Soundbox : contrat HTTP de soumission locale testé avec un faux serveur, garde-fous
  de configuration/poids/droits, reçus prompts/seeds/variantes. Ni installation du serveur,
  ni inférence, ni récupération automatisée complète des WAV de jobs terminés vérifiées.
- Activation permanente des candidats : commande protégée par validation d'écoute ;
  volontairement non exécutée. Les overrides de variantes restent prioritaires.
- Benchmarks audio natifs Android/Windows, latence et absence de décrochage sur matériel.
  Les captures ALSA null valident le mixage logiciel, pas un haut-parleur de téléphone.
- CI distante : état indiqué dans la pull request ; les succès locaux ne constituent
  pas une affirmation de succès GitHub Actions avant sa fin.

## Blocages et choix explicites

- IA : aucun GPU, RAM limitée à 8 Gio, disque racine saturé. Travail/cache sur tmpfs,
  qui consomme aussi la RAM. Stable Audio Open Small ~1,68 Go, gate officiel et droits
  Community conditionnels ; raw README/licence HTTP 401. AudioGen : poids NC.
  Voir [évaluation détaillée](AI-MODELS.md). Pas de contournement, poids ni fausse démo IA.
- Kenney/OpenGameArt/Europeana : liens de recherche/revue, pas de téléchargement automatique
  sans vérification par fichier. Pas de faux connecteur API annoncé opérationnel.
- Pas de MCP supplémentaire : la CLI suffit à Codex et réduit la surface d'accès.
- Aucun service audio payant activé, aucun achat. Clés optionnelles dans l'environnement.
  Les workflows consomment le quota GitHub Actions existant, sans génération IA coûteuse.

## Suites utiles

Valider les cinq écoutes, puis acquérir des captations autorisées de 305 et des
familles manquantes, idéalement en cabine et par régimes avec métadonnées de vitesse.
Comparer les régimes plutôt qu'un passage complet très bruité, compléter portes/gongs
spécifiques seulement avec preuves du matériel. Tester tunnel/pont et mixage sur un
Android bas de gamme et Windows avant remplacement des banques. Les bus d'environnement
restent partagés, appropriés à une rame principale ; un trafic de nombreuses rames
sonores demanderait une architecture de voix/environnements dédiée et mesurée.
