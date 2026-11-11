#!/usr/bin/env bash
# Usage : GODOT=/chemin/godot tests/run_all.sh
set -u
G="${GODOT:-godot}"; cd "$(dirname "$0")/.."
rc=0
"$G" --headless --path . --import >/dev/null 2>&1
for t in run_tests test_rolling_stock test_angers test_angers_real test_traffic_free test_turnback test_save test_scene test_input test_all_networks; do
  if [ "$t" = "test_input" ]; then
    command -v xvfb-run >/dev/null || { echo "SKIP $t (xvfb-run absent)"; continue; }
    out=$(timeout 600 xvfb-run -a -s "-screen 0 1280x720x24" "$G" --path . --rendering-driver opengl3 --resolution 1280x720 -s tests/$t.gd 2>&1); c=$?
  else
    out=$(timeout 2400 "$G" --headless --path . -s tests/$t.gd 2>&1); c=$?
  fi
  if [ $c -ne 0 ] || echo "$out" | grep -q "^ECHEC\|SCRIPT ERROR\|TOTAL_ECHECS|[1-9]"; then echo "FAIL $t"; echo "$out" | grep "ECHEC\|SCRIPT"; rc=1; else echo "PASS $t ($(echo "$out" | grep -c '^ok'))"; fi
done
python3 -W ignore -m unittest tests/test_import.py 2>&1 | tail -1
python3 tools/import/validate_networks.py data/networks/*.json data/free/*.json tests/fixtures/schema_test.json > /tmp/validate.log || { cat /tmp/validate.log; rc=1; }
grep -c " 0 erreur" /tmp/validate.log | xargs echo "réseaux valides :"
exit $rc
