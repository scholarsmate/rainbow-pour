extends Control

const BoardCodeCodec = preload("res://scripts/board_code.gd")
const TRAIT_NONE := ""
const TRAIT_PRISMATIC := "prismatic"
const TRAIT_TINTED := "tinted"
const TRAIT_CRACKED := "cracked"
const TOOL_PAINT := 0
const TOOL_ERASE := 1
const OPTIMAL_SOLVER_CALCULATING := -2

var capacity: int = 4
var difficulty_key: String = "normal"
var filled_beakers: int = 6
var empty_beakers: int = 2
var beaker_count: int = 8
var selected_color: int = 0
var selected_tool: int = TOOL_PAINT
var beakers: Array = []
var beaker_traits: Array = []
var color_buttons: Array = []
var segment_buttons: Array = []
var trait_buttons: Array = []
var trait_type_buttons := {}
var selected_trait_type: String = TRAIT_PRISMATIC

var board_grid: GridContainer
var color_grid: GridContainer
var status_label: Label
var count_label: Label
var solver_label: Label
var board_code_input: LineEdit
var copy_button: Button
var play_button: Button
var tool_option: OptionButton
var total_option: OptionButton
var empty_option: OptionButton
var colors_value_label: Label
var capacity_option: OptionButton
var solver_node: Node
var solver_code: String = ""
var solver_result: int = -1
var solver_progress_text := ""

func _ready() -> void:
	if AudioManager and AudioManager.has_method("play_menu_music"):
		AudioManager.play_menu_music()
	difficulty_key = GameSettings.difficulty if GameSettings.DIFFICULTIES.has(GameSettings.difficulty) else "normal"
	capacity = GameSettings.beaker_capacity
	_apply_counts_from_difficulty()
	_initialize_empty_board_state()
	_build_ui()
	_setup_solver_preview()
	_refresh_all()

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	margin.add_child(layout)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	layout.add_child(top_row)

	var menu_button := Button.new()
	menu_button.text = tr("Menu")
	menu_button.custom_minimum_size = Vector2(90, 42)
	menu_button.add_theme_font_size_override("font_size", 18)
	menu_button.pressed.connect(_on_menu_pressed)
	top_row.add_child(menu_button)

	var title := Label.new()
	title.text = tr("Board Builder")
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(title)

	copy_button = Button.new()
	copy_button.text = tr("Copy Code")
	copy_button.custom_minimum_size = Vector2(130, 42)
	copy_button.add_theme_font_size_override("font_size", 18)
	copy_button.pressed.connect(_on_copy_pressed)
	top_row.add_child(copy_button)

	play_button = Button.new()
	play_button.text = tr("Play Board")
	play_button.custom_minimum_size = Vector2(130, 42)
	play_button.add_theme_font_size_override("font_size", 18)
	play_button.pressed.connect(_on_play_pressed)
	top_row.add_child(play_button)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body)

	var panel_scroll := ScrollContainer.new()
	panel_scroll.custom_minimum_size = Vector2(306, 0)
	panel_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(panel_scroll)

	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(286, 0)
	panel.add_theme_constant_override("separation", 12)
	panel_scroll.add_child(panel)

	_add_section_label(panel, tr("Puzzle"))
	_add_count_rows(panel)
	_add_capacity_row(panel)
	_add_tool_row(panel)
	_add_beaker_type_row(panel)

	_add_section_label(panel, tr("Liquid"))
	color_grid = GridContainer.new()
	color_grid.columns = 4
	color_grid.add_theme_constant_override("h_separation", 8)
	color_grid.add_theme_constant_override("v_separation", 8)
	panel.add_child(color_grid)

	count_label = Label.new()
	count_label.add_theme_font_size_override("font_size", 15)
	count_label.add_theme_color_override("font_color", Color(0.78, 0.84, 0.94))
	count_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	count_label.custom_minimum_size = Vector2(0, 112)
	panel.add_child(count_label)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	panel.add_child(action_row)

	var clear_button := Button.new()
	clear_button.text = tr("Clear")
	clear_button.custom_minimum_size = Vector2(88, 40)
	clear_button.pressed.connect(_on_clear_pressed)
	action_row.add_child(clear_button)

	var random_button := Button.new()
	random_button.text = tr("Random Fill")
	random_button.custom_minimum_size = Vector2(138, 40)
	random_button.pressed.connect(_on_random_fill_pressed)
	action_row.add_child(random_button)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color(0.58, 0.94, 1.0))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(0, 62)
	panel.add_child(status_label)

	solver_label = Label.new()
	solver_label.add_theme_font_size_override("font_size", 17)
	solver_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	solver_label.custom_minimum_size = Vector2(0, 34)
	panel.add_child(solver_label)

	var board_scroll := ScrollContainer.new()
	board_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(board_scroll)

	board_grid = GridContainer.new()
	board_grid.columns = _get_board_grid_columns()
	board_grid.add_theme_constant_override("h_separation", 14)
	board_grid.add_theme_constant_override("v_separation", 14)
	board_scroll.add_child(board_grid)

	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 10)
	layout.add_child(code_row)

	var code_label := Label.new()
	code_label.text = tr("Board code")
	code_label.custom_minimum_size = Vector2(110, 34)
	code_label.add_theme_font_size_override("font_size", 18)
	code_label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.98))
	code_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	code_row.add_child(code_label)

	board_code_input = LineEdit.new()
	board_code_input.editable = false
	board_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_code_input.custom_minimum_size = Vector2(0, 34)
	board_code_input.add_theme_font_size_override("font_size", 16)
	code_row.add_child(board_code_input)

	_rebuild_color_grid()
	_rebuild_board_grid()

