use godot::prelude::*;
struct TramSimExtension;
// SAFETY: all exported methods operate on owned numeric arrays and the main thread.
#[gdextension]
unsafe impl ExtensionLibrary for TramSimExtension {}

#[derive(GodotClass)]
#[class(base=RefCounted, init)]
struct TramSimNative {
    base: Base<RefCounted>,
}

#[godot_api]
impl TramSimNative {
    #[func]
    fn abi_version(&self) -> i32 {
        tramsim_core::ABI_VERSION
    }
    #[func]
    fn physics_step(&self, a: PackedFloat64Array) -> PackedFloat64Array {
        tramsim_core::physics(a.as_slice())
            .map(|v| PackedFloat64Array::from(v.as_slice()))
            .unwrap_or_default()
    }
    #[func]
    fn weather_step(&self, a: PackedFloat64Array) -> PackedFloat64Array {
        tramsim_core::weather(a.as_slice())
            .map(|v| PackedFloat64Array::from(v.as_slice()))
            .unwrap_or_default()
    }
}
