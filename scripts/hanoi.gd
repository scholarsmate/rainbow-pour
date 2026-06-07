extends Node2D

signal disk_moved

const TOWER_COUNT = 3

var disk_count: int = 5

const BASE_Y = 560.0
const DISK_HEIGHT = 36.0
const DISK_WIDTH_UNIT = 32.0
const POLE_WIDTH = 16

var towers = [[], [], []]
var tower_positions = []
var selected_tower = -1
var _play_area := Rect2(0.0, 96.0, 1280.0, 532.0)
var _base_y := BASE_Y
var _disk_height := DISK_HEIGHT
var _disk_width_unit := DISK_WIDTH_UNIT
var _pole_width := POLE_WIDTH
var _tower_hit_width := 110.0

var disk_colors = [
	Color(0.937, 0.267, 0.267),  # Red
	Color(0.976, 0.451, 0.086),  # Orange
	Color(0.918, 0.702, 0.031),  # Yellow
	Color(0.133, 0.773, 0.369),  # Green
	Color(0.231, 0.510, 0.965),  # Blue
	Color(0.529, 0.196, 0.902),  # Purple
	Color(0.957, 0.267, 0.573),  # Pink
	Color(0.067, 0.784, 0.757),  # Teal
	Color(0.663, 0.341, 0.161),  # Brown
	Color(0.584, 0.647, 0.651),  # Gray-Blue
]

func _ready():
	_apply_settings()
	_recalculate_layout()
	setup_disks()

func _apply_settings() -> void:
	disk_count = clampi(GameSettings.hanoi_disk_count,
			GameSettings.HANOI_DISK_COUNT_MIN, GameSettings.HANOI_DISK_COUNT_MAX)

func set_play_area(area: Rect2) -> void:
	var sanitized := Rect2(
			area.position.x,
			area.position.y,
			maxf(420.0, area.size.x),
			maxf(260.0, area.size.y))
	if _play_area.is_equal_approx(sanitized):
		return
	_play_area = sanitized
	_recalculate_layout()
	queue_redraw()

func _recalculate_layout() -> void:
	var visual_scale := _get_visual_scale()
	var center_x := _play_area.position.x + _play_area.size.x * 0.5
	var spacing := minf(400.0 * visual_scale, maxf(170.0 * visual_scale, _play_area.size.x * 0.32))
	_disk_height = clampf((_play_area.size.y - 74.0 * visual_scale) / float(disk_count + 1),
			20.0 * visual_scale, DISK_HEIGHT * visual_scale)
	_disk_width_unit = clampf((spacing * 0.68) / (float(maxi(1, disk_count)) * 1.1),
			16.0 * visual_scale, DISK_WIDTH_UNIT * visual_scale)
	_pole_width = clampf(_disk_width_unit * 0.50, 10.0 * visual_scale, POLE_WIDTH * visual_scale)
	_tower_hit_width = maxf(92.0, spacing * 0.28)
	var pole_h := float(disk_count) * _disk_height + 20.0
	var bottom_base_y := _play_area.position.y + _play_area.size.y - 28.0 * visual_scale
	if _is_play_area_portrait():
		var centered_base_y := _play_area.position.y + _play_area.size.y * 0.5 + pole_h * 0.5 - 6.0
		var top_base_y := _play_area.position.y + pole_h + 16.0 * visual_scale
		_base_y = clampf(centered_base_y, top_base_y, bottom_base_y)
	else:
		_base_y = bottom_base_y
	tower_positions = [
		Vector2(center_x - spacing, _base_y),
		Vector2(center_x, _base_y),
		Vector2(center_x + spacing, _base_y),
	]

func _is_play_area_portrait() -> bool:
	return _play_area.size.y > _play_area.size.x * 1.08

func _get_visual_scale() -> float:
	if _is_play_area_portrait():
		return clampf(_play_area.size.x / 540.0, 1.0, 2.0)
	return clampf(minf(_play_area.size.x / 1280.0, _play_area.size.y / 532.0), 0.85, 1.35)

func setup_disks():
	towers = [[], [], []]
	for i in range(disk_count, 0, -1):
		towers[0].append(i)
	queue_redraw()

func can_move(src: int, dst: int) -> bool:
	if towers[src].is_empty():
		return false
	if towers[dst].is_empty():
		return true
	return towers[src].back() < towers[dst].back()

func check_complete() -> bool:
	return towers[1].size() == disk_count

func reset():
	selected_tower = -1
	_apply_settings()
	_recalculate_layout()
	setup_disks()

func _draw():
	for i in TOWER_COUNT:
		_draw_tower(i)

func _draw_tower(idx: int):
	var pos = tower_positions[idx]
	var is_selected = (idx == selected_tower)
	var is_goal = (idx == 1)
	var pole_h = disk_count * _disk_height + 20.0
	var base_hw = (disk_count + 1) * _disk_width_unit / 2.0

	if is_selected:
		var hw = (disk_count + 1) * _disk_width_unit / 2.0 + 10.0
		draw_rect(Rect2(pos.x - hw, pos.y - pole_h - 10, hw * 2, pole_h + 20),
				  Color(1, 1, 0.2, 0.3), true)

	var pole_color := Color(1.0, 0.78, 0.12) if is_goal else Color(0.5, 0.52, 0.6)

	# Pole
	draw_rect(Rect2(pos.x - _pole_width / 2.0, pos.y - pole_h, _pole_width, pole_h),
			  pole_color, true)
	# Base
	draw_rect(Rect2(pos.x - base_hw, pos.y, base_hw * 2, 12), pole_color, true)

	# Disks
	for disk_idx in towers[idx].size():
		var size = towers[idx][disk_idx]
		var width = size * _disk_width_unit * 1.1
		var y = pos.y - (disk_idx + 1) * _disk_height
		var color = disk_colors[(size - 1) % disk_colors.size()]
		draw_rect(Rect2(pos.x - width / 2.0, y, width, _disk_height - 4.0), color, true)
		draw_rect(Rect2(pos.x - width / 2.0, y, width, _disk_height - 4.0), Color.BLACK, false, 2)

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var idx = _get_tower_at(event.position)
		if idx >= 0:
			_handle_click(idx)

func _get_tower_at(pos: Vector2) -> int:
	for i in TOWER_COUNT:
		if abs(pos.x - tower_positions[i].x) < _tower_hit_width:
			return i
	return -1

func _handle_click(idx: int):
	if selected_tower < 0:
		if not towers[idx].is_empty():
			selected_tower = idx
			if AudioManager:
				AudioManager.play_select()
			queue_redraw()
	else:
		if selected_tower == idx:
			selected_tower = -1
			queue_redraw()
			return
		if can_move(selected_tower, idx):
			towers[idx].append(towers[selected_tower].pop_back())
			if AudioManager:
				AudioManager.play_move()
			queue_redraw()
			emit_signal("disk_moved")
		else:
			if AudioManager:
				AudioManager.play_invalid()
			selected_tower = idx if not towers[idx].is_empty() else -1
			queue_redraw()
