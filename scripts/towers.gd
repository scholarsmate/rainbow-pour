extends Node2D

signal disk_moved
signal goal_changed(optimal_pours: int)
signal solver_progress(searched: int, frontier: int, depth: int, limit: int)
signal no_moves_available
signal cracked_beaker_shattered(beaker_idx: int)
signal cheat_applied(cheat_type: String)
signal cheat_cancelled

const BoardCodeCodec = preload("res://scripts/board_code.gd")
const WALL = 5
const PLAY_TOP = 108.0
const PLAY_BOTTOM = 692.0
const OPTIMAL_SOLVER_CALCULATING = -2
const SOLVER_NODE_LIMIT = 750000
const SOLVER_STEPS_PER_FRAME = 260
const SOLVER_FRONTIER_LIMIT = 260000
const MOBILE_SOLVER_STEPS_PER_FRAME = 220
const GENERATED_SOLVER_RETRY_MAX = 8
const SOLVER_PROGRESS_INTERVAL = 2.0
const FINISHED_BEAKER_PULSE_TIME = 1.25
const _bg_color := Color(0.12, 0.14, 0.17, 1.0)
const BEAKER_TRAIT_NONE := ""
const BEAKER_TRAIT_PRISMATIC := "prismatic"
const BEAKER_TRAIT_TINTED := "tinted"
const BEAKER_TRAIT_CRACKED := "cracked"
const BEAKER_HEADROOM := 4.0
const PRISMATIC_BONUS_SCORE := 100
const TINTED_BONUS_SCORE := 250
const CRACKED_REVEAL_DURATION := 0.34
const PIPETTE_ANIM_DURATION := 2.10
const PIPETTE_STIR_ANIM_DURATION := 1.55
const PIPETTE_SWAP_ANIM_DURATION := 1.55

var beaker_capacity:    int   = 4
var beaker_count:       int   = 8
var empty_beakers:      int   = 2
var filled_beakers:     int   = 6
var beakers_per_row:    int   = 4
var optimal_pours:      int   = -1
var liquid_unit_height: int   = 40
var beaker_width:       int   = 80
var beaker_height:      int   = 180
var _play_area := Rect2(0.0, PLAY_TOP, 1280.0, PLAY_BOTTOM - PLAY_TOP)

var beakers:          Array = []
var beaker_traits:    Array = []
var beaker_capacities: Array = []
var beaker_positions: Array = []
var selected_beaker:  int   = -1
var _vis_fill:        Array = []
var _is_animating:    bool  = false
var _anim_src:        int   = -1
var _anim_dst:        int   = -1
var _anim_color:      int   = -1
var _anim_src_snap:   Array = []
var _pour_stream_progress: float = 0.0
var _undo_beakers:    Array = []
var _undo_vis_fill:   Array = []
var _starting_beakers: Array = []
var _starting_beaker_traits: Array = []
var _starting_beaker_capacities: Array = []
var _starting_filled_beakers: int = 0
var _starting_empty_beakers: int = 0
var _starting_beaker_count: int = 0
var _temporary_extra_beakers: int = 0
var _solver_active:   bool  = false
var _solver_queue:    Array = []
var _solver_depths:   Array = []
var _solver_visited:  Dictionary = {}
var _solver_front:    int   = 0
var _solver_searched: int   = 0
var _solver_current_depth: int = 0
var _solver_next_progress_time: float = 0.0
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
var _hover_beaker:    int   = -1
var _cheat_mode:      String = ""
var _cheat_swap_beaker: int = -1
var _cheat_swap_segment: int = -1
var _cheat_pipette_beaker: int = -1
var _cheat_pipette_segment: int = -1
var _cheat_pipette_run_start: int = -1
var _cheat_pipette_run_count: int = 0
var _cheat_pipette_color: int = -1
var _cracked_reveal_idx: int = -1
var _cracked_reveal_progress := 1.0
var _cracked_reveal_tween: Tween
var _pipette_anim_tween: Tween
var _pipette_anim_mode := ""
var _pipette_anim_progress := 1.0
var _pipette_anim_src := -1
var _pipette_anim_dst := -1
var _pipette_anim_run_start := -1
var _pipette_anim_run_count := 0
var _pipette_anim_color := -1
var _pipette_anim_alt_color := -1
var _pipette_anim_source_point := Vector2.ZERO
var _pipette_anim_dest_point := Vector2.ZERO
var _pipette_source_removed := false
var _pipette_destination_added := false
var _pipette_stir_result: Array = []
var _pipette_stir_applied := false
var _pipette_swap_first_segment := -1
var _pipette_swap_second_segment := -1
var _pipette_swap_applied := false
var _generated_solver_retry := 0
var _retry_generated_solver_on_failure := false

func _ready():
	_apply_capacity()
	setup_beaker_positions()
	generate_puzzle()

func set_play_area(area: Rect2) -> void:
	var sanitized := Rect2(
			area.position.x,
			area.position.y,
			maxf(360.0, area.size.x),
			maxf(220.0, area.size.y))
	if _play_area.is_equal_approx(sanitized):
		return
	_play_area = sanitized
	_recalculate_beaker_dimensions()
	setup_beaker_positions()
	queue_redraw()

func _apply_capacity():
	beaker_capacity    = GameSettings.beaker_capacity
	filled_beakers     = GameSettings.get_filled_beaker_count()
	empty_beakers      = GameSettings.get_empty_beaker_count()
	beaker_count       = filled_beakers + empty_beakers
	beakers_per_row    = _get_beaker_grid_columns()
	_recalculate_beaker_dimensions()

func _recalculate_beaker_dimensions() -> void:
	beakers_per_row = _get_beaker_grid_columns()
	var row_count := _get_beaker_grid_rows()
	var visual_scale := _get_visual_scale()
	var play_height := _play_area.size.y
	var row_gap := _get_row_gap(visual_scale)
	var row_slot := (play_height - row_gap * float(maxi(0, row_count - 1))) / float(maxi(1, row_count))
	var max_unit := int((row_slot - 18.0 * visual_scale - BEAKER_HEADROOM * visual_scale) / float(beaker_capacity))
	liquid_unit_height = clampi(max_unit, 10, int(round(40.0 * visual_scale)))
	beaker_height = int(float(beaker_capacity * liquid_unit_height) + BEAKER_HEADROOM * visual_scale)
	var capacity_width := int(round((100.0 - float(beaker_capacity - 4) * 4.0) * visual_scale))
	if row_count >= 5:
		capacity_width = mini(capacity_width, int(round(82.0 * visual_scale)))
	elif row_count >= 4:
		capacity_width = mini(capacity_width, int(round(90.0 * visual_scale)))
	elif row_count >= 3:
		capacity_width = mini(capacity_width, int(round(100.0 * visual_scale)))
	var column_slot := maxf(76.0 * visual_scale, (_play_area.size.x - 96.0 * visual_scale) / float(maxi(1, beakers_per_row)))
	var width_ratio := 0.70 if _is_play_area_portrait() else 0.55
	var grid_width := int(column_slot * width_ratio)
	var min_width := mini(int(round(44.0 * visual_scale)), grid_width)
	beaker_width = clampi(mini(capacity_width, grid_width), maxi(40, min_width), int(round(102.0 * visual_scale)))

func _process(delta: float):
	_time += delta
	if _solver_active:
		_process_optimal_solver(_get_solver_steps_per_frame())
	var dirty := true
	for _trait in beaker_traits:
		if str(_trait.get("type", "")) == BEAKER_TRAIT_PRISMATIC:
			dirty = true
			break
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
	beakers_per_row = _get_beaker_grid_columns()
	var row_count := _get_beaker_grid_rows()
	var visual_scale := _get_visual_scale()
	var trait_clearance := _get_trait_tag_radius(float(beaker_width) * 0.5) * 1.65
	var side_margin := maxf(42.0 * visual_scale, float(beaker_width) * 0.5 + trait_clearance)
	var spacing_x := 0.0
	if beakers_per_row > 1:
		spacing_x = (_play_area.size.x - side_margin * 2.0) / float(beakers_per_row - 1)
		spacing_x = minf(spacing_x, 240.0 * visual_scale)
	var avail := _play_area.size.y
	var row_gap := _get_row_gap(visual_scale)
	var row_slot := (avail - row_gap * float(maxi(0, row_count - 1))) / float(maxi(1, row_count))
	var center_x := _play_area.position.x + _play_area.size.x * 0.5
	for row in row_count:
		var remaining := beaker_count - row * beakers_per_row
		var row_items := mini(beakers_per_row, remaining)
		var sx := center_x - spacing_x * float(row_items - 1) * 0.5
		var row_top := _play_area.position.y + float(row) * (row_slot + row_gap)
		var base_y := row_top + row_slot * 0.5 + float(beaker_height) * 0.5
		for col in row_items:
			beaker_positions.append(Vector2(sx + col * spacing_x, base_y))

func _ensure_beaker_positions() -> void:
	if beaker_positions.size() == beaker_count:
		return
	_recalculate_beaker_dimensions()
	setup_beaker_positions()

func _ensure_runtime_arrays() -> void:
	if beakers.size() < beaker_count:
		while beakers.size() < beaker_count:
			beakers.append([])
	elif beakers.size() > beaker_count:
		beakers.resize(beaker_count)
	_ensure_beaker_traits()
	if _vis_fill.size() != beaker_count:
		var old_vis := _vis_fill.duplicate()
		_vis_fill.resize(beaker_count)
		for i in beaker_count:
			if i < old_vis.size():
				_vis_fill[i] = old_vis[i]
			else:
				_vis_fill[i] = float(beakers[i].size())
	if _finished_beakers.size() != beaker_count or _finish_pulses.size() != beaker_count:
		_reset_finish_state()
	_ensure_beaker_positions()
	_ensure_beaker_capacities()

func _ensure_beaker_capacities() -> void:
	var normalized := []
	for idx in beaker_count:
		var capacity := beaker_capacity
		if idx < beaker_capacities.size():
			capacity = int(beaker_capacities[idx])
		normalized.append(clampi(capacity, 1, beaker_capacity))
	beaker_capacities = normalized

func _make_default_beaker_capacities(count: int) -> Array:
	var capacities := []
	for idx in count:
		capacities.append(beaker_capacity)
	return capacities

func _get_extra_beaker_capacity() -> int:
	return maxi(1, beaker_capacity - 1)

func _get_beaker_capacity(idx: int) -> int:
	if idx >= 0 and idx < beaker_capacities.size():
		return clampi(int(beaker_capacities[idx]), 1, beaker_capacity)
	return beaker_capacity

func _get_beaker_visual_height(idx: int) -> float:
	return float(_get_beaker_capacity(idx) * liquid_unit_height) + BEAKER_HEADROOM

func _get_beaker_grid_columns() -> int:
	if beaker_count <= 0:
		return 1
	if _is_play_area_portrait():
		if beaker_count <= 10:
			return 2
		if beaker_count <= 15:
			return 3
		return 4
	if beaker_count <= 8:
		return int(ceil(float(beaker_count) / 2.0))
	return 4

func _get_beaker_grid_rows() -> int:
	return int(ceil(float(maxi(1, beaker_count)) / float(maxi(1, beakers_per_row))))

func _is_play_area_portrait() -> bool:
	return _play_area.size.y > _play_area.size.x * 1.08

func _get_visual_scale() -> float:
	if _is_play_area_portrait():
		return clampf(_play_area.size.x / 460.0, 1.35, 2.45)
	return clampf(minf(_play_area.size.x / 1280.0, _play_area.size.y / 584.0), 0.85, 1.35)

func _get_row_gap(visual_scale: float) -> float:
	if _is_play_area_portrait():
		return clampf(13.0 * visual_scale, 13.0, 28.0)
	return 14.0 * visual_scale

func generate_puzzle(retry_attempt: int = 0):
	_generated_solver_retry = retry_attempt
	_temporary_extra_beakers = 0
	beakers.clear()
	beaker_traits.clear()
	beaker_capacities.clear()
	_particles.clear()
	_clear_pour_animation_state()
	_clear_pointer_state()
	_clear_undo_state()
	_cancel_cheat_state()
	_clear_pipette_animation_state()
	_clear_cracked_reveal_state()
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
	_repair_completed_generated_beakers()
	beaker_capacities = _make_default_beaker_capacities(beaker_count)
	_vis_fill.resize(beaker_count)
	for i in beaker_count:
		_vis_fill[i] = float(beakers[i].size())
	_assign_special_beaker_traits()
	_sync_finished_beakers(false)
	_store_starting_puzzle_state()
	if GameSettings.chill_mode:
		_finish_goalless_chill_mode()
	else:
		_start_optimal_solver(_starting_beakers, true)
	queue_redraw()

func _repair_completed_generated_beakers() -> void:
	if filled_beakers <= 1:
		return
	for idx in filled_beakers:
		if idx >= beakers.size() or not _is_tube_complete(beakers[idx]):
			continue
		_mix_completed_beaker_with_next(idx)

func _mix_completed_beaker_with_next(idx: int) -> void:
	var src: Array = beakers[idx]
	if src.is_empty():
		return
	for offset in range(1, filled_beakers):
		var dst_idx := (idx + offset) % filled_beakers
		if dst_idx >= beakers.size():
			continue
		var dst: Array = beakers[dst_idx]
		if dst.is_empty():
			continue
		for src_segment in src.size():
			for dst_segment in dst.size():
				if src[src_segment] == dst[dst_segment]:
					continue
				var tmp = src[src_segment]
				src[src_segment] = dst[dst_segment]
				dst[dst_segment] = tmp
				return

func can_pour(src: int, dst: int) -> bool:
	if src < 0 or src >= beaker_count or dst < 0 or dst >= beaker_count:
		return false
	if src >= beakers.size() or dst >= beakers.size():
		return false
	if src == dst:
		return false
	if beakers[src].is_empty():
		return false
	if _is_beaker_complete(src):
		return false
	if beakers[dst].size() >= _get_beaker_capacity(dst):
		return false
	if beakers[dst].is_empty():
		return true
	return beakers[src].back() == beakers[dst].back()

func pour(src: int, dst: int):
	_store_undo_state()
	var old_src := float(beakers[src].size())
	var old_dst := float(beakers[dst].size())
	_anim_src      = src
	_anim_dst      = dst
	_anim_src_snap = beakers[src].duplicate()
	var top = beakers[src].back()
	_anim_color = int(top)
	_pour_stream_progress = 0.0
	var dst_capacity := _get_beaker_capacity(dst)
	while not beakers[src].is_empty() and beakers[src].back() == top and beakers[dst].size() < dst_capacity:
		beakers[dst].append(beakers[src].pop_back())
	if AudioManager:
		AudioManager.play_pour()
	_is_animating = true
	var tw := create_tween().set_parallel()
	var src_tweener := tw.tween_method(_set_vis.bind(src), old_src, float(beakers[src].size()), 0.38)
	src_tweener.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var dst_tweener := tw.tween_method(_set_vis.bind(dst), old_dst, float(beakers[dst].size()), 0.38)
	dst_tweener.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	var stream_tweener := tw.tween_method(_set_pour_stream_progress, 0.0, 1.0, 0.38)
	stream_tweener.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var changed_indices := [src, dst]
	var on_done := func():
		_finish_pour_after_animation(changed_indices)
	tw.chain().tween_callback(on_done)

func _finish_pour_after_animation(changed_indices: Array) -> void:
	_is_animating = false
	_clear_pour_animation_state()
	_sync_finished_beakers(true)
	if _reveal_hidden_cracked_beaker_if_needed(changed_indices, Callable(self, "_finish_pour_state_change")):
		return
	_finish_pour_state_change()

func _finish_pour_state_change() -> void:
	if _shatter_first_cracked_beaker_if_needed():
		return
	emit_signal("disk_moved")
	if check_complete():
		_celebrate()
	elif not has_available_moves():
		emit_signal("no_moves_available")

func _set_vis(v: float, idx: int) -> void:
	_vis_fill[idx] = v
	queue_redraw()

func _set_pour_stream_progress(v: float) -> void:
	_pour_stream_progress = clampf(v, 0.0, 1.0)
	queue_redraw()

func _clear_pour_animation_state() -> void:
	_anim_src = -1
	_anim_dst = -1
	_anim_color = -1
	_anim_src_snap.clear()
	_pour_stream_progress = 0.0

func check_complete() -> bool:
	_ensure_beaker_traits()
	for idx in beaker_count:
		if idx >= beakers.size():
			return false
		var b: Array = beakers[idx]
		if _is_cracked_beaker(idx):
			if not b.is_empty():
				return false
			continue
		if b.is_empty():
			continue
		if not _is_tube_complete(b):
			return false
	return true

func _is_beaker_complete(idx: int) -> bool:
	if idx < 0 or idx >= beaker_count or idx >= beakers.size():
		return false
	if _is_cracked_beaker(idx):
		return false
	var b: Array = beakers[idx]
	return _is_tube_complete(b)

func _has_completed_beaker() -> bool:
	for idx in beaker_count:
		if idx < beakers.size() and _is_tube_complete(beakers[idx]):
			return true
	return false

func _is_tube_complete(tube: Array) -> bool:
	return _is_tube_complete_for_capacity(tube, beaker_capacity)

func _is_tube_complete_for_capacity(tube: Array, capacity: int) -> bool:
	if tube.size() != capacity:
		return false
	var c = tube[0]
	for u in tube:
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
	_ensure_runtime_arrays()
	if idx < 0 or idx >= beaker_positions.size() or idx >= beakers.size() or idx >= _finish_pulses.size():
		return
	_finish_pulses[idx] = FINISHED_BEAKER_PULSE_TIME
	if AudioManager and AudioManager.has_method("play_beaker_capped"):
		AudioManager.play_beaker_capped()
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