func _add_section_label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.36, 0.82, 1.0))
	label.custom_minimum_size = Vector2(0, 30)
	parent.add_child(label)

func _add_count_rows(parent: Control) -> void:
	var total_row := HBoxContainer.new()
	total_row.add_theme_constant_override("separation", 10)
	parent.add_child(total_row)

	var total_label := Label.new()
	total_label.text = tr("Beakers")
	total_label.custom_minimum_size = Vector2(74, 34)
	total_label.add_theme_font_size_override("font_size", 18)
	total_label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.98))
	total_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	total_row.add_child(total_label)

	total_option = OptionButton.new()
	total_option.custom_minimum_size = Vector2(120, 34)
	total_option.item_selected.connect(_on_total_count_selected)
	total_row.add_child(total_option)

	var colors_row := HBoxContainer.new()
	colors_row.add_theme_constant_override("separation", 10)
	parent.add_child(colors_row)

	var colors_label := Label.new()
	colors_label.text = tr("Colors")
	colors_label.custom_minimum_size = Vector2(74, 34)
	colors_label.add_theme_font_size_override("font_size", 18)
	colors_label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.98))
	colors_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	colors_row.add_child(colors_label)

	colors_value_label = Label.new()
	colors_value_label.custom_minimum_size = Vector2(120, 34)
	colors_value_label.add_theme_font_size_override("font_size", 18)
	colors_value_label.add_theme_color_override("font_color", Color(0.78, 0.84, 0.94))
	colors_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	colors_row.add_child(colors_value_label)

	var empty_row := HBoxContainer.new()
	empty_row.add_theme_constant_override("separation", 10)
	parent.add_child(empty_row)

	var empty_label := Label.new()
	empty_label.text = tr("Empty")
	empty_label.custom_minimum_size = Vector2(74, 34)
	empty_label.add_theme_font_size_override("font_size", 18)
	empty_label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.98))
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_row.add_child(empty_label)

	empty_option = OptionButton.new()
	empty_option.custom_minimum_size = Vector2(120, 34)
	empty_option.item_selected.connect(_on_empty_count_selected)
	empty_row.add_child(empty_option)

func _add_capacity_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var label := Label.new()
	label.text = tr("Slots")
	label.custom_minimum_size = Vector2(74, 34)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.98))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	capacity_option = OptionButton.new()
	capacity_option.custom_minimum_size = Vector2(120, 34)
	for value in range(GameSettings.CAPACITY_MIN, GameSettings.CAPACITY_MAX + 1):
		var idx := capacity_option.get_item_count()
		capacity_option.add_item(str(value))
		capacity_option.set_item_metadata(idx, value)
	capacity_option.item_selected.connect(_on_capacity_selected)
	row.add_child(capacity_option)

