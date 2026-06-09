extends Control

@onready var settings_button = get_node_or_null("SettingsButton")
@onready var title_label: Label = get_node_or_null("Title")
@onready var subtitle_label: Label = get_node_or_null("Subtitle")
@onready var buttons_root: Control = get_node_or_null("Buttons")
@onready var version_label: Label = get_node_or_null("VersionLabel")

const PrismaticButtonFrame := preload("res://scripts/prismatic_button_frame.gd")
const FEATURED_BUTTON_NAME := "BeakerButton"
const SECONDARY_BUTTON_NAMES := ["AdventureButton", "HanoiButton", "BuilderButton"]
const SCORE_MAX := 1000
const PORTRAIT_REFERENCE_WIDTH := 460.0
const MOBILE_UI_SCALE_MIN := 1.55
const PRISMATIC_FRAME_NAME := "PrismaticFrame"
const ADVENTURE_GOLD_TEXT_COLOR := Color(1.0, 0.86, 0.35)
const ADVENTURE_PLATINUM_TEXT_COLOR := Color(0.84, 0.94, 1.0)

var settings_overlay: Control
var adventure_overlay: Control
var adventure_confirm_overlay: Control
var adventure_scroll: ScrollContainer
var adventure_content: VBoxContainer
var special_beakers_toggle: CheckButton
var music_slider: HSlider
var music_value: Label
var effects_slider: HSlider
var effects_value: Label
var adventure_expanded_blocks: Dictionary = {}
var _adventure_scroll_drag_active := false
var _adventure_scroll_drag_started := false
var _adventure_scroll_drag_start := Vector2.ZERO
var _adventure_scroll_drag_last := Vector2.ZERO
var _adventure_scroll_suppress_click_until := 0

const ADVENTURE_SCROLL_DRAG_THRESHOLD := 12.0
const ADVENTURE_SCROLL_CLICK_SUPPRESS_MS := 220

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
	_build_adventure_dialog()
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
	_layout_adventure_overlay(area)

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
	var secondary_width := featured_width
	if not portrait and not secondary_buttons.is_empty():
		secondary_width = (featured_width - secondary_gap * float(maxi(0, secondary_buttons.size() - 1))) / float(secondary_buttons.size())
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
	if AdventureManager:
		AdventureManager.clear_current_puzzle()
	get_tree().change_scene_to_file("res://scenes/beaker.tscn")

func _on_adventure_pressed():
	_open_adventure_dialog()

func _on_builder_pressed():
	if AudioManager:
		AudioManager.play_click()
	get_tree().change_scene_to_file("res://scenes/board_builder.tscn")

func _build_adventure_dialog() -> void:
	adventure_overlay = Control.new()
	adventure_overlay.name = "AdventureOverlay"
	adventure_overlay.visible = false
	adventure_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	adventure_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	adventure_overlay.z_index = 100
	add_child(adventure_overlay)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.015, 0.020, 0.034, 0.96)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_adventure_backdrop_gui_input)
	adventure_overlay.add_child(backdrop)

	var card := ColorRect.new()
	card.name = "AdventureCard"
	card.color = Color(0.026, 0.032, 0.052, 1.0)
	card.custom_minimum_size = Vector2(720, 520)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -360.0
	card.offset_top = -260.0
	card.offset_right = 360.0
	card.offset_bottom = 260.0
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	adventure_overlay.add_child(card)

	var stripe := ColorRect.new()
	stripe.name = "Stripe"
	stripe.color = Color(1.0, 0.75, 0.1, 1.0)
	stripe.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stripe.offset_bottom = 5.0
	card.add_child(stripe)

	var root := VBoxContainer.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 28.0
	root.offset_top = 22.0
	root.offset_right = -28.0
	root.offset_bottom = -24.0
	root.add_theme_constant_override("separation", 14)
	card.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)

	var title := Label.new()
	title.text = tr("Adventure Mode")
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.name = "CloseAdventureButton"
	close_btn.text = "X"
	close_btn.tooltip_text = tr("Close")
	close_btn.custom_minimum_size = Vector2(52, 42)
	close_btn.add_theme_font_size_override("font_size", 18)
	_apply_adventure_button_style(close_btn, false)
	close_btn.pressed.connect(_close_adventure_dialog)
	header.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	adventure_scroll = scroll
	scroll.follow_focus = true
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	adventure_content = VBoxContainer.new()
	adventure_content.name = "Content"
	adventure_content.mouse_filter = Control.MOUSE_FILTER_PASS
	adventure_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	adventure_content.add_theme_constant_override("separation", 18)
	scroll.add_child(adventure_content)

