#!/usr/bin/env bash
# Cuisson LightmapGI des scènes préparées par prepare_lightmaps.gd (refonte P1).
# Usage : tools/lightmaps/bake.sh <godot> [scène res://… …]   (défaut : toutes les assets/lightmaps/*/*_bake.tscn)
# Exige Vulkan (GPU, ou lavapipe : mesa-vulkan-drivers) ; sans affichage, lancé sous xvfb-run.
# BAKE_TIMEOUT : durée maximale en secondes (défaut 7200). CI : .github/workflows/lightmaps.yml ; Windows : bake_windows.bat.
set -uo pipefail
G="$1"; shift
cd "$(dirname "$0")/../.."
SCENES="${*:-$(ls assets/lightmaps/*/*_bake.tscn 2>/dev/null | sed 's|^|res://|' | paste -sd, -)}"
[ -n "$SCENES" ] || { echo "aucune scène : lancer prepare_lightmaps.gd"; exit 1; }
mkdir -p addons/tramsim_lightmap_bake && cp tools/lightmaps/addon/plugin.cfg tools/lightmaps/addon/plugin.gd addons/tramsim_lightmap_bake/
cp project.godot /tmp/project.godot.bak
printf '\n[editor_plugins]\n\nenabled=PackedStringArray("res://addons/tramsim_lightmap_bake/plugin.cfg")\n' >> project.godot
RUN=(); command -v xvfb-run >/dev/null && [ -z "${DISPLAY:-}" ] && RUN=(xvfb-run -a -s "-screen 0 1280x720x24")
TRAMSIM_BAKE="${SCENES// /,}" timeout "${BAKE_TIMEOUT:-7200}" "${RUN[@]}" "$G" --editor --path . --rendering-driver vulkan --audio-driver Dummy 2>&1 | tee "${BAKE_LOG:-/dev/null}" | grep -E 'BAKE\|' ; rc=${PIPESTATUS[0]}
cp /tmp/project.godot.bak project.godot; rm -rf addons/tramsim_lightmap_bake
exit "$rc"
