# Serveur de données : villes téléchargeables

Les exports (APK Android, EXE/MSI Windows) ne contiennent plus aucune donnée de ville. Les 28 villes (Angers et
Nantes comprises) se téléchargent depuis le jeu, à partir d'un serveur HTTPS hébergé sur un VPS, avec repli sur les
assets de la release GitHub du build.

## Architecture

```
GitHub Actions (release.yml)                         VPS (server/, Docker)
  import Godot → build_packs.gd (mobile + pc)          Caddy :443 (Let's Encrypt sur DATA_DOMAIN)
  packs.py manifest → manifest.json (sha256)    ─┐       /api/v1/health, /api/v1/manifest
  release : APK, EXE/MSI (+ packs en repli)      │       /api/v1/formats/<n>/manifest.json
deploy-data.yml (après release / manuel)        │       /packs/<version>/tramsim-*.pck (Range, immutable)
  rsync --link-dest ─────────────────────────────┴──►  /srv/tramsim-data/www  (scripts/publish.sh, rétention)

Jeu : CityPacks (état, montage) + PackDownloader (réseau) ─► user://packs/*.pck → ProjectSettings.load_resource_pack
```

### Contenu des packs (`data/packs/plan.json`)

| Pack | Contenu | Mobile | PC |
|---|---|---|---|
| `tramsim-city-<ville>-<plateforme>.pck` (×28) | scène, terrain, décor, monuments (`assets/models/<ville>`), lightmaps, réseau libre, rames HD et livrées utilisées par cette seule ville | 5,4 à 94,8 Mo (médiane 15,9) | 11,4 à 165,3 Mo (médiane 27,3) |
| `tramsim-commun-rames-…` | kits et livrées partagés par plusieurs villes, `assets/models/rolling_stock` | 51,3 Mo | 98,9 Mo |
| `tramsim-commun-decor-…` | textures PBR, végétation, modèles partagés | 42,0 Mo | 186,0 Mo |
| **Total** | 30 packs | **682 Mo** | **1 333 Mo** |

Mobile : textures etc2/astc, sans LOD0, cabines PC, livrées 4k ni PBR 2048². PC : s3tc/bptc, tout.
Chaque ville dépend des deux packs communs (`requires` du manifeste), téléchargés une seule fois.
`python3 tools/packs/packs.py stock` répartit les fichiers de rames (une ville → son pack, sinon commun) ;
`build_packs.gd` refuse de construire si un fichier exclu des exports n'appartient à aucun pack.

### Ce qui reste dans l'appli

Moteur, scripts, UI, polices et icônes, catalogue (`data/index.json`, `data/networks`, missions, stations), fiches
et vignettes des rames (`data/rolling_stock`), sons essentiels (`data/audio`). L'accueil (fond dégradé à la place de
la vue aérienne) et le choix de ville fonctionnent avant tout téléchargement : la ville choisie affiche un panneau
non bloquant « Télécharger la ville ».

| | Avant | Après (mesuré / estimé) |
|---|---|---|
| APK Android (arm64) | 181 Mo | ≈ 47 Mo (moteur ≈ 31 Mo compressé + données 16,0 Mo mesurées par `--export-pack`) |
| PCK Windows | ≈ 800 Mo | 32,1 Mo mesurés |
| Dossier EXE Windows (moteur 101–105 Mo + PCK) | ≈ 900 Mo | ≈ 135 Mo ; ZIP/MSI ≈ 60 Mo |

Estimation hors build : `python3 tools/packs/packs.py apk Android --zip`.

## Versions et compatibilité

- **Version de données** (`data_version`, ex. `20261127.119`) : indépendante de la version de l'appli. Chaque
  build en produit une ; un pack au contenu inchangé garde le même sha256 (le manifeste interne d'un pack ne contient
  ni version de jeu ni version de données), donc le joueur ne retélécharge que ce qui a changé.
- **Format de données** (`format`, `CityPacks.DATA_FORMAT`, `data/packs/plan.json`) : à incrémenter quand une
  appli ne peut plus lire les packs précédents (chemins, scripts, ressources). L'appli lit
  `/api/v1/formats/<son format>/manifest.json` : une ancienne appli continue de recevoir la dernière version de son
  format tant qu'elle est conservée sur le serveur. Le manifeste indique aussi `engine` (Godot `4.6`) : un manifeste
  d'un autre moteur ou d'un autre format est refusé avec un message.

### Manifeste

```json
{"schema": 1, "format": 1, "engine": "4.6", "data_version": "20261127.119", "app_version": "0.13.2",
 "release_tag": "v0.13.2-build.119", "generated": "…", "totals": {"mobile": 715689564, "pc": 1397460464},
 "platforms": {"mobile": {"lyon": {"kind": "city", "label": "Lyon", "file": "tramsim-city-lyon-mobile.pck",
   "size": 47406132, "sha256": "a8da…", "url": "/packs/20261127.119/tramsim-city-lyon-mobile.pck",
   "requires": ["commun-rames", "commun-decor"]}, "commun-rames": {"kind": "common", "requires": [], …}}, "pc": {…}}}
```

## Client (jeu)

- `src/catalogue/city_packs.gd` : URL de base (réglage avancé `user://packs/settings.cfg`, sinon
  `tramsim/data/base_url` écrit au build depuis `DATA_DOMAIN`), sources (serveur puis release `tramsim/release/repo`
  + `tramsim/release/tag`), état local `user://packs/installed.json`, manifeste en cache, montage avec dépendances,
  suppression, nettoyage des fichiers orphelins au démarrage, espace libre.
