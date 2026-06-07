extends Node2D

const SCORE_MAX := 1000
const REPEATED_STATE_LOSS_COUNT := 3
const MULLIGAN_POUR_PENALTY := 0.5
const MULLIGAN_MAX_USES := 4
const CHEAT_POUR_PENALTY := 2.0
const CHEAT_MAX_USES := 1
const EXTRA_BEAKER_PENALTY_RATIO := 0.35
const EXTRA_BEAKER_MIN_PENALTY := 4.0
const OPTIMAL_SOLVER_CALCULATING := -2
const STAR_FILLED := "★"
const STAR_EMPTY := "☆"
const STAR_SPARK := "✦"
const UI_MARGIN := 20.0
const UI_BUTTON_HEIGHT := 40.0
const UI_BUTTON_GAP := 12.0
const PORTRAIT_ASPECT_THRESHOLD := 1.08
const PORTRAIT_REFERENCE_WIDTH := 460.0
const MOBILE_UI_SCALE_MIN := 1.55

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
var difficulty_buttons := {}
var symbol_set_buttons := {}
var mulligan_badge: Label

var moves = 0
var _settings_ready := false
var _syncing_settings_ui := false
var _state_visits := {}
var _mulligans_used := 0
var _cheats_used := 0
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
	_build_mulligan_badge()
	get_viewport().size_changed.connect(_update_responsive_layout)
	_update_responsive_layout()
	_load_pending_board_code_if_any()
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

func _load_pending_board_code_if_any() -> void:
	if not GameSettings.has_method("consume_pending_board_code"):
		return
	var code := str(GameSettings.call("consume_pending_board_code")).strip_edges()
	if code == "":
		return
	if towers.has_method("import_board_code") and bool(towers.call("import_board_code", code)):
		return
	push_warning("Pending board code failed to load.")

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
	var margin := UI_MARGIN * ui_scale
	var button_height := UI_BUTTON_HEIGHT * ui_scale
	var button_gap := UI_BUTTON_GAP * ui_scale
	var top_safe := _get_top_safe_padding(area, ui_scale)

	_set_font_size(move_counter, 22, ui_scale)
	_set_font_size(goal_label, 18, ui_scale)
	_set_font_size(possible_moves_label, 18, ui_scale)
	_set_full_width_label(move_counter, top_safe + 8.0 * ui_scale, 30.0 * ui_scale)
	_set_full_width_label(goal_label, top_safe + 36.0 * ui_scale, 26.0 * ui_scale)
	_set_full_width_label(possible_moves_label, top_safe + 64.0 * ui_scale, 26.0 * ui_scale)

	var hidden_action_buttons := [new_puzzle_button, retry_button, extra_beaker_button, mulligan_button, menu_button]
	for control in hidden_action_buttons:
		if control:
			control.visible = false
	if settings_button:
		settings_button.visible = true
	if cheats_button:
		cheats_button.visible = true
	var action_buttons := [settings_button, cheats_button]
	_style_action_buttons(action_buttons, ui_scale)

	var play_top := 108.0 * ui_scale
	var play_bottom := area.y - 28.0
	var columns := 2
	var button_width := minf(270.0 * ui_scale, (area.x - margin * 2.0 - button_gap * float(columns - 1)) / float(columns))
	var controls_width := button_width * float(columns) + button_gap * float(columns - 1)
	var controls_top := area.y - button_height - margin
	_layout_button_grid(action_buttons, columns,
			Rect2((area.x - controls_width) * 0.5, controls_top, controls_width, button_height),
			button_height, button_gap)
	play_top = top_safe + (100.0 if portrait else 92.0) * ui_scale
	play_bottom = controls_top - 18.0 * ui_scale

	_set_towers_play_area(0.0, play_top, area.x, maxf(260.0 * ui_scale, play_bottom - play_top))

