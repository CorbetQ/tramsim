# Cahier des charges : refonte visuelle « réaliste PBR » (0.14 et suivantes)

Statut : proposition du 22/11/2026, rédigée par l'agent recherche/ingénieur. Données chiffrées : `docs/refonte-visuelle/budgets.json` et `docs/refonte-visuelle/sources.json`.

**Décision du joueur.** On abandonne la DA « low poly + cel shading ». La cible est le **niveau de qualité** des trois captures de City Transport Simulator (CTS, Unreal) rangées dans le scratchpad (`ref_cts/ref1..3`). Ces captures servent d'**étalon de qualité** et rien d'autre. TramSim garde ses réseaux français réels, ses rames françaises, son UI et sa simulation. On ne reprend aucun asset, logo, livrée ni design de CTS, pupitre compris : le nôtre est celui des Citadis et Flexity français.

---

## 1. Analyse des références et écart avec l'état actuel

### 1.1 Ce qui fait la qualité des références

| Réf. | Cadrage | Ingrédients de qualité observés |
|---|---|---|
| ref1 | Cabine, station couverte en béton | Pupitre modélisé en vrai relief : boutons, voyants, écran LCD, manipulateur, coup-de-poing rouge, sérigraphies lisibles. Béton matricé avec micro-variations. **Occlusion ambiante** très marquée sous la dalle et au pied des piliers. **Lumière indirecte** douce sous la couverture (aucun noir bouché). Rails à gorge noyés dans la dalle. Câble de caténaire fin et anticrénelé. Rame en face à l'échelle exacte, avec girouette lumineuse. Voyageurs sur le quai. |
| ref2 | Extérieur de jour, rame en mouvement | Carrosserie PBR : blanc légèrement satiné, joints de caisse, vitrages avec reflets **et** intérieur visible (sièges, barres). Pantographe détaillé. Ombre portée douce et contact shadow sous la rame. Dalles béton avec joints. Arbres feuillus réalistes avec feuillage en cartes alpha et translucidité. Herbe. **Perspective atmosphérique** (brume bleutée au loin). Monument néogothique très détaillé. Poteaux, consoles et fils de caténaire fins. |
| ref3 | Cabine, trémie/tunnel | Grands volumes béton : banches, joints, salissures en decals. Pénombre progressive à l'entrée de la trémie, gérée par l'exposition auto et la lumière indirecte. Réglettes LED en émissif. Dalle béton et rails à gorge en courbe. Végétation visible par les ouvertures latérales. |

Facteurs communs, du plus au moins déterminant :

1. **Éclairage** : GI (ou lightmaps), AO, ombres douces filtrées, exposition et tonemapping filmique (ACES/AgX).
2. **Matériaux PBR** : albédo, normal map, rugosité et AO, textures ≥ 1 px/cm de près, detail maps, decals de salissure.
3. **Densité de détail géométrique à l'échelle 1:1** : pupitre, mobilier, caténaire, joints.
4. **Végétation crédible.**
5. **Post-traitement** : TAA/FSR2, bloom discret, brouillard atmosphérique.

### 1.2 État actuel (0.13.1)

- `project.godot` : `rendering_method` = **gl_compatibility** sur PC et sur mobile. Une grande partie du pipeline 3D moderne est donc indisponible (§2).
- `src/rendering/` : shaders `toon`, `toon_building`, `cel.gdshaderinc` et `outline`/`edges`. Matériaux procéduraux qui s'estompent vers 10 m. Bâtiments en couleurs de sommet. `visual_effects.gd` gère trois profils (economy/balanced/cinematic) qui se limitent à glow et flou.
- `docs/AUDIT_VISUEL_0_11.md` : chaîne de couleur faussée (double conversion sRGB vers linéaire), voirie en rubans sans polygones de carrefour, relief à 10 m, z-fighting, aucun horizon lointain.
- Rames : `data/rolling_stock/plans/*.json` contient 20 plans cotés (modules, bogies, hauteurs de caisse, vitrages), ce qui est une très bonne base. La géométrie actuelle (`stock_geometry.gd`, `citadis_meshy.gd`) est procédurale ou issue de Meshy, à faible densité. Cabine : `tram_interior.gd`, `citadis_interior.gd`, sans pupitre détaillé.
- Données : `data/` pèse 344 Mo, dont `data/scenes` 273 Mo (224 fichiers `.bin`/`.json` pour le sol, les bâtiments et les ponts, par ville).

### 1.3 Écart (par ordre de gain visuel par unité d'effort)

| Écart | Gravité | Lot |
|---|---|---|
| Renderer Compatibility : ni GI, ni SSAO de qualité, ni TAA, ni brouillard volumétrique | Bloquant | P0 |
| Shaders toon et couleurs de sommet au lieu de PBR texturé | Bloquant | P0/P1 |
| Pas de bibliothèque de matériaux PBR (béton, pavés, enrobé, ballast, gazon, façades) | Bloquant | P1 |
| Rames et cabines basse définition, pupitre absent | Majeur | P2 |
| Voirie, carrefours et quais sans géométrie propre (bordures, joints, rails à gorge en relief) | Majeur | P1 |
| Végétation et mobilier urbain pauvres | Majeur | P3 |
| Façades génériques, monuments absents ou trop simples | Moyen | P3/P4 |

---

## 2. Faisabilité technique dans Godot 4.6

### 2.1 Renderers

| Fonction | Forward+ (PC Vulkan / D3D12) | Mobile (Android Vulkan) | Compatibility (GLES3) |
|---|---|---|---|
| PBR standard, normal/ORM | oui | oui | oui (BRDF simplifiée) |
| LightmapGI (précalculé) | oui | **oui** | oui (lecture) |
| SDFGI / VoxelGI | oui | non | non |
| SSAO / SSIL | oui | non | SSAO très basique (ajouté en 4.6, à vérifier) |
| SSR | oui | non | non |
| Brouillard volumétrique | oui | non | non |
| Brouillard exponentiel / de hauteur | oui | oui | oui |
| ReflectionProbe | oui | oui | oui (limité) |
| Decals | oui | oui | non |
| TAA / FSR2 / SMAA | oui | non (MSAA, FSR1) | MSAA, FXAA |
| Ombres douces (PCSS) | oui | partiel | non |
| MultiMesh, visibility ranges (HLOD), occlusion culling | oui | oui | oui |

Points 4.4 à 4.6 utiles : Jolt est le moteur physique par défaut. Le shader baker (4.5) précompile les pipelines et supprime les saccades de compilation à l'export, ce qui est crucial sur Android. AgX est disponible comme tonemapper. D3D12 est le pilote par défaut sous Windows en 4.6, à évaluer sur ARM64 (Snapdragon X) face à Vulkan. Le glow Mobile a été optimisé en 4.6. Le site godotengine.org n'est pas joignable depuis ce conteneur : les détails 4.6 sont à revérifier sur le changelog officiel.

### 2.2 Stratégie retenue

| Profil | Plateforme | Renderer | Éclairage | Post-traitement |
|---|---|---|---|---|
| **Ultra** | PC x64 avec GPU dédié | Forward+ | SDFGI (extérieur) ou LightmapGI (stations, trémies), SSAO+SSIL, brouillard volumétrique, ombres 4096 PCSS, SSR | TAA ou FSR2 qualité, AgX, bloom léger |
| **Haut** | PC x64 iGPU, Windows ARM64 (Adreno X1) | Forward+ | LightmapGI + probes, SSAO moitié, sans SDFGI, brouillard de hauteur | FSR2 équilibré ou SMAA |
| **Mobile** | Android Vulkan milieu de gamme (Adreno 6xx/7xx, Mali-G7x) | **Mobile** | LightmapGI précalculé (stations, trémies, abords), AO cuite dans les textures et la couleur de sommet, ReflectionProbes statiques, decals | MSAA 2x + FSR1 à 0,75, glow Mobile |
| **Repli** | Android sans Vulkan correct, vieux PC | Compatibility | Même contenu, lightmaps cuites, pas de decals (remplacés par des quads) | FXAA |