func _layout_adventure_overlay(area: Vector2) -> void:
	if not adventure_overlay:
		return
	var card := adventure_overlay.get_node_or_null("AdventureCard") as Control
	var root := adventure_overlay.get_node_or_null("AdventureCard/Root") as Control
	if not card or not root:
		return
	var ui_scale := _get_ui_scale(area)
	var modal_scale := clampf(ui_scale, 1.18, 1.82)
	var mobile_sheet := _is_mobile_runtime() or area.y > area.x * 1.08
	var margin := (8.0 if area.y > area.x * 1.08 else 18.0) * modal_scale
	var card_size := Vector2(area.x - margin * 2.0, area.y - margin * 2.0) if mobile_sheet else Vector2(
			minf(820.0, area.x - margin * 2.0),
			minf(620.0, area.y - margin * 2.0))
	var card_pos := Vector2((area.x - card_size.x) * 0.5, (area.y - card_size.y) * 0.5)
	if mobile_sheet and area.y > area.x * 1.08:
		card_pos.y = margin
	_set_control_rect(card, Rect2(card_pos, card_size))

	var stripe := card.get_node_or_null("Stripe") as Control
	if stripe:
		_set_control_rect(stripe, Rect2(0.0, 0.0, card_size.x, maxf(6.0, 5.0 * modal_scale)))

	var pad_x := 20.0 * modal_scale
	var pad_top := 18.0 * modal_scale
	var pad_bottom := 22.0 * modal_scale
	root.anchor_left = 0.0
	root.anchor_top = 0.0
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = pad_x
	root.offset_top = pad_top
	root.offset_right = -pad_x
	root.offset_bottom = -pad_bottom
	_style_adventure_tree(root, modal_scale)

func _style_adventure_tree(root: Node, modal_scale: float) -> void:
	for child in root.get_children():
		if child is VBoxContainer:
			(child as VBoxContainer).add_theme_constant_override("separation", int(round(12.0 * modal_scale)))
		elif child is HBoxContainer:
			(child as HBoxContainer).add_theme_constant_override("separation", int(round(10.0 * modal_scale)))
		elif child is GridContainer:
			var grid := child as GridContainer
			grid.add_theme_constant_override("h_separation", int(round(8.0 * modal_scale)))
			grid.add_theme_constant_override("v_separation", int(round(8.0 * modal_scale)))
		if child is Button:
			var button := child as Button
			var button_role := str(button.get_meta("adventure_role", "button"))
			var base_font_size := 18.0
			var min_height := 48.0
			if button_role == "puzzle":
				base_font_size = 15.0
				min_height = 54.0
			elif button_role == "compact":
				base_font_size = 14.0
				min_height = 38.0
			elif button.name == "CloseAdventureButton":
				base_font_size = 18.0
				min_height = 42.0
				button.custom_minimum_size.x = maxf(button.custom_minimum_size.x, 50.0 * modal_scale)
			button.add_theme_font_size_override("font_size", int(round(base_font_size * modal_scale)))
			button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, min_height * modal_scale)
		elif child is Label:
			var label := child as Label
			var label_role := str(label.get_meta("adventure_role", "body"))
			var label_font_size := 18.0
			var min_label_height := 28.0
			match label_role:
				"dialog_title":
					label_font_size = 20.0
					min_label_height = 34.0
				"pack_title":
					label_font_size = 22.0
					min_label_height = 36.0
				"block_title":
					label_font_size = 18.0
					min_label_height = 30.0
				"muted":
					label_font_size = 14.0
					min_label_height = 24.0
				"progress":
					label_font_size = 15.0
					min_label_height = 24.0
			label.add_theme_font_size_override("font_size", int(round(label_font_size * modal_scale)))
			label.custom_minimum_size.y = maxf(label.custom_minimum_size.y, min_label_height * modal_scale)
		_style_adventure_tree(child, modal_scale)

