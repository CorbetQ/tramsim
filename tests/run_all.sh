#!/usr/bin/env bash
# Usage : GODOT=/chemin/godot tests/run_all.sh
set -u
G="${GODOT:-godot}"; cd "$(dirname "$0")/.."
rc=0
"$G" --headless --path . --import >/dev/null 2>&1
for t in run_tests test_angers test_angers_real test_traffic_free test_save test_scene; do
  out=$(timeout 180 "$G" --headless --path . -s tests/$t.gd 2>&1); c=$?
  if [ $c -ne 0 ] || echo "$out" | grep -q "^ECHEC\|SCRIPT ERROR"; then echo "FAIL $t"; echo "$out" | grep "ECHEC\|SCRIPT"; rc=1; else echo "PASS $t ($(echo "$out" | grep -c '^ok'))"; fi
done
python3 -W ignore -m unittest tests/test_import.py 2>&1 | tail -1
python3 tools/import/validate_networks.py data/networks/*.json tests/fixtures/schema_test.json || rc=1
exit $rc
