class_name PassengerController
extends RefCounted
const EYE := 1.65
const WALK_SPEED := 1.4
var position := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var train_id := ""
var ride_distance := 4.0
var lateral := 0.0
var seated := false

func look(delta: Vector2) -> void:
	yaw=wrapf(yaw-delta.x*.003,-PI,PI);pitch=clampf(pitch-delta.y*.003,-1.2,1.2)

func walk(input: Vector2, dt: float, ground: Callable, clear: Callable) -> void:
	var direction := Vector3(input.x,0,input.y).limit_length()*WALK_SPEED*dt
	direction=direction.rotated(Vector3.UP,yaw)
	var count := maxi(1,ceili(direction.length()/.2))
	for i in count:
		var candidate := position+direction/count
		var y: float = ground.call(candidate)+EYE
		if absf(y-position.y)>.45:continue
		candidate.y=y
		if clear.is_valid() and not clear.call(position,candidate):continue
		position=candidate

static func can_board(speed: float, door_open: float, distance: float, height_difference: float) -> bool:
	return absf(speed)<.1 and door_open>.9 and distance<=2.7 and absf(height_difference)<1.2
