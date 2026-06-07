extends Control

@onready var settings_button = get_node_or_null("SettingsButton")
@onready var title_label: Label = get_node_or_null("Title")
@onready var subtitle_label: Label = get_node_or_null("Subtitle")
@onready var buttons_root: Control = get_node_or_null("Buttons")
@onready var version_label: Label = get_node_or_null("VersionLabel")

const PrismaticButtonFrame := preload("res://scripts/prismatic_button_frame.gd")
const FEATURED_BUTTON_NAME := "BeakerButton"
const SECONDARY_BUTTON_NAMES := ["HanoiButton", "BuilderButton"]
const PORTRAIT_REFERENCE_WIDTH := 460.0
const MOBILE_UI_SCALE_MIN := 1.55
const PRISMATIC_FRAME_NAME := "PrismaticFrame"

var settings_overlay: Control
var special_beakers_toggle: CheckButton
var music_slider: HSlider
var music_value: Label
var effects_slider: HSlider
var effects_value: Label

func _ready():
	if AudioManager and AudioManager.has_method("play_menu_music"):
		AudioManager.play_menu_music()
	elif AudioManager and AudioManager.has_method("play_game_music"):
		AudioManager.play_game_music(0.0)
	elif AudioManager and AudioManager.has_method("set_loop_pressure"):
		AudioManager.set_loop_pressure(0.0)
	_sync_version_label()
	_install_prismatic_button_frames()
	_build_settings_dialog()
	get_viewport().size_changed.connect(_update_responsive_layout)
	_update_responsive_layout.call_deferred()

func _update_responsive_layout() -> void:
	var area := get_viewport_rect().size
	var portrait := area.y > area.x * 1.08
	var ui_scale := _get_ui_scale(area)
	if title_label:
		title_label.add_theme_font_size_override("font_size", int(round((44.0 if portrait else 60.0) * ui_scale)))
		var title_width := minf(area.x - 32.0 * ui_scale, 620.0 * ui_scale)
		_set_control_rect(title_label, Rect2((area.x - title_width) * 0.5, 46.0 * ui_scale, title_width, 82.0 * ui_scale))
	if subtitle_label:
		subtitle_label.add_theme_font_size_override("font_size", int(round(22.0 * ui_scale)))
		var subtitle_width := minf(area.x - 40.0 * ui_scale, 460.0 * ui_scale)
		_set_control_rect(subtitle_label, Rect2((area.x - subtitle_width) * 0.5, 136.0 * ui_scale, subtitle_width, 34.0 * ui_scale))
	if settings_button:
		settings_button.add_theme_font_size_override("font_size", int(round(20.0 * ui_scale)))
		_set_control_rect(settings_button, Rect2(area.x - 154.0 * ui_scale, 20.0 * ui_scale, 134.0 * ui_scale, 40.0 * ui_scale))
	if version_label:
		var version_font_size := int(round(clampf(24.0 * ui_scale, 24.0, 38.0)))
		var version_width := minf(230.0 * ui_scale, area.x - 28.0 * ui_scale)
		var version_height := 46.0 * ui_scale
		var version_margin := 14.0 * ui_scale
		version_label.add_theme_font_size_override("font_size", version_font_size)
		version_label.add_theme_color_override("font_color", Color(0.84, 0.90, 1.0, 0.88))
		version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		version_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_set_control_rect(version_label, Rect2(
				area.x - version_width - version_margin,
				area.y - version_height - version_margin,
				version_width,
				version_height))
	if not buttons_root:
		return
	_layout_menu_buttons(area, ui_scale, portrait)
	_layout_settings_overlay(area)

