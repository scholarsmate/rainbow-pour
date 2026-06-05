extends Node2D

const SCORE_MAX := 1000
const REPEATED_STATE_LOSS_COUNT := 3
const MULLIGAN_POUR_PENALTY := 0.5
const MULLIGAN_MAX_USES := 1
const CHEAT_POUR_PENALTY := 2.0
const CHEAT_MAX_USES := 1
const OPTIMAL_SOLVER_CALCULATING := -2
const GOAL_SPINNER_TICK := 0.12
const GOAL_SPINNER_FRAMES := ["|", "/", "-", "\\"]
const STAR_FILLED := "★"
const STAR_EMPTY := "☆"
const STAR_SPARK := "✦"

@export var move_label: String = "Moves"
@export var win_label: String = "moves"

@onready var towers = $Towers
@onready var move_counter = $UI/MoveCounter
@onready var goal_label = get_node_or_null("UI/GoalLabel")
@onready var possible_moves_label = get_node_or_null("UI/PossibleMovesLabel")
@onready var mulligan_button = get_node_or_null("UI/MulliganButton")
@onready var settings_button = get_node_or_null("UI/SettingsButton")
@onready var instructions_label: Label = get_node_or_null("UI/Instructions")

var settings_overlay: Control
var disk_count_slider: HSlider
var disk_count_value: Label
var depth_slider: HSlider
var depth_value: Label
var goal_toggle: CheckButton
var special_beakers_toggle: CheckButton
var palette_option: OptionButton
var liquid_symbols_toggle: CheckButton
var liquid_alpha_slider: HSlider
var liquid_alpha_value: Label
var board_code_input: LineEdit
var board_code_status: Label
var music_slider: HSlider
var music_value: Label
var effects_slider: HSlider
var effects_value: Label
var difficulty_buttons := {}

var moves = 0
var _settings_ready := false
var _state_visits := {}
var _mulligans_used := 0
var _cheats_used := 0
var _goal_spinner_time := 0.0
var _goal_spinner_frame := 0
var _solver_progress_text := ""
var _victory_stars_shown := false
var _score_forced_zero := false
var _default_instructions_text := ""
var _recovery_cheats_available_for_loss := false
var _last_recovery_loss_title := ""
var _last_recovery_loss_detail := ""

func _ready():
	towers.disk_moved.connect(_on_disk_moved)
	if towers.has_signal("goal_changed"):
		towers.connect("goal_changed", Callable(self, "_on_goal_changed"))
	if towers.has_signal("solver_progress"):
		towers.connect("solver_progress", Callable(self, "_on_solver_progress"))
	if towers.has_signal("no_moves_available"):
		towers.connect("no_moves_available", Callable(self, "_on_no_moves_available"))
	if towers.has_signal("cheat_applied"):
		towers.connect("cheat_applied", Callable(self, "_on_cheat_applied"))
	if towers.has_signal("cheat_cancelled"):
		towers.connect("cheat_cancelled", Callable(self, "_on_cheat_cancelled"))
	if instructions_label:
		_default_instructions_text = instructions_label.text
	_build_settings_dialog()
	_load_pending_board_code_if_any()
	update_move_counter()
	update_possible_moves_label()
	update_goal_label()
	_update_music_pressure()
	_setup_settings_ui()
	_reset_stalemate_tracker()
	_update_mulligan_button()
	_check_for_no_moves.call_deferred()

func _load_pending_board_code_if_any() -> void:
	if not GameSettings.has_method("consume_pending_board_code"):
		return
	var code := str(GameSettings.call("consume_pending_board_code")).strip_edges()
	if code == "":
		return
	if towers.has_method("import_board_code") and bool(towers.call("import_board_code", code)):
		return
	push_warning("Pending board code failed to load.")

func _process(delta: float):
	if _get_optimal_pours() != OPTIMAL_SOLVER_CALCULATING:
		return
	_goal_spinner_time += delta
	if _goal_spinner_time < GOAL_SPINNER_TICK:
		return
	_goal_spinner_time = fmod(_goal_spinner_time, GOAL_SPINNER_TICK)
	_goal_spinner_frame = (_goal_spinner_frame + 1) % GOAL_SPINNER_FRAMES.size()
	update_goal_label()
	_refresh_victory_score()