func get_single_available_move_source() -> int:
	var found_source := -1
	var found_count := 0
	for src in beaker_count:
		for dst in beaker_count:
			if not can_pour(src, dst):
				continue
			found_source = src
			found_count += 1
			if found_count > 1:
				return -1
	return found_source if found_count == 1 else -1

func has_shattered_cracked_beaker() -> bool:
	return _get_shattered_cracked_beaker() >= 0

func _get_shattered_cracked_beaker() -> int:
	_ensure_beaker_traits()
	for idx in beaker_count:
		if idx < beakers.size() and _is_cracked_shatter_state(idx, beakers[idx]):
			return idx
	return -1

func _is_cracked_shatter_state(idx: int, tube: Array) -> bool:
	return _is_cracked_beaker(idx) and _is_tube_complete(tube)

func _shatter_first_cracked_beaker_if_needed() -> bool:
	var shattered_idx := _get_shattered_cracked_beaker()
	if shattered_idx < 0:
		return false
	if not _shatter_cracked_beaker(shattered_idx):
		return false
	emit_signal("cracked_beaker_shattered", shattered_idx)
	return true

func _shatter_cracked_beaker(idx: int) -> bool:
	if idx < 0 or idx >= beaker_count or idx >= beakers.size():
		return false
	if not _is_cracked_shatter_state(idx, beakers[idx]):
		return false
	var lost: Array = beakers[idx].duplicate()
	var spill_color := int(lost[0]) if not lost.is_empty() else -1
	beakers[idx].clear()
	if idx < _vis_fill.size():
		_vis_fill[idx] = 0.0
	selected_beaker = -1
	_clear_pointer_state()
	_clear_undo_state()
	_cancel_cheat_state()
	_spawn_shatter_particles(idx, spill_color)
	if AudioManager:
		if AudioManager.has_method("play_shatter"):
			AudioManager.call("play_shatter")
		else:
			AudioManager.play_loss()
		if AudioManager.has_method("play_liquid_spill"):
			AudioManager.call("play_liquid_spill")
	_reset_finish_state()
	_sync_finished_beakers(false)
	queue_redraw()
	return true

func has_non_empty_cracked_beaker() -> bool:
	_ensure_beaker_traits()
	for idx in beaker_count:
		if _is_cracked_beaker(idx) and idx < beakers.size() and not (beakers[idx] as Array).is_empty():
			return true
	return false

func is_only_cracked_blocking_completion() -> bool:
	_ensure_beaker_traits()
	var has_non_empty_cracked := false
	for idx in beaker_count:
		if idx >= beakers.size():
			return false
		var tube: Array = beakers[idx]
		if _is_cracked_beaker(idx):
			if not tube.is_empty():
				has_non_empty_cracked = true
			continue
		if tube.is_empty():
			continue
		if not _is_tube_complete(tube):
			return false
	return has_non_empty_cracked

func is_beaker_empty(idx: int) -> bool:
	return idx >= 0 and idx < beakers.size() and (beakers[idx] as Array).is_empty()

func _spawn_shatter_particles(idx: int, color_idx: int) -> void:
	if idx < 0 or idx >= beaker_positions.size():
		return
	var pos: Vector2 = beaker_positions[idx]
	var liquid := _get_liquid_color(color_idx) if color_idx >= 0 else Color(1.0, 0.30, 0.22)
	for n in 40:
		var is_glass := n % 3 == 0
		var ml := randf_range(0.45, 0.95)
		var angle := randf_range(-PI * 0.95, -PI * 0.05)
		var speed := randf_range(110.0, 310.0)
		_particles.append({
			"pos": pos + Vector2(randf_range(-float(beaker_width) * 0.30, float(beaker_width) * 0.30), -float(beaker_height) * randf_range(0.20, 0.92)),
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"color": Color(0.92, 0.98, 1.0, 0.92) if is_glass else liquid.lightened(randf_range(0.03, 0.22)),
			"radius": randf_range(2.0, 5.5) if is_glass else randf_range(4.0, 9.0),
			"life": ml,
			"max_life": ml,
			"alpha": 1.0,
		})

func _spawn_cracked_reveal_particles(idx: int) -> void:
	if idx < 0 or idx >= beaker_positions.size():
		return
	var pos: Vector2 = beaker_positions[idx]
	var hw := float(beaker_width) / 2.0
	var bh := _get_beaker_visual_height(idx)
	var radius := _get_trait_tag_radius(hw)
	var center := _get_trait_tag_center(pos, hw, bh, radius)
	for n in 18:
		var angle := randf_range(PI * 0.62, PI * 1.38)
		var speed := randf_range(60.0, 180.0)
		var ml := randf_range(0.22, 0.48)
		_particles.append({
			"pos": center + Vector2(randf_range(-radius * 0.20, radius * 0.20), randf_range(-radius * 0.16, radius * 0.16)),
			"vel": Vector2(cos(angle), sin(angle)) * speed + Vector2(randf_range(-18.0, 18.0), randf_range(-56.0, -12.0)),
			"color": Color(0.90, 0.97, 1.0, 0.92) if n % 3 == 0 else Color(0.34, 0.38, 0.44, 0.96),
			"radius": randf_range(1.6, 4.2),
			"life": ml,
			"max_life": ml,
			"alpha": 1.0,
		})

func get_possible_destinations(src: int) -> Array:
	var destinations := []
	for dst in beaker_count:
		if can_pour(src, dst):
			destinations.append(dst)
	return destinations

func get_board_signature() -> String:
	return BoardCodeCodec.encode(beaker_capacity, filled_beakers, empty_beakers, beakers, beaker_traits, -1)

func export_board_code() -> String:
	_ensure_beaker_traits()
	var cached_goal := optimal_pours if not GameSettings.chill_mode and _temporary_extra_beakers <= 0 else -1
	return BoardCodeCodec.encode(beaker_capacity, filled_beakers, empty_beakers, beakers, beaker_traits, cached_goal)

func import_board_code(raw_code: String, forced_cached_goal: int = -1) -> bool:
	var decoded := BoardCodeCodec.decode(raw_code)
	if not bool(decoded.get("ok", false)):
		return false
	var imported_capacity := int(decoded["capacity"])
	var imported_filled := int(decoded["filled_count"])
	var imported_empty := int(decoded["empty_count"])
	if imported_capacity < GameSettings.CAPACITY_MIN or imported_capacity > GameSettings.CAPACITY_MAX:
		return false
	if imported_filled <= 0 or imported_empty <= 0:
		return false
	var imported_count := imported_filled + imported_empty
	if imported_count > GameSettings.MAX_BEAKERS:
		return false
	var imported_beakers: Array = decoded["beakers"]
	var imported_traits: Array = decoded["traits"]
	var has_forced_goal := forced_cached_goal >= 0
	var cached_goal := forced_cached_goal if has_forced_goal else int(decoded.get("cached_goal", -1))
	if imported_beakers.size() != imported_count or imported_traits.size() != imported_count:
		return false
	for tube in imported_beakers:
		if (tube as Array).size() > imported_capacity:
			return false
		for color in tube:
			if int(color) < 0 or int(color) >= imported_filled:
				return false
	var imported_has_cracked := false
	for idx in imported_count:
		var trait_data: Dictionary = imported_traits[idx] if typeof(imported_traits[idx]) == TYPE_DICTIONARY else {}
		if str(trait_data.get("type", BEAKER_TRAIT_NONE)) == BEAKER_TRAIT_CRACKED:
			imported_has_cracked = true
			if _is_tube_complete_for_capacity(imported_beakers[idx], imported_capacity):
				return false

	var difficulty_key := GameSettings.find_difficulty_for_counts(imported_filled, imported_empty)
	if difficulty_key != "":
		GameSettings.set_difficulty(difficulty_key)
	else:
		GameSettings.set_beaker_counts(imported_filled, imported_empty)
	GameSettings.set_beaker_capacity(imported_capacity)

	beaker_capacity = imported_capacity
	filled_beakers = imported_filled
	empty_beakers = imported_empty
	beaker_count = imported_count
	beakers_per_row = _get_beaker_grid_columns()
	_recalculate_beaker_dimensions()
	beakers = imported_beakers
	beaker_traits = imported_traits
	beaker_capacities = _make_default_beaker_capacities(beaker_count)
	_ensure_beaker_traits()
	_vis_fill.resize(beaker_count)
	for i in beaker_count:
		_vis_fill[i] = float(beakers[i].size())
	selected_beaker = -1
	_is_animating = false
	_clear_pour_animation_state()
	_particles.clear()
	_clear_pointer_state()
	_clear_undo_state()
	_cancel_cheat_state()
	_clear_pipette_animation_state()
	_clear_cracked_reveal_state()
	_reset_finish_state()
	_temporary_extra_beakers = 0
	_ensure_beaker_capacities()
	setup_beaker_positions()
	_sync_finished_beakers(false)
	_store_starting_puzzle_state()
	if GameSettings.chill_mode:
		_finish_goalless_chill_mode()
	elif cached_goal >= 0 and (has_forced_goal or not imported_has_cracked):
		_clear_solver_state()
		optimal_pours = cached_goal
		emit_signal("goal_changed", optimal_pours)
	else:
		_start_optimal_solver(_starting_beakers)
	queue_redraw()
	return true

func get_beaker_bonus_score() -> int:
	var counts := get_earned_beaker_bonus_counts()
	return int(counts["prismatic_score"]) + int(counts["tinted_score"])

func get_earned_beaker_bonus_counts() -> Dictionary:
	var counts := {
		"prismatic": 0,
		"tinted": 0,
		"prismatic_score": 0,
		"tinted_score": 0,
	}
	if not check_complete():
		return counts
	_ensure_beaker_traits()
	for idx in beaker_count:
		var trait_data := _get_beaker_trait(idx)
		var trait_type := str(trait_data.get("type", BEAKER_TRAIT_NONE))
		if trait_type == BEAKER_TRAIT_PRISMATIC and _is_beaker_trait_bonus_earned(idx):
			counts["prismatic"] = int(counts["prismatic"]) + 1
			counts["prismatic_score"] = int(counts["prismatic_score"]) + PRISMATIC_BONUS_SCORE
		elif trait_type == BEAKER_TRAIT_TINTED and _is_beaker_trait_bonus_earned(idx):
			counts["tinted"] = int(counts["tinted"]) + 1
			counts["tinted_score"] = int(counts["tinted_score"]) + TINTED_BONUS_SCORE
	return counts

func get_available_beaker_bonus_score() -> int:
	_ensure_beaker_traits()
	var total := 0
	for idx in beaker_count:
		var trait_data := _get_beaker_trait(idx)
		match str(trait_data.get("type", BEAKER_TRAIT_NONE)):
			BEAKER_TRAIT_PRISMATIC:
				total += PRISMATIC_BONUS_SCORE
			BEAKER_TRAIT_TINTED:
				total += TINTED_BONUS_SCORE
	return total

func _assign_special_beaker_traits() -> void:
	beaker_traits = _blank_beaker_traits(beaker_count)
	if not GameSettings.special_beakers_enabled or beaker_count <= 0:
		return
	var candidates := []
	for idx in beaker_count:
		candidates.append(idx)
	candidates.shuffle()
	var next_candidate := 0
	var cracked_candidates := []
	for idx in filled_beakers:
		if idx < beakers.size() and not _is_tube_complete(beakers[idx]):
			cracked_candidates.append(idx)
	cracked_candidates.shuffle()
	if not cracked_candidates.is_empty():
		var cracked_idx := int(cracked_candidates[0])
		beaker_traits[cracked_idx] = _make_beaker_trait(BEAKER_TRAIT_CRACKED)
		candidates.erase(cracked_idx)
	if next_candidate < candidates.size():
		beaker_traits[int(candidates[next_candidate])] = _make_beaker_trait(BEAKER_TRAIT_PRISMATIC)
		next_candidate += 1
	if filled_beakers > 0 and next_candidate < candidates.size():
		beaker_traits[int(candidates[next_candidate])] = _make_beaker_trait(BEAKER_TRAIT_TINTED, randi() % filled_beakers)

func _blank_beaker_traits(count: int) -> Array:
	var traits := []
	for idx in count:
		traits.append(_make_beaker_trait())
	return traits

func _make_beaker_trait(trait_type: String = BEAKER_TRAIT_NONE, color_idx: int = -1, revealed: bool = false) -> Dictionary:
	return {"type": trait_type, "color": color_idx, "revealed": revealed}

func _store_starting_puzzle_state() -> void:
	_ensure_beaker_capacities()
	_starting_beakers = _copy_state(beakers)
	_starting_beaker_traits = _copy_beaker_traits(beaker_traits)
	_starting_beaker_capacities = beaker_capacities.duplicate()
	_starting_filled_beakers = filled_beakers
	_starting_empty_beakers = empty_beakers
	_starting_beaker_count = beaker_count

func _copy_beaker_traits(traits: Array) -> Array:
	var copied := []
	for trait_data in traits:
		if typeof(trait_data) == TYPE_DICTIONARY:
			var data: Dictionary = trait_data
			copied.append(data.duplicate())
		else:
			copied.append(_make_beaker_trait())
	return copied

func _ensure_beaker_traits() -> void:
	var normalized := []
	for idx in beaker_count:
		if idx < beaker_traits.size():
			normalized.append(_normalize_beaker_trait(beaker_traits[idx]))
		else:
			normalized.append(_make_beaker_trait())
	beaker_traits = normalized