func _layout_menu_buttons(area: Vector2, ui_scale: float, portrait: bool) -> void:
	var featured := buttons_root.get_node_or_null(FEATURED_BUTTON_NAME) as Button
	var secondary_buttons := []
	for button_name in SECONDARY_BUTTON_NAMES:
		var secondary := buttons_root.get_node_or_null(button_name) as Button
		if secondary:
			secondary_buttons.append(secondary)
	if not featured:
		return

	var dimension_scale := minf(ui_scale, 1.25)
	var featured_width := minf(area.x - 40.0 * ui_scale, (520.0 if portrait else 680.0) * ui_scale)
	var featured_height := clampf(area.y * (0.19 if portrait else 0.25),
			170.0 * dimension_scale, (270.0 if portrait else 224.0) * dimension_scale)
	var secondary_gap := 18.0 * dimension_scale
	var secondary_height := clampf(area.y * (0.115 if portrait else 0.17),
			108.0 * dimension_scale, (166.0 if portrait else 156.0) * dimension_scale)
	var secondary_width := featured_width if portrait else (featured_width - secondary_gap) * 0.5
	var cluster_height := featured_height + secondary_gap
	if portrait:
		cluster_height += float(secondary_buttons.size()) * secondary_height
		cluster_height += float(maxi(0, secondary_buttons.size() - 1)) * secondary_gap
	else:
		cluster_height += secondary_height

	var title_bottom := 128.0 * ui_scale
	if title_label:
		title_bottom = title_label.offset_bottom
	var footer_clearance := 58.0 * dimension_scale
	var min_top := title_bottom + 18.0 * dimension_scale
	var max_top := area.y - cluster_height - footer_clearance
	var preferred_top := (area.y - cluster_height) * (0.50 if portrait else 0.55)
	var top := preferred_top
	if max_top >= min_top:
		top = clampf(preferred_top, min_top, max_top)
	else:
		top = maxf(8.0 * dimension_scale, max_top)

	var left := (area.x - featured_width) * 0.5
	_set_control_rect(buttons_root, Rect2(0.0, 0.0, area.x, area.y))
	_style_menu_button(featured, ui_scale, true)
	featured.custom_minimum_size = Vector2(featured_width, featured_height)
	_set_control_rect(featured, Rect2(left, top, featured_width, featured_height))

	var secondary_top := top + featured_height + secondary_gap
	for idx in secondary_buttons.size():
		var button := secondary_buttons[idx] as Button
		_style_menu_button(button, ui_scale, false)
		button.custom_minimum_size = Vector2(secondary_width, secondary_height)
		var secondary_left := left
		var button_top := secondary_top
		if portrait:
			button_top += float(idx) * (secondary_height + secondary_gap)
		else:
			secondary_left += float(idx) * (secondary_width + secondary_gap)
		_set_control_rect(button, Rect2(secondary_left, button_top, secondary_width, secondary_height))

func _install_prismatic_button_frames() -> void:
	if not buttons_root:
		return
	for child in buttons_root.get_children():
		if child is Button:
			_ensure_prismatic_button_frame(child as Button)

func _ensure_prismatic_button_frame(button: Button) -> void:
	var frame := button.get_node_or_null(PRISMATIC_FRAME_NAME) as Control
	if not frame:
		frame = PrismaticButtonFrame.new()
		frame.name = PRISMATIC_FRAME_NAME
		button.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 0.0
	frame.offset_top = 0.0
	frame.offset_right = 0.0
	frame.offset_bottom = 0.0
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set("phase_offset", float(button.get_index()) * 0.64)
	frame.set("intensity", 1.24 if button.name == FEATURED_BUTTON_NAME else 0.92)

