extends Node2D

signal disk_moved
signal goal_changed(optimal_pours: int)
signal no_moves_available
signal cheat_applied(cheat_type: String)
signal cheat_cancelled

const WALL = 5
const PLAY_TOP = 145.0
const PLAY_BOTTOM = 650.0
const OPTIMAL_SOLVER_CALCULATING = -2
const SOLVER_NODE_LIMIT = 750000
const SOLVER_STEPS_PER_FRAME = 900
const FINISHED_BEAKER_PULSE_TIME = 1.25
const BOARD_CODE_PREFIX := "RP1"
const BOARD_CODE_ALPHABET := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"

var beaker_capacity:    int   = 4
var beaker_count:       int   = 8
var empty_beakers:      int   = 2
var filled_beakers:     int   = 6
var beakers_per_row:    int   = 4
var optimal_pours:      int   = -1
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
var _undo_beakers:    Array = []
var _undo_vis_fill:   Array = []
var _starting_beakers: Array = []
var _solver_active:   bool  = false
var _solver_queue:    Array = []
var _solver_depths:   Array = []
var _solver_visited:  Dictionary = {}
var _solver_front:    int   = 0
var _solver_searched: int   = 0
var _time:            float = 0.0
var _particles:       Array = []
var _finished_beakers: Array = []
var _finish_pulses:   Array = []
var _press_beaker:    int   = -1
var _press_position:  Vector2 = Vector2.ZERO
var _press_had_selection: bool = false
var _dragging:        bool  = false
var _drag_pos:        Vector2 = Vector2.ZERO
var _drag_hover:      int   = -1
var _cheat_mode:      String = ""
var _cheat_swap_beaker: int = -1
var _cheat_swap_segment: int = -1

func _ready():
	_apply_capacity()
	setup_beaker_positions()
	generate_puzzle()

func _apply_capacity():
	beaker_capacity    = GameSettings.beaker_capacity
	beaker_count       = GameSettings.get_beaker_count()
	empty_beakers      = GameSettings.get_empty_beaker_count()
	filled_beakers     = GameSettings.get_filled_beaker_count()
	beakers_per_row    = int(ceil(float(beaker_count) / 2.0))
	_recalculate_beaker_dimensions()

func _recalculate_beaker_dimensions() -> void:
	# Scale unit height so both rows always fit on screen
	# Available vertical space leaves room for settings/goal UI above the board.
	var play_height := PLAY_BOTTOM - PLAY_TOP
	# Leave 20px headroom above each row's liquid.
	var max_unit := int(((play_height - 30.0) / 2.0 - 20.0) / float(beaker_capacity))
	liquid_unit_height = clampi(max_unit, 18, 40)
	beaker_height      = beaker_capacity * liquid_unit_height
	# Wider beakers for smaller capacities (more slots = less width needed per visual)
	beaker_width = clampi(100 - (beaker_capacity - 4) * 4, 68, 100)

func _process(delta: float):
	_time += delta
	if _solver_active:
		_process_optimal_solver(SOLVER_STEPS_PER_FRAME)
	var dirty := selected_beaker >= 0 or _is_animating or _dragging or _has_finished_beakers()
	for i in _finish_pulses.size():
		if float(_finish_pulses[i]) <= 0.0:
			continue
		_finish_pulses[i] = maxf(0.0, float(_finish_pulses[i]) - delta)
		dirty = true
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
	var spacing_x := clampf(960.0 / maxf(float(beakers_per_row - 1), 1.0), 200.0, 240.0)
	var sx        := (1280.0 - float(beakers_per_row - 1) * spacing_x) / 2.0
	# Center each row vertically in its half of the available play area
	var avail     := PLAY_BOTTOM - PLAY_TOP
	var row_slot  := (avail - 30.0) / 2.0
	var base1     := PLAY_TOP + row_slot / 2.0 + float(beaker_height) / 2.0
	var base2     := PLAY_TOP + row_slot + 30.0 + row_slot / 2.0 + float(beaker_height) / 2.0
	for row in 2:
		for col in beakers_per_row:
			if beaker_positions.size() >= beaker_count:
				return
			beaker_positions.append(Vector2(sx + col * spacing_x, [base1, base2][row]))

func generate_puzzle():
	beakers.clear()
	_particles.clear()
	_anim_src = -1
	_anim_src_snap.clear()
	_clear_pointer_state()
	_clear_undo_state()
	_cancel_cheat_state()
	_reset_finish_state()
	var pool: Array = []
	for i in filled_beakers:
		for j in beaker_capacity:
			pool.append(i)
	pool.shuffle()
	for i in filled_beakers:
		var b := []
		for j in beaker_capacity:
			b.append(pool[i * beaker_capacity + j])
		beakers.append(b)
	for k in empty_beakers:
		beakers.append([])
	_vis_fill.resize(beaker_count)
	for i in beaker_count:
		_vis_fill[i] = float(beakers[i].size())
	if check_complete():
		generate_puzzle()
		return
	_sync_finished_beakers(false)
	_starting_beakers = _copy_state(beakers)
	_start_optimal_solver(_starting_beakers)
	queue_redraw()