func _open_adventure_dialog() -> void:
	if not adventure_overlay:
		return
	_reset_adventure_scroll_drag()
	if AdventureManager:
		AdventureManager.reload_adventures()
	_populate_adventure_dialog()
	_layout_adventure_overlay(get_viewport_rect().size)
	adventure_overlay.visible = true
	adventure_overlay.move_to_front()
	if AudioManager:
		AudioManager.play_click()

func _close_adventure_dialog() -> void:
	if not adventure_overlay or not adventure_overlay.visible:
		return
	_reset_adventure_scroll_drag()
	_clear_adventure_confirm_overlay()
	adventure_overlay.visible = false
	if AudioManager:
		AudioManager.play_click()

func _on_adventure_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_adventure_dialog()

func _populate_adventure_dialog() -> void:
	if not adventure_content:
		return
	for child in adventure_content.get_children():
		adventure_content.remove_child(child)
		child.queue_free()
	if not AdventureManager or not AdventureManager.has_adventures():
		var empty_label := Label.new()
		empty_label.text = tr("No adventures found.")
		empty_label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.98))
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		adventure_content.add_child(empty_label)
		return
	for adventure in AdventureManager.get_adventures():
		_add_adventure_pack(adventure)

func _add_adventure_pack(adventure: Dictionary) -> void:
	var metadata: Dictionary = adventure.get("adventure", {}) if typeof(adventure.get("adventure", {})) == TYPE_DICTIONARY else {}
	var adventure_id := str(metadata.get("id", ""))
	var summary := AdventureManager.get_adventure_progress_summary(adventure_id)
	var has_progress := int(summary.get("solved", 0)) > 0 or int(summary.get("stars", 0)) > 0
	if AdventureManager.has_method("has_adventure_progress"):
		has_progress = has_progress or bool(AdventureManager.call("has_adventure_progress", adventure_id))
	var pack_panel := PanelContainer.new()
	pack_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pack_panel.add_theme_stylebox_override("panel", _make_adventure_panel_style(Color(0.065, 0.078, 0.125, 1.0), Color(1.0, 0.82, 0.28, 0.34)))
	adventure_content.add_child(pack_panel)

	var pack_box := VBoxContainer.new()
	pack_box.add_theme_constant_override("separation", 14)
	pack_panel.add_child(pack_box)

	var title := Label.new()
	title.text = str(metadata.get("title", adventure_id))
	title.set_meta("adventure_role", "pack_title")
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pack_box.add_child(title)

	var description := str(metadata.get("description", "")).strip_edges()
	if description != "":
		var description_label := Label.new()
		description_label.text = description
		description_label.set_meta("adventure_role", "muted")
		description_label.add_theme_color_override("font_color", Color(0.70, 0.76, 0.88))
		description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pack_box.add_child(description_label)

	_add_adventure_progress_line(pack_box,
			int(summary.get("solved", 0)),
			int(summary.get("puzzles", 0)),
			int(summary.get("stars", 0)),
			int(summary.get("max_stars", 0)),
			true)

	var resume := AdventureManager.get_first_playable_puzzle(adventure_id)
	if not resume.is_empty():
		var resume_btn := Button.new()
		resume_btn.text = tr("Continue Adventure")
		resume_btn.tooltip_text = resume_btn.text
		resume_btn.set_meta("adventure_role", "resume")
		resume_btn.custom_minimum_size = Vector2(0, 56)
		resume_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_apply_adventure_button_style(resume_btn, true)
		resume_btn.pressed.connect(_start_adventure_puzzle.bind(
				adventure_id,
				int(resume["block_index"]),
				int(resume["puzzle_index"])))
		pack_box.add_child(resume_btn)
	if has_progress:
		var reset_btn := Button.new()
		reset_btn.text = tr("Reset Progress")
		reset_btn.tooltip_text = reset_btn.text
		reset_btn.set_meta("adventure_role", "compact")
		reset_btn.custom_minimum_size = Vector2(0, 44)
		reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_apply_adventure_button_style(reset_btn, false)
		reset_btn.pressed.connect(_show_adventure_reset_confirmation.bind(adventure_id, str(metadata.get("title", adventure_id))))
		pack_box.add_child(reset_btn)

	var blocks: Array = adventure.get("blocks", []) if typeof(adventure.get("blocks", [])) == TYPE_ARRAY else []
	var expanded_block := _get_adventure_expanded_block(adventure_id, blocks)
	var locked_preview_added := false
	var hidden_locked_count := 0
	for block_index in blocks.size():
		if typeof(blocks[block_index]) != TYPE_DICTIONARY:
			continue
		var unlocked := AdventureManager.is_block_unlocked(adventure_id, block_index)
		if not unlocked and locked_preview_added:
			hidden_locked_count += 1
			continue
		_add_adventure_block(pack_box, adventure_id, blocks[block_index], block_index, block_index == expanded_block)
		if not unlocked:
			locked_preview_added = true
	if hidden_locked_count > 0:
		_add_adventure_locked_summary(pack_box, hidden_locked_count)

