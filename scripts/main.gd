extends Node2D

const PrismaticButtonFrame := preload("res://scripts/prismatic_button_frame.gd")

const SCORE_MAX := 1000
const REPEATED_STATE_LOSS_COUNT := 2
const MULLIGAN_POUR_PENALTY := 0.5
const MULLIGAN_MAX_USES := 4
const STIR_CHEAT_POUR_PENALTY := 2.0
const SWAP_CHEAT_POUR_PENALTY := 3.0
const PIPETTE_CHEAT_POUR_PENALTY := 4.0
const CHEAT_MAX_USES := 1
const EXTRA_BEAKER_PENALTY_RATIO := 0.35
const EXTRA_BEAKER_MIN_PENALTY := 4.0
const OPTIMAL_SOLVER_CALCULATING := -2
const STAR_FILLED_KEY := "UI Symbol Star Filled"
const STAR_EMPTY_KEY := "UI Symbol Star Empty"
const STAR_SPARK_KEY := "UI Symbol Star Spark"
const STAR_GOLD_COLOR := Color(1.0, 0.78, 0.12)
const STAR_GOLD_IDLE_COLOR := Color(1.0, 0.93, 0.36)
const STAR_PLATINUM_COLOR := Color(0.86, 0.94, 1.0)
const STAR_PLATINUM_IDLE_COLOR := Color(0.66, 0.92, 1.0)
const STAR_EMPTY_COLOR := Color(0.38, 0.42, 0.52)
const SOLVED_TITLE_KEY := "Solved Result Title"
const SHATTERED_TITLE_KEY := "Shattered Beaker Title"
const UI_MARGIN := 20.0
const UI_BUTTON_HEIGHT := 40.0
const UI_BUTTON_GAP := 12.0
const PORTRAIT_ASPECT_THRESHOLD := 1.08
const PORTRAIT_REFERENCE_WIDTH := 460.0
const MOBILE_UI_SCALE_MIN := 1.55
const PORTRAIT_TRAIT_CHIP_GUTTER := 36.0
const CHEATS_ATTENTION_FRAME_NAME := "CheatsAttentionFrame"

@export var move_label: String = "Moves"
@export var win_label: String = "moves"

@onready var towers = $Towers
@onready var move_counter = $UI/MoveCounter
@onready var goal_label = get_node_or_null("UI/GoalLabel")
@onready var possible_moves_label = get_node_or_null("UI/PossibleMovesLabel")
@onready var mulligan_button = get_node_or_null("UI/MulliganButton")
@onready var extra_beaker_button = get_node_or_null("UI/ExtraBeakerButton")
@onready var settings_button = get_node_or_null("UI/SettingsButton")
@onready var new_puzzle_button = get_node_or_null("UI/NewPuzzleButton")
@onready var retry_button = get_node_or_null("UI/RetryButton")
@onready var menu_button = get_node_or_null("UI/MenuButton")
@onready var instructions_label: Label = get_node_or_null("UI/Instructions")

var settings_overlay: Control
var cheats_button: Button
var cheats_overlay: Control
var disk_count_slider: HSlider
var disk_count_value: Label
var depth_slider: HSlider
var depth_value: Label
var filled_beakers_slider: HSlider
var filled_beakers_value: Label
var empty_beakers_slider: HSlider
var empty_beakers_value: Label
var chill_mode_toggle: CheckButton
var goal_toggle: CheckButton
var special_beakers_toggle: CheckButton
var palette_option: OptionButton
var symbol_set_option: OptionButton
var liquid_symbols_toggle: CheckButton
var liquid_alpha_slider: HSlider
var liquid_alpha_value: Label
var board_code_input: LineEdit
var board_code_status: Label
var music_slider: HSlider
var music_value: Label
var effects_slider: HSlider
var effects_value: Label
var adventure_rank_label: Label
var adventure_puzzle_label: Label
var difficulty_buttons := {}
var palette_buttons := {}
var symbol_set_buttons := {}
var mulligan_badge: Label
var adventure_dialog_overlay: CanvasLayer

var moves = 0
var _settings_ready := false
var _syncing_settings_ui := false
var _state_visits := {}
var _mulligans_used := 0
var _cheats_used := 0
var _cheat_use_counts := {}
var _recovery_cheat_pour_penalty := 0.0
var _recovery_cheat_kind := ""
var _solver_progress_text := ""
var _victory_stars_shown := false
var _score_forced_zero := false
var _default_instructions_text := ""
var _recovery_cheats_available_for_loss := false
var _last_recovery_loss_title := ""
var _last_recovery_loss_detail := ""
var _shatter_loss_locked := false
var _shatter_loss_generation := 0
var _ui_text_font: Font
var _cheats_attention_frame: Control
var _cheats_attention_active := false
var _adventure_completion_recorded := false
var _adventure_outro_shown := false

func _ready():
	towers.disk_moved.connect(_on_disk_moved)
	if towers.has_signal("goal_changed"):
		towers.connect("goal_changed", Callable(self, "_on_goal_changed"))
	if towers.has_signal("solver_progress"):
		towers.connect("solver_progress", Callable(self, "_on_solver_progress"))
	if towers.has_signal("no_moves_available"):
		towers.connect("no_moves_available", Callable(self, "_on_no_moves_available"))
	if towers.has_signal("cracked_beaker_shattered"):
		towers.connect("cracked_beaker_shattered", Callable(self, "_on_cracked_beaker_shattered"))
	if towers.has_signal("cheat_applied"):
		towers.connect("cheat_applied", Callable(self, "_on_cheat_applied"))
	if towers.has_signal("cheat_cancelled"):
		towers.connect("cheat_cancelled", Callable(self, "_on_cheat_cancelled"))
	if instructions_label:
		_default_instructions_text = instructions_label.text
	_build_settings_dialog()
	_build_cheats_dialog()
	_build_adventure_position_labels()
	_build_mulligan_badge()
	get_viewport().size_changed.connect(_update_responsive_layout)
	_update_responsive_layout()
	var loaded_pending_board := _load_pending_board_code_if_any()
	_apply_adventure_context(loaded_pending_board)
	update_move_counter()
	update_possible_moves_label()
	update_goal_label()
	_update_music_pressure()
	_setup_settings_ui()
	_reset_stalemate_tracker()
	_update_mulligan_button()
	_check_for_no_moves.call_deferred()

func _build_mulligan_badge() -> void:
	if not mulligan_button:
		return
	mulligan_badge = _create_mulligan_badge()
	mulligan_button.add_child(mulligan_badge)

func _build_adventure_position_labels() -> void:
	var ui := get_node_or_null("UI")
	if not ui:
		return
	adventure_rank_label = _make_adventure_position_label("AdventureRankLabel")
	adventure_puzzle_label = _make_adventure_position_label("AdventurePuzzleLabel")
	ui.add_child(adventure_rank_label)
	ui.add_child(adventure_puzzle_label)
	_sync_adventure_position_labels()

func _make_adventure_position_label(label_name: String) -> Label:
	var label := Label.new()
	label.name = label_name
	label.visible = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_color_override("font_color", Color(0.76, 0.93, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.62))
	label.add_theme_constant_override("outline_size", 1)
	return label

func _create_mulligan_badge() -> Label:
	var badge := Label.new()
	badge.name = "RemainingBadge"
	badge.custom_minimum_size = Vector2(36, 32)
	badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -35.0
	badge.offset_top = -14.0
	badge.offset_right = 1.0
	badge.offset_bottom = 18.0
	badge.add_theme_font_size_override("font_size", 18)
	badge.add_theme_color_override("font_color", Color(0.05, 0.07, 0.10))
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.z_index = 4
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1.0, 0.86, 0.35, 0.96)
	bg.border_color = Color(0.04, 0.05, 0.08, 0.92)
	bg.set_border_width_all(2)
	bg.corner_radius_top_left = 12
	bg.corner_radius_top_right = 12
	bg.corner_radius_bottom_left = 12
	bg.corner_radius_bottom_right = 12
	badge.add_theme_stylebox_override("normal", bg)
	return badge

func _load_pending_board_code_if_any() -> bool:
	if not GameSettings.has_method("consume_pending_board_code"):
		return false
	var code := str(GameSettings.call("consume_pending_board_code")).strip_edges()
	if code == "":
		return false
	var forced_goal := _get_adventure_precomputed_optimal_pours()
	if towers.has_method("import_board_code") and bool(towers.call("import_board_code", code, forced_goal)):
		return true
	push_warning("Pending board code failed to load.")
	return false

func _apply_adventure_context(loaded_adventure_board: bool) -> void:
	_adventure_completion_recorded = false
	_adventure_outro_shown = false
	if not _is_adventure_active():
		_sync_adventure_position_labels()
		return
	if not loaded_adventure_board:
		_load_current_adventure_puzzle(false)
		return
	_sync_adventure_position_labels()
	_update_adventure_instruction_label()
	call_deferred("_show_current_adventure_intro")

func _is_adventure_active() -> bool:
	return AdventureManager != null and AdventureManager.is_playing_adventure()

func _load_current_adventure_puzzle(show_intro: bool = true) -> bool:
	if not _is_adventure_active():
		return false
	var board_code := AdventureManager.get_current_board_code()
	if board_code == "" or not towers.has_method("import_board_code"):
		return false
	if not bool(towers.call("import_board_code", board_code, _get_adventure_precomputed_optimal_pours())):
		push_warning("Adventure board code failed to load.")
		return false
	_adventure_completion_recorded = false
	_adventure_outro_shown = false
	_sync_adventure_position_labels()
	_update_adventure_instruction_label()
	if show_intro:
		call_deferred("_show_current_adventure_intro")
	return true

func _update_adventure_instruction_label() -> void:
	if not instructions_label or not _is_adventure_active():
		return
	var title := AdventureManager.get_current_title()
	if title == "":
		_restore_instruction_label()
		return
	instructions_label.text = title

func _show_current_adventure_intro() -> void:
	if not _is_adventure_active():
		return
	var lines := AdventureManager.get_current_dialog("intro")
	if lines.is_empty():
		return
	_show_adventure_dialog(lines, AdventureManager.get_current_title(), Callable())

func _show_current_adventure_outro_or_victory() -> void:
	if not _is_adventure_active() or _adventure_outro_shown:
		show_victory_screen()
		return
	var lines := AdventureManager.get_current_dialog("outro")
	if lines.is_empty():
		show_victory_screen()
		return
	_adventure_outro_shown = true
	_show_adventure_dialog(lines, AdventureManager.get_current_title(), Callable(self, "show_victory_screen"))

func _show_adventure_dialog(lines: Array, title: String, after_close: Callable) -> void:
	if lines.is_empty():
		if after_close.is_valid():
			after_close.call()
		return
	_clear_adventure_dialog_overlay()
	adventure_dialog_overlay = CanvasLayer.new()
	adventure_dialog_overlay.name = "AdventureDialogOverlay"
	adventure_dialog_overlay.layer = 11
	add_child(adventure_dialog_overlay)
	_refresh_towers_input_enabled()

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.72)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	adventure_dialog_overlay.add_child(bg)

	var card := ColorRect.new()
	card.name = "Card"
	var area := get_viewport_rect().size
	var portrait := _is_portrait(area)
	var modal_scale := _get_result_modal_scale(area)
	var margin := 16.0 * modal_scale
	var card_width := minf(780.0 * modal_scale, area.x - margin * 2.0)
	var card_height := minf(340.0 * modal_scale, area.y - margin * 2.0)
	if portrait:
		card_width = area.x - margin * 2.0
		card_height = minf(440.0 * modal_scale, area.y - margin * 2.0)
	card.color = Color(0.08, 0.10, 0.18, 0.98)
	card.custom_minimum_size = Vector2(card_width, card_height)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -card_width * 0.5
	card.offset_top = -card_height * 0.5
	card.offset_right = card_width * 0.5
	card.offset_bottom = card_height * 0.5
	adventure_dialog_overlay.add_child(card)

	var stripe := ColorRect.new()
	stripe.color = Color(1.0, 0.75, 0.1, 1.0)
	stripe.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stripe.offset_bottom = maxf(6.0, 6.0 * modal_scale)
	card.add_child(stripe)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 30.0 * modal_scale
	vb.offset_top = 22.0 * modal_scale
	vb.offset_right = -30.0 * modal_scale
	vb.offset_bottom = -22.0 * modal_scale
	vb.add_theme_constant_override("separation", int(round(14.0 * modal_scale)))
	card.add_child(vb)

	var title_label := Label.new()
	title_label.text = title
	_use_ui_text_font(title_label)
	title_label.add_theme_font_size_override("font_size", int(round(26.0 * modal_scale)))
	title_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title_label)

	var body := Label.new()
	body.text = _format_adventure_dialog_lines(lines)
	_use_ui_text_font(body)
	body.add_theme_font_size_override("font_size", int(round(22.0 * modal_scale)))
	body.add_theme_color_override("font_color", Color(0.90, 0.94, 1.0))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vb.add_child(body)

	var continue_btn := Button.new()
	continue_btn.text = tr("Continue")
	continue_btn.tooltip_text = continue_btn.text
	continue_btn.custom_minimum_size = Vector2(180.0 * modal_scale, 48.0 * modal_scale)
	continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_use_ui_text_font(continue_btn)
	continue_btn.add_theme_font_size_override("font_size", int(round(20.0 * modal_scale)))
	_apply_button_chrome(continue_btn, modal_scale, "action")
	continue_btn.pressed.connect(func():
		_clear_adventure_dialog_overlay()
		if after_close.is_valid():
			after_close.call()
	)
	vb.add_child(continue_btn)

func _format_adventure_dialog_lines(lines: Array) -> String:
	var parts := PackedStringArray()
	for raw_line in lines:
		if typeof(raw_line) == TYPE_DICTIONARY:
			var line: Dictionary = raw_line
			var speaker := str(line.get("speaker", "")).strip_edges()
			var text := str(line.get("text", "")).strip_edges()
			if text == "":
				continue
			if speaker != "":
				parts.append("%s: %s" % [speaker, text])
			else:
				parts.append(text)
		else:
			var text := str(raw_line).strip_edges()
			if text != "":
				parts.append(text)
	return "\n\n".join(parts)

func _clear_adventure_dialog_overlay() -> void:
	if adventure_dialog_overlay and is_instance_valid(adventure_dialog_overlay):
		adventure_dialog_overlay.queue_free()
	adventure_dialog_overlay = null
	call_deferred("_refresh_towers_input_enabled")

func _process(_delta: float):
	pass

func _update_responsive_layout() -> void:
	var area := get_viewport_rect().size
	if area.x <= 0.0 or area.y <= 0.0:
		return
	if _has_water_sort_settings():
		_layout_water_sort_ui(area)
	else:
		_layout_hanoi_ui(area)
	_layout_settings_overlay(area)
	_layout_cheats_overlay(area)

