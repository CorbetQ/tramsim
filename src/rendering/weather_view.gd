class_name WeatherView
extends Node3D
## Bounded near-camera precipitation. No geography assets changed.
var drops: CPUParticles3D
func _ready() -> void:
	drops=CPUParticles3D.new();drops.amount=160 if OS.has_feature("mobile") else 320
	drops.lifetime=1.2;drops.emission_shape=CPUParticles3D.EMISSION_SHAPE_BOX
	drops.emission_box_extents=Vector3(10,0.2,10);drops.direction=Vector3(-0.12,-1,0)
	drops.spread=4;drops.initial_velocity_min=15;drops.initial_velocity_max=22
	drops.gravity=Vector3(0,-3,0);drops.local_coords=false
	var mesh := QuadMesh.new();mesh.size=Vector2(0.018,0.45)
	var mat := StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mat.vertex_color_use_as_albedo=true;mat.albedo_color=Color.WHITE
	mat.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED;mesh.material=mat;drops.mesh=mesh
	drops.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;drops.emitting=false;add_child(drops)

func apply(state: WeatherState, view: LineView, sheltered: bool = false) -> void:
	if drops==null or view.cam==null:return
	global_position=view.cam.global_position+Vector3(0,9,0)
	drops.emitting=state.rain>0.03 and not sheltered
	drops.visible=not sheltered
	drops.color=Color(0.65,0.8,0.92,state.rain*.4)
	var env := view.day_night.env
	env.fog_density+=state.fog*0.012+state.rain*0.001
	view.day_night.sun.light_energy*=1.0-state.rain*0.45
	var sky := view.day_night.sky_mat
	for key in ["top_color","horizon_color","cloud_light","cloud_shade"]:
		var original: Color=sky.get_shader_parameter(key)
		sky.set_shader_parameter(key,original.lerp(Color("#8999a5"),state.rain*.65))