func _add_tool_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var label := Label.new()
	label.text = tr("Tool")
	label.custom_minimum_size = Vector2(74, 34)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.98))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	tool_option = OptionButton.new()
	tool_option.custom_minimum_size = Vector2(150, 34)
	tool_option.add_item(tr("Paint"), TOOL_PAINT)
	tool_option.add_item(tr("Erase"), TOOL_ERASE)
	tool_option.item_selected.connect(_on_tool_selected)
	row.add_child(tool_option)

func _add_beaker_type_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label := Label.new()
	label.text = tr("Type")
	label.custom_minimum_size = Vector2(74, 34)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.98))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	for trait_type in [TRAIT_NONE, TRAIT_PRISMATIC, TRAIT_TINTED, TRAIT_CRACKED]:
		var button := Button.new()
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(58, 34)
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_select_trait_type.bind(trait_type))
		row.add_child(button)
		trait_type_buttons[trait_type] = button

func _setup_solver_preview() -> void:
	var board_script = load("res://scripts/towers.gd")
	solver_node = board_script.new()
	solver_node.visible = false
	solver_node.set_process_input(false)
	add_child(solver_node)
	if solver_node.has_signal("goal_changed"):
		solver_node.connect("goal_changed", Callable(self, "_on_solver_goal_changed"))
	if solver_node.has_signal("solver_progress"):
		solver_node.connect("solver_progress", Callable(self, "_on_solver_progress"))

func _apply_counts_from_difficulty() -> void:
	if difficulty_key == "custom":
		filled_beakers = GameSettings.get_filled_beaker_count()
		empty_beakers = GameSettings.get_empty_beaker_count()
		beaker_count = filled_beakers + empty_beakers
		selected_color = clampi(selected_color, 0, maxi(0, filled_beakers - 1))
		return
	var data: Dictionary = GameSettings.DIFFICULTIES[difficulty_key]
	filled_beakers = int(data["filled_beakers"])
	empty_beakers = int(data["empty_beakers"])
	beaker_count = filled_beakers + empty_beakers
	selected_color = clampi(selected_color, 0, maxi(0, filled_beakers - 1))

func _reset_board() -> void:
	_initialize_empty_board_state()
	_rebuild_color_grid()
	_rebuild_board_grid()
	_refresh_all()

func _initialize_empty_board_state() -> void:
	beakers.clear()
	beaker_traits.clear()
	for idx in beaker_count:
		beakers.append([])
		beaker_traits.append(_make_trait())

func _rebuild_color_grid() -> void:
	if not color_grid:
		return
	for child in color_grid.get_children():
		color_grid.remove_child(child)
		child.queue_free()
	color_buttons.clear()
	var symbols := GameSettings.get_liquid_symbols()
	for color_idx in filled_beakers:
		var button := Button.new()
		button.custom_minimum_size = Vector2(54, 44)
		button.text = str(symbols[color_idx % symbols.size()])
		button.add_theme_font_size_override("font_size", 18)
		button.pressed.connect(_select_color.bind(color_idx))
		color_grid.add_child(button)
		color_buttons.append(button)
	_refresh_palette()

func _rebuild_board_grid() -> void:
	if not board_grid:
		return
	for child in board_grid.get_children():
		board_grid.remove_child(child)
		child.queue_free()
	segment_buttons.clear()
	trait_buttons.clear()
	board_grid.columns = _get_board_grid_columns()
	for beaker_idx in beaker_count:
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(94, 48 + float(capacity) * 30.0)
		card.add_theme_constant_override("separation", 4)
		board_grid.add_child(card)

		var trait_button := Button.new()
		trait_button.custom_minimum_size = Vector2(88, 32)
		trait_button.add_theme_font_size_override("font_size", 13)
		trait_button.pressed.connect(_cycle_trait.bind(beaker_idx))
		card.add_child(trait_button)
		trait_buttons.append(trait_button)

		var buttons_for_beaker := []
		buttons_for_beaker.resize(capacity)
		for display_level in range(capacity - 1, -1, -1):
			var segment_button := Button.new()
			segment_button.custom_minimum_size = Vector2(88, 28)
			segment_button.add_theme_font_size_override("font_size", 14)
			segment_button.pressed.connect(_on_segment_pressed.bind(beaker_idx, display_level))
			card.add_child(segment_button)
			buttons_for_beaker[display_level] = segment_button
		segment_buttons.append(buttons_for_beaker)
	_refresh_board()