func _layout_water_sort_ui(area: Vector2) -> void:
	var portrait := _is_portrait(area)
	var ui_scale := _get_ui_scale(area)
	var button_height := UI_BUTTON_HEIGHT * ui_scale
	var top_safe := _get_top_safe_padding(area, ui_scale)

	_set_font_size(move_counter, 22, ui_scale)
	_set_font_size(goal_label, 18, ui_scale)
	_set_font_size(possible_moves_label, 18, ui_scale)

	var hidden_action_buttons := [new_puzzle_button, retry_button, extra_beaker_button, mulligan_button]
	for control in hidden_action_buttons:
		if control:
			control.visible = false
	if settings_button:
		settings_button.visible = true
	if cheats_button:
		cheats_button.visible = true
	if menu_button:
		menu_button.visible = true
		menu_button.text = "X"
		menu_button.tooltip_text = tr("Menu")
	var action_buttons := [settings_button, cheats_button, menu_button]
	_style_action_buttons(action_buttons, ui_scale)

	var buttons_bottom := _layout_top_pair_buttons(settings_button, cheats_button, area, ui_scale, button_height, top_safe)
	_layout_top_center_button(menu_button, area, ui_scale, button_height, top_safe)
	var labels_bottom := _layout_adventure_position_labels(settings_button, cheats_button, buttons_bottom, ui_scale)
	var info_top := maxf(top_safe + 8.0 * ui_scale, labels_bottom + 6.0 * ui_scale)
	_set_full_width_label(move_counter, info_top, 30.0 * ui_scale)
	_set_full_width_label(goal_label, info_top + 30.0 * ui_scale, 26.0 * ui_scale)
	_set_full_width_label(possible_moves_label, info_top + 58.0 * ui_scale, 26.0 * ui_scale)

	var play_top := info_top + (92.0 if portrait else 86.0) * ui_scale
	var play_bottom := area.y - 24.0 * ui_scale
	var trait_chip_gutter := _get_trait_chip_gutter_width(area, ui_scale)
	_set_towers_play_area(0.0, play_top, area.x - trait_chip_gutter, maxf(260.0 * ui_scale, play_bottom - play_top))

func _layout_hanoi_ui(area: Vector2) -> void:
	var portrait := _is_portrait(area)
	var ui_scale := _get_ui_scale(area)
	var button_height := UI_BUTTON_HEIGHT * ui_scale
	var top_safe := _get_top_safe_padding(area, ui_scale)
	if cheats_button:
		cheats_button.visible = false
	if settings_button:
		settings_button.visible = true
	if menu_button:
		menu_button.visible = true
		menu_button.text = "X"
		menu_button.tooltip_text = tr("Menu")
	_hide_adventure_position_labels()
	for control in [new_puzzle_button, retry_button, extra_beaker_button, mulligan_button]:
		if control:
			control.visible = false
	var hanoi_buttons := [settings_button, menu_button]
	_style_action_buttons(hanoi_buttons, ui_scale)
	_set_font_size(get_node_or_null("UI/Title"), 28, ui_scale)
	_set_font_size(move_counter, 22, ui_scale)
	_set_font_size(instructions_label, 18, ui_scale)

	var buttons_bottom := _layout_top_pair_buttons(settings_button, menu_button, area, ui_scale, button_height, top_safe)
	var title_top := maxf(top_safe + 8.0 * ui_scale, buttons_bottom + 6.0 * ui_scale)
	var move_top := title_top + 38.0 * ui_scale

	_set_full_width_label(get_node_or_null("UI/Title"), title_top, 42.0 * ui_scale, 460.0 * ui_scale)
	_set_full_width_label(move_counter, move_top, 30.0 * ui_scale)
	if instructions_label:
		var instruction_width := minf(720.0, area.x - UI_MARGIN * 2.0)
		_set_control_rect(instructions_label,
				Rect2((area.x - instruction_width) * 0.5, area.y - 72.0 * ui_scale, instruction_width, 54.0 * ui_scale))
	var play_top := move_top + (62.0 if portrait else 54.0) * ui_scale
	var play_bottom := area.y - ((118.0 if portrait else 88.0) * ui_scale if instructions_label else 24.0 * ui_scale)
	_set_towers_play_area(0.0, play_top, area.x, maxf(300.0 * ui_scale, play_bottom - play_top))

func _set_towers_play_area(left: float, top: float, width: float, height: float) -> void:
	if towers and towers.has_method("set_play_area"):
		towers.call("set_play_area", Rect2(left, top, width, height))

func _get_trait_chip_gutter_width(area: Vector2, ui_scale: float) -> float:
	if not _is_portrait(area) or not GameSettings.special_beakers_enabled:
		return 0.0
	var desired := PORTRAIT_TRAIT_CHIP_GUTTER * ui_scale
	var min_board_width := minf(area.x, maxf(360.0, area.x * 0.68))
	return minf(desired, maxf(0.0, area.x - min_board_width))

func _set_full_width_label(label: Control, top: float, height: float, max_width: float = 0.0) -> void:
	if not label:
		return
	var area := get_viewport_rect().size
	var width := area.x - UI_MARGIN * 2.0
	if max_width > 0.0:
		width = minf(width, max_width)
	_set_control_rect(label, Rect2((area.x - width) * 0.5, top, width, height))

func _layout_button_column(buttons: Array, left: float, top: float, width: float, height: float, gap: float) -> void:
	var next_top := top
	for control in buttons:
		if not control:
			continue
		_set_control_rect(control, Rect2(left, next_top, width, height))
		next_top += height + gap

func _layout_button_grid(buttons: Array, columns: int, rect: Rect2, height: float, gap: float) -> void:
	var visible_buttons := []
	for control in buttons:
		if control:
			visible_buttons.append(control)
	if visible_buttons.is_empty():
		return
	var button_width := (rect.size.x - gap * float(maxi(0, columns - 1))) / float(maxi(1, columns))
	for idx in visible_buttons.size():
		var control: Control = visible_buttons[idx]
		var col := idx % columns
		var row := int(idx / columns)
		_set_control_rect(control, Rect2(
				rect.position.x + float(col) * (button_width + gap),
				rect.position.y + float(row) * (height + gap),
				button_width,
				height))

func _layout_top_pair_buttons(left_button: Control, right_button: Control, area: Vector2,
		ui_scale: float, button_height: float, top_safe: float) -> float:
	var top := _get_top_button_y(area, ui_scale, top_safe)
	var mobile_runtime := _is_mobile_runtime()
	var base_margin := (22.0 if mobile_runtime else UI_MARGIN) * ui_scale
	var margin := maxf(base_margin, _get_horizontal_safe_padding(area, ui_scale) + 12.0 * ui_scale)
	var center_gap := clampf(area.x * (0.24 if _is_portrait(area) else 0.34), 92.0 * ui_scale, 180.0 * ui_scale)
	var min_button_width := 96.0 * ui_scale
	var max_button_width := 190.0 * ui_scale
	var available_each := (area.x - margin * 2.0 - center_gap) * 0.5
	if available_each < min_button_width:
		center_gap = maxf(24.0 * ui_scale, area.x - margin * 2.0 - min_button_width * 2.0)
		available_each = (area.x - margin * 2.0 - center_gap) * 0.5
	var button_width := clampf(available_each, min_button_width, max_button_width)
	if left_button:
		left_button.visible = true
		_set_control_rect(left_button, Rect2(margin, top, button_width, button_height))
	if right_button:
		right_button.visible = true
		_set_control_rect(right_button, Rect2(area.x - margin - button_width, top, button_width, button_height))
	return top + button_height

func _layout_top_center_button(button: Control, area: Vector2, ui_scale: float, button_height: float, top_safe: float) -> float:
	if not button:
		return _get_top_button_y(area, ui_scale, top_safe) + button_height
	var top := _get_top_button_y(area, ui_scale, top_safe)
	var button_width := clampf(button_height * 1.12, 44.0 * ui_scale, 70.0 * ui_scale)
	button.visible = true
	_set_control_rect(button, Rect2((area.x - button_width) * 0.5, top, button_width, button_height))
	return top + button_height

func _get_top_button_y(area: Vector2, ui_scale: float, top_safe: float) -> float:
	return 8.0 * ui_scale if _is_mobile_runtime() and _is_portrait(area) else top_safe + UI_MARGIN * ui_scale

func _layout_adventure_position_labels(left_button: Control, right_button: Control, buttons_bottom: float, ui_scale: float) -> float:
	if not _is_adventure_active():
		_hide_adventure_position_labels()
		return buttons_bottom
	_sync_adventure_position_labels()
	if not adventure_rank_label or not adventure_puzzle_label:
		return buttons_bottom

	var top := buttons_bottom + 3.0 * ui_scale
	var height := 22.0 * ui_scale
	_set_font_size(adventure_rank_label, 13, ui_scale)
	_set_font_size(adventure_puzzle_label, 13, ui_scale)
	adventure_rank_label.visible = left_button != null and left_button.visible
	adventure_puzzle_label.visible = right_button != null and right_button.visible
	if adventure_rank_label.visible:
		var left_rect := _get_control_rect(left_button)
		_set_control_rect(adventure_rank_label, Rect2(left_rect.position.x, top, left_rect.size.x, height))
	if adventure_puzzle_label.visible:
		var right_rect := _get_control_rect(right_button)
		_set_control_rect(adventure_puzzle_label, Rect2(right_rect.position.x, top, right_rect.size.x, height))
	return top + height

func _sync_adventure_position_labels() -> void:
	if not adventure_rank_label or not adventure_puzzle_label:
		return
	if not _is_adventure_active() or not AdventureManager.has_method("get_current_rank_progress"):
		_hide_adventure_position_labels()
		return
	var progress: Dictionary = AdventureManager.call("get_current_rank_progress")
	if progress.is_empty():
		_hide_adventure_position_labels()
		return
	adventure_rank_label.text = tr("Rank %d/%d") % [
		int(progress.get("rank_index", 0)),
		int(progress.get("rank_count", 0)),
	]
	adventure_puzzle_label.text = tr("Puzzle %d/%d") % [
		int(progress.get("puzzle_index", 0)),
		int(progress.get("puzzle_count", 0)),
	]

func _hide_adventure_position_labels() -> void:
	if adventure_rank_label:
		adventure_rank_label.visible = false
	if adventure_puzzle_label:
		adventure_puzzle_label.visible = false

func _get_control_rect(control: Control) -> Rect2:
	return Rect2(
			control.offset_left,
			control.offset_top,
			control.offset_right - control.offset_left,
			control.offset_bottom - control.offset_top)

func _count_controls(items: Array) -> int:
	var count := 0
	for item in items:
		if item:
			count += 1
	return count

func _is_portrait(area: Vector2) -> bool:
	return area.y > area.x * PORTRAIT_ASPECT_THRESHOLD

func _get_ui_scale(area: Vector2) -> float:
	if _is_portrait(area):
		var portrait_scale := clampf(area.x / PORTRAIT_REFERENCE_WIDTH, 1.0, 2.35)
		return maxf(MOBILE_UI_SCALE_MIN, portrait_scale) if _is_mobile_runtime() else portrait_scale
	var landscape_scale := clampf(minf(area.x / 1280.0, area.y / 720.0), 0.90, 1.35)
	return maxf(MOBILE_UI_SCALE_MIN, landscape_scale) if _is_mobile_runtime() else landscape_scale

func _get_result_modal_scale(area: Vector2) -> float:
	if area.x <= 0.0 or area.y <= 0.0:
		return 1.0
	if _is_portrait(area):
		return clampf(area.x / 660.0, 1.0, 1.70)
	return clampf(minf(area.x / 1280.0, area.y / 720.0), 0.95, 1.30)

func _is_mobile_runtime() -> bool:
	return OS.has_feature("mobile") or OS.get_name() == "Android" or OS.get_name() == "iOS"

func _get_top_safe_padding(area: Vector2, ui_scale: float) -> float:
	if not _is_mobile_runtime():
		return 0.0
	var top := 0.0
	var safe_area := DisplayServer.get_display_safe_area()
	if safe_area.size.x > 0 and safe_area.size.y > 0:
		var screen_size := Vector2(DisplayServer.screen_get_size())
		if screen_size.x > 0.0 and screen_size.y > 0.0:
			top = float(safe_area.position.y) * area.y / screen_size.y
		else:
			top = float(safe_area.position.y)
	if _is_portrait(area):
		top = maxf(top, 30.0 * ui_scale)
	else:
		top = maxf(top, 4.0 * ui_scale)
	return top

func _get_horizontal_safe_padding(area: Vector2, _ui_scale: float) -> float:
	if not _is_mobile_runtime():
		return 0.0
	var safe_area := DisplayServer.get_display_safe_area()
	if safe_area.size.x <= 0 or safe_area.size.y <= 0:
		return 0.0
	var screen_size := Vector2(DisplayServer.screen_get_size())
	if screen_size.x <= 0.0:
		return float(safe_area.position.x)
	var left := float(safe_area.position.x) * area.x / screen_size.x
	var right := maxf(0.0, float(screen_size.x - safe_area.position.x - safe_area.size.x) * area.x / screen_size.x)
	return maxf(left, right)

func _set_font_size(control: Control, base_size: int, ui_scale: float) -> void:
	if not control:
		return
	_use_ui_text_font(control)
	control.add_theme_font_size_override("font_size", int(round(float(base_size) * ui_scale)))

