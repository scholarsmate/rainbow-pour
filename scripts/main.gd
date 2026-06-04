extends Node2D

const SCORE_MAX := 1000
const REPEATED_STATE_LOSS_COUNT := 3
const MULLIGAN_POUR_PENALTY := 0.5
const MULLIGAN_MAX_USES := 1
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

var settings_overlay: Control
var depth_slider: HSlider
var depth_value: Label
var goal_toggle: CheckButton
var music_slider: HSlider
var music_value: Label
var effects_slider: HSlider
var effects_value: Label
var difficulty_buttons := {}

var moves = 0
var _settings_ready := false
var _state_visits := {}
var _mulligans_used := 0
var _goal_spinner_time := 0.0
var _goal_spinner_frame := 0
var _victory_stars_shown := false
var _score_forced_zero := false

func _ready():
	towers.disk_moved.connect(_on_disk_moved)
	if towers.has_signal("goal_changed"):
		towers.connect("goal_changed", Callable(self, "_on_goal_changed"))
	if towers.has_signal("no_moves_available"):
		towers.connect("no_moves_available", Callable(self, "_on_no_moves_available"))
	_build_settings_dialog()
	update_move_counter()
	update_possible_moves_label()
	update_goal_label()
	_setup_settings_ui()
	_reset_stalemate_tracker()
	_update_mulligan_button()
	_check_for_no_moves.call_deferred()

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
	card.custom_minimum_size = Vector2(580, 520)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -290.0
	card.offset_top = -260.0
	card.offset_right = 290.0
	card.offset_bottom = 260.0
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
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(92, 38)
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.pressed.connect(_close_settings_dialog)
	header.add_child(close_btn)

	if _has_water_sort_settings():
		_add_section_label(content, "Puzzle")
		var capacity_controls := _add_labeled_slider_row(content, "Slots")
		depth_slider = capacity_controls["slider"] as HSlider
		depth_value = capacity_controls["value"] as Label
		depth_slider.min_value = GameSettings.CAPACITY_MIN
		depth_slider.max_value = GameSettings.CAPACITY_MAX
		depth_slider.step = 1.0
		depth_slider.value_changed.connect(_on_depth_changed)
		_add_difficulty_row(content)

		goal_toggle = CheckButton.new()
		goal_toggle.text = "Show optimal goal"
		goal_toggle.add_theme_font_size_override("font_size", 18)
		goal_toggle.toggled.connect(_on_show_goal_toggled)
		content.add_child(goal_toggle)

	_add_section_label(content, "Audio")
	var music_controls := _add_labeled_slider_row(content, "Music")
	music_slider = music_controls["slider"] as HSlider
	music_value = music_controls["value"] as Label
	music_slider.min_value = 0.0
	music_slider.max_value = 1.0
	music_slider.step = 0.01
	music_slider.value_changed.connect(_on_music_volume_changed)

	var effects_controls := _add_labeled_slider_row(content, "Effects")
	effects_slider = effects_controls["slider"] as HSlider
	effects_value = effects_controls["value"] as Label
	effects_slider.min_value = 0.0
	effects_slider.max_value = 1.0
	effects_slider.step = 0.01
	effects_slider.value_changed.connect(_on_effects_volume_changed)

func _has_water_sort_settings() -> bool:
	return towers.has_signal("goal_changed") and towers.has_method("retry_current_puzzle")

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

func _add_difficulty_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label := Label.new()
	label.text = "Difficulty"
	label.custom_minimum_size = Vector2(110, 34)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.98))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	for key in ["easy", "normal", "hard"]:
		var button := Button.new()
		button.text = GameSettings.DIFFICULTIES[key]["label"]
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

func _setup_settings_ui():
	if depth_slider:
		depth_slider.min_value = GameSettings.CAPACITY_MIN
		depth_slider.max_value = GameSettings.CAPACITY_MAX
		depth_slider.value = GameSettings.beaker_capacity
		if depth_value:
			depth_value.text = str(GameSettings.beaker_capacity)
	if goal_toggle:
		goal_toggle.button_pressed = GameSettings.show_goal_hint
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
	_update_mulligan_button()
	if towers.check_complete():
		_show_victory_delayed()
	elif _is_pour_limit_exceeded():
		var limit := _get_pour_limit()
		_show_loss("POUR LIMIT REACHED", "You crossed the %d-%s limit." % [limit, win_label])
	elif _record_repeated_state():
		_show_loss("STUCK IN A LOOP", "This board state repeated %d times." % REPEATED_STATE_LOSS_COUNT)