func _build_settings_dialog():
	if not settings_button:
		return
	settings_button.pressed.connect(_open_settings_dialog)
	var ui = get_node_or_null("UI")
	if not ui:
		return
	var has_water_sort_settings := _has_water_sort_settings()
	var has_hanoi_settings := _has_hanoi_settings()

	settings_overlay = Control.new()
	settings_overlay.name = "SettingsOverlay"
	settings_overlay.visible = false
	settings_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(settings_overlay)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0, 0, 0, 0.68)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_settings_backdrop_gui_input)
	settings_overlay.add_child(backdrop)

	var card := ColorRect.new()
	card.name = "SettingsCard"
	card.color = Color(0.075, 0.09, 0.14, 0.98)
	var card_size: Vector2
	if has_water_sort_settings:
		card_size = Vector2(700, 680)
	elif has_hanoi_settings:
		card_size = Vector2(560, 390)
	else:
		card_size = Vector2(520, 320)
	card.custom_minimum_size = card_size
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -card_size.x * 0.5
	card.offset_top = -card_size.y * 0.5
	card.offset_right = card_size.x * 0.5
	card.offset_bottom = card_size.y * 0.5
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_overlay.add_child(card)

	var stripe := ColorRect.new()
	stripe.color = Color(0.14, 0.70, 1.0, 1.0)
	stripe.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stripe.offset_bottom = 5.0
	card.add_child(stripe)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 28.0
	content.offset_top = 22.0
	content.offset_right = -28.0
	content.offset_bottom = -24.0
	content.add_theme_constant_override("separation", 12)
	card.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)

	var title := Label.new()
	title.text = tr("Settings")
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = tr("Close")
	close_btn.custom_minimum_size = Vector2(92, 38)
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.pressed.connect(_close_settings_dialog)
	header.add_child(close_btn)

	if has_hanoi_settings:
		_add_section_label(content, tr("Puzzle"))
		var disk_controls := _add_labeled_slider_row(content, tr("Discs"))
		disk_count_slider = disk_controls["slider"] as HSlider
		disk_count_value = disk_controls["value"] as Label
		disk_count_slider.min_value = GameSettings.HANOI_DISK_COUNT_MIN
		disk_count_slider.max_value = GameSettings.HANOI_DISK_COUNT_MAX
		disk_count_slider.step = 1.0
		disk_count_slider.value_changed.connect(_on_disk_count_changed)

	if has_water_sort_settings:
		_add_section_label(content, tr("Puzzle"))
		var capacity_controls := _add_labeled_slider_row(content, tr("Slots"))
		depth_slider = capacity_controls["slider"] as HSlider
		depth_value = capacity_controls["value"] as Label
		depth_slider.min_value = GameSettings.CAPACITY_MIN
		depth_slider.max_value = GameSettings.CAPACITY_MAX
		depth_slider.step = 1.0
		depth_slider.value_changed.connect(_on_depth_changed)
		_add_difficulty_row(content)

		goal_toggle = CheckButton.new()
		goal_toggle.text = tr("Show optimal goal")
		goal_toggle.add_theme_font_size_override("font_size", 18)
		goal_toggle.toggled.connect(_on_show_goal_toggled)
		content.add_child(goal_toggle)

		special_beakers_toggle = CheckButton.new()
		special_beakers_toggle.text = tr("Bonus beakers")
		special_beakers_toggle.add_theme_font_size_override("font_size", 18)
		special_beakers_toggle.toggled.connect(_on_special_beakers_toggled)
		content.add_child(special_beakers_toggle)

		_add_board_code_row(content)

		_add_section_label(content, tr("Display"))
		var palette_controls := _add_labeled_option_row(content, tr("Palette"))
		palette_option = palette_controls["option"] as OptionButton
		palette_option.item_selected.connect(_on_palette_selected)

		var liquid_alpha_controls := _add_labeled_slider_row(content, tr("Liquid opacity"))
		liquid_alpha_slider = liquid_alpha_controls["slider"] as HSlider
		liquid_alpha_value = liquid_alpha_controls["value"] as Label
		liquid_alpha_slider.min_value = GameSettings.LIQUID_ALPHA_MIN
		liquid_alpha_slider.max_value = GameSettings.LIQUID_ALPHA_MAX
		liquid_alpha_slider.step = 0.01
		liquid_alpha_slider.value_changed.connect(_on_liquid_alpha_changed)

		liquid_symbols_toggle = CheckButton.new()
		liquid_symbols_toggle.text = tr("Show liquid symbols")
		liquid_symbols_toggle.add_theme_font_size_override("font_size", 18)
		liquid_symbols_toggle.toggled.connect(_on_liquid_symbols_toggled)
		content.add_child(liquid_symbols_toggle)

	_add_section_label(content, tr("Audio"))
	var music_controls := _add_labeled_slider_row(content, tr("Music"))
	music_slider = music_controls["slider"] as HSlider
	music_value = music_controls["value"] as Label
	music_slider.min_value = 0.0
	music_slider.max_value = 1.0
	music_slider.step = 0.01
	music_slider.value_changed.connect(_on_music_volume_changed)

	var effects_controls := _add_labeled_slider_row(content, tr("Effects"))
	effects_slider = effects_controls["slider"] as HSlider
	effects_value = effects_controls["value"] as Label
	effects_slider.min_value = 0.0
	effects_slider.max_value = 1.0
	effects_slider.step = 0.01
	effects_slider.value_changed.connect(_on_effects_volume_changed)

func _has_water_sort_settings() -> bool:
	return towers.has_signal("goal_changed") and towers.has_method("retry_current_puzzle")

func _has_hanoi_settings() -> bool:
	return towers.get("disk_count") != null and not _has_water_sort_settings()

func _add_section_label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.36, 0.82, 1.0))
	label.custom_minimum_size = Vector2(0, 30)
	parent.add_child(label)

func _add_labeled_slider_row(parent: Control, label_text: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(110, 34)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.98))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(300, 34)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(64, 34)
	value_label.add_theme_font_size_override("font_size", 18)
	value_label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.98))
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value_label)

	return {"slider": slider, "value": value_label}

func _add_labeled_option_row(parent: Control, label_text: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(110, 34)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.98))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(300, 34)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)

	return {"option": option}

func _add_board_code_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var label := Label.new()
	label.text = tr("Board code")
	label.custom_minimum_size = Vector2(110, 34)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.98))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	board_code_input = LineEdit.new()
	board_code_input.custom_minimum_size = Vector2(300, 34)
	board_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_code_input.placeholder_text = "RP1..."
	row.add_child(board_code_input)

	var copy_btn := Button.new()
	copy_btn.text = tr("Copy")
	copy_btn.custom_minimum_size = Vector2(72, 34)
	copy_btn.pressed.connect(_on_copy_board_code_pressed)
	row.add_child(copy_btn)

	var load_btn := Button.new()
	load_btn.text = tr("Load")
	load_btn.custom_minimum_size = Vector2(72, 34)
	load_btn.pressed.connect(_on_load_board_code_pressed)
	row.add_child(load_btn)

	board_code_status = Label.new()
	board_code_status.custom_minimum_size = Vector2(0, 22)
	board_code_status.add_theme_font_size_override("font_size", 15)
	board_code_status.add_theme_color_override("font_color", Color(0.58, 0.94, 1.0))
	parent.add_child(board_code_status)

func _add_difficulty_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label := Label.new()
	label.text = tr("Difficulty")
	label.custom_minimum_size = Vector2(110, 34)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.98))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	for key in ["easy", "normal", "hard"]:
		var button := Button.new()
		button.text = tr(GameSettings.DIFFICULTIES[key]["label"])
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(102, 34)
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(_set_difficulty.bind(key))
		difficulty_buttons[key] = button
		row.add_child(button)

func _open_settings_dialog():
	if not settings_overlay:
		return
	_setup_settings_ui()
	settings_overlay.visible = true
	settings_overlay.move_to_front()
	towers.set_process_input(false)
	if AudioManager:
		AudioManager.play_click()

func _close_settings_dialog():
	if not settings_overlay or not settings_overlay.visible:
		return
	settings_overlay.visible = false
	towers.set_process_input(true)
	if AudioManager:
		AudioManager.play_click()