Principe : **le réalisme vient d'abord du contenu cuit** (lightmaps, AO cuite, textures PBR). C'est ce qui permet au profil Mobile de rester proche du PC. Les effets temps réel (SDFGI, SSIL, brouillard volumétrique) sont des bonus réservés au PC.

Choix du renderer au lancement : `rendering_method` = `forward_plus`, `rendering_method.mobile` = `mobile`. Repli automatique `--rendering-method gl_compatibility` si Vulkan échoue : Godot le fait nativement avec `rendering/rendering_device/fallback_to_opengl3`. Le shader cel et l'outline sont retirés (on garde éventuellement une option « style BD » hors périmètre).

### 2.3 Contraintes

- **Mobile** : bande passante limitée. Pas de transparence plein écran, au plus 4 lumières dynamiques ombrées et 8 omni par objet en Mobile (limite moteur). Les textures doivent être en ETC2/ASTC (VRAM compression « Mobile »).
- **Windows ARM64** : les exports Godot existent. GPU Adreno X1 de 3,8 à 4,6 TFLOPS environ, soit le niveau d'un iGPU. Mesurer D3D12 contre Vulkan. Profil « Haut ».
- **Taille** : APK actuel ≈ données de 344 Mo. Visé : APK de base ≤ 150 Mo (Play Store) + **Play Asset Delivery** (packs par ville, install-time/on-demand, max 2 Go par pack fast-follow). Sous Godot, cela passe par des `.pck` additionnels par ville téléchargés au premier lancement, ou par l'intégration PAD via le plugin Gradle Android.

---

## 3. Choix du moteur (demande du joueur)

Comparaison objective **pour ce projet** : simulateur ferroviaire français, 28 villes générées depuis l'open data, Android + Windows x64/ARM64, CI Linux headless, 24 400 lignes GDScript (`src`, `tests`, `tools`) + 11 800 lignes Python d'import.

| Critère | Godot 4.6 (Forward+ / Mobile) | Unreal Engine 5.6+ | Unity 6 (URP / HDRP) |
|---|---|---|---|
| Qualité atteignable sur PC | Très bonne avec assets PBR + SDFGI/lightmaps. En dessous de Lumen/Nanite sur la GI dynamique et la micro-géométrie. Le niveau des références est **atteignable** : CTS lui-même est assez sobre (béton, ombres, AO). | Maximale : Lumen, Nanite, Virtual Shadow Maps. Référence du secteur. | HDRP : très élevée sur PC seulement. URP : proche de Godot Forward+, avec APV (probes) et SSAO. |
| Android milieu de gamme | Renderer Mobile correct, lightmaps et probes. Même contenu que le PC. | Renderer mobile ES3.1/Vulkan **sans Lumen ni Nanite** (Lumen mobile expérimental, haut de gamme seulement). Il faut deux pipelines de contenu. | URP efficace sur Android, le plus éprouvé sur mobile. HDRP non supporté sur mobile. |
| Windows ARM64 | Export officiel | Support WinArm64 récent ou partiel, à vérifier par version | Player Windows ARM64 supporté |
| Taille APK minimale | ≈ 30 à 40 Mo pour le moteur | ≈ 100 Mo en Shipping en 5.6 (mesure communautaire, 340 Mo en 5.4) | ≈ 20 à 40 Mo (IL2CPP, stripping) |
| Licence | MIT, 0 € | Gratuit jusqu'à 1 M$ de revenus bruts par produit, puis 5 % de redevance. EULA Epic. | Personal gratuit sous 200 k$ (splash optionnel depuis Unity 6). Pro ≈ 2 310 $/an par siège en 2026. Plus de runtime fee. |
| CI Linux / GitHub Actions | **Fonctionne aujourd'hui** (headless, xvfb + llvmpipe, `tests.yml`, `release.yml`) | Moteur à compiler depuis les sources (compte Epic lié à GitHub). Images Docker `ghcr.io/epicgames` de plusieurs dizaines de Go. Cook Android lourd : 100 à 200 Go de disque et des heures par build. Les runners GitHub standard (14 Go de disque) sont **insuffisants**, il faut un runner auto-hébergé. | GameCI (images Docker de 5 à 15 Go), build headless Linux possible. Activation de licence obligatoire dans la CI (secrets de compte Unity). Faisable sur runners standard. |
| Faisable dans **ce conteneur** (4 vCPU, 15 Go de RAM, pas de GPU, **3,9 Go de disque libre**, réseau filtré) | Oui, c'est l'existant | **Non** (disque, pas de GPU pour l'éditeur, téléchargements Epic) | Très difficile : éditeur > 10 Go, activation, pas de GPU. Seul un build CI externe est possible. |
| Coût de migration | 0 (évolution) | Tout réécrire en C++/Blueprint : simulation, UI, imports runtime, tests. Les `.bin` de `data/scenes` sont à réimporter (format maison, lecteurs à réécrire). Estimation **9 à 15 mois-agent**. | Réécriture en C# (portage GDScript → C# plus mécanique). UI à refaire (UI Toolkit). Estimation **6 à 10 mois-agent**. |
| Réutilisable | Tout | `data/*.json`, outils Python d'import (ils produisent des données indépendantes du moteur), plans de rames, assets glTF | Idem |

### Recommandation

**Rester sur Godot 4.6** : Forward+ sur PC, Mobile sur Android, Compatibility en repli.

Arguments chiffrés :

1. L'écart visuel avec les références tient à **80 % au contenu et à l'éclairage cuit**, pas au moteur. Les références ne montrent ni Nanite ni GI dynamique indispensable.
2. Sur Android, qui est une cible prioritaire, **Unreal perd Lumen et Nanite**. Il ne garderait l'avantage que sur PC, pour un coût de migration de 9 à 15 mois et une CI non faisable ici.
3. Unity URP n'apporte qu'un gain modeste sur mobile, pour 6 à 10 mois de portage et une dépendance de licence.
4. Le risque d'une migration (réécrire 36 000 lignes et la CI) est supérieur au risque technique d'une montée en gamme Godot (perf Android, résolue par les lightmaps).

**Stratégie hybride** : Godot reste le runtime, et la qualité est produite **hors moteur**. Blender en CLI (bpy) sert à la modélisation procédurale, au bake d'AO et de lightmaps éventuel, et aux LOD. Les assets sont en glTF et KTX2, donc **portables** : si une édition PC séparée sous Unreal était décidée un jour, ils resteraient réutilisables, comme les données `data/` et les outils Python.

**Porte de décision (go/no-go)** à la fin du lot P1, sur la tranche verticale « Angers, station Ralliement + trémie » :

- si le profil Ultra n'atteint pas les critères du §7 (comparaison à l'aveugle avec les références ≥ 3/5 en moyenne sur 3 évaluateurs) **et** que l'écart est attribuable au moteur (GI, densité géométrique), on réévalue une **édition PC Unreal** séparée : 6 mois, réutilisation des données et des assets, mobile laissé sous Godot ;
- sinon, on continue sous Godot.

Risque estimé : migration UE ≈ élevé (délai × 3, CI hors conteneur). Montée en gamme Godot ≈ moyen (perf mobile).

---

## 4. Pipeline d'assets

### 4.1 Sources libres (licences vérifiées sur les pages de licence connues ; à revérifier au moment de l'import)

