# Rotterdam Citadis traction regimes

Source: **Streetcar04.wav**, **LG**, [Freesound 14279](https://freesound.org/people/LG/sounds/14279/), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Source description identifies a Citadis departing a Rotterdam platform. It does **not** certify a French Citadis 302 or 305 configuration.

The project uses the public preview collected in `samples/raw/`, then the approved harmonic candidate `samples/analysis/revision3/rotterdam-motor-harmonic-candidate.flac`. Its STFT harmonic/ridge mask reduces broadband/transient components but does not prove an isolated motor: voices, bells, rail tones or other harmonic sources may remain. The full source/candidate/residual reconstruction study remains in `samples/analysis/revision3/`. No claim is made that the entire remaining signal is traction.

Adaptation: mono 16→32 kHz resampling; three short source windows; 80–180 ms equal-amplitude overlap, 8 ms cosine endpoint guards, DC removal and constant-gain normalization to −20 LUFS. No synthesized partials or global spectral flattening. See `rotterdam-traction-manifest.json` for source and loop SHA-256, exact windows, levels and processing. The loops inherit CC BY 4.0. Rebuild with `python tools/audio/build_rotterdam_bank.py` (numpy, scipy, ffmpeg).

- Startup carrier: source 2.00–2.80 s, resulting loop 0.72 s.
- Low regime: source 4.00–5.50 s, resulting loop 1.35 s.
- High regime: source 10.25–12.75 s, resulting loop 2.32 s.

Speed anchors (1, 4 and 13 m/s) are **design estimates**, not measured speeds. Runtime uses existing players, smooth effort envelopes, low/high regime crossfades and pitch bounded to 0.94–1.16. Short windows preserve locally useful tonal structure; they do not recreate the complete original acceleration contour. Repetition, overlap beating and source-separation artifacts remain possible and require listening review.

All 15 canonical Citadis 302 variants use this **related-family** bank, including Le Mans 302. Other families, including the existing Le Mans 402 fallback, remain unchanged. These departure textures mute on coasting and braking. Braking regeneration remains an explicitly procedural estimate; no real deceleration was fabricated. The 305 model is unchanged and remains modeled.
