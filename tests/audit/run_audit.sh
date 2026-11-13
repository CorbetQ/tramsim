#!/usr/bin/env bash
# Audit visuel : prises de vue des 28 villes. Usage : tests/audit/run_audit.sh <godot> <dossier> [villes...]
set -u
GODOT="$1"; OUT="$2"; shift 2
cd "$(dirname "$0")/../.."
CITIES="${*:-$(ls data/free/*.json | xargs -n1 basename | sed 's/\.json$//')}"
mkdir -p "$OUT"
for c in $CITIES; do
  timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path . --rendering-driver opengl3 --resolution 1280x720 \
    -s tests/audit/audit_shots.gd -- "$OUT" "$c" > "$OUT/$c.log" 2>&1
  rc=$?; echo "$c : $(grep -c "AUDIT|shot" "$OUT/$c.log") vues, code $rc"
done
grep -h '^AUDIT|' "$OUT"/*.log > "$OUT/audit_points.txt"
