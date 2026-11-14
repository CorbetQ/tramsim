#!/usr/bin/env bash
# Vues aériennes verticales par ville (globale + communes/quartiers) et comparaison orthophoto IGN.
# Usage : TERRAIN_CACHE=<cache> tests/audit/run_aerial.sh <godot> <dossier> [villes...]  (identifiants : angers, idf…)
set -u
GODOT="$1"; OUT="$2"; shift 2
cd "$(dirname "$0")/../.."
CITIES="${*:-$(ls data/free/*.json | xargs -n1 basename | sed 's/\.json$//')}"
for c in $CITIES; do
  d=$(python3 tests/audit/aerial_views.py prepare "$c" "$OUT" | sed -n 's/.*-> //p')
  [ -n "$d" ] || { echo "$c : préparation impossible"; continue; }
  timeout 5400 xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" --path . --rendering-driver opengl3 \
    -s tests/audit/aerial_shots.gd -- "$d/views.json" 2>&1 | grep -E '^AERIAL|ERROR' | head -100 > "$d/rendu.log"
  python3 tests/audit/aerial_views.py compose "$c" "$OUT"
  echo "$c : $(ls "$d"/*.png 2>/dev/null | wc -l) images"
done