func _on_settings_backdrop_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_settings_dialog()

func _unhandled_input(event: InputEvent):
	if settings_overlay and settings_overlay.visible and event.is_action_pressed("ui_cancel"):
		_close_settings_dialog()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and towers and towers.has_method("is_choosing_cheat") and bool(towers.call("is_choosing_cheat")):
		towers.call("cancel_cheat")
		get_viewport().set_input_as_handled()

func _setup_settings_ui():
	if disk_count_slider:
		disk_count_slider.min_value = GameSettings.HANOI_DISK_COUNT_MIN
		disk_count_slider.max_value = GameSettings.HANOI_DISK_COUNT_MAX
		disk_count_slider.value = GameSettings.hanoi_disk_count
		if disk_count_value:
			disk_count_value.text = str(GameSettings.hanoi_disk_count)
	if depth_slider:
		depth_slider.min_value = GameSettings.CAPACITY_MIN
		depth_slider.max_value = GameSettings.CAPACITY_MAX
		depth_slider.value = GameSettings.beaker_capacity
		if depth_value:
			depth_value.text = str(GameSettings.beaker_capacity)
	if goal_toggle:
		goal_toggle.button_pressed = GameSettings.show_goal_hint
	if special_beakers_toggle:
		special_beakers_toggle.button_pressed = GameSettings.special_beakers_enabled
	if palette_option:
		_sync_palette_option()
	if liquid_alpha_slider:
		liquid_alpha_slider.min_value = GameSettings.LIQUID_ALPHA_MIN
		liquid_alpha_slider.max_value = GameSettings.LIQUID_ALPHA_MAX
		liquid_alpha_slider.value = GameSettings.liquid_alpha
	if liquid_alpha_value:
		liquid_alpha_value.text = _format_volume(GameSettings.liquid_alpha)
	if liquid_symbols_toggle:
		liquid_symbols_toggle.button_pressed = GameSettings.show_liquid_symbols
	if board_code_input and towers and towers.has_method("export_board_code"):
		board_code_input.text = str(towers.call("export_board_code"))
	if board_code_status:
		board_code_status.text = ""
	if music_slider:
		music_slider.value = GameSettings.music_volume
	if music_value:
		music_value.text = _format_volume(GameSettings.music_volume)
	if effects_slider:
		effects_slider.value = GameSettings.effects_volume
	if effects_value:
		effects_value.text = _format_volume(GameSettings.effects_volume)
	_sync_difficulty_buttons()
	_settings_ready = true

func _on_disk_moved():
	moves += 1
	update_move_counter()
	update_possible_moves_label()
	update_goal_label()
	_update_music_pressure()
	_update_mulligan_button()
	if towers.check_complete():
		_show_victory_delayed()
	elif _is_pour_limit_exceeded():
		var limit := _get_pour_limit()
		_show_loss(tr("POUR LIMIT REACHED"), tr("You crossed the %d-%s limit.") % [limit, tr(win_label)])
	elif _record_repeated_state():
		_show_loss(tr("STUCK IN A LOOP"), tr("This board state repeated %d times.") % REPEATED_STATE_LOSS_COUNT, true)

func update_move_counter():
	move_counter.text = "%s: %d" % [tr(move_label), moves]

func update_possible_moves_label():
	if not possible_moves_label:
		return
	if not towers.has_method("count_available_moves"):
		possible_moves_label.visible = false
		return
	possible_moves_label.visible = true
	var count := int(towers.call("count_available_moves"))
	possible_moves_label.text = tr("Possible moves: %d") % count

func _on_goal_changed(_optimal_pours: int):
	_solver_progress_text = ""
	update_goal_label()
	_refresh_victory_score()
	_update_music_pressure()

func _on_solver_progress(searched: int, frontier: int, depth: int, limit: int) -> void:
	_solver_progress_text = "%s/%s checked | depth %d | %s open" % [
		_format_solver_count(searched),
		_format_solver_count(limit),
		depth,
		_format_solver_count(frontier),
	]
	update_goal_label()

func update_goal_label():
	if not goal_label:
		return
	if not GameSettings.show_goal_hint:
		goal_label.visible = false
		return
	var optimal := _get_optimal_pours()
	if optimal == OPTIMAL_SOLVER_CALCULATING:
		goal_label.visible = true
		if _solver_progress_text != "":
			goal_label.text = tr("Goal: finding optimal %s | %s") % [GOAL_SPINNER_FRAMES[_goal_spinner_frame], _solver_progress_text]
		else:
			goal_label.text = tr("Goal: finding optimal %s") % GOAL_SPINNER_FRAMES[_goal_spinner_frame]
		return
	if optimal < 0:
		goal_label.visible = true
		goal_label.text = tr("Goal: exact solution not found")
		return
	var limit := _get_pour_limit()
	var score := _get_score()
	goal_label.visible = true
	goal_label.text = tr("Goal: %d | Limit: %d | Score: %s") % [optimal, limit, _format_score(score)]
	if _mulligans_used > 0:
		goal_label.text += tr(" | Undo: +%s") % _format_pours(_get_mulligan_pour_penalty())
	if _cheats_used > 0:
		goal_label.text += tr(" | Cheat: +%s") % _format_pours(_get_cheat_pour_penalty())

func _get_optimal_pours() -> int:
	var raw_goal = towers.get("optimal_pours")
	if raw_goal == null:
		return -1
	return int(raw_goal)

func _get_pour_limit() -> int:
	var optimal := _get_optimal_pours()
	if optimal < 0:
		return -1
	var grace := maxi(6, int(ceil(float(optimal) * 0.5)))
	return optimal + grace

func _get_score() -> int:
	if _score_forced_zero:
		return 0
	var optimal := _get_optimal_pours()
	if optimal < 0:
		return -1
	var limit := _get_pour_limit()
	var grace := maxi(1, limit - optimal)
	var extra := _get_extra_pours()
	var score_ratio := clampf(1.0 - extra / float(grace), 0.0, 1.0)
	var score := int(round(float(SCORE_MAX) * score_ratio * score_ratio))
	return maxi(0, score + _get_beaker_bonus_score())