func _refresh_all() -> void:
	_sync_count_options()
	_sync_capacity_option()
	_refresh_trait_type_buttons()
	_refresh_palette()
	_refresh_board()
	var code := _get_solver_signature()
	var valid := _is_board_valid()
	_update_solver_preview(valid, code)
	_refresh_code_status_and_actions(valid)

func _refresh_code_status_and_actions(valid: bool) -> void:
	var ready := valid and solver_result >= 0
	if board_code_input:
		board_code_input.text = _export_board_code(true) if ready else ""
	if copy_button:
		copy_button.disabled = not ready
	if play_button:
		play_button.disabled = not ready
	_refresh_status(valid)

func _sync_count_options() -> void:
	_populate_count_option(total_option, 2, GameSettings.MAX_BEAKERS, beaker_count)
	_populate_count_option(empty_option, 1, beaker_count - 1, empty_beakers)
	if colors_value_label:
		colors_value_label.text = "%d" % filled_beakers

func _populate_count_option(option: OptionButton, min_value: int, max_value: int, selected_value: int) -> void:
	if not option:
		return
	option.clear()
	var selected_idx := 0
	for value in range(min_value, max_value + 1):
		var idx := option.get_item_count()
		option.add_item(str(value))
		option.set_item_metadata(idx, value)
		if value == selected_value:
			selected_idx = idx
	option.select(selected_idx)

func _sync_capacity_option() -> void:
	if not capacity_option:
		return
	for idx in capacity_option.get_item_count():
		if int(capacity_option.get_item_metadata(idx)) == capacity:
			capacity_option.select(idx)
			return

func _refresh_palette() -> void:
	var counts := _get_color_counts()
	for idx in color_buttons.size():
		var button: Button = color_buttons[idx]
		var base := _get_liquid_color(idx)
		var is_filled := int(counts[idx]) >= capacity
		button.disabled = is_filled
		var alpha := 0.40 if is_filled else 0.92
		var border := Color(1.0, 1.0, 1.0, 0.92) if idx == selected_color else Color(0.0, 0.0, 0.0, 0.38)
		if is_filled:
			border = Color(0.72, 0.78, 0.86, 0.42) if idx == selected_color else Color(0.0, 0.0, 0.0, 0.22)
		_apply_button_style(button, Color(base.r, base.g, base.b, alpha), border, _ink_for_color(base))

func _refresh_trait_type_buttons() -> void:
	for trait_type in trait_type_buttons:
		var button: Button = trait_type_buttons[trait_type]
		var fill := Color(0.08, 0.10, 0.15, 0.95)
		var border := Color(0.0, 0.0, 0.0, 0.38)
		var font_color := Color(0.82, 0.88, 0.96)
		button.text = _get_trait_button_label(str(trait_type))
		button.button_pressed = str(trait_type) == selected_trait_type
		if trait_type == TRAIT_PRISMATIC:
			fill = Color(0.14, 0.18, 0.24, 0.95)
			border = Color(1.0, 1.0, 1.0, 0.48)
			font_color = Color(0.96, 0.98, 1.0)
		elif trait_type == TRAIT_TINTED:
			var base := _get_liquid_color(selected_color)
			fill = Color(base.r, base.g, base.b, 0.72)
			border = Color(1.0, 1.0, 1.0, 0.42)
			font_color = _ink_for_color(base)
		elif trait_type == TRAIT_CRACKED:
			fill = Color(0.18, 0.08, 0.07, 0.95)
			border = Color(1.0, 0.34, 0.24, 0.62)
			font_color = Color(1.0, 0.90, 0.84)
		if str(trait_type) == selected_trait_type:
			border = Color(0.92, 0.96, 1.0, 0.96)
		_apply_button_style(button, fill, border, font_color)

