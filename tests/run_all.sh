#!/usr/bin/env bash
# Usage : GODOT=/chemin/godot PYTHON=python3 tests/run_all.sh
set -uo pipefail
G="${GODOT:-godot}"
P="${PYTHON:-python3}"
cd "$(dirname "$0")/.."
rc=0
import_log=$(mktemp)
if ! "$G" --headless --path . --import >"$import_log" 2>&1 || grep -Eq 'SCRIPT ERROR|Parse Error' "$import_log"; then
  cat "$import_log"
  rm -f "$import_log"
  exit 1
fi
rm -f "$import_log"
for t in run_tests test_adhesion test_world_geometry test_rolling_stock test_angers test_angers_real test_traffic_free test_turnback test_bidir test_audio test_audio_families test_save test_scene test_scene_data test_geo test_input test_mobile test_choice test_network_ui test_physical_networks test_operations test_power_routing test_platform_stops test_all_networks; do
  if [ "$t" = "test_input" ] || [ "$t" = "test_mobile" ] || [ "$t" = "test_choice" ] || [ "$t" = "test_network_ui" ]; then
    if command -v xvfb-run >/dev/null; then
      out=$(timeout 600 xvfb-run -a -s "-screen 0 1280x720x24" "$G" --path . --audio-driver Dummy --rendering-driver opengl3 --resolution 1280x720 -s "tests/$t.gd" 2>&1); c=$?
    elif [ -n "${DISPLAY:-}" ]; then
      out=$(timeout 600 "$G" --path . --audio-driver Dummy --rendering-driver opengl3 --resolution 1280x720 -s "tests/$t.gd" 2>&1); c=$?
    else
      echo "SKIP $t (affichage OpenGL absent)"; continue
    fi
  else
    out=$(timeout 2400 "$G" --headless --path . -s "tests/$t.gd" 2>&1); c=$?
  fi
  if [ "$c" -ne 0 ] || printf '%s\n' "$out" | grep -Eq '^ECHEC|SCRIPT ERROR|TOTAL_ECHECS\|[1-9]'; then
    echo "FAIL $t ($c)"; printf '%s\n' "$out" | tail -50; rc=1
  else echo "PASS $t ($(printf '%s\n' "$out" | grep -c '^ok' || true))"; fi
done
"$P" -W ignore -m unittest discover -s tests -p 'test_*.py' || rc=1
"$P" tools/import/validate_networks.py data/networks/*.json data/free/*.json tests/fixtures/schema_test.json > /tmp/validate.log || { cat /tmp/validate.log; rc=1; }
grep -c ' 0 erreur' /tmp/validate.log | xargs echo 'réseaux valides :'
exit "$rc"