func _normalize_beaker_trait(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _make_beaker_trait()
	var data: Dictionary = value
	var trait_type := str(data.get("type", BEAKER_TRAIT_NONE))
	if trait_type == BEAKER_TRAIT_PRISMATIC:
		return _make_beaker_trait(BEAKER_TRAIT_PRISMATIC)
	if trait_type == BEAKER_TRAIT_TINTED:
		var color_idx := int(data.get("color", -1))
		if color_idx >= 0 and color_idx < filled_beakers:
			return _make_beaker_trait(BEAKER_TRAIT_TINTED, color_idx)
	if trait_type == BEAKER_TRAIT_CRACKED:
		return _make_beaker_trait(BEAKER_TRAIT_CRACKED, -1, bool(data.get("revealed", false)))
	return _make_beaker_trait()

func _get_beaker_trait(idx: int) -> Dictionary:
	if idx < 0 or idx >= beaker_traits.size():
		return _make_beaker_trait()
	return _normalize_beaker_trait(beaker_traits[idx])

func _is_cracked_beaker(idx: int) -> bool:
	if idx < 0 or idx >= beaker_count:
		return false
	return str(_get_beaker_trait(idx).get("type", BEAKER_TRAIT_NONE)) == BEAKER_TRAIT_CRACKED

func _is_cracked_beaker_revealed(idx: int) -> bool:
	if not _is_cracked_beaker(idx):
		return false
	return bool(_get_beaker_trait(idx).get("revealed", false))

func _set_cracked_beaker_revealed(idx: int, revealed: bool) -> void:
	if idx < 0 or idx >= beaker_count:
		return
	_ensure_beaker_traits()
	if idx >= beaker_traits.size() or not _is_cracked_beaker(idx):
		return
	beaker_traits[idx] = _make_beaker_trait(BEAKER_TRAIT_CRACKED, -1, revealed)

func _reveal_hidden_cracked_beaker_if_needed(changed_indices: Array, after_reveal: Callable) -> bool:
	for raw_idx in changed_indices:
		var idx := int(raw_idx)
		if idx < 0 or idx >= beaker_count:
			continue
		if _is_cracked_beaker(idx) and not _is_cracked_beaker_revealed(idx):
			_start_cracked_reveal(idx, after_reveal)
			return true
	return false

func _start_cracked_reveal(idx: int, after_reveal: Callable) -> void:
	if _cracked_reveal_tween and _cracked_reveal_tween.is_valid():
		_cracked_reveal_tween.kill()
	_cracked_reveal_idx = idx
	_cracked_reveal_progress = 0.0
	_is_animating = true
	selected_beaker = -1
	_clear_pointer_state()
	var tw := create_tween().set_parallel()
	_cracked_reveal_tween = tw
	tw.tween_method(_set_cracked_reveal_progress, 0.0, 1.0, CRACKED_REVEAL_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(_play_cracked_reveal_sound).set_delay(CRACKED_REVEAL_DURATION * 0.78)
	tw.chain().tween_callback(func():
		_complete_cracked_reveal(idx, after_reveal)
	)
	queue_redraw()

func _set_cracked_reveal_progress(value: float) -> void:
	_cracked_reveal_progress = clampf(value, 0.0, 1.0)
	queue_redraw()

func _play_cracked_reveal_sound() -> void:
	if not AudioManager:
		return
	if AudioManager.has_method("play_glass_crack"):
		AudioManager.call("play_glass_crack")
	else:
		AudioManager.play_invalid()

func _complete_cracked_reveal(idx: int, after_reveal: Callable) -> void:
	if idx == _cracked_reveal_idx:
		_spawn_cracked_reveal_particles(idx)
	_set_cracked_beaker_revealed(idx, true)
	_cracked_reveal_idx = -1
	_cracked_reveal_progress = 1.0
	_cracked_reveal_tween = null
	_is_animating = false
	queue_redraw()
	if after_reveal.is_valid():
		after_reveal.call()

func _clear_cracked_reveal_state() -> void:
	if _cracked_reveal_tween and _cracked_reveal_tween.is_valid():
		_cracked_reveal_tween.kill()
	_cracked_reveal_tween = null
	_cracked_reveal_idx = -1
	_cracked_reveal_progress = 1.0

func _is_beaker_trait_bonus_earned(idx: int) -> bool:
	if not _is_beaker_complete(idx):
		return false
	var trait_data := _get_beaker_trait(idx)
	match str(trait_data.get("type", BEAKER_TRAIT_NONE)):
		BEAKER_TRAIT_PRISMATIC:
			return true
		BEAKER_TRAIT_TINTED:
			return int(beakers[idx][0]) == int(trait_data.get("color", -1))
	return false

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

func has_usable_pipette_cheat() -> bool:
	if _is_animating or check_complete():
		return false
	for idx in beaker_count:
		if idx >= beakers.size() or _is_beaker_complete(idx):
			continue
		var b: Array = beakers[idx]
		for segment in b.size():
			if _can_pipette_select_segment(idx, segment):
				return true
	return false

func can_add_empty_beaker() -> bool:
	return not _is_animating and not check_complete() and beaker_count < GameSettings.MAX_BEAKERS

func add_empty_beaker() -> bool:
	if not can_add_empty_beaker():
		return false
	selected_beaker = -1
	_is_animating = false
	_clear_pour_animation_state()
	_particles.clear()
	_clear_pointer_state()
	_clear_undo_state()
	_cancel_cheat_state()
	beaker_count += 1
	empty_beakers += 1
	_temporary_extra_beakers += 1
	beakers.append([])
	beaker_traits.append(_make_beaker_trait())
	beaker_capacities.append(_get_extra_beaker_capacity())
	_vis_fill.append(0.0)
	_ensure_beaker_capacities()
	_recalculate_beaker_dimensions()
	setup_beaker_positions()
	_reset_finish_state()
	_sync_finished_beakers(false)
	queue_redraw()
	return true

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

func begin_pipette_cheat() -> bool:
	if not has_usable_pipette_cheat():
		return false
	_cancel_cheat_state()
	_cheat_mode = "pipette"
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
	_clear_pour_animation_state()
	_particles.clear()
	_clear_pointer_state()
	_clear_undo_state()
	_cancel_cheat_state()
	_clear_pipette_animation_state()
	_clear_cracked_reveal_state()
	_reset_finish_state()
	_sync_finished_beakers(false)
	queue_redraw()
	return true

func retry_current_puzzle() -> bool:
	if _starting_beakers.is_empty():
		return false
	var cached_goal := optimal_pours
	filled_beakers = _starting_filled_beakers if _starting_filled_beakers > 0 else filled_beakers
	empty_beakers = _starting_empty_beakers if _starting_empty_beakers > 0 else empty_beakers
	beaker_count = _starting_beaker_count if _starting_beaker_count > 0 else _starting_beakers.size()
	_temporary_extra_beakers = 0
	beakers_per_row = _get_beaker_grid_columns()
	_recalculate_beaker_dimensions()
	setup_beaker_positions()
	beakers = _copy_state(_starting_beakers)
	beaker_traits = _copy_beaker_traits(_starting_beaker_traits)
	beaker_capacities = _starting_beaker_capacities.duplicate()
	_ensure_beaker_traits()
	_ensure_beaker_capacities()
	_vis_fill.resize(beaker_count)
	for i in beaker_count:
		_vis_fill[i] = float(beakers[i].size())
	selected_beaker = -1
	_is_animating = false
	_clear_pour_animation_state()
	_particles.clear()
	_clear_pointer_state()
	_clear_undo_state()
	_cancel_cheat_state()
	_clear_pipette_animation_state()
	_clear_cracked_reveal_state()
	_reset_finish_state()
	_sync_finished_beakers(false)
	if GameSettings.chill_mode:
		_finish_goalless_chill_mode()
	elif cached_goal == OPTIMAL_SOLVER_CALCULATING:
		_start_optimal_solver(_starting_beakers)
	else:
		_finish_optimal_solver(cached_goal)
	queue_redraw()
	return true

func reset():
	selected_beaker = -1
	_is_animating   = false
	_clear_pour_animation_state()
	_particles.clear()
	_clear_pointer_state()
	_clear_undo_state()
	_cancel_cheat_state()
	_clear_pipette_animation_state()
	_clear_cracked_reveal_state()
	_reset_finish_state()
	_starting_beaker_traits.clear()
	_starting_beaker_capacities.clear()
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
	_cheat_pipette_beaker = -1
	_cheat_pipette_segment = -1
	_cheat_pipette_run_start = -1
	_cheat_pipette_run_count = 0
	_cheat_pipette_color = -1

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
	return _start_stir_animation(idx, stirred)

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
	return _start_swap_animation(idx, first_segment, second_segment)

func _start_stir_animation(idx: int, stirred: Array) -> bool:
	if idx < 0 or idx >= beakers.size():
		return false
	_clear_pipette_animation_state()
	var b: Array = beakers[idx]
	_pipette_anim_mode = "stir"
	_pipette_anim_src = idx
	_pipette_anim_dst = idx
	_pipette_anim_run_start = 0
	_pipette_anim_run_count = b.size()
	_pipette_anim_color = int(b.back()) if not b.is_empty() else 0
	_pipette_anim_alt_color = _pipette_anim_color
	_pipette_anim_source_point = _beaker_stir_point(idx)
	_pipette_anim_dest_point = _pipette_anim_source_point
	_pipette_stir_result = stirred.duplicate()
	_pipette_stir_applied = false
	_pipette_anim_progress = 0.0
	_is_animating = true
	selected_beaker = -1
	_clear_pointer_state()
	_cancel_cheat_state()
	var tw := create_tween().set_parallel()
	_pipette_anim_tween = tw
	tw.tween_method(_set_pipette_anim_progress, 0.0, 1.0, PIPETTE_STIR_ANIM_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_play_pipette_stir_sound).set_delay(0.30)
	tw.tween_callback(_apply_pipette_stir).set_delay(1.05)
	tw.chain().tween_callback(_finish_pipette_stir)
	queue_redraw()
	return true

func _start_swap_animation(idx: int, first_segment: int, second_segment: int) -> bool:
	if idx < 0 or idx >= beakers.size():
		return false
	_clear_pipette_animation_state()
	var b: Array = beakers[idx]
	_pipette_anim_mode = "swap"
	_pipette_anim_src = idx
	_pipette_anim_dst = idx
	_pipette_anim_run_start = first_segment
	_pipette_anim_run_count = 1
	_pipette_anim_color = int(b[first_segment])
	_pipette_anim_alt_color = int(b[second_segment])
	_pipette_anim_source_point = _segment_run_center(idx, first_segment, 1)
	_pipette_anim_dest_point = _segment_run_center(idx, second_segment, 1)
	_pipette_swap_first_segment = first_segment
	_pipette_swap_second_segment = second_segment
	_pipette_swap_applied = false
	_pipette_anim_progress = 0.0
	_is_animating = true
	selected_beaker = -1
	_clear_pointer_state()
	_cancel_cheat_state()
	var tw := create_tween().set_parallel()
	_pipette_anim_tween = tw
	tw.tween_method(_set_pipette_anim_progress, 0.0, 1.0, PIPETTE_SWAP_ANIM_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_play_pipette_suck_sound).set_delay(0.30)
	tw.tween_callback(_play_pipette_squirt_sound).set_delay(0.92)
	tw.tween_callback(_apply_pipette_swap).set_delay(1.15)
	tw.chain().tween_callback(_finish_pipette_swap)
	queue_redraw()
	return true

func _get_pipette_run(idx: int, segment: int) -> Dictionary:
	if idx < 0 or idx >= beaker_count or idx >= beakers.size():
		return {"start": -1, "count": 0, "color": -1}
	var b: Array = beakers[idx]
	if segment < 0 or segment >= b.size():
		return {"start": -1, "count": 0, "color": -1}
	var color := int(b[segment])
	var start := segment
	while start > 0 and int(b[start - 1]) == color:
		start -= 1
	var end := segment
	while end + 1 < b.size() and int(b[end + 1]) == color:
		end += 1
	return {"start": start, "count": end - start + 1, "color": color}

func _can_pipette_select_segment(idx: int, segment: int) -> bool:
	if idx < 0 or idx >= beaker_count or idx >= beakers.size():
		return false
	if _is_beaker_complete(idx):
		return false
	var run := _get_pipette_run(idx, segment)
	var count := int(run["count"])
	var color := int(run["color"])
	if count <= 0 or color < 0:
		return false
	for dst in beaker_count:
		if _can_pipette_move(idx, dst, count, color):
			return true
	return false

func _can_pipette_move(src: int, dst: int, count: int, color: int) -> bool:
	if src < 0 or dst < 0 or src == dst:
		return false
	if src >= beaker_count or dst >= beaker_count or src >= beakers.size() or dst >= beakers.size():
		return false
	if _is_beaker_complete(src):
		return false
	var to: Array = beakers[dst]
	if to.is_empty():
		return count <= _get_beaker_capacity(dst)
	if int(to.back()) != color:
		return false
	return to.size() + count <= _get_beaker_capacity(dst)

func _can_pipette_destination(idx: int) -> bool:
	return _can_pipette_move(_cheat_pipette_beaker, idx, _cheat_pipette_run_count, _cheat_pipette_color)

func _select_pipette_segment(idx: int, segment: int) -> bool:
	if not _can_pipette_select_segment(idx, segment):
		return false
	var run := _get_pipette_run(idx, segment)
	_cheat_pipette_beaker = idx
	_cheat_pipette_segment = segment
	_cheat_pipette_run_start = int(run["start"])
	_cheat_pipette_run_count = int(run["count"])
	_cheat_pipette_color = int(run["color"])
	if AudioManager:
		AudioManager.play_select()
	queue_redraw()
	return true

func _start_pipette_transfer(dst: int) -> bool:
	if not _can_pipette_destination(dst):
		return false
	_store_undo_state()
	var src := _cheat_pipette_beaker
	_pipette_anim_src = src
	_pipette_anim_dst = dst
	_pipette_anim_mode = "transfer"
	_pipette_anim_run_start = _cheat_pipette_run_start
	_pipette_anim_run_count = _cheat_pipette_run_count
	_pipette_anim_color = _cheat_pipette_color
	_pipette_anim_source_point = _segment_run_center(src, _pipette_anim_run_start, _pipette_anim_run_count)
	_pipette_anim_dest_point = _destination_pipette_point(dst)
	_pipette_source_removed = false
	_pipette_destination_added = false
	_pipette_anim_progress = 0.0
	_is_animating = true
	selected_beaker = -1
	_clear_pointer_state()
	_cancel_cheat_state()
	if _pipette_anim_tween and _pipette_anim_tween.is_valid():
		_pipette_anim_tween.kill()
	var tw := create_tween().set_parallel()
	_pipette_anim_tween = tw
	tw.tween_method(_set_pipette_anim_progress, 0.0, 1.0, PIPETTE_ANIM_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_play_pipette_suck_sound).set_delay(0.36)
	tw.tween_callback(_apply_pipette_source_remove).set_delay(0.78)
	tw.tween_callback(_play_pipette_squirt_sound).set_delay(1.36)
	tw.tween_callback(_apply_pipette_destination_add).set_delay(1.64)
	tw.chain().tween_callback(_finish_pipette_transfer)
	queue_redraw()
	return true

func _set_pipette_anim_progress(value: float) -> void:
	_pipette_anim_progress = clampf(value, 0.0, 1.0)
	queue_redraw()

func _play_pipette_suck_sound() -> void:
	if not AudioManager:
		return
	if AudioManager.has_method("play_pipette_suck"):
		AudioManager.call("play_pipette_suck")
	else:
		AudioManager.play_pour()

func _play_pipette_squirt_sound() -> void:
	if not AudioManager:
		return
	if AudioManager.has_method("play_pipette_squirt"):
		AudioManager.call("play_pipette_squirt")
	else:
		AudioManager.play_pour()

func _play_pipette_stir_sound() -> void:
	if not AudioManager:
		return
	if AudioManager.has_method("play_pipette_stir"):
		AudioManager.call("play_pipette_stir")
	else:
		AudioManager.play_pour()

func _apply_pipette_stir() -> void:
	if _pipette_stir_applied:
		return
	var idx := _pipette_anim_src
	if idx < 0 or idx >= beakers.size():
		return
	beakers[idx] = _pipette_stir_result.duplicate()
	_pipette_stir_applied = true
	if idx < _vis_fill.size():
		_vis_fill[idx] = float(beakers[idx].size())
	queue_redraw()

func _finish_pipette_stir() -> void:
	_apply_pipette_stir()
	var changed_indices := [_pipette_anim_src]
	_clear_pipette_animation_state(false)
	_finish_cheat("stir", changed_indices)

func _apply_pipette_swap() -> void:
	if _pipette_swap_applied:
		return
	var idx := _pipette_anim_src
	if not _can_swap_segments(idx, _pipette_swap_first_segment, _pipette_swap_second_segment):
		return
	var b: Array = beakers[idx]
	var tmp = b[_pipette_swap_first_segment]
	b[_pipette_swap_first_segment] = b[_pipette_swap_second_segment]
	b[_pipette_swap_second_segment] = tmp
	_pipette_swap_applied = true
	if idx < _vis_fill.size():
		_vis_fill[idx] = float(b.size())
	queue_redraw()

func _finish_pipette_swap() -> void:
	_apply_pipette_swap()
	var changed_indices := [_pipette_anim_src]
	_clear_pipette_animation_state(false)
	_finish_cheat("swap", changed_indices)

func _apply_pipette_source_remove() -> void:
	if _pipette_source_removed:
		return
	var src := _pipette_anim_src
	if src < 0 or src >= beakers.size():
		return
	var b: Array = beakers[src]
	for _n in _pipette_anim_run_count:
		if _pipette_anim_run_start >= 0 and _pipette_anim_run_start < b.size():
			b.remove_at(_pipette_anim_run_start)
	_pipette_source_removed = true
	if src < _vis_fill.size():
		_vis_fill[src] = float(b.size())
	queue_redraw()

func _apply_pipette_destination_add() -> void:
	if _pipette_destination_added:
		return
	var dst := _pipette_anim_dst
	if dst < 0 or dst >= beakers.size():
		return
	var b: Array = beakers[dst]
	for _n in _pipette_anim_run_count:
		if b.size() < _get_beaker_capacity(dst):
			b.append(_pipette_anim_color)
	_pipette_destination_added = true
	if dst < _vis_fill.size():
		_vis_fill[dst] = float(b.size())
	queue_redraw()

func _finish_pipette_transfer() -> void:
	_apply_pipette_source_remove()
	_apply_pipette_destination_add()
	var changed_indices := [_pipette_anim_src, _pipette_anim_dst]
	_clear_pipette_animation_state(false)
	_finish_cheat("pipette", changed_indices)

func _clear_pipette_animation_state(kill_tween: bool = true) -> void:
	if kill_tween and _pipette_anim_tween and _pipette_anim_tween.is_valid():
		_pipette_anim_tween.kill()
	_pipette_anim_tween = null
	_pipette_anim_mode = ""
	_pipette_anim_progress = 1.0
	_pipette_anim_src = -1
	_pipette_anim_dst = -1
	_pipette_anim_run_start = -1
	_pipette_anim_run_count = 0
	_pipette_anim_color = -1
	_pipette_anim_alt_color = -1
	_pipette_anim_source_point = Vector2.ZERO
	_pipette_anim_dest_point = Vector2.ZERO
	_pipette_source_removed = false
	_pipette_destination_added = false
	_pipette_stir_result.clear()
	_pipette_stir_applied = false
	_pipette_swap_first_segment = -1
	_pipette_swap_second_segment = -1
	_pipette_swap_applied = false

func _finish_cheat(cheat_type: String, changed_indices: Array = []) -> void:
	_cancel_cheat_state()
	selected_beaker = -1
	_is_animating = false
	_clear_pour_animation_state()
	_particles.clear()
	_clear_pointer_state()
	_clear_undo_state()
	_vis_fill.resize(beaker_count)
	for i in beaker_count:
		_vis_fill[i] = float(beakers[i].size())
	_reset_finish_state()
	_sync_finished_beakers(true)
	if _reveal_hidden_cracked_beaker_if_needed(changed_indices, Callable(self, "_finish_cheat_state_change").bind(cheat_type)):
		return
	_finish_cheat_state_change(cheat_type)

func _finish_cheat_state_change(cheat_type: String) -> void:
	if _shatter_first_cracked_beaker_if_needed():
		return
	emit_signal("goal_changed", optimal_pours)
	queue_redraw()
	emit_signal("cheat_applied", cheat_type)

# ---------------------------------------------------------------------------
# Solver
# ---------------------------------------------------------------------------

func _finish_goalless_chill_mode() -> void:
	_retry_generated_solver_on_failure = false
	_generated_solver_retry = 0
	_clear_solver_state()
	optimal_pours = -1
	emit_signal("goal_changed", optimal_pours)

func _start_optimal_solver(state: Array, retry_generated_on_failure: bool = false):
	_ensure_beaker_traits()
	_retry_generated_solver_on_failure = retry_generated_on_failure
	var start := _copy_state(state)
	if _state_has_shattered_cracked_beaker(start):
		_finish_optimal_solver(-1, "cracked beaker would shatter")
		return
	if _state_complete(start):
		_finish_optimal_solver(0)
		return

	var start_key := _encode_state(start)
	_solver_queue = [_encode_exact_state(start)]
	_solver_depths = [0]
	_solver_visited = {start_key: true}
	_solver_front = 0
	_solver_searched = 0
	_solver_current_depth = 0
	_solver_next_progress_time = _time + SOLVER_PROGRESS_INTERVAL
	_solver_active = true
	optimal_pours = OPTIMAL_SOLVER_CALCULATING
	emit_signal("goal_changed", optimal_pours)
	_emit_solver_progress()

func _process_optimal_solver(max_steps: int):
	var processed := 0
	var node_limit := _get_solver_node_limit()
	var frontier_limit := _get_solver_frontier_limit()
	while _solver_active and processed < max_steps:
		if _solver_front >= _solver_queue.size():
			_finish_optimal_solver(-1, "search exhausted")
			return
		if _solver_searched >= node_limit or _solver_visited.size() >= node_limit:
			_finish_optimal_solver(-1, "state limit")
			return
		if _get_solver_frontier_size() >= frontier_limit:
			_finish_optimal_solver(-1, "frontier limit")
			return

		var state: Array = _decode_exact_state(str(_solver_queue[_solver_front]))
		var depth: int = _solver_depths[_solver_front]
		_solver_current_depth = depth
		_solver_queue[_solver_front] = null
		_solver_front += 1
		_solver_searched += 1
		processed += 1

		var seen_sources := {}
		for src in state.size():
			var from: Array = state[src]
			if from.is_empty() or _state_tube_complete_at(src, from):
				continue
			var source_key := _solver_tube_group_key(src, from)
			if seen_sources.has(source_key):
				continue
			seen_sources[source_key] = true

			var seen_destinations := {}
			var used_empty_destinations := {}
			for dst in state.size():
				if src == dst:
					continue
				var to: Array = state[dst]
				if to.is_empty():
					var destination_group := _solver_trait_group(dst)
					if used_empty_destinations.has(destination_group):
						continue
					if _state_tube_uniform(from) and _solver_trait_group(src) == destination_group:
						continue
					used_empty_destinations[destination_group] = true
				else:
					var destination_key := _solver_tube_group_key(dst, to)
					if seen_destinations.has(destination_key):
						continue
					seen_destinations[destination_key] = true

				if not _state_can_pour(state, src, dst):
					continue
				var next := _state_after_pour(state, src, dst)
				if _state_has_shattered_cracked_beaker(next):
					continue
				var key := _encode_state(next)
				if _solver_visited.has(key):
					continue
				if _state_complete(next):
					_finish_optimal_solver(depth + 1)
					return
				_solver_visited[key] = true
				_solver_queue.append(_encode_exact_state(next))
				_solver_depths.append(depth + 1)
				if _solver_visited.size() >= node_limit or _get_solver_frontier_size() >= frontier_limit:
					_finish_optimal_solver(-1, "mobile search budget" if _is_mobile_runtime() else "search budget")
					return
	_compact_solver_queue_if_needed()
	if _solver_active and processed > 0 and _time >= _solver_next_progress_time:
		_solver_next_progress_time = _time + SOLVER_PROGRESS_INTERVAL
		_emit_solver_progress()

func _finish_optimal_solver(result: int, reason: String = ""):
	var retry_generated := _retry_generated_solver_on_failure
	_retry_generated_solver_on_failure = false
	if result < 0 and retry_generated and _generated_solver_retry < GENERATED_SOLVER_RETRY_MAX:
		if reason != "":
			print("Generated puzzle rejected: %s" % reason)
		_clear_solver_state()
		optimal_pours = OPTIMAL_SOLVER_CALCULATING
		emit_signal("goal_changed", optimal_pours)
		call_deferred("generate_puzzle", _generated_solver_retry + 1)
		return
	if reason != "" and result < 0:
		print("Optimal solver stopped: %s" % reason)
	if result >= 0:
		_generated_solver_retry = 0
	_clear_solver_state()
	optimal_pours = result
	emit_signal("goal_changed", optimal_pours)

func _clear_solver_state() -> void:
	_solver_active = false
	_solver_queue.clear()
	_solver_depths.clear()
	_solver_visited.clear()
	_solver_front = 0
	_solver_searched = 0
	_solver_current_depth = 0
	_solver_next_progress_time = 0.0

func _emit_solver_progress() -> void:
	var frontier := maxi(0, _solver_queue.size() - _solver_front)
	emit_signal("solver_progress", _solver_searched, frontier, _solver_current_depth, _get_solver_node_limit())

func _compact_solver_queue_if_needed() -> void:
	if _solver_front < 4096:
		return
	if _solver_front * 2 < _solver_queue.size():
		return
	_solver_queue = _solver_queue.slice(_solver_front, _solver_queue.size())
	_solver_depths = _solver_depths.slice(_solver_front, _solver_depths.size())
	_solver_front = 0

func _get_solver_frontier_size() -> int:
	return maxi(0, _solver_queue.size() - _solver_front)

func _get_solver_node_limit() -> int:
	return SOLVER_NODE_LIMIT

func _get_solver_frontier_limit() -> int:
	return SOLVER_FRONTIER_LIMIT

func _get_solver_steps_per_frame() -> int:
	return MOBILE_SOLVER_STEPS_PER_FRAME if _is_mobile_runtime() else SOLVER_STEPS_PER_FRAME

func _is_mobile_runtime() -> bool:
	return OS.has_feature("mobile") or OS.get_name() == "Android" or OS.get_name() == "iOS"

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

func _state_tube_complete_at(idx: int, tube: Array) -> bool:
	if _is_cracked_beaker(idx):
		return false
	return _state_tube_complete(tube)

func _state_has_shattered_cracked_beaker(state: Array) -> bool:
	for idx in state.size():
		var tube: Array = state[idx]
		if _is_cracked_beaker(idx) and _state_tube_complete(tube):
			return true
	return false

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
	for idx in state.size():
		var b: Array = state[idx]
		if _is_cracked_beaker(idx):
			if not b.is_empty():
				return false
			continue
		if b.is_empty():
			continue
		if not _state_tube_complete(b):
			return false
	return true

func _encode_state(state: Array) -> String:
	var regular_tubes := PackedStringArray()
	var cracked_tubes := PackedStringArray()
	for idx in state.size():
		var b: Array = state[idx]
		var colors := PackedStringArray()
		for color in b:
			colors.append(str(int(color)))
		if _is_cracked_beaker(idx):
			cracked_tubes.append(",".join(colors))
		else:
			regular_tubes.append(",".join(colors))
	regular_tubes.sort()
	cracked_tubes.sort()
	return "C:%s|R:%s" % [";".join(cracked_tubes), ";".join(regular_tubes)]

func _solver_trait_group(idx: int) -> String:
	return "C" if _is_cracked_beaker(idx) else "R"

func _solver_tube_group_key(idx: int, tube: Array) -> String:
	return "%s:%s" % [_solver_trait_group(idx), _tube_key(tube)]

func _encode_exact_state(state: Array) -> String:
	var tubes := PackedStringArray()
	for b in state:
		var colors := PackedStringArray()
		for color in b:
			colors.append(str(int(color)))
		tubes.append(",".join(colors))
	return "|".join(tubes)

func _decode_exact_state(encoded: String) -> Array:
	var state := []
	for tube_key in encoded.split("|", true):
		var tube := []
		if tube_key != "":
			for color_key in tube_key.split(",", false):
				tube.append(int(color_key))
		state.append(tube)
	return state

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
		if _press_beaker >= 0:
			_update_pointer(event.position)
		else:
			_update_hover(event.position)
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

func _update_hover(pos: Vector2) -> void:
	var next_hover := _beaker_at(pos)
	if next_hover == _hover_beaker:
		return
	_hover_beaker = next_hover
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
	_update_hover(pos)
	if was_dragging and not _is_animating:
		queue_redraw()

func _clear_pointer_state() -> void:
	_press_beaker = -1
	_press_position = Vector2.ZERO
	_press_had_selection = false
	_dragging = false
	_drag_pos = Vector2.ZERO
	_drag_hover = -1
	_hover_beaker = -1

func clear_pointer_state() -> void:
	_clear_pointer_state()
	queue_redraw()

func _handle_cheat_input(pos: Vector2) -> void:
	if _cheat_mode == "stir":
		var idx := _beaker_at(pos)
		if _stir_beaker(idx):
			return
		if AudioManager:
			AudioManager.play_invalid()
		return

	if _cheat_mode == "pipette":
		_handle_pipette_input(pos)
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

func _handle_pipette_input(pos: Vector2) -> void:
	var dst := _beaker_at(pos)
	if _cheat_pipette_beaker >= 0 and _can_pipette_destination(dst):
		if _start_pipette_transfer(dst):
			return

	var hit := _segment_at(pos)
	var idx := int(hit["beaker"])
	var segment := int(hit["segment"])
	if idx >= 0 and segment >= 0 and _select_pipette_segment(idx, segment):
		return

	if AudioManager:
		AudioManager.play_invalid()
	queue_redraw()

func _beaker_at(pos: Vector2) -> int:
	_ensure_beaker_positions()
	for i in mini(beaker_count, beaker_positions.size()):
		var bp: Vector2 = beaker_positions[i]
		var bh := _get_beaker_visual_height(i)
		if (abs(pos.x - bp.x) <= beaker_width / 2.0 + 12
				and pos.y >= bp.y - bh - 12.0
				and pos.y <= bp.y + 12):
			return i
	return -1

func _segment_at(pos: Vector2) -> Dictionary:
	var idx := _beaker_at(pos)
	if idx < 0 or idx >= beaker_positions.size() or idx >= beakers.size():
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
	_ensure_runtime_arrays()
	_draw_bg()
	_draw_pour_stream()
	_draw_drag_path()
	var single_move_source := -1
	if selected_beaker < 0 and not _is_animating and _cheat_mode == "":
		single_move_source = get_single_available_move_source()
	for i in mini(beaker_count, beaker_positions.size()):
		_draw_beaker(i, single_move_source)
	_draw_pipette_animation()
	_draw_cracked_reveal_projectile()
	for pt in _particles:
		draw_circle(pt["pos"], pt["radius"],
				Color(pt["color"].r, pt["color"].g, pt["color"].b, pt["alpha"]))

func _draw_bg():
	var area := get_viewport_rect().size
	var center := area * 0.5
	var radius_step := maxf(area.x, area.y) * 0.056
	for i in range(10, 0, -1):
		draw_circle(center, float(i) * radius_step,
				Color(0.15, 0.25, 0.45, float(i) / 10.0 * 0.025))

func _draw_drag_path():
	if not _dragging or selected_beaker < 0 or selected_beaker >= beaker_positions.size():
		return
	var source: Vector2 = beaker_positions[selected_beaker] + Vector2(0, -_get_beaker_visual_height(selected_beaker) - 7.0)
	var legal_hover: bool = _drag_hover >= 0 and can_pour(selected_beaker, _drag_hover)
	var pour_color := _get_selected_pour_color()
	var color: Color = pour_color if legal_hover else Color(1.0, 0.86, 0.18, 1.0)
	var arc_alpha := 0.76 if legal_hover else 0.48
	var arc_width := 5.0 if legal_hover else 3.2
	_draw_liquid_arc(source, _drag_pos, color, arc_alpha, arc_width, _time * 1.25, legal_hover)
	draw_circle(_drag_pos, 11.0, Color(color.r, color.g, color.b, 0.26))
	draw_circle(_drag_pos, 5.2, Color(color.r, color.g, color.b, 0.80))
	if legal_hover:
		draw_circle(_drag_pos, 2.4, Color(1.0, 1.0, 1.0, 0.74))

func _draw_pipette_animation() -> void:
	if _pipette_anim_src < 0 or _pipette_anim_color < 0:
		return
	var t := clampf(_pipette_anim_progress, 0.0, 1.0)
	var visual_scale := _get_visual_scale()
	match _pipette_anim_mode:
		"stir":
			_draw_pipette_stir_animation(t, visual_scale)
		"swap":
			_draw_pipette_swap_animation(t, visual_scale)
		_:
			if _pipette_anim_dst >= 0:
				_draw_pipette_transfer_animation(t, visual_scale)

func _draw_pipette_transfer_animation(t: float, visual_scale: float) -> void:
	var source := _pipette_anim_source_point
	var dest := _pipette_anim_dest_point
	var entry := _pipette_top_entry_point(source, visual_scale)
	var exit := _pipette_top_entry_point(dest + Vector2(24.0 * visual_scale, 0.0), visual_scale)
	var tip := source
	if t < 0.17:
		tip = entry.lerp(source, _smoothstep_float(0.0, 0.17, t))
	elif t < 0.43:
		var wobble := Vector2(sin(t * 74.0), cos(t * 63.0)) * 1.4 * visual_scale
		tip = source + wobble
	elif t < 0.67:
		var travel := _smoothstep_float(0.43, 0.67, t)
		tip = source.lerp(dest, travel)
		tip.y -= sin(travel * PI) * 52.0 * visual_scale
	elif t < 0.93:
		var wobble := Vector2(sin(t * 66.0), cos(t * 71.0)) * 1.2 * visual_scale
		tip = dest + wobble
	else:
		tip = dest.lerp(exit, _smoothstep_float(0.93, 1.0, t))

	var color := _get_liquid_color(_pipette_anim_color)
	var fill_amount := _smoothstep_float(0.19, 0.40, t) * (1.0 - _smoothstep_float(0.70, 0.94, t) * 0.92)
	var alpha := _smoothstep_float(0.0, 0.08, t) * (1.0 - _smoothstep_float(0.95, 1.0, t) * 0.85)
	var angle := PI * 0.5
	if t > 0.43 and t < 0.67:
		var travel := _smoothstep_float(0.43, 0.67, t)
		var lean := clampf((dest.x - source.x) / maxf(1.0, source.distance_to(dest)), -1.0, 1.0) * 0.18
		angle += lean * sin(travel * PI)

	if t >= 0.18 and t <= 0.43:
		var suction := _smoothstep_float(0.18, 0.28, t) * (1.0 - _smoothstep_float(0.36, 0.43, t))
		_draw_pipette_suction(source, tip, color, suction, visual_scale)
	if t >= 0.67 and t <= 0.94:
		var squirt := _smoothstep_float(0.67, 0.75, t) * (1.0 - _smoothstep_float(0.88, 0.94, t))
		_draw_pipette_squirt(tip, dest, color, squirt, visual_scale)

	_draw_pipette_tool(tip, angle, visual_scale, color, fill_amount, alpha)

func _draw_pipette_stir_animation(t: float, visual_scale: float) -> void:
	var center := _pipette_anim_source_point
	var entry := _pipette_top_entry_point(center, visual_scale)
	var exit := _pipette_top_entry_point(center + Vector2(24.0 * visual_scale, 0.0), visual_scale)
	var tip := center
	var lift_point := center + Vector2(0.0, -18.0 * visual_scale)
	if t < 0.18:
		tip = entry.lerp(center, _smoothstep_float(0.0, 0.18, t))
	elif t < 0.76:
		var stir_t := _smoothstep_float(0.18, 0.76, t)
		var spin := stir_t * TAU * 3.25 + sin(_time * 1.6) * 0.14
		var radius_x := maxf(8.0 * visual_scale, float(beaker_width) * 0.20)
		var radius_y := maxf(5.0 * visual_scale, float(liquid_unit_height) * 0.36)
		tip = center + Vector2(cos(spin) * radius_x, sin(spin) * radius_y)
	elif t < 0.90:
		tip = center.lerp(lift_point, _smoothstep_float(0.76, 0.90, t))
	else:
		tip = lift_point.lerp(exit, _smoothstep_float(0.90, 1.0, t))

	var color := _get_liquid_color(_pipette_anim_color)
	var stir_strength := _smoothstep_float(0.15, 0.28, t) * (1.0 - _smoothstep_float(0.74, 0.96, t))
	if stir_strength > 0.0:
		_draw_pipette_stir_wake(center, color, stir_strength, visual_scale)

	var alpha := _smoothstep_float(0.0, 0.10, t) * (1.0 - _smoothstep_float(0.92, 1.0, t) * 0.86)
	var fill_amount := 0.16 * stir_strength + 0.06 * maxf(0.0, sin(_time * 9.0))
	var angle := PI * 0.5 + sin(_time * 9.5) * 0.18 * stir_strength
	_draw_pipette_tool(tip, angle, visual_scale, color, fill_amount, alpha)

func _draw_pipette_swap_animation(t: float, visual_scale: float) -> void:
	var source := _pipette_anim_source_point
	var dest := _pipette_anim_dest_point
	var swap_dir := 1.0 if source.y >= dest.y else -1.0
	var inject := dest + Vector2(0.0, -swap_dir * float(liquid_unit_height) * 0.28)
	var entry := _pipette_top_entry_point(source, visual_scale)
	var exit := _pipette_top_entry_point(inject, visual_scale)
	var tip := source
	if t < 0.18:
		tip = entry.lerp(source, _smoothstep_float(0.0, 0.18, t))
	elif t < 0.40:
		var wobble := Vector2(sin(t * 86.0), cos(t * 72.0)) * 1.15 * visual_scale
		tip = source + wobble
	elif t < 0.66:
		var travel := _smoothstep_float(0.40, 0.66, t)
		tip = source.lerp(inject, travel)
		tip.y -= sin(travel * PI) * 18.0 * visual_scale
	elif t < 0.88:
		var wobble := Vector2(sin(t * 76.0), cos(t * 83.0)) * 1.1 * visual_scale
		tip = inject + wobble
	else:
		tip = inject.lerp(exit, _smoothstep_float(0.88, 1.0, t))

	var color := _get_liquid_color(_pipette_anim_color)
	var other_color := _get_liquid_color(_pipette_anim_alt_color)
	var alpha := _smoothstep_float(0.0, 0.10, t) * (1.0 - _smoothstep_float(0.92, 1.0, t) * 0.84)
	var fill_amount := _smoothstep_float(0.20, 0.38, t) * (1.0 - _smoothstep_float(0.58, 0.82, t))
	var suction := _smoothstep_float(0.18, 0.28, t) * (1.0 - _smoothstep_float(0.34, 0.42, t))
	var squirt := _smoothstep_float(0.56, 0.66, t) * (1.0 - _smoothstep_float(0.78, 0.88, t))
	if suction > 0.0:
		_draw_pipette_suction(source, tip, color, suction, visual_scale)
	if squirt > 0.0:
		_draw_pipette_squirt(tip, inject, color, squirt, visual_scale)
		var ring_alpha := 0.38 * squirt
		_draw_ellipse_outline(inject, Vector2(float(beaker_width) * 0.22, float(liquid_unit_height) * 0.22),
				Color(other_color.r, other_color.g, other_color.b, ring_alpha), maxf(1.4, 2.0 * visual_scale))

	var angle := PI * 0.5 + sin(_time * 8.0) * 0.04
	_draw_pipette_tool(tip, angle, visual_scale, color, fill_amount, alpha)

func _pipette_top_entry_point(target: Vector2, visual_scale: float) -> Vector2:
	return Vector2(target.x, -112.0 * visual_scale)

func _draw_pipette_stir_wake(center: Vector2, color: Color, strength: float, visual_scale: float) -> void:
	var radius_x := maxf(10.0 * visual_scale, float(beaker_width) * 0.25)
	var radius_y := maxf(5.0 * visual_scale, float(liquid_unit_height) * 0.34)
	for i in 3:
		var phase := _time * (5.0 + float(i) * 0.42) + float(i) * TAU / 3.0
		var arc_color := Color(color.r, color.g, color.b, (0.28 - float(i) * 0.045) * strength)
		var radii := Vector2(radius_x * (1.0 - float(i) * 0.16), radius_y * (1.0 - float(i) * 0.10))
		_draw_ellipse_arc(center, radii, phase, phase + PI * 1.35, arc_color, maxf(1.6, 3.0 * visual_scale * strength))
	for i in 4:
		var drift := _time * 3.2 + float(i) * 0.63
		var p := center + Vector2(cos(drift) * radius_x * 0.70, sin(drift * 1.22) * radius_y * 0.72)
		draw_circle(p, (2.1 + float(i % 2)) * visual_scale * strength,
				Color(1.0, 1.0, 1.0, 0.22 * strength))

func _draw_pipette_suction(source: Vector2, tip: Vector2, color: Color, strength: float, visual_scale: float) -> void:
	if strength <= 0.0:
		return
	for i in 5:
		var phase := fposmod(_time * 2.8 + float(i) * 0.18, 1.0)
		var p := source.lerp(tip, phase)
		p += Vector2(sin(_time * 8.0 + float(i)) * 4.0, cos(_time * 7.0 + float(i) * 0.6) * 2.0) * visual_scale
		var radius := (3.6 + float(i % 2) * 1.2) * visual_scale * strength
		draw_circle(p, radius + 1.4 * visual_scale, Color(1.0, 1.0, 1.0, 0.18 * strength))
		draw_circle(p, radius, Color(color.r, color.g, color.b, 0.78 * strength))
	_draw_liquid_arc(source, tip, color, 0.42 * strength, 3.5 * visual_scale, _time * 3.2, true)

func _draw_pipette_squirt(tip: Vector2, dest: Vector2, color: Color, strength: float, visual_scale: float) -> void:
	if strength <= 0.0:
		return
	_draw_liquid_arc(tip, dest, color, 0.76 * strength, 5.0 * visual_scale, _time * 4.4, true)
	for i in 4:
		var phase := fposmod(_time * 3.7 + float(i) * 0.22, 1.0)
		var p := tip.lerp(dest, phase)
		var radius := (3.0 + float(i % 2)) * visual_scale * strength
		draw_circle(p, radius, Color(color.r, color.g, color.b, 0.82 * strength))

func _draw_pipette_tool(tip: Vector2, angle: float, visual_scale: float, fill_color: Color, fill_amount: float, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var axis := Vector2(cos(angle), sin(angle))
	var normal := Vector2(-axis.y, axis.x)
	var length := 112.0 * visual_scale
	var barrel_start := tip - axis * length
	var barrel_end := tip - axis * 12.0 * visual_scale
	var bulb_center := barrel_start - axis * 18.0 * visual_scale
	var tip_base := tip - axis * 18.0 * visual_scale
	var glass := Color(0.84, 0.96, 1.0, 0.34 * alpha)
	var rim := Color(0.96, 1.0, 1.0, 0.78 * alpha)
	var shadow := Color(0.0, 0.0, 0.0, 0.26 * alpha)
	draw_line(bulb_center + normal * 5.0 * visual_scale, tip + normal * 5.0 * visual_scale,
			shadow, 10.0 * visual_scale, true)
	draw_line(barrel_start, barrel_end, glass, 18.0 * visual_scale, true)
	draw_line(barrel_start, barrel_end, rim, 3.2 * visual_scale, true)
	draw_line(barrel_start + normal * 4.8 * visual_scale, barrel_end + normal * 4.8 * visual_scale,
			Color(1.0, 1.0, 1.0, 0.30 * alpha), 2.0 * visual_scale, true)

	if fill_amount > 0.0:
		var fill_start := barrel_end.lerp(barrel_start, clampf(fill_amount, 0.0, 1.0))
		draw_line(fill_start, barrel_end,
				Color(fill_color.r, fill_color.g, fill_color.b, 0.86 * alpha), 9.0 * visual_scale, true)
		draw_line(fill_start + normal * 2.2 * visual_scale, barrel_end + normal * 2.2 * visual_scale,
				Color(1.0, 1.0, 1.0, 0.22 * alpha), 2.0 * visual_scale, true)

	draw_line(tip_base, tip, Color(0.84, 0.96, 1.0, 0.52 * alpha), 7.0 * visual_scale, true)
	draw_line(tip_base, tip, rim, 1.8 * visual_scale, true)
	draw_circle(tip, 3.0 * visual_scale, Color(0.96, 1.0, 1.0, 0.86 * alpha))
	draw_circle(tip, 1.4 * visual_scale, Color(fill_color.r, fill_color.g, fill_color.b, 0.72 * alpha))

	var bulb_r := 20.0 * visual_scale
	_draw_ellipse_filled(bulb_center, Vector2(bulb_r * 1.04, bulb_r * 0.88), Color(0.74, 0.90, 1.0, 0.25 * alpha))
	_draw_ellipse_outline(bulb_center, Vector2(bulb_r * 1.04, bulb_r * 0.88), rim, 2.2 * visual_scale)
	_draw_ellipse_filled(bulb_center - normal * 4.5 * visual_scale - axis * 2.0 * visual_scale,
			Vector2(bulb_r * 0.36, bulb_r * 0.18), Color(1.0, 1.0, 1.0, 0.24 * alpha))
	if fill_amount > 0.18:
		_draw_ellipse_filled(bulb_center + axis * 3.0 * visual_scale,
				Vector2(bulb_r * 0.50, bulb_r * 0.34),
				Color(fill_color.r, fill_color.g, fill_color.b, 0.26 * alpha * fill_amount))

func _draw_cracked_reveal_projectile() -> void:
	if _cracked_reveal_idx < 0 or _cracked_reveal_idx >= beaker_positions.size():
		return
	var idx := _cracked_reveal_idx
	var base_pos: Vector2 = beaker_positions[idx]
	var hw := float(beaker_width) / 2.0
	var bh := _get_beaker_visual_height(idx)
	var tag_radius := _get_trait_tag_radius(hw)
	var target := _get_trait_tag_center(base_pos, hw, bh, tag_radius)
	var area := get_viewport_rect().size
	var visual_scale := _get_visual_scale()
	var start := Vector2(area.x + tag_radius * 4.5, target.y - 46.0 * visual_scale)
	var t := clampf(_cracked_reveal_progress, 0.0, 1.0)
	var center := _cracked_reveal_path_point(start, target, t, visual_scale)
	for trail_idx in 5:
		var trail_t := clampf(t - 0.045 * float(trail_idx + 1), 0.0, 1.0)
		if trail_t <= 0.0:
			continue
		var trail_center := _cracked_reveal_path_point(start, target, trail_t, visual_scale)
		var alpha := (1.0 - float(trail_idx) / 5.0) * 0.16 * t
		draw_circle(trail_center, tag_radius * (0.78 - float(trail_idx) * 0.08),
				Color(0.82, 0.88, 0.95, alpha))
	var impact := _smoothstep_float(0.74, 1.0, t)
	if impact > 0.0:
		var ring_alpha := (1.0 - impact) * 0.72
		_draw_ellipse_outline(target, Vector2(tag_radius + impact * 15.0 * visual_scale, tag_radius + impact * 8.0 * visual_scale),
				Color(0.94, 0.99, 1.0, ring_alpha), maxf(1.4, 2.0 * visual_scale))
		center += Vector2(sin(t * 96.0), cos(t * 84.0)) * (1.0 - impact) * 2.6 * visual_scale
	var stone_radius := tag_radius * lerpf(1.08, 0.88, t)
	_draw_thrown_cracked_stone(center, stone_radius, t * TAU * 1.75)

func _cracked_reveal_path_point(start: Vector2, target: Vector2, t: float, visual_scale: float) -> Vector2:
	var p := start.lerp(target, t)
	p.y -= sin(t * PI) * 66.0 * visual_scale
	return p

func _draw_thrown_cracked_stone(center: Vector2, radius: float, rotation: float) -> void:
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var base := Color(0.36, 0.39, 0.42, 0.98)
	for i in 10:
		var angle := rotation + float(i) * TAU / 10.0
		var wobble := 0.90 + 0.14 * sin(float(i) * 2.21 + 0.6)
		var point := center + Vector2(cos(angle), sin(angle)) * radius * wobble
		points.append(point)
		colors.append(base.lightened(0.13 if i < 4 else 0.0))
	draw_polygon(points, colors)
	var outline := PackedVector2Array(points)
	outline.append(points[0])
	draw_polyline(outline, Color(0.06, 0.07, 0.09, 0.88), maxf(1.8, radius * 0.13), true)
	draw_circle(center + _rotated_offset(Vector2(-radius * 0.20, -radius * 0.24), rotation), radius * 0.22,
			Color(0.78, 0.82, 0.86, 0.32))
	var crack := PackedVector2Array([
		center + _rotated_offset(Vector2(-radius * 0.10, -radius * 0.55), rotation),
		center + _rotated_offset(Vector2(radius * 0.12, -radius * 0.16), rotation),
		center + _rotated_offset(Vector2(-radius * 0.04, radius * 0.10), rotation),
		center + _rotated_offset(Vector2(radius * 0.24, radius * 0.50), rotation),
	])
	draw_polyline(crack, Color(0.96, 0.99, 1.0, 0.82), maxf(1.8, radius * 0.16), true)
	draw_polyline(crack, Color(0.02, 0.025, 0.04, 0.92), maxf(1.0, radius * 0.07), true)

func _rotated_offset(offset: Vector2, angle: float) -> Vector2:
	return Vector2(
			offset.x * cos(angle) - offset.y * sin(angle),
			offset.x * sin(angle) + offset.y * cos(angle))

func _draw_pour_stream() -> void:
	if not _is_animating or _anim_src < 0 or _anim_dst < 0 or _anim_color < 0:
		return
	if _anim_src >= beaker_positions.size() or _anim_dst >= beaker_positions.size():
		return
	var src_pos: Vector2 = beaker_positions[_anim_src]
	var dst_pos: Vector2 = beaker_positions[_anim_dst]
	var direction := 1.0 if dst_pos.x >= src_pos.x else -1.0
	var source := src_pos + Vector2(direction * float(beaker_width) * 0.28, -_get_beaker_visual_height(_anim_src) - 7.0)
	var target := dst_pos + Vector2(-direction * float(beaker_width) * 0.20, -_get_beaker_visual_height(_anim_dst) - 6.0)
	var alpha := _smoothstep_float(0.02, 0.18, _pour_stream_progress) * (1.0 - _smoothstep_float(0.78, 1.0, _pour_stream_progress))
	if alpha <= 0.01:
		return
	var color := _get_liquid_color(_anim_color)
	_draw_liquid_arc(source, target, color, 0.94 * alpha, 7.0, _time * 1.8 + _pour_stream_progress * 2.8, true)

func _draw_liquid_arc(source: Vector2, target: Vector2, color: Color, alpha: float, width: float, flow: float, energetic: bool) -> void:
	if alpha <= 0.01:
		return
	var distance := source.distance_to(target)
	var lift := clampf(distance * 0.27, 34.0, 86.0)
	var control := (source + target) * 0.5 + Vector2(0.0, -lift)
	var points := PackedVector2Array()
	var point_count := 26
	for i in point_count:
		var curve_t := float(i) / float(point_count - 1)
		points.append(_quadratic_bezier(source, control, target, curve_t))
	var shadow := Color(color.r * 0.36, color.g * 0.36, color.b * 0.42, alpha * 0.30)
	draw_polyline(points, shadow, width + 3.4, true)
	draw_polyline(points, Color(color.r, color.g, color.b, alpha), width, true)
	draw_polyline(points, Color(1.0, 1.0, 1.0, alpha * 0.50), maxf(1.2, width * 0.24), true)
	var droplet_count := 6 if energetic else 3
	for i in droplet_count:
		var drop_t := fmod(flow + float(i) / float(droplet_count), 1.0)
		var p := _quadratic_bezier(source, control, target, drop_t)
		var radius := (2.0 + 2.2 * sin(drop_t * PI)) if energetic else 2.0
		draw_circle(p, radius + 1.2, Color(0.0, 0.0, 0.0, alpha * 0.12))
		draw_circle(p, radius, Color(color.r, color.g, color.b, alpha * 0.88))
		draw_circle(p + Vector2(-radius * 0.28, -radius * 0.30), maxf(0.9, radius * 0.34),
				Color(1.0, 1.0, 1.0, alpha * 0.58))

func _quadratic_bezier(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * u * u + b * 2.0 * u * t + c * t * t

func _smoothstep_float(edge0: float, edge1: float, value: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 0.0
	var x := clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

func _pseudo_random01(seed: int) -> float:
	var raw := sin(float(seed) * 12.9898) * 43758.5453
	return raw - floor(raw)

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
	if not GameSettings.show_liquid_symbols or h < 8.0 or w < 10.0:
		return
	var symbol := _get_liquid_symbol(color_idx)
	if symbol.is_empty():
		return
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var ink := Color(1.0, 0.98, 0.88, 0.98)
	var outline := Color(0.01, 0.015, 0.03, 0.78)
	var font_size := int(clampf(minf(h * 0.86, w * 0.62), 13.0, 34.0 * _get_visual_scale()))
	var baseline := Vector2(x, y + h * 0.5 + float(font_size) * 0.36)
	var outline_px := maxf(1.0, float(font_size) * 0.065)
	_draw_centered_liquid_symbol(font, symbol, baseline, w, font_size, ink, outline, outline_px)

func _get_liquid_symbol(color_idx: int) -> String:
	var symbols := GameSettings.get_liquid_symbols()
	if symbols.is_empty():
		return ""
	return str(symbols[color_idx % symbols.size()])

func _draw_centered_liquid_symbol(font: Font, symbol: String, baseline: Vector2, width: float,
		font_size: int, ink: Color, outline: Color, outline_px: float,
		include_diagonals: bool = false) -> void:
	var offsets := [
		Vector2(-outline_px, 0.0),
		Vector2(outline_px, 0.0),
		Vector2(0.0, -outline_px),
		Vector2(0.0, outline_px),
	]
	if include_diagonals:
		offsets.append(Vector2(-outline_px * 0.68, -outline_px * 0.68))
		offsets.append(Vector2(outline_px * 0.68, outline_px * 0.68))
	for offset in offsets:
		draw_string(font, baseline + offset, symbol, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, outline)
	draw_string(font, baseline, symbol, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, ink)

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
	if selected_beaker < 0 or selected_beaker >= beaker_count or selected_beaker >= beakers.size():
		return Color(0.86, 0.90, 0.96)
	var b: Array = beakers[selected_beaker]
	if b.is_empty():
		return Color(0.86, 0.90, 0.96)
	return _get_liquid_color(int(b.back()))

func _draw_beaker(idx: int, single_move_source: int = -1):
	if idx < 0 or idx >= beaker_positions.size() or idx >= beakers.size() or idx >= _vis_fill.size():
		return
	var base_pos: Vector2 = beaker_positions[idx]
	var hw   := float(beaker_width) / 2.0
	var bh   := _get_beaker_visual_height(idx)
	var isel := (idx == selected_beaker)
	var is_finished := _is_beaker_complete(idx)
	var is_target := selected_beaker >= 0 and idx != selected_beaker and can_pour(selected_beaker, idx)
	var is_hover := (idx == _hover_beaker and not isel and not is_target
			and not _dragging and not _is_animating and _cheat_mode == "")
	var pos := base_pos + _get_beaker_visual_offset(idx, isel, is_target, is_hover)
	var selected_pulse := 0.0
	if isel:
		selected_pulse = 0.5 + 0.5 * sin(_time * 6.8)
		var selected_scale := 1.045 + selected_pulse * 0.030
		draw_set_transform(pos, 0.0, Vector2(selected_scale, selected_scale))
		pos = Vector2.ZERO

	_draw_beaker_shadow(pos, hw, bh, isel or is_hover or is_target)

	if is_finished:
		_draw_finished_beaker_glow(idx, pos, hw, bh)

	if is_target:
		var target_color := _get_selected_pour_color()
		var strength := 1.08 if idx == _drag_hover else 0.82
		_draw_beaker_halo(pos, hw, bh, target_color, strength, idx == _drag_hover)
	if isel:
		var selected_color := _get_selected_pour_color()
		_draw_beaker_halo(pos, hw, bh, selected_color, 1.55 + selected_pulse * 0.22, true)
	elif is_hover:
		_draw_beaker_halo(pos, hw, bh, Color(0.74, 0.92, 1.0, 1.0), 0.38, false)
	elif idx == single_move_source:
		_draw_beaker_halo(pos, hw, bh, Color(1.0, 0.86, 0.24, 1.0), 1.04, true)
		_draw_single_move_frame(pos, hw, bh)

	if _cheat_mode != "":
		_draw_cheat_highlight(idx, pos, hw, bh)

	_draw_beaker_trait(idx, pos, hw, bh, false)

	_draw_glass_interior(pos, hw, bh)

	var color_data: Array
	if idx == _anim_src and _is_animating:
		color_data = _anim_src_snap
	else:
		color_data = beakers[idx]
	var vis: float = _vis_fill[idx]
	var top_visible_segment := -1
	if not color_data.is_empty() and vis > 0.0:
		top_visible_segment = clampi(int(ceil(vis)) - 1, 0, color_data.size() - 1)
	for ui in color_data.size():
		var f0 := float(ui)
		var f1 := minf(float(ui + 1), vis)
		if f1 <= f0:
			break
		var col: Color = _get_liquid_color(int(color_data[ui]))
		var y_top := pos.y - f1 * float(liquid_unit_height)
		var y_bottom := pos.y - f0 * float(liquid_unit_height)
		_draw_liquid_segment(pos, hw, bh, y_top, y_bottom, col, int(color_data[ui]), ui, ui == top_visible_segment)

	if is_finished and not color_data.is_empty():
		_draw_finished_bubbles(idx, pos, hw, bh, int(color_data[0]))

	_draw_glass_shell(idx, pos, hw, bh, isel, is_hover, is_finished)
	if isel:
		_draw_selected_source_marker(pos, hw, bh, _get_selected_pour_color())
	_draw_beaker_trait(idx, pos, hw, bh, true)
	if is_finished and not color_data.is_empty():
		_draw_finished_beaker_symbol(pos, hw, bh, int(color_data[0]))
	else:
		_draw_liquid_symbols_for_beaker(pos, hw, bh, color_data, vis)
	if is_finished:
		_draw_finished_beaker_lid(idx, pos, hw, bh)
	if isel:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _get_beaker_visual_offset(idx: int, is_selected: bool, _is_target: bool, is_hover: bool) -> Vector2:
	var lift := 0.0
	if _is_animating and idx == _anim_src:
		lift -= 4.0 + 2.0 * sin(_pour_stream_progress * PI)
	elif _is_animating and idx == _anim_dst:
		lift -= 2.0 * sin(_pour_stream_progress * PI)
	elif is_selected:
		lift -= 6.0 + 1.2 * sin(_time * 5.5)
	elif is_hover:
		lift -= 3.0 + 0.7 * sin(_time * 6.0)
	return Vector2(0.0, lift)

func _draw_beaker_shadow(pos: Vector2, hw: float, _bh: float, active: bool) -> void:
	var alpha := 0.30 if active else 0.20
	_draw_ellipse_filled(Vector2(pos.x, pos.y + 9.0), Vector2(hw * 0.88, 7.5), Color(0.0, 0.0, 0.0, alpha))
	_draw_ellipse_filled(Vector2(pos.x, pos.y + 5.0), Vector2(hw * 0.58, 3.8), Color(0.0, 0.0, 0.0, alpha * 0.34))

func _draw_beaker_halo(pos: Vector2, hw: float, bh: float, color: Color, strength: float, hot: bool) -> void:
	var pulse := 0.74 + 0.26 * sin(_time * 7.0)
	var center := Vector2(pos.x, pos.y - bh * 0.48)
	for layer in 4:
		var t := float(layer) / 3.0
		var grow := lerpf(28.0, 4.0, t) + (8.0 * pulse if hot else 0.0)
		var alpha := strength * (1.0 - t) * (0.075 + 0.028 * pulse)
		_draw_ellipse_filled(center, Vector2(hw + grow, bh * 0.50 + grow * 0.88),
				Color(color.r, color.g, color.b, alpha))
	var outline := Color(color.r, color.g, color.b, 0.64 + 0.22 * pulse).lightened(0.18)
	var outline_hw := hw + (5.0 if hot else 3.0)
	var outline_bh := bh + (4.0 if hot else 2.0)
	var outline_width := 2.4 if hot else 1.6
	_draw_tube_outline(pos, outline_hw, outline_bh, outline, outline_width)
	if hot:
		_draw_ellipse_arc(Vector2(pos.x, pos.y - bh - 1.5), Vector2(hw + 6.8, 5.8),
				PI, 0.0, Color(1.0, 1.0, 1.0, 0.58), 2.0)

func _draw_single_move_frame(pos: Vector2, hw: float, bh: float) -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 6.5)
	var gold := Color(1.0, 0.86, 0.22, 0.82 + 0.16 * pulse)
	var outer_hw := hw + 8.0 + pulse * 4.0
	var outer_bh := bh + 6.0 + pulse * 3.0
	_draw_tube_outline(pos, outer_hw, outer_bh, gold, 3.8 + pulse)
	_draw_tube_outline(pos, outer_hw + 4.0, outer_bh + 4.0,
			Color(1.0, 0.96, 0.45, 0.18 + 0.12 * pulse), 2.0)
	_draw_ellipse_arc(Vector2(pos.x, pos.y - bh - 2.0),
			Vector2(hw + 12.0 + pulse * 3.0, 7.0 + pulse * 1.4),
			PI, 0.0, Color(1.0, 1.0, 0.75, 0.78 + 0.18 * pulse), 2.6 + pulse)

func _draw_selected_source_marker(pos: Vector2, hw: float, bh: float, pour_color: Color) -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 7.8)
	var source_gold := Color(1.0, 0.92, 0.30, 0.88 + 0.10 * pulse)
	var source_white := Color(1.0, 1.0, 0.92, 0.82 + 0.12 * pulse)
	_draw_tube_outline(pos, hw + 11.0 + pulse * 3.0, bh + 8.0 + pulse * 2.0,
			source_gold, 4.0 + pulse * 0.8)
	_draw_tube_outline(pos, hw + 16.0 + pulse * 5.0, bh + 12.0 + pulse * 3.5,
			Color(1.0, 0.92, 0.30, 0.28 + pulse * 0.16), 2.0 + pulse * 0.6)
	_draw_tube_outline(pos, hw + 2.8, bh + 2.0,
			Color(pour_color.r, pour_color.g, pour_color.b, 0.92).lightened(0.30), 2.4)
	var top_center := Vector2(pos.x, pos.y - bh - 18.0)
	var pointer := PackedVector2Array([
		top_center + Vector2(0.0, -10.0 - pulse * 2.0),
		top_center + Vector2(-10.0, 7.0),
		top_center + Vector2(10.0, 7.0),
	])
	draw_polygon(pointer, PackedColorArray([source_gold, source_gold, source_gold]))
	draw_polyline(PackedVector2Array([pointer[0], pointer[1], pointer[2], pointer[0]]),
			Color(0.05, 0.06, 0.08, 0.84), 2.0, true)
	draw_circle(top_center + Vector2(0.0, 9.0), 4.0 + pulse * 1.4, source_white)
	_draw_ellipse_arc(Vector2(pos.x, pos.y - bh - 1.8),
			Vector2(hw + 12.0 + pulse * 2.4, 7.4 + pulse),
			PI, 0.0, source_white, 2.8 + pulse * 0.5)

func _draw_glass_interior(pos: Vector2, hw: float, bh: float) -> void:
	var top_y := pos.y - bh
	var bottom_y := pos.y - 6.0
	var top_hw := _tube_inner_half_width_at(pos, hw, bh, top_y + 2.0)
	var bottom_hw := _tube_inner_half_width_at(pos, hw, bh, bottom_y)
	draw_polygon(PackedVector2Array([
		Vector2(pos.x - top_hw, top_y + 3.0),
		Vector2(pos.x + top_hw, top_y + 3.0),
		Vector2(pos.x + bottom_hw, bottom_y),
		Vector2(pos.x - bottom_hw, bottom_y),
	]), PackedColorArray([
		Color(0.03, 0.055, 0.085, 0.20),
		Color(0.08, 0.14, 0.18, 0.15),
		Color(0.02, 0.035, 0.055, 0.23),
		Color(0.01, 0.025, 0.045, 0.27),
	]))
	_draw_ellipse_filled(Vector2(pos.x, bottom_y), Vector2(bottom_hw, 7.0), Color(0.0, 0.0, 0.0, 0.045))
	_draw_ellipse_filled(Vector2(pos.x, top_y + 1.0), Vector2(top_hw, 5.6), Color(0.01, 0.018, 0.030, 0.20))

func _draw_liquid_segment(pos: Vector2, hw: float, bh: float, y_top: float, y_bottom: float,
		col: Color, color_idx: int, segment_idx: int, draw_surface: bool) -> void:
	if y_bottom - y_top < 1.0:
		return
	var alpha := _get_liquid_alpha()
	var visual_top_y := y_top
	var reaches_bottom := y_bottom >= pos.y - 1.0
	var body_bottom_y := pos.y - 7.0 if reaches_bottom else y_bottom
	if body_bottom_y - visual_top_y < 1.0:
		return
	var top_hw := maxf(4.0, _liquid_half_width_at(pos, hw, bh, visual_top_y))
	var bottom_hw := maxf(4.0, _liquid_half_width_at(pos, hw, bh, body_bottom_y))
	var edge_col := Color(col.r, col.g, col.b, alpha).darkened(0.42)
	var center_col := Color(col.r, col.g, col.b, alpha).lightened(0.17)
	var center := pos.x
	if reaches_bottom:
		var bottom_radii := _liquid_surface_radii_at(pos, hw, bh, body_bottom_y, bottom_hw)
		_draw_liquid_bottom_fill(Vector2(center, body_bottom_y), bottom_radii, col, alpha)

	draw_polygon(PackedVector2Array([
		Vector2(center - top_hw, visual_top_y),
		Vector2(center, visual_top_y),
		Vector2(center, body_bottom_y),
		Vector2(center - bottom_hw, body_bottom_y),
	]), PackedColorArray([edge_col, center_col, center_col.darkened(0.05), edge_col.darkened(0.08)]))
	draw_polygon(PackedVector2Array([
		Vector2(center, visual_top_y),
		Vector2(center + top_hw, visual_top_y),
		Vector2(center + bottom_hw, body_bottom_y),
		Vector2(center, body_bottom_y),
	]), PackedColorArray([center_col, edge_col, edge_col.darkened(0.07), center_col.darkened(0.03)]))

	var highlight_top_x := center - top_hw * 0.50
	var highlight_bottom_x := center - bottom_hw * 0.46
	var highlight_w_top := maxf(3.0, top_hw * 0.18)
	var highlight_w_bottom := maxf(3.0, bottom_hw * 0.16)
	draw_polygon(PackedVector2Array([
		Vector2(highlight_top_x, visual_top_y + 1.0),
		Vector2(highlight_top_x + highlight_w_top, visual_top_y + 1.0),
		Vector2(highlight_bottom_x + highlight_w_bottom, body_bottom_y - 1.0),
		Vector2(highlight_bottom_x, body_bottom_y - 1.0),
	]), PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.11),
		Color(1.0, 1.0, 1.0, 0.025),
		Color(1.0, 1.0, 1.0, 0.014),
		Color(1.0, 1.0, 1.0, 0.08),
	]))

	var texture_hw := minf(top_hw, bottom_hw)
	var texture_x := center - texture_hw + 5.0
	var texture_w := texture_hw * 2.0 - 10.0
	if texture_w > 10.0:
		_draw_liquid_texture(texture_x, visual_top_y + 3.0, texture_w, maxf(0.0, body_bottom_y - visual_top_y - 5.0), color_idx, segment_idx)

	var surface_center := Vector2(center, visual_top_y + 1.0)
	var surface_radii := _liquid_surface_radii_at(pos, hw, bh, visual_top_y, top_hw)
	var surface_col := Color(col.r, col.g, col.b, minf(1.0, alpha + 0.08)).lightened(0.22)
	if draw_surface:
		_draw_ellipse_filled(surface_center, surface_radii, surface_col)
		_draw_ellipse_arc(surface_center + Vector2(0.0, -0.2), surface_radii,
				PI, 0.0, Color(1.0, 1.0, 1.0, 0.12), 1.2)
	elif segment_idx > 0:
		_draw_ellipse_arc(surface_center, Vector2(top_hw, surface_radii.y * 0.70),
				PI, 0.0, Color(1.0, 1.0, 1.0, 0.05), 1.0)

