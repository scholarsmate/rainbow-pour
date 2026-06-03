extends Node2D

signal disk_moved

const BEAKERS_PER_ROW = 4
const BEAKER_COUNT    = 8
const EMPTY_BEAKERS   = 2
const FILLED_BEAKERS  = BEAKER_COUNT - EMPTY_BEAKERS
const WALL            = 5

var beaker_capacity:    int   = 4
var liquid_unit_height: int   = 40
var beaker_width:       int   = 80
var beaker_height:      int   = 180

var beakers:          Array = []
var beaker_positions: Array = []
var selected_beaker:  int   = -1
var _vis_fill:        Array = []
var _is_animating:    bool  = false
var _anim_src:        int   = -1
var _anim_src_snap:   Array = []
var _time:            float = 0.0
var _particles:       Array = []

var liquid_colors: Array = [
	Color(0.95, 0.18, 0.18),
	Color(1.00, 0.52, 0.04),
	Color(0.94, 0.82, 0.04),
	Color(0.06, 0.84, 0.30),
	Color(0.15, 0.50, 1.00),
	Color(0.72, 0.18, 0.98),
]

func _ready():
	_apply_capacity()
	setup_beaker_positions()
	generate_puzzle()

func _apply_capacity():
	beaker_capacity    = GameSettings.beaker_capacity
	# Scale unit height so both rows always fit on screen
	# Available vertical space between top UI (~85px) and bottom UI (~650px) = 565px
	# Two rows + 30px gap => each row bucket = (565 - 30) / 2 = 267px
	# Leave 20px headroom above liquid => unit_h = (267 - 20) / capacity
	var max_unit := int((565 - 30) / 2 - 20) / beaker_capacity
	liquid_unit_height = clampi(max_unit, 18, 40)
	beaker_height      = beaker_capacity * liquid_unit_height
	# Wider beakers for smaller capacities (more slots = less width needed per visual)
	beaker_width = clampi(100 - (beaker_capacity - 4) * 4, 68, 100)

func _process(delta: float):
	_time += delta
	var dirty := selected_beaker >= 0 or _is_animating
	for pt in _particles:
		pt["vel"] += Vector2(0, 520.0 * delta)
		pt["pos"] += pt["vel"] * delta
		pt["life"] -= delta
		pt["alpha"] = maxf(0.0, pt["life"] / pt["max_life"])
		dirty = true
	_particles = _particles.filter(func(pt): return pt["life"] > 0.0)
	if dirty:
		queue_redraw()

func setup_beaker_positions():
	beaker_positions.clear()
	var spacing_x := 240.0
	var sx        := (1280.0 - (BEAKERS_PER_ROW - 1) * spacing_x) / 2.0
	# Center each row vertically in its half of the available play area
	var avail     := 565.0
	var row_slot  := (avail - 30.0) / 2.0
	var base1     := 85.0 + row_slot / 2.0 + float(beaker_height) / 2.0
	var base2     := 85.0 + row_slot + 30.0 + row_slot / 2.0 + float(beaker_height) / 2.0
	for row in 2:
		for col in BEAKERS_PER_ROW:
			beaker_positions.append(Vector2(sx + col * spacing_x, [base1, base2][row]))

func generate_puzzle():
	beakers.clear()
	_particles.clear()
	_anim_src = -1
	_anim_src_snap.clear()
	var pool: Array = []
	for i in FILLED_BEAKERS:
		for j in beaker_capacity:
			pool.append(i)
	pool.shuffle()
	for i in FILLED_BEAKERS:
		var b := []
		for j in beaker_capacity:
			b.append(pool[i * beaker_capacity + j])
		beakers.append(b)
	for k in EMPTY_BEAKERS:
		beakers.append([])
	_vis_fill.resize(BEAKER_COUNT)
	for i in BEAKER_COUNT:
		_vis_fill[i] = float(beakers[i].size())
	if check_complete():
		generate_puzzle()
		return
	queue_redraw()

func can_pour(src: int, dst: int) -> bool:
	if beakers[src].is_empty():
		return false
	if beakers[dst].size() >= beaker_capacity:
		return false
	if beakers[dst].is_empty():
		return true
	return beakers[src].back() == beakers[dst].back()