func _get_beaker_bonus_score() -> int:
	if not towers or not towers.has_method("get_beaker_bonus_score"):
		return 0
	return maxi(0, int(towers.call("get_beaker_bonus_score")))

func _get_mulligan_pour_penalty() -> float:
	return float(_mulligans_used) * MULLIGAN_POUR_PENALTY

func _get_cheat_pour_penalty() -> float:
	return float(_cheats_used) * CHEAT_POUR_PENALTY

func _get_effective_pours() -> float:
	return float(moves) + _get_mulligan_pour_penalty() + _get_cheat_pour_penalty()

func _get_extra_pours() -> float:
	var optimal := _get_optimal_pours()
	if optimal < 0:
		return 0.0
	return maxf(0.0, _get_effective_pours() - float(optimal))

func _format_score(score: int) -> String:
	return "%.1f" % (float(score) / 10.0)

func _format_pours(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return "%.1f" % value

func _format_solver_count(value: int) -> String:
	var amount := maxi(0, value)
	if amount >= 1000000:
		return "%.1fm" % (float(amount) / 1000000.0)
	if amount >= 1000:
		return "%.1fk" % (float(amount) / 1000.0)
	return str(amount)

func _format_volume(value: float) -> String:
	return "%d%%" % int(round(clampf(value, 0.0, 1.0) * 100.0))

func _has_result_overlay() -> bool:
	for overlay_name in ["VictoryOverlay", "LoseOverlay"]:
		var overlay = get_node_or_null(overlay_name)
		if overlay and not overlay.is_queued_for_deletion():
			return true
	return false

func _update_music_pressure() -> void:
	if not AudioManager:
		return
	if _score_forced_zero or _has_result_overlay():
		return
	var limit := _get_pour_limit()
	if limit <= 0:
		if AudioManager.has_method("play_game_music"):
			AudioManager.call("play_game_music", 0.0)
		elif AudioManager.has_method("set_loop_pressure"):
			AudioManager.call("set_loop_pressure", 0.0)
		return
	var progress := clampf(_get_effective_pours() / float(limit), 0.0, 1.0)
	if AudioManager.has_method("play_game_music"):
		AudioManager.call("play_game_music", progress)
	elif AudioManager.has_method("set_loop_pressure"):
		AudioManager.call("set_loop_pressure", progress)

func _get_star_count(score: int) -> int:
	if score >= 900:
		return 5
	if score >= 750:
		return 4
	if score >= 550:
		return 3
	if score >= 300:
		return 2
	return 1

func _is_pour_limit_exceeded() -> bool:
	var limit := _get_pour_limit()
	return limit >= 0 and _get_effective_pours() > float(limit)

func _reset_stalemate_tracker():
	_state_visits.clear()
	_record_repeated_state(false)

func _record_repeated_state(can_lose: bool = true) -> bool:
	if not towers.has_method("get_board_signature"):
		return false
	if towers.check_complete():
		return false
	var signature := str(towers.call("get_board_signature"))
	var visits := int(_state_visits.get(signature, 0)) + 1
	_state_visits[signature] = visits
	return can_lose and visits >= REPEATED_STATE_LOSS_COUNT

func _show_victory_delayed():
	if AudioManager:
		AudioManager.play_win()
	await get_tree().create_timer(1.2).timeout
	if get_node_or_null("VictoryOverlay"):
		return
	show_victory_screen()

func show_victory_screen():
	if AudioManager and AudioManager.has_method("play_solved_music"):
		AudioManager.play_solved_music()
	_victory_stars_shown = false
	var cl := CanvasLayer.new()
	cl.name = "VictoryOverlay"
	cl.layer = 10
	add_child(cl)

	# Dimming background
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	cl.add_child(bg)

	# Card
	var card := ColorRect.new()
	card.name = "Card"
	card.color = Color(0.08, 0.10, 0.18, 0.97)
	card.custom_minimum_size = Vector2(660, 380)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left   = -330.0
	card.offset_top    = -190.0
	card.offset_right  =  330.0
	card.offset_bottom =  190.0
	card.pivot_offset  = Vector2(330, 190)
	card.scale         = Vector2(0.05, 0.05)
	cl.add_child(card)

	# Border strip at top of card
	var stripe := ColorRect.new()
	stripe.color = Color(1.0, 0.75, 0.1, 1.0)
	stripe.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stripe.offset_bottom = 6.0
	card.add_child(stripe)

	# Layout inside card
	var vb := VBoxContainer.new()
	vb.name = "Content"
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_top = 14.0
	vb.add_theme_constant_override("separation", 8)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vb)

	var solved_lbl := Label.new()
	solved_lbl.text = tr("🎉  SOLVED!  🎉")
	solved_lbl.add_theme_font_size_override("font_size", 66)
	solved_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.15))
	solved_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(solved_lbl)

	var count_lbl := Label.new()
	count_lbl.text = tr("Completed in %d %s") % [moves, tr(win_label)]
	count_lbl.add_theme_font_size_override("font_size", 28)
	count_lbl.add_theme_color_override("font_color", Color(0.82, 0.88, 1.0))
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(count_lbl)

	var score_lbl := Label.new()
	score_lbl.name = "ScoreLine"
	score_lbl.add_theme_font_size_override("font_size", 24)
	score_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(score_lbl)

	var star_row := HBoxContainer.new()
	star_row.name = "StarRow"
	star_row.alignment = BoxContainer.ALIGNMENT_CENTER
	star_row.custom_minimum_size = Vector2(0, 58)
	star_row.add_theme_constant_override("separation", 4)
	vb.add_child(star_row)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vb.add_child(spacer)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 18)
	vb.add_child(hb)

	_add_result_button(hb, tr("Retry"), 120.0, retry_game)
	_add_result_button(hb, tr("New Puzzle"), 150.0, reset_game)
	_add_result_button(hb, tr("View Board"), 150.0, _return_to_board_from_result)
	_add_result_button(hb, tr("Menu"), 120.0, go_to_menu)

	var fx_layer := Control.new()
	fx_layer.name = "StarFxLayer"
	fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(fx_layer)
	fx_layer.move_to_front()

	_refresh_victory_score()

	# Animate in
	var tw := create_tween().set_parallel()
	tw.tween_property(bg,   "color", Color(0, 0, 0, 0.72), 0.35)
	tw.tween_property(card, "scale", Vector2(1, 1),         0.50) \
	  .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _refresh_victory_score():
	var score_lbl: Label = get_node_or_null("VictoryOverlay/Card/Content/ScoreLine")
	if not score_lbl:
		return
	var score := _get_score()
	if score < 0:
		if _get_optimal_pours() == OPTIMAL_SOLVER_CALCULATING:
			score_lbl.text = tr("Score: finding optimal %s") % GOAL_SPINNER_FRAMES[_goal_spinner_frame]
		else:
			score_lbl.text = tr("Score: exact solution not found")
		return
	var optimal := _get_optimal_pours()
	var extra := _get_extra_pours()
	score_lbl.text = tr("Score: %s  |  Goal: %d  |  Extra: %s") % [_format_score(score), optimal, _format_pours(extra)]
	var bonus := _get_beaker_bonus_score()
	if bonus > 0:
		score_lbl.text += tr("  |  Bonus: +%s") % _format_score(bonus)
	if _mulligans_used > 0:
		score_lbl.text += tr("  |  Undo: +%s") % _format_pours(_get_mulligan_pour_penalty())
	if _cheats_used > 0:
		score_lbl.text += tr("  |  Cheat: +%s") % _format_pours(_get_cheat_pour_penalty())
	var star_row: HBoxContainer = get_node_or_null("VictoryOverlay/Card/Content/StarRow")
	if star_row and not _victory_stars_shown:
		_victory_stars_shown = true
		_populate_star_row(star_row, _get_star_count(score), true)