func _refresh_board() -> void:
	if segment_buttons.size() != beaker_count:
		return
	var symbols := GameSettings.get_liquid_symbols()
	for beaker_idx in beaker_count:
		var tube: Array = beakers[beaker_idx]
		for segment_idx in capacity:
			var button: Button = segment_buttons[beaker_idx][segment_idx]
			if segment_idx < tube.size():
				var color_idx := int(tube[segment_idx])
				var base := _get_liquid_color(color_idx)
				button.text = str(symbols[color_idx % symbols.size()])
				_apply_button_style(button, Color(base.r, base.g, base.b, 0.88), Color(1.0, 1.0, 1.0, 0.24), _ink_for_color(base))
			else:
				button.text = ""
				_apply_button_style(button, Color(0.04, 0.055, 0.08, 0.88), Color(0.62, 0.80, 1.0, 0.34), Color(0.82, 0.88, 0.96))
		_refresh_trait_button(beaker_idx)

func _refresh_trait_button(beaker_idx: int) -> void:
	if beaker_idx < 0 or beaker_idx >= trait_buttons.size():
		return
	var button: Button = trait_buttons[beaker_idx]
	var trait_data: Dictionary = beaker_traits[beaker_idx]
	var trait_type := str(trait_data.get("type", TRAIT_NONE))
	if trait_type == TRAIT_PRISMATIC:
		button.text = _get_trait_button_label(TRAIT_PRISMATIC)
		_apply_button_style(button, Color(0.14, 0.18, 0.24, 0.95), Color(1.0, 1.0, 1.0, 0.86), Color(0.96, 0.98, 1.0))
	elif trait_type == TRAIT_TINTED:
		var color_idx := int(trait_data.get("color", 0))
		var base := _get_liquid_color(color_idx)
		button.text = _get_trait_button_label(TRAIT_TINTED, color_idx)
		_apply_button_style(button, Color(base.r, base.g, base.b, 0.72), Color(1.0, 1.0, 1.0, 0.70), _ink_for_color(base))
	elif trait_type == TRAIT_CRACKED:
		button.text = _get_trait_button_label(TRAIT_CRACKED)
		_apply_button_style(button, Color(0.18, 0.08, 0.07, 0.95), Color(1.0, 0.34, 0.24, 0.86), Color(1.0, 0.90, 0.84))
	else:
		button.text = _get_trait_button_label(TRAIT_NONE)
		_apply_button_style(button, Color(0.08, 0.10, 0.15, 0.95), Color(0.62, 0.80, 1.0, 0.34), Color(0.82, 0.88, 0.96))

func _refresh_status(valid: bool) -> void:
	var counts := _get_color_counts()
	var parts := PackedStringArray()
	for color_idx in filled_beakers:
		parts.append("%d:%d/%d" % [color_idx + 1, int(counts[color_idx]), capacity])
	count_label.text = "%d beakers  |  %d colors + %d empty\nCounts  %s" % [
		beaker_count,
		filled_beakers,
		empty_beakers,
		"  ".join(parts),
	]
	if valid:
		if solver_result == OPTIMAL_SOLVER_CALCULATING:
			status_label.text = tr("Solving goal...")
			status_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
		elif solver_result < 0:
			status_label.text = tr("Goal not found.")
			status_label.add_theme_color_override("font_color", Color(1.0, 0.74, 0.30))
		else:
			status_label.text = tr("Code ready: %d pours.") % solver_result
			status_label.add_theme_color_override("font_color", Color(0.58, 0.94, 1.0))
	else:
		if not _has_valid_color_counts():
			status_label.text = tr("Use %d of each color.") % capacity
		elif _has_cracked_shatter_setup():
			status_label.text = tr("No full one-color cracked beakers.")
		status_label.add_theme_color_override("font_color", Color(1.0, 0.74, 0.30))

