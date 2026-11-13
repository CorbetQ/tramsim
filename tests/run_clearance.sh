#!/usr/bin/env bash
# Chaque ville conserve tous ses échantillons de gabarit et sa limite de quatre minutes.
# Les isoler évite qu'un contrôle complet dépende du temps déjà consommé par les autres villes.
set -uo pipefail
cd "$(dirname "$0")/.."
G="${GODOT:-godot}"
P="${PYTHON:-python3}"
mapfile -t stock_test_cities < <("$P" - <<'PY'
import json
from pathlib import Path
index=json.load(open('data/index.json'))
print('\n'.join(sorted({n['id'].split('_')[0] for n in index['networks'] if Path('data/scenes',n['id'].split('_')[0]+'.bin').exists()})))
PY
)
stock_test_result=0
for stock_test_city in "${stock_test_cities[@]}"; do
  stock_test_output=$(timeout 360 "$G" --headless --path . -s tests/test_clearance.gd -- "$stock_test_city" 2>&1)
  stock_test_code=$?
  if [ "$stock_test_code" -ne 0 ] || printf '%s\n' "$stock_test_output" | grep -Eq '^ECHEC|SCRIPT ERROR|TOTAL_ECHECS\|[1-9]'; then
    printf 'FAIL clearance %s (%s)\n%s\n' "$stock_test_city" "$stock_test_code" "$stock_test_output"
    stock_test_result=1
  else
    printf 'PASS clearance %s\n' "$stock_test_city"
    printf '%s\n' "$stock_test_output" | grep '^gabarit :'
  fi
done
exit "$stock_test_result"
