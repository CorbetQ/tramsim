class_name Speedometer
extends Control
## Tachymètre circulaire : arc de vitesse (rouge au-delà de la limite), repère et panneau de limite,
## vitesse numérique au centre. Aiguille amortie.

var speed_kmh := 0.0
var limit_kmh := 50.0
var max_kmh := 80.0
var overspeed := false
var _shown := 0.0

const A0 := deg_to_rad(135.0)
const SWEEP := deg_to_rad(270.0)

func _init() -> void:
	custom_minimum_size = Vector2(212, 212)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_values(v: float, lim: float, vmax: float, over: bool) -> void:
	speed_kmh = maxf(v, 0.0); limit_kmh = lim; overspeed = over
	max_kmh = maxf(40.0, ceilf(maxf(vmax, lim) / 10.0) * 10.0)

func _process(dt: float) -> void:
	var t := speed_kmh
	if absf(_shown - t) > 0.02:
		_shown = lerpf(_shown, t, clampf(dt * 10.0, 0.0, 1.0)); queue_redraw()

func _ang(v: float) -> float:
	return A0 + SWEEP * clampf(v / max_kmh, 0.0, 1.0)

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 4.0
	var font := UiTheme.font(); var bold := UiTheme.font(true)
	draw_circle(c, r, Color(0.05, 0.065, 0.085, 0.82))
	draw_arc(c, r, 0, TAU, 64, Color(1, 1, 1, 0.08), 1.5, true)
	var ar := r - 16.0
	draw_arc(c, ar, A0, A0 + SWEEP, 64, Color(1, 1, 1, 0.1), 10.0, true)
	# vitesse : arc d'accent jusqu'à la limite, rouge au-delà
	var lim_a := _ang(limit_kmh)
	var sp_a := _ang(_shown)
	if _shown > 0.3:
		draw_arc(c, ar, A0, minf(sp_a, lim_a), 48, UiTheme.ACCENT, 10.0, true)
		if sp_a > lim_a:
			draw_arc(c, ar, lim_a, sp_a, 24, UiTheme.DANGER, 10.0, true)
	# zone au-dessus de la limite (fine, rouge)
	draw_arc(c, ar + 9.0, lim_a, A0 + SWEEP, 32, Color(UiTheme.DANGER, 0.55), 3.0, true)
	# graduations
	var step := 10.0 if max_kmh <= 100.0 else 20.0
	var v := 0.0
	while v <= max_kmh + 0.1:
		var a := _ang(v)
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * (ar - 9.0), c + dir * (ar - 17.0), Color(1, 1, 1, 0.55), 2.0, true)
		var s := str(int(v)); var fs := 13
		var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, c + dir * (ar - 30.0) - Vector2(tw.x * 0.5, -fs * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.6))
		v += step
	# repère de limite
	var ld := Vector2(cos(lim_a), sin(lim_a))
	draw_line(c + ld * (ar - 8.0), c + ld * (ar + 12.0), UiTheme.DANGER, 4.0, true)
	# aiguille
	var nd := Vector2(cos(sp_a), sin(sp_a))
	draw_line(c + nd * 18.0, c + nd * (ar - 4.0), Color.WHITE, 3.0, true)
	draw_circle(c + nd * (ar - 2.0), 5.0, UiTheme.DANGER if overspeed else Color.WHITE)
	# vitesse numérique
	var txt := str(roundi(speed_kmh)); var big := int(r * 0.48)
	var sz := bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, big)
	draw_string(bold, c + Vector2(-sz.x * 0.5, big * 0.18), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, big, UiTheme.DANGER if overspeed else Color.WHITE)
	var u := "km/h"; var us := font.get_string_size(u, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	draw_string(font, c + Vector2(-us.x * 0.5, big * 0.18 + 18.0), u, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.MUTED)
	# panneau de limitation (cercle rouge) en bas
	var pc := c + Vector2(0, r * 0.66)
	var pr := r * 0.2
	draw_circle(pc, pr, Color.WHITE)
	draw_arc(pc, pr - 2.5, 0, TAU, 32, UiTheme.DANGER, 5.0, true)
	var ls := str(roundi(limit_kmh)); var lfs := int(pr * 0.95)
	var lsz := bold.get_string_size(ls, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs)
	draw_string(bold, pc + Vector2(-lsz.x * 0.5, lfs * 0.36), ls, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, Color.BLACK)