func _add_adventure_block(parent: Control, adventure_id: String, block: Dictionary, block_index: int, expanded: bool) -> void:
	var block_progress := AdventureManager.get_block_progress(adventure_id, block_index)
	var unlocked := AdventureManager.is_block_unlocked(adventure_id, block_index)
	var block_panel := PanelContainer.new()
	block_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	block_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block_panel.add_theme_stylebox_override("panel", _make_adventure_panel_style(
			Color(0.044, 0.052, 0.082, 1.0) if unlocked else Color(0.036, 0.040, 0.058, 1.0),
			Color(0.80, 0.92, 1.0, 0.22) if unlocked else Color(0.45, 0.50, 0.62, 0.18)))
	parent.add_child(block_panel)

	var block_box := VBoxContainer.new()
	block_box.mouse_filter = Control.MOUSE_FILTER_PASS
	block_box.add_theme_constant_override("separation", 10)
	block_panel.add_child(block_box)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_theme_constant_override("separation", 10)
	block_box.add_child(header)

	var block_label := Label.new()
	block_label.text = str(block.get("title", "Block %d" % (block_index + 1)))
	block_label.set_meta("adventure_role", "block_title")
	block_label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.98) if unlocked else Color(0.56, 0.60, 0.70))
	block_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	block_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block_label.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_child(block_label)

	if unlocked and not expanded:
		var open_btn := Button.new()
		open_btn.text = tr("Open")
		open_btn.tooltip_text = open_btn.text
		open_btn.set_meta("adventure_role", "compact")
		open_btn.custom_minimum_size = Vector2(92, 38)
		_apply_adventure_button_style(open_btn, false)
		open_btn.pressed.connect(_expand_adventure_block.bind(adventure_id, block_index))
		header.add_child(open_btn)

	_add_adventure_progress_line(block_box,
			int(block_progress.get("solved", 0)),
			int(block_progress.get("puzzles", 0)),
			int(block_progress.get("stars", 0)),
			int(block_progress.get("max_stars", 0)),
			false)

	if not unlocked:
		var locked_label := Label.new()
		locked_label.text = "%s - %s" % [tr("Locked"), tr("Clear previous block to unlock.")]
		locked_label.set_meta("adventure_role", "muted")
		locked_label.add_theme_color_override("font_color", Color(0.50, 0.56, 0.70))
		locked_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		locked_label.mouse_filter = Control.MOUSE_FILTER_PASS
		block_box.add_child(locked_label)
		return

	if not expanded:
		return

	var puzzle_grid := GridContainer.new()
	puzzle_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	puzzle_grid.columns = _get_adventure_puzzle_grid_columns()
	puzzle_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	puzzle_grid.add_theme_constant_override("h_separation", 8)
	puzzle_grid.add_theme_constant_override("v_separation", 8)
	block_box.add_child(puzzle_grid)

	var puzzles: Array = block.get("puzzles", []) if typeof(block.get("puzzles", [])) == TYPE_ARRAY else []
	for puzzle_index in puzzles.size():
		var progress := AdventureManager.get_puzzle_progress(adventure_id, block_index, puzzle_index)
		var stars := int(progress.get("stars", 0))
		var platinum := int(progress.get("best_score", -1)) > SCORE_MAX
		var button := Button.new()
		button.text = "%02d\n%s" % [puzzle_index + 1, _format_adventure_stars(stars)]
		button.tooltip_text = str((puzzles[puzzle_index] as Dictionary).get("title", "Puzzle %d" % (puzzle_index + 1))) if typeof(puzzles[puzzle_index]) == TYPE_DICTIONARY else button.text
		button.disabled = not unlocked
		button.set_meta("adventure_role", "puzzle")
		button.custom_minimum_size = Vector2(0, 58)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_apply_adventure_button_style(button, stars > 0, platinum)
		button.pressed.connect(_start_adventure_puzzle.bind(adventure_id, block_index, puzzle_index))
		puzzle_grid.add_child(button)