func _style_action_buttons(buttons: Array, ui_scale: float) -> void:
	for control in buttons:
		if not control or not (control is Button):
			continue
		var button := control as Button
		_use_ui_text_font(button)
		button.add_theme_font_size_override("font_size", int(round(19.0 * ui_scale)))
		_apply_button_chrome(button, ui_scale, "action")
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func _apply_button_chrome(button: Button, ui_scale: float, variant: String = "action") -> void:
	var radius := maxi(6, int(round(7.0 * ui_scale)))
	var border_width := maxi(1, int(round(1.6 * ui_scale)))
	var normal_fill := Color(0.068, 0.086, 0.132, 0.98)
	var hover_fill := Color(0.088, 0.112, 0.168, 1.0)
	var pressed_fill := Color(0.044, 0.060, 0.096, 1.0)
	var disabled_fill := Color(0.050, 0.056, 0.070, 0.72)
	var normal_border := Color(0.80, 0.91, 1.0, 0.46)
	var hover_border := Color(1.0, 0.91, 0.48, 0.76)
	var pressed_border := Color(1.0, 0.76, 0.28, 0.84)
	var disabled_border := Color(0.45, 0.50, 0.58, 0.30)
	if variant == "cheat":
		radius = maxi(7, int(round(8.0 * ui_scale)))
		border_width = maxi(2, int(round(2.0 * ui_scale)))
		normal_fill = Color(0.080, 0.102, 0.158, 0.98)
		hover_fill = Color(0.105, 0.132, 0.196, 1.0)
		pressed_fill = Color(0.056, 0.072, 0.118, 1.0)
		normal_border = Color(1.0, 0.84, 0.34, 0.58)
		hover_border = Color(1.0, 0.95, 0.62, 0.88)
		pressed_border = Color(1.0, 0.66, 0.22, 0.92)
	button.add_theme_stylebox_override("normal", _make_button_style(normal_fill, normal_border, radius, border_width, ui_scale, false))
	button.add_theme_stylebox_override("hover", _make_button_style(hover_fill, hover_border, radius, border_width, ui_scale, true))
	button.add_theme_stylebox_override("pressed", _make_button_style(pressed_fill, pressed_border, radius, border_width, ui_scale, false))
	button.add_theme_stylebox_override("focus", _make_button_style(hover_fill, Color(1.0, 1.0, 0.88, 0.92), radius, border_width + 1, ui_scale, true))
	button.add_theme_stylebox_override("disabled", _make_button_style(disabled_fill, disabled_border, radius, border_width, ui_scale, false))
	button.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.88, 0.94, 1.0, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.58, 0.64, 0.72, 0.86))
	button.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.68))
	button.add_theme_constant_override("outline_size", maxi(1, int(round(1.5 * ui_scale))))

func _make_button_style(fill: Color, border: Color, radius: int, border_width: int, ui_scale: float, lifted: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.38 if lifted else 0.26)
	style.shadow_size = int(round((5.0 if lifted else 3.0) * ui_scale))
	style.shadow_offset = Vector2(0.0, 2.0 * ui_scale)
	style.content_margin_left = 10.0 * ui_scale
	style.content_margin_right = 10.0 * ui_scale
	style.content_margin_top = 4.0 * ui_scale
	style.content_margin_bottom = 4.0 * ui_scale
	return style

func _get_ui_text_font() -> Font:
	if _ui_text_font == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["sans-serif", "Roboto", "Noto Sans", "Arial"])
		_ui_text_font = font
	return _ui_text_font

func _use_ui_text_font(control: Control) -> void:
	if not control:
		return
	control.add_theme_font_override("font", _get_ui_text_font())

func _layout_settings_overlay(area: Vector2) -> void:
	if not settings_overlay:
		return
	var card := settings_overlay.get_node_or_null("SettingsCard") as Control
	var scroll := settings_overlay.get_node_or_null("SettingsCard/Scroll") as ScrollContainer
	var content := settings_overlay.get_node_or_null("SettingsCard/Scroll/Content") as Control
	if not card or not scroll or not content:
		return
	var ui_scale := _get_ui_scale(area)
	var modal_scale := clampf(ui_scale, 1.15, 1.70)
	var mobile_sheet := _is_mobile_runtime() or _is_portrait(area)
	var margin := (10.0 if _is_portrait(area) else 18.0) * modal_scale
	var card_size: Vector2
	if mobile_sheet:
		card_size = Vector2(area.x - margin * 2.0, area.y - margin * 2.0)
	else:
		card_size = Vector2(minf(900.0, area.x - margin * 2.0), minf(700.0, area.y - margin * 2.0))
	var card_pos := Vector2((area.x - card_size.x) * 0.5, (area.y - card_size.y) * 0.5)
	if mobile_sheet and _is_portrait(area):
		card_pos.y = margin
	_set_control_rect(card, Rect2(card_pos, card_size))

	var stripe := card.get_node_or_null("Stripe") as Control
	if stripe:
		_set_control_rect(stripe, Rect2(0.0, 0.0, card_size.x, maxf(6.0, 5.0 * modal_scale)))

	var pad_x := 24.0 * modal_scale
	var pad_top := 22.0 * modal_scale
	var pad_bottom := 24.0 * modal_scale
	scroll.anchor_left = 0.0
	scroll.anchor_top = 0.0
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = pad_x
	scroll.offset_top = pad_top
	scroll.offset_right = -pad_x
	scroll.offset_bottom = -pad_bottom
	content.custom_minimum_size = Vector2(maxf(280.0, card_size.x - pad_x * 2.0 - 18.0), 0.0)
	if content is VBoxContainer:
		(content as VBoxContainer).add_theme_constant_override("separation", int(round(14.0 * modal_scale)))
	_style_settings_tree(content, modal_scale)

func _style_settings_tree(root: Node, modal_scale: float) -> void:
	for child in root.get_children():
		if child is HBoxContainer:
			(child as HBoxContainer).add_theme_constant_override("separation", int(round(12.0 * modal_scale)))
		elif child is GridContainer:
			var grid := child as GridContainer
			grid.add_theme_constant_override("h_separation", int(round(10.0 * modal_scale)))
			grid.add_theme_constant_override("v_separation", int(round(10.0 * modal_scale)))
		if child is Label:
			var label := child as Label
			_use_ui_text_font(label)
			var base_size := 19.0
			if label.text == tr("Settings"):
				base_size = 36.0
			elif label.custom_minimum_size.y >= 30.0:
				base_size = 23.0
			label.add_theme_font_size_override("font_size", int(round(base_size * modal_scale)))
			if label.custom_minimum_size.x > 0.0:
				label.custom_minimum_size.x = maxf(label.custom_minimum_size.x, 118.0 * modal_scale)
			label.custom_minimum_size.y = maxf(label.custom_minimum_size.y, 38.0 * modal_scale)
		elif child is CheckButton:
			var check := child as CheckButton
			_use_ui_text_font(check)
			check.add_theme_font_size_override("font_size", int(round(24.0 * modal_scale)))
			check.custom_minimum_size.y = maxf(check.custom_minimum_size.y, 66.0 * modal_scale)
			check.add_theme_constant_override("h_separation", int(round(14.0 * modal_scale)))
			_style_settings_toggle(check, modal_scale)
		elif child is Button:
			var button := child as Button
			var is_palette := button.has_meta("palette_button") and bool(button.get_meta("palette_button"))
			_use_ui_text_font(button)
			button.add_theme_font_size_override("font_size", int(round((20.0 if is_palette else 22.0) * modal_scale)))
			button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, (62.0 if is_palette else 58.0) * modal_scale)
			button.custom_minimum_size.x = maxf(button.custom_minimum_size.x, (260.0 if is_palette else 92.0) * modal_scale)
			if is_palette:
				_style_settings_palette_button(button, modal_scale)
			_apply_button_chrome(button, modal_scale, "action")
		elif child is HSlider:
			var slider := child as HSlider
			_style_settings_slider(slider, modal_scale)
		elif child is OptionButton:
			var option := child as OptionButton
			_style_settings_option_button(option, modal_scale)
		elif child is LineEdit:
			var input := child as LineEdit
			_use_ui_text_font(input)
			input.add_theme_font_size_override("font_size", int(round(22.0 * modal_scale)))
			input.custom_minimum_size.y = maxf(input.custom_minimum_size.y, 56.0 * modal_scale)
		_style_settings_tree(child, modal_scale)

func _style_settings_option_button(option: OptionButton, modal_scale: float) -> void:
	var font_size := int(round(24.0 * modal_scale))
	_use_ui_text_font(option)
	option.add_theme_font_size_override("font_size", font_size)
	option.custom_minimum_size = Vector2(maxf(option.custom_minimum_size.x, 320.0 * modal_scale), 66.0 * modal_scale)
	_apply_button_chrome(option, modal_scale, "action")
	var popup := option.get_popup()
	if not popup:
		return
	popup.add_theme_font_override("font", _get_ui_text_font())
	popup.add_theme_font_size_override("font_size", font_size)
	popup.add_theme_constant_override("v_separation", int(round(18.0 * modal_scale)))
	popup.add_theme_constant_override("item_start_padding", int(round(18.0 * modal_scale)))
	popup.add_theme_constant_override("item_end_padding", int(round(26.0 * modal_scale)))

func _style_settings_slider(slider: HSlider, modal_scale: float) -> void:
	var height := 62.0 * modal_scale
	slider.custom_minimum_size = Vector2(maxf(slider.custom_minimum_size.x, 300.0 * modal_scale), height)
	slider.add_theme_stylebox_override("slider", _make_slider_track_style(modal_scale, false))
	slider.add_theme_stylebox_override("grabber_area", _make_slider_track_style(modal_scale, true))
	slider.add_theme_stylebox_override("grabber_area_highlight", _make_slider_track_style(modal_scale, true))
	var radius := maxf(14.0, 14.0 * modal_scale)
	slider.add_theme_icon_override("grabber", _make_circle_texture(radius, Color(0.94, 0.97, 1.0), Color(0.10, 0.13, 0.20), 2.0 * modal_scale))
	slider.add_theme_icon_override("grabber_highlight", _make_circle_texture(radius * 1.08, Color(1.0, 0.91, 0.48), Color(0.10, 0.13, 0.20), 2.0 * modal_scale))
	slider.add_theme_icon_override("grabber_disabled", _make_circle_texture(radius, Color(0.44, 0.49, 0.58), Color(0.10, 0.13, 0.20), 2.0 * modal_scale))

func _style_settings_toggle(toggle: CheckButton, modal_scale: float) -> void:
	var width := int(round(58.0 * modal_scale))
	var height := int(round(34.0 * modal_scale))
	toggle.add_theme_icon_override("unchecked", _make_toggle_texture(width, height, false, true))
	toggle.add_theme_icon_override("checked", _make_toggle_texture(width, height, true, true))
	toggle.add_theme_icon_override("unchecked_disabled", _make_toggle_texture(width, height, false, false))
	toggle.add_theme_icon_override("checked_disabled", _make_toggle_texture(width, height, true, false))

func _style_settings_palette_button(button: Button, modal_scale: float) -> void:
	var key := str(button.get_meta("palette_key", ""))
	if GameSettings.LIQUID_PALETTES.has(key):
		var colors := GameSettings.LIQUID_PALETTES[key]["colors"] as Array
		var preview_size := Vector2i(int(round(124.0 * modal_scale)), int(round(24.0 * modal_scale)))
		button.icon = _make_palette_preview_texture(colors, preview_size)
	button.add_theme_constant_override("h_separation", int(round(14.0 * modal_scale)))

func _make_palette_preview_texture(colors: Array, texture_size: Vector2i) -> Texture2D:
	var width := maxi(64, texture_size.x)
	var height := maxi(18, texture_size.y)
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.015, 0.020, 0.035, 0.0))
	var border := maxi(2, int(round(float(height) * 0.08)))
	var inner_width := width - border * 2
	var inner_height := height - border * 2
	var swatch_count := mini(colors.size(), 8)
	if swatch_count <= 0 or inner_width <= 0 or inner_height <= 0:
		return ImageTexture.create_from_image(image)
	for y in range(border, height - border):
		for x in range(border, width - border):
			var local_x := x - border
			var swatch_idx := clampi(int(floor(float(local_x) / float(inner_width) * float(swatch_count))), 0, swatch_count - 1)
			var color := colors[swatch_idx] as Color
			var shade := 0.12 if y < border + maxf(1.0, float(inner_height) * 0.32) else 0.0
			image.set_pixel(x, y, color.lightened(shade))
	var outline := Color(0.92, 0.97, 1.0, 0.82)
	for y in height:
		for x in width:
			if x < border or x >= width - border or y < border or y >= height - border:
				image.set_pixel(x, y, outline)
	return ImageTexture.create_from_image(image)

func _make_slider_track_style(modal_scale: float, active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.68, 0.95, 0.70) if active else Color(0.040, 0.052, 0.082, 0.96)
	style.border_color = Color(0.86, 0.94, 1.0, 0.50) if active else Color(0.45, 0.56, 0.72, 0.56)
	var border := maxi(1, int(round(1.5 * modal_scale)))
	style.set_border_width_all(border)
	var radius := maxi(6, int(round(7.0 * modal_scale)))
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_top = 8.0 * modal_scale
	style.content_margin_bottom = 8.0 * modal_scale
	return style

func _make_circle_texture(radius: float, fill: Color, border: Color, border_width: float) -> Texture2D:
	var size := maxi(2, int(round((radius + border_width + 1.0) * 2.0)))
	var center := Vector2(float(size - 1) * 0.5, float(size - 1) * 0.5)
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in size:
		for x in size:
			var d := Vector2(float(x), float(y)).distance_to(center)
			if d <= radius + border_width:
				image.set_pixel(x, y, border if d > radius else fill)
	return ImageTexture.create_from_image(image)

func _make_toggle_texture(width: int, height: int, checked: bool, enabled: bool) -> Texture2D:
	width = maxi(width, 2)
	height = maxi(height, 2)
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var border_width := maxf(2.0, float(height) * 0.065)
	var track_fill := Color(0.16, 0.68, 0.92, 0.96) if checked else Color(0.045, 0.056, 0.086, 0.96)
	var track_border := Color(0.96, 0.98, 1.0, 0.72) if checked else Color(0.70, 0.78, 0.88, 0.54)
	var knob_fill := Color(1.0, 0.96, 0.74, 1.0) if checked else Color(0.86, 0.91, 0.98, 1.0)
	if not enabled:
		track_fill = Color(track_fill.r, track_fill.g, track_fill.b, 0.42)
		track_border = Color(track_border.r, track_border.g, track_border.b, 0.32)
		knob_fill = Color(0.56, 0.60, 0.68, 0.90)
	var outer := Rect2(0.0, 0.0, float(width), float(height))
	var inner := outer.grow(-border_width)
	for y in height:
		for x in width:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var in_outer := _is_point_in_pill(p, outer)
			if not in_outer:
				continue
			var in_inner := _is_point_in_pill(p, inner)
			image.set_pixel(x, y, track_fill if in_inner else track_border)
	var knob_radius := float(height) * 0.33
	var knob_center := Vector2(float(width) - float(height) * 0.50, float(height) * 0.50) if checked else Vector2(float(height) * 0.50, float(height) * 0.50)
	for y in height:
		for x in width:
			var d := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(knob_center)
			if d <= knob_radius + border_width:
				image.set_pixel(x, y, Color(0.04, 0.05, 0.08, 0.80) if d > knob_radius else knob_fill)
	return ImageTexture.create_from_image(image)

func _is_point_in_pill(point: Vector2, rect: Rect2) -> bool:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return false
	var radius := rect.size.y * 0.5
	var center_y := rect.position.y + radius
	var left_center := Vector2(rect.position.x + radius, center_y)
	var right_center := Vector2(rect.position.x + rect.size.x - radius, center_y)
	if point.x >= left_center.x and point.x <= right_center.x:
		return point.y >= rect.position.y and point.y <= rect.position.y + rect.size.y
	return point.distance_to(left_center if point.x < left_center.x else right_center) <= radius