func _draw_liquid_bottom_fill(center: Vector2, radii: Vector2, col: Color, alpha: float) -> void:
	var base := Color(col.r, col.g, col.b, alpha).lightened(0.04)
	_draw_ellipse_filled(center, Vector2(radii.x, radii.y * 0.98), base)
	_draw_ellipse_filled(center + Vector2(0.0, radii.y * 0.30), Vector2(radii.x * 0.88, radii.y * 0.44),
			Color(col.r, col.g, col.b, alpha * 0.18).darkened(0.08))

func _draw_liquid_symbols_for_beaker(pos: Vector2, hw: float, bh: float, color_data: Array, vis: float) -> void:
	if not GameSettings.show_liquid_symbols or color_data.is_empty() or vis <= 0.0:
		return
	for ui in color_data.size():
		var f0 := float(ui)
		var f1 := minf(float(ui + 1), vis)
		if f1 <= f0:
			break
		var y_top := pos.y - f1 * float(liquid_unit_height)
		var y_bottom := pos.y - f0 * float(liquid_unit_height)
		if y_bottom >= pos.y - 1.0:
			y_bottom = pos.y - 7.0
		var top_hw := maxf(4.0, _liquid_half_width_at(pos, hw, bh, y_top))
		var bottom_hw := maxf(4.0, _liquid_half_width_at(pos, hw, bh, y_bottom))
		var symbol_hw := minf(top_hw, bottom_hw)
		_draw_liquid_symbol(pos.x - symbol_hw, y_top, symbol_hw * 2.0, y_bottom - y_top, int(color_data[ui]))