func _populate_star_row(row: HBoxContainer, stars: int, animate: bool):
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	for i in 5:
		var filled := i < stars
		var star := Label.new()
		star.text = STAR_FILLED if filled else STAR_EMPTY
		star.custom_minimum_size = Vector2(52, 58)
		star.pivot_offset = Vector2(26, 29)
		star.add_theme_font_size_override("font_size", 46)
		star.add_theme_color_override("font_color", Color(1.0, 0.78, 0.12) if filled else Color(0.38, 0.42, 0.52))
		star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(star)
		if animate:
			star.modulate = Color(1, 1, 1, 0)
			star.scale = Vector2(0.1, 0.1)
	if animate:
		Callable(self, "_animate_star_row").call_deferred(row, stars)

func _animate_star_row(row: HBoxContainer, stars: int) -> void:
	await get_tree().process_frame
	if not is_instance_valid(row):
		return
	var tw := create_tween().set_parallel()
	for i in row.get_child_count():
		var star := row.get_child(i) as Label
		if not star:
			continue
		var filled := i < stars
		if filled:
			var base_pos := star.position
			var landing_center := star.global_position + star.size * 0.5
			var direction := -1.0 if i % 2 == 0 else 1.0
			var start_offset := Vector2(randf_range(-220.0, 220.0), direction * randf_range(120.0, 190.0))
			var delay := 0.42 + float(i) * 0.13
			star.position = base_pos + start_offset
			star.scale = Vector2(0.12, 0.12)
			star.rotation = randf_range(-1.1, 1.1)
			star.modulate = Color(1, 1, 1, 0)
			tw.tween_property(star, "modulate", Color.WHITE, 0.07).set_delay(delay)
			tw.tween_property(star, "position", base_pos, 0.42).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(star, "scale", Vector2(1.85, 1.85), 0.20).set_delay(delay + 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(star, "scale", Vector2(1.0, 1.0), 0.18).set_delay(delay + 0.36).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_property(star, "rotation", 0.0, 0.36).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			_spawn_star_burst(landing_center, delay + 0.28)
			_schedule_star_boom(row, i, delay + 0.28)
		else:
			var delay := 0.42 + float(stars) * 0.13 + 0.18
			star.modulate = Color(1, 1, 1, 0)
			star.scale = Vector2(0.7, 0.7)
			tw.tween_property(star, "modulate", Color.WHITE, 0.20).set_delay(delay)
			tw.tween_property(star, "scale", Vector2(1.0, 1.0), 0.20).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _schedule_star_boom(row: HBoxContainer, star_index: int, delay: float) -> void:
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		if not is_instance_valid(row):
			return
		if AudioManager and AudioManager.has_method("play_star_boom"):
			AudioManager.play_star_boom(star_index)
	)

func _spawn_star_burst(global_center: Vector2, delay: float) -> void:
	var fx_layer := get_node_or_null("VictoryOverlay/Card/StarFxLayer") as Control
	if not fx_layer:
		return
	var local_center := fx_layer.get_global_transform().affine_inverse() * global_center
	_spawn_star_flash(fx_layer, local_center, delay)
	for n in 16:
		var spark := Label.new()
		spark.text = STAR_SPARK
		spark.custom_minimum_size = Vector2(18, 18)
		spark.pivot_offset = Vector2(9, 9)
		spark.position = local_center - Vector2(9, 9)
		spark.rotation = randf_range(-0.6, 0.6)
		spark.scale = Vector2(randf_range(0.65, 1.15), randf_range(0.65, 1.15))
		spark.modulate = Color(1, 1, 1, 0)
		spark.add_theme_font_size_override("font_size", int(randf_range(12.0, 22.0)))
		spark.add_theme_color_override("font_color", Color(1.0, randf_range(0.66, 0.95), randf_range(0.12, 0.36)))
		fx_layer.add_child(spark)
		var angle := TAU * float(n) / 16.0 + randf_range(-0.16, 0.16)
		var distance := randf_range(48.0, 118.0)
		var target := local_center + Vector2(cos(angle), sin(angle)) * distance - Vector2(9, 9)
		var spark_tw := create_tween().set_parallel()
		spark_tw.tween_property(spark, "modulate", Color.WHITE, 0.05).set_delay(delay)
		spark_tw.tween_property(spark, "modulate", Color(1, 1, 1, 0), 0.32).set_delay(delay + 0.10)
		spark_tw.tween_property(spark, "position", target, 0.42).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		spark_tw.tween_property(spark, "scale", Vector2(0.1, 0.1), 0.42).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		spark_tw.tween_property(spark, "rotation", randf_range(-4.0, 4.0), 0.42).set_delay(delay)
		spark_tw.chain().tween_callback(spark.queue_free)