| Source | Licence | Usage |
|---|---|---|
| Poly Haven (textures, HDRI, modèles) | CC0 | Béton, pavés, enrobé, gazon, écorces, HDRI ciel |
| ambientCG | CC0 | Matériaux PBR (béton, briques, ballast, métal, peinture) |
| Kenney, Quaternius | CC0 | Accessoires génériques (mobilier, voitures basse définition pour LOD) |
| Sketchfab, filtre CC0/CC-BY | Variable, **vérifier par modèle** | Monuments éventuels (CC-BY à créditer dans `CREDITS.md`) |
| IGN BD TOPO, LiDAR HD, BD ORTHO | Licence Ouverte 2.0 (Etalab) | Emprises, hauteurs, toits, orthophotos (déjà utilisés) |
| Panoramax | Photos majoritairement CC-BY-SA 4.0 (selon l'instance et l'auteur) | **Références visuelles** de façades et de stations. Pas de texture dérivée si CC-BY-SA, sauf conformité de partage. |
| Wikimedia Commons | Selon le fichier | Références de rames et de pupitres (déjà `tests/audit/refs_commons.py`) |

Interdit : assets et marques CTS, kits « ripped », logos d'exploitants sans accord. Les livrées sont reproduites comme schéma de couleurs, sans logos déposés, ou remplacées par des génériques.

Réseau : depuis ce conteneur, **polyhaven.com et ambientcg.com sont bloqués par le proxy** (403). github.com et npm sont accessibles. Il faut soit autoriser ces hôtes dans l'environnement, soit télécharger en CI (`release.yml` a accès à Internet).

### 4.2 Bibliothèque de matériaux (P1)

Format : textures 2048² (PC) et 1024² (mobile), ORM packé (AO/Rough/Metal), normal en BC5/ETC2-RG, albédo sRGB. Atlas par famille.

| Famille | Variantes minimales |
|---|---|
| Béton | banché, lissé, dalle de plate-forme avec joints, matricé (trémies) |
| Sols | enrobé neuf et usé, pavé granit, pavé béton, dalles calcaire, bordures granit |
| Voie | dalle béton avec gorge, gazon de plate-forme (sedum et gazon), ballast, rail (acier usé, tête brillante) |
| Façades | pierre de taille, tuffeau (Angers, Tours), brique (Lille, Toulouse), enduit, crépi, menuiseries |
| Toitures | ardoise, zinc, tuile mécanique, tuile canal, terrasse |
| Divers | verre (abris), inox brossé, peinture RAL (livrées), caoutchouc |

### 4.3 Outils (essais faits dans ce conteneur le 22/11/2026)

| Outil | Rôle | Statut ici |
|---|---|---|
| **ImageMagick 6.9** | Atlas, conversion, réduction | **Installé** (`/usr/bin/convert`) |
| **gltfpack 1.3** (meshoptimizer, npm WASM) | Simplification LOD, quantification, meshopt | **Installable et testé** : `npm i gltfpack` fonctionne (essai dans le scratchpad) |
| **Blender** en headless | Modélisation procédurale, bake AO et lightmap, export glTF | `apt` : candidat **4.0.2**. `pip install bpy` : wheel **5.3.0 cp313** téléchargeable (427 Mo, ≈ 1,5 Go installé). **Non installé** car il ne reste que 3,9 Go de disque libre. À installer en CI ou après nettoyage. |
| **toktx / KTX-Software** (KTX2 + Basis Universal) | Compression GPU universelle | Releases GitHub accessibles (binaire Linux .deb/.tar). **Non installé.** `pip basisu` n'existe pas. |
| Godot 4.6.3 headless | Import, tests, captures | Absent du conteneur à cet instant. Présent dans la CI (`tests.yml`). |
| Python 3.13, Node 22 | Scripts d'import | Présents |

Pour les textures, Godot réimporte en VRAM compressée (S3TC/BPTC sur PC, ETC2/ASTC sur Android). KTX2/Basis n'est utile que pour le transport compact en glTF (`KHR_texture_basisu`, supporté par l'importeur Godot). **Priorité** : importer en PNG/WebP sources, puis laisser Godot compresser par plateforme. Les KTX2 servent aux packs de téléchargement.

### 4.4 Génération procédurale des villes