func _draw_finished_beaker_symbol(pos: Vector2, hw: float, bh: float, color_idx: int) -> void:
	if not GameSettings.show_liquid_symbols:
		return
	var symbol := _get_liquid_symbol(color_idx)
	if symbol.is_empty():
		return
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var visual_scale := _get_visual_scale()
	var font_size := int(clampf(minf(bh * 0.34, hw * 0.92), 24.0 * visual_scale, 46.0 * visual_scale))
	var width := hw * 2.0
	var baseline := Vector2(pos.x - hw, pos.y - bh * 0.50 + float(font_size) * 0.36)
	var outline_px := maxf(1.4, float(font_size) * 0.075)
	var outline := Color(0.01, 0.015, 0.03, 0.78)
	var ink := Color(1.0, 0.98, 0.88, 0.96)
	_draw_centered_liquid_symbol(font, symbol, baseline, width, font_size, ink, outline, outline_px, true)

func _draw_finished_bubbles(idx: int, pos: Vector2, hw: float, bh: float, color_idx: int) -> void:
	var bubble_count := clampi(int(bh / 16.0), 9, 15)
	var top_y := pos.y - bh + 14.0
	var bottom_y := pos.y - 12.0
	var base := _get_liquid_color(color_idx).lightened(0.28)
	for i in bubble_count:
		var seed := idx * 97 + color_idx * 31 + i * 17
		var speed := lerpf(0.085, 0.165, _pseudo_random01(seed + 1))
		var rise := fmod(_time * speed + _pseudo_random01(seed + 2), 1.0)
		var y := lerpf(bottom_y, top_y, rise)
		var half := maxf(4.0, _liquid_half_width_at(pos, hw, bh, y) - 7.0)
		var side := lerpf(-0.86, 0.86, _pseudo_random01(seed + 3))
		var drift := sin(_time * lerpf(1.2, 2.4, _pseudo_random01(seed + 4)) + _pseudo_random01(seed + 5) * TAU) * minf(5.0, half * 0.17)
		var x := pos.x + side * half + drift
		var radius := lerpf(1.7, 4.1, _pseudo_random01(seed + 6))
		var fade := sin(rise * PI)
		var alpha := (0.18 + 0.15 * _pseudo_random01(seed + 7)) * fade
		var center := Vector2(x, y)
		draw_circle(center, radius + 1.1, Color(0.0, 0.0, 0.0, alpha * 0.18))
		draw_circle(center, radius, Color(1.0, 1.0, 1.0, alpha))
		draw_circle(center + Vector2(-radius * 0.26, -radius * 0.30), maxf(0.65, radius * 0.34),
				Color(base.r, base.g, base.b, alpha * 0.92))