func update_move_counter():
	move_counter.text = "%s: %d" % [move_label, moves]

func update_possible_moves_label():
	if not possible_moves_label:
		return
	if not towers.has_method("count_available_moves"):
		possible_moves_label.visible = false
		return
	possible_moves_label.visible = true
	var count := int(towers.call("count_available_moves"))
	possible_moves_label.text = "Possible moves: %d" % count

func _on_goal_changed(_optimal_pours: int):
	update_goal_label()
	_refresh_victory_score()

func update_goal_label():
	if not goal_label:
		return
	if not GameSettings.show_goal_hint:
		goal_label.visible = false
		return
	var optimal := _get_optimal_pours()
	if optimal == OPTIMAL_SOLVER_CALCULATING:
		goal_label.visible = true
		goal_label.text = "Goal: finding optimal %s" % GOAL_SPINNER_FRAMES[_goal_spinner_frame]
		return
	if optimal < 0:
		goal_label.visible = true
		goal_label.text = "Goal: exact solution not found"
		return
	var limit := _get_pour_limit()
	var score := _get_score()
	goal_label.visible = true
	goal_label.text = "Goal: %d | Limit: %d | Score: %s" % [optimal, limit, _format_score(score)]
	if _mulligans_used > 0:
		goal_label.text += " | Undo: +%s" % _format_pours(_get_mulligan_pour_penalty())

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
	return maxi(0, score)

func _get_mulligan_pour_penalty() -> float:
	return float(_mulligans_used) * MULLIGAN_POUR_PENALTY

func _get_effective_pours() -> float:
	return float(moves) + _get_mulligan_pour_penalty()

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

func _format_volume(value: float) -> String:
	return "%d%%" % int(round(clampf(value, 0.0, 1.0) * 100.0))

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
	return limit >= 0 and moves > limit

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
	solved_lbl.text = "🎉  SOLVED!  🎉"
	solved_lbl.add_theme_font_size_override("font_size", 66)
	solved_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.15))
	solved_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(solved_lbl)

	var count_lbl := Label.new()
	count_lbl.text = "Completed in %d %s" % [moves, win_label]
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

	var retry_btn := Button.new()
	retry_btn.text = "Retry"
	retry_btn.add_theme_font_size_override("font_size", 22)
	retry_btn.custom_minimum_size = Vector2(120, 50)
	retry_btn.pressed.connect(retry_game)
	hb.add_child(retry_btn)

	var new_btn := Button.new()
	new_btn.text = "New Puzzle"
	new_btn.add_theme_font_size_override("font_size", 22)
	new_btn.custom_minimum_size = Vector2(150, 50)
	new_btn.pressed.connect(reset_game)
	hb.add_child(new_btn)

	var menu_btn := Button.new()
	menu_btn.text = "Menu"
	menu_btn.add_theme_font_size_override("font_size", 22)
	menu_btn.custom_minimum_size = Vector2(120, 50)
	menu_btn.pressed.connect(go_to_menu)
	hb.add_child(menu_btn)

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
			score_lbl.text = "Score: finding optimal %s" % GOAL_SPINNER_FRAMES[_goal_spinner_frame]
		else:
			score_lbl.text = "Score: exact solution not found"
		return
	var optimal := _get_optimal_pours()
	var extra := _get_extra_pours()
	score_lbl.text = "Score: %s  |  Goal: %d  |  Extra: %s" % [_format_score(score), optimal, _format_pours(extra)]
	if _mulligans_used > 0:
		score_lbl.text += "  |  Undo: +%s" % _format_pours(_get_mulligan_pour_penalty())
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
	_show_loss("NO MOVES LEFT", "There are no legal pours remaining.")