func _style_menu_button(button: Button, ui_scale: float, featured: bool) -> void:
	var radius := int(round((11.0 if featured else 9.0) * ui_scale))
	var border_width := maxi(1, int(round((2.0 if featured else 1.0) * ui_scale)))
	var normal := _make_menu_button_style(
			Color(0.052, 0.068, 0.108, 0.97) if featured else Color(0.040, 0.052, 0.082, 0.94),
			Color(1.0, 0.94, 0.68, 0.34) if featured else Color(0.82, 0.92, 1.0, 0.18),
			radius, border_width)
	var hover := _make_menu_button_style(
			Color(0.070, 0.090, 0.138, 0.98) if featured else Color(0.058, 0.078, 0.120, 0.97),
			Color(1.0, 0.98, 0.86, 0.48) if featured else Color(0.90, 0.98, 1.0, 0.30),
			radius, border_width)
	var pressed := _make_menu_button_style(
			Color(0.034, 0.046, 0.074, 0.98) if featured else Color(0.028, 0.038, 0.062, 0.98),
			Color(1.0, 0.88, 0.52, 0.54) if featured else Color(1.00, 1.00, 1.0, 0.34),
			radius, border_width)
	var focus := _make_menu_button_style(
			Color(0.064, 0.082, 0.128, 0.98) if featured else Color(0.052, 0.068, 0.106, 0.98),
			Color(1.0, 1.0, 0.92, 0.58) if featured else Color(1.00, 1.00, 1.0, 0.45),
			radius, border_width)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_font_size_override("font_size", int(round((27.0 if featured else 21.0) * ui_scale)))
	button.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.88, 0.94, 1.0, 1.0))
	button.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.62))
	button.add_theme_constant_override("outline_size", maxi(1, int(round(2.0 * ui_scale))))
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _make_menu_button_style(fill: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	return style

func _get_ui_scale(area: Vector2) -> float:
	if area.y > area.x * 1.08:
		var portrait_scale := clampf(area.x / PORTRAIT_REFERENCE_WIDTH, 1.0, 2.35)
		return maxf(MOBILE_UI_SCALE_MIN, portrait_scale) if _is_mobile_runtime() else portrait_scale
	var landscape_scale := clampf(minf(area.x / 1280.0, area.y / 720.0), 0.90, 1.35)
	return maxf(MOBILE_UI_SCALE_MIN, landscape_scale) if _is_mobile_runtime() else landscape_scale

func _is_mobile_runtime() -> bool:
	return OS.has_feature("mobile") or OS.get_name() == "Android" or OS.get_name() == "iOS"

func _set_control_rect(control: Control, rect: Rect2) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.position.x + rect.size.x
	control.offset_bottom = rect.position.y + rect.size.y
	control.custom_minimum_size = rect.size

func _sync_version_label() -> void:
	if not version_label:
		return
	version_label.text = "v%s" % _get_app_version()

func _get_app_version() -> String:
	var version_file := FileAccess.open("res://VERSION.txt", FileAccess.READ)
	if version_file:
		var version := version_file.get_as_text().strip_edges()
		if version != "":
			return version
	var project_version := str(ProjectSettings.get_setting("application/config/version", "0.1.0")).strip_edges()
	return project_version if project_version != "" else "0.1.0"

func _layout_settings_overlay(area: Vector2) -> void:
	if not settings_overlay:
		return
	var card := settings_overlay.get_node_or_null("SettingsCard") as Control
	var content := settings_overlay.get_node_or_null("SettingsCard/Content") as Control
	if not card or not content:
		return
	var ui_scale := _get_ui_scale(area)
	var modal_scale := clampf(ui_scale, 1.15, 1.70)
	var mobile_sheet := _is_mobile_runtime() or area.y > area.x * 1.08
	var margin := (10.0 if area.y > area.x * 1.08 else 18.0) * modal_scale
	var card_size := Vector2(area.x - margin * 2.0, area.y - margin * 2.0) if mobile_sheet else Vector2(
			minf(620.0, area.x - margin * 2.0),
			minf(460.0, area.y - margin * 2.0))
	var card_pos := Vector2((area.x - card_size.x) * 0.5, (area.y - card_size.y) * 0.5)
	if mobile_sheet and area.y > area.x * 1.08:
		card_pos.y = margin
	_set_control_rect(card, Rect2(card_pos, card_size))

	var stripe := card.get_node_or_null("Stripe") as Control
	if stripe:
		_set_control_rect(stripe, Rect2(0.0, 0.0, card_size.x, maxf(6.0, 5.0 * modal_scale)))

	var pad_x := 24.0 * modal_scale
	var pad_top := 22.0 * modal_scale
	var pad_bottom := 24.0 * modal_scale
	content.anchor_left = 0.0
	content.anchor_top = 0.0
	content.anchor_right = 1.0
	content.anchor_bottom = 1.0
	content.offset_left = pad_x
	content.offset_top = pad_top
	content.offset_right = -pad_x
	content.offset_bottom = -pad_bottom
	content.custom_minimum_size = Vector2(maxf(280.0, card_size.x - pad_x * 2.0), 0.0)
	if content is VBoxContainer:
		(content as VBoxContainer).add_theme_constant_override("separation", int(round(16.0 * modal_scale)))
	_style_settings_tree(content, modal_scale)

func _style_settings_tree(root: Node, modal_scale: float) -> void:
	for child in root.get_children():
		if child is HBoxContainer:
			(child as HBoxContainer).add_theme_constant_override("separation", int(round(12.0 * modal_scale)))
		if child is CheckButton:
			var check := child as CheckButton
			check.add_theme_font_size_override("font_size", int(round(20.0 * modal_scale)))
			check.custom_minimum_size.y = maxf(check.custom_minimum_size.y, 48.0 * modal_scale)
		elif child is Button:
			var button := child as Button
			button.add_theme_font_size_override("font_size", int(round(19.0 * modal_scale)))
			button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 46.0 * modal_scale)
			button.custom_minimum_size.x = maxf(button.custom_minimum_size.x, 86.0 * modal_scale)
		elif child is Label:
			var label := child as Label
			var base_size := 19.0
			if label.text == tr("Settings"):
				base_size = 36.0
			elif label.custom_minimum_size.y >= 30.0:
				base_size = 23.0
			label.add_theme_font_size_override("font_size", int(round(base_size * modal_scale)))
			label.custom_minimum_size.y = maxf(label.custom_minimum_size.y, 38.0 * modal_scale)
		elif child is HSlider:
			var slider := child as HSlider
			slider.custom_minimum_size = Vector2(maxf(slider.custom_minimum_size.x, 250.0 * modal_scale), 44.0 * modal_scale)
		_style_settings_tree(child, modal_scale)