func _draw_glass_shell(idx: int, pos: Vector2, hw: float, bh: float, is_selected: bool, is_hover: bool, is_finished: bool) -> void:
	var top_y := pos.y - bh
	var bottom_y := pos.y
	var outer_top_hw := hw
	var outer_bottom_hw := _tube_outer_half_width_at(pos, hw, bh, bottom_y - 7.0)
	var inner_top_hw := _tube_inner_half_width_at(pos, hw, bh, top_y + 3.0)
	var inner_bottom_hw := _tube_inner_half_width_at(pos, hw, bh, bottom_y - 8.0)
	var active := is_selected or is_hover or is_finished
	var wall_alpha := 0.50 if active else 0.36
	var edge := Color(0.72, 0.90, 1.0, wall_alpha)
	var edge_bright := Color(0.90, 0.98, 1.0, wall_alpha + 0.04)
	var edge_dim := Color(0.34, 0.52, 0.72, wall_alpha * 0.84)
	var bottom_fill_alpha := 0.075 if active else 0.050
	var bottom_edge_alpha := 0.22 if active else 0.15
	var rim_alpha := 0.46 if active else 0.34
	var rim_front_alpha := 0.38 if active else 0.27
	var shell_outline_alpha := 0.24 if active else 0.16

	var rim_outer := Vector2(outer_top_hw + 0.4, 4.7)
	var rim_inner := Vector2(inner_top_hw + 0.3, 3.0)
	draw_polygon(PackedVector2Array([
		Vector2(pos.x - outer_top_hw, top_y + 2.0),
		Vector2(pos.x - inner_top_hw, top_y + 5.0),
		Vector2(pos.x - inner_bottom_hw, bottom_y - 8.0),
		Vector2(pos.x - outer_bottom_hw, bottom_y - 7.0),
	]), PackedColorArray([edge_bright, edge_dim, edge_dim.darkened(0.12), edge]))
	draw_polygon(PackedVector2Array([
		Vector2(pos.x + inner_top_hw, top_y + 5.0),
		Vector2(pos.x + outer_top_hw, top_y + 2.0),
		Vector2(pos.x + outer_bottom_hw, bottom_y - 7.0),
		Vector2(pos.x + inner_bottom_hw, bottom_y - 8.0),
	]), PackedColorArray([edge_dim, edge_bright, edge, edge_dim.darkened(0.10)]))

	_draw_ellipse_filled(Vector2(pos.x, bottom_y - 7.0), Vector2(outer_bottom_hw, 9.0),
			Color(0.70, 0.90, 1.0, bottom_fill_alpha))
	_draw_ellipse_arc(Vector2(pos.x, bottom_y - 7.0), Vector2(outer_bottom_hw, 9.0),
			PI, 0.0, Color(0.88, 0.98, 1.0, bottom_edge_alpha), 2.0)

	var rim_center := Vector2(pos.x, top_y)
	_draw_ellipse_filled(rim_center, rim_outer, Color(0.76, 0.94, 1.0, 0.18))
	_draw_ellipse_filled(rim_center + Vector2(0.0, 0.3), rim_inner, Color(0.015, 0.030, 0.050, 0.28))
	_draw_ellipse_outline(rim_center, rim_outer, Color(0.87, 0.98, 1.0, rim_alpha), 1.7)
	_draw_ellipse_arc(rim_center, rim_outer, PI, 0.0,
			Color(1.0, 1.0, 1.0, rim_front_alpha), 2.1)

	var shimmer_cycle := fmod(_time + float(idx) * 0.16, 9.0)
	var shimmer_duration := 1.20
	var shimmer_side := -0.58
	var shimmer_front := 0.34
	if shimmer_cycle < shimmer_duration:
		var shimmer_phase := shimmer_cycle / shimmer_duration
		var shimmer_peak := sin(shimmer_phase * PI)
		shimmer_side = lerpf(-0.66, -0.42, shimmer_phase)
		shimmer_front = 0.34 + 0.42 * shimmer_peak
	var shimmer_alpha := (0.022 + shimmer_front * 0.046) * (1.0 if active else 0.74)
	var hl_top := Vector2(pos.x + shimmer_side * inner_top_hw * 0.54, top_y + 13.0)
	var hl_bottom := Vector2(pos.x + shimmer_side * inner_bottom_hw * 0.42, bottom_y - 18.0)
	var hl_top_w := maxf(2.8, hw * lerpf(0.042, 0.075, shimmer_front))
	var hl_bottom_w := maxf(2.1, hw * lerpf(0.034, 0.060, shimmer_front))
	draw_polygon(PackedVector2Array([
		hl_top + Vector2(-hl_top_w * 0.5, 0.0),
		hl_top + Vector2(hl_top_w * 0.5, 1.5),
		hl_bottom + Vector2(hl_bottom_w * 0.5, 0.0),
		hl_bottom + Vector2(-hl_bottom_w * 0.5, 0.0),
	]), PackedColorArray([
		Color(1.0, 1.0, 1.0, shimmer_alpha),
		Color(1.0, 1.0, 1.0, shimmer_alpha * 0.28),
		Color(1.0, 1.0, 1.0, shimmer_alpha * 0.18),
		Color(1.0, 1.0, 1.0, shimmer_alpha * 0.72),
	]))
	draw_line(hl_top + Vector2(-hl_top_w * 0.12, 0.0),
			hl_bottom + Vector2(-hl_bottom_w * 0.12, 0.0),
			Color(1.0, 1.0, 1.0, minf(0.30, shimmer_alpha * 1.35)),
			maxf(1.05, hw * 0.016), true)
	draw_line(hl_top + Vector2(hl_top_w * 0.48, 2.0),
			hl_bottom + Vector2(hl_bottom_w * 0.48, 0.0),
			Color(0.88, 0.98, 1.0, minf(0.11, shimmer_alpha * 0.34)),
			maxf(0.75, hw * 0.009), true)
	draw_line(Vector2(pos.x + inner_top_hw * 0.58, top_y + 10.0),
			Vector2(pos.x + inner_bottom_hw * 0.50, bottom_y - 18.0),
			Color(0.0, 0.0, 0.0, 0.07), 1.4, true)
	_draw_tube_outline(pos, hw, bh, Color(0.86, 0.97, 1.0, shell_outline_alpha), 1.35)

