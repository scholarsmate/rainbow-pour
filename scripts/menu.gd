extends Control

@onready var settings_button = get_node_or_null("SettingsButton")

var settings_overlay: Control
var music_slider: HSlider
var music_value: Label
var effects_slider: HSlider
var effects_value: Label

func _ready():
	_build_settings_dialog()

func _on_hanoi_pressed():
	if AudioManager:
		AudioManager.play_click()
	get_tree().change_scene_to_file("res://scenes/hanoi.tscn")

func _on_beaker_pressed():
	if AudioManager:
		AudioManager.play_click()
	get_tree().change_scene_to_file("res://scenes/beaker.tscn")

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
	card.color = Color(0.075, 0.09, 0.14, 0.98)
	card.custom_minimum_size = Vector2(520, 320)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -260.0
	card.offset_top = -160.0
	card.offset_right = 260.0
	card.offset_bottom = 160.0
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_overlay.add_child(card)

	var stripe := ColorRect.new()
	stripe.color = Color(0.14, 0.70, 1.0, 1.0)
	stripe.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stripe.offset_bottom = 5.0
	card.add_child(stripe)

	var content := VBoxContainer.new()
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

func _format_volume(value: float) -> String:
	return "%d%%" % int(round(clampf(value, 0.0, 1.0) * 100.0))