func _update_solver_preview(valid: bool, code: String) -> void:
	if not solver_node:
		return
	if not valid:
		solver_code = ""
		solver_result = -1
		solver_progress_text = ""
		solver_node.set("_solver_active", false)
		solver_label.text = tr("Place pieces")
		return
	if code == solver_code:
		return
	solver_code = code
	solver_result = OPTIMAL_SOLVER_CALCULATING
	solver_progress_text = ""
	solver_label.text = tr("Finding goal")
	solver_node.set("beaker_capacity", capacity)
	solver_node.set("filled_beakers", filled_beakers)
	solver_node.set("empty_beakers", empty_beakers)
	solver_node.set("beaker_count", beaker_count)
	solver_node.set("beakers_per_row", _get_board_grid_columns())
	solver_node.set("beakers", _copy_beakers(beakers))
	solver_node.set("beaker_traits", _get_solver_traits())
	solver_node.call("_start_optimal_solver", _copy_beakers(beakers))

func _on_solver_goal_changed(optimal_pours: int) -> void:
	if solver_code == "":
		return
	solver_result = optimal_pours
	if optimal_pours != OPTIMAL_SOLVER_CALCULATING:
		solver_progress_text = ""
	if optimal_pours == OPTIMAL_SOLVER_CALCULATING:
		_refresh_solver_progress_label()
	elif optimal_pours < 0:
		solver_label.text = tr("Goal not found")
	else:
		solver_label.text = tr("%d pours") % optimal_pours
	_refresh_code_status_and_actions(_is_board_valid())

func _on_solver_progress(searched: int, frontier: int, depth: int, limit: int) -> void:
	if solver_code == "" or solver_result != OPTIMAL_SOLVER_CALCULATING:
		return
	solver_progress_text = "%s/%s checked | d%d | %s open" % [
		_format_solver_count(searched),
		_format_solver_count(limit),
		depth,
		_format_solver_count(frontier),
	]
	_refresh_solver_progress_label()

func _refresh_solver_progress_label() -> void:
	if solver_progress_text == "":
		solver_label.text = tr("Finding goal")
	else:
		solver_label.text = solver_progress_text

func _on_total_count_selected(index: int) -> void:
	if not total_option:
		return
	var next_total := int(total_option.get_item_metadata(index))
	var next_empty := mini(empty_beakers, next_total - 1)
	_set_counts(next_total - next_empty, next_empty)

func _on_empty_count_selected(index: int) -> void:
	if not empty_option:
		return
	var next_empty := int(empty_option.get_item_metadata(index))
	_set_counts(beaker_count - next_empty, next_empty)

func _set_counts(next_filled: int, next_empty: int) -> void:
	next_filled = clampi(next_filled, 1, GameSettings.MAX_BEAKERS - 1)
	next_empty = clampi(next_empty, 1, GameSettings.MAX_BEAKERS - next_filled)
	if next_filled == filled_beakers and next_empty == empty_beakers:
		_sync_count_options()
		return
	filled_beakers = next_filled
	empty_beakers = next_empty
	beaker_count = filled_beakers + empty_beakers
	var matching_difficulty := GameSettings.find_difficulty_for_counts(filled_beakers, empty_beakers)
	difficulty_key = matching_difficulty
	selected_color = clampi(selected_color, 0, maxi(0, filled_beakers - 1))
	_reset_board()
	if AudioManager:
		AudioManager.play_select()

func _on_capacity_selected(index: int) -> void:
	var next_capacity := int(capacity_option.get_item_metadata(index))
	if next_capacity == capacity:
		return
	capacity = next_capacity
	_reset_board()
	if AudioManager:
		AudioManager.play_select()

func _on_tool_selected(index: int) -> void:
	selected_tool = int(tool_option.get_item_id(index))
	if AudioManager:
		AudioManager.play_select()

func _select_color(color_idx: int) -> void:
	selected_color = clampi(color_idx, 0, filled_beakers - 1)
	selected_tool = TOOL_PAINT
	if tool_option:
		tool_option.select(TOOL_PAINT)
	_refresh_trait_type_buttons()
	_refresh_palette()
	if AudioManager:
		AudioManager.play_select()

func _select_trait_type(trait_type: String) -> void:
	if not [TRAIT_NONE, TRAIT_PRISMATIC, TRAIT_TINTED, TRAIT_CRACKED].has(trait_type):
		return
	selected_trait_type = trait_type
	_refresh_trait_type_buttons()
	if AudioManager:
		AudioManager.play_select()