func _spawn_star_flash(parent: Control, center: Vector2, delay: float) -> void:
	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.78, 0.12, 0.34)
	flash.size = Vector2(20, 20)
	flash.pivot_offset = Vector2(10, 10)
	flash.position = center - Vector2(10, 10)
	flash.scale = Vector2(0.1, 0.1)
	flash.modulate = Color(1, 1, 1, 0)
	parent.add_child(flash)
	var tw := create_tween().set_parallel()
	tw.tween_property(flash, "modulate", Color.WHITE, 0.04).set_delay(delay)
	tw.tween_property(flash, "modulate", Color(1, 1, 1, 0), 0.34).set_delay(delay + 0.06)
	tw.tween_property(flash, "scale", Vector2(8.5, 4.4), 0.40).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(flash.queue_free)

func _on_no_moves_available():
	_check_for_no_moves()

func _check_for_no_moves():
	if not towers.has_method("has_available_moves"):
		return
	if towers.check_complete() or bool(towers.call("has_available_moves")):
		return
	_show_loss(tr("NO MOVES LEFT"), tr("There are no legal pours remaining."), true)

func _show_loss(title: String, detail: String, allow_recovery_cheats: bool = false):
	if get_node_or_null("VictoryOverlay") or get_node_or_null("LoseOverlay"):
		return
	_recovery_cheats_available_for_loss = allow_recovery_cheats
	_last_recovery_loss_title = title if allow_recovery_cheats else ""
	_last_recovery_loss_detail = detail if allow_recovery_cheats else ""
	_score_forced_zero = true
	update_goal_label()
	update_possible_moves_label()
	if AudioManager:
		AudioManager.play_loss()
	if AudioManager and AudioManager.has_method("play_failed_music"):
		AudioManager.play_failed_music()
	show_loss_screen(title, detail)

func show_loss_screen(title: String, detail: String):
	var cl := CanvasLayer.new()
	cl.name = "LoseOverlay"
	cl.layer = 10
	add_child(cl)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	cl.add_child(bg)

	var card := ColorRect.new()
	card.color = Color(0.08, 0.10, 0.18, 0.97)
	card.custom_minimum_size = Vector2(680, 430)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left   = -340.0
	card.offset_top    = -215.0
	card.offset_right  =  340.0
	card.offset_bottom =  215.0
	card.pivot_offset  = Vector2(340, 215)
	card.scale         = Vector2(0.05, 0.05)
	cl.add_child(card)

	var stripe := ColorRect.new()
	stripe.color = Color(0.95, 0.22, 0.28, 1.0)
	stripe.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stripe.offset_bottom = 6.0
	card.add_child(stripe)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_top = 18.0
	vb.add_theme_constant_override("separation", 10)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vb)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 54)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.42, 0.48))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title_lbl)

	var detail_lbl := Label.new()
	detail_lbl.text = detail
	detail_lbl.add_theme_font_size_override("font_size", 24)
	detail_lbl.add_theme_color_override("font_color", Color(0.82, 0.88, 1.0))
	detail_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(detail_lbl)

	var optimal := _get_optimal_pours()
	if _score_forced_zero:
		var goal_lbl := Label.new()
		goal_lbl.text = tr("Score: %s") % _format_score(_get_score())
		if optimal >= 0:
			goal_lbl.text = tr("Goal: %d  |  Limit: %d  |  %s") % [optimal, _get_pour_limit(), goal_lbl.text]
		if _mulligans_used > 0:
			goal_lbl.text += tr("  |  Undo: +%s") % _format_pours(_get_mulligan_pour_penalty())
		if _cheats_used > 0:
			goal_lbl.text += tr("  |  Cheat: +%s") % _format_pours(_get_cheat_pour_penalty())
		goal_lbl.add_theme_font_size_override("font_size", 22)
		goal_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
		goal_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(goal_lbl)
	elif optimal >= 0:
		var goal_lbl := Label.new()
		goal_lbl.text = tr("Goal: %d  |  Limit: %d  |  Score: %s") % [optimal, _get_pour_limit(), _format_score(_get_score())]
		if _mulligans_used > 0:
			goal_lbl.text += tr("  |  Undo: +%s") % _format_pours(_get_mulligan_pour_penalty())
		if _cheats_used > 0:
			goal_lbl.text += tr("  |  Cheat: +%s") % _format_pours(_get_cheat_pour_penalty())
		goal_lbl.add_theme_font_size_override("font_size", 22)
		goal_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
		goal_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(goal_lbl)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vb.add_child(spacer)

	var hb := GridContainer.new()
	hb.columns = 3
	hb.add_theme_constant_override("h_separation", 16)
	hb.add_theme_constant_override("v_separation", 10)
	vb.add_child(hb)

	_add_result_button(hb, tr("Retry"), 110.0, retry_game)
	_add_result_button(hb, tr("New Puzzle"), 145.0, reset_game)

	if _can_use_mulligan():
		var mulligan_btn := Button.new()
		mulligan_btn.text = tr("Undo +%s") % _format_pours(MULLIGAN_POUR_PENALTY)
		mulligan_btn.add_theme_font_size_override("font_size", 22)
		mulligan_btn.custom_minimum_size = Vector2(155, 50)
		mulligan_btn.pressed.connect(use_mulligan)
		hb.add_child(mulligan_btn)

	if _can_use_recovery_cheat():
		if towers.has_method("has_usable_stir_cheat") and bool(towers.call("has_usable_stir_cheat")):
			var stir_btn := Button.new()
			stir_btn.text = tr("Stir +%s") % _format_pours(CHEAT_POUR_PENALTY)
			stir_btn.add_theme_font_size_override("font_size", 22)
			stir_btn.custom_minimum_size = Vector2(130, 50)
			stir_btn.pressed.connect(start_stir_cheat)
			hb.add_child(stir_btn)
		if towers.has_method("has_usable_swap_cheat") and bool(towers.call("has_usable_swap_cheat")):
			var swap_btn := Button.new()
			swap_btn.text = tr("Swap +%s") % _format_pours(CHEAT_POUR_PENALTY)
			swap_btn.add_theme_font_size_override("font_size", 22)
			swap_btn.custom_minimum_size = Vector2(135, 50)
			swap_btn.pressed.connect(start_swap_cheat)
			hb.add_child(swap_btn)

	_add_result_button(hb, tr("View Board"), 150.0, _return_to_board_from_result)
	_add_result_button(hb, tr("Menu"), 120.0, go_to_menu)

	var tw := create_tween().set_parallel()
	tw.tween_property(bg,   "color", Color(0, 0, 0, 0.72), 0.35)
	tw.tween_property(card, "scale", Vector2(1, 1),         0.50) \
	  .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _add_result_button(parent: Control, text: String, min_width: float, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 22)
	button.custom_minimum_size = Vector2(min_width, 50)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _return_to_board_from_result() -> void:
	_clear_result_overlays()
	if AudioManager:
		AudioManager.play_click()

