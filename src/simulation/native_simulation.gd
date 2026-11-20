class_name NativeSimulation
extends RefCounted
## Optional native kernel. A missing platform library never prevents starting the game.
static var enabled := true
static var _kernel: Object
static var _checked := false
static func kernel() -> Object:
	if not enabled: return null
	if not _checked:
		_checked=true
		if ClassDB.class_exists("TramSimNative"):
			var candidate: Object = ClassDB.instantiate("TramSimNative")
			if candidate.call("abi_version") == 1: _kernel = candidate
	return _kernel