func _on_hanoi_pressed():
	if AudioManager:
		AudioManager.play_click()
	get_tree().change_scene_to_file("res://scenes/hanoi.tscn")

func _on_beaker_pressed():
	if AudioManager:
		AudioManager.play_click()
	get_tree().change_scene_to_file("res://scenes/beaker.tscn")

func _on_builder_pressed():
	if AudioManager:
		AudioManager.play_click()
	get_tree().change_scene_to_file("res://scenes/board_builder.tscn")

func _build_settings_dialog():
	if not settings_button:
		return
	settings_button.pressed.connect(_open_settings_dialog)

	settings_overlay = Control.new()
	settings_overlay.name = "SettingsOverlay"
	settings_overlay.visible = false
	settings_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(settings_overlay)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.68)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_settings_backdrop_gui_input)
	settings_overlay.add_child(backdrop)

	var card := ColorRect.new()
	card.name = "SettingsCard"
	card.color = Color(0.075, 0.09, 0.14, 0.98)
	card.custom_minimum_size = Vector2(520, 380)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -260.0
	card.offset_top = -190.0
	card.offset_right = 260.0
	card.offset_bottom = 190.0
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_overlay.add_child(card)

	var stripe := ColorRect.new()
	stripe.name = "Stripe"
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
	content.add_theme_constant_override("separation", 14)
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

	_add_section_label(content, tr("Puzzle"))
	special_beakers_toggle = CheckButton.new()
	special_beakers_toggle.text = tr("Special beakers")
	special_beakers_toggle.add_theme_font_size_override("font_size", 18)
	special_beakers_toggle.toggled.connect(_on_special_beakers_toggled)
	content.add_child(special_beakers_toggle)

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
	_sync_settings_ui()

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
	label.custom_minimum_size = Vector2(100, 34)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.98))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(270, 34)
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

func _sync_settings_ui():
	if special_beakers_toggle:
		special_beakers_toggle.button_pressed = GameSettings.special_beakers_enabled
	if music_slider:
		music_slider.value = GameSettings.music_volume
	if music_value:
		music_value.text = _format_volume(GameSettings.music_volume)
	if effects_slider:
		effects_slider.value = GameSettings.effects_volume
	if effects_value:
		effects_value.text = _format_volume(GameSettings.effects_volume)

func _open_settings_dialog():
	if not settings_overlay:
		return
	_sync_settings_ui()
	_layout_settings_overlay(get_viewport_rect().size)
	settings_overlay.visible = true
	settings_overlay.move_to_front()
	if AudioManager:
		AudioManager.play_click()

func _close_settings_dialog():
	if not settings_overlay or not settings_overlay.visible:
		return
	settings_overlay.visible = false
	if AudioManager:
		AudioManager.play_click()

func _on_settings_backdrop_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_settings_dialog()

func _unhandled_input(event: InputEvent):
	if settings_overlay and settings_overlay.visible and event.is_action_pressed("ui_cancel"):
		_close_settings_dialog()
		get_viewport().set_input_as_handled()

func _on_music_volume_changed(value: float):
	GameSettings.set_music_volume(value)
	if music_value:
		music_value.text = _format_volume(GameSettings.music_volume)

func _on_effects_volume_changed(value: float):
	GameSettings.set_effects_volume(value)
	if effects_value:
		effects_value.text = _format_volume(GameSettings.effects_volume)
	if AudioManager:
		AudioManager.play_select()

func _on_special_beakers_toggled(button_pressed: bool) -> void:
	if button_pressed == GameSettings.special_beakers_enabled:
		return
	GameSettings.set_special_beakers_enabled(button_pressed)
	if AudioManager:
		AudioManager.play_select()

func _format_volume(value: float) -> String:
	return "%d%%" % int(round(clampf(value, 0.0, 1.0) * 100.0))