func _layout_hanoi_ui(area: Vector2) -> void:
	var portrait := _is_portrait(area)
	var ui_scale := _get_ui_scale(area)
	var margin := UI_MARGIN * ui_scale
	var button_height := UI_BUTTON_HEIGHT * ui_scale
	var button_gap := UI_BUTTON_GAP * ui_scale
	var top_safe := _get_top_safe_padding(area, ui_scale)
	if cheats_button:
		cheats_button.visible = false
	for control in [new_puzzle_button, retry_button, extra_beaker_button, mulligan_button, menu_button]:
		if control:
			control.visible = control == new_puzzle_button or control == menu_button
	var hanoi_buttons := [settings_button, new_puzzle_button, menu_button]
	_style_action_buttons(hanoi_buttons, ui_scale)
	_set_font_size(get_node_or_null("UI/Title"), 28, ui_scale)
	_set_font_size(move_counter, 22, ui_scale)
	_set_font_size(instructions_label, 18, ui_scale)

	var title_top := top_safe + 8.0 * ui_scale
	var move_top := top_safe + 46.0 * ui_scale
	if portrait:
		var controls_width := area.x - margin * 2.0
		_layout_button_grid(hanoi_buttons, 3,
				Rect2(margin, top_safe + margin, controls_width, button_height),
				button_height, button_gap)
		title_top = top_safe + margin + button_height + 8.0 * ui_scale
		move_top = title_top + 38.0 * ui_scale
	else:
		if settings_button:
			_set_control_rect(settings_button, Rect2(UI_MARGIN, top_safe + UI_MARGIN, 130.0 * ui_scale, button_height))
		if new_puzzle_button and menu_button:
			_set_control_rect(new_puzzle_button, Rect2(area.x - 260.0 * ui_scale, top_safe + UI_MARGIN, 140.0 * ui_scale, button_height))
			_set_control_rect(menu_button, Rect2(area.x - 110.0 * ui_scale, top_safe + UI_MARGIN, 90.0 * ui_scale, button_height))
		elif new_puzzle_button:
			_set_control_rect(new_puzzle_button, Rect2(area.x - 160.0 * ui_scale, top_safe + UI_MARGIN, 140.0 * ui_scale, button_height))

	_set_full_width_label(get_node_or_null("UI/Title"), title_top, 42.0 * ui_scale, 460.0 * ui_scale)
	_set_full_width_label(move_counter, move_top, 30.0 * ui_scale)
	if instructions_label:
		var instruction_width := minf(720.0, area.x - UI_MARGIN * 2.0)
		_set_control_rect(instructions_label,
				Rect2((area.x - instruction_width) * 0.5, area.y - 72.0 * ui_scale, instruction_width, 54.0 * ui_scale))
	var play_top := move_top + 48.0 * ui_scale if portrait else 96.0 * ui_scale
	var play_bottom := area.y - (88.0 * ui_scale if instructions_label else 24.0 * ui_scale)
	_set_towers_play_area(0.0, play_top, area.x, maxf(300.0 * ui_scale, play_bottom - play_top))

func _set_towers_play_area(left: float, top: float, width: float, height: float) -> void:
	if towers and towers.has_method("set_play_area"):
		towers.call("set_play_area", Rect2(left, top, width, height))

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
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

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
			check.add_theme_font_size_override("font_size", int(round(20.0 * modal_scale)))
			check.custom_minimum_size.y = maxf(check.custom_minimum_size.y, 48.0 * modal_scale)
		elif child is Button:
			var button := child as Button
			_use_ui_text_font(button)
			button.add_theme_font_size_override("font_size", int(round(19.0 * modal_scale)))
			button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 46.0 * modal_scale)
			button.custom_minimum_size.x = maxf(button.custom_minimum_size.x, 86.0 * modal_scale)
		elif child is HSlider:
			var slider := child as HSlider
			slider.custom_minimum_size = Vector2(maxf(slider.custom_minimum_size.x, 250.0 * modal_scale), 44.0 * modal_scale)
		elif child is OptionButton:
			var option := child as OptionButton
			_style_settings_option_button(option, modal_scale)
		elif child is LineEdit:
			var input := child as LineEdit
			_use_ui_text_font(input)
			input.add_theme_font_size_override("font_size", int(round(19.0 * modal_scale)))
			input.custom_minimum_size.y = maxf(input.custom_minimum_size.y, 44.0 * modal_scale)
		_style_settings_tree(child, modal_scale)

func _style_settings_option_button(option: OptionButton, modal_scale: float) -> void:
	var font_size := int(round(22.0 * modal_scale))
	_use_ui_text_font(option)
	option.add_theme_font_size_override("font_size", font_size)
	option.custom_minimum_size = Vector2(maxf(option.custom_minimum_size.x, 300.0 * modal_scale), 58.0 * modal_scale)
	var popup := option.get_popup()
	if not popup:
		return
	popup.add_theme_font_override("font", _get_ui_text_font())
	popup.add_theme_font_size_override("font_size", font_size)
	popup.add_theme_constant_override("v_separation", int(round(18.0 * modal_scale)))
	popup.add_theme_constant_override("item_start_padding", int(round(18.0 * modal_scale)))
	popup.add_theme_constant_override("item_end_padding", int(round(26.0 * modal_scale)))

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
			button.add_theme_font_size_override("font_size", int(round(20.0 * modal_scale)))
			button.custom_minimum_size = Vector2(maxf(button.custom_minimum_size.x, 150.0 * modal_scale), 52.0 * modal_scale)
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
		_add_settings_actions(content)

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
	cheats_button.pressed.connect(_open_cheats_dialog)
	ui.add_child(cheats_button)

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