func _layout_cheats_overlay(area: Vector2) -> void:
	if not cheats_overlay:
		return
	var card := cheats_overlay.get_node_or_null("CheatsCard") as Control
	var content := cheats_overlay.get_node_or_null("CheatsCard/Scroll/Content") as Control
	if not card or not content:
		return
	var ui_scale := _get_ui_scale(area)
	var modal_scale := clampf(ui_scale, 1.15, 1.70)
	var margin := (10.0 if _is_portrait(area) else 18.0) * modal_scale
	var mobile_sheet := _is_mobile_runtime() or _is_portrait(area)
	var card_size: Vector2
	if mobile_sheet:
		card_size = Vector2(area.x - margin * 2.0, minf(area.y - margin * 2.0, 620.0 * modal_scale))
	else:
		card_size = Vector2(minf(620.0 * modal_scale, area.x - margin * 2.0), minf(420.0 * modal_scale, area.y - margin * 2.0))
	var card_pos := Vector2((area.x - card_size.x) * 0.5, (area.y - card_size.y) * 0.5)
	if mobile_sheet:
		card_pos.y = area.y - card_size.y - margin
	_set_control_rect(card, Rect2(card_pos, card_size))

	var stripe := card.get_node_or_null("Stripe") as Control
	if stripe:
		_set_control_rect(stripe, Rect2(0.0, 0.0, card_size.x, maxf(6.0, 5.0 * modal_scale)))
	var scroll := card.get_node_or_null("Scroll") as ScrollContainer
	if scroll:
		scroll.anchor_left = 0.0
		scroll.anchor_top = 0.0
		scroll.anchor_right = 1.0
		scroll.anchor_bottom = 1.0
		scroll.offset_left = 22.0 * modal_scale
		scroll.offset_top = 18.0 * modal_scale
		scroll.offset_right = -22.0 * modal_scale
		scroll.offset_bottom = -22.0 * modal_scale
	content.custom_minimum_size = Vector2(maxf(280.0, card_size.x - 48.0 * modal_scale), 0.0)
	_style_cheats_tree(content, modal_scale)

func _style_cheats_tree(root: Node, modal_scale: float) -> void:
	for child in root.get_children():
		if child is GridContainer:
			var grid := child as GridContainer
			grid.add_theme_constant_override("h_separation", int(round(10.0 * modal_scale)))
			grid.add_theme_constant_override("v_separation", int(round(10.0 * modal_scale)))
		elif child is HBoxContainer:
			(child as HBoxContainer).add_theme_constant_override("separation", int(round(12.0 * modal_scale)))
		elif child is Label:
			var label := child as Label
			_use_ui_text_font(label)
			var base_size := 20.0
			if label.text == tr("Cheats"):
				base_size = 34.0
			label.add_theme_font_size_override("font_size", int(round(base_size * modal_scale)))
			label.custom_minimum_size.y = maxf(label.custom_minimum_size.y, 38.0 * modal_scale)
		elif child is Button:
			var button := child as Button
			_use_ui_text_font(button)
			button.add_theme_font_size_override("font_size", int(round(24.0 * modal_scale)))
			button.custom_minimum_size = Vector2(maxf(button.custom_minimum_size.x, 190.0 * modal_scale), 68.0 * modal_scale)
			var variant := "cheat" if button.has_meta("cheat_button") and bool(button.get_meta("cheat_button")) else "action"
			_apply_button_chrome(button, modal_scale, variant)
		_style_cheats_tree(child, modal_scale)

func _set_control_rect(control: Control, rect: Rect2) -> void:
	if not control:
		return
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.position.x + rect.size.x
	control.offset_bottom = rect.position.y + rect.size.y
	control.custom_minimum_size = rect.size

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
		card_size = Vector2(840, 680)
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
	stripe.name = "Stripe"
	stripe.color = Color(0.14, 0.70, 1.0, 1.0)
	stripe.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stripe.offset_bottom = 5.0
	card.add_child(stripe)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 28.0
	scroll.offset_top = 22.0
	scroll.offset_right = -28.0
	scroll.offset_bottom = -24.0
	card.add_child(scroll)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.custom_minimum_size = Vector2(card_size.x - 100.0, 0.0)
	content.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

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
	close_btn.text = "X"
	close_btn.tooltip_text = tr("Close")
	close_btn.custom_minimum_size = Vector2(52, 38)
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.pressed.connect(_close_settings_dialog)
	header.add_child(close_btn)
	_add_settings_actions(content)

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
		depth_slider.max_value = _get_capacity_setting_max()
		depth_slider.step = 1.0
		depth_slider.value_changed.connect(_on_depth_changed)
		_add_difficulty_row(content)
		var filled_controls := _add_labeled_slider_row(content, tr("Colors"))
		filled_beakers_slider = filled_controls["slider"] as HSlider
		filled_beakers_value = filled_controls["value"] as Label
		filled_beakers_slider.min_value = 1.0
		filled_beakers_slider.max_value = _get_filled_beaker_setting_max()
		filled_beakers_slider.step = 1.0
		filled_beakers_slider.value_changed.connect(_on_filled_beakers_changed)

		var empty_controls := _add_labeled_slider_row(content, tr("Empty"))
		empty_beakers_slider = empty_controls["slider"] as HSlider
		empty_beakers_value = empty_controls["value"] as Label
		empty_beakers_slider.min_value = _get_empty_beaker_setting_min()
		empty_beakers_slider.max_value = _get_empty_beaker_setting_max()
		empty_beakers_slider.step = 1.0
		empty_beakers_slider.value_changed.connect(_on_empty_beakers_changed)

		chill_mode_toggle = CheckButton.new()
		chill_mode_toggle.text = tr("Chill mode")
		chill_mode_toggle.add_theme_font_size_override("font_size", 18)
		chill_mode_toggle.toggled.connect(_on_chill_mode_toggled)
		content.add_child(chill_mode_toggle)

		goal_toggle = CheckButton.new()
		goal_toggle.text = tr("Show goal")
		goal_toggle.add_theme_font_size_override("font_size", 18)
		goal_toggle.toggled.connect(_on_show_goal_toggled)
		content.add_child(goal_toggle)

		special_beakers_toggle = CheckButton.new()
		special_beakers_toggle.text = tr("Special beakers")
		special_beakers_toggle.add_theme_font_size_override("font_size", 18)
		special_beakers_toggle.toggled.connect(_on_special_beakers_toggled)
		content.add_child(special_beakers_toggle)

		_add_board_code_row(content)

		_add_section_label(content, tr("Display"))
		_add_palette_row(content)

		var liquid_alpha_controls := _add_labeled_slider_row(content, tr("Liquid opacity"))
		liquid_alpha_slider = liquid_alpha_controls["slider"] as HSlider
		liquid_alpha_value = liquid_alpha_controls["value"] as Label
		liquid_alpha_slider.min_value = GameSettings.LIQUID_ALPHA_MIN
		liquid_alpha_slider.max_value = GameSettings.LIQUID_ALPHA_MAX
		liquid_alpha_slider.step = 0.01
		liquid_alpha_slider.value_changed.connect(_on_liquid_alpha_changed)

		liquid_symbols_toggle = CheckButton.new()
		liquid_symbols_toggle.text = tr("Liquid symbols")
		liquid_symbols_toggle.add_theme_font_size_override("font_size", 18)
		liquid_symbols_toggle.toggled.connect(_on_liquid_symbols_toggled)
		content.add_child(liquid_symbols_toggle)

		_add_symbol_set_row(content)

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
	option.custom_minimum_size = Vector2(300, 46)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)

	return {"option": option}

func _add_palette_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var label := Label.new()
	label.text = tr("Palette")
	label.custom_minimum_size = Vector2(110, 34)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.98))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var options := GridContainer.new()
	options.columns = 1
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_theme_constant_override("h_separation", 8)
	options.add_theme_constant_override("v_separation", 8)
	row.add_child(options)

	palette_buttons.clear()
	for key in GameSettings.LIQUID_PALETTE_ORDER:
		var button := Button.new()
		button.text = GameSettings.get_liquid_palette_label(key)
		button.tooltip_text = button.text
		button.toggle_mode = true
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(300, 52)
		button.set_meta("palette_button", true)
		button.set_meta("palette_key", key)
		button.pressed.connect(_on_palette_button_pressed.bind(key))
		palette_buttons[key] = button
		options.add_child(button)

func _add_settings_actions(parent: Control) -> void:
	_add_section_label(parent, tr("Actions"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	parent.add_child(grid)

	_add_settings_action_button(grid, tr("New Puzzle"), reset_game)
	_add_settings_action_button(grid, tr("Retry"), retry_game)
	_add_settings_action_button(grid, tr("Menu"), go_to_menu)

func _add_settings_action_button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = text
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(150, 46)
	button.pressed.connect(func():
		_close_settings_dialog(false)
		callback.call()
	)
	parent.add_child(button)
	return button

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

func _add_symbol_set_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label := Label.new()
	label.text = tr("Symbols")
	label.custom_minimum_size = Vector2(110, 34)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.98))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	for key in GameSettings.LIQUID_SYMBOL_SET_ORDER:
		var button := Button.new()
		button.text = GameSettings.get_liquid_symbol_set_label(key)
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(142, 46)
		button.add_theme_font_size_override("font_size", 18)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_symbol_set_button_pressed.bind(key))
		symbol_set_buttons[key] = button
		row.add_child(button)

func _get_capacity_setting_max() -> int:
	return GameSettings.CAPACITY_MAX

func _get_filled_beaker_setting_max(empty_count: int = -1) -> int:
	var empty := maxi(_get_empty_beaker_setting_min(), GameSettings.get_empty_beaker_count() if empty_count < 0 else empty_count)
	return maxi(1, GameSettings.MAX_BEAKERS - empty)

func _get_empty_beaker_setting_min() -> int:
	return 2

func _get_empty_beaker_setting_max(filled_count: int = -1) -> int:
	var filled := GameSettings.get_filled_beaker_count() if filled_count < 0 else filled_count
	return maxi(_get_empty_beaker_setting_min(), GameSettings.MAX_BEAKERS - filled)

func _open_settings_dialog():
	if not settings_overlay:
		return
	_setup_settings_ui()
	_layout_settings_overlay(get_viewport_rect().size)
	settings_overlay.visible = true
	settings_overlay.move_to_front()
	_refresh_towers_input_enabled()
	if AudioManager:
		AudioManager.play_click()

func _close_settings_dialog(play_sound: bool = true):
	if not settings_overlay or not settings_overlay.visible:
		return
	settings_overlay.visible = false
	_refresh_towers_input_enabled()
	if play_sound and AudioManager:
		AudioManager.play_click()

func _on_settings_backdrop_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_settings_dialog()

func _build_cheats_dialog() -> void:
	if not _has_water_sort_settings():
		return
	var ui = get_node_or_null("UI")
	if not ui:
		return
	cheats_button = Button.new()
	cheats_button.name = "CheatsButton"
	cheats_button.text = tr("Cheats")
	cheats_button.tooltip_text = tr("Cheats")
	cheats_button.add_theme_font_size_override("font_size", 18)
	cheats_button.pressed.connect(_on_cheats_button_pressed)
	ui.add_child(cheats_button)
	_ensure_cheats_attention_frame()
	_sync_cheats_button_label()

	cheats_overlay = Control.new()
	cheats_overlay.name = "CheatsOverlay"
	cheats_overlay.visible = false
	cheats_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cheats_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(cheats_overlay)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0, 0, 0, 0.60)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_cheats_backdrop_gui_input)
	cheats_overlay.add_child(backdrop)

	var card := ColorRect.new()
	card.name = "CheatsCard"
	card.color = Color(0.075, 0.09, 0.14, 0.98)
	card.custom_minimum_size = Vector2(560, 360)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	cheats_overlay.add_child(card)

	var stripe := ColorRect.new()
	stripe.name = "Stripe"
	stripe.color = Color(1.0, 0.72, 0.16, 1.0)
	stripe.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stripe.offset_bottom = 5.0
	card.add_child(stripe)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 22.0
	scroll.offset_top = 18.0
	scroll.offset_right = -22.0
	scroll.offset_bottom = -22.0
	card.add_child(scroll)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

func _on_cheats_button_pressed() -> void:
	if _is_choosing_cheat():
		if towers and towers.has_method("cancel_cheat"):
			towers.call("cancel_cheat")
		if AudioManager:
			AudioManager.play_click()
		_sync_cheats_button_label()
		return
	_open_cheats_dialog()

func _open_cheats_dialog() -> void:
	if not cheats_overlay:
		return
	_populate_cheats_dialog()
	_layout_cheats_overlay(get_viewport_rect().size)
	cheats_overlay.visible = true
	cheats_overlay.move_to_front()
	_sync_cheats_attention()
	_refresh_towers_input_enabled()
	if AudioManager:
		AudioManager.play_click()

func _close_cheats_dialog(play_sound: bool = true) -> void:
	if not cheats_overlay or not cheats_overlay.visible:
		return
	cheats_overlay.visible = false
	_sync_cheats_attention()
	_refresh_towers_input_enabled()
	if play_sound and AudioManager:
		AudioManager.play_click()

func _on_cheats_backdrop_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_cheats_dialog()

func _populate_cheats_dialog() -> void:
	var content := cheats_overlay.get_node_or_null("CheatsCard/Scroll/Content") as VBoxContainer
	if not content:
		return
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)

	var title := Label.new()
	title.text = tr("Cheats")
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.tooltip_text = tr("Close")
	close_btn.custom_minimum_size = Vector2(52, 42)
	close_btn.pressed.connect(_close_cheats_dialog)
	header.add_child(close_btn)

	var utility_grid := GridContainer.new()
	utility_grid.columns = 2
	utility_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	utility_grid.add_theme_constant_override("h_separation", 14)
	utility_grid.add_theme_constant_override("v_separation", 14)
	content.add_child(utility_grid)

	var undo_btn := _add_cheats_menu_button(utility_grid,
			_get_undo_button_text(),
			use_mulligan,
			_can_use_mulligan())
	var undo_badge := _create_mulligan_badge()
	undo_badge.text = str(_get_mulligans_remaining())
	undo_badge.tooltip_text = tr("Undos left: %d") % _get_mulligans_remaining()
	undo_btn.add_child(undo_badge)

	_add_cheats_menu_button(utility_grid, _get_extra_beaker_button_text(), use_extra_beaker_cheat, _can_use_extra_beaker_cheat())

	var pipette_label := Label.new()
	pipette_label.text = tr("Pipette")
	pipette_label.add_theme_color_override("font_color", Color(0.78, 0.96, 1.0))
	content.add_child(pipette_label)

	var pipette_grid := GridContainer.new()
	pipette_grid.columns = 2
	pipette_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pipette_grid.add_theme_constant_override("h_separation", 14)
	pipette_grid.add_theme_constant_override("v_separation", 14)
	content.add_child(pipette_grid)

	var can_stir := _can_start_recovery_cheat("stir")
	var can_swap := _can_start_recovery_cheat("swap")
	var can_pipette := _can_start_recovery_cheat("pipette")
	_add_cheats_menu_button(pipette_grid, _get_recovery_cheat_button_text("stir"), start_stir_cheat, can_stir)
	_add_cheats_menu_button(pipette_grid, _get_recovery_cheat_button_text("swap"), start_swap_cheat, can_swap)
	_add_cheats_menu_button(pipette_grid, _get_recovery_cheat_button_text("pipette"), start_pipette_cheat, can_pipette)