func _add_adventure_locked_summary(parent: Control, hidden_locked_count: int) -> void:
	var summary_panel := PanelContainer.new()
	summary_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	summary_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_panel.add_theme_stylebox_override("panel", _make_adventure_panel_style(
			Color(0.030, 0.034, 0.048, 1.0),
			Color(0.45, 0.50, 0.62, 0.14)))
	parent.add_child(summary_panel)

	var label := Label.new()
	label.text = _format_more_locked_blocks(hidden_locked_count)
	label.set_meta("adventure_role", "muted")
	label.add_theme_color_override("font_color", Color(0.50, 0.56, 0.70))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	summary_panel.add_child(label)

func _format_more_locked_blocks(hidden_locked_count: int) -> String:
	return tr("1 more locked block") if hidden_locked_count == 1 else tr("%d more locked blocks") % hidden_locked_count

func _add_adventure_progress_line(parent: Control, solved: int, puzzles: int, stars: int, max_stars: int, centered: bool) -> void:
	var label := Label.new()
	label.text = "%d of %d solved    %d of %d stars" % [solved, puzzles, stars, max_stars]
	label.set_meta("adventure_role", "progress")
	label.add_theme_color_override("font_color", Color(0.78, 0.84, 0.96))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(label)

func _show_adventure_reset_confirmation(adventure_id: String, adventure_title: String) -> void:
	if not adventure_overlay:
		return
	_clear_adventure_confirm_overlay()

	adventure_confirm_overlay = Control.new()
	adventure_confirm_overlay.name = "AdventureConfirmOverlay"
	adventure_confirm_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	adventure_confirm_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	adventure_confirm_overlay.z_index = 130
	adventure_overlay.add_child(adventure_confirm_overlay)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.0, 0.0, 0.0, 0.62)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_clear_adventure_confirm_overlay()
	)
	adventure_confirm_overlay.add_child(backdrop)

	var area := get_viewport_rect().size
	var modal_scale := clampf(_get_ui_scale(area), 1.15, 1.72)
	var card_width := minf(area.x - 28.0 * modal_scale, 560.0 * modal_scale)
	var card_height := minf(area.y - 28.0 * modal_scale, 250.0 * modal_scale)
	var card := PanelContainer.new()
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", _make_adventure_panel_style(
			Color(0.045, 0.052, 0.082, 1.0),
			Color(1.0, 0.58, 0.34, 0.52)))
	adventure_confirm_overlay.add_child(card)
	_set_control_rect(card, Rect2(
			(area.x - card_width) * 0.5,
			(area.y - card_height) * 0.5,
			card_width,
			card_height))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(round(12.0 * modal_scale)))
	card.add_child(box)

	var title := Label.new()
	title.text = tr("Clear progress?")
	title.add_theme_font_size_override("font_size", int(round(25.0 * modal_scale)))
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var body := Label.new()
	body.text = tr("Clear progress for %s?") % adventure_title
	body.add_theme_font_size_override("font_size", int(round(17.0 * modal_scale)))
	body.add_theme_color_override("font_color", Color(0.82, 0.88, 1.0))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(body)

	var note := Label.new()
	note.text = tr("This cannot be undone.")
	note.add_theme_font_size_override("font_size", int(round(14.0 * modal_scale)))
	note.add_theme_color_override("font_color", Color(0.70, 0.76, 0.88))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", int(round(12.0 * modal_scale)))
	box.add_child(buttons)

	var cancel_btn := Button.new()
	cancel_btn.text = tr("Cancel")
	cancel_btn.tooltip_text = cancel_btn.text
	cancel_btn.custom_minimum_size = Vector2(126.0 * modal_scale, 46.0 * modal_scale)
	_apply_adventure_button_style(cancel_btn, false)
	cancel_btn.pressed.connect(_clear_adventure_confirm_overlay)
	buttons.add_child(cancel_btn)

	var clear_btn := Button.new()
	clear_btn.text = tr("Clear Progress")
	clear_btn.tooltip_text = clear_btn.text
	clear_btn.custom_minimum_size = Vector2(156.0 * modal_scale, 46.0 * modal_scale)
	_apply_adventure_button_style(clear_btn, true)
	clear_btn.pressed.connect(_confirm_clear_adventure_progress.bind(adventure_id))
	buttons.add_child(clear_btn)

	if AudioManager:
		AudioManager.play_click()