func can_pour(src: int, dst: int) -> bool:
	if src < 0 or src >= beaker_count or dst < 0 or dst >= beaker_count:
		return false
	if src == dst:
		return false
	if beakers[src].is_empty():
		return false
	if _is_beaker_complete(src):
		return false
	if beakers[dst].size() >= beaker_capacity:
		return false
	if beakers[dst].is_empty():
		return true
	return beakers[src].back() == beakers[dst].back()

func pour(src: int, dst: int):
	_store_undo_state()
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
		_sync_finished_beakers(true)
		var complete := check_complete()
		emit_signal("disk_moved")
		if complete:
			_celebrate()
		elif not has_available_moves():
			emit_signal("no_moves_available")
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

func _is_beaker_complete(idx: int) -> bool:
	if idx < 0 or idx >= beaker_count:
		return false
	var b: Array = beakers[idx]
	if b.size() != beaker_capacity:
		return false
	var c = b[0]
	for u in b:
		if u != c:
			return false
	return true

func _reset_finish_state() -> void:
	_finished_beakers.clear()
	_finish_pulses.clear()
	for i in beaker_count:
		_finished_beakers.append(false)
		_finish_pulses.append(0.0)

func _sync_finished_beakers(trigger_effects: bool) -> void:
	if _finished_beakers.size() != beaker_count or _finish_pulses.size() != beaker_count:
		_reset_finish_state()
	for i in beaker_count:
		var was_finished := bool(_finished_beakers[i])
		var is_finished := _is_beaker_complete(i)
		_finished_beakers[i] = is_finished
		if trigger_effects and is_finished and not was_finished:
			_trigger_finished_beaker_effect(i)

func _has_finished_beakers() -> bool:
	for finished in _finished_beakers:
		if bool(finished):
			return true
	return false

func _get_finish_pulse(idx: int) -> float:
	if idx < 0 or idx >= _finish_pulses.size():
		return 0.0
	return float(_finish_pulses[idx]) / FINISHED_BEAKER_PULSE_TIME

func _trigger_finished_beaker_effect(idx: int) -> void:
	_finish_pulses[idx] = FINISHED_BEAKER_PULSE_TIME
	var pos: Vector2 = beaker_positions[idx]
	var color_idx: int = int(beakers[idx][0])
	var base_color: Color = _get_liquid_color(color_idx)
	for n in 28:
		var ml := randf_range(0.55, 1.10)
		var angle := TAU * float(n) / 28.0 + randf_range(-0.12, 0.12)
		var rim_offset := Vector2(cos(angle) * randf_range(18.0, float(beaker_width) * 0.58), randf_range(-10.0, 8.0))
		_particles.append({
			"pos":      pos + Vector2(0, -float(beaker_height) - 4.0) + rim_offset,
			"vel":      Vector2(cos(angle) * randf_range(80.0, 180.0), randf_range(-250.0, -90.0)),
			"color":    base_color.lightened(randf_range(0.18, 0.45)),
			"radius":   randf_range(3.0, 8.0),
			"life":     ml,
			"max_life": ml,
			"alpha":    1.0,
		})
	queue_redraw()

func has_available_moves() -> bool:
	return count_available_moves() > 0

func count_available_moves() -> int:
	var count := 0
	for src in beaker_count:
		for dst in beaker_count:
			if can_pour(src, dst):
				count += 1
	return count

func get_possible_destinations(src: int) -> Array:
	var destinations := []
	for dst in beaker_count:
		if can_pour(src, dst):
			destinations.append(dst)
	return destinations

func get_board_signature() -> String:
	return _encode_exact_state(beakers)

func export_board_code() -> String:
	var encoded_tubes := PackedStringArray()
	for b in beakers:
		var encoded := ""
		for color in b:
			encoded += _encode_board_digit(int(color))
		encoded_tubes.append(encoded)
	return "%s%s%s%s:%s" % [
		BOARD_CODE_PREFIX,
		_encode_board_digit(beaker_capacity),
		_encode_board_digit(filled_beakers),
		_encode_board_digit(empty_beakers),
		".".join(encoded_tubes),
	]

func import_board_code(raw_code: String) -> bool:
	var code := raw_code.strip_edges()
	if not code.begins_with(BOARD_CODE_PREFIX):
		return false
	var payload := code.substr(BOARD_CODE_PREFIX.length())
	if payload.length() < 4 or payload.substr(3, 1) != ":":
		return false

	var imported_capacity := _decode_board_digit(payload.substr(0, 1))
	var imported_filled := _decode_board_digit(payload.substr(1, 1))
	var imported_empty := _decode_board_digit(payload.substr(2, 1))
	if imported_capacity < GameSettings.CAPACITY_MIN or imported_capacity > GameSettings.CAPACITY_MAX:
		return false
	if imported_filled <= 0 or imported_empty <= 0:
		return false
	var imported_count := imported_filled + imported_empty
	var tube_parts := payload.substr(4).split(".", true)
	if tube_parts.size() != imported_count:
		return false

	var imported_beakers := []
	for tube_text in tube_parts:
		if tube_text.length() > imported_capacity:
			return false
		var tube := []
		for i in tube_text.length():
			var color_idx := _decode_board_digit(tube_text.substr(i, 1))
			if color_idx < 0 or color_idx >= imported_filled:
				return false
			tube.append(color_idx)
		imported_beakers.append(tube)

	var difficulty_key := GameSettings.find_difficulty_for_counts(imported_filled, imported_empty)
	if difficulty_key != "":
		GameSettings.set_difficulty(difficulty_key)
	GameSettings.set_beaker_capacity(imported_capacity)

	beaker_capacity = imported_capacity
	filled_beakers = imported_filled
	empty_beakers = imported_empty
	beaker_count = imported_count
	beakers_per_row = int(ceil(float(beaker_count) / 2.0))
	_recalculate_beaker_dimensions()
	beakers = imported_beakers
	_vis_fill.resize(beaker_count)
	for i in beaker_count:
		_vis_fill[i] = float(beakers[i].size())
	selected_beaker = -1
	_is_animating = false
	_anim_src = -1
	_anim_src_snap.clear()
	_particles.clear()
	_clear_pointer_state()
	_clear_undo_state()
	_cancel_cheat_state()
	_reset_finish_state()
	setup_beaker_positions()
	_sync_finished_beakers(false)
	_starting_beakers = _copy_state(beakers)
	_start_optimal_solver(beakers)
	queue_redraw()
	return true