func _open_cheats_dialog() -> void:
	if not cheats_overlay:
		return
	_populate_cheats_dialog()
	_layout_cheats_overlay(get_viewport_rect().size)
	cheats_overlay.visible = true
	cheats_overlay.move_to_front()
	_refresh_towers_input_enabled()
	if AudioManager:
		AudioManager.play_click()

func _close_cheats_dialog(play_sound: bool = true) -> void:
	if not cheats_overlay or not cheats_overlay.visible:
		return
	cheats_overlay.visible = false
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
	close_btn.text = tr("Close")
	close_btn.custom_minimum_size = Vector2(92, 42)
	close_btn.pressed.connect(_close_cheats_dialog)
	header.add_child(close_btn)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	content.add_child(grid)

	var undo_btn := _add_cheats_menu_button(grid,
			tr("Undo +%s") % _format_pours(MULLIGAN_POUR_PENALTY),
			use_mulligan,
			_can_use_mulligan())
	var undo_badge := _create_mulligan_badge()
	undo_badge.text = str(_get_mulligans_remaining())
	undo_badge.tooltip_text = tr("Undos left: %d") % _get_mulligans_remaining()
	undo_btn.add_child(undo_badge)

	var penalty := _get_extra_beaker_pour_penalty()
	var extra_text := tr("Extra +%s") % _format_pours(penalty) if penalty > 0.0 else tr("Extra")
	_add_cheats_menu_button(grid, extra_text, use_extra_beaker_cheat, _can_use_extra_beaker_cheat())

	if _recovery_cheats_available_for_loss:
		var can_stir := _can_use_recovery_cheat() and towers.has_method("has_usable_stir_cheat") and bool(towers.call("has_usable_stir_cheat"))
		var can_swap := _can_use_recovery_cheat() and towers.has_method("has_usable_swap_cheat") and bool(towers.call("has_usable_swap_cheat"))
		_add_cheats_menu_button(grid, tr("Stir +%s") % _format_pours(CHEAT_POUR_PENALTY), start_stir_cheat, can_stir)
		_add_cheats_menu_button(grid, tr("Swap +%s") % _format_pours(CHEAT_POUR_PENALTY), start_swap_cheat, can_swap)

func _add_cheats_menu_button(parent: Control, text: String, callback: Callable, enabled: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = text
	button.disabled = not enabled
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(150, 52)
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

func _on_goal_changed(_optimal_pours: int):
	if _optimal_pours != OPTIMAL_SOLVER_CALCULATING:
		_solver_progress_text = ""
	update_goal_label()
	_refresh_victory_score()
	_update_music_pressure()
	_update_mulligan_button()

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
		goal_label.text = tr("Still calculating goal")
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
	return _recovery_cheat_pour_penalty

func _format_recovery_cheat_penalty(wide: bool) -> String:
	var key := "  |  Cheat: +%s" if wide else " | Cheat: +%s"
	if _recovery_cheat_kind == "extra_beaker":
		key = "  |  Beaker: +%s" if wide else " | Beaker: +%s"
	return tr(key) % _format_pours(_get_cheat_pour_penalty())

func _get_extra_beaker_pour_penalty() -> float:
	var optimal := _get_optimal_pours()
	if optimal < 0:
		return 0.0
	var rounded: float = ceil(float(optimal) * EXTRA_BEAKER_PENALTY_RATIO * 2.0) / 2.0
	return maxf(EXTRA_BEAKER_MIN_PENALTY, rounded)

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

func _refresh_towers_input_enabled() -> void:
	if not towers:
		return
	var settings_open := settings_overlay != null and settings_overlay.visible
	var cheats_open := cheats_overlay != null and cheats_overlay.visible
	var should_enable := not settings_open and not cheats_open and not _has_result_overlay() and not _shatter_loss_locked
	towers.set_process_input(should_enable)
	if not should_enable and towers.has_method("clear_pointer_state"):
		towers.call("clear_pointer_state")

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
	show_victory_screen()

func show_victory_screen():
	if AudioManager and AudioManager.has_method("play_solved_music"):
		AudioManager.play_solved_music()
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
	solved_lbl.text = tr("🎉  SOLVED!  🎉")
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
	star_row.custom_minimum_size = Vector2(0, 58.0 * modal_scale)
	star_row.add_theme_constant_override("separation", int(round(4.0 * modal_scale)))
	vb.add_child(star_row)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8.0 * modal_scale)
	vb.add_child(spacer)

	var hb := GridContainer.new()
	hb.columns = 2 if portrait else 4
	_style_result_button_grid(hb, portrait, modal_scale, card_width)
	vb.add_child(hb)

	_add_result_button(hb, tr("Retry"), 110.0, retry_game)
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
	var score_lbl: Label = get_node_or_null("VictoryOverlay/Card/Content/ScoreLine")
	if not score_lbl:
		return
	var score := _get_score()
	if score < 0:
		score_lbl.text = tr("Score pending")
		return
	var optimal := _get_optimal_pours()
	var extra := _get_extra_pours()
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
		_populate_star_row(star_row, _get_star_count(score), true)

