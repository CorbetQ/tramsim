# TramSim Audio Studio

Use `python tools/audio/studio.py --help` from the repository root.
Read `docs/audio-studio/README.md` before changing banks.

- Audio production is offline; never run inference in Godot.
- `data/audio/sources.json` → `catalogue` is the source of truth for current asset
  hashes, measurements, classification and rights. `families.json` is runtime routing.
- Keep original sources. New downloads: official APIs, verified CC0 or CC BY only.
  Existing CC BY-SA files must retain their credit and share-alike obligations.
- Unknown/NC/ND rights are denied. Research-only references are not distributable assets.
- Never call a related capture exact, or a modelled/synthetic/AI sound authentic.
- Do not import `design_samples.py`: its top-level code rewrites production assets.
- Legacy rebuilders may overwrite approved profiles; use additive candidate Studio banks.
- Never replace approved routing before human audition. `bank activate` requires
  `--human-reviewed`; respect variant overrides.
- No paid services, no secret in Git, no weight download on first generation.
- Tests: `python tools/audio/studio.py test --godot`; report:
  `python tools/audio/studio.py report --waveforms`.
- True Godot recording: `python tools/audio/studio.py demo`. ALSA null is clocked
  by the trusted local C helper. `--headless` alone forces Dummy and cannot prove sound.
- Metrics and spectral comparisons are technical checks, never perceptual approval.