func has_usable_stir_cheat() -> bool:
	if _is_animating or check_complete():
		return false
	for idx in beaker_count:
		if _can_stir_beaker(idx):
			return true
	return false

func has_usable_swap_cheat() -> bool:
	if _is_animating or check_complete():
		return false
	for idx in beaker_count:
		var b: Array = beakers[idx]
		for segment in maxi(0, b.size() - 1):
			if b[segment] != b[segment + 1]:
				return true
	return false

func begin_stir_cheat() -> bool:
	if not has_usable_stir_cheat():
		return false
	_cheat_mode = "stir"
	_cheat_swap_beaker = -1
	_cheat_swap_segment = -1
	selected_beaker = -1
	_clear_pointer_state()
	queue_redraw()
	return true

func begin_swap_cheat() -> bool:
	if not has_usable_swap_cheat():
		return false
	_cheat_mode = "swap"
	_cheat_swap_beaker = -1
	_cheat_swap_segment = -1
	selected_beaker = -1
	_clear_pointer_state()
	queue_redraw()
	return true

func is_choosing_cheat() -> bool:
	return _cheat_mode != ""

func cancel_cheat(emit_event: bool = true) -> void:
	if _cheat_mode == "":
		return
	_cancel_cheat_state()
	queue_redraw()
	if emit_event:
		emit_signal("cheat_cancelled")

func can_undo_last_pour() -> bool:
	return not _is_animating and not _undo_beakers.is_empty()

func undo_last_pour() -> bool:
	if not can_undo_last_pour():
		return false
	beakers = _copy_state(_undo_beakers)
	_vis_fill = _undo_vis_fill.duplicate()
	selected_beaker = -1
	_is_animating = false
	_anim_src = -1
	_anim_src_snap.clear()
	_particles.clear()
	_clear_pointer_state()
	_clear_undo_state()
	_cancel_cheat_state()
	_reset_finish_state()
	_sync_finished_beakers(false)
	queue_redraw()
	return true

func retry_current_puzzle() -> bool:
	if _starting_beakers.is_empty():
		return false
	beakers = _copy_state(_starting_beakers)
	_vis_fill.resize(beaker_count)
	for i in beaker_count:
		_vis_fill[i] = float(beakers[i].size())
	selected_beaker = -1
	_is_animating = false
	_anim_src = -1
	_anim_src_snap.clear()
	_particles.clear()
	_clear_pointer_state()
	_clear_undo_state()
	_cancel_cheat_state()
	_reset_finish_state()
	_sync_finished_beakers(false)
	_start_optimal_solver(_starting_beakers)
	queue_redraw()
	return true

func reset():
	selected_beaker = -1
	_is_animating   = false
	_anim_src       = -1
	_anim_src_snap.clear()
	_particles.clear()
	_clear_pointer_state()
	_clear_undo_state()
	_cancel_cheat_state()
	_reset_finish_state()
	_apply_capacity()
	setup_beaker_positions()
	generate_puzzle()

func _store_undo_state():
	_undo_beakers = _copy_state(beakers)
	_undo_vis_fill = _vis_fill.duplicate()

func _clear_undo_state():
	_undo_beakers.clear()
	_undo_vis_fill.clear()

func _cancel_cheat_state() -> void:
	_cheat_mode = ""
	_cheat_swap_beaker = -1
	_cheat_swap_segment = -1

func _can_stir_beaker(idx: int) -> bool:
	if idx < 0 or idx >= beaker_count:
		return false
	var b: Array = beakers[idx]
	if b.size() < 2:
		return false
	var first = b[0]
	for color in b:
		if color != first:
			return true
	return false

func _stir_beaker(idx: int) -> bool:
	if not _can_stir_beaker(idx):
		return false
	_store_undo_state()
	var before: Array = beakers[idx].duplicate()
	var stirred: Array = before.duplicate()
	for attempt in 12:
		stirred.shuffle()
		if _tube_key(stirred) != _tube_key(before):
			break
	if _tube_key(stirred) == _tube_key(before):
		stirred.reverse()
	beakers[idx] = stirred
	_finish_cheat("stir")
	return true

func _can_swap_segments(idx: int, first_segment: int, second_segment: int) -> bool:
	if idx < 0 or idx >= beaker_count:
		return false
	var b: Array = beakers[idx]
	if first_segment < 0 or second_segment < 0:
		return false
	if first_segment >= b.size() or second_segment >= b.size():
		return false
	if abs(first_segment - second_segment) != 1:
		return false
	return b[first_segment] != b[second_segment]