func _add_cheats_menu_button(parent: Control, text: String, callback: Callable, enabled: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = text
	button.disabled = not enabled
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(190, 68)
	button.set_meta("cheat_button", true)
	_apply_button_chrome(button, 1.0, "cheat")
	button.pressed.connect(func():
		_close_cheats_dialog(false)
		callback.call()
	)
	parent.add_child(button)
	return button

func _unhandled_input(event: InputEvent):
	if cheats_overlay and cheats_overlay.visible and event.is_action_pressed("ui_cancel"):
		_close_cheats_dialog()
		get_viewport().set_input_as_handled()
	elif settings_overlay and settings_overlay.visible and event.is_action_pressed("ui_cancel"):
		_close_settings_dialog()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and towers and towers.has_method("is_choosing_cheat") and bool(towers.call("is_choosing_cheat")):
		towers.call("cancel_cheat")
		get_viewport().set_input_as_handled()

func _setup_settings_ui():
	_syncing_settings_ui = true
	if disk_count_slider:
		disk_count_slider.min_value = GameSettings.HANOI_DISK_COUNT_MIN
		disk_count_slider.max_value = GameSettings.HANOI_DISK_COUNT_MAX
		disk_count_slider.value = GameSettings.hanoi_disk_count
		if disk_count_value:
			disk_count_value.text = str(GameSettings.hanoi_disk_count)
	if depth_slider:
		depth_slider.min_value = GameSettings.CAPACITY_MIN
		depth_slider.max_value = _get_capacity_setting_max()
		depth_slider.value = GameSettings.beaker_capacity
		if depth_value:
			depth_value.text = str(GameSettings.beaker_capacity)
	if chill_mode_toggle:
		chill_mode_toggle.button_pressed = GameSettings.chill_mode
	if goal_toggle:
		goal_toggle.button_pressed = GameSettings.show_goal_hint
		goal_toggle.disabled = GameSettings.chill_mode
	if special_beakers_toggle:
		special_beakers_toggle.button_pressed = GameSettings.special_beakers_enabled
	if palette_option or not palette_buttons.is_empty():
		_sync_palette_option()
	if liquid_alpha_slider:
		liquid_alpha_slider.min_value = GameSettings.LIQUID_ALPHA_MIN
		liquid_alpha_slider.max_value = GameSettings.LIQUID_ALPHA_MAX
		liquid_alpha_slider.value = GameSettings.liquid_alpha
	if liquid_alpha_value:
		liquid_alpha_value.text = _format_volume(GameSettings.liquid_alpha)
	if liquid_symbols_toggle:
		liquid_symbols_toggle.button_pressed = GameSettings.show_liquid_symbols
	if symbol_set_option or not symbol_set_buttons.is_empty():
		_sync_symbol_set_option()
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
	_sync_beaker_count_controls()
	_sync_difficulty_buttons()
	_syncing_settings_ui = false
	_settings_ready = true

func _on_disk_moved():
	moves += 1
	update_move_counter()
	update_possible_moves_label()
	update_goal_label()
	_update_music_pressure()
	_update_mulligan_button()
	if _is_pour_limit_exceeded():
		_show_pour_limit_loss()
	elif towers.check_complete():
		_show_victory_delayed()
	elif _record_repeated_state():
		_show_loss(tr("LOOP DETECTED"), tr("State repeated %d times.") % REPEATED_STATE_LOSS_COUNT, true)

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
	possible_moves_label.text = tr("Options: %d") % count
	_sync_cheats_attention()

func _on_goal_changed(_optimal_pours: int):
	if _optimal_pours != OPTIMAL_SOLVER_CALCULATING:
		_solver_progress_text = ""
	update_goal_label()
	_refresh_victory_score()
	_update_music_pressure()
	_update_mulligan_button()

func _on_solver_progress(searched: int, frontier: int, depth: int, limit: int) -> void:
	if _is_adventure_active():
		_solver_progress_text = ""
		update_goal_label()
		return
	if _is_chill_mode():
		_solver_progress_text = ""
		update_goal_label()
		return
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
	if _is_chill_mode():
		goal_label.visible = true
		goal_label.text = tr("Chill mode")
		return
	var optimal := _get_optimal_pours()
	if optimal == OPTIMAL_SOLVER_CALCULATING:
		goal_label.visible = true
		if _solver_progress_text != "":
			goal_label.text = "%s | %s" % [tr("Calculating goal"), _solver_progress_text]
		else:
			goal_label.text = tr("Calculating goal")
		return
	if not GameSettings.show_goal_hint:
		goal_label.visible = true
		goal_label.text = tr("Goal ready")
		return
	if optimal < 0:
		goal_label.visible = true
		goal_label.text = tr("Goal ready") if _is_adventure_active() else tr("Still calculating goal")
		return
	var limit := _get_pour_limit()
	var score := _get_score()
	goal_label.visible = true
	goal_label.text = tr("Goal %d | Limit %d | Score %s") % [optimal, limit, _format_score(score)]
	if _mulligans_used > 0:
		goal_label.text += tr(" | Undo: +%s") % _format_pours(_get_mulligan_pour_penalty())
	if _cheats_used > 0:
		goal_label.text += _format_recovery_cheat_penalty(false)

func _get_optimal_pours() -> int:
	if _is_chill_mode():
		return -1
	var adventure_goal := _get_adventure_precomputed_optimal_pours()
	if adventure_goal >= 0:
		return adventure_goal
	var raw_goal = towers.get("optimal_pours")
	if raw_goal == null:
		return -1
	return int(raw_goal)

func _get_adventure_precomputed_optimal_pours() -> int:
	if _is_adventure_active() and AdventureManager.has_method("get_current_optimal_pours"):
		return int(AdventureManager.call("get_current_optimal_pours"))
	return -1

func _get_pour_limit() -> int:
	if _is_chill_mode():
		return -1
	if _is_adventure_active() and AdventureManager.has_method("get_current_pour_limit"):
		var adventure_limit := int(AdventureManager.call("get_current_pour_limit"))
		if adventure_limit >= 0:
			return adventure_limit
	var optimal := _get_optimal_pours()
	if optimal < 0:
		return -1
	var grace := maxi(6, int(ceil(float(optimal) * 0.5)))
	return optimal + grace

func _get_score() -> int:
	if _is_chill_mode():
		return -1
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
	if _is_chill_mode():
		return 0.0
	return float(_mulligans_used) * MULLIGAN_POUR_PENALTY

func _get_cheat_pour_penalty() -> float:
	if _is_chill_mode():
		return 0.0
	return _recovery_cheat_pour_penalty

func _format_recovery_cheat_penalty(wide: bool) -> String:
	if _is_chill_mode():
		return ""
	var key := "  |  Cheat: +%s" if wide else " | Cheat: +%s"
	if _cheats_used > 0 and _get_cheat_use_count("extra_beaker") == _cheats_used:
		key = "  |  Beaker: +%s" if wide else " | Beaker: +%s"
	return tr(key) % _format_pours(_get_cheat_pour_penalty())

func _get_extra_beaker_pour_penalty() -> float:
	if _is_chill_mode():
		return 0.0
	var optimal := _get_optimal_pours()
	if optimal < 0:
		return 0.0
	var rounded: float = ceil(float(optimal) * EXTRA_BEAKER_PENALTY_RATIO * 2.0) / 2.0
	return maxf(EXTRA_BEAKER_MIN_PENALTY, rounded)

func _get_effective_pours() -> float:
	if _is_chill_mode():
		return float(moves)
	return float(moves) + _get_mulligan_pour_penalty() + _get_cheat_pour_penalty()

func _get_extra_pours() -> float:
	if _is_chill_mode():
		return 0.0
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

func _get_undo_button_text() -> String:
	if _is_chill_mode():
		return tr("Undo")
	return tr("Undo +%s") % _format_pours(MULLIGAN_POUR_PENALTY)

func _get_extra_beaker_button_text() -> String:
	var penalty := _get_extra_beaker_pour_penalty()
	return tr("Extra +%s") % _format_pours(penalty) if penalty > 0.0 else tr("Extra")

func _get_recovery_cheat_button_text(cheat_type: String) -> String:
	var penalty := _get_recovery_cheat_pour_penalty(cheat_type)
	if cheat_type == "pipette":
		return tr("Transfer +%s") % _format_pours(penalty) if penalty > 0.0 else tr("Transfer")
	if cheat_type == "swap":
		return tr("Swap +%s") % _format_pours(penalty) if penalty > 0.0 else tr("Swap")
	return tr("Stir +%s") % _format_pours(penalty) if penalty > 0.0 else tr("Stir")

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

func _is_chill_mode() -> bool:
	if _is_adventure_active():
		return AdventureManager.is_current_chill()
	return towers != null and _has_water_sort_settings() and GameSettings.chill_mode

func _refresh_towers_input_enabled() -> void:
	if not towers:
		return
	var settings_open := settings_overlay != null and settings_overlay.visible
	var cheats_open := cheats_overlay != null and cheats_overlay.visible
	var adventure_dialog_open := adventure_dialog_overlay != null and is_instance_valid(adventure_dialog_overlay)
	var should_enable := (not settings_open and not cheats_open and not adventure_dialog_open
			and not _has_result_overlay() and not _shatter_loss_locked)
	towers.set_process_input(should_enable)
	if not should_enable and towers.has_method("clear_pointer_state"):
		towers.call("clear_pointer_state")

func _update_music_pressure() -> void:
	if not AudioManager:
		return
	if _is_chill_mode():
		if AudioManager.has_method("play_game_music"):
			AudioManager.call("play_game_music", 0.0)
		elif AudioManager.has_method("set_loop_pressure"):
			AudioManager.call("set_loop_pressure", 0.0)
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

func _would_exceed_pour_limit(extra_penalty: float) -> bool:
	var limit := _get_pour_limit()
	return limit >= 0 and _get_effective_pours() + extra_penalty > float(limit)

func _would_mulligan_exceed_pour_limit() -> bool:
	var limit := _get_pour_limit()
	if limit < 0:
		return false
	var next_effective := float(maxi(0, moves - 1)) + float(_mulligans_used + 1) * MULLIGAN_POUR_PENALTY + _get_cheat_pour_penalty()
	return next_effective > float(limit)

func _show_pour_limit_loss() -> void:
	var limit := _get_pour_limit()
	_show_loss(tr("POUR LIMIT"), tr("Limit: %d %s.") % [limit, tr(win_label)])

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
	if _is_pour_limit_exceeded():
		_show_pour_limit_loss()
		return
	if AudioManager:
		AudioManager.play_win()
	await get_tree().create_timer(1.2).timeout
	if get_node_or_null("VictoryOverlay") or get_node_or_null("LoseOverlay"):
		return
	if _is_pour_limit_exceeded():
		_show_pour_limit_loss()
		return
	_show_current_adventure_outro_or_victory()

func show_victory_screen():
	if AudioManager and AudioManager.has_method("play_solved_music"):
		AudioManager.play_solved_music()
	_record_adventure_completion_if_ready()
	_victory_stars_shown = false
	var cl := CanvasLayer.new()
	cl.name = "VictoryOverlay"
	cl.layer = 10
	add_child(cl)
	_refresh_towers_input_enabled()

	# Dimming background
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	cl.add_child(bg)

	# Card
	var card := ColorRect.new()
	card.name = "Card"
	var area := get_viewport_rect().size
	var portrait := _is_portrait(area)
	var modal_scale := _get_result_modal_scale(area)
	var margin := 14.0 * modal_scale
	var card_width := minf(860.0 * modal_scale, area.x - margin * 2.0)
	var card_height := minf(460.0 * modal_scale, area.y - margin * 2.0)
	if portrait:
		card_width = area.x - margin * 2.0
		card_height = minf(620.0 * modal_scale, area.y - margin * 2.0)
	card.color = Color(0.08, 0.10, 0.18, 0.97)
	card.custom_minimum_size = Vector2(card_width, card_height)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left   = -card_width * 0.5
	card.offset_top    = -card_height * 0.5
	card.offset_right  =  card_width * 0.5
	card.offset_bottom =  card_height * 0.5
	card.pivot_offset  = Vector2(card_width * 0.5, card_height * 0.5)
	card.scale         = Vector2(0.05, 0.05)
	cl.add_child(card)

	# Border strip at top of card
	var stripe := ColorRect.new()
	stripe.color = Color(1.0, 0.75, 0.1, 1.0)
	stripe.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stripe.offset_bottom = maxf(6.0, 6.0 * modal_scale)
	card.add_child(stripe)

	# Layout inside card
	var vb := VBoxContainer.new()
	vb.name = "Content"
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 30.0 * modal_scale
	vb.offset_top = 14.0 * modal_scale
	vb.offset_right = -30.0 * modal_scale
	vb.offset_bottom = -18.0 * modal_scale
	vb.add_theme_constant_override("separation", int(round(8.0 * modal_scale)))
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vb)

	var solved_lbl := Label.new()
	solved_lbl.text = tr(SOLVED_TITLE_KEY)
	solved_lbl.add_theme_font_size_override("font_size", int(round(66.0 * modal_scale)))
	solved_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.15))
	solved_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	solved_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(solved_lbl)

	var count_lbl := Label.new()
	count_lbl.text = tr("Completed in %d %s") % [moves, tr(win_label)]
	_use_ui_text_font(count_lbl)
	count_lbl.add_theme_font_size_override("font_size", int(round(28.0 * modal_scale)))
	count_lbl.add_theme_color_override("font_color", Color(0.82, 0.88, 1.0))
	count_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(count_lbl)

	if not _is_chill_mode():
		var score_lbl := Label.new()
		score_lbl.name = "ScoreLine"
		_use_ui_text_font(score_lbl)
		score_lbl.add_theme_font_size_override("font_size", int(round(24.0 * modal_scale)))
		score_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
		score_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		score_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(score_lbl)

		var star_row := HBoxContainer.new()
		star_row.name = "StarRow"
		star_row.alignment = BoxContainer.ALIGNMENT_CENTER
		star_row.custom_minimum_size = Vector2(0, 84.0 * modal_scale)
		star_row.add_theme_constant_override("separation", int(round(12.0 * modal_scale)))
		vb.add_child(star_row)
	else:
		var chill_bonus_summary := _get_chill_bonus_summary()
		if chill_bonus_summary != "":
			_add_chill_result_line(vb, tr("Bonuses: %s") % chill_bonus_summary, modal_scale,
					Color(0.95, 0.98, 1.0))
		var chill_cheats_summary := _get_chill_cheats_summary()
		if chill_cheats_summary != "":
			_add_chill_result_line(vb, tr("Cheats used: %s") % chill_cheats_summary, modal_scale,
					Color(1.0, 0.86, 0.35))

	if _is_adventure_active():
		_add_adventure_rank_progress_line(vb, modal_scale)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8.0 * modal_scale)
	vb.add_child(spacer)

	var hb := GridContainer.new()
	hb.columns = 2 if portrait else 4
	_style_result_button_grid(hb, portrait, modal_scale, card_width)
	vb.add_child(hb)

	_add_result_button(hb, tr("Retry"), 110.0, retry_game)
	if _is_adventure_active() and not AdventureManager.get_next_puzzle_after_current().is_empty():
		_add_result_button(hb, tr("Next"), 104.0, _go_to_next_adventure_puzzle)
	else:
		_add_result_button(hb, tr("New"), 104.0, reset_game)
	_add_result_button(hb, tr("Board"), 110.0, _return_to_board_from_result)
	_add_result_button(hb, tr("Menu"), 104.0, go_to_menu)

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
	if _is_chill_mode():
		return
	var score_lbl: Label = get_node_or_null("VictoryOverlay/Card/Content/ScoreLine")
	if not score_lbl:
		return
	var score := _get_score()
	if score < 0:
		score_lbl.text = tr("Score pending")
		return
	_record_adventure_completion_if_ready()
	var optimal := _get_optimal_pours()
	var extra := _get_extra_pours()
	var platinum := score > SCORE_MAX
	score_lbl.add_theme_color_override("font_color", STAR_PLATINUM_COLOR if platinum else Color(1.0, 0.86, 0.35))
	score_lbl.text = tr("Score %s | Goal %d | Extra %s") % [_format_score(score), optimal, _format_pours(extra)]
	var bonus := _get_beaker_bonus_score()
	if bonus > 0:
		score_lbl.text += tr("  |  Bonus: +%s") % _format_score(bonus)
	if _mulligans_used > 0:
		score_lbl.text += tr("  |  Undo: +%s") % _format_pours(_get_mulligan_pour_penalty())
	if _cheats_used > 0:
		score_lbl.text += _format_recovery_cheat_penalty(true)
	var star_row: HBoxContainer = get_node_or_null("VictoryOverlay/Card/Content/StarRow")
	if star_row and not _victory_stars_shown:
		_victory_stars_shown = true
		_populate_star_row(star_row, _get_star_count(score), true, platinum)

