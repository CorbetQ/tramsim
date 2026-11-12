# 0.9.2 — Plan, alimentation, sens normal et sons

Le bouton **Plan** remplace Carte et Aiguillages. Il conserve la recherche des arrêts,
le suivi de la rame, le déplacement, le zoom et le pincement. Les manœuvres et leurs
verrouillages restent disponibles en mode libre ; en mission, le même plan est en
lecture seule, y compris par les raccourcis clavier. M et A ouvrent ce panneau.

**Alimentation** remplace la commande séparée du pantographe. P ouvre les modes
supportés par le matériel : LAC / APS ou LAC / autonomie pour Nice. La sélection
commande aussi le collecteur. Elle est refusée en marche (vitesse ≥ 0,1 m/s), et
coupe la traction pendant les 0,6 s de commutation, durée commune à la simulation
et à l’animation. Un mode incorrect coupe l’alimentation et applique au moins F3.
L’alimentation initiale est choisie selon la section et les capacités du matériel.
Le mode d’adaptation existant du libre reste explicitement annoncé pour les rames
étrangères au réseau.

Les contacts APS étaient dessinés sous le dessus de plateforme (3,5–4,5 cm contre
9 cm). Le dessus du contact est désormais à 10,5 cm, soit 1,5 cm au-dessus de la
plateforme. Les hauteurs sont partagées entre voie et électrification. Les sections
APS restent celles des données : aucun troisième rail ajouté aux sections LAC.

Les 28 réseaux physiques libres incluent maintenant un sens normal par arête :
priorité aux tags OSM `oneway` / `railway:preferred_direction`, puis déduction sur
les paires urbaines parallèles non ambiguës. Les voies de service et le RFN non
documentés restent sans sens imposé. Le départ et les aiguillages privilégient le
sens normal et la continuité de voie, puis les voies principales. Le réglage est
appliqué une seule fois ; les manœuvres suivantes restent libres. Six choix initiaux
à contre-sens ont été corrigés et testés à Angers. Identifiants, coordonnées,
connexions et graphes de missions ne changent pas. Pour régénérer après un import :
`python tools/import/normal_directions.py` (cache OSM géographique requis).

Le moteur sonore choisit maintenant une banque par famille. **7 familles captées** :
Citadis 302, 402, 403, TFS, Flexity Marseille, Avanto et Urbos. **5 apparentées** :
Citadis Reims, Tours, Compact, X05 et X05 Nantes. **8 synthétiques** : Incentro,
Eurotram, Dualis, Tango, Vevey, Breda, Translohr et X01. Il s’agit de captations de
la même famille, pas de chaque réseau ni d’une reproduction acoustique exacte du
groupe de traction. Le statut apparaît dans la fiche du matériel. Translohr utilise
un roulement de pneus, sans joints ni crissement de roue acier. Les régimes bas et
haut se fondent selon la vitesse ; effort, freinage, cabine, tunnel et pont continuent
à piloter le mixage. Les hauteurs des captations restent dans une plage étroite.
Sources, licences et transformations : [CREDITS](../CREDITS.md),
`data/audio/families.json` et `docs/audio-bank-coverage.json`. Les résultats bruts
de recherche, parfois hors sujet, ne sont pas des sources automatiquement validées.

Les horaires GTFS et la tolérance de retard sont conservés. L’arrêt nécessaire pour
changer de mode peut donc entraîner un retard ; aucun recalage artificiel du score.

Validation : contrôles de puissance et des six aiguillages angevins, Plan commun
libre/mission, sélecteur tactile réellement ouvert, mixage des 20 familles, licences,
mesures de sonie liées aux empreintes des OGG, suite de régression et 120 missions.
Captures OpenGL sur petite fenêtre ; exports Android et Windows. Les essais ne
remplacent pas une écoute et une prise en main sur téléphone physique.