func _confirm_clear_adventure_progress(adventure_id: String) -> void:
	if AdventureManager and AdventureManager.has_method("clear_adventure_progress"):
		AdventureManager.call("clear_adventure_progress", adventure_id)
	if adventure_expanded_blocks.has(adventure_id):
		adventure_expanded_blocks.erase(adventure_id)
	_clear_adventure_confirm_overlay()
	_populate_adventure_dialog()
	_layout_adventure_overlay(get_viewport_rect().size)
	if AudioManager:
		AudioManager.play_click()

func _clear_adventure_confirm_overlay() -> void:
	if adventure_confirm_overlay and is_instance_valid(adventure_confirm_overlay):
		adventure_confirm_overlay.queue_free()
	adventure_confirm_overlay = null

func _get_adventure_expanded_block(adventure_id: String, blocks: Array) -> int:
	var default_block := _get_default_adventure_expanded_block(adventure_id, blocks)
	if default_block < 0:
		return default_block
	var expanded := int(adventure_expanded_blocks.get(adventure_id, default_block))
	if expanded < 0 or expanded >= blocks.size() or not AdventureManager.is_block_unlocked(adventure_id, expanded):
		expanded = default_block
	adventure_expanded_blocks[adventure_id] = expanded
	return expanded

func _get_default_adventure_expanded_block(adventure_id: String, blocks: Array) -> int:
	var fallback := -1
	for block_index in blocks.size():
		if not AdventureManager.is_block_unlocked(adventure_id, block_index):
			break
		fallback = block_index
		var block_progress := AdventureManager.get_block_progress(adventure_id, block_index)
		if int(block_progress.get("solved", 0)) < int(block_progress.get("puzzles", 0)):
			return block_index
	return fallback

func _expand_adventure_block(adventure_id: String, block_index: int) -> void:
	if _is_adventure_scroll_suppressing_clicks():
		return
	adventure_expanded_blocks[adventure_id] = block_index
	_populate_adventure_dialog()
	_layout_adventure_overlay(get_viewport_rect().size)
	if AudioManager:
		AudioManager.play_click()

func _get_adventure_puzzle_grid_columns() -> int:
	var area := get_viewport_rect().size
	return 10 if area.x > area.y * 1.08 else 5

func _format_adventure_stars(stars: int) -> String:
	var filled := mini(5, maxi(0, stars))
	var filled_symbol := tr("UI Symbol Star Filled")
	var empty_symbol := tr("UI Symbol Star Empty")
	if filled_symbol == "UI Symbol Star Filled":
		filled_symbol = "*"
	if empty_symbol == "UI Symbol Star Empty":
		empty_symbol = "."
	var text := ""
	for idx in 5:
		text += filled_symbol if idx < filled else empty_symbol
	return text

func _make_adventure_panel_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.content_margin_left = 14
	style.content_margin_top = 12
	style.content_margin_right = 14
	style.content_margin_bottom = 12
	return style

func _apply_adventure_button_style(button: Button, accent: bool, platinum: bool = false) -> void:
	var normal_border := Color(0.70, 0.90, 1.0, 0.54) if platinum else Color(1.0, 0.86, 0.35, 0.42)
	var hover_border := Color(0.86, 0.98, 1.0, 0.68) if platinum else Color(1.0, 0.94, 0.55, 0.58)
	var pressed_border := Color(0.64, 0.86, 1.0, 0.68) if platinum else Color(1.0, 0.74, 0.26, 0.58)
	var normal := _make_menu_button_style(
			Color(0.082, 0.102, 0.160, 1.0) if accent else Color(0.058, 0.070, 0.108, 1.0),
			normal_border if accent else Color(0.74, 0.84, 1.0, 0.22),
			7, 2)
	var hover := _make_menu_button_style(
			Color(0.105, 0.128, 0.196, 1.0) if accent else Color(0.074, 0.090, 0.138, 1.0),
			hover_border if accent else Color(0.86, 0.94, 1.0, 0.34),
			7, 2)
	var pressed := _make_menu_button_style(
			Color(0.046, 0.060, 0.100, 1.0),
			pressed_border if accent else Color(0.86, 0.94, 1.0, 0.32),
			7, 2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	var font_color := ADVENTURE_PLATINUM_TEXT_COLOR if platinum else (ADVENTURE_GOLD_TEXT_COLOR if accent else Color(0.94, 0.97, 1.0))
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_disabled_color", Color(0.42, 0.46, 0.56))
	button.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.58))
	button.add_theme_constant_override("outline_size", 1)