func _on_disk_count_changed(value: float):
	if not disk_count_slider:
		return
	var count := int(value)
	if count == GameSettings.hanoi_disk_count:
		return
	GameSettings.set_hanoi_disk_count(count)
	if disk_count_value:
		disk_count_value.text = str(GameSettings.hanoi_disk_count)
	if _settings_ready:
		if AudioManager:
			AudioManager.play_select()
		reset_game(false)

func _on_depth_changed(value: float):
	if not depth_slider:
		return
	var capacity := int(value)
	if capacity == GameSettings.beaker_capacity:
		return
	GameSettings.set_beaker_capacity(capacity)
	if depth_value:
		depth_value.text = str(GameSettings.beaker_capacity)
	if _settings_ready:
		if AudioManager:
			AudioManager.play_select()
		reset_game(false)

func _on_show_goal_toggled(button_pressed: bool):
	GameSettings.set_show_goal_hint(button_pressed)
	if _settings_ready and AudioManager:
		AudioManager.play_select()
	update_goal_label()

func _on_special_beakers_toggled(button_pressed: bool) -> void:
	if button_pressed == GameSettings.special_beakers_enabled:
		return
	GameSettings.set_special_beakers_enabled(button_pressed)
	if _settings_ready:
		if AudioManager:
			AudioManager.play_select()
		reset_game(false)

func _on_palette_selected(index: int) -> void:
	if not palette_option:
		return
	var key := str(palette_option.get_item_metadata(index))
	GameSettings.set_liquid_palette(key)
	if _settings_ready and AudioManager:
		AudioManager.play_select()
	if towers and towers.has_method("queue_redraw"):
		towers.queue_redraw()

func _on_liquid_alpha_changed(value: float):
	GameSettings.set_liquid_alpha(value)
	if liquid_alpha_value:
		liquid_alpha_value.text = _format_volume(GameSettings.liquid_alpha)
	if towers and towers.has_method("queue_redraw"):
		towers.queue_redraw()

func _on_liquid_symbols_toggled(button_pressed: bool) -> void:
	GameSettings.set_show_liquid_symbols(button_pressed)
	if _settings_ready and AudioManager:
		AudioManager.play_select()
	if towers and towers.has_method("queue_redraw"):
		towers.queue_redraw()

func _on_copy_board_code_pressed() -> void:
	_copy_current_board_code(board_code_status, "Copied")

func _copy_current_board_code(status_label: Label = null, copied_text: String = "Copied") -> bool:
	if not towers or not towers.has_method("export_board_code"):
		return false
	var code := str(towers.call("export_board_code"))
	if board_code_input:
		board_code_input.text = code
	DisplayServer.clipboard_set(code)
	if status_label:
		status_label.text = tr(copied_text)
	if AudioManager:
		AudioManager.play_select()
	return true

func _on_load_board_code_pressed() -> void:
	if not towers or not towers.has_method("import_board_code"):
		return
	var code := board_code_input.text.strip_edges() if board_code_input else ""
	if code == "":
		code = DisplayServer.clipboard_get().strip_edges()
	var loaded := bool(towers.call("import_board_code", code))
	if not loaded:
		if board_code_status:
			board_code_status.text = tr("Invalid board code")
		if AudioManager:
			AudioManager.play_invalid()
		return
	_clear_result_overlays()
	_score_forced_zero = false
	_recovery_cheats_available_for_loss = false
	_last_recovery_loss_title = ""
	_last_recovery_loss_detail = ""
	_mulligans_used = 0
	_cheats_used = 0
	moves = 0
	update_move_counter()
	update_possible_moves_label()
	update_goal_label()
	_setup_settings_ui()
	_reset_stalemate_tracker()
	_update_mulligan_button()
	_update_music_pressure()
	if board_code_input:
		board_code_input.text = str(towers.call("export_board_code"))
	if board_code_status:
		board_code_status.text = tr("Loaded")
	if AudioManager:
		AudioManager.play_select()
	_check_for_no_moves.call_deferred()

func _on_music_volume_changed(value: float):
	GameSettings.set_music_volume(value)
	if music_value:
		music_value.text = _format_volume(GameSettings.music_volume)

func _on_effects_volume_changed(value: float):
	GameSettings.set_effects_volume(value)
	if effects_value:
		effects_value.text = _format_volume(GameSettings.effects_volume)
	if _settings_ready and AudioManager:
		AudioManager.play_select()

func _on_difficulty_easy_pressed():
	_set_difficulty("easy")

func _on_difficulty_normal_pressed():
	_set_difficulty("normal")

func _on_difficulty_hard_pressed():
	_set_difficulty("hard")

func _set_difficulty(value: String):
	if value == GameSettings.difficulty:
		_sync_difficulty_buttons()
		return
	GameSettings.set_difficulty(value)
	_sync_difficulty_buttons()
	if _settings_ready:
		if AudioManager:
			AudioManager.play_select()
		reset_game(false)

func _sync_difficulty_buttons():
	for key in difficulty_buttons:
		var button = difficulty_buttons[key]
		if button:
			button.button_pressed = key == GameSettings.difficulty