func _on_segment_pressed(beaker_idx: int, segment_idx: int) -> void:
	if beaker_idx < 0 or beaker_idx >= beakers.size():
		return
	var tube: Array = beakers[beaker_idx]
	if selected_tool == TOOL_ERASE:
		if segment_idx < tube.size():
			while tube.size() > segment_idx:
				tube.pop_back()
			_refresh_all()
			if AudioManager:
				AudioManager.play_select()
		return
	var current_color := int(tube[segment_idx]) if segment_idx < tube.size() else -1
	if not _can_place_color(selected_color, current_color):
		if AudioManager:
			AudioManager.play_invalid()
		return
	if segment_idx < tube.size():
		tube[segment_idx] = selected_color
	elif tube.size() < capacity:
		tube.append(selected_color)
	else:
		if AudioManager:
			AudioManager.play_invalid()
		return
	_advance_selected_color_if_filled()
	_refresh_all()
	if AudioManager:
		AudioManager.play_select()

func _cycle_trait(beaker_idx: int) -> void:
	if beaker_idx < 0 or beaker_idx >= beaker_traits.size():
		return
	beaker_traits[beaker_idx] = _make_trait(selected_trait_type, selected_color if selected_trait_type == TRAIT_TINTED else -1)
	_refresh_all()
	if AudioManager:
		AudioManager.play_select()

func _on_clear_pressed() -> void:
	_reset_board()
	if AudioManager:
		AudioManager.play_click()

func _on_random_fill_pressed() -> void:
	_random_fill_board_once()
	_repair_completed_beakers()
	_refresh_all()
	if AudioManager:
		AudioManager.play_click()

func _random_fill_board_once() -> void:
	var pool := []
	for color_idx in filled_beakers:
		for slot in capacity:
			pool.append(color_idx)
	pool.shuffle()
	for beaker_idx in beaker_count:
		beakers[beaker_idx].clear()
	for idx in pool.size():
		var beaker_idx := int(idx / capacity)
		beakers[beaker_idx].append(pool[idx])

func _repair_completed_beakers() -> void:
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

func _on_copy_pressed() -> void:
	if not _is_board_valid() or solver_result < 0:
		if AudioManager:
			AudioManager.play_invalid()
		return
	var code := _export_board_code(true)
	DisplayServer.clipboard_set(code)
	board_code_input.text = code
	status_label.text = tr("Copied board code.")
	status_label.add_theme_color_override("font_color", Color(0.58, 0.94, 1.0))
	if AudioManager:
		AudioManager.play_select()

func _on_play_pressed() -> void:
	if not _is_board_valid() or solver_result < 0:
		if AudioManager:
			AudioManager.play_invalid()
		return
	GameSettings.set_pending_board_code(_export_board_code(true))
	if AudioManager:
		AudioManager.play_click()
	get_tree().change_scene_to_file("res://scenes/beaker.tscn")

func _on_menu_pressed() -> void:
	if AudioManager:
		AudioManager.play_click()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _is_board_valid() -> bool:
	return _has_valid_color_counts() and not _has_cracked_shatter_setup()

func _has_valid_color_counts() -> bool:
	var counts := _get_color_counts()
	for color_idx in filled_beakers:
		if int(counts[color_idx]) != capacity:
			return false
	return true

func _has_cracked_shatter_setup() -> bool:
	for idx in beaker_count:
		if idx >= beaker_traits.size() or idx >= beakers.size():
			continue
		var trait_data: Dictionary = beaker_traits[idx]
		if str(trait_data.get("type", TRAIT_NONE)) == TRAIT_CRACKED and _is_tube_complete(beakers[idx]):
			return true
	return false

func _has_completed_beaker() -> bool:
	for tube in beakers:
		if _is_tube_complete(tube):
			return true
	return false

func _is_tube_complete(tube: Array) -> bool:
	if tube.size() != capacity:
		return false
	var first = tube[0]
	for color in tube:
		if color != first:
			return false
	return true

