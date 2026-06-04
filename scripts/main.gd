extends Node2D

@export var move_label: String = "Moves"
@export var win_label: String = "moves"

@onready var towers = $Towers
@onready var move_counter = $UI/MoveCounter
@onready var depth_slider = get_node_or_null("DepthRow/DepthSlider")
@onready var depth_value  = get_node_or_null("DepthRow/DepthValue")

var moves = 0

func _ready():
	towers.disk_moved.connect(_on_disk_moved)
	update_move_counter()
	# Initialize depth slider from GameSettings (only if the slider exists)
	if depth_slider:
		depth_slider.value = GameSettings.beaker_capacity
		depth_value.text   = str(GameSettings.beaker_capacity)

func _on_disk_moved():
	moves += 1
	update_move_counter()
	if towers.check_complete():
		_show_victory_delayed()

func update_move_counter():
	move_counter.text = "%s: %d" % [move_label, moves]

func _show_victory_delayed():
	if AudioManager:
		AudioManager.play_win()
	await get_tree().create_timer(1.2).timeout
	if get_node_or_null("VictoryOverlay"):
		return
	show_victory_screen()

func show_victory_screen():
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

	# Border strip at top of card
	var stripe := ColorRect.new()
	stripe.color = Color(1.0, 0.75, 0.1, 1.0)
	stripe.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stripe.offset_bottom = 6.0
	card.add_child(stripe)

	# Layout inside card
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_top = 14.0
	vb.add_theme_constant_override("separation", 10)
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

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vb.add_child(spacer)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 24)
	vb.add_child(hb)

	var again_btn := Button.new()
	again_btn.text = "Play Again"
	again_btn.add_theme_font_size_override("font_size", 22)
	again_btn.custom_minimum_size = Vector2(160, 50)
	again_btn.pressed.connect(reset_game)
	hb.add_child(again_btn)

	var menu_btn := Button.new()
	menu_btn.text = "Menu"
	menu_btn.add_theme_font_size_override("font_size", 22)
	menu_btn.custom_minimum_size = Vector2(120, 50)
	menu_btn.pressed.connect(go_to_menu)
	hb.add_child(menu_btn)

	# Animate in
	var tw := create_tween().set_parallel()
	tw.tween_property(bg,   "color", Color(0, 0, 0, 0.72), 0.35)
	tw.tween_property(card, "scale", Vector2(1, 1),         0.50) \
	  .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_depth_changed(value: float):
	if not depth_slider:
		return
	GameSettings.beaker_capacity = int(value)
	depth_value.text = str(int(value))

func reset_game():
	moves = 0
	update_move_counter()
	towers.reset()
	var overlay = get_node_or_null("VictoryOverlay")
	if overlay:
		overlay.queue_free()

func go_to_menu():
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
