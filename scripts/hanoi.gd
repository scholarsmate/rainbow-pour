extends Node2D

signal disk_moved

const TOWER_COUNT = 3
const DISK_COUNT = 5

const BASE_Y = 560.0
const DISK_HEIGHT = 36.0
const DISK_WIDTH_UNIT = 32.0
const POLE_WIDTH = 16

var towers = [[], [], []]
var tower_positions = []
var selected_tower = -1

var disk_colors = [
	Color(0.937, 0.267, 0.267),  # Red
	Color(0.976, 0.451, 0.086),  # Orange
	Color(0.918, 0.702, 0.031),  # Yellow
	Color(0.133, 0.773, 0.369),  # Green
	Color(0.231, 0.510, 0.965),  # Blue
]

func _ready():
	tower_positions = [
		Vector2(240, BASE_Y),
		Vector2(640, BASE_Y),
		Vector2(1040, BASE_Y),
	]
	setup_disks()

func setup_disks():
	towers = [[], [], []]
	for i in range(DISK_COUNT, 0, -1):
		towers[0].append(i)
	queue_redraw()

func can_move(src: int, dst: int) -> bool:
	if towers[src].is_empty():
		return false
	if towers[dst].is_empty():
		return true
	return towers[src].back() < towers[dst].back()

func check_complete() -> bool:
	return towers[1].size() == DISK_COUNT

func reset():
	selected_tower = -1
	setup_disks()

func _draw():
	for i in TOWER_COUNT:
		_draw_tower(i)

func _draw_tower(idx: int):
	var pos = tower_positions[idx]
	var is_selected = (idx == selected_tower)
	var pole_h = DISK_COUNT * DISK_HEIGHT + 20

	if is_selected:
		var hw = (DISK_COUNT + 1) * DISK_WIDTH_UNIT / 2.0 + 10
		draw_rect(Rect2(pos.x - hw, pos.y - pole_h - 10, hw * 2, pole_h + 20),
				  Color(1, 1, 0.2, 0.3), true)

	# Pole
	draw_rect(Rect2(pos.x - POLE_WIDTH / 2.0, pos.y - pole_h, POLE_WIDTH, pole_h),
			  Color(0.5, 0.52, 0.6), true)
	# Base
	var base_hw = (DISK_COUNT + 1) * DISK_WIDTH_UNIT / 2.0
	draw_rect(Rect2(pos.x - base_hw, pos.y, base_hw * 2, 12), Color(0.5, 0.52, 0.6), true)

	# Disks
	for disk_idx in towers[idx].size():
		var size = towers[idx][disk_idx]
		var width = size * DISK_WIDTH_UNIT * 1.1
		var y = pos.y - (disk_idx + 1) * DISK_HEIGHT
		var color = disk_colors[(size - 1) % disk_colors.size()]
		draw_rect(Rect2(pos.x - width / 2.0, y, width, DISK_HEIGHT - 4), color, true)
		draw_rect(Rect2(pos.x - width / 2.0, y, width, DISK_HEIGHT - 4), Color.BLACK, false, 2)

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var idx = _get_tower_at(event.position)
		if idx >= 0:
			_handle_click(idx)

func _get_tower_at(pos: Vector2) -> int:
	for i in TOWER_COUNT:
		if abs(pos.x - tower_positions[i].x) < 110:
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
