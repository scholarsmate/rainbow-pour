extends ColorRect

const RIBBON_COLORS := [
	Color(0.96, 0.18, 0.22),
	Color(1.00, 0.50, 0.08),
	Color(1.00, 0.86, 0.10),
	Color(0.16, 0.88, 0.38),
	Color(0.14, 0.58, 1.00),
	Color(0.46, 0.28, 1.00),
	Color(0.92, 0.22, 0.82),
]

@export var animated := true

var _time := 0.0

func _ready() -> void:
	color = Color(0.035, 0.045, 0.080, 1.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_to_viewport()
	get_viewport().size_changed.connect(_sync_to_viewport)
	set_process(animated)

func _sync_to_viewport() -> void:
	size = get_viewport_rect().size
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var area := size
	if area.x <= 0.0 or area.y <= 0.0:
		return
	_draw_base_gradient(area)
	_draw_stage_lights(area)
	_draw_rainbow_ribbons(area)
	_draw_lower_glow(area)
	_draw_vignette(area)

func _draw_base_gradient(area: Vector2) -> void:
	var steps := 42
	var top := Color(0.030, 0.038, 0.078)
	var mid := Color(0.055, 0.070, 0.112)
	var bottom := Color(0.018, 0.024, 0.042)
	for i in steps:
		var t := float(i) / float(steps - 1)
		var c := top.lerp(mid, minf(t * 1.45, 1.0)) if t < 0.69 else mid.lerp(bottom, (t - 0.69) / 0.31)
		var y := area.y * t
		draw_rect(Rect2(0.0, y, area.x, area.y / float(steps) + 1.0), c, true)

func _draw_stage_lights(area: Vector2) -> void:
	var drift := sin(_time * 0.18) * 28.0
	for i in 10:
		var t := float(i) / 9.0
		var x := lerpf(-area.x * 0.15, area.x * 1.05, t) + drift
		var alpha := 0.026 + 0.014 * sin(_time * 0.42 + float(i) * 1.7)
		draw_line(Vector2(x, -40.0), Vector2(x + area.x * 0.34, area.y + 40.0),
				Color(0.38, 0.72, 1.0, alpha), 3.0, true)
	for i in 9:
		var t := float(i) / 8.0
		var x := lerpf(area.x * 1.08, -area.x * 0.08, t) - drift * 0.7
		var alpha := 0.018 + 0.012 * sin(_time * 0.36 + float(i) * 1.3)
		draw_line(Vector2(x, -30.0), Vector2(x - area.x * 0.30, area.y + 30.0),
				Color(1.0, 0.66, 0.25, alpha), 2.0, true)

func _draw_rainbow_ribbons(area: Vector2) -> void:
	var base_y := area.y * 0.20
	var width := maxf(14.0, area.y * 0.027)
	for band in RIBBON_COLORS.size():
		var points := PackedVector2Array()
		var color: Color = RIBBON_COLORS[band]
		var band_y := base_y + float(band) * area.y * 0.045
		var phase := _time * (0.18 + float(band) * 0.018) + float(band) * 0.9
		for step in 34:
			var t := float(step) / 33.0
			var x := lerpf(-area.x * 0.12, area.x * 1.12, t)
			var wave := sin(t * TAU * 1.25 + phase) * area.y * 0.030
			var slow_wave := sin(t * TAU * 0.55 - phase * 0.72) * area.y * 0.020
			points.append(Vector2(x, band_y + wave + slow_wave))
		draw_polyline(points, Color(color.r, color.g, color.b, 0.115), width, true)
		draw_polyline(points, Color(1.0, 1.0, 1.0, 0.026), maxf(2.0, width * 0.18), true)

func _draw_lower_glow(area: Vector2) -> void:
	for i in 12:
		var t := float(i) / 11.0
		var y := lerpf(area.y * 0.66, area.y, t)
		var alpha := 0.048 * (1.0 - t)
		draw_rect(Rect2(0.0, y, area.x, area.y * 0.035 + 2.0),
				Color(0.08, 0.30, 0.43, alpha), true)
	for i in 7:
		var y := area.y * (0.78 + float(i) * 0.026)
		var alpha := 0.020 + 0.010 * sin(_time * 0.7 + float(i))
		draw_line(Vector2(area.x * 0.08, y), Vector2(area.x * 0.92, y + sin(float(i)) * 12.0),
				Color(0.85, 0.95, 1.0, alpha), 1.5, true)

func _draw_vignette(area: Vector2) -> void:
	var strips := 18
	for i in strips:
		var t := float(i) / float(strips)
		var alpha := pow(1.0 - t, 2.2) * 0.24
		var inset := t * 72.0
		draw_rect(Rect2(inset, inset, area.x - inset * 2.0, 4.0), Color(0, 0, 0, alpha), true)
		draw_rect(Rect2(inset, area.y - inset - 4.0, area.x - inset * 2.0, 4.0), Color(0, 0, 0, alpha), true)
		draw_rect(Rect2(inset, inset, 4.0, area.y - inset * 2.0), Color(0, 0, 0, alpha), true)
		draw_rect(Rect2(area.x - inset - 4.0, inset, 4.0, area.y - inset * 2.0), Color(0, 0, 0, alpha), true)