func _start_adventure_puzzle(adventure_id: String, block_index: int, puzzle_index: int) -> void:
	if _is_adventure_scroll_suppressing_clicks():
		return
	if not AdventureManager.start_puzzle(adventure_id, block_index, puzzle_index):
		if AudioManager:
			AudioManager.play_invalid()
		return
	var board_code := AdventureManager.get_current_board_code()
	if board_code == "":
		AdventureManager.clear_current_puzzle()
		if AudioManager:
			AudioManager.play_invalid()
		return
	GameSettings.set_pending_board_code(board_code)
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
	close_btn.text = "X"
	close_btn.tooltip_text = tr("Close")
	close_btn.custom_minimum_size = Vector2(52, 38)
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

func _input(event: InputEvent):
	if adventure_overlay and adventure_overlay.visible:
		_handle_adventure_scroll_input(event)

func _handle_adventure_scroll_input(event: InputEvent) -> void:
	if not adventure_scroll or not is_instance_valid(adventure_scroll):
		return
	var scroll_rect := adventure_scroll.get_global_rect()
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if scroll_rect.has_point(touch.position):
				_begin_adventure_scroll_drag(touch.position)
		else:
			_finish_adventure_scroll_drag()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _adventure_scroll_drag_active or scroll_rect.has_point(drag.position):
			if not _adventure_scroll_drag_active:
				_begin_adventure_scroll_drag(drag.position)
			_drag_adventure_scroll_to(drag.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.pressed:
			if scroll_rect.has_point(mouse_button.position):
				_begin_adventure_scroll_drag(mouse_button.position)
		else:
			_finish_adventure_scroll_drag()
	elif event is InputEventMouseMotion and _adventure_scroll_drag_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var motion := event as InputEventMouseMotion
		_drag_adventure_scroll_to(motion.position)

func _begin_adventure_scroll_drag(pos: Vector2) -> void:
	_adventure_scroll_drag_active = true
	_adventure_scroll_drag_started = false
	_adventure_scroll_drag_start = pos
	_adventure_scroll_drag_last = pos

func _drag_adventure_scroll_to(pos: Vector2) -> void:
	if not _adventure_scroll_drag_active or not adventure_scroll:
		return
	if not _adventure_scroll_drag_started:
		if _adventure_scroll_drag_start.distance_to(pos) < ADVENTURE_SCROLL_DRAG_THRESHOLD:
			return
		_adventure_scroll_drag_started = true
	var delta_y := pos.y - _adventure_scroll_drag_last.y
	if absf(delta_y) >= 0.5:
		adventure_scroll.scroll_vertical = maxi(0, adventure_scroll.scroll_vertical - int(round(delta_y)))
		_adventure_scroll_drag_last = pos
		get_viewport().set_input_as_handled()

func _finish_adventure_scroll_drag() -> void:
	if _adventure_scroll_drag_started:
		_adventure_scroll_suppress_click_until = Time.get_ticks_msec() + ADVENTURE_SCROLL_CLICK_SUPPRESS_MS
		get_viewport().set_input_as_handled()
	_reset_adventure_scroll_drag()

func _reset_adventure_scroll_drag() -> void:
	_adventure_scroll_drag_active = false
	_adventure_scroll_drag_started = false
	_adventure_scroll_drag_start = Vector2.ZERO
	_adventure_scroll_drag_last = Vector2.ZERO

func _is_adventure_scroll_suppressing_clicks() -> bool:
	return Time.get_ticks_msec() < _adventure_scroll_suppress_click_until

func _unhandled_input(event: InputEvent):
	if adventure_overlay and adventure_overlay.visible and event.is_action_pressed("ui_cancel"):
		_close_adventure_dialog()
		get_viewport().set_input_as_handled()
		return
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