func _tube_outer_half_width_at(pos: Vector2, hw: float, bh: float, y: float) -> float:
	var top_y := pos.y - bh
	var t := clampf((y - top_y) / maxf(1.0, bh), 0.0, 1.0)
	return lerpf(hw, hw * 0.80, t)

func _tube_inner_half_width_at(pos: Vector2, hw: float, bh: float, y: float) -> float:
	var outer := _tube_outer_half_width_at(pos, hw, bh, y)
	var top_y := pos.y - bh
	var t := clampf((y - top_y) / maxf(1.0, bh), 0.0, 1.0)
	var bottom_squeeze := 1.0 - 0.08 * _smoothstep_float(0.88, 1.0, t)
	return maxf(7.0, (outer - float(WALL) - 1.5) * bottom_squeeze)

func _liquid_half_width_at(pos: Vector2, hw: float, bh: float, y: float) -> float:
	var top_y := pos.y - bh
	var t := clampf((y - top_y) / maxf(1.0, bh), 0.0, 1.0)
	var wall_follow_width := _tube_outer_half_width_at(pos, hw, bh, y) - float(WALL) * 0.58
	var top_release := _smoothstep_float(0.00, 0.10, t)
	var bottom_release := 1.0 - _smoothstep_float(0.76, 1.0, t)
	var body_bonus := 0.4 * top_release * bottom_release
	return maxf(4.0, wall_follow_width + body_bonus)

func _liquid_surface_radii_at(pos: Vector2, hw: float, bh: float, y: float, half_width: float) -> Vector2:
	var top_y := pos.y - bh
	var t := clampf((y - top_y) / maxf(1.0, bh), 0.0, 1.0)
	var body_ry := maxf(3.4, minf(6.6, float(liquid_unit_height) * 0.13))
	var rim_blend := 1.0 - _smoothstep_float(0.0, 0.09, t)
	var bottom_blend := _smoothstep_float(0.82, 1.0, t)
	var ry := lerpf(body_ry, 3.1, rim_blend)
	ry = lerpf(ry, 7.0, bottom_blend)
	return Vector2(maxf(4.0, half_width), ry)

func _draw_tube_outline(pos: Vector2, hw: float, bh: float, color: Color, width: float) -> void:
	var top_y := pos.y - bh
	var side_bottom_y := pos.y - 7.0
	var bottom_hw := hw * 0.80
	draw_line(Vector2(pos.x - hw, top_y + 2.0), Vector2(pos.x - bottom_hw, side_bottom_y), color, width, true)
	draw_line(Vector2(pos.x + hw, top_y + 2.0), Vector2(pos.x + bottom_hw, side_bottom_y), color, width, true)
	_draw_ellipse_arc(Vector2(pos.x, side_bottom_y), Vector2(bottom_hw, 9.0), PI, 0.0, color, width)
	_draw_ellipse_outline(Vector2(pos.x, top_y), Vector2(hw + 0.4, 4.7), Color(color.r, color.g, color.b, color.a * 0.85), width)

func _draw_beaker_trait(idx: int, pos: Vector2, hw: float, bh: float, front: bool) -> void:
	var trait_data := _get_beaker_trait(idx)
	var trait_type := str(trait_data.get("type", BEAKER_TRAIT_NONE))
	if trait_type == BEAKER_TRAIT_NONE:
		return
	var earned := _is_beaker_trait_bonus_earned(idx)
	if trait_type == BEAKER_TRAIT_PRISMATIC:
		_draw_prismatic_beaker_trait(pos, hw, bh, earned, front)
	elif trait_type == BEAKER_TRAIT_TINTED:
		_draw_tinted_beaker_trait(pos, hw, bh, int(trait_data.get("color", -1)), earned, front)
	elif trait_type == BEAKER_TRAIT_CRACKED:
		if not _is_cracked_beaker_revealed(idx):
			return
		var is_clear := idx < beakers.size() and (beakers[idx] as Array).is_empty()
		_draw_cracked_beaker_trait(pos, hw, bh, is_clear, front)

func _draw_prismatic_beaker_trait(pos: Vector2, hw: float, bh: float, earned: bool, front: bool) -> void:
	if not front:
		return
	var alpha := 0.76 if earned else 0.56
	var glow_alpha := 0.15 if earned else 0.09
	var width := 3.0 if earned else 2.4
	var glow_width := width + 3.0
	var color_shift := _time * 1.35
	var frame_hw := hw + 1.4
	var frame_bh := bh + 1.2
	var top_y := pos.y - frame_bh
	var side_bottom_y := pos.y - 7.0
	var bottom_hw := frame_hw * 0.80
	var top_radii := Vector2(frame_hw + 0.4, 4.7)

	_draw_prismatic_connected_frame(pos, frame_hw, frame_bh, side_bottom_y, bottom_hw, glow_alpha, glow_width, color_shift)
	_draw_prismatic_connected_frame(pos, frame_hw, frame_bh, side_bottom_y, bottom_hw, alpha, width, color_shift)
	_draw_prismatic_ellipse_gradient(Vector2(pos.x, top_y), top_radii, 0.0, TAU, glow_alpha, glow_width, color_shift, 0.68)
	_draw_prismatic_ellipse_gradient(Vector2(pos.x, top_y), top_radii, 0.0, TAU, alpha, width, color_shift, 0.68)
	if earned:
		_draw_tube_outline(pos, frame_hw + 0.8, frame_bh + 0.6, Color(1.0, 1.0, 1.0, 0.18), 1.3)
	_draw_prismatic_beaker_tag(pos, hw, bh, earned, color_shift)

func _draw_prismatic_connected_frame(pos: Vector2, frame_hw: float, frame_bh: float,
		side_bottom_y: float, bottom_hw: float, alpha: float, width: float, color_shift: float) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var top_y := pos.y - frame_bh
	var side_samples := 18
	for i in side_samples:
		var t := float(i) / float(side_samples - 1)
		var y := lerpf(top_y + 2.0, side_bottom_y, t)
		var x := lerpf(pos.x - frame_hw, pos.x - bottom_hw, t)
		pts.append(Vector2(x, y))
		cols.append(_get_prismatic_frame_color(t * 0.30, alpha, color_shift))
	var arc_samples := 24
	for i in range(1, arc_samples + 1):
		var t := float(i) / float(arc_samples)
		var angle := lerpf(PI, 0.0, t)
		pts.append(Vector2(pos.x + cos(angle) * bottom_hw, side_bottom_y + sin(angle) * 9.0))
		cols.append(_get_prismatic_frame_color(0.30 + t * 0.24, alpha, color_shift))
	for i in range(1, side_samples):
		var t := float(i) / float(side_samples - 1)
		var y := lerpf(side_bottom_y, top_y + 2.0, t)
		var x := lerpf(pos.x + bottom_hw, pos.x + frame_hw, t)
		pts.append(Vector2(x, y))
		cols.append(_get_prismatic_frame_color(0.54 + t * 0.30, alpha, color_shift))
	draw_polyline_colors(pts, cols, width, true)

func _draw_prismatic_ellipse_gradient(center: Vector2, radii: Vector2, start_angle: float, end_angle: float,
		alpha: float, width: float, color_shift: float, phase_offset: float) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var samples := 40
	for i in samples + 1:
		var t := float(i) / float(samples)
		var angle := lerpf(start_angle, end_angle, t)
		pts.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
		cols.append(_get_prismatic_frame_color(phase_offset + t * 0.30, alpha, color_shift))
	draw_polyline_colors(pts, cols, width, true)

func _get_prismatic_frame_color(phase: float, alpha: float, color_shift: float) -> Color:
	var color_steps := mini(maxi(filled_beakers, 4), 8)
	var color_pos := fmod(phase * float(color_steps) + color_shift, float(color_steps))
	if color_pos < 0.0:
		color_pos += float(color_steps)
	var idx_a := int(floor(color_pos)) % color_steps
	var idx_b := (idx_a + 1) % color_steps
	var blended := _get_liquid_color(idx_a).lerp(_get_liquid_color(idx_b), fmod(color_pos, 1.0))
	return Color(blended.r, blended.g, blended.b, alpha)

func _get_trait_tag_radius(hw: float) -> float:
	var visual_scale := _get_visual_scale()
	return clampf(hw * 0.29, 15.0 * visual_scale, 25.0 * visual_scale)

func _get_trait_tag_center(pos: Vector2, hw: float, bh: float, radius: float) -> Vector2:
	var visual_scale := _get_visual_scale()
	return Vector2(pos.x + hw + radius * 0.72 - 4.0 * visual_scale, pos.y - bh + radius * 0.30)

func _draw_prismatic_beaker_tag(pos: Vector2, hw: float, bh: float, earned: bool, color_shift: float) -> void:
	var visual_scale := _get_visual_scale()
	var tag_radius := _get_trait_tag_radius(hw)
	var tag_center := _get_trait_tag_center(pos, hw, bh, tag_radius)
	draw_circle(tag_center + Vector2(0.0, 2.0 * visual_scale), tag_radius + 2.0 * visual_scale,
			Color(0.0, 0.0, 0.0, 0.38))
	draw_circle(tag_center, tag_radius, Color(0.025, 0.030, 0.055, 0.94))
	_draw_prismatic_ellipse_gradient(tag_center, Vector2(tag_radius + 1.0 * visual_scale, tag_radius + 1.0 * visual_scale),
			0.0, TAU, 0.24 if earned else 0.16, maxf(4.0, 4.4 * visual_scale), color_shift, 0.10)
	_draw_prismatic_ellipse_gradient(tag_center, Vector2(tag_radius, tag_radius),
			0.0, TAU, 0.96 if earned else 0.78, maxf(2.4, 2.7 * visual_scale), color_shift, 0.10)
	var star := PackedVector2Array()
	var star_cols := PackedColorArray()
	for i in 16:
		var point_radius := tag_radius * (0.70 if i % 2 == 0 else 0.34)
		var angle := -PI * 0.5 + float(i) * PI / 8.0 + sin(_time * 1.4) * 0.035
		star.append(tag_center + Vector2(cos(angle), sin(angle)) * point_radius)
		var color := _get_prismatic_frame_color(float(i) / 16.0, 0.98, color_shift)
		star_cols.append(color.lightened(0.18 if earned else 0.06))
	draw_polygon(star, star_cols)
	var outline := PackedVector2Array(star)
	outline.append(star[0])
	draw_polyline(outline, Color(1.0, 1.0, 1.0, 0.86), maxf(1.5, 1.7 * visual_scale), true)
	draw_circle(tag_center, tag_radius * 0.16, Color(1.0, 1.0, 1.0, 0.72))

func _draw_tinted_beaker_trait(pos: Vector2, hw: float, bh: float, color_idx: int, earned: bool, front: bool) -> void:
	if color_idx < 0:
		return
	var base := _get_liquid_color(color_idx)
	var halo_strength := 0.22 if earned else 0.12
	if not front:
		_draw_beaker_halo(pos, hw, bh, Color(base.r, base.g, base.b, 1.0), halo_strength, false)
		return
	var frame_hw := hw + 1.4
	var frame_bh := bh + 1.2
	var outline := Color(base.r, base.g, base.b, 0.78).lightened(0.12)
	_draw_tube_outline(pos, frame_hw, frame_bh, outline, 2.4)
	_draw_ellipse_arc(Vector2(pos.x, pos.y - 7.0), Vector2(frame_hw * 0.80 + 1.0, 9.6),
			PI, 0.0, Color(base.r, base.g, base.b, 0.84).lightened(0.16), 2.4)
	if earned:
		_draw_tube_outline(pos, frame_hw + 1.0, frame_bh + 0.8, Color(1.0, 1.0, 1.0, 0.16), 1.2)
	var visual_scale := _get_visual_scale()
	var chip_radius := _get_trait_tag_radius(hw)
	var chip_center := _get_trait_tag_center(pos, hw, bh, chip_radius)
	var chip := Color(base.r, base.g, base.b, 0.92).lightened(0.16)
	var points := PackedVector2Array([
		chip_center + Vector2(0.0, -chip_radius),
		chip_center + Vector2(chip_radius, 0.0),
		chip_center + Vector2(0.0, chip_radius),
		chip_center + Vector2(-chip_radius, 0.0),
	])
	var shadow_points := PackedVector2Array([
		points[0] + Vector2(0.0, 2.0 * visual_scale),
		points[1] + Vector2(0.0, 2.0 * visual_scale),
		points[2] + Vector2(0.0, 2.0 * visual_scale),
		points[3] + Vector2(0.0, 2.0 * visual_scale),
	])
	draw_polygon(shadow_points, PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.38),
		Color(0.0, 0.0, 0.0, 0.38),
		Color(0.0, 0.0, 0.0, 0.38),
		Color(0.0, 0.0, 0.0, 0.38),
	]))
	draw_polygon(points, PackedColorArray([chip, chip, chip, chip]))
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]),
			Color(0.02, 0.025, 0.035, 0.82), maxf(2.0, 2.2 * visual_scale), true)
	draw_line(points[0], points[1], Color(1.0, 1.0, 1.0, 0.72), maxf(1.5, 1.6 * visual_scale), true)
	draw_line(points[3], points[0], Color(1.0, 1.0, 1.0, 0.60), maxf(1.3, 1.4 * visual_scale), true)
	var symbols := GameSettings.get_liquid_symbols()
	var font := ThemeDB.fallback_font
	if not symbols.is_empty() and font != null:
		var symbol := str(symbols[color_idx % symbols.size()])
		var ink := Color(1.0, 0.98, 0.88, 0.98)
		var symbol_outline := Color(0.01, 0.015, 0.03, 0.78)
		var font_size := int(round(chip_radius * 1.28))
		var width := chip_radius * 2.0
		var baseline := chip_center + Vector2(-chip_radius, float(font_size) * 0.36)
		var outline_px := maxf(1.0, chip_radius * 0.08)
		for offset in [
			Vector2(-outline_px, 0.0),
			Vector2(outline_px, 0.0),
			Vector2(0.0, -outline_px),
			Vector2(0.0, outline_px),
		]:
			draw_string(font, baseline + offset, symbol, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, symbol_outline)
		draw_string(font, baseline, symbol, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, ink)