- `src/catalogue/pack_downloader.gd` : fil réseau `HTTPClient` ; reprise par `Range` sur `<pack>.part` (après
  annulation ou coupure : 3 nouvelles tentatives automatiques), redirections (release GitHub), sha256 incrémental (pack
  rejeté et `.part` supprimé si différent), contrôle de l'espace libre, installation sous un nom suffixé par
  l'empreinte (jamais d'écrasement d'un pack monté), repli sur la release si le serveur ne répond pas.
- `src/catalogue/city_preload.gd` + `src/ui/main.gd` : panneau de téléchargement (taille, progression, Mo/s, temps
  restant, Annuler, Mettre à jour / Jouer avec la version installée, Choisir une autre ville). Réglages → « Données
  des villes » : liste, taille, version, mise à jour disponible, Supprimer, serveur de données, Vérifier les mises à jour.
- **Hors ligne** : les packs installés sont montés sans réseau ; seule une ville jamais téléchargée est indisponible.
- Un dossier `packs/` à côté de l'exécutable (copie manuelle des `.pck`) est aussi lu.
- En développement (arborescence source, `data/packs/plan.json` présent), tout est local : aucun accès réseau.
- `TRAMSIM_PACK_DOWNLOAD=0` désactive le réseau ; `TRAMSIM_PACK_PLATFORM=mobile|pc` force la plateforme.

## Déploiement

### À fournir dans GitHub (Settings → Secrets and variables → Actions)

| Nom | Type | Valeur |
|---|---|---|
| `VPS_HOST` | secret | adresse IP ou nom du VPS |
| `VPS_USER` | secret | utilisateur de déploiement (ex. `tramsim`, membre du groupe `docker`) |
| `VPS_SSH_KEY` | secret | clé privée SSH (ed25519, sans mot de passe) dont la clé publique est dans `authorized_keys` |
| `VPS_PORT` | secret, facultatif | port SSH (22 par défaut) |
| `DATA_DOMAIN` | variable | domaine HTTPS pointant vers le VPS, ex. `donnees.exemple.org` (embarqué dans l'appli au build) |
| `DATA_ROOT` | variable, facultative | dossier sur le VPS (`/srv/tramsim-data`) |
| `DATA_KEEP_VERSIONS` | variable, facultative | versions conservées (3) |
| `RELEASE_DATA_FALLBACK` | variable, facultative | `false` : ne plus joindre les packs à la release |

Installation du VPS : [server/README.md](../server/README.md) (Docker, pare-feu 80/443, utilisateur, DNS).

### Workflows

- `release.yml` : exporte APK et EXE/MSI sans données, construit les 60 packs (28 villes + 2 communs, ×2
  plateformes) et `manifest.json`, les publie en artefact `TramSimFrance-data-packs` et, en repli, en assets de la
  release. **Choix** : les packs restent joints à la release (désactivable) pour que le jeu fonctionne avant la
  configuration du serveur, quand le VPS est en panne, et pour qu'un build reste autonome ; le stockage des releases
  GitHub est gratuit. Sans `DATA_DOMAIN`, l'appli n'a que ce repli et la release fonctionne comme avant.
- `deploy-data.yml` : après une release réussie (hors pull request) ou à la main (packs d'une release existante, ou
  reconstruits depuis les sources). Sans les secrets ou sans `DATA_DOMAIN`, un job de contrôle affiche une notice
  et rien n'est déployé (aucun échec). Sinon : contrôle sha256/tailles, `rsync --link-dest` vers
  `incoming/<version>`, `scripts/publish.sh` (bascule atomique des manifestes, rétention, `health.json`),
  `docker compose up -d`, puis vérification `health`, manifeste du format et requête `Range` (HTTP 206).

### Rotation des versions

`publish.sh` garde les `KEEP_VERSIONS` dernières versions et toute version encore annoncée par
`/api/v1/formats/<n>/manifest.json` (anciennes applis). Les manifestes de chaque version restent sous
`/api/v1/versions/`. Retour arrière : recopier l'un d'eux sur le manifeste du format.

## Coûts estimés

**Disque** : une version complète = 0,7 Go (mobile) + 1,3 Go (pc) = 2,0 Go. Grâce aux liens durs, une version
suivante n'ajoute que les packs modifiés (souvent les 2 communs et quelques villes : 0,3 à 0,6 Go). Avec 3 versions :
2,6 à 6 Go ; prévoir 10 Go libres. Certificats et journaux : négligeables.

**Bande passante** (sortante) : un joueur mobile qui télécharge une ville moyenne = communs 93 Mo + ville 21 Mo
≈ 115 Mo ; toutes les villes : 683 Mo. PC : 285 Mo + 37 Mo ≈ 320 Mo ; tout : 1,33 Go. Une mise à jour ne transfère
que les packs modifiés. Ordre de grandeur : 1 000 joueurs mobiles × 2 villes ≈ 135 Go/mois ; 1 000 joueurs PC × 2
villes ≈ 360 Go/mois, ce qui tient dans le trafic inclus de la plupart des VPS (1 à 20 To/mois). Envoi depuis GitHub
Actions : jusqu'à 2 Go par déploiement (seulement les différences quand rsync trouve la version précédente).
