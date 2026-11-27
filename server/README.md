# Serveur de données Tram Sim France

Caddy (Docker) sert en HTTPS, avec un certificat Let's Encrypt automatique, les packs de ville et une API JSON
statique. Architecture, secrets GitHub et coûts : [docs/SERVEUR_DONNEES.md](../docs/SERVEUR_DONNEES.md).

| Route | Contenu | Cache |
|---|---|---|
| `GET /api/v1/health` | état : version de données, formats, versions conservées, disque | `no-cache` |
| `GET /api/v1/manifest` | dernier manifeste publié | `no-cache` |
| `GET /api/v1/formats/<n>/manifest.json` | dernier manifeste du format de données `n` (celui que lit l'appli) | `no-cache` |
| `GET /api/v1/versions/<version>.json` | manifeste d'une version conservée | `no-cache` |
| `GET /packs/<version>/<fichier>.pck` | pack (requêtes `Range` pour la reprise) | 1 an, `immutable` |

Le JSON est compressé (zstd/gzip). Les `.pck` ne le sont pas, pour que les requêtes `Range` restent exactes.

## Installation (Debian 12 / Ubuntu 22.04+)

1. **DNS** : créez un enregistrement `A` (et `AAAA` si le serveur a une IPv6) pour le domaine choisi, par exemple
   `donnees.exemple.org`, vers l'adresse du VPS. Let's Encrypt a besoin de ce DNS et du port 80.
2. **Docker** (dépôt officiel) :
   ```sh
   sudo apt-get update && sudo apt-get install -y ca-certificates curl rsync
   sudo install -m 0755 -d /etc/apt/keyrings
   . /etc/os-release
   sudo curl -fsSL https://download.docker.com/linux/$ID/gpg -o /etc/apt/keyrings/docker.asc
   echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID $VERSION_CODENAME stable" \
     | sudo tee /etc/apt/sources.list.d/docker.list
   sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
   ```
3. **Pare-feu** : SSH, 80 (certificat, redirection) et 443 (TCP, et UDP pour HTTP/3).
   ```sh
   sudo apt-get install -y ufw
   sudo ufw allow OpenSSH        # ou le port SSH choisi (secret VPS_PORT)
   sudo ufw allow 80/tcp && sudo ufw allow 443/tcp && sudo ufw allow 443/udp
   sudo ufw enable
   ```
   Si l'hébergeur a son propre pare-feu (panneau web), ouvrez-y les mêmes ports.
4. **Utilisateur de déploiement** (utilisé par GitHub Actions, clé SSH sans mot de passe dédiée) :
   ```sh
   sudo adduser --disabled-password --gecos "" tramsim
   sudo usermod -aG docker tramsim
   sudo install -d -o tramsim -g tramsim /srv/tramsim-data
   # sur votre poste : ssh-keygen -t ed25519 -f tramsim_deploy -N "" -C deploy-tramsim
   sudo -u tramsim sh -c 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys' < tramsim_deploy.pub
   ```
   La clé privée `tramsim_deploy` devient le secret GitHub `VPS_SSH_KEY`. Le groupe `docker` équivaut à un accès
   root : réservez ce compte au déploiement.
5. **Premier déploiement** : créez les secrets et la variable GitHub (voir la doc), puis lancez le workflow
   *deploy-data* (Actions → deploy-data → Run workflow, source `release`). Il copie ce dossier dans
   `/srv/tramsim-data/server`, publie les packs, écrit `.env` et lance `docker compose up -d`.

### Démarrage à la main (sans GitHub Actions)

```sh
cd /srv/tramsim-data/server            # copie de ce dossier
cp .env.example .env && nano .env      # DATA_DOMAIN, DATA_ROOT
# packs et manifest.json d'une release : gh release download <tag> -p 'tramsim-*.pck' -p manifest.json -D /tmp/v
DATA_ROOT=/srv/tramsim-data KEEP_VERSIONS=3 sh scripts/publish.sh /tmp/v
docker compose up -d
curl https://$DATA_DOMAIN/api/v1/health
```

## Exploitation

- **Rétention** : `scripts/publish.sh` garde les `KEEP_VERSIONS` versions les plus récentes (3 par défaut, entrée du
  workflow ou variable de dépôt `DATA_KEEP_VERSIONS`) et toute version encore annoncée par un format. Les packs
  inchangés d'une version à l'autre sont des liens durs (rsync `--link-dest`) : ils n'occupent la place qu'une fois.
- **Journaux** : `docker compose logs -f caddy` (rotation 5 × 20 Mo).
- **Mise à jour de Caddy** : changer l'image dans `docker-compose.yml`, puis `docker compose pull && docker compose up -d`.
- **Certificats** : volume `caddy_data` ; ne pas le supprimer (limites de Let's Encrypt).
- **Retour arrière** : republier une version conservée :
  `cp www/api/v1/versions/<v>.json www/api/v1/formats/<n>/manifest.json` (et `www/api/v1/manifest.json`).