func _populate_star_row(row: HBoxContainer, stars: int, animate: bool):
	var modal_scale := _get_result_modal_scale(get_viewport_rect().size)
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	for i in 5:
		var filled := i < stars
		var star := Label.new()
		star.text = STAR_FILLED if filled else STAR_EMPTY
		star.custom_minimum_size = Vector2(52.0 * modal_scale, 58.0 * modal_scale)
		star.pivot_offset = Vector2(26.0 * modal_scale, 29.0 * modal_scale)
		star.add_theme_font_size_override("font_size", int(round(46.0 * modal_scale)))
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
	var modal_scale := _get_result_modal_scale(get_viewport_rect().size)
	var local_center := fx_layer.get_global_transform().affine_inverse() * global_center
	_spawn_star_flash(fx_layer, local_center, delay)
	for n in 16:
		var spark := Label.new()
		spark.text = STAR_SPARK
		spark.custom_minimum_size = Vector2(18.0 * modal_scale, 18.0 * modal_scale)
		spark.pivot_offset = Vector2(9.0 * modal_scale, 9.0 * modal_scale)
		spark.position = local_center - Vector2(9.0 * modal_scale, 9.0 * modal_scale)
		spark.rotation = randf_range(-0.6, 0.6)
		spark.scale = Vector2(randf_range(0.65, 1.15), randf_range(0.65, 1.15))
		spark.modulate = Color(1, 1, 1, 0)
		spark.add_theme_font_size_override("font_size", int(round(randf_range(12.0, 22.0) * modal_scale)))
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

func _spawn_star_flash(parent: Control, center: Vector2, delay: float) -> void:
	var modal_scale := _get_result_modal_scale(get_viewport_rect().size)
	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.78, 0.12, 0.34)
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
	_show_loss(tr("BEAKER SHATTERED"), tr("Cracked beaker shattered."), false, false)

func _check_for_no_moves():
	if not towers.has_method("has_available_moves"):
		return
	if towers.check_complete():
		return
	if towers.has_method("is_only_cracked_blocking_completion") and bool(towers.call("is_only_cracked_blocking_completion")):
		_show_loss(tr("CRACKED NOT EMPTY"), tr("Cracked must end empty."), true)
		return
	if bool(towers.call("has_available_moves")):
		return
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
	if _score_forced_zero:
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
	elif optimal >= 0:
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
		_style_result_button(mulligan_btn, tr("Undo +%s") % _format_pours(MULLIGAN_POUR_PENALTY), 130.0, use_mulligan)
		var badge := _create_mulligan_badge()
		badge.text = str(_get_mulligans_remaining())
		badge.tooltip_text = tr("Undos left: %d") % _get_mulligans_remaining()
		mulligan_btn.add_child(badge)
		hb.add_child(mulligan_btn)

	if _recovery_cheats_available_for_loss and _can_use_extra_beaker_cheat():
		var extra_btn := Button.new()
		_style_result_button(extra_btn, tr("Extra +%s") % _format_pours(_get_extra_beaker_pour_penalty()), 124.0, use_extra_beaker_cheat)
		hb.add_child(extra_btn)

	if _can_use_recovery_cheat():
		if towers.has_method("has_usable_stir_cheat") and bool(towers.call("has_usable_stir_cheat")):
			var stir_btn := Button.new()
			_style_result_button(stir_btn, tr("Stir +%s") % _format_pours(CHEAT_POUR_PENALTY), 112.0, start_stir_cheat)
			hb.add_child(stir_btn)
		if towers.has_method("has_usable_swap_cheat") and bool(towers.call("has_usable_swap_cheat")):
			var swap_btn := Button.new()
			_style_result_button(swap_btn, tr("Swap +%s") % _format_pours(CHEAT_POUR_PENALTY), 116.0, start_swap_cheat)
			hb.add_child(swap_btn)

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
	button.pressed.connect(callback)

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
	_clear_result_overlays()
	_score_forced_zero = false
	_recovery_cheats_available_for_loss = false
	_last_recovery_loss_title = ""
	_last_recovery_loss_detail = ""
	_mulligans_used = 0
	_cheats_used = 0
	_recovery_cheat_pour_penalty = 0.0
	_recovery_cheat_kind = ""
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
	if _cheats_used >= CHEAT_MAX_USES:
		return false
	if _would_exceed_pour_limit(CHEAT_POUR_PENALTY):
		return false
	if _shatter_loss_locked:
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

