#!/bin/sh
# Publie une version de données envoyée par deploy-data.yml (ou à la main) et applique la rétention.
# Usage : DATA_ROOT=/srv/tramsim-data KEEP_VERSIONS=3 sh scripts/publish.sh <dossier contenant manifest.json et *.pck>
# Résultat (servi par Caddy) :
#   www/packs/<version>/tramsim-*.pck        packs immuables (liens durs vers la version précédente si inchangés)
#   www/api/v1/formats/<format>/manifest.json  dernière version de chaque format de données (appli compatible)
#   www/api/v1/manifest.json                  dernière version publiée ; www/api/v1/versions/<version>.json
#   www/api/v1/health.json                    état (version, formats, versions conservées)
# Rétention : KEEP_VERSIONS versions les plus récentes, plus toute version encore servie par un format.
set -eu
SRC=${1:?dossier de la version à publier}
ROOT=${DATA_ROOT:-/srv/tramsim-data}
KEEP=${KEEP_VERSIONS:-3}
WWW=$ROOT/www
[ -f "$SRC/manifest.json" ] || { echo "manifest.json absent de $SRC" >&2; exit 1; }
VER=$(sed -n 's/^ *"data_version": *"\([^"]*\)".*/\1/p' "$SRC/manifest.json" | head -1)
FMT=$(sed -n 's/^ *"format": *\([0-9][0-9]*\).*/\1/p' "$SRC/manifest.json" | head -1)
case "$VER" in ''|*[!0-9A-Za-z._-]*) echo "data_version invalide : '$VER'" >&2; exit 1;; esac
case "$FMT" in ''|*[!0-9]*) echo "format invalide : '$FMT'" >&2; exit 1;; esac
for f in "$SRC"/*.pck; do [ -f "$f" ] || { echo "aucun pack dans $SRC" >&2; exit 1; }; break; done
mkdir -p "$WWW/packs" "$WWW/api/v1/formats/$FMT" "$WWW/api/v1/versions"
# 1. packs : remplacement atomique du dossier de version
rm -rf "$WWW/packs/.$VER.new"
mv "$SRC" "$WWW/packs/.$VER.new"
rm -rf "$WWW/packs/$VER"
mv "$WWW/packs/.$VER.new" "$WWW/packs/$VER"
touch "$WWW/packs/$VER"
chmod -R a+rX "$WWW/packs/$VER"
# 2. manifestes (écriture puis renommage : jamais de fichier à moitié écrit)
put() { cp "$1" "$2.tmp" && chmod a+r "$2.tmp" && mv "$2.tmp" "$2"; }
put "$WWW/packs/$VER/manifest.json" "$WWW/api/v1/versions/$VER.json"
put "$WWW/packs/$VER/manifest.json" "$WWW/api/v1/formats/$FMT/manifest.json"
put "$WWW/packs/$VER/manifest.json" "$WWW/api/v1/manifest.json"
# 3. rétention
live=$(for m in "$WWW"/api/v1/formats/*/manifest.json; do sed -n 's/^ *"data_version": *"\([^"]*\)".*/\1/p' "$m" | head -1; done)
n=0
for v in $(ls -1t "$WWW/packs"); do
	case "$v" in .*) continue;; esac
	n=$((n + 1))
	if [ "$n" -le "$KEEP" ] || echo "$live" | grep -qx "$v"; then continue; fi
	echo "rétention : suppression de la version $v"
	rm -rf "$WWW/packs/$v" "$WWW/api/v1/versions/$v.json"
done
# 4. santé
versions=$(ls -1t "$WWW/packs" | grep -v '^\.' | sed 's/.*/"&"/' | paste -sd, -)
formats=$(ls -1 "$WWW/api/v1/formats" | sed 's/.*/&/' | paste -sd, -)
bytes=$(du -sb "$WWW/packs" 2>/dev/null | cut -f1 || echo 0)
cat > "$WWW/api/v1/health.json.tmp" <<JSON
{"status": "ok", "data_version": "$VER", "format": $FMT, "formats": [$formats], "versions": [$versions], "disk_bytes": ${bytes:-0}, "published": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
JSON
chmod a+r "$WWW/api/v1/health.json.tmp" && mv "$WWW/api/v1/health.json.tmp" "$WWW/api/v1/health.json"
echo "publié : données $VER (format $FMT), versions conservées : $versions"
