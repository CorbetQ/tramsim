#!/usr/bin/env bash
# Real Godot Master capture with a clocked ALSA null sink; PCM samples are untouched.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d)
had_override=0
if [[ -f override.cfg ]]; then cp override.cfg "$work/override.cfg"; had_override=1; fi
cleanup() {
  if [[ "$had_override" == 1 ]]; then cp "$work/override.cfg" override.cfg; else rm -f override.cfg; fi
  rm -rf "$work"
}
trap cleanup EXIT
cat > "$work/asound.conf" <<'CONFIG'
pcm.!default { type null }
ctl.!default { type null }
CONFIG
printf '[audio]\ndriver/mix_rate=48000\n' >> override.cfg
gcc -shared -fPIC -o "$work/clock.so" tools/audio/alsa_null_clock.c -ldl
export LD_PRELOAD="$work/clock.so${LD_PRELOAD:+:$LD_PRELOAD}"
export ALSA_CONFIG_PATH="$work/asound.conf"
# Do not use --headless: it would override the explicit ALSA driver with Dummy.
godot --display-driver headless --audio-driver ALSA --path . \
  --script tools/audio/capture_driving_audio.gd -- "${1:-citadis_302}" "${2:-angers__citadis_302}" "${3:-}" "${4:-}"
