#!/bin/bash
# usage: fetch.sh OUT asset...
OUT=$1; shift
UA="tramsim-asset-fetch/1.0"
for a in "$@"; do
  mkdir -p "$OUT/$a"
  curl -sf -A "$UA" "https://api.polyhaven.com/files/$a" -o "$OUT/$a/files.json" || { echo "fail $a"; continue; }
  curl -sf -A "$UA" "https://api.polyhaven.com/info/$a" -o "$OUT/$a/info.json"
  for k in Diffuse nor_gl arm; do
    u=$(python3 -I -c "import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]]['2k']['jpg']['url'])" "$OUT/$a/files.json" $k)
    [ -s "$OUT/$a/$k.jpg" ] || curl -sf -A "$UA" "$u" -o "$OUT/$a/$k.jpg"
  done
  echo "ok $a"
done
