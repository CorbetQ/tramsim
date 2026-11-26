class_name RoadDecals
extends RefCounted
## Decals de voirie (refonte P3) : plaques d'égout, salissures en pied de bordure, taches d'huile sous les voitures
## en stationnement, rapiéçages d'enrobé et marquages usés. Projetés (Decal Godot) sur l'enrobé/les dalles :
## Forward+ et Mobile seulement ; **aucun decal en Compatibility** (repli : sol texturé seul). Textures générées
## (tools/models/props/build_vegetation_textures.py, assets/textures/vegetation/decal_*.png), fiche
## data/materials/decals_voirie.json. Portée courte (fondu en distance) : coût de clusters borné.

const GRIME := 0
const OIL := 1
const MANHOLE := 2
const PATCH := 3
const NAMES := ["grime", "oil", "manhole", "patch"]
const FADE := 70.0
const FADE_MOBILE := 35.0

static var _tex: Array = []

## Vrai si le renderer actif dessine les decals (pas en Compatibility, ni sans affichage).
static func enabled() -> bool:
	return VisualEffects.renderer() != "gl_compatibility" and DisplayServer.get_name() != "headless"

static func texture(kind: int) -> Texture2D:
	if _tex.is_empty():
		for n in NAMES: _tex.append(load("res://assets/textures/vegetation/decal_%s.png" % n))
	return _tex[kind]

## Un decal : `kind`, position (repère du parent, y = sol), angle (rad), taille (largeur x longueur, m).
static func make(kind: int, pos: Vector3, angle: float, size: Vector2) -> Decal:
	var d := Decal.new()
	d.size = Vector3(size.x, 0.5, size.y)
	d.position = pos
	d.rotation = Vector3(0, angle, 0)
	d.texture_albedo = texture(kind)
	if kind == MANHOLE: d.texture_normal = load("res://assets/textures/vegetation/decal_manhole_n.png")
	d.albedo_mix = 1.0
	d.upper_fade = 0.15; d.lower_fade = 0.15
	d.normal_fade = 0.5    # pas de projection sur les faces verticales (bordures, façades)
	d.distance_fade_enabled = true
	d.distance_fade_begin = FADE_MOBILE if DayNight.low_quality else FADE
	d.distance_fade_length = 15.0
	d.cull_mask = 1
	d.name = "decal_" + NAMES[kind]
	return d
