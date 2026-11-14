# Chargement de ville et arrivée au tram

La branche audio (66cb61c) et le dernier état Claude Code (92a8853) sont réunis. Les nouvelles cartes, les commandes et la banque sonore approuvée sont conservées.

La sélection de ville lance le préchargement des fichiers, du JSON, des graphes de réseaux et des métadonnées du décor. Un écran de chargement bloque le départ et Lancer reste désactivé jusqu’à disponibilité de la ville et de sa vue aérienne. Les sélections périmées sont ignorées ; une erreur reste visible avec possibilité de réessayer. Le cache est limité à la ville courante, réutilise ses fichiers lors d’un retour au menu et garde des graphes indépendants du JSON partagé.

Au départ, le menu disparaît par fondu et zoom. Le LOD aérien déjà construit est transféré depuis l’accueil : caméra verticale orientée au nord, glissement jusqu’à l’arrêt puis zooms par paliers et arrivée sur la pose exacte de conduite. Les tuiles détaillées sont préparées pendant l’animation ; elle attend leur disponibilité avant de révéler le quartier. Le frein initial F3 et le gel de la simulation sont conservés. Les clics et touches ne peuvent pas changer la sélection pendant la sortie du menu.

Vérifications locales : préchargement et sélection concurrente, reprise après erreur, absence de relecture des données au départ, captures OpenGL de l’arrivée, physique/scoring, 28 réseaux physiques, missions et familles audio. Les suites ciblées sont vertes ; la vérification complète du parcours accueil/reprise reste en cours au moment de la publication accélérée demandée. Les logs signalent également les avertissements historiques de ressources à la fermeture.

Tests ajoutés : test_city_preload.gd et test_arrival_transition.gd. La suite test_home.gd tient compte de la préparation asynchrone et vérifie aussi le passage de l’intro et la reprise.