func _record_adventure_completion_if_ready() -> bool:
	if _adventure_completion_recorded or not _is_adventure_active():
		return false
	var score := -1
	var stars := 1
	if AdventureManager.is_current_chill():
		stars = AdventureManager.get_current_chill_stars()
	else:
		score = _get_score()
		if score < 0:
			return false
		stars = _get_star_count(score)
	AdventureManager.complete_current(moves, score, stars)
	_adventure_completion_recorded = true
	return true

func _add_chill_result_line(parent: VBoxContainer, text: String, modal_scale: float, color: Color) -> void:
	var label := Label.new()
	label.text = text
	_use_ui_text_font(label)
	label.add_theme_font_size_override("font_size", int(round(22.0 * modal_scale)))
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)

func _add_adventure_rank_progress_line(parent: VBoxContainer, modal_scale: float) -> void:
	var text := _format_adventure_rank_progress()
	if text == "":
		return
	var label := Label.new()
	label.text = text
	_use_ui_text_font(label)
	label.add_theme_font_size_override("font_size", int(round(19.0 * modal_scale)))
	label.add_theme_color_override("font_color", Color(0.76, 0.93, 1.0))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)

func _format_adventure_rank_progress() -> String:
	if not _is_adventure_active() or not AdventureManager.has_method("get_current_rank_progress"):
		return ""
	var progress: Dictionary = AdventureManager.call("get_current_rank_progress")
	if progress.is_empty():
		return ""
	var stars := int(progress.get("stars", 0))
	var max_stars := int(progress.get("max_stars", 0))
	var threshold := int(progress.get("threshold", 0))
	var puzzles_remaining := int(progress.get("puzzles_remaining", 0))
	if bool(progress.get("final_rank", false)):
		var final_text := tr("Final rank progress: %d/%d stars.") % [stars, max_stars]
		if puzzles_remaining > 0:
			final_text += " " + _format_adventure_remaining_puzzles(puzzles_remaining)
		return final_text

	var parts := PackedStringArray()
	parts.append(tr("Rank progress: %d/%d stars (threshold %d).") % [stars, max_stars, threshold])
	if puzzles_remaining > 0:
		parts.append(_format_adventure_remaining_puzzles(puzzles_remaining))
	var stars_remaining := int(progress.get("stars_remaining", 0))
	if stars_remaining > 0:
		parts.append(_format_adventure_remaining_stars(stars_remaining))
	if puzzles_remaining <= 0 and stars_remaining <= 0:
		parts.append(tr("Next rank unlocked."))
	return " ".join(parts)

func _format_adventure_remaining_puzzles(count: int) -> String:
	return tr("%d puzzle remaining for next rank.") % count if count == 1 else tr("%d puzzles remaining for next rank.") % count

func _format_adventure_remaining_stars(count: int) -> String:
	return tr("%d star remaining for next rank.") % count if count == 1 else tr("%d stars remaining for next rank.") % count

func _populate_star_row(row: HBoxContainer, stars: int, animate: bool, platinum: bool = false):
	var modal_scale := _get_result_modal_scale(get_viewport_rect().size)
	var metrics := _get_victory_star_metrics(modal_scale)
	var slot_width := float(metrics["slot_width"])
	var slot_height := float(metrics["slot_height"])
	var font_size := int(metrics["font_size"])
	var separation := int(metrics["separation"])
	var filled_color := STAR_PLATINUM_COLOR if platinum else STAR_GOLD_COLOR
	row.custom_minimum_size = Vector2(0, slot_height)
	row.add_theme_constant_override("separation", separation)
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	for i in 5:
		var filled := i < stars
		var star := Label.new()
		star.text = tr(STAR_FILLED_KEY) if filled else tr(STAR_EMPTY_KEY)
		star.custom_minimum_size = Vector2(slot_width, slot_height)
		star.pivot_offset = Vector2(slot_width * 0.5, slot_height * 0.5)
		star.add_theme_font_size_override("font_size", font_size)
		star.add_theme_color_override("font_color", filled_color if filled else STAR_EMPTY_COLOR)
		star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(star)
		if animate:
			star.modulate = Color(1, 1, 1, 0)
			star.scale = Vector2(0.1, 0.1)
		elif filled:
			Callable(self, "_start_earned_star_idle").call_deferred(star, i, platinum)
	if animate:
		Callable(self, "_animate_star_row").call_deferred(row, stars, platinum)

func _get_victory_star_metrics(modal_scale: float) -> Dictionary:
	var area := get_viewport_rect().size
	var margin := 14.0 * modal_scale
	var card_width := minf(860.0 * modal_scale, area.x - margin * 2.0)
	if _is_portrait(area):
		card_width = area.x - margin * 2.0
	var content_width := maxf(220.0 * modal_scale, card_width - 60.0 * modal_scale)
	var desired_separation := 14.0 * modal_scale
	var separation := clampf(desired_separation, 8.0 * modal_scale, maxf(8.0 * modal_scale, content_width * 0.040))
	var max_slot_width := maxf(38.0 * modal_scale, (content_width - separation * 4.0) / 5.0)
	var slot_width := minf(72.0 * modal_scale, max_slot_width)
	var slot_height := maxf(84.0 * modal_scale, slot_width * 1.14)
	var font_size := int(round(minf(64.0 * modal_scale, slot_width * 0.94)))
	return {
		"slot_width": slot_width,
		"slot_height": slot_height,
		"font_size": font_size,
		"separation": int(round(separation)),
	}

func _animate_star_row(row: HBoxContainer, stars: int, platinum: bool = false) -> void:
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
			tw.tween_callback(Callable(self, "_start_earned_star_idle").bind(star, i, platinum)).set_delay(delay + 0.66)
			_spawn_star_burst(landing_center, delay + 0.28, platinum)
			_schedule_star_boom(row, i, delay + 0.28)
		else:
			var delay := 0.42 + float(stars) * 0.13 + 0.18
			star.modulate = Color(1, 1, 1, 0)
			star.scale = Vector2(0.7, 0.7)
			tw.tween_property(star, "modulate", Color.WHITE, 0.20).set_delay(delay)
			tw.tween_property(star, "scale", Vector2(1.0, 1.0), 0.20).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _start_earned_star_idle(star: Label, star_index: int, platinum: bool = false) -> void:
	if not is_instance_valid(star):
		return
	star.scale = Vector2.ONE
	star.rotation = 0.0
	star.modulate = Color.WHITE
	var direction := -1.0 if star_index % 2 == 0 else 1.0
	var swing := deg_to_rad(5.5 + float(star_index % 3) * 1.4)
	var peak_scale := 1.18 + float(star_index % 2) * 0.040
	var hot_color := STAR_PLATINUM_IDLE_COLOR if platinum else STAR_GOLD_IDLE_COLOR
	var tw := star.create_tween().set_loops()
	tw.tween_property(star, "scale", Vector2(peak_scale, peak_scale), 0.46).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(star, "rotation", direction * swing, 0.46).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(star, "modulate", hot_color, 0.46).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(star, "scale", Vector2(1.02, 1.02), 0.52).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(star, "rotation", -direction * swing * 0.70, 0.52).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(star, "modulate", Color.WHITE, 0.52).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(star, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(star, "rotation", 0.0, 0.34).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _get_chill_cheats_summary() -> String:
	var used := PackedStringArray()
	if _mulligans_used > 0:
		used.append(tr("Undo x%d") % _mulligans_used if _mulligans_used > 1 else tr("Undo"))
	for cheat_type in ["extra_beaker", "stir", "swap", "pipette"]:
		var count := _get_cheat_use_count(cheat_type)
		if count <= 0:
			continue
		used.append(_get_recovery_cheat_display_name(cheat_type))
	return ", ".join(used)

func _get_chill_bonus_summary() -> String:
	var bonuses := _get_earned_beaker_bonus_counts()
	var earned := PackedStringArray()
	var prismatic_score := int(bonuses.get("prismatic_score", 0))
	if prismatic_score > 0:
		earned.append(tr("Prism +%s") % _format_score(prismatic_score))
	var tinted_score := int(bonuses.get("tinted_score", 0))
	if tinted_score > 0:
		earned.append(tr("Tint +%s") % _format_score(tinted_score))
	if earned.is_empty():
		var total := _get_beaker_bonus_score()
		if total > 0:
			earned.append(tr("Bonus +%s") % _format_score(total))
	return ", ".join(earned)

func _get_earned_beaker_bonus_counts() -> Dictionary:
	if not towers or not towers.has_method("get_earned_beaker_bonus_counts"):
		return {}
	var raw = towers.call("get_earned_beaker_bonus_counts")
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return raw

func _get_recovery_cheat_display_name(cheat_type: String) -> String:
	if cheat_type == "extra_beaker":
		return tr("Extra")
	if cheat_type == "pipette":
		return tr("Transfer")
	if cheat_type == "swap":
		return tr("Swap")
	if cheat_type == "stir":
		return tr("Stir")
	return tr("Cheat")

func _schedule_star_boom(row: HBoxContainer, star_index: int, delay: float) -> void:
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		if not is_instance_valid(row):
			return
		if AudioManager and AudioManager.has_method("play_star_boom"):
			AudioManager.play_star_boom(star_index)
	)

func _spawn_star_burst(global_center: Vector2, delay: float, platinum: bool = false) -> void:
	var fx_layer := get_node_or_null("VictoryOverlay/Card/StarFxLayer") as Control
	if not fx_layer:
		return
	var modal_scale := _get_result_modal_scale(get_viewport_rect().size)
	var local_center := fx_layer.get_global_transform().affine_inverse() * global_center
	_spawn_star_flash(fx_layer, local_center, delay, platinum)
	for n in 16:
		var spark := Label.new()
		spark.text = tr(STAR_SPARK_KEY)
		spark.custom_minimum_size = Vector2(18.0 * modal_scale, 18.0 * modal_scale)
		spark.pivot_offset = Vector2(9.0 * modal_scale, 9.0 * modal_scale)
		spark.position = local_center - Vector2(9.0 * modal_scale, 9.0 * modal_scale)
		spark.rotation = randf_range(-0.6, 0.6)
		spark.scale = Vector2(randf_range(0.65, 1.15), randf_range(0.65, 1.15))
		spark.modulate = Color(1, 1, 1, 0)
		spark.add_theme_font_size_override("font_size", int(round(randf_range(12.0, 22.0) * modal_scale)))
		if platinum:
			spark.add_theme_color_override("font_color", Color(randf_range(0.76, 0.95), randf_range(0.90, 1.0), 1.0))
		else:
			spark.add_theme_color_override("font_color", Color(1.0, randf_range(0.66, 0.95), randf_range(0.12, 0.36)))
		fx_layer.add_child(spark)
		var angle := TAU * float(n) / 16.0 + randf_range(-0.16, 0.16)
		var distance := randf_range(48.0, 118.0) * modal_scale
		var target := local_center + Vector2(cos(angle), sin(angle)) * distance - Vector2(9.0 * modal_scale, 9.0 * modal_scale)
		var spark_tw := create_tween().set_parallel()
		spark_tw.tween_property(spark, "modulate", Color.WHITE, 0.05).set_delay(delay)
		spark_tw.tween_property(spark, "modulate", Color(1, 1, 1, 0), 0.32).set_delay(delay + 0.10)
		spark_tw.tween_property(spark, "position", target, 0.42).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		spark_tw.tween_property(spark, "scale", Vector2(0.1, 0.1), 0.42).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		spark_tw.tween_property(spark, "rotation", randf_range(-4.0, 4.0), 0.42).set_delay(delay)
		spark_tw.chain().tween_callback(spark.queue_free)