func _draw_cracked_beaker_trait(pos: Vector2, hw: float, bh: float, is_clear: bool, front: bool) -> void:
	if not front:
		if not is_clear:
			_draw_beaker_halo(pos, hw, bh, Color(0.92, 0.98, 1.0, 1.0), 0.10, false)
		return
	var alpha := 0.36 if is_clear else 0.52
	var crack := Color(0.96, 0.99, 1.0, alpha)
	var shadow := Color(0.0, 0.0, 0.0, 0.18 if is_clear else 0.26)
	var start := Vector2(pos.x + hw * 0.16, pos.y - bh + 18.0)
	var branch := PackedVector2Array([
		start,
		start + Vector2(hw * 0.20, bh * 0.14),
		start + Vector2(hw * 0.04, bh * 0.29),
		start + Vector2(hw * 0.27, bh * 0.45),
		start + Vector2(hw * 0.10, bh * 0.64),
	])
	draw_polyline(branch, shadow, 6.2, true)
	draw_polyline(branch, crack, 3.2, true)
	var left_branch := PackedVector2Array([
		branch[1],
		branch[1] + Vector2(-hw * 0.18, bh * 0.08),
		branch[1] + Vector2(-hw * 0.28, bh * 0.20),
	])
	var right_branch := PackedVector2Array([
		branch[2],
		branch[2] + Vector2(hw * 0.28, bh * 0.07),
		branch[2] + Vector2(hw * 0.42, bh * 0.18),
	])
	draw_polyline(left_branch, shadow, 5.0, true)
	draw_polyline(right_branch, shadow, 5.0, true)
	draw_polyline(left_branch, crack, 2.5, true)
	draw_polyline(right_branch, crack, 2.5, true)
	if not is_clear:
		_draw_tube_outline(pos, hw + 3.0, bh + 2.0, Color(0.92, 0.98, 1.0, 0.18), 1.6)
	_draw_cracked_beaker_tag(pos, hw, bh, is_clear)

func _draw_cracked_beaker_tag(pos: Vector2, hw: float, bh: float, is_clear: bool) -> void:
	var visual_scale := _get_visual_scale()
	var tag_radius := _get_trait_tag_radius(hw)
	var tag_center := _get_trait_tag_center(pos, hw, bh, tag_radius)
	var alpha := 0.92 if not is_clear else 0.76
	var fill := Color(0.72, 0.92, 1.0, alpha) if not is_clear else Color(0.58, 0.68, 0.78, alpha)
	var rim := Color(0.96, 0.99, 1.0, 0.92 if not is_clear else 0.72)
	draw_circle(tag_center + Vector2(0.0, 2.0 * visual_scale), tag_radius + 2.0 * visual_scale,
			Color(0.0, 0.0, 0.0, 0.38))

	var points := PackedVector2Array()
	for i in 8:
		var angle := -PI * 0.5 + float(i) * TAU / 8.0
		points.append(tag_center + Vector2(cos(angle), sin(angle)) * tag_radius)
	var colors := PackedColorArray()
	for i in points.size():
		var phase := float(i) / float(points.size())
		colors.append(fill.lerp(Color(1.0, 1.0, 1.0, alpha), 0.22 + 0.12 * sin(phase * TAU)))
	draw_polygon(points, colors)

	var outline := PackedVector2Array(points)
	outline.append(points[0])
	draw_polyline(outline, Color(0.02, 0.025, 0.04, 0.82), maxf(2.0, 2.2 * visual_scale), true)
	draw_polyline(outline, rim, maxf(1.1, 1.3 * visual_scale), true)

	var crack_shadow := Color(1.0, 1.0, 1.0, 0.66)
	var crack_ink := Color(0.025, 0.035, 0.07, 0.98)
	var main := PackedVector2Array([
		tag_center + Vector2(-tag_radius * 0.18, -tag_radius * 0.62),
		tag_center + Vector2(tag_radius * 0.18, -tag_radius * 0.22),
		tag_center + Vector2(-tag_radius * 0.08, tag_radius * 0.04),
		tag_center + Vector2(tag_radius * 0.28, tag_radius * 0.62),
	])
	var left := PackedVector2Array([
		main[1],
		tag_center + Vector2(-tag_radius * 0.38, -tag_radius * 0.04),
		tag_center + Vector2(-tag_radius * 0.52, tag_radius * 0.22),
	])
	var right := PackedVector2Array([
		main[2],
		tag_center + Vector2(tag_radius * 0.40, tag_radius * 0.12),
		tag_center + Vector2(tag_radius * 0.54, tag_radius * 0.34),
	])
	var wide := maxf(3.6, 3.7 * visual_scale)
	var narrow := maxf(2.0, 2.3 * visual_scale)
	draw_polyline(main, crack_shadow, wide, true)
	draw_polyline(left, crack_shadow, wide * 0.72, true)
	draw_polyline(right, crack_shadow, wide * 0.72, true)
	draw_polyline(main, crack_ink, narrow, true)
	draw_polyline(left, crack_ink, narrow * 0.72, true)
	draw_polyline(right, crack_ink, narrow * 0.72, true)

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
	elif _cheat_mode == "pipette":
		if _cheat_pipette_beaker < 0:
			var has_run := false
			if idx < beakers.size() and not _is_beaker_complete(idx):
				var b: Array = beakers[idx]
				for segment in b.size():
					if _can_pipette_select_segment(idx, segment):
						has_run = true
						var run := _get_pipette_run(idx, segment)
						var run_rect := _segment_run_rect(idx, int(run["start"]), int(run["count"]))
						draw_rect(run_rect.grow(2.0), Color(0.68, 0.96, 1.0, 0.10), true)
						draw_rect(run_rect.grow(2.0), Color(0.72, 1.0, 0.96, 0.38), false, 1.3)
			if has_run:
				draw_rect(rect, Color(0.18, 0.86, 1.0, 0.10), true)
				draw_rect(rect, Color(0.60, 1.0, 0.94, 0.76), false, 2.2)
		else:
			if idx == _cheat_pipette_beaker:
				var selected_rect := _segment_run_rect(idx, _cheat_pipette_run_start, _cheat_pipette_run_count)
				draw_rect(selected_rect.grow(5.0), Color(1.0, 1.0, 1.0, 0.18), true)
				draw_rect(selected_rect.grow(5.0), Color(0.96, 1.0, 1.0, 0.96), false, 2.4)
			elif _can_pipette_destination(idx):
				draw_rect(rect, Color(0.22, 1.0, 0.62, 0.13), true)
				draw_rect(rect, Color(0.58, 1.0, 0.76, 0.86), false, 2.5)

func _segment_rect(idx: int, segment: int) -> Rect2:
	if idx < 0 or idx >= beaker_positions.size():
		return Rect2()
	var pos: Vector2 = beaker_positions[idx]
	var hw := float(beaker_width) / 2.0
	var inner_x := pos.x - hw + WALL
	var inner_w := float(beaker_width) - WALL * 2.0
	var top := pos.y - float(segment + 1) * float(liquid_unit_height)
	return Rect2(inner_x, top, inner_w, float(liquid_unit_height))

func _segment_run_rect(idx: int, start: int, count: int) -> Rect2:
	if count <= 0:
		return Rect2()
	var first := _segment_rect(idx, start)
	if first.size == Vector2.ZERO:
		return first
	var top := first.position.y - float(maxi(0, count - 1)) * float(liquid_unit_height)
	return Rect2(first.position.x, top, first.size.x, first.size.y * float(count))

func _segment_run_center(idx: int, start: int, count: int) -> Vector2:
	var rect := _segment_run_rect(idx, start, count)
	if rect.size == Vector2.ZERO:
		return Vector2.ZERO
	return rect.position + rect.size * 0.5

func _destination_pipette_point(idx: int) -> Vector2:
	if idx < 0 or idx >= beaker_positions.size() or idx >= beakers.size():
		return Vector2.ZERO
	var pos: Vector2 = beaker_positions[idx]
	var fill := float(beakers[idx].size())
	return Vector2(pos.x, pos.y - (fill + 0.18) * float(liquid_unit_height))

func _beaker_stir_point(idx: int) -> Vector2:
	if idx < 0 or idx >= beaker_positions.size() or idx >= beakers.size():
		return Vector2.ZERO
	var pos: Vector2 = beaker_positions[idx]
	var fill := maxf(1.0, float(beakers[idx].size()))
	var top_y := pos.y - fill * float(liquid_unit_height)
	var bottom_y := pos.y - float(liquid_unit_height) * 0.24
	return Vector2(pos.x, lerpf(bottom_y, top_y, 0.48))

func _draw_finished_beaker_glow(idx: int, pos: Vector2, hw: float, bh: float) -> void:
	var color_idx: int = int(beakers[idx][0])
	var base: Color = _get_liquid_color(color_idx).lightened(0.28)
	var pulse := _get_finish_pulse(idx)
	var idle := 0.14 + 0.05 * sin(_time * 3.4 + float(idx) * 0.7)
	var center := Vector2(pos.x, pos.y - bh * 0.48)
	for layer in 5:
		var t := float(layer) / 4.0
		var grow := lerpf(24.0, 4.0, t) + pulse * lerpf(26.0, 5.0, t)
		var alpha := (1.0 - t) * (idle * 0.18 + 0.035) + pulse * (1.0 - t) * 0.08
		_draw_ellipse_filled(center, Vector2(hw + grow, bh * 0.50 + grow * 0.72),
				Color(base.r, base.g, base.b, alpha))
	_draw_tube_outline(pos, hw + 4.0 + pulse * 4.0, bh + 4.0 + pulse * 4.0,
			Color(base.r, base.g, base.b, 0.24 + pulse * 0.30), 2.0)
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
	var bob := sin(_time * 3.0 + float(idx)) * 1.0
	var rim_rx := hw + 1.2
	var lid_center := Vector2(pos.x, top - 3.0 + bob)
	var lid_rx := rim_rx + 2.0 + pulse * 2.8
	var lid_ry := 5.7 + pulse * 0.9
	_draw_ellipse_filled(lid_center + Vector2(0.0, 4.2), Vector2(lid_rx + 2.0, lid_ry),
			Color(0.0, 0.0, 0.0, 0.30))
	draw_rect(Rect2(pos.x - lid_rx, lid_center.y, lid_rx * 2.0, 7.0),
			Color(0.10, 0.13, 0.18, 0.92), true)
	_draw_ellipse_filled(lid_center + Vector2(0.0, 3.0), Vector2(lid_rx, lid_ry),
			Color(liquid.r, liquid.g, liquid.b, 0.80).darkened(0.10))
	_draw_ellipse_filled(lid_center, Vector2(lid_rx, lid_ry),
			Color(liquid.r, liquid.g, liquid.b, 0.90).lightened(0.16))
	_draw_ellipse_filled(lid_center + Vector2(0.0, -1.0), Vector2(lid_rx * 0.66, lid_ry * 0.48),
			Color(1.0, 0.92, 0.48, 0.22 + pulse * 0.12))
	_draw_lid_handle(idx, lid_center + Vector2(0.0, -8.5), Vector2(13.0 + pulse * 2.0, 5.0 + pulse), pulse)
	_draw_ellipse_outline(lid_center, Vector2(lid_rx, lid_ry), Color(1.0, 0.98, 0.72, 0.24 + pulse * 0.12), 1.5)
	draw_line(Vector2(pos.x - lid_rx + 10.0, lid_center.y - 3.0),
			Vector2(pos.x + lid_rx - 10.0, lid_center.y - 3.0),
			Color(1.0, 1.0, 1.0, 0.18), 2.0, true)
	if pulse > 0.0:
		var shine_color := Color(1.0, 0.95, 0.42, pulse)
		draw_line(Vector2(pos.x - rim_rx - 15.0, top - 18.0), Vector2(pos.x - rim_rx + 9.0, top - 42.0), shine_color, 3.0, true)
		draw_line(Vector2(pos.x + rim_rx + 13.0, top - 7.0), Vector2(pos.x + rim_rx + 37.0, top - 31.0), shine_color, 3.0, true)

func _draw_lid_handle(idx: int, center: Vector2, radii: Vector2, pulse: float) -> void:
	_draw_ellipse_filled(center + Vector2(0.0, 1.6), radii + Vector2(1.4, 0.8), Color(0.0, 0.0, 0.0, 0.24))
	var trait_data := _get_beaker_trait(idx)
	var trait_type := str(trait_data.get("type", BEAKER_TRAIT_NONE))
	var bonus_earned := _is_beaker_trait_bonus_earned(idx)
	if trait_type == BEAKER_TRAIT_PRISMATIC and bonus_earned:
		var color_shift := _time * 1.55
		_draw_ellipse_filled(center, radii, Color(0.84, 0.90, 1.0, 0.34 + pulse * 0.10))
		var stripes := 7
		for i in stripes:
			var t := (float(i) + 0.5) / float(stripes)
			var stripe_center := center + Vector2(lerpf(-radii.x * 0.72, radii.x * 0.72, t), 0.0)
			var stripe_radii := Vector2(radii.x / float(stripes) * 1.25, radii.y * 0.94)
			var stripe := _get_prismatic_frame_color(t * 0.48, 0.84, color_shift).lightened(0.16)
			_draw_ellipse_filled(stripe_center, stripe_radii, stripe)
		_draw_prismatic_ellipse_gradient(center, radii + Vector2(0.4, 0.2), 0.0, TAU, 0.96, 1.8, color_shift, 0.68)
		_draw_ellipse_filled(center + Vector2(-radii.x * 0.14, -radii.y * 0.30), Vector2(radii.x * 0.50, radii.y * 0.24),
				Color(1.0, 1.0, 1.0, 0.34 + pulse * 0.12))
		return

	if trait_type == BEAKER_TRAIT_TINTED and bonus_earned:
		var tint_idx := int(trait_data.get("color", -1))
		var tint := _get_liquid_color(tint_idx) if tint_idx >= 0 else Color(0.82, 0.90, 1.0, 1.0)
		var base := tint.lightened(0.18)
		_draw_ellipse_filled(center, radii, Color(base.r, base.g, base.b, 0.94))
		_draw_ellipse_filled(center + Vector2(0.0, -radii.y * 0.25), Vector2(radii.x * 0.76, radii.y * 0.42),
				Color(1.0, 1.0, 1.0, 0.22 + pulse * 0.10))
		_draw_ellipse_outline(center, radii, Color(base.r, base.g, base.b, 0.74).lightened(0.18), 1.3)
		return

	_draw_ellipse_filled(center, radii, Color(0.66, 0.70, 0.75, 0.97))
	_draw_ellipse_filled(center + Vector2(0.0, -radii.y * 0.26), Vector2(radii.x * 0.84, radii.y * 0.42),
			Color(0.97, 0.99, 1.0, 0.66 + pulse * 0.12))
	_draw_ellipse_filled(center + Vector2(0.0, radii.y * 0.30), Vector2(radii.x * 0.78, radii.y * 0.34),
			Color(0.22, 0.25, 0.30, 0.20))
	_draw_ellipse_outline(center, radii, Color(0.96, 0.98, 1.0, 0.58), 1.2)

func _draw_ellipse_filled(center: Vector2, radii: Vector2, col: Color):
	var pts  := PackedVector2Array()
	var cols := PackedColorArray()
	var steps := 18
	for i in steps:
		var a := TAU * float(i) / float(steps)
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
		cols.append(col)
	draw_polygon(pts, cols)

func _draw_ellipse_outline(center: Vector2, radii: Vector2, col: Color, width: float, steps: int = 28) -> void:
	if radii.x <= 0.0 or radii.y <= 0.0:
		return
	var pts := PackedVector2Array()
	for i in steps + 1:
		var a := TAU * float(i) / float(steps)
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_polyline(pts, col, width, true)

func _draw_ellipse_arc(center: Vector2, radii: Vector2, start_angle: float, end_angle: float,
		col: Color, width: float, steps: int = 18) -> void:
	if radii.x <= 0.0 or radii.y <= 0.0:
		return
	var pts := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		var a := lerpf(start_angle, end_angle, t)
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_polyline(pts, col, width, true)

# ---------------------------------------------------------------------------
# Win celebration
# ---------------------------------------------------------------------------

func _celebrate():
	_ensure_beaker_positions()
	if beaker_positions.is_empty():
		return
	for n in 70:
		var bp: Vector2 = beaker_positions[randi() % beaker_positions.size()]
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