1. **Bâtiments** : emprise BD TOPO + hauteur LiDAR (déjà en place) → génération de façades par **grammaire** (rez-de-chaussée commercial, étages courants, corniche, toit) avec modules glTF par **style régional** (`data/city_styles.json` à étendre : haussmannien, tuffeau angevin, brique du Nord, béton des années 1970). Les toits sont issus de LiDAR/ortho (pente, matériau).
2. **Textures de façade** : bibliothèque modulaire. Les photos Panoramax servent de **référence** pour le choix du style par îlot, pas de projection directe (licence et qualité).
3. **Monuments** : liste dans `data/landmarks.json`. Modèles dédiés pour les 1 à 3 monuments visibles depuis la ligne dans chaque ville (cathédrale Saint-Maurice à Angers, château des Ducs à Nantes…), créés par l'agent modélisateur ou issus de sources CC-BY vérifiées.
4. **Voirie** (corrige l'audit 0.11) : polygones de carrefour, trottoirs continus, bordures extrudées, passages piétons en decals.

---

## 5. Rames

### 5.1 Exigences par modèle

- **Extérieur** : PBR. Peinture de caisse en clearcoat (Godot `clearcoat`). Joints de caisse et intercirculations en soufflet. Vitrages réfléchissants avec ReflectionProbe, intérieur visible à travers. Bogies et carénages, pantographe articulé (animation lever/baisser liée à la simulation). Feux, girouettes et indicateurs en émissif piloté par l'état.
- **Intérieur voyageurs** : sièges, barres, plancher, plafonnier, écrans d'info, portes animées.
- **Cabine** (vue conducteur) : pupitre modélisé **par rame** selon photos. Chaque commande du jeu (manipulateur, klaxon/gong, portes, pantographe, sablage, phares, essuie-glace, arrêt d'urgence, rétroviseurs ou caméras) a un **nœud 3D nommé** (`ctl_<action>`) lié à `src/input` et `src/simulation`. Voyants, écrans et vitesse sont rendus en `SubViewport` ou en matériaux émissifs pilotés. Cible : cliquable/touchable à terme.
- **Échelle** : celle des plans `data/rolling_stock/plans/*.json` (longueur, hauteurs, bogies), tolérance ±2 cm.

### 5.2 LOD et budgets (par rame complète)

| LOD | Distance | PC tris | Mobile tris | Textures |
|---|---|---|---|---|
| LOD0 + cabine | < 25 m / vue cabine | 250 k (cabine 80 k) | 80 k (cabine 40 k) | PC 3 × 4096 + 2048 cabine ; mobile 2048 + 1024 |
| LOD1 | 25 à 80 m | 60 k | 25 k | idem (mips) |
| LOD2 | 80 à 250 m | 12 k | 6 k | 512 atlas |
| LOD3 / imposteur | > 250 m | 1,5 k | 1 k | 256 |

Mobile : 3 rames maximum en LOD0 simultanées.

### 5.3 Priorités

1. **Citadis X05** (Angers 305, Nantes 405), puis **Citadis 302** (Angers). Les références Meshy et les photos existent déjà dans `docs/rolling-stock-meshy`.
2. Citadis Dualis.
3. Flexity (Marseille), TFS (Grenoble, Rouen…).
4. Le reste du parc de `data/rolling_stock/plans` (20 plans).

**Sources** : plans cotés existants. Photos libres Commons et Panoramax (CC-BY/CC-BY-SA, comme références uniquement). Données constructeur publiques (fiches techniques). Pas de plans propriétaires.

**Méthode** : génération de la caisse par script Blender depuis le plan JSON (profil de caisse, modules, baies), puis détail manuel ou procédural. Les maillages Meshy servent au mieux de proxy de forme ; leur topologie et leurs UV ne sont pas utilisables en HD.

---

## 6. Environnement

- **Stations** : quais en béton ou dalles avec bande podotactile, bordure de quai, abris par réseau (modèles dédiés selon `data/station_models`), totems, distributeurs, bancs, éclairage. Stations couvertes ou souterraines en LightmapGI.
- **Voies** : rail à gorge Ri60 modélisé en profil extrudé (tête, gorge, contre-rail), sur dalle béton, gazon ou pavés. Joints de dilatation. Appareils de voie modélisés (aiguilles, cœurs). Gazon en shader avec fibres en cartes à courte distance.
- **Trémies, tunnels, ponts** : béton banché, joints, réglettes LED, salissures en decals, lightmap. Garde-corps et parapets. Ponts selon type (dalle, poutres, arc).
- **Caténaire** : poteaux tubulaires ou treillis, consoles, haubans, isolateurs, fil de contact en ruban géométrique anticrénelé (shader avec épaisseur minimale en pixels pour éviter le scintillement). Pendules.
- **Végétation** : 6 à 8 essences françaises (platane, tilleul, marronnier, érable, pin parasol au sud, chêne). Feuillage en cartes alpha avec translucidité, vent léger. LOD : maillage, puis cartes simplifiées, puis imposteur octaédrique. Haies et massifs. MultiMesh partout.
- **Mobilier urbain français** : feux R17 (signalisation tramway, barres blanches) et R11/R13, potelets, barrières, poubelles, candélabres par ville, panneaux de police, plaques de rue, abribus, bornes, vélos, véhicules (LOD), piétons animés (LOD).
- **Éclairage, temps, météo** : cycle jour/nuit (`day_night.gd` à refaire) avec ciel physique (`PhysicalSkyMaterial` ou ciel personnalisé), HDRI de nuit et de couvert. Exposition auto (« camera attributes » physiques). Pluie : chaussée mouillée (rugosité et flaques), gouttes sur le pare-brise de la cabine, essuie-glace. Brouillard : de hauteur relatif au sol (bug de l'audit 0.11) et volumétrique sur PC. Nuit : candélabres en omni à distance limitée, émissif + lightmap.
- **Post-traitement** : tonemapper AgX ou ACES, une seule conversion de couleur, contraste et saturation à 1,0, bloom bas, TAA/FSR2 sur PC.

---

## 7. Budgets et critères d'acceptation

### 7.1 Budgets (détails dans `budgets.json`)

| Mesure | Ultra PC (RTX 3060 / RX 6600, 1440p) | Haut (iGPU, Win ARM64, 1080p) | Mobile (Adreno 650 / Mali-G78, 1080p ×0,75) |
|---|---|---|---|
| FPS cible (P1, centre dense) | 60 (min 45) | 45 (min 30) | 30 stables (min 25), thermique 20 min |
| Draw calls | ≤ 3 000 | ≤ 2 000 | ≤ 600 |
| Triangles visibles | ≤ 8 M | ≤ 3 M | ≤ 800 k |
| VRAM | ≤ 4 Go | ≤ 2 Go (partagée) | ≤ 1 Go |
| RAM du processus | ≤ 6 Go | ≤ 4 Go | ≤ 2 Go |
| Taille | Installateur PC ≤ 6 Go | idem | APK de base ≤ 150 Mo + packs de ville ≤ 400 Mo chacun |
| Saccades | aucune image > 50 ms après 10 s (shader baker) | idem | idem |

### 7.2 Critères d'acceptation vérifiables

1. **Captures comparatives** : `tests/audit/` est étendu avec trois cadrages fixes qui reproduisent les références sur des sites français réels.
   - C1 : cabine X05 en station couverte (Angers, à définir, ou trémie Nantes).
   - C2 : rame à l'arrêt, extérieur avec monument (Angers Ralliement, cathédrale en fond).
   - C3 : cabine en trémie.

   Rendu par profil, avec planche côte à côte référence/TramSim. Notation à l'aveugle sur cinq axes (éclairage, matériaux, détail, végétation, cabine) : **moyenne ≥ 3/5**, aucun axe < 2.
2. **Tests automatiques** en CI (headless) :
   - aucun matériau `toon`/`cel` restant (grep) ;
   - tous les `StandardMaterial3D` ou shaders PBR ont albédo + normale + ORM ;
   - LOD présents (visibility ranges) sur tout maillage > 5 k triangles ;
   - budgets de draw calls et de triangles mesurés via `Performance.get_monitor` sur les points d'audit (comme `p0-performance.yml`) ;
   - taille d'APK et de `.pck` contrôlée ;
   - histogramme des captures : pas de noir pur > 2 % ni de sursaturation (régression de l'audit 0.11) ;
   - nœuds `ctl_*` de la cabine présents pour chaque commande du jeu.
3. **Mesure sur appareils réels** (Android de référence + PC ARM64) par un test de 5 minutes : FPS moyen et 1 % bas consignés dans `docs/refonte-visuelle/mesures/`.

---

## 8. Plan de lots

| Lot | Contenu | Agents | Dépend de | Durée indicative |
|---|---|---|---|---|
| **P0** Fondations rendu | Bascule Forward+/Mobile + repli Compatibility. Suppression du cel/outline. Profils de qualité (`visual_effects.gd`). Chaîne de couleur, tonemapper, exposition. Brouillard relatif au sol. Installation des outils (Blender bpy, gltfpack, toktx) en CI. Shader baker. Tests de §7.2 (squelettes). | Ingénieur | — | 1 à 2 semaines |
| **P1** Tranche verticale Angers | Bibliothèque de matériaux PBR (béton, dalle, rails, pavés, gazon). Voie à gorge HD. Station Ralliement + une trémie avec lightmaps. Voirie en polygones. Captures C1 à C3. **Porte go/no-go moteur.** | Ingénieur + modélisateur + recherche (sources) | P0 | 3 à 4 semaines |
| **P2** Rames HD | Citadis X05 puis 302 : extérieur, intérieur, cabine avec pupitre lié aux commandes, LOD0-3, pipeline plan JSON → Blender. | Modélisateur + ingénieur (liaison commandes) | P0 (P1 pour l'éclairage) | 4 à 6 semaines |
| **P3** Ville dense | Façades par grammaire et styles régionaux, végétation et mobilier, caténaire HD, monuments d'Angers et de Nantes, packs de ville (PAD). | Modélisateur + ingénieur + recherche | P1 | 6 à 8 semaines |
| **P4** Généralisation | 28 villes, rames restantes, météo et nuit avancées, monuments des autres villes, optimisation mobile finale. | Tous | P2, P3 | continu |

**Conservé** : toutes les données géographiques et les imports (`data/`, `tools/*.py`), la simulation (`src/simulation`), l'UI, l'audio, les tests et la CI. `data/scenes/*.bin` sert de base, régénéré avec plus de détail (sol plus fin, polygones de voirie). Les plans de rames restent la source de vérité dimensionnelle.

**Remplacé** : shaders toon/cel/outline, `stock_geometry.gd` et `citadis_meshy.gd` (remplacés par des glTF HD), une partie de `street_props.gd` et de `station_layout.gd` (remplacés par des scènes d'assets), `day_night.gd` (refait).

### Risques majeurs

| Risque | Prob. | Impact | Mitigation |
|---|---|---|---|
| Perf Android insuffisante (thermique) | Élevée | Élevé | Contenu cuit, LOD stricts, profil Mobile distinct, mesure sur appareil dès P1 |
| Taille data/APK (textures HD × 28 villes) | Élevée | Élevé | Atlas partagés entre villes, packs par ville téléchargeables, ASTC/ETC2, KTX2 |
| Licences (CC-BY-SA, photos, logos d'exploitants) | Moyenne | Élevé | `sources.json` + `CREDITS.md` obligatoires par asset, revue par l'agent recherche, pas de logos |
| Temps de modélisation (rames et cabines) | Élevée | Moyen | Génération procédurale depuis les plans, priorités X05/302, pupitres modulaires partagés entre Citadis |
| Environnement (disque 3,9 Go libre, pas de GPU, Poly Haven/ambientCG bloqués) | Certaine | Moyen | Bakes et téléchargements en CI, ou autorisation des hôtes ; captures llvmpipe en Compatibility/Forward+ logiciel (lent) |
| Bakes LightmapGI longs sans GPU | Moyenne | Moyen | Bake par station en CI, ou bake d'AO dans Blender Cycles CPU |

---

## 9. État P0 (22/11/2026)

**Livré** (lot P0 « Fondations rendu ») :

| Point | Réalisation |
|---|---|
| Renderers | `project.godot` : Forward+ (PC), Mobile (Android), Vulkan imposé sous Windows (`driver.windows`) avec repli D3D12 puis **repli automatique Compatibility** (`fallback_to_opengl3`, ANGLE). Compression VRAM ETC2/ASTC + S3TC/BPTC. Presets d'export (Android, Windows, Windows ARM64) : **shader baker activé** ; `release.yml` réessaie l'export sans baker (avertissement) si le baker échoue en headless. |
| Fin du cel shading | `toon`, `toon_building`, `cel.gdshaderinc`, `outline`, `edges` supprimés. Shaders PBR : `pbr_object` (rames, végétation, objets), `pbr_world` (décor, rugosité/métal/spéculaire par identifiant de matériau, nouvel id 9 = acier des rails), `water`, `station_paving`, `meshy_citadis` ; **aucun `light()` personnalisé** (BRDF du moteur). Rames : peinture vernie (clearcoat), vitrages rugosité 0,08 ; feuillage translucide (BACKLIGHT). |
| Bibliothèque PBR | `src/rendering/pbr_materials.gd` + `data/materials/*.json` (16 fiches : enrobé, dallage, gazon, façade, rail, béton, ballast, peinture, vitrage, feuillage…) : albédo/normal/ORM/échelle métrique ; **repli documenté** : couleur unie + scalaires tant que P1 n'a pas livré les textures (toutes les fiches sont en repli à ce stade). |
| Profils de qualité | `visual_effects.gd` : Ultra (SDFGI, SSAO+SSIL, SSR, brouillard volumétrique, ombres 4096 + PCSS, TAA), Haut (SSAO ½, FSR2 0,77, ombres 2048), Mobile (MSAA 2x + FSR1 0,75), Repli (FXAA). Choix auto par renderer et type de GPU, plafonné par le renderer actif ; Réglages « Qualité graphique » (Automatique par défaut, anciens choix 0.13 convertis), sauvegardé dans `settings.visual_profile`. |
| Chaîne de couleur | Conversion sRGB → linéaire **unique** en fin de fragment (`pbr_albedo`, identité en Compatibility où `OUTPUT_IS_SRGB`, mesuré 0,5 → 0,502 ; Forward+/Mobile linéaires, 0,5 → 0,737 sans conversion). Tonemapper **AgX**, exposition jour/nuit, ambiance issue du ciel, ciel physique simplifié (masse d'air, Mie Henyey-Greenstein, disque HDR, nuages fBm lissés) toujours piloté par DayNight/WeatherView, brouillard de hauteur relatif au sol, glow léger (seuil HDR 1,1). |
| Outils CI | `.github/workflows/asset-tools.yml` (séparé, n'allonge pas `release.yml`) : gltfpack 1.3.0 (npm), toktx (dernière release KTX-Software), Blender 4.5 LTS (tarball) ; cache `actions/cache`, contrôle des versions. |
| Tests §7.2 | `test_pbr_materials` (aucun vestige toon/cel/outline, aucun `light()`, fiches complètes ou repli documenté), `test_quality_profiles` (réglages par profil, plafonnement, AgX, brouillard, renderers, baker), `test_render_budgets` (Angers, station dense : draw calls/triangles via `Performance.get_monitor` contre `budgets.json`, histogramme : noir pur ≤ 2 %, saturation ≤ 3 %, luminance de jour). Ajoutés à `tests/run_all.sh` ; les tests à affichage forcent `--rendering-method gl_compatibility`. |

**Correctifs annexes** : matériaux non éclairés à couleurs de sommet (`AerialCityLOD` de l'accueil, lignes, caténaire, événements, pluie) passés en `vertex_color_is_srgb` : le fond d'accueil n'est plus délavé en Forward+ (luminance 0,74 → 0,48, identique à Compatibility). `test_arrival_transition` compare la qualité restituée à celle du profil appliqué.

**Tests** : `test_pbr_materials`, `test_quality_profiles`, `test_render_budgets` et les tests rendu/UI (scene, scene_data, world_geometry, map_surfaces, home, input, mobile, explore, arrival_transition, cinematic_lod, rails_visible, rolling_stock, stock_ui, citadis_meshy, passenger_mode) verts en Compatibility. Captures avant/après et planche hors dépôt (scratchpad `p0/`).

**Mesures** (Angers, St-Serge Université, 1280×720) : 3e personne 383 draws / 1,08 M triangles (Compatibility), 406 / 1,20 M (Forward+, lavapipe) ; cabine 286 / 1,07 M ; verticale 131 / 0,33 M ; nuit 408 / 1,32 M. Dans le budget Haut (2 000 / 3 M) ; **au-delà du budget Mobile en triangles (800 k)** : LOD/HLOD à traiter en P1 (signalé en INFO par le test). Histogramme : 0 % de noir pur de jour, 0,17 % de nuit (Compatibility).

**Limites** : pas de GPU ici, Forward+ et Mobile validés en rendu logiciel (lavapipe) uniquement ; perf réelle et shader baker à mesurer sur appareils et en CI ; SDFGI/volumétrique non mesurés en perf ; lightmaps (LightmapGI) prévues par profil mais aucune n'est cuite (P1) ; géométrie encore low poly à normales de facette.

**Reste pour P1** : textures PBR réelles dans les fiches `data/materials`, decals, LightmapGI des stations/trémies, LOD/HLOD pour tenir le budget Mobile, voie à gorge et voirie en polygones, captures C1–C3 et notation à l'aveugle.

---

## 10. État P1 (22/11/2026) — lot ingénieur

| Point | Réalisation |
|---|---|
| Bibliothèque de matériaux | **18 couches de textures CC0 Poly Haven** (2K téléchargées, recompressées) dans trois `Texture2DArray` (albédo sRGB, normale OpenGL, ORM = AO/rugosité/métal) `assets/textures/pbr/{albedo,normal,orm}_{2k,1k}.jpg`, importées en VRAM compressée (S3TC/BPTC + ETC2/ASTC), mipmaps, anisotrope. Couches : enrobé, dallage, gazon, ardoise, enduit, sol nu, acier de rail, dalle béton, ballast, pavés granit, tuffeau, brique, bordure granit, béton banché, métal peint, pierre de taille, écorce, bois. 32 fiches texturées (16 propres + 2 `lm_*` propres + 14 `lm_*` du modélisateur par `texture_from`, teinte de la fiche, `texture_contrast`/`texture_saturation`), 16 en repli **par conception** (verre, eau, émissifs, feuillage en cartes, livrée, marquage). Chaîne : `tools/materials/fetch_polyhaven.sh` → `build_texture_arrays.py` (fiches mises à jour : couche, moyennes d'albédo/rugosité/AO). Licences : `CREDITS.md`, `docs/refonte-visuelle/sources.json` (`textures_p1`). |
| Shaders | `pbr_textures.gdshaderinc` (commun) : projection métrique sans UV (sol en XZ monde, murs/pentes par facette), `textureGrad` hors branches, **l'albédo module la teinte calibrée** (rapport texture / moyenne de couche : histogrammes inchangés), normal map en repère monde, ORM (rugosité relative, AO). Anti-répétition : 2ᵉ échantillon tourné/réduit mélangé par bruit macro (PC) ; Mobile/Repli : 1 échantillon, 1024². `pbr_world` : couche par identifiant de matériau (16 ids, 6 nouveaux : dalle béton, ballast, pavés, granit, béton banché, métal peint) et par type d'appareil de façade ; vitrages des façades sans normal map. `pbr_surface.gdshader` + `PbrMaterials.surface(id, opts)` : API des modèles dédiés (UV2 libre pour les lightmaps), utilisée par `LandmarkModels`. Profil : `PbrMaterials.set_profile` appelé par `VisualEffects`. |
| Voie à gorge HD | `TrackView` : profil **Ri60** extrudé (chanfrein, congé de roulement, flancs et fond de gorge, lèvre, âme sur longrine) en **LOD proche** par cellules de 64 m (`NearSink`, portée 90 m PC / 45 m Mobile, sans ombre) ; LOD de base confondu (mêmes faces, même teinte : pas de scintillement). Plateforme texturée : dalle béton (joints tous les 6 m), pavés granit, gazon, enrobé ; bordures granit ; soutènements en béton banché ; aiguilles et cœurs inchangés (P0). Test `test_track_hd`. |
| Voirie | Déjà en polygones (P0.11 : `RoadView`, bordures extrudées 15 cm, marquages en géométrie). P1 : enrobé, trottoirs (dallage), **bordures granit**, ballast et pavés texturés ; marquages exclus du texturage (nets). Les marquages restent des **quads** dans les trois renderers (nets, sans coût de clusters) ; les `Decal` sont réservés aux salissures (P3). |
| LOD / HLOD | Végétation : **HLOD par tuile** (houppier simplifié ≈ 12 triangles, sans ombre, toujours affiché) + arbre complet par cellule de 100 m jusqu'à 230 m (PC) / 110 m (Mobile) ; arbustes et vivaces par cellule (120 / 60 m). Mobilier : instances découpées par cellule de 100 m (la portée de visibilité Godot se mesure au centre de la boîte englobante : auparavant une tuile de 400 m rendait ces portées inopérantes). Rail : LOD proche par cellule. |
| Budgets | `test_render_budgets` : 2ᵉ passe **Mobile bloquante** (contenu `low_quality`, profil Mobile, textures 1024²) contre 600 draws / 800 k triangles (ombres comprises). Mesures Angers St-Serge (Compatibility, 1280×720) : PC 3ᵉ pers. **411 draws / 538 k tris** (P0 : 383 / 1,08 M), cabine 291 / 516 k, nuit 427 / 598 k ; **Mobile** 3ᵉ pers. **305 / 475 k**, cabine 232 / 475 k, nuit 347 / 533 k. Captures : C2 Ralliement 294 / 649 k (Mobile 258 / 589 k), C1 209 / 383 k (Mobile 157 / 311 k) ; Forward+ lavapipe du même ordre (C2 325 / 677 k). Histogramme inchangé (0 % de noir pur de jour). |
| LightmapGI | `tools/lightmaps/prepare_lightmaps.gd` (headless) : scènes de cuisson `assets/lightmaps/<id>/<id>_bake.tscn` pour Ralliement et la trémie L3 (LOD0 déplié en UV2 par xatlas, LightmapGI non directionnel 2048, 3 rebonds, soleil en cuisson indirecte seule, données `.lmbake` pré-attribuées). `tools/lightmaps/bake.sh` : cuisson sans intervention par l'éditeur (greffon activé le temps de la cuisson, bouton « Bake Lightmaps »). **Ici (lavapipe, 4 cœurs) : la cuisson ne se termine pas en 25 min** → à exécuter sur un poste GPU ou en CI GPU ; les scènes cuites sont ensuite à brancher par `LandmarkModels` (modélisateur). |
| Captures | `tests/audit/p1_shots.gd` : C1 cabine en station couverte (station enterrée de la trémie L3, Nantes), C2 rame à l'arrêt à Ralliement avec la cathédrale en fond (point de vue surélevé : la place masque la nef à hauteur d'homme), C3 cabine au portail de la trémie, C0 approche de Ralliement ; option `mobile`. `tests/audit/p1_planche.py` : planche référence/TramSim et planche **à l'aveugle** (A/B aléatoires + clé séparée). Grille : `docs/refonte-visuelle/notation_P1.md` (à remplir par le joueur). Captures hors dépôt (scratchpad `p1/`). |
| Taille | `assets/textures` + `assets/lightmaps` : **≈ 72 Mo** ajoutés (2K : 57 Mo, 1K : 15 Mo) ; `.godot/imported` ≈ +330 Mo (non versionné). |

**Tests verts** (Compatibility forcé) : test_pbr_materials (étendu : couches, profils, licences), test_quality_profiles, test_render_budgets (2 passes), test_scene_data, test_world_geometry, test_map_surfaces, test_rails_visible, test_track_hd (nouveau), test_landmark_models, test_home, test_explore, test_mobile, clearance Angers et Nantes.

**Limites** : pas de GPU ici (Forward+ en lavapipe, Mobile simulé en Compatibility : perf réelle et ETC2/ASTC à mesurer sur appareil) ; lightmaps non cuites ; géométrie des bâtiments génériques encore à facettes (le texturage ne remplace pas la grammaire de façades, P3) ; pas d'imposteurs pour les bâtiments lointains (le budget Mobile tient sans) ; cabine non modélisée (P2) : l'axe « cabine » de la notation restera bas.

**Avis porte go/no-go moteur** : **GO Godot** pour poursuivre. Les briques à risque de P1 tiennent dans Godot 4.6 : PBR texturé en tableaux compressés identique dans les trois renderers, LOD/HLOD par portées de visibilité, budget Mobile tenu avec ~40 % de marge en triangles et ~50 % en draw calls au point le plus dense. Réserves à lever avant P2 : (1) cuisson LightmapGI sur GPU (CI ou poste) et mesure sur un Android de référence ; (2) shader baker en export. L'écart restant avec les références (éclairage global, cabine, végétation en cartes, façades) relève du contenu (P2/P3), pas du moteur.

---

## 11. État P2 (23/11/2026) — lot ingénieur « Rames HD »

| Point | Réalisation |
|---|---|
| Contrat modélisateur | `docs/refonte-visuelle/stock_manifest.md` (schéma v1) : `assets/models/rolling_stock/manifest.json`, un dossier par variante (clé = `variant_id` de la livrée), `lod0..3.glb` + `cab.glb` (+ `*_m.glb` Mobile), repère du rig (Y haut, 0 = rail, -Z = cabine A), nœuds `module_XX`, `door_<n>_<L\|R>_a/b`, `panto_*`, `wiper_*`, `mirror_*`, `em_*`, `sign_dest_*`, `cab_proxy_*`, cabine `cam_driver`, `ctl_*`, `screen_*`, `em_lamp_*` ; matériaux `paint_<zone>`/`livery*` (clearcoat) et `glass*`. |
| Intégration | `src/rendering/stock_hd.gd` : chargement paresseux par variante (glb importé, ou lu à l'exécution pour les tests), validation complète avant usage (caisses ±2 cm, portes par côté, nœuds requis, budgets §5.2 lus dans `budgets.json`) et **repli** sur le modèle actuel (procédural / CitadisMeshy) sinon ; `TramModel.build_rig` applique l'habillage HD, le rig reste l'autorité (états, longueurs). Désactivable : `TRAMSIM_STOCK_HD=0` ; manifeste alternatif : `TRAMSIM_STOCK_MANIFEST`. |
| LOD | Bascule par distance caméra 25 / 80 / 250 m avec hystérésis 10 %, LOD0 en vue cabine ; Mobile : fichiers `mobile_file` sinon un cran plus bas quand un LOD dépasse le budget Mobile, **rames IA un cran plus bas, 3 rames au plus en LOD0** (`AiTramView`) ; ombres coupées dès LOD2. |
| Matériaux, feux | Livrée en **clearcoat**, vitrages PBR réfléchissants (ReflectionProbe existante des profils PC, intérieur visible) ; phares (extrémité active, pleins feux la nuit/tunnel ou touche H), feux arrière, plafonniers nuit/tunnel, **girouette = terminus de la mission** (Label3D sur l'ancre `sign_dest_*`). |
| Animations | Portes (côté quai réel, louvoiement puis coulissement du plan), pantographe (montée/baisse selon `pantograph_up` : LAC/APS), **essuie-glace** (pluie de `WeatherState` > 0,15 ou touche E, retour en butée), rétroviseurs (N), manipulateur au **cran réel**. |
| Cabine | `src/rendering/cab_view.gd` : caméra au point `cam_driver` du modèle (pare-brise et pupitre visibles), chaque `ctl_*` lié à `src/input/cab_actions.gd` (11 actions : manipulateur, urgence, portes, gong, pantographe/alimentation, inverseur, sablage, phares, essuie-glace, rétroviseurs, pilote auto ; alias et nœuds supplémentaires du modélisateur) ; mouvement visuel quand l'action vient du clavier, du HUD ou d'un **clic/toucher** (lancer de rayon sur l'AABB de chaque commande ; manipulateur : moitié haute = traction, basse = freinage) ; voyants `em_lamp_*` ; écrans `screen_*` en **SubViewport** (`cab_screens.gd` : vitesse/limite, cran, prochain arrêt + distance, signal, info), rendus à la demande (5 Hz). **HUD minimal** en cabine (touche I, réglage `cab_hud_min`). Nouvelles touches : B sablage, H phares, E essuie-glace, N rétroviseurs, I HUD. |
| Tests | `tests/test_stock_hd.gd` (dans `run_all.sh`) : manifeste réel validé variante par variante, plus un **modèle de test minimal** conforme (`tests/fixtures/stock_hd_fixture.gd`, écrit en `user://`) : nœuds `ctl_*` pour chaque action, budgets, repli, bascule LOD, portes côté quai, pantographe, essuie-glace, rétroviseurs, émissifs, girouette, cabine (11/11 commandes visibles et cliquables), écrans, voyants, clearcoat/verre, puis jeu complet (vue cabine HD, touche H, clic sur `ctl_doors` → portes, HUD minimal). `test_render_budgets` : nouveau cadrage `dense_ia` (4 rames IA HD visibles devant la rame du joueur) dans les deux passes. `tests/audit/p1_shots.gd` : option `x05` (C1/C3 en cabine X05 Nantes, C2 X05 Angers). |

### Reprise de l'intégration P2 (Codex, 23/11/2026)

Suite au point de sauvegarde `caf73cb`, corrections et mesures reproductibles dans
[le rapport P2](refonte-visuelle/p2/README.md) : choix des vrais modèles mobiles dès la construction,
validation des deux profils hors jeu, purge des gabarits, import GPU/mipmaps, pupitres mobiles 1024 px,
stationnement de l'essuie-glace, écrans et signature lumineuse Naolib. Captures produites par le runtime
et contrôles de rendu automatisés ; les critères de validation humaine et sur appareils réels du §7
restent requis. Les lots P3/P4 et les autres matériels du §5.3 ne sont pas déclarés terminés.

---

## 12. État P3 — végétation/mobilier/caténaire (26/11/2026, agent dédié)

| Point | Réalisation |
|---|---|
| Végétation | `src/rendering/vegetation.gd` + `shaders/vegetation.gdshader`, essences dans `data/vegetation_species.json` (11 : tilleul, **marronnier** (une instance sur deux du type 0), platane à écorce desquamée, érable, peuplier, conifère, pin parasol, palmier ; massifs, graminées, vivaces). Positions, hauteurs (LiDAR) et houppiers (rayon = `CROWN_R`) inchangés. LOD0 : tronc conique, charpentières et rameaux en tubes, **cartes de rameaux alpha** (atlas 4×2 `assets/textures/vegetation/foliage_{2k,1k}.png` composé de feuilles scannées **CC0 ambientCG** LeafSet024/027/019/009 + palmes/graminées générées, `tools/models/props/build_vegetation_textures.py`), normales sphériques, translucidité (BACKLIGHT), vent (balancement ∝ h² + frémissement), variation de teinte et de saison (`season`) par instance, appoint nocturne (`night_fill`, évite le noir pur). LOD1 : **imposteur** (quad tourné vers la caméra, silhouette pré-calculée par essence `impostors_{1k,512}.png`) ; bascule **par instance** dans le shader à la distance de la caméra principale (`MAIN_CAM_INV_VIEW_MATRIX`, cohérente dans les passes d'ombre) : 164 m PC / 60 m Mobile, cellules de 70 m bornées à 230 / 110 m. Triangles par arbre : 136 (palmier) à 786 (platane). Touffes d'herbe instanciées sur les pelouses : jusqu'à 700 par tuile en Forward+, 128 en Mobile/Compatibility (la pelouse reste la texture). |
| Mobilier | `street_props.gd` : modèles détaillés pour tout le mobilier (candélabres de rue, à crosse et de style à lanterne vitrée, feux R11 à visières + panneau de contraste + feu piéton R12 + boîtier d'appel, panneaux à liseré, potelets en fonte tournés, bancs à lattes, corbeilles « Vigipirate », arceaux en U, totems, voitures à profil galbé, jantes, rétroviseurs, plaques) + 2 nouveaux : **MUPI** (affiches rétroéclairées génériques, sans marque) et **barrières** croix de Saint-André aux carrefours à feux. LOD par cellule : détaillé < 75 m (Mobile 40 m), simple au-delà, portées complémentaires mesurées au même centre : **aucun draw call supplémentaire**. Métal peint texturé (id 15). |
| Caténaire | `electrification_view.gd` : poteaux tubulaires coniques (treillis pour Saint-Étienne, Lille, Marseille) avec platine et massif, consoles à deux tubes + contrefiche, **isolateurs** à ailettes, bras de rappel, fil de contact en **zigzag ±20 cm**, **porteur en chaînette** (6,05 m aux supports, flèche 25 cm), **pendules** tous les 5 m, haubans d'ancrage en fin de canton, suspension transversale (porteur + pendule) aux appareils de voie. Fils : `shaders/wire.gdshader`, rubans tournés vers la caméra, **largeur d'écran ≥ 1,15 px** et opacité proportionnelle au-delà (plus de pointillés au loin). LOD : isolateurs, rappels, pendules et haubans < 140 m (Mobile 70 m). Positions des poteaux inchangées (gabarit). |
| Decals | `road_decals.gd` : plaques d'égout (albédo + normale), salissures en pied de bordure, taches d'huile sous les voitures, rapiéçages/marquages usés ; Forward+ et Mobile (fondu 70 / 35 m, moitié moins en Mobile), **aucun en Compatibility** ; jamais sur la plateforme. Fiche `data/materials/decals_voirie.json`. |
| Tests | Nouveau `tests/test_p3_props.gd` (dans `run_all.sh`). `test_world_geometry` adapté (fils = maillages `Wires`). Verts : test_render_budgets (2 passes, Mobile bloquant), test_pbr_materials, test_scene_data, test_world_geometry, clearance Angers et Nantes, test_rails_visible, test_home, test_explore, test_mobile. |
| Mesures (Compatibility, 1280×720) | St-Serge (test_render_budgets) : PC 3ᵉ pers. 1 211 draws / 1,04 M tris, cabine 549 / 0,89 M, nuit 1 240 / 1,11 M (noir pur 1,46 %) ; **Mobile** 3ᵉ pers. 408 / 615 k, IA 466 / 623 k, cabine 389 / 610 k, nuit 478 / 710 k (noir 0,34 %) : dans le budget Mobile (600 / 800 k), marge ≈ 11 % en triangles. Cadrages P3 (Compatibility) : Angers cabine 628 draws / 1,02 M tris (avant 514 / 0,62 M), Nantes cabine 251 / 0,74 M (avant 194 / 0,46 M) ; Forward+ (lavapipe, decals actifs) Angers cabine 692 / 1,07 M. Planches avant/après (cabine, rue, oblique) Angers Foch-Maison Bleue et Nantes Duchesse Anne : `tests/audit/p3_shots.gd` (hors dépôt, scratchpad `p3v/`). |
| Taille | `assets/textures/vegetation` : **3,2 Mo**. |

**Limites** : abris de station par réseau non refaits (`station_layout.gd`, hors périmètre de ce lot) ; feux R17/R24 tramway relèvent de `signal_view.gd` (non modifiés) ; écorce procédurale (la couche Poly Haven `lm_ecorce` n'est pas échantillonnée par le shader de végétation) ; imposteurs à une seule vue (pas octaédriques : aplatis vus de haut) ; suspensions transversales entre façades non générées (seulement aux appareils de voie) ; pas de GPU ici : Forward+ vérifié en rendu logiciel (lavapipe), coût des cartes alpha (sur-dessin) et des decals à mesurer sur appareil ; touffes d'herbe de la plateforme gazonnée non traitées (`track_view.gd`).

---

## 12. État P3 — façades/monuments (26/11/2026)

| Point | Réalisation |
|---|---|
| Grammaire de façades | `src/rendering/facades.gd` (`Facades`) appelée par `CityScene._building`. Sept styles : **anjou** (tuffeau, ardoise à forte pente, lucarnes à fronton, chaînes d'angle harpées, souches en tuffeau), **nantes_xviii** (île Feydeau, quai de la Fosse, Graslin, Bouffay : tuffeau, agrafes, balconnets en fer forgé de l'étage noble sur consoles, comble brisé d'ardoise), **haussmann** (pierre, balcons filants aux 2e et 5e étages, corniche, brisis en zinc à lucarnes, souches de brique), **moderne** (nez de dalle, balcons une travée sur trois à garde-corps vitrés ou métalliques, acrotère), **pavillon**, **activite** (bardage nervuré, bandeau vitré, portes sectionnelles), **generic** (rendu d'avant P3). Choix du style : quartiers de `data/facade_styles.json` (cercles WGS84 : 5 à Angers, 7 à Nantes), puis usage (classe BD TOPO), hauteur LiDAR, emprise et appareil régional ; l'appareil imposé par le style est stable par graine. Nuance de teinte propre à chaque bâtiment. Faîtages en zinc. |
| Relief | Calé exactement sur la trame des baies du shader (`Facades.bays` = bloc M_FACADE de `pbr_world.gdshader` : travée, hauteur d'étage, proportions par appareil ; vitrines : cellules de 4,2 m). Encadrements saillants de 8 à 15 cm avec embrasure, appuis, clés, garde-corps, balcons, cordons, corniches moulurées à trois ressauts, chaînes d'angle. Rez-de-chaussée commerciaux : piliers, menuiseries sombres, enseignes génériques en relief (sans marque), stores bannes, corniche de devanture. Seules les **faces sur rue** reçoivent du relief (voie ou plateforme du tram à moins de 22 m devant la face), et seulement pour les bâtiments à moins de 80 m d'une voie du réseau. Au plus 4 faces et 10 travées par face. |
| Toitures | Combles brisés (`_mansard`) à lucarnes à fronton alignées sur les travées ; lucarnes angevines à fronton (`_dormers(..., pediment)`) ; souches de cheminée sur pignons et terrassons ; toitures d'ardoise texturées (couche P1). |
| LOD | Relief dans des maillages **par cellule de 48 m** (`facade_relief_x_z`, portée mesurée au centre de la cellule) : **150 m PC, 45 m Mobile sans ombre**, et barreaux de garde-corps espacés en Mobile. De 150 à 190 m : détails `_D` existants (soubassements, lucarnes). Au-delà : baies peintes par le shader avec estompage lointain (`far_col`), puis proxy aérien `AerialCityLOD`. Aucun imposteur nouveau : le budget tient sans. Bascule A/B : `TRAMSIM_FACADES=0`. |
| Monuments | `tools/models/build_monuments.py` (appelé seul ; fusionne dans `landmark_models.json`, `"lot": "P3"`), 10 modèles en glTF LOD0-2. **Angers** : château (enceinte BD TOPO à tours rondes rayées de schiste et de tuffeau, glacis, chemin de ronde, merlons, tour du Moulin à poivrière), gare Saint-Laud (pavillon à comble et horloge, ailes à arcades, marquise), hôtel de ville (emprises « Mairie d'Angers » BD TOPO, combles brisés, avant-corps à fronton, horloge, campanile). **Nantes** : château des ducs (courtines et tours à mâchicoulis en tuffeau sur granit, châtelet d'entrée à poivrières face au pont dormant ; tracé à 13 m de la contrescarpe BD TOPO, constructions linéaires, et tenu à 13 m de la ligne 1), cathédrale (tours de 63 m à contreforts et pinacles, nef de 38 m sous ardoise, bas-côtés, arcs-boutants, portails, vitraux), tour Bretagne (sur l'emprise BD TOPO de 109 m : **landmarks.json est décalé de 70 m**), mezzanine de la gare, tour LU (dôme doré), façade du passage Pommeraye et sa verrière, Grand Éléphant (silhouette). Les emprises génériques recouvertes sont remplacées (`replace`), et des obstacles caméra sont ajoutés. Bascule A/B : `TRAMSIM_P3_MONUMENTS=0`. |
| Tests | `tests/test_facades.gd` (dans `run_all.sh`) : miroir de la trame du shader, styles attendus par quartier (Angers centre, Feydeau, centre de Nantes) et hors quartier, cellules de LOD, portées PC et Mobile, ombres Mobile, borne de triangles. `test_landmark_models` : réseau par défaut par ville pour les monuments P3 (gabarit libre vérifié). Captures : `tests/audit/p3f_shots.gd` (cabine, rue, oblique 150 m, aérienne ; monuments ; options `mobile`, `sites`, `monuments`, `only=`). |
| Budgets (Compatibility, 1280×720, St-Serge, avec la végétation et le mobilier P3) | PC : dense_ext 1 211 draws / 1,06 M triangles, nuit 1 240 / 1,13 M (budget haut : 2 000 / 3 M). **Mobile : ext 407 / 616 k, cabine 387 / 602 k, nuit 477 / 713 k** (budget 600 / 800 k) : vert. |
| Taille | Monuments P3 : 5,9 Mo de glb. Données : `data/facade_styles.json` (2 Ko). Pas de nouvelle texture : le zinc reprend la couche ardoise teintée ; des textures zinc et granit dédiées restent souhaitables. |

**Limites** : pas de date de construction dans les données de scène (époque déduite de la hauteur, de l'emprise et du quartier). Le relief reste en saillie, sans percement des murs : les baies restent peintes et l'embrasure est simulée par le chambranle. Monuments procéduraux simplifiés, plus de 10 fois plus légers que Saint-Maurice P1 (cathédrale et tour LU surtout volumétriques ; pas de jardins dans les douves d'Angers, car le relief IGN lisse le fossé ; Grand Logis de Nantes : bâti BD TOPO générique). Implantation du passage Pommeraye et de l'éléphant d'après des points WGS84, sans emprise dédiée. Mesures en lavapipe/llvmpipe uniquement. La brume des vues aériennes relève de `day_night.gd` (densité de jour) : signalée, non modifiée.
