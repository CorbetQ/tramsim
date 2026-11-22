#!/usr/bin/env bash
# Vues aériennes verticales par ville (globale + communes/quartiers) et comparaison orthophoto IGN.
# Usage : TERRAIN_CACHE=<cache> tests/audit/run_aerial.sh <godot> <dossier> [villes...]  (identifiants : angers, idf…)
# Rendu par lots de 6 vues (un processus Godot par lot, mémoire bornée), puis une reprise des vues manquantes.
set -u
GODOT="$1"; OUT="$2"; shift 2
cd "$(dirname "$0")/../.."
CITIES="${*:-$(ls data/free/*.json | xargs -n1 basename | sed 's/\.json$//')}"
render() {  # $1 = views.json, puis fichiers
  timeout 5400 xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
    -s tests/audit/aerial_shots.gd -- "$@" 2>&1 | grep -E '^AERIAL|SCRIPT ERROR' | head -50
}
for c in $CITIES; do
  d=$(python3 tests/audit/aerial_views.py prepare "$c" "$OUT" | sed -n 's/.*-> //p')
  [ -n "$d" ] || { echo "$c : préparation impossible"; continue; }
  files=$(python3 -c "import json,sys;print(' '.join(v['file'] for v in json.load(open(sys.argv[1]))['views']))" "$d/views.json")
  : > "$d/rendu.log"
  for pass in 1 2; do
    todo=""
    for f in $files; do [ -f "$d/raw_$f.png" ] || [ -f "$d/$f.png" -a "$pass" = 2 ] || todo="$todo $f"; done
    [ -n "$todo" ] || break
    set -- $todo
    while [ $# -gt 0 ]; do
      batch="${*:1:6}"; shift $(( $# < 6 ? $# : 6 ))
      render "$d/views.json" $batch >> "$d/rendu.log"
    done
  done
  python3 tests/audit/aerial_views.py compose "$c" "$OUT"
  echo "$c : $(ls "$d"/*.png 2>/dev/null | wc -l) images"
done