func _swap_segments(idx: int, first_segment: int, second_segment: int) -> bool:
	if not _can_swap_segments(idx, first_segment, second_segment):
		return false
	_store_undo_state()
	var b: Array = beakers[idx]
	var tmp = b[first_segment]
	b[first_segment] = b[second_segment]
	b[second_segment] = tmp
	_finish_cheat("swap")
	return true

func _finish_cheat(cheat_type: String) -> void:
	_cancel_cheat_state()
	selected_beaker = -1
	_is_animating = false
	_anim_src = -1
	_anim_src_snap.clear()
	_particles.clear()
	_clear_pointer_state()
	_clear_undo_state()
	_vis_fill.resize(beaker_count)
	for i in beaker_count:
		_vis_fill[i] = float(beakers[i].size())
	_reset_finish_state()
	_sync_finished_beakers(true)
	_start_optimal_solver(beakers)
	queue_redraw()
	emit_signal("cheat_applied", cheat_type)

# ---------------------------------------------------------------------------
# Solver
# ---------------------------------------------------------------------------

func _start_optimal_solver(state: Array):
	var start := _copy_state(state)
	if _state_complete(start):
		_finish_optimal_solver(0)
		return

	var start_key := _encode_state(start)
	_solver_queue = [start]
	_solver_depths = [0]
	_solver_visited = {start_key: true}
	_solver_front = 0
	_solver_searched = 0
	_solver_active = true
	optimal_pours = OPTIMAL_SOLVER_CALCULATING
	emit_signal("goal_changed", optimal_pours)

func _process_optimal_solver(max_steps: int):
	var processed := 0
	while _solver_active and processed < max_steps:
		if _solver_front >= _solver_queue.size():
			_finish_optimal_solver(-1)
			return
		if _solver_searched >= SOLVER_NODE_LIMIT:
			_finish_optimal_solver(-1)
			return

		var state: Array = _solver_queue[_solver_front]
		var depth: int = _solver_depths[_solver_front]
		_solver_queue[_solver_front] = null
		_solver_front += 1
		_solver_searched += 1
		processed += 1

		var seen_sources := {}
		for src in state.size():
			var from: Array = state[src]
			if from.is_empty() or _state_tube_complete(from):
				continue
			var source_key := _tube_key(from)
			if seen_sources.has(source_key):
				continue
			seen_sources[source_key] = true

			var seen_destinations := {}
			var used_empty_destination := false
			for dst in state.size():
				if src == dst:
					continue
				var to: Array = state[dst]
				if to.is_empty():
					if used_empty_destination or _state_tube_uniform(from):
						continue
					used_empty_destination = true
				else:
					var destination_key := _tube_key(to)
					if seen_destinations.has(destination_key):
						continue
					seen_destinations[destination_key] = true

				if not _state_can_pour(state, src, dst):
					continue
				var next := _state_after_pour(state, src, dst)
				var key := _encode_state(next)
				if _solver_visited.has(key):
					continue
				if _state_complete(next):
					_finish_optimal_solver(depth + 1)
					return
				_solver_visited[key] = true
				_solver_queue.append(next)
				_solver_depths.append(depth + 1)

func _finish_optimal_solver(result: int):
	_solver_active = false
	_solver_queue.clear()
	_solver_depths.clear()
	_solver_visited.clear()
	_solver_front = 0
	_solver_searched = 0
	optimal_pours = result
	emit_signal("goal_changed", optimal_pours)

func _copy_state(state: Array) -> Array:
	var copy := []
	for b in state:
		copy.append(b.duplicate())
	return copy

func _state_can_pour(state: Array, src: int, dst: int) -> bool:
	if src == dst:
		return false
	var from: Array = state[src]
	var to: Array = state[dst]
	if from.is_empty():
		return false
	if to.size() >= beaker_capacity:
		return false
	if to.is_empty():
		return true
	return from.back() == to.back()

func _state_tube_complete(tube: Array) -> bool:
	return tube.size() == beaker_capacity and _state_tube_uniform(tube)

func _state_tube_uniform(tube: Array) -> bool:
	if tube.is_empty():
		return true
	var c = tube[0]
	for color in tube:
		if color != c:
			return false
	return true

func _tube_key(tube: Array) -> String:
	var colors := PackedStringArray()
	for color in tube:
		colors.append(str(int(color)))
	return ",".join(colors)

func _state_after_pour(state: Array, src: int, dst: int) -> Array:
	var next := _copy_state(state)
	var from: Array = next[src]
	var to: Array = next[dst]
	var top = from.back()
	while not from.is_empty() and from.back() == top and to.size() < beaker_capacity:
		to.append(from.pop_back())
	return next

func _state_complete(state: Array) -> bool:
	for b in state:
		if b.is_empty():
			continue
		if b.size() != beaker_capacity:
			return false
		var c = b[0]
		for u in b:
			if u != c:
				return false
	return true

func _encode_state(state: Array) -> String:
	var tubes := PackedStringArray()
	for b in state:
		var colors := PackedStringArray()
		for color in b:
			colors.append(str(int(color)))
		tubes.append(",".join(colors))
	tubes.sort()
	return "|".join(tubes)

