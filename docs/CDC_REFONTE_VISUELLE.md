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
