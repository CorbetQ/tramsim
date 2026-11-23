class_name CabActions
extends RefCounted
## Commandes de conduite du jeu et leur liaison : touche clavier, nœud 3D de cabine (`ctl_<…>`, voir
## docs/refonte-visuelle/stock_manifest.md) et type d'animation. Source unique pour main.gd (clavier, HUD,
## clic/toucher en cabine), CabView (animations) et tests/test_stock_hd.gd (nœuds requis).

## action -> {node, keys, label, kind}
const ACTIONS := {
	"notch": {"node": "ctl_notch", "keys": [KEY_W, KEY_Z, KEY_UP, KEY_S, KEY_DOWN, KEY_X], "label": "Manipulateur", "kind": "lever"},
	"emergency": {"node": "ctl_emergency", "keys": [KEY_SPACE], "label": "Arrêt d'urgence", "kind": "button"},
	"doors": {"node": "ctl_doors", "keys": [KEY_O], "label": "Portes", "kind": "button"},
	"horn": {"node": "ctl_horn", "keys": [KEY_K], "label": "Gong", "kind": "button"},
	"pantograph": {"node": "ctl_pantograph", "keys": [KEY_P], "label": "Pantographe / alimentation", "kind": "toggle"},
	"reverser": {"node": "ctl_reverser", "keys": [KEY_V], "label": "Inverseur / changement de cabine", "kind": "toggle"},
	"sand": {"node": "ctl_sand", "keys": [KEY_B], "label": "Sablage", "kind": "button"},
	"headlights": {"node": "ctl_headlights", "keys": [KEY_H], "label": "Phares", "kind": "toggle"},
	"wiper": {"node": "ctl_wiper", "keys": [KEY_E], "label": "Essuie-glace", "kind": "toggle"},
	"mirrors": {"node": "ctl_mirrors", "keys": [KEY_N], "label": "Rétroviseurs", "kind": "toggle"},
	"autopilot": {"node": "ctl_autopilot", "keys": [KEY_L], "label": "Pilote automatique", "kind": "button"},
}
## Nœuds supplémentaires facultatifs du modélisateur -> action.
const EXTRA_NODES := {"ctl_bell": "horn", "ctl_doors_left": "doors", "ctl_doors_right": "doors", "ctl_doors_close": "doors",
	"ctl_power_mode": "pantograph"}
const HUD_MIN_KEY := KEY_I   # HUD minimal en vue cabine

static func actions() -> PackedStringArray:
	return PackedStringArray(ACTIONS.keys())

static func node_for(action: String) -> String:
	return str(ACTIONS.get(action, {}).get("node", ""))

static func required_nodes() -> PackedStringArray:
	var r := PackedStringArray()
	for a in ACTIONS: r.append(ACTIONS[a].node)
	return r

## Nom de nœud (ou alias du manifeste) -> action, "" si aucune.
static func action_for_node(node_name: String, aliases: Dictionary = {}) -> String:
	var n := str(aliases.get(node_name, node_name))
	if not n.begins_with("ctl_"): n = "ctl_" + n
	for a in ACTIONS:
		if ACTIONS[a].node == n: return a
	return str(EXTRA_NODES.get(n, ""))

static func action_for_key(k: int) -> String:
	for a in ACTIONS:
		if k in ACTIONS[a].keys: return a
	return ""
