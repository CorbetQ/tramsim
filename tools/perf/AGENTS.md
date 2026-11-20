# Diagnostics TramSim

- Read `docs/p0/ANDROID_INSTRUMENTATION.md` before profiling.
- No runtime inference, subscription, root, network downloads or player-save changes.
- Default gameplay must never enable the benchmark. The no-request autoload removes itself.
- `python tools/perf/run_headless_smoke.py` runs the actual desktop game in an isolated
  profile; its FPS are never Android/GPU performance results.
- `python tools/perf/android_benchmark.py devices` is read-only. Physical capture needs
  an authorized device, a debuggable build and explicit `--restart` after finishing gameplay.
- Never invent unavailable GPU, memory, thermal or energy values. Keep fixture/emulator
  results distinct from physical-device captures. No FPS promise without actual hardware.
- Preserve source datasets, user directories and old baselines. Do not delete GitHub
  artifacts to work around a quota without explicit authorization.
- Keep each P0 lot independent; no automatic merges or releases.
