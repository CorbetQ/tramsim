class_name NotchLever
extends Control
## Manipulateur traction / freinage : crans dessinés (T1–T4 vers le haut, F1–F4 vers le bas, U = urgence),
## poignée déplaçable au doigt ou à la souris (clic, glisser). Valeur dans [-1, 1].

signal changed(v: float)

var value := 0.0
var emergency := false
var _drag := false
const PAD := 18.0

func _init() -> void:
	custom_minimum_size = Vector2(96, 260)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_VSIZE

func set_value(v: float) -> void:
	value = clampf(v, -1.0, 1.0); queue_redraw()

func _y_of(v: float) -> float:
	return PAD + (1.0 - (v + 1.0) * 0.5) * (size.y - 2.0 * PAD)

func _v_of(y: float) -> float:
	var v := 1.0 - 2.0 * (y - PAD) / maxf(1.0, size.y - 2.0 * PAD)
	v = clampf(snappedf(v, 0.05), -1.0, 1.0)
	if absf(v) < 0.08: v = 0.0   # cran neutre « magnétique »
	return v

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_drag = ev.pressed
		if ev.pressed: _apply(ev.position.y)
		accept_event()
	elif ev is InputEventMouseMotion and _drag:
		_apply(ev.position.y); accept_event()
	elif ev is InputEventScreenTouch:
		_drag = ev.pressed
		if ev.pressed: _apply(ev.position.y)
		accept_event()
	elif ev is InputEventScreenDrag:
		_apply(ev.position.y); accept_event()

func _apply(y: float) -> void:
	var v := _v_of(y)
	if v != value:
		value = v; queue_redraw(); changed.emit(v)

func _draw() -> void:
	var font := UiTheme.font(); var bold := UiTheme.font(true)
	var cx := size.x * 0.5 + 10.0
	var tw := 22.0
	var y0 := _y_of(0.0)
	# rail : traction (vert) en haut, freinage (orange) en bas, urgence (rouge) en butée
	draw_rect(Rect2(cx - tw * 0.5, _y_of(1.0), tw, y0 - _y_of(1.0)), Color(UiTheme.TRACTION, 0.18))
	draw_rect(Rect2(cx - tw * 0.5, y0, tw, _y_of(-0.9) - y0), Color(UiTheme.BRAKE, 0.18))
	draw_rect(Rect2(cx - tw * 0.5, _y_of(-0.9), tw, _y_of(-1.0) - _y_of(-0.9)), Color(UiTheme.DANGER, 0.45))
	# remplissage jusqu'à la valeur courante
	var yv := _y_of(value)
	if value > 0.0:
		draw_rect(Rect2(cx - tw * 0.5, yv, tw, y0 - yv), Color(UiTheme.TRACTION, 0.85))
	elif value < 0.0:
		draw_rect(Rect2(cx - tw * 0.5, y0, tw, yv - y0), Color(UiTheme.DANGER if value <= -0.99 else UiTheme.BRAKE, 0.85))
	# crans
	var marks := [[1.0, "T4"], [0.75, "T3"], [0.5, "T2"], [0.25, "T1"], [0.0, "N"], [-0.25, "F1"], [-0.5, "F2"], [-0.75, "F3"], [-1.0, "U"]]
	for m in marks:
		var y := _y_of(m[0])
		var col: Color = UiTheme.TRACTION if m[0] > 0.0 else (UiTheme.MUTED if m[0] == 0.0 else (UiTheme.DANGER if m[0] <= -0.99 else UiTheme.BRAKE))
		draw_line(Vector2(cx - tw * 0.5 - 6.0, y), Vector2(cx + tw * 0.5 + 6.0, y), Color(1, 1, 1, 0.35 if m[0] != 0.0 else 0.8), 2.0)
		var fs := 13 if m[0] != 0.0 else 15
		var s: String = m[1]
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(bold if m[0] == 0.0 else font, Vector2(cx - tw * 0.5 - 12.0 - w, y + fs * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	# poignée
	var kh := 26.0; var kw := 58.0
	var knob := Rect2(cx - kw * 0.5, yv - kh * 0.5, kw, kh)
	var sb := UiTheme.box(Color("#f1f5f9"), 9, 0, Color(0, 0, 0, 0.35), 2)
	draw_style_box(sb, knob)
	draw_line(Vector2(knob.position.x + 10, yv), Vector2(knob.end.x - 10, yv), Color(0.2, 0.25, 0.3), 3.0)