func _show_loss(title: String, detail: String):
	if get_node_or_null("VictoryOverlay") or get_node_or_null("LoseOverlay"):
		return
	_score_forced_zero = true
	update_goal_label()
	update_possible_moves_label()
	if AudioManager:
		AudioManager.play_loss()
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
	card.custom_minimum_size = Vector2(620, 320)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left   = -310.0
	card.offset_top    = -160.0
	card.offset_right  =  310.0
	card.offset_bottom =  160.0
	card.pivot_offset  = Vector2(310, 160)
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
		goal_lbl.text = "Score: %s" % _format_score(_get_score())
		if optimal >= 0:
			goal_lbl.text = "Goal: %d  |  Limit: %d  |  %s" % [optimal, _get_pour_limit(), goal_lbl.text]
		if _mulligans_used > 0:
			goal_lbl.text += "  |  Undo: +%s" % _format_pours(_get_mulligan_pour_penalty())
		goal_lbl.add_theme_font_size_override("font_size", 22)
		goal_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
		goal_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(goal_lbl)
	elif optimal >= 0:
		var goal_lbl := Label.new()
		goal_lbl.text = "Goal: %d  |  Limit: %d  |  Score: %s" % [optimal, _get_pour_limit(), _format_score(_get_score())]
		if _mulligans_used > 0:
			goal_lbl.text += "  |  Undo: +%s" % _format_pours(_get_mulligan_pour_penalty())
		goal_lbl.add_theme_font_size_override("font_size", 22)
		goal_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
		goal_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(goal_lbl)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vb.add_child(spacer)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 16)
	vb.add_child(hb)

	var retry_btn := Button.new()
	retry_btn.text = "Retry"
	retry_btn.add_theme_font_size_override("font_size", 22)
	retry_btn.custom_minimum_size = Vector2(110, 50)
	retry_btn.pressed.connect(retry_game)
	hb.add_child(retry_btn)

	var new_btn := Button.new()
	new_btn.text = "New Puzzle"
	new_btn.add_theme_font_size_override("font_size", 22)
	new_btn.custom_minimum_size = Vector2(145, 50)
	new_btn.pressed.connect(reset_game)
	hb.add_child(new_btn)

	if _can_use_mulligan():
		var mulligan_btn := Button.new()
		mulligan_btn.text = "Undo +%s" % _format_pours(MULLIGAN_POUR_PENALTY)
		mulligan_btn.add_theme_font_size_override("font_size", 22)
		mulligan_btn.custom_minimum_size = Vector2(155, 50)
		mulligan_btn.pressed.connect(use_mulligan)
		hb.add_child(mulligan_btn)

	var menu_btn := Button.new()
	menu_btn.text = "Menu"
	menu_btn.add_theme_font_size_override("font_size", 22)
	menu_btn.custom_minimum_size = Vector2(120, 50)
	menu_btn.pressed.connect(go_to_menu)
	hb.add_child(menu_btn)

	var tw := create_tween().set_parallel()
	tw.tween_property(bg,   "color", Color(0, 0, 0, 0.72), 0.35)
	tw.tween_property(card, "scale", Vector2(1, 1),         0.50) \
	  .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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

func _can_use_mulligan() -> bool:
	return (_mulligans_used < MULLIGAN_MAX_USES
			and not towers.check_complete()
			and towers.has_method("can_undo_last_pour")
			and bool(towers.call("can_undo_last_pour")))

func _update_mulligan_button():
	if not mulligan_button:
		return
	mulligan_button.text = "Undo +%s" % _format_pours(MULLIGAN_POUR_PENALTY)
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
	_clear_result_overlays()
	moves = maxi(0, moves - 1)
	update_move_counter()
	update_possible_moves_label()
	update_goal_label()
	_reset_stalemate_tracker()
	_update_mulligan_button()
	_check_for_no_moves.call_deferred()

func retry_game(play_sound: bool = true):
	if play_sound and AudioManager:
		AudioManager.play_click()
	_clear_result_overlays()
	_score_forced_zero = false
	_mulligans_used = 0
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
	_check_for_no_moves.call_deferred()

func reset_game(play_sound: bool = true):
	if play_sound and AudioManager:
		AudioManager.play_click()
	_clear_result_overlays()
	_score_forced_zero = false
	_mulligans_used = 0
	moves = 0
	update_move_counter()
	towers.reset()
	update_possible_moves_label()
	update_goal_label()
	_reset_stalemate_tracker()
	_update_mulligan_button()
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