func pour(src: int, dst: int):
	var old_src := float(beakers[src].size())
	var old_dst := float(beakers[dst].size())
	_anim_src      = src
	_anim_src_snap = beakers[src].duplicate()
	var top = beakers[src].back()
	while not beakers[src].is_empty() and beakers[src].back() == top and beakers[dst].size() < beaker_capacity:
		beakers[dst].append(beakers[src].pop_back())
	if AudioManager:
		AudioManager.play_pour()
	_is_animating = true
	var tw := create_tween().set_parallel()
	var src_tweener := tw.tween_method(_set_vis.bind(src), old_src, float(beakers[src].size()), 0.38)
	src_tweener.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var dst_tweener := tw.tween_method(_set_vis.bind(dst), old_dst, float(beakers[dst].size()), 0.38)
	dst_tweener.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	var on_done := func():
		_anim_src = -1
		_anim_src_snap.clear()
		_is_animating = false
		emit_signal("disk_moved")
		if check_complete():
			_celebrate()
	tw.chain().tween_callback(on_done)

func _set_vis(v: float, idx: int) -> void:
	_vis_fill[idx] = v
	queue_redraw()

func check_complete() -> bool:
	for b in beakers:
		if b.is_empty():
			continue
		if b.size() != beaker_capacity:
			return false
		var c = b[0]
		for u in b:
			if u != c:
				return false
	return true

func reset():
	selected_beaker = -1
	_is_animating   = false
	_anim_src       = -1
	_anim_src_snap.clear()
	_particles.clear()
	_apply_capacity()
	setup_beaker_positions()
	generate_puzzle()

func _input(event: InputEvent):
	if _is_animating:
		return
	if not (event is InputEventMouseButton):
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var idx := _beaker_at(event.position)
	if idx >= 0:
		_handle_click(idx)

func _beaker_at(pos: Vector2) -> int:
	for i in BEAKER_COUNT:
		var bp: Vector2 = beaker_positions[i]
		if (abs(pos.x - bp.x) <= beaker_width / 2.0 + 12
				and pos.y >= bp.y - beaker_height - 12
				and pos.y <= bp.y + 12):
			return i
	return -1

func _handle_click(idx: int):
	if selected_beaker < 0:
		if not beakers[idx].is_empty():
			selected_beaker = idx
			if AudioManager:
				AudioManager.play_select()
			queue_redraw()
	else:
		if selected_beaker == idx:
			selected_beaker = -1
			queue_redraw()
			return
		if can_pour(selected_beaker, idx):
			pour(selected_beaker, idx)
			selected_beaker = -1
		else:
			if AudioManager:
				AudioManager.play_invalid()
			if not beakers[idx].is_empty():
				selected_beaker = idx
			else:
				selected_beaker = -1
			queue_redraw()

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw():
	_draw_bg()
	for i in BEAKER_COUNT:
		_draw_beaker(i)
	for pt in _particles:
		draw_circle(pt["pos"], pt["radius"],
				Color(pt["color"].r, pt["color"].g, pt["color"].b, pt["alpha"]))

func _draw_bg():
	for i in range(10, 0, -1):
		draw_circle(Vector2(640, 360), float(i) * 72.0,
				Color(0.15, 0.25, 0.45, float(i) / 10.0 * 0.025))

func _draw_cylinder_rect(x: float, y: float, w: float, h: float, col: Color):
	# Simulate a cylindrical surface: dark edges, bright centre
	var cx    := x + w * 0.5
	var dim   := col.darkened(0.42)
	var mid   := col.lightened(0.18)
	# Left half: dim -> mid
	draw_polygon(
		PackedVector2Array([Vector2(x,y), Vector2(cx,y), Vector2(cx,y+h), Vector2(x,y+h)]),
		PackedColorArray([dim, mid, mid, dim])
	)
	# Right half: mid -> dim
	draw_polygon(
		PackedVector2Array([Vector2(cx,y), Vector2(x+w,y), Vector2(x+w,y+h), Vector2(cx,y+h)]),
		PackedColorArray([mid, dim, dim, mid])
	)
	# Bright specular highlight strip (left ~15% width)
	var hl_w := maxf(4.0, w * 0.14)
	draw_polygon(
		PackedVector2Array([Vector2(x+2, y), Vector2(x+2+hl_w, y), Vector2(x+2+hl_w, y+h), Vector2(x+2, y+h)]),
		PackedColorArray([
			Color(1,1,1, 0.28), Color(1,1,1, 0.0),
			Color(1,1,1, 0.0),  Color(1,1,1, 0.28)
		])
	)