func _sync_palette_option() -> void:
	if not palette_option:
		return
	palette_option.clear()
	var selected_idx := 0
	for key in GameSettings.LIQUID_PALETTE_ORDER:
		var idx := palette_option.get_item_count()
		palette_option.add_item(GameSettings.get_liquid_palette_label(key))
		palette_option.set_item_metadata(idx, key)
		if key == GameSettings.liquid_palette:
			selected_idx = idx
	palette_option.select(selected_idx)

func _can_use_recovery_cheat() -> bool:
	if _cheats_used >= CHEAT_MAX_USES:
		return false
	if not towers or towers.check_complete():
		return false
	if not _recovery_cheats_available_for_loss:
		return false
	if towers.has_method("is_choosing_cheat") and bool(towers.call("is_choosing_cheat")):
		return false
	var can_stir := towers.has_method("has_usable_stir_cheat") and bool(towers.call("has_usable_stir_cheat"))
	var can_swap := towers.has_method("has_usable_swap_cheat") and bool(towers.call("has_usable_swap_cheat"))
	return can_stir or can_swap

func start_stir_cheat() -> void:
	_start_recovery_cheat("stir")

func start_swap_cheat() -> void:
	_start_recovery_cheat("swap")

func _start_recovery_cheat(cheat_type: String) -> void:
	if not _can_use_recovery_cheat():
		return
	var started := false
	if cheat_type == "stir" and towers.has_method("begin_stir_cheat"):
		started = bool(towers.call("begin_stir_cheat"))
	elif cheat_type == "swap" and towers.has_method("begin_swap_cheat"):
		started = bool(towers.call("begin_swap_cheat"))
	if not started:
		if AudioManager:
			AudioManager.play_invalid()
		return
	_clear_result_overlays()
	_set_cheat_status(cheat_type)
	_update_mulligan_button()
	if AudioManager:
		AudioManager.play_select()

func _set_cheat_status(cheat_type: String) -> void:
	if not instructions_label:
		return
	if cheat_type == "stir":
		instructions_label.text = tr("Recovery: choose one mixed beaker to stir.")
	elif cheat_type == "swap":
		instructions_label.text = tr("Recovery: choose two adjacent segments to swap.")

func _restore_instruction_label() -> void:
	if instructions_label and _default_instructions_text != "":
		instructions_label.text = tr(_default_instructions_text)

func _on_cheat_applied(_cheat_type: String) -> void:
	_cheats_used += 1
	_score_forced_zero = false
	_recovery_cheats_available_for_loss = false
	_last_recovery_loss_title = ""
	_last_recovery_loss_detail = ""
	_clear_result_overlays()
	_restore_instruction_label()
	update_move_counter()
	update_possible_moves_label()
	update_goal_label()
	_reset_stalemate_tracker()
	_update_mulligan_button()
	_update_music_pressure()
	if towers.check_complete():
		_show_victory_delayed()
	else:
		_check_for_no_moves.call_deferred()

func _on_cheat_cancelled() -> void:
	_restore_instruction_label()
	_update_mulligan_button()
	if _recovery_cheats_available_for_loss and _last_recovery_loss_title != "":
		show_loss_screen(_last_recovery_loss_title, _last_recovery_loss_detail)
		return
	_check_for_no_moves.call_deferred()

func _can_use_mulligan() -> bool:
	return (_mulligans_used < MULLIGAN_MAX_USES
			and not towers.check_complete()
			and not (towers.has_method("is_choosing_cheat") and bool(towers.call("is_choosing_cheat")))
			and towers.has_method("can_undo_last_pour")
			and bool(towers.call("can_undo_last_pour")))

func _update_mulligan_button():
	if not mulligan_button:
		return
	mulligan_button.text = tr("Undo +%s") % _format_pours(MULLIGAN_POUR_PENALTY)
	mulligan_button.disabled = not _can_use_mulligan()

func use_mulligan():
	if not _can_use_mulligan():
		return
	if not bool(towers.call("undo_last_pour")):
		return
	if AudioManager:
		AudioManager.play_select()
	_mulligans_used += 1
	_score_forced_zero = false
	_recovery_cheats_available_for_loss = false
	_last_recovery_loss_title = ""
	_last_recovery_loss_detail = ""
	_clear_result_overlays()
	moves = maxi(0, moves - 1)
	update_move_counter()
	update_possible_moves_label()
	update_goal_label()
	_reset_stalemate_tracker()
	_update_mulligan_button()
	_update_music_pressure()
	_check_for_no_moves.call_deferred()

func retry_game(play_sound: bool = true):
	if play_sound and AudioManager:
		AudioManager.play_click()
	if towers.has_method("cancel_cheat"):
		towers.call("cancel_cheat", false)
	_restore_instruction_label()
	_clear_result_overlays()
	_score_forced_zero = false
	_recovery_cheats_available_for_loss = false
	_last_recovery_loss_title = ""
	_last_recovery_loss_detail = ""
	_mulligans_used = 0
	_cheats_used = 0
	moves = 0
	update_move_counter()
	if towers.has_method("retry_current_puzzle") and bool(towers.call("retry_current_puzzle")):
		update_possible_moves_label()
		update_goal_label()
	else:
		towers.reset()
		update_possible_moves_label()
		update_goal_label()
	_reset_stalemate_tracker()
	_update_mulligan_button()
	_update_music_pressure()
	_check_for_no_moves.call_deferred()

func reset_game(play_sound: bool = true):
	if play_sound and AudioManager:
		AudioManager.play_click()
	if towers.has_method("cancel_cheat"):
		towers.call("cancel_cheat", false)
	_restore_instruction_label()
	_clear_result_overlays()
	_score_forced_zero = false
	_recovery_cheats_available_for_loss = false
	_last_recovery_loss_title = ""
	_last_recovery_loss_detail = ""
	_mulligans_used = 0
	_cheats_used = 0
	moves = 0
	update_move_counter()
	towers.reset()
	update_possible_moves_label()
	update_goal_label()
	_reset_stalemate_tracker()
	_update_mulligan_button()
	_update_music_pressure()
	_check_for_no_moves.call_deferred()

func _clear_result_overlays():
	for overlay_name in ["VictoryOverlay", "LoseOverlay"]:
		var overlay = get_node_or_null(overlay_name)
		if overlay:
			overlay.queue_free()

func go_to_menu():
	if AudioManager:
		AudioManager.play_click()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