func _encode_exact_state(state: Array) -> String:
	var tubes := PackedStringArray()
	for b in state:
		var colors := PackedStringArray()
		for color in b:
			colors.append(str(int(color)))
		tubes.append(",".join(colors))
	return "|".join(tubes)

func _encode_board_digit(value: int) -> String:
	if value < 0 or value >= BOARD_CODE_ALPHABET.length():
		return "?"
	return BOARD_CODE_ALPHABET.substr(value, 1)

func _decode_board_digit(ch: String) -> int:
	if ch.length() != 1:
		return -1
	return BOARD_CODE_ALPHABET.find(ch)

func _input(event: InputEvent):
	if _is_animating:
		return
	if _cheat_mode != "":
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_handle_cheat_input(event.position)
			get_viewport().set_input_as_handled()
		elif event is InputEventScreenTouch and event.pressed:
			_handle_cheat_input(event.position)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_pointer(event.position)
		else:
			_finish_pointer(event.position)
	elif event is InputEventMouseMotion:
		_update_pointer(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_begin_pointer(event.position)
		else:
			_finish_pointer(event.position)
	elif event is InputEventScreenDrag:
		_update_pointer(event.position)

func _begin_pointer(pos: Vector2) -> void:
	var idx := _beaker_at(pos)
	if idx < 0:
		return
	_press_beaker = idx
	_press_position = pos
	_press_had_selection = selected_beaker >= 0
	_dragging = false
	_drag_pos = pos
	_drag_hover = idx
	if selected_beaker < 0 and not beakers[idx].is_empty() and not _is_beaker_complete(idx):
		selected_beaker = idx
		if AudioManager:
			AudioManager.play_select()
		queue_redraw()

func _update_pointer(pos: Vector2) -> void:
	if _press_beaker < 0:
		return
	_drag_pos = pos
	_drag_hover = _beaker_at(pos)
	if not _dragging and _press_position.distance_to(pos) >= 12.0:
		_dragging = true
	if _dragging:
		queue_redraw()

func _finish_pointer(pos: Vector2) -> void:
	if _press_beaker < 0:
		return
	var release_idx := _beaker_at(pos)
	var was_dragging := _dragging
	if _dragging:
		if selected_beaker == _press_beaker:
			if release_idx >= 0 and release_idx != _press_beaker:
				_resolve_selected_target(release_idx)
			else:
				queue_redraw()
		elif _press_had_selection and release_idx >= 0:
			_resolve_selected_target(release_idx)
	else:
		if _press_had_selection:
			if release_idx >= 0:
				_handle_click(release_idx)
		elif release_idx >= 0 and release_idx != _press_beaker and selected_beaker == _press_beaker:
			_resolve_selected_target(release_idx)
		else:
			queue_redraw()
	_clear_pointer_state()
	if was_dragging and not _is_animating:
		queue_redraw()

func _clear_pointer_state() -> void:
	_press_beaker = -1
	_press_position = Vector2.ZERO
	_press_had_selection = false
	_dragging = false
	_drag_pos = Vector2.ZERO
	_drag_hover = -1

func _handle_cheat_input(pos: Vector2) -> void:
	if _cheat_mode == "stir":
		var idx := _beaker_at(pos)
		if _stir_beaker(idx):
			return
		if AudioManager:
			AudioManager.play_invalid()
		return

	if _cheat_mode != "swap":
		return

	var hit := _segment_at(pos)
	var idx := int(hit["beaker"])
	var segment := int(hit["segment"])
	if idx < 0 or segment < 0:
		if AudioManager:
			AudioManager.play_invalid()
		return

	if _cheat_swap_beaker < 0:
		_cheat_swap_beaker = idx
		_cheat_swap_segment = segment
		if AudioManager:
			AudioManager.play_select()
		queue_redraw()
		return

	if idx == _cheat_swap_beaker and _swap_segments(idx, _cheat_swap_segment, segment):
		return

	if AudioManager:
		AudioManager.play_invalid()
	_cheat_swap_beaker = idx
	_cheat_swap_segment = segment
	queue_redraw()

func _beaker_at(pos: Vector2) -> int:
	for i in beaker_count:
		var bp: Vector2 = beaker_positions[i]
		if (abs(pos.x - bp.x) <= beaker_width / 2.0 + 12
				and pos.y >= bp.y - beaker_height - 12
				and pos.y <= bp.y + 12):
			return i
	return -1

func _segment_at(pos: Vector2) -> Dictionary:
	var idx := _beaker_at(pos)
	if idx < 0:
		return {"beaker": -1, "segment": -1}
	var bp: Vector2 = beaker_positions[idx]
	var segment := int(floor((bp.y - pos.y) / float(liquid_unit_height)))
	if segment < 0 or segment >= beakers[idx].size():
		return {"beaker": -1, "segment": -1}
	return {"beaker": idx, "segment": segment}

func _handle_click(idx: int):
	if selected_beaker < 0:
		if not beakers[idx].is_empty() and not _is_beaker_complete(idx):
			selected_beaker = idx
			if AudioManager:
				AudioManager.play_select()
			queue_redraw()
	else:
		_resolve_selected_target(idx)

func _resolve_selected_target(idx: int) -> void:
	if selected_beaker == idx:
		selected_beaker = -1
		queue_redraw()
		return
	var src := selected_beaker
	if can_pour(src, idx):
		selected_beaker = -1
		pour(src, idx)
	else:
		if AudioManager:
			AudioManager.play_invalid()
		if not beakers[idx].is_empty() and not _is_beaker_complete(idx):
			selected_beaker = idx
		else:
			selected_beaker = -1
		queue_redraw()

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw():
	_draw_bg()
	_draw_drag_path()
	for i in beaker_count:
		_draw_beaker(i)
	for pt in _particles:
		draw_circle(pt["pos"], pt["radius"],
				Color(pt["color"].r, pt["color"].g, pt["color"].b, pt["alpha"]))

func _draw_bg():
	for i in range(10, 0, -1):
		draw_circle(Vector2(640, 360), float(i) * 72.0,
				Color(0.15, 0.25, 0.45, float(i) / 10.0 * 0.025))

func _draw_drag_path():
	if not _dragging or selected_beaker < 0:
		return
	var source: Vector2 = beaker_positions[selected_beaker] + Vector2(0, -float(beaker_height) - 16.0)
	var legal_hover: bool = _drag_hover >= 0 and can_pour(selected_beaker, _drag_hover)
	var pour_color := _get_selected_pour_color()
	var color: Color = Color(pour_color.r, pour_color.g, pour_color.b, 0.74) if legal_hover else Color(1.0, 0.86, 0.18, 0.48)
	draw_line(source, _drag_pos, color, 4.0, true)
	draw_circle(_drag_pos, 10.0, color)
	if legal_hover:
		draw_circle(_drag_pos, 5.0, Color(1.0, 1.0, 1.0, 0.54))

func _draw_cylinder_rect(x: float, y: float, w: float, h: float, col: Color):
	# Simulate a cylindrical surface: dark edges, bright centre
	var liquid_col := Color(col.r, col.g, col.b, _get_liquid_alpha())
	var cx    := x + w * 0.5
	var dim   := liquid_col.darkened(0.42)
	var mid   := liquid_col.lightened(0.18)
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

func _draw_liquid_texture(x: float, y: float, w: float, h: float, color_idx: int, segment_idx: int) -> void:
	if h < 10.0:
		return
	var phase := _time * 3.2 + float(color_idx) * 1.17 + float(segment_idx) * 0.71
	var alpha := 0.075 + 0.035 * maxf(0.0, sin(phase))
	var light := Color(1.0, 1.0, 1.0, alpha)
	var dark := Color(0.0, 0.0, 0.0, alpha * 0.58)
	match color_idx % 5:
		0:
			var step := 10
			var offset := int(fmod(_time * 8.0 + float(color_idx) * 3.0, float(step)))
			for yy in range(int(y) + offset, int(y + h), step):
				draw_line(Vector2(x + 5.0, float(yy)), Vector2(x + w - 5.0, float(yy)), light, 1.0, true)
		1:
			for yy in range(int(y + 6.0), int(y + h - 3.0), 13):
				var row_offset := 6.0 if int(yy / 13) % 2 == 0 else 12.0
				for xx in range(int(x + row_offset), int(x + w - 5.0), 18):
					draw_circle(Vector2(float(xx), float(yy)), 2.0, light)
		2:
			for yy in range(int(y + 5.0), int(y + h - 2.0), 11):
				for xx in range(int(x + 2.0), int(x + w - 6.0), 16):
					draw_line(Vector2(float(xx), float(yy) + 5.0), Vector2(float(xx) + 8.0, float(yy)), light, 1.1, true)
		3:
			for xx in range(int(x + 8.0), int(x + w - 4.0), 14):
				draw_line(Vector2(float(xx), y + 4.0), Vector2(float(xx), y + h - 4.0), dark, 1.0, true)
		_:
			for yy in range(int(y + 7.0), int(y + h - 4.0), 12):
				draw_line(Vector2(x + 7.0, float(yy)), Vector2(x + 18.0, float(yy)), light, 1.0, true)
				draw_line(Vector2(x + w - 18.0, float(yy) + 4.0), Vector2(x + w - 7.0, float(yy) + 4.0), light, 1.0, true)

func _draw_liquid_symbol(x: float, y: float, w: float, h: float, color_idx: int) -> void:
	if not GameSettings.show_liquid_symbols or h < 18.0:
		return
	var symbols := GameSettings.get_liquid_symbols()
	if symbols.is_empty():
		return
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var symbol := str(symbols[color_idx % symbols.size()])
	var base := _get_liquid_color(color_idx)
	var luminance := base.r * 0.299 + base.g * 0.587 + base.b * 0.114
	var ink := Color(0.02, 0.025, 0.035, 0.52) if luminance > 0.55 else Color(1.0, 1.0, 1.0, 0.58)
	var font_size := int(clampf(h * 0.46, 12.0, 20.0))
	draw_string(font, Vector2(x, y + h * 0.5 + float(font_size) * 0.36),
			symbol, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, ink)

func _get_liquid_alpha() -> float:
	return clampf(GameSettings.liquid_alpha, GameSettings.LIQUID_ALPHA_MIN, GameSettings.LIQUID_ALPHA_MAX)

func _get_liquid_colors() -> Array:
	return GameSettings.get_liquid_colors()

func _get_liquid_color(color_idx: int) -> Color:
	var colors := _get_liquid_colors()
	if colors.is_empty():
		return Color.WHITE
	return colors[color_idx % colors.size()]

func _get_liquid_color_count() -> int:
	return maxi(1, _get_liquid_colors().size())

func _get_selected_pour_color() -> Color:
	if selected_beaker < 0 or selected_beaker >= beaker_count:
		return Color(0.86, 0.90, 0.96)
	var b: Array = beakers[selected_beaker]
	if b.is_empty():
		return Color(0.86, 0.90, 0.96)
	return _get_liquid_color(int(b.back()))

func _draw_beaker(idx: int):
	var pos:  Vector2 = beaker_positions[idx]
	var hw   := float(beaker_width) / 2.0
	var bh   := float(beaker_height)
	var isel := (idx == selected_beaker)
	var is_finished := _is_beaker_complete(idx)
	var is_target := selected_beaker >= 0 and idx != selected_beaker and can_pour(selected_beaker, idx)

	if is_finished:
		_draw_finished_beaker_glow(idx, pos, hw, bh)

	if _cheat_mode != "":
		_draw_cheat_highlight(idx, pos, hw, bh)

	if is_target:
		var target_pulse := 0.24 + 0.10 * sin(_time * 7.5 + float(idx))
		var pour_color := _get_selected_pour_color()
		var outline := Color(pour_color.r, pour_color.g, pour_color.b, 0.96).lightened(0.18)
		var fill := Color(pour_color.r, pour_color.g, pour_color.b, target_pulse * 0.62)
		var shimmer := Color(1.0, 1.0, 1.0, 0.28 + target_pulse * 0.42)
		if idx == _drag_hover:
			outline = Color(pour_color.r, pour_color.g, pour_color.b, 1.0).lightened(0.30)
			fill = Color(pour_color.r, pour_color.g, pour_color.b, target_pulse * 0.78 + 0.08)
			shimmer = Color(1.0, 1.0, 1.0, 0.46 + target_pulse * 0.46)
		var rect := Rect2(pos.x - hw - 12, pos.y - bh - 12,
				float(beaker_width) + 24.0, bh + 24.0)
		draw_rect(rect, fill, true)
		draw_rect(rect, outline, false, 3.0)
		draw_rect(rect.grow(-3.0), shimmer, false, 1.3)

	# --- Pulsing selection glow ---
	if isel:
		var pulse := 0.18 + 0.10 * sin(_time * 7.0)
		var pour_color := _get_selected_pour_color()
		draw_rect(Rect2(pos.x - hw - 10, pos.y - bh - 10,
				float(beaker_width) + 20.0, bh + 20.0),
				Color(pour_color.r, pour_color.g, pour_color.b, pulse), true)
		draw_rect(Rect2(pos.x - hw - 10, pos.y - bh - 10,
				float(beaker_width) + 20.0, bh + 20.0),
				Color(pour_color.r, pour_color.g, pour_color.b, 0.58).lightened(0.16), false, 2.0)

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
		var col: Color = _get_liquid_color(int(color_data[ui]))
		var h   := (f1 - f0) * float(liquid_unit_height)
		var ly  := pos.y - f1 * float(liquid_unit_height)
		_draw_cylinder_rect(inner_x, ly, inner_w, h, col)
		_draw_liquid_texture(inner_x, ly, inner_w, h, int(color_data[ui]), ui)
		_draw_liquid_symbol(inner_x, ly, inner_w, h, int(color_data[ui]))
		# Shimmer line at top of each full segment
		if f1 >= float(ui + 1) - 0.01:
			var shimmer := 0.16 + 0.14 * maxf(0.0, sin(_time * 2.8 + float(color_data[ui]) * 1.7 + float(idx) * 0.43))
			draw_rect(Rect2(inner_x + 2, ly, inner_w - 4, 3),
					Color(1.0, 1.0, 1.0, shimmer), true)

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

	if is_finished:
		_draw_finished_beaker_lid(idx, pos, hw, bh)

func _draw_cheat_highlight(idx: int, pos: Vector2, hw: float, bh: float) -> void:
	var rect := Rect2(pos.x - hw - 10.0, pos.y - bh - 10.0,
			float(beaker_width) + 20.0, bh + 20.0)
	if _cheat_mode == "stir" and _can_stir_beaker(idx):
		var pulse := 0.18 + 0.08 * sin(_time * 7.0 + float(idx))
		draw_rect(rect, Color(0.30, 0.86, 1.0, pulse), true)
		draw_rect(rect, Color(0.56, 0.94, 1.0, 0.82), false, 2.5)
	elif _cheat_mode == "swap":
		var has_pair := false
		var b: Array = beakers[idx]
		for segment in maxi(0, b.size() - 1):
			if b[segment] != b[segment + 1]:
				has_pair = true
				break
		if has_pair:
			draw_rect(rect, Color(1.0, 0.82, 0.18, 0.11), true)
			draw_rect(rect, Color(1.0, 0.86, 0.24, 0.70), false, 2.0)
		if idx == _cheat_swap_beaker and _cheat_swap_segment >= 0:
			var segment_rect := _segment_rect(idx, _cheat_swap_segment)
			draw_rect(segment_rect.grow(3.0), Color(1.0, 1.0, 1.0, 0.16), true)
			draw_rect(segment_rect.grow(3.0), Color(1.0, 1.0, 1.0, 0.92), false, 2.0)

func _segment_rect(idx: int, segment: int) -> Rect2:
	var pos: Vector2 = beaker_positions[idx]
	var hw := float(beaker_width) / 2.0
	var inner_x := pos.x - hw + WALL
	var inner_w := float(beaker_width) - WALL * 2.0
	var top := pos.y - float(segment + 1) * float(liquid_unit_height)
	return Rect2(inner_x, top, inner_w, float(liquid_unit_height))

func _draw_finished_beaker_glow(idx: int, pos: Vector2, hw: float, bh: float) -> void:
	var color_idx: int = int(beakers[idx][0])
	var base: Color = _get_liquid_color(color_idx).lightened(0.28)
	var pulse := _get_finish_pulse(idx)
	var idle := 0.14 + 0.05 * sin(_time * 3.4 + float(idx) * 0.7)
	var rect := Rect2(pos.x - hw - 15.0, pos.y - bh - 15.0, float(beaker_width) + 30.0, bh + 30.0)
	for layer in 5:
		var t := float(layer) / 4.0
		var grow := lerpf(24.0, 4.0, t) + pulse * lerpf(26.0, 5.0, t)
		var alpha := (1.0 - t) * (idle * 0.18 + 0.035) + pulse * (1.0 - t) * 0.08
		draw_rect(rect.grow(grow), Color(base.r, base.g, base.b, alpha), true)
	_draw_ellipse_filled(Vector2(pos.x, pos.y - bh - 6.0),
			Vector2(hw + 26.0 + pulse * 16.0, 15.0 + pulse * 6.0),
			Color(1.0, 0.90, 0.38, 0.11 + pulse * 0.14))
	_draw_ellipse_filled(Vector2(pos.x, pos.y - WALL / 2.0),
			Vector2(hw + 18.0, 10.0),
			Color(base.r, base.g, base.b, 0.06))
	if pulse > 0.0:
		_draw_ellipse_filled(Vector2(pos.x, pos.y - bh - 6.0),
				Vector2(hw + 48.0 + (1.0 - pulse) * 38.0, 22.0 + (1.0 - pulse) * 16.0),
				Color(1.0, 0.92, 0.36, pulse * 0.10))

func _draw_finished_beaker_lid(idx: int, pos: Vector2, hw: float, bh: float) -> void:
	var pulse := _get_finish_pulse(idx)
	var top := pos.y - bh
	var color_idx: int = int(beakers[idx][0])
	var liquid: Color = _get_liquid_color(color_idx)
	var bob := sin(_time * 3.0 + float(idx)) * 1.2
	var lid_center := Vector2(pos.x, top - 5.0 + bob)
	var lid_rx := hw + 10.0 + pulse * 4.0
	var lid_ry := 8.0 + pulse * 1.5
	_draw_ellipse_filled(lid_center + Vector2(0.0, 3.5), Vector2(lid_rx + 2.0, lid_ry),
			Color(0.0, 0.0, 0.0, 0.30))
	draw_rect(Rect2(pos.x - lid_rx, top - 5.0 + bob, lid_rx * 2.0, 8.0),
			Color(0.10, 0.13, 0.18, 0.92), true)
	_draw_ellipse_filled(lid_center, Vector2(lid_rx, lid_ry),
			Color(liquid.r, liquid.g, liquid.b, 0.90).lightened(0.16))
	_draw_ellipse_filled(lid_center + Vector2(0.0, -1.0), Vector2(lid_rx - 7.0, lid_ry - 3.0),
			Color(1.0, 0.92, 0.48, 0.32 + pulse * 0.18))
	_draw_ellipse_filled(lid_center + Vector2(0.0, -8.0), Vector2(13.0 + pulse * 2.0, 5.0 + pulse),
			Color(0.96, 0.86, 0.38, 0.92))
	draw_line(Vector2(pos.x - lid_rx + 8.0, top - 8.0 + bob),
			Vector2(pos.x + lid_rx - 8.0, top - 8.0 + bob),
			Color(1.0, 1.0, 1.0, 0.26), 2.0, true)
	var sweep := fmod(_time * 46.0 + float(idx) * 17.0, bh + 46.0) - 23.0
	var sweep_y := top + sweep
	if sweep_y >= top and sweep_y <= pos.y:
		draw_rect(Rect2(pos.x - hw + WALL + 3.0, sweep_y, float(beaker_width) - WALL * 2.0 - 6.0, 5.0),
				Color(1.0, 1.0, 1.0, 0.16), true)
	if pulse > 0.0:
		var shine_color := Color(1.0, 0.95, 0.42, pulse)
		draw_line(Vector2(pos.x - hw - 18.0, top - 20.0), Vector2(pos.x - hw + 6.0, top - 44.0), shine_color, 3.0, true)
		draw_line(Vector2(pos.x + hw + 18.0, top - 8.0), Vector2(pos.x + hw + 42.0, top - 32.0), shine_color, 3.0, true)

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
		var bp: Vector2 = beaker_positions[randi() % beaker_count]
		var ml := randf_range(0.8, 2.2)
		_particles.append({
			"pos":      bp + Vector2(randf_range(-35, 35), randf_range(-float(beaker_height) * 0.9, -5.0)),
			"vel":      Vector2(randf_range(-240, 240), randf_range(-450, -60)),
			"color":    _get_liquid_color(randi() % _get_liquid_color_count()),
			"radius":   randf_range(4.0, 13.0),
			"life":     ml,
			"max_life": ml,
			"alpha":    1.0,
		})
