extends Control

const FALLBACK_COLORS := [
	Color(0.98, 0.16, 0.25),
	Color(1.00, 0.58, 0.12),
	Color(0.98, 0.86, 0.16),
	Color(0.20, 0.82, 0.36),
	Color(0.12, 0.62, 1.00),
	Color(0.56, 0.28, 1.00),
	Color(0.98, 0.24, 0.82),
]

var phase_offset := 0.0
var intensity := 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 8
	set_process(true)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if size.x < 24.0 or size.y < 24.0:
		return
	var short_side := minf(size.x, size.y)
	var line_width := clampf(short_side * 0.034, 4.0, 8.0)
	var glow_width := line_width + clampf(short_side * 0.035, 5.0, 9.0)
	var inset := glow_width * 0.52
	var rect := Rect2(Vector2(inset, inset), size - Vector2(inset * 2.0, inset * 2.0))
	var radius := clampf(short_side * 0.075, 8.0, 16.0)
	var color_shift := Time.get_ticks_msec() / 1000.0 * 1.20 + phase_offset

	_draw_prismatic_rounded_rect(rect, radius, 0.18 * intensity, glow_width, color_shift)
	_draw_prismatic_rounded_rect(rect, radius, 0.92 * intensity, line_width, color_shift)

func _draw_prismatic_rounded_rect(rect: Rect2, radius: float, alpha: float, line_width: float, color_shift: float) -> void:
	var pts := _make_rounded_rect_points(rect, radius)
	if pts.size() < 2:
		return
	var cols := PackedColorArray()
	for i in pts.size():
		var phase := float(i) / float(maxi(1, pts.size() - 1))
		cols.append(_get_prismatic_color(phase, alpha, color_shift))
	draw_polyline_colors(pts, cols, line_width, true)

func _make_rounded_rect_points(rect: Rect2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var end := rect.position + rect.size
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var corner_samples := 8
	var corners := [
		{"center": Vector2(end.x - r, rect.position.y + r), "start": -PI * 0.5, "end": 0.0},
		{"center": Vector2(end.x - r, end.y - r), "start": 0.0, "end": PI * 0.5},
		{"center": Vector2(rect.position.x + r, end.y - r), "start": PI * 0.5, "end": PI},
		{"center": Vector2(rect.position.x + r, rect.position.y + r), "start": PI, "end": PI * 1.5},
	]
	for corner in corners:
		var center := corner["center"] as Vector2
		var start_angle := float(corner["start"])
		var end_angle := float(corner["end"])
		for i in corner_samples + 1:
			var t := float(i) / float(corner_samples)
			var angle := lerpf(start_angle, end_angle, t)
			pts.append(center + Vector2(cos(angle), sin(angle)) * r)
	pts.append(pts[0])
	return pts

func _get_prismatic_color(phase: float, alpha: float, color_shift: float) -> Color:
	var palette := _get_prismatic_palette()
	var color_count := palette.size()
	var color_pos := fmod(phase * float(color_count) + color_shift, float(color_count))
	if color_pos < 0.0:
		color_pos += float(color_count)
	var idx_a := int(floor(color_pos)) % color_count
	var idx_b := (idx_a + 1) % color_count
	var blended := (palette[idx_a] as Color).lerp(palette[idx_b] as Color, fmod(color_pos, 1.0))
	return Color(blended.r, blended.g, blended.b, alpha)

func _get_prismatic_palette() -> Array:
	if GameSettings and GameSettings.has_method("get_liquid_colors"):
		var colors := GameSettings.get_liquid_colors()
		if colors.size() >= 4:
			var color_steps := mini(maxi(GameSettings.filled_beakers, 4), mini(colors.size(), 8))
			var palette := []
			for i in color_steps:
				palette.append(colors[i])
			return palette
	return FALLBACK_COLORS