func _spawn_star_flash(parent: Control, center: Vector2, delay: float, platinum: bool = false) -> void:
	var modal_scale := _get_result_modal_scale(get_viewport_rect().size)
	var flash := ColorRect.new()
	flash.color = Color(0.72, 0.92, 1.0, 0.34) if platinum else Color(1.0, 0.78, 0.12, 0.34)
	flash.size = Vector2(20.0 * modal_scale, 20.0 * modal_scale)
	flash.pivot_offset = Vector2(10.0 * modal_scale, 10.0 * modal_scale)
	flash.position = center - Vector2(10.0 * modal_scale, 10.0 * modal_scale)
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

func _on_cracked_beaker_shattered(_beaker_idx: int) -> void:
	_shatter_loss_locked = true
	var shatter_generation := _shatter_loss_generation
	moves += 1
	_score_forced_zero = true
	_recovery_cheats_available_for_loss = false
	_last_recovery_loss_title = ""
	_last_recovery_loss_detail = ""
	update_move_counter()
	update_possible_moves_label()
	update_goal_label()
	_update_music_pressure()
	_update_mulligan_button()
	if towers:
		towers.set_process_input(false)
		if towers.has_method("clear_pointer_state"):
			towers.call("clear_pointer_state")
	await get_tree().create_timer(1.35).timeout
	if shatter_generation != _shatter_loss_generation:
		return
	if get_node_or_null("VictoryOverlay") or get_node_or_null("LoseOverlay"):
		return
	if towers and towers.has_method("is_beaker_empty") and not bool(towers.call("is_beaker_empty", _beaker_idx)):
		return
	_show_loss(tr(SHATTERED_TITLE_KEY), tr("Cracked beaker shattered."), false, false)

func _check_for_no_moves():
	if not towers.has_method("has_available_moves"):
		return
	if towers.check_complete():
		_set_cheats_attention(false)
		return
	if towers.has_method("is_only_cracked_blocking_completion") and bool(towers.call("is_only_cracked_blocking_completion")):
		_set_cheats_attention(false)
		_show_loss(tr("CRACKED NOT EMPTY"), tr("Cracked must end empty."), true)
		return
	if bool(towers.call("has_available_moves")):
		_set_cheats_attention(false)
		return
	update_possible_moves_label()
	if _has_affordable_cheat_available():
		_set_cheats_attention(true)
		return
	_set_cheats_attention(false)
	_show_loss(tr("NO MOVES"), tr("No legal pours remain."), true)

func _show_loss(title: String, detail: String, allow_recovery_cheats: bool = false, play_loss_sfx: bool = true):
	if get_node_or_null("VictoryOverlay") or get_node_or_null("LoseOverlay"):
		return
	_recovery_cheats_available_for_loss = allow_recovery_cheats
	_last_recovery_loss_title = title if allow_recovery_cheats else ""
	_last_recovery_loss_detail = detail if allow_recovery_cheats else ""
	_score_forced_zero = true
	update_goal_label()
	update_possible_moves_label()
	if AudioManager and play_loss_sfx:
		AudioManager.play_loss()
	if AudioManager and AudioManager.has_method("play_failed_music"):
		AudioManager.play_failed_music()
	show_loss_screen(title, detail)

func show_loss_screen(title: String, detail: String):
	var cl := CanvasLayer.new()
	cl.name = "LoseOverlay"
	cl.layer = 10
	add_child(cl)
	_refresh_towers_input_enabled()

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	cl.add_child(bg)

	var card := ColorRect.new()
	var area := get_viewport_rect().size
	var portrait := _is_portrait(area)
	var modal_scale := _get_result_modal_scale(area)
	var margin := 14.0 * modal_scale
	var card_width := minf(860.0 * modal_scale, maxf(320.0 * modal_scale, area.x - margin * 2.0))
	var card_height := minf(470.0 * modal_scale, area.y - margin * 2.0)
	if portrait:
		card_width = area.x - margin * 2.0
		card_height = minf(660.0 * modal_scale, area.y - margin * 2.0)
	card.color = Color(0.08, 0.10, 0.18, 0.97)
	card.custom_minimum_size = Vector2(card_width, card_height)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left   = -card_width * 0.5
	card.offset_top    = -card_height * 0.5
	card.offset_right  =  card_width * 0.5
	card.offset_bottom =  card_height * 0.5
	card.pivot_offset  = Vector2(card_width * 0.5, card_height * 0.5)
	card.scale         = Vector2(0.05, 0.05)
	cl.add_child(card)

	var stripe := ColorRect.new()
	stripe.color = Color(0.95, 0.22, 0.28, 1.0)
	stripe.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stripe.offset_bottom = maxf(6.0, 6.0 * modal_scale)
	card.add_child(stripe)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 32.0 * modal_scale
	vb.offset_top = 18.0 * modal_scale
	vb.offset_right = -32.0 * modal_scale
	vb.offset_bottom = -18.0 * modal_scale
	vb.add_theme_constant_override("separation", int(round(10.0 * modal_scale)))
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vb)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", int(round(48.0 * modal_scale)))
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.42, 0.48))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title_lbl)

	var detail_lbl := Label.new()
	detail_lbl.text = detail
	_use_ui_text_font(detail_lbl)
	detail_lbl.add_theme_font_size_override("font_size", int(round(22.0 * modal_scale)))
	detail_lbl.add_theme_color_override("font_color", Color(0.82, 0.88, 1.0))
	detail_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(detail_lbl)

	var optimal := _get_optimal_pours()
	if _score_forced_zero and not _is_chill_mode():
		var goal_lbl := Label.new()
		goal_lbl.text = tr("Score: %s") % _format_score(_get_score())
		if optimal >= 0:
			goal_lbl.text = tr("Goal %d | Limit %d | %s") % [optimal, _get_pour_limit(), goal_lbl.text]
		if _mulligans_used > 0:
			goal_lbl.text += tr("  |  Undo: +%s") % _format_pours(_get_mulligan_pour_penalty())
		if _cheats_used > 0:
			goal_lbl.text += _format_recovery_cheat_penalty(true)
		_use_ui_text_font(goal_lbl)
		goal_lbl.add_theme_font_size_override("font_size", int(round(20.0 * modal_scale)))
		goal_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
		goal_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		goal_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		goal_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(goal_lbl)
	elif optimal >= 0 and not _is_chill_mode():
		var goal_lbl := Label.new()
		goal_lbl.text = tr("Goal %d | Limit %d | Score %s") % [optimal, _get_pour_limit(), _format_score(_get_score())]
		if _mulligans_used > 0:
			goal_lbl.text += tr("  |  Undo: +%s") % _format_pours(_get_mulligan_pour_penalty())
		if _cheats_used > 0:
			goal_lbl.text += _format_recovery_cheat_penalty(true)
		_use_ui_text_font(goal_lbl)
		goal_lbl.add_theme_font_size_override("font_size", int(round(20.0 * modal_scale)))
		goal_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
		goal_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		goal_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		goal_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(goal_lbl)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8.0 * modal_scale)
	vb.add_child(spacer)

	var hb := GridContainer.new()
	hb.columns = 2 if portrait else 4
	_style_result_button_grid(hb, portrait, modal_scale, card_width)
	vb.add_child(hb)

	_add_result_button(hb, tr("Retry"), 104.0, retry_game)
	_add_result_button(hb, tr("New"), 104.0, reset_game)

	if _can_use_mulligan():
		var mulligan_btn := Button.new()
		_style_result_button(mulligan_btn, _get_undo_button_text(), 130.0, use_mulligan)
		var badge := _create_mulligan_badge()
		badge.text = str(_get_mulligans_remaining())
		badge.tooltip_text = tr("Undos left: %d") % _get_mulligans_remaining()
		mulligan_btn.add_child(badge)
		hb.add_child(mulligan_btn)

	if _recovery_cheats_available_for_loss and _can_use_extra_beaker_cheat():
		var extra_btn := Button.new()
		_style_result_button(extra_btn, _get_extra_beaker_button_text(), 124.0, use_extra_beaker_cheat)
		hb.add_child(extra_btn)

	if _can_use_recovery_cheat():
		if towers.has_method("has_usable_stir_cheat") and bool(towers.call("has_usable_stir_cheat")):
			var stir_btn := Button.new()
			_style_result_button(stir_btn, _get_recovery_cheat_button_text("stir"), 112.0, start_stir_cheat)
			hb.add_child(stir_btn)
		if towers.has_method("has_usable_swap_cheat") and bool(towers.call("has_usable_swap_cheat")):
			var swap_btn := Button.new()
			_style_result_button(swap_btn, _get_recovery_cheat_button_text("swap"), 116.0, start_swap_cheat)
			hb.add_child(swap_btn)
		if towers.has_method("has_usable_pipette_cheat") and bool(towers.call("has_usable_pipette_cheat")):
			var pipette_btn := Button.new()
			_style_result_button(pipette_btn, _get_recovery_cheat_button_text("pipette"), 132.0, start_pipette_cheat)
			hb.add_child(pipette_btn)

	_add_result_button(hb, tr("Board"), 110.0, _return_to_board_from_result)
	_add_result_button(hb, tr("Menu"), 104.0, go_to_menu)

	var tw := create_tween().set_parallel()
	tw.tween_property(bg,   "color", Color(0, 0, 0, 0.72), 0.35)
	tw.tween_property(card, "scale", Vector2(1, 1),         0.50) \
	  .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _add_result_button(parent: Control, text: String, min_width: float, callback: Callable) -> Button:
	var button := Button.new()
	_style_result_button(button, text, min_width, callback)
	parent.add_child(button)
	return button

func _style_result_button_grid(grid: GridContainer, portrait: bool, modal_scale: float, card_width: float) -> void:
	if portrait:
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.custom_minimum_size.x = maxf(0.0, card_width - 64.0 * modal_scale)
	else:
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", int(round((18.0 if portrait else 14.0) * modal_scale)))
	grid.add_theme_constant_override("v_separation", int(round((18.0 if portrait else 12.0) * modal_scale)))

func _style_result_button(button: Button, text: String, min_width: float, callback: Callable) -> void:
	var modal_scale := _get_result_modal_scale(get_viewport_rect().size)
	var portrait := _is_portrait(get_viewport_rect().size)
	var touch_scale := modal_scale * (1.18 if portrait else 1.0)
	button.text = text
	button.tooltip_text = text
	_use_ui_text_font(button)
	button.autowrap_mode = TextServer.AUTOWRAP_OFF
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", int(round((22.0 if portrait else 18.0) * touch_scale)))
	button.custom_minimum_size = Vector2(min_width * touch_scale, (68.0 if portrait else 44.0) * touch_scale)
	_apply_button_chrome(button, touch_scale, "action")
	button.pressed.connect(callback)

func _return_to_board_from_result() -> void:
	_clear_result_overlays()
	if AudioManager:
		AudioManager.play_click()

func _go_to_next_adventure_puzzle() -> void:
	if not _is_adventure_active():
		reset_game(false)
		return
	var next_puzzle := AdventureManager.get_next_puzzle_after_current()
	if next_puzzle.is_empty():
		go_to_menu()
		return
	if not AdventureManager.start_puzzle(
			str(next_puzzle["adventure_id"]),
			int(next_puzzle["block_index"]),
			int(next_puzzle["puzzle_index"])):
		if AudioManager:
			AudioManager.play_invalid()
		return
	reset_game(false)

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

func _sync_beaker_count_controls() -> void:
	var filled := GameSettings.get_filled_beaker_count()
	var empty := maxi(_get_empty_beaker_setting_min(), GameSettings.get_empty_beaker_count())
	if empty != GameSettings.get_empty_beaker_count() or filled > _get_filled_beaker_setting_max(empty):
		filled = mini(filled, _get_filled_beaker_setting_max(empty))
		GameSettings.set_beaker_counts(filled, empty)
	if filled_beakers_slider:
		filled_beakers_slider.min_value = 1.0
		filled_beakers_slider.max_value = float(_get_filled_beaker_setting_max(empty))
		filled_beakers_slider.value = filled
	if filled_beakers_value:
		filled_beakers_value.text = str(filled)
	if empty_beakers_slider:
		empty_beakers_slider.min_value = float(_get_empty_beaker_setting_min())
		empty_beakers_slider.max_value = float(_get_empty_beaker_setting_max(filled))
		empty_beakers_slider.value = empty
	if empty_beakers_value:
		empty_beakers_value.text = str(empty)

func _on_filled_beakers_changed(value: float):
	if not filled_beakers_slider:
		return
	var filled := clampi(int(round(value)), 1, _get_filled_beaker_setting_max())
	if _syncing_settings_ui:
		if filled_beakers_value:
			filled_beakers_value.text = str(filled)
		return
	if filled == GameSettings.get_filled_beaker_count():
		return
	GameSettings.set_beaker_counts(filled, GameSettings.get_empty_beaker_count())
	_syncing_settings_ui = true
	_sync_beaker_count_controls()
	_sync_difficulty_buttons()
	_syncing_settings_ui = false
	if _settings_ready:
		if AudioManager:
			AudioManager.play_select()
		reset_game(false)

func _on_empty_beakers_changed(value: float):
	if not empty_beakers_slider:
		return
	var empty := clampi(int(round(value)), _get_empty_beaker_setting_min(), _get_empty_beaker_setting_max())
	if _syncing_settings_ui:
		if empty_beakers_value:
			empty_beakers_value.text = str(empty)
		return
	if empty == GameSettings.get_empty_beaker_count():
		return
	GameSettings.set_beaker_counts(GameSettings.get_filled_beaker_count(), empty)
	_syncing_settings_ui = true
	_sync_beaker_count_controls()
	_sync_difficulty_buttons()
	_syncing_settings_ui = false
	if _settings_ready:
		if AudioManager:
			AudioManager.play_select()
		reset_game(false)

func _on_show_goal_toggled(button_pressed: bool):
	GameSettings.set_show_goal_hint(button_pressed)
	if _settings_ready and AudioManager:
		AudioManager.play_select()
	update_goal_label()

func _on_chill_mode_toggled(button_pressed: bool) -> void:
	if button_pressed == GameSettings.chill_mode:
		if goal_toggle:
			goal_toggle.disabled = button_pressed
		return
	GameSettings.set_chill_mode(button_pressed)
	if goal_toggle:
		goal_toggle.disabled = button_pressed
	_solver_progress_text = ""
	update_goal_label()
	_update_mulligan_button()
	_update_music_pressure()
	if _settings_ready and not _syncing_settings_ui:
		if AudioManager:
			AudioManager.play_select()
		reset_game(false)

func _on_special_beakers_toggled(button_pressed: bool) -> void:
	if button_pressed == GameSettings.special_beakers_enabled:
		return
	GameSettings.set_special_beakers_enabled(button_pressed)
	_update_responsive_layout()
	if _settings_ready:
		if AudioManager:
			AudioManager.play_select()
		reset_game(false)

func _on_palette_selected(index: int) -> void:
	if not palette_option:
		return
	var key := str(palette_option.get_item_metadata(index))
	GameSettings.set_liquid_palette(key)
	_sync_palette_option()
	if _settings_ready and AudioManager:
		AudioManager.play_select()
	if towers and towers.has_method("queue_redraw"):
		towers.queue_redraw()