func _get_color_counts() -> Array:
	var counts := []
	counts.resize(filled_beakers)
	for idx in filled_beakers:
		counts[idx] = 0
	for tube in beakers:
		for color in tube:
			var color_idx := int(color)
			if color_idx >= 0 and color_idx < filled_beakers:
				counts[color_idx] = int(counts[color_idx]) + 1
	return counts

func _can_place_color(color_idx: int, replacing_color: int = -1) -> bool:
	if color_idx < 0 or color_idx >= filled_beakers:
		return false
	if replacing_color == color_idx:
		return true
	var counts := _get_color_counts()
	return int(counts[color_idx]) < capacity

func _advance_selected_color_if_filled() -> void:
	var counts := _get_color_counts()
	if selected_color < 0 or selected_color >= counts.size() or int(counts[selected_color]) < capacity:
		return
	for offset in range(1, filled_beakers + 1):
		var next_color := (selected_color + offset) % filled_beakers
		if int(counts[next_color]) < capacity:
			selected_color = next_color
			return

func _export_board_code(include_cached_goal: bool = true) -> String:
	var cached_goal := solver_result if include_cached_goal else -1
	return BoardCodeCodec.encode(capacity, filled_beakers, empty_beakers, beakers, beaker_traits, cached_goal)

func _get_solver_signature() -> String:
	return BoardCodeCodec.encode(capacity, filled_beakers, empty_beakers, beakers, _get_solver_traits(), -1)

func _get_solver_traits() -> Array:
	var solver_traits := []
	for idx in beaker_count:
		var trait_data: Dictionary = beaker_traits[idx] if idx < beaker_traits.size() else _make_trait()
		if str(trait_data.get("type", TRAIT_NONE)) == TRAIT_CRACKED:
			solver_traits.append(_make_trait(TRAIT_CRACKED))
		else:
			solver_traits.append(_make_trait())
	return solver_traits

func _get_board_grid_columns() -> int:
	if beaker_count <= 0:
		return 1
	if beaker_count <= 8:
		return int(ceil(float(beaker_count) / 2.0))
	return 4

func _make_trait(trait_type: String = TRAIT_NONE, color_idx: int = -1) -> Dictionary:
	return {"type": trait_type, "color": color_idx}

func _get_trait_button_label(trait_type: String, color_idx: int = -1) -> String:
	if trait_type == TRAIT_PRISMATIC:
		return tr("Prism")
	if trait_type == TRAIT_TINTED:
		var tint_color := selected_color if color_idx < 0 else color_idx
		return tr("Tint %d") % (tint_color + 1)
	if trait_type == TRAIT_CRACKED:
		return tr("Crack")
	return tr("Plain")

func _format_solver_count(value: int) -> String:
	var amount := maxi(0, value)
	if amount >= 1000000:
		return "%.1fm" % (float(amount) / 1000000.0)
	if amount >= 1000:
		return "%.1fk" % (float(amount) / 1000.0)
	return str(amount)

func _copy_beakers(source: Array) -> Array:
	var copy := []
	for tube in source:
		copy.append((tube as Array).duplicate())
	return copy

func _get_liquid_color(color_idx: int) -> Color:
	var colors := GameSettings.get_liquid_colors()
	if colors.is_empty():
		return Color.WHITE
	return colors[color_idx % colors.size()]

func _ink_for_color(base: Color) -> Color:
	var luminance := base.r * 0.299 + base.g * 0.587 + base.b * 0.114
	return Color(0.02, 0.025, 0.035, 0.92) if luminance > 0.55 else Color(1.0, 1.0, 1.0, 0.94)

func _apply_button_style(button: Button, fill: Color, border: Color, font_color: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = fill
	normal.border_color = border
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_right = 6
	normal.corner_radius_bottom_left = 6

	var hover := normal.duplicate()
	hover.bg_color = fill.lightened(0.08)
	var pressed := normal.duplicate()
	pressed.bg_color = fill.darkened(0.10)
	var disabled := normal.duplicate()
	disabled.bg_color = fill.darkened(0.22)
	disabled.border_color = border.darkened(0.20)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", font_color)
	button.add_theme_color_override("font_pressed_color", font_color)
	button.add_theme_color_override("font_disabled_color", Color(font_color.r, font_color.g, font_color.b, 0.58))