func _can_use_extra_beaker_cheat() -> bool:
	return (_cheats_used < CHEAT_MAX_USES
			and towers != null
			and _get_optimal_pours() >= 0
			and not _would_exceed_pour_limit(_get_extra_beaker_pour_penalty())
			and not towers.check_complete()
			and not _shatter_loss_locked
			and not (towers.has_method("is_choosing_cheat") and bool(towers.call("is_choosing_cheat")))
			and towers.has_method("can_add_empty_beaker")
			and bool(towers.call("can_add_empty_beaker")))

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

func use_extra_beaker_cheat() -> void:
	if not _can_use_extra_beaker_cheat():
		if AudioManager:
			AudioManager.play_invalid()
		return
	var penalty := _get_extra_beaker_pour_penalty()
	if penalty <= 0.0 or not bool(towers.call("add_empty_beaker")):
		if AudioManager:
			AudioManager.play_invalid()
		return
	_cheats_used += 1
	_recovery_cheat_pour_penalty += penalty
	_recovery_cheat_kind = "extra_beaker"
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
		instructions_label.text = tr("Recovery: choose a mixed beaker.")
	elif cheat_type == "swap":
		instructions_label.text = tr("Recovery: choose adjacent segments.")

func _restore_instruction_label() -> void:
	if instructions_label and _default_instructions_text != "":
		instructions_label.text = tr(_default_instructions_text)

func _on_cheat_applied(_cheat_type: String) -> void:
	_cheats_used += 1
	_recovery_cheat_pour_penalty += CHEAT_POUR_PENALTY
	_recovery_cheat_kind = _cheat_type
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
	if _is_pour_limit_exceeded():
		_show_pour_limit_loss()
	elif towers.check_complete():
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
	return (_get_mulligans_remaining() > 0
			and towers != null
			and not _would_mulligan_exceed_pour_limit()
			and not towers.check_complete()
			and not (towers.has_method("is_choosing_cheat") and bool(towers.call("is_choosing_cheat")))
			and towers.has_method("can_undo_last_pour")
			and bool(towers.call("can_undo_last_pour")))

func _get_mulligans_remaining() -> int:
	return maxi(0, MULLIGAN_MAX_USES - _mulligans_used)

func _update_mulligan_button():
	if mulligan_button:
		mulligan_button.text = tr("Undo +%s") % _format_pours(MULLIGAN_POUR_PENALTY)
		mulligan_button.disabled = not _can_use_mulligan()
		if mulligan_badge:
			mulligan_badge.text = str(_get_mulligans_remaining())
			mulligan_badge.tooltip_text = tr("Undos left: %d") % _get_mulligans_remaining()
	_update_extra_beaker_button()

func _update_extra_beaker_button() -> void:
	if not extra_beaker_button:
		return
	var penalty := _get_extra_beaker_pour_penalty()
	if penalty > 0.0:
		extra_beaker_button.text = tr("Extra +%s") % _format_pours(penalty)
	else:
		extra_beaker_button.text = tr("Extra")
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
	_shatter_loss_locked = false
	_shatter_loss_generation += 1
	_mulligans_used = 0
	_cheats_used = 0
	_recovery_cheat_pour_penalty = 0.0
	_recovery_cheat_kind = ""
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
	_shatter_loss_locked = false
	_shatter_loss_generation += 1
	_mulligans_used = 0
	_cheats_used = 0
	_recovery_cheat_pour_penalty = 0.0
	_recovery_cheat_kind = ""
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
	_refresh_towers_input_enabled()

func go_to_menu():
	if AudioManager:
		AudioManager.play_click()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