func _draw_beaker(idx: int):
	var pos:  Vector2 = beaker_positions[idx]
	var hw   := float(beaker_width) / 2.0
	var bh   := float(beaker_height)
	var isel := (idx == selected_beaker)

	# --- Pulsing selection glow ---
	if isel:
		var pulse := 0.18 + 0.10 * sin(_time * 7.0)
		draw_rect(Rect2(pos.x - hw - 10, pos.y - bh - 10,
				float(beaker_width) + 20.0, bh + 20.0),
				Color(1.0, 0.95, 0.15, pulse), true)

	# --- Glass interior background (dark tint inside tube) ---
	var inner_x := pos.x - hw + WALL
	var inner_w := float(beaker_width) - WALL * 2.0
	draw_rect(Rect2(inner_x, pos.y - bh, inner_w, bh), Color(0, 0, 0, 0.28), true)

	# --- Liquid segments ---
	var color_data: Array
	if idx == _anim_src and _is_animating:
		color_data = _anim_src_snap
	else:
		color_data = beakers[idx]
	var vis: float = _vis_fill[idx]
	for ui in color_data.size():
		var f0 := float(ui)
		var f1 := minf(float(ui + 1), vis)
		if f1 <= f0:
			break
		var col: Color = liquid_colors[color_data[ui]]
		var h   := (f1 - f0) * float(liquid_unit_height)
		var ly  := pos.y - f1 * float(liquid_unit_height)
		_draw_cylinder_rect(inner_x, ly, inner_w, h, col)
		# Shimmer line at top of each full segment
		if f1 >= float(ui + 1) - 0.01:
			draw_rect(Rect2(inner_x + 2, ly, inner_w - 4, 3),
					Color(1.0, 1.0, 1.0, 0.30), true)

	# --- Glass tube walls ---
	# Main wall body with a subtle inner gradient (left bright, right slightly dim)
	var glass_base := Color(0.62, 0.80, 1.0, 0.82)
	var glass_dim  := Color(0.42, 0.62, 0.85, 0.82)
	# Left wall
	draw_polygon(
		PackedVector2Array([
			Vector2(pos.x - hw,          pos.y - bh),
			Vector2(pos.x - hw + WALL,   pos.y - bh),
			Vector2(pos.x - hw + WALL,   pos.y),
			Vector2(pos.x - hw,          pos.y)
		]),
		PackedColorArray([glass_base, glass_dim, glass_dim, glass_base])
	)
	# Right wall
	draw_polygon(
		PackedVector2Array([
			Vector2(pos.x + hw - WALL,   pos.y - bh),
			Vector2(pos.x + hw,          pos.y - bh),
			Vector2(pos.x + hw,          pos.y),
			Vector2(pos.x + hw - WALL,   pos.y)
		]),
		PackedColorArray([glass_dim, glass_base, glass_base, glass_dim])
	)
	# Bottom wall
	draw_rect(Rect2(pos.x - hw, pos.y - WALL, float(beaker_width), WALL), glass_base, true)

	# Rounded bottom cap illusion: dark ellipse inside bottom
	_draw_ellipse_filled(Vector2(pos.x, pos.y - WALL / 2.0),
			Vector2(inner_w / 2.0, 5.0), Color(0, 0, 0, 0.35))

	# --- Glass rim (top opening lip) ---
	draw_rect(Rect2(pos.x - hw, pos.y - bh - 3, float(beaker_width), 3),
			Color(0.85, 0.95, 1.0, 0.70), true)

	# --- Inner reflection strip on left wall ---
	draw_rect(Rect2(pos.x - hw + WALL, pos.y - bh, 3, bh),
			Color(1, 1, 1, 0.18), true)

func _draw_ellipse_filled(center: Vector2, radii: Vector2, col: Color):
	var pts  := PackedVector2Array()
	var cols := PackedColorArray()
	var steps := 18
	for i in steps:
		var a := TAU * float(i) / float(steps)
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
		cols.append(col)
	draw_polygon(pts, cols)

# ---------------------------------------------------------------------------
# Win celebration
# ---------------------------------------------------------------------------

func _celebrate():
	for n in 70:
		var bp: Vector2 = beaker_positions[randi() % BEAKER_COUNT]
		var ml := randf_range(0.8, 2.2)
		_particles.append({
			"pos":      bp + Vector2(randf_range(-35, 35), randf_range(-float(beaker_height) * 0.9, -5.0)),
			"vel":      Vector2(randf_range(-240, 240), randf_range(-450, -60)),
			"color":    liquid_colors[randi() % liquid_colors.size()],
			"radius":   randf_range(4.0, 13.0),
			"life":     ml,
			"max_life": ml,
			"alpha":    1.0,
		})