func _on_palette_button_pressed(key: String) -> void:
	if key == GameSettings.liquid_palette:
		_sync_palette_option()
		return
	GameSettings.set_liquid_palette(key)
	_sync_palette_option()
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

func _on_symbol_set_selected(index: int) -> void:
	if not symbol_set_option:
		return
	var key := str(symbol_set_option.get_item_metadata(index))
	GameSettings.set_liquid_symbol_set(key)
	if _settings_ready and AudioManager:
		AudioManager.play_select()
	if towers and towers.has_method("queue_redraw"):
		towers.queue_redraw()

func _on_symbol_set_button_pressed(key: String) -> void:
	if key == GameSettings.liquid_symbol_set:
		_sync_symbol_set_option()
		return
	GameSettings.set_liquid_symbol_set(key)
	_sync_symbol_set_option()
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
	if AdventureManager:
		AdventureManager.clear_current_puzzle()
	_clear_result_overlays()
	_score_forced_zero = false
	_recovery_cheats_available_for_loss = false
	_last_recovery_loss_title = ""
	_last_recovery_loss_detail = ""
	_mulligans_used = 0
	_reset_cheat_tracking()
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
		_syncing_settings_ui = true
		_sync_beaker_count_controls()
		_syncing_settings_ui = false
		return
	GameSettings.set_difficulty(value)
	_syncing_settings_ui = true
	_sync_beaker_count_controls()
	_syncing_settings_ui = false
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
	if palette_option:
		palette_option.clear()
		var selected_idx := 0
		for key in GameSettings.LIQUID_PALETTE_ORDER:
			var idx := palette_option.get_item_count()
			palette_option.add_item(GameSettings.get_liquid_palette_label(key))
			palette_option.set_item_metadata(idx, key)
			if key == GameSettings.liquid_palette:
				selected_idx = idx
		palette_option.select(selected_idx)
	for key in palette_buttons:
		var button := palette_buttons[key] as Button
		if button:
			button.button_pressed = key == GameSettings.liquid_palette

func _sync_symbol_set_option() -> void:
	if symbol_set_option:
		symbol_set_option.clear()
		var selected_idx := 0
		for key in GameSettings.LIQUID_SYMBOL_SET_ORDER:
			var idx := symbol_set_option.get_item_count()
			symbol_set_option.add_item(GameSettings.get_liquid_symbol_set_label(key))
			symbol_set_option.set_item_metadata(idx, key)
			if key == GameSettings.liquid_symbol_set:
				selected_idx = idx
		symbol_set_option.select(selected_idx)
	for key in symbol_set_buttons:
		var button := symbol_set_buttons[key] as Button
		if button:
			button.button_pressed = key == GameSettings.liquid_symbol_set

func _can_use_recovery_cheat() -> bool:
	return _can_start_recovery_cheat("stir") or _can_start_recovery_cheat("swap") or _can_start_recovery_cheat("pipette")

func _has_affordable_cheat_available() -> bool:
	return (_can_use_mulligan()
			or _can_use_extra_beaker_cheat()
			or _can_start_recovery_cheat("stir")
			or _can_start_recovery_cheat("swap")
			or _can_start_recovery_cheat("pipette"))

func _can_use_cheat_with_penalty(penalty: float, cheat_type: String = "") -> bool:
	if cheat_type != "" and _get_cheat_use_count(cheat_type) >= CHEAT_MAX_USES:
		return false
	if _would_exceed_pour_limit(penalty):
		return false
	if _shatter_loss_locked:
		return false
	if not towers or towers.check_complete():
		return false
	if towers.has_method("is_choosing_cheat") and bool(towers.call("is_choosing_cheat")):
		return false
	return true

func _can_start_recovery_cheat(cheat_type: String) -> bool:
	if not _can_use_cheat_with_penalty(_get_recovery_cheat_pour_penalty(cheat_type), cheat_type):
		return false
	if cheat_type == "stir":
		return towers.has_method("has_usable_stir_cheat") and bool(towers.call("has_usable_stir_cheat"))
	if cheat_type == "swap":
		return towers.has_method("has_usable_swap_cheat") and bool(towers.call("has_usable_swap_cheat"))
	if cheat_type == "pipette":
		return towers.has_method("has_usable_pipette_cheat") and bool(towers.call("has_usable_pipette_cheat"))
	return false

func _get_recovery_cheat_pour_penalty(cheat_type: String) -> float:
	if _is_chill_mode():
		return 0.0
	if cheat_type == "pipette":
		return PIPETTE_CHEAT_POUR_PENALTY
	if cheat_type == "swap":
		return SWAP_CHEAT_POUR_PENALTY
	return STIR_CHEAT_POUR_PENALTY

func _can_use_extra_beaker_cheat() -> bool:
	if not _is_chill_mode() and _get_optimal_pours() < 0:
		return false
	if not _can_use_cheat_with_penalty(_get_extra_beaker_pour_penalty(), "extra_beaker"):
		return false
	return towers.has_method("can_add_empty_beaker") and bool(towers.call("can_add_empty_beaker"))

func start_stir_cheat() -> void:
	_start_recovery_cheat("stir")

func start_swap_cheat() -> void:
	_start_recovery_cheat("swap")

func start_pipette_cheat() -> void:
	_start_recovery_cheat("pipette")

func _start_recovery_cheat(cheat_type: String) -> void:
	if not _can_start_recovery_cheat(cheat_type):
		if AudioManager:
			AudioManager.play_invalid()
		return
	var started := false
	if cheat_type == "stir" and towers.has_method("begin_stir_cheat"):
		started = bool(towers.call("begin_stir_cheat"))
	elif cheat_type == "swap" and towers.has_method("begin_swap_cheat"):
		started = bool(towers.call("begin_swap_cheat"))
	elif cheat_type == "pipette" and towers.has_method("begin_pipette_cheat"):
		started = bool(towers.call("begin_pipette_cheat"))
	if not started:
		if AudioManager:
			AudioManager.play_invalid()
		return
	_clear_result_overlays()
	_set_cheat_status(cheat_type)
	_update_mulligan_button()
	_sync_cheats_button_label()
	if AudioManager:
		AudioManager.play_select()

func use_extra_beaker_cheat() -> void:
	if not _can_use_extra_beaker_cheat():
		if AudioManager:
			AudioManager.play_invalid()
		return
	var penalty := _get_extra_beaker_pour_penalty()
	if not bool(towers.call("add_empty_beaker")):
		if AudioManager:
			AudioManager.play_invalid()
		return
	_record_cheat_use("extra_beaker", penalty)
	_score_forced_zero = false
	_recovery_cheats_available_for_loss = false
	_last_recovery_loss_title = ""
	_last_recovery_loss_detail = ""
	_clear_result_overlays()
	_restore_instruction_label()
	update_possible_moves_label()
	update_goal_label()
	_reset_stalemate_tracker()
	_update_mulligan_button()
	_update_music_pressure()
	if AudioManager:
		AudioManager.play_select()
	if _is_pour_limit_exceeded():
		_show_pour_limit_loss()
	elif towers.check_complete():
		_show_victory_delayed()
	else:
		_check_for_no_moves.call_deferred()

func _set_cheat_status(cheat_type: String) -> void:
	if not instructions_label:
		return
	if cheat_type == "stir":
		instructions_label.text = tr("Cheat: choose a mixed beaker.")
	elif cheat_type == "swap":
		instructions_label.text = tr("Cheat: choose adjacent segments.")
	elif cheat_type == "pipette":
		instructions_label.text = tr("Cheat: choose liquid to pipette.")

func _restore_instruction_label() -> void:
	if instructions_label and _is_adventure_active():
		var title := AdventureManager.get_current_title()
		if title != "":
			instructions_label.text = title
			return
	if instructions_label and _default_instructions_text != "":
		instructions_label.text = tr(_default_instructions_text)

func _on_cheat_applied(_cheat_type: String) -> void:
	_record_cheat_use(_cheat_type, _get_recovery_cheat_pour_penalty(_cheat_type))
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
	_sync_cheats_button_label()
	_update_music_pressure()
	if _is_pour_limit_exceeded():
		_show_pour_limit_loss()
	elif towers.check_complete():
		_show_victory_delayed()
	else:
		_check_for_no_moves.call_deferred()

func _on_cheat_cancelled() -> void:
	_restore_instruction_label()
	_update_mulligan_button()
	_sync_cheats_button_label()
	if _recovery_cheats_available_for_loss and _last_recovery_loss_title != "":
		show_loss_screen(_last_recovery_loss_title, _last_recovery_loss_detail)
		return
	_check_for_no_moves.call_deferred()

func _is_choosing_cheat() -> bool:
	return towers != null and towers.has_method("is_choosing_cheat") and bool(towers.call("is_choosing_cheat"))

func _sync_cheats_button_label() -> void:
	if not cheats_button:
		return
	var text := tr("Cancel") if _is_choosing_cheat() else tr("Cheats")
	cheats_button.text = text
	cheats_button.tooltip_text = text

func _can_use_mulligan() -> bool:
	return (_get_mulligans_remaining() > 0
			and towers != null
			and not _would_mulligan_exceed_pour_limit()
			and not towers.check_complete()
			and not _is_choosing_cheat()
			and towers.has_method("can_undo_last_pour")
			and bool(towers.call("can_undo_last_pour")))

func _get_mulligans_remaining() -> int:
	return maxi(0, MULLIGAN_MAX_USES - _mulligans_used)

func _update_mulligan_button():
	if mulligan_button:
		mulligan_button.text = _get_undo_button_text()
		mulligan_button.disabled = not _can_use_mulligan()
		if mulligan_badge:
			mulligan_badge.text = str(_get_mulligans_remaining())
			mulligan_badge.tooltip_text = tr("Undos left: %d") % _get_mulligans_remaining()
	_update_extra_beaker_button()
	_sync_cheats_attention()

func _should_emphasize_cheats() -> bool:
	if not cheats_button or not towers:
		return false
	if not _has_water_sort_settings():
		return false
	if cheats_overlay != null and cheats_overlay.visible:
		return false
	if _has_result_overlay() or _shatter_loss_locked:
		return false
	if towers.check_complete():
		return false
	if towers.has_method("is_choosing_cheat") and bool(towers.call("is_choosing_cheat")):
		return false
	if not towers.has_method("has_available_moves"):
		return false
	if bool(towers.call("has_available_moves")):
		return false
	return _has_affordable_cheat_available()

func _sync_cheats_attention() -> void:
	_set_cheats_attention(_should_emphasize_cheats())

func _set_cheats_attention(active: bool) -> void:
	_cheats_attention_active = active
	if not cheats_button:
		return
	_ensure_cheats_attention_frame()
	if _cheats_attention_frame:
		_cheats_attention_frame.visible = active and cheats_button.visible

func _ensure_cheats_attention_frame() -> void:
	if not cheats_button:
		return
	var frame := cheats_button.get_node_or_null(CHEATS_ATTENTION_FRAME_NAME) as Control
	if not frame:
		frame = PrismaticButtonFrame.new()
		frame.name = CHEATS_ATTENTION_FRAME_NAME
		cheats_button.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 0.0
	frame.offset_top = 0.0
	frame.offset_right = 0.0
	frame.offset_bottom = 0.0
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set("phase_offset", 2.35)
	frame.set("intensity", 1.35)
	frame.visible = _cheats_attention_active and cheats_button.visible
	frame.move_to_front()
	_cheats_attention_frame = frame

func _update_extra_beaker_button() -> void:
	if not extra_beaker_button:
		return
	extra_beaker_button.text = _get_extra_beaker_button_text()
	extra_beaker_button.disabled = not _can_use_extra_beaker_cheat()
	extra_beaker_button.tooltip_text = extra_beaker_button.text

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
	call_deferred("_refresh_towers_input_enabled")

func _record_cheat_use(cheat_type: String, penalty: float) -> void:
	_cheats_used += 1
	_recovery_cheat_pour_penalty += penalty
	_recovery_cheat_kind = cheat_type
	_cheat_use_counts[cheat_type] = _get_cheat_use_count(cheat_type) + 1

func _get_cheat_use_count(cheat_type: String) -> int:
	return int(_cheat_use_counts.get(cheat_type, 0))

func _reset_cheat_tracking() -> void:
	_cheats_used = 0
	_cheat_use_counts.clear()
	_recovery_cheat_pour_penalty = 0.0
	_recovery_cheat_kind = ""

func retry_game(play_sound: bool = true):
	if play_sound and AudioManager:
		AudioManager.play_click()
	if towers.has_method("cancel_cheat"):
		towers.call("cancel_cheat", false)
	_sync_cheats_button_label()
	_restore_instruction_label()
	_clear_result_overlays()
	_score_forced_zero = false
	_recovery_cheats_available_for_loss = false
	_last_recovery_loss_title = ""
	_last_recovery_loss_detail = ""
	_shatter_loss_locked = false
	_shatter_loss_generation += 1
	_mulligans_used = 0
	_reset_cheat_tracking()
	moves = 0
	update_move_counter()
	if towers.has_method("retry_current_puzzle") and bool(towers.call("retry_current_puzzle")):
		_update_adventure_instruction_label()
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
	call_deferred("_refresh_towers_input_enabled")

func reset_game(play_sound: bool = true):
	if play_sound and AudioManager:
		AudioManager.play_click()
	if towers.has_method("cancel_cheat"):
		towers.call("cancel_cheat", false)
	_sync_cheats_button_label()
	_restore_instruction_label()
	_clear_result_overlays()
	_score_forced_zero = false
	_recovery_cheats_available_for_loss = false
	_last_recovery_loss_title = ""
	_last_recovery_loss_detail = ""
	_shatter_loss_locked = false
	_shatter_loss_generation += 1
	_mulligans_used = 0
	_reset_cheat_tracking()
	moves = 0
	update_move_counter()
	if not (_is_adventure_active() and _load_current_adventure_puzzle(true)):
		towers.reset()
	update_possible_moves_label()
	update_goal_label()
	_reset_stalemate_tracker()
	_update_mulligan_button()
	_update_music_pressure()
	_check_for_no_moves.call_deferred()
	call_deferred("_refresh_towers_input_enabled")

func _clear_result_overlays():
	var removed_overlay := false
	for overlay_name in ["VictoryOverlay", "LoseOverlay"]:
		var overlay = get_node_or_null(overlay_name)
		if overlay:
			removed_overlay = true
			overlay.queue_free()
	if removed_overlay:
		call_deferred("_refresh_towers_input_enabled")
	else:
		_refresh_towers_input_enabled()

func go_to_menu():
	if AudioManager:
		AudioManager.play_click()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
