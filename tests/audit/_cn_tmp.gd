extends SceneTree
func _init():
	var S = load("res://tests/audit/p4v_shots.gd")
	for c in ["bordeaux", "dijon", "lyon"]: print(c, " ", S.center_net(c))
	quit()
