extends Node

const CAPACITY_MIN := 3
const CAPACITY_MAX := 8
const SETTINGS_PATH := "user://settings.cfg"
const MUSIC_VOLUME_DEFAULT := 0.65
const EFFECTS_VOLUME_DEFAULT := 0.85

const DIFFICULTIES := {
	"easy": {
		"label": "Easy",
		"filled_beakers": 4,
		"empty_beakers": 2,
	},
	"normal": {
		"label": "Normal",
		"filled_beakers": 6,
		"empty_beakers": 2,
	},
	"hard": {
		"label": "Hard",
		"filled_beakers": 8,
		"empty_beakers": 2,
	},
}

var beaker_capacity: int = 4
var difficulty: String = "normal"
var show_goal_hint: bool = true
var music_volume: float = MUSIC_VOLUME_DEFAULT
var effects_volume: float = EFFECTS_VOLUME_DEFAULT

func _ready() -> void:
	load_settings()
	_apply_audio_settings.call_deferred()

func set_beaker_capacity(value: int) -> void:
	beaker_capacity = clampi(value, CAPACITY_MIN, CAPACITY_MAX)
	save_settings()

func set_difficulty(value: String) -> void:
	if DIFFICULTIES.has(value):
		difficulty = value
		save_settings()

func set_show_goal_hint(value: bool) -> void:
	show_goal_hint = value
	save_settings()

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	save_settings()
	_apply_audio_settings()

func set_effects_volume(value: float) -> void:
	effects_volume = clampf(value, 0.0, 1.0)
	save_settings()
	_apply_audio_settings()

func get_difficulty_label() -> String:
	return str(DIFFICULTIES[difficulty]["label"])

func get_filled_beaker_count() -> int:
	return int(DIFFICULTIES[difficulty]["filled_beakers"])

func get_empty_beaker_count() -> int:
	return int(DIFFICULTIES[difficulty]["empty_beakers"])

func get_beaker_count() -> int:
	return get_filled_beaker_count() + get_empty_beaker_count()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	beaker_capacity = clampi(int(cfg.get_value("game", "beaker_capacity", beaker_capacity)), CAPACITY_MIN, CAPACITY_MAX)
	var saved_difficulty := str(cfg.get_value("game", "difficulty", difficulty))
	if DIFFICULTIES.has(saved_difficulty):
		difficulty = saved_difficulty
	show_goal_hint = bool(cfg.get_value("game", "show_goal_hint", show_goal_hint))
	music_volume = clampf(float(cfg.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
	effects_volume = clampf(float(cfg.get_value("audio", "effects_volume", effects_volume)), 0.0, 1.0)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "beaker_capacity", beaker_capacity)
	cfg.set_value("game", "difficulty", difficulty)
	cfg.set_value("game", "show_goal_hint", show_goal_hint)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "effects_volume", effects_volume)
	cfg.save(SETTINGS_PATH)

func _apply_audio_settings() -> void:
	if AudioManager and AudioManager.has_method("apply_volume_settings"):
		AudioManager.apply_volume_settings()
