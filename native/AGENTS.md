# Native simulation

- Keep Godot as renderer/export host and preserve GDScript fallback until each platform passes native parity tests.
- `cargo test --manifest-path native/Cargo.toml --locked -p tramsim-core`
- `python tools/build_native.py --release`; then import Godot and run `tests/test_native_weather.gd -- --require-native` through `tools/qa/run_godot_check.py`.
- No dependencies, downloads, IO, scene objects or threads in the pure core crate.
- ABI version 1 numeric buffers reject nonfinite/invalid inputs. Update both sides and tests before changing the layout.
- Keep Cargo.lock. godot-rust uses MPL-2.0, not MIT; retain THIRD_PARTY.md and license/source notices.
- A successful cross-compilation is not a device test. Do not claim Android FPS from a CPU microbenchmark.
- Never overwrite a loaded library in place; installer uses atomic replacement and the editor must restart to load a new version.
