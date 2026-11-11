# Crédits et licences

- Moteur : Godot Engine 4.6.3 (MIT).
- **Décor (bâtiments, routes, eau, végétation, terrains de sport, cimetières, voies ferrées)** : Source : IGN – BD TOPO®,
  service WFS data.geopf.fr, **Licence Ouverte 2.0** (Etalab). Fichiers dérivés : `data/scenes/*.bin` (+ `.json` : date d'extraction).
- Modèles de rames, livrées, palettes de façades : créations originales du projet (aucune image ni marque reproduite) ;
  les couleurs d'accent sont les couleurs officielles des lignes publiées dans les GTFS.
- Données d'offre de transport (tracés, arrêts, horaires) issues des GTFS publiés sur transport.data.gouv.fr. Les fichiers `data/networks/*.json` sont des bases dérivées ; celles issues de jeux sous ODbL restent sous **ODbL**.

| Réseau | Producteur | Licence |
|---|---|---|
| Angers | Irigo / Angers Loire Métropole | ODbL |
| Nantes | Naolib / Nantes Métropole | Licence Ouverte 2.0 |
| Bordeaux | TBM / Bordeaux Métropole | Licence Ouverte |
| Clermont-Ferrand | T2C / SMTC-AC | Licence Ouverte 2.0 |
| Mulhouse | Soléa | Licence Ouverte 2.0 |
| Grenoble | M réso / SMMAG | ODbL |
| Toulouse | Tisséo | ODbL |
| Strasbourg | CTS | Licence Ouverte 2.0 |
| Montpellier | TaM | ODbL |
| Lille | Ilévia / MEL | Licence Ouverte 2.0 |
| Lyon | TCL / Sytral Mobilités | Licence Mobilités (vérifier les conditions) |
| Marseille | RTM / Métropole Aix-Marseille-Provence | Licence Ouverte 2.0 |
| Nice | Lignes d'Azur | Licence Ouverte 2.0 |
| Rouen | Astuce / Métropole Rouen Normandie | Licence Ouverte 2.0 |
| Reims | Grand Reims Mobilités | Licence Ouverte 2.0 |
| Dijon | DiviaMobilités | Licence Ouverte 2.0 |
| Tours | Fil Bleu / SMT | Licence Ouverte 2.0 |
| Orléans | TAO / Orléans Métropole | Licence Ouverte 2.0 |
| Le Mans | SETRAM | Licence Ouverte 2.0 |
| Caen | Twisto / Caen la Mer | non précisée sur le portail (à vérifier) |
| Brest | Bibus / Brest Métropole | Licence Ouverte 2.0 |
| Le Havre | LiA | ODbL |
| Saint-Étienne | STAS | Licence Ouverte 2.0 |
| Besançon | Ginko | Licence Ouverte 2.0 |
| Avignon | Orizo | Licence Ouverte 2.0 |
| Valenciennes | Transvilles / SIMOUV | Licence Ouverte 2.0 |
| Île-de-France | Île-de-France Mobilités | Licence Mobilités (vérifier les conditions) |
| Aubagne | Les lignes de l'agglo / Métropole Aix-Marseille-Provence | Licence Ouverte 2.0 |

Deux jeux (Lyon TCL, Île-de-France Mobilités) sont sous « Licence Mobilités » : conditions de réutilisation à vérifier avant toute diffusion publique.
Caen : licence non précisée sur le portail — à vérifier avant diffusion publique.

## Sons

Tous les sons de `data/audio/*.ogg` (onduleur IGBT, porteuse de découpage, roulement, joints de rail, crissement en courbe,
climatisation / compresseur, freinage électrique et mécanique, urgence, portes et signal de fermeture, gong, ambiance urbaine)
sont des **synthèses originales du projet** générées par `data/audio/make_audio.py` (numpy/scipy, encodage ffmpeg/libvorbis) ;
aucun audio extrait de vidéos ni d'œuvres protégées. Détail par fichier : `data/audio/sources.json`.

Enregistrements libres de référence identifiés sur Wikimedia Commons (pour recaler les synthèses ; non inclus — originaux
non téléchargeables depuis l'environnement de génération, HTTP 429) :

| Fichier Commons | Auteur | Licence |
|---|---|---|
| Départ / Arrivée d'une rame Citadis 402 à la station Porte d'Ivry | Litlok | CC BY-SA 4.0 |
| Tram sound in Lyon, France | Glaneur de sons | CC BY 3.0 |
| Tram doors open and close hiss and beeping | stephan | domaine public |
| Noodrem / Diverse bellen / Omvormer en compressor / Het rijden van een tram (Amsterdam, Den Haag) | Beeld en Geluid | CC BY-SA 3.0 |
| Ratelend voetgangerslicht en voorbij rijdende tram | Campos | CC BY-SA 3.0 |

## Images du catalogue

Vignettes `data/rolling_stock/thumbs/*.png` : rendus des modèles 3D du projet (`tools/render_thumbs.gd`), aucune photo reproduite.
Les photos Wikimedia Commons citées dans `data/rolling_stock/research.json` (« references ») ont servi de référence de forme et de
couleur uniquement ; elles ne sont pas distribuées.
