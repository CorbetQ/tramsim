# Recherche de traction réelle — révision 3

Le bilan cumulé des recherches v2/v3 inventorie **5 fichiers complets, 6,27 Mo**, dont trois Citadis de Rotterdam, une prise intérieure de Nantes non identifiée et les essais du Citadis 302 T7 à Villejuif. Les fichiers téléchargés contiennent bien une piste audio et leurs SHA256 sont documentés. Cet agent de recherche n’a pas écouté les médias et ne certifie aucune fenêtre de moteur isolé. L’agent d’étude a reçu les fichiers.

**Aucun média réel 305 et aucun média 302 d’Angers n’a pu être téléchargé.** La collecte fournit des références vidéo identifiées ; elles ne doivent pas être comptées comme échantillons sonores disponibles. Les simulations existantes ne deviennent pas authentiques grâce à ces liens.

## Fichiers réellement disponibles

- `spotting-rotterdam-citadis-lg-56878-preview.mp3` : 122,12 s, intérieur Citadis Rotterdam, LG, CC BY 4.0. L’auteur décrit traction, freinage, portes et passagers. Sous-type Citadis non certifié par sa page.
- `spotting-rotterdam-citadis-lg-14279-preview.mp3` : 13,98 s, Citadis quittant le quai, LG, CC BY 4.0. Pas d’identité d’onduleur certifiée.
- `spotting-rotterdam-citadis-lg-18723-preview.mp3` : 13,22 s, Citadis en courbe, LG, CC BY 4.0. Référence de roulement/crissement, pas de moteur isolé.
- `revision3-nantes-interior-779136-preview.mp3` : 146,06 s, YannSauvin, CC BY 4.0. Intérieur nantais sans modèle documenté ; ne pas attribuer arbitrairement à l’Incentro, au TFS, à l’Urbos ou au X05.
- `spotting-citadis302-paris-t7-testing-reference.mp3` : 73,40 s, Soundlandscapes / Des Coulam, essais avant inauguration T7 en 2013 ; article identifiant le 302. **Référence d’étude sans licence de redistribution établie, exclue de Git par `samples/raw/.gitignore`. Ne pas intégrer ni publier ce fichier.**

Les liens source, licences, fichiers et hachages sont dans `spotting-research.json` et `revision3-downloads.json`. Aucun original nécessitant une connexion Freesound n’a été téléchargé : seulement les préviews publiques proposées par les pages HTTP200. Les trois préviews LG haute qualité sont complets. Une copie basse qualité existe aussi dans le travail partagé ; elle reste distincte de cette nouvelle collecte.

## Références 305 et Angers

Les deux références de l’utilisateur sont enregistrées en priorité : [nouveau réseau Irigo](https://www.youtube.com/watch?v=S24ij5gZQkU) et [ligne A en 2022](https://www.youtube.com/watch?v=f0bF9B_WLEc). Le type précis des rames doit être vérifié à l’image, surtout en 2022 où les302 et 305 coexistent. Leur média n’a pas été obtenu.

La [prise inductive Sydney 305](https://www.youtube.com/watch?v=rSOYQ9Df7AY) a été retrouvée par le lien 71 du [fil de son auteur](https://nswtrains.fandom.com/f/p/4400000000000122060). Elle capte des variations de champ avec une bobine : utile potentiellement pour la chronologie PWM, mais pas un enregistrement acoustique normal. Aucun son n’a été écouté ou récupéré.

Les captations Kaohsiung [arrivée 305](https://www.bilibili.com/video/BV1s5411P7v2/) et [départ 305](https://www.bilibili.com/video/BV1SX4y137m5/) sont attribuées à TPLin交通小林 par leurs pages. Le titre identifie le 305, mais la republication est explicitement interdite sans autorisation. La page de départ a répondu 412 ; aucun média n’a été téléchargé.

Le [répertoire UrbanRail](https://www.urbanrail.net/cab-rides/YOUTUBE%20VIDEOS%20CAB%20RIDES%20TRAMWAYS%20EUROPE.pdf) a permis d’identifier six cabrides Caen 2019–2020 et deux Angers 2011. Titres, auteurs, dates, durées déclarées et liens directs figurent dans `spotting-research.json`. Le registre indique le réseau et la date des prises de Caen ; le modèle doit encore être confirmé dans les images et le contenu acoustique demeure non vérifié.

## Couverture des20 familles

La matrice `revision3-family-motor-coverage.json` couvre toutes les20 familles. Les 8 familles déjà captées restent des captations souvent mêlées au roulement, aux passages, à l’ambiance ou aux auxiliaires. Il manque une preuve de motrice précise et une segmentation validée pour chacune. Aucun moteur 305 n’est déduit d’un 403.

Les recherches natives Freesound sont conservées dans `revision3-search-inventory*.json` et `revision3-model-searches.json`. Beaucoup de résultats sont des homonymes ou ambiances urbaines ; ils ne sont pas ajoutés aux sons de famille. La requête `tram-train` a finalement reçu HTTP 429 : arrêt sans nouvelle tentative. Aucun contournement des refus YouTube 403, des restrictions Bilibili ou d’une authentification n’a été tenté.
