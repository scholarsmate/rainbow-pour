extends Node

const CAPACITY_MIN := 3
const CAPACITY_MAX := 8
const MAX_BEAKERS := 16
const HANOI_DISK_COUNT_MIN := 5
const HANOI_DISK_COUNT_MAX := 10
const SETTINGS_PATH := "user://settings.cfg"
const MUSIC_VOLUME_DEFAULT := 0.65
const EFFECTS_VOLUME_DEFAULT := 0.85
const LIQUID_ALPHA_MIN := 0.35
const LIQUID_ALPHA_MAX := 1.0
const LIQUID_ALPHA_DEFAULT := 0.86
const LIQUID_PALETTE_DEFAULT := "classic"

const LIQUID_PALETTE_ORDER := ["classic", "colorblind", "high_contrast"]
const LIQUID_PALETTES := {
	"classic": {
		"label": "Classic",
		"colors": [
			Color(0.95, 0.18, 0.18),
			Color(1.00, 0.52, 0.04),
			Color(0.94, 0.82, 0.04),
			Color(0.58, 0.92, 0.04),
			Color(0.06, 0.84, 0.30),
			Color(0.00, 0.78, 0.72),
			Color(0.15, 0.50, 1.00),
			Color(0.33, 0.26, 1.00),
			Color(0.72, 0.18, 0.98),
			Color(0.07, 0.74, 0.86),
			Color(1.00, 0.27, 0.58),
			Color(0.98, 0.48, 0.18),
			Color(0.56, 0.34, 0.16),
			Color(0.80, 0.88, 1.00),
			Color(0.08, 0.18, 0.28),
			Color(0.93, 0.93, 0.93),
			Color(0.42, 0.48, 0.55),
		],
	},
	"colorblind": {
		"label": "Colorblind",
		"colors": [
			Color(0.90, 0.62, 0.00),
			Color(0.34, 0.71, 0.91),
			Color(0.00, 0.62, 0.45),
			Color(0.94, 0.89, 0.26),
			Color(0.00, 0.45, 0.70),
			Color(0.84, 0.37, 0.00),
			Color(0.80, 0.47, 0.65),
			Color(0.58, 0.58, 0.58),
			Color(0.96, 0.73, 0.80),
			Color(0.36, 0.16, 0.68),
			Color(0.13, 0.50, 0.24),
			Color(0.72, 0.62, 0.34),
			Color(0.36, 0.72, 0.68),
			Color(0.96, 0.48, 0.28),
			Color(0.82, 0.82, 0.82),
			Color(0.12, 0.12, 0.12),
		],
	},
	"high_contrast": {
		"label": "High Contrast",
		"colors": [
			Color(1.00, 0.08, 0.08),
			Color(1.00, 0.92, 0.00),
			Color(0.00, 0.88, 0.36),
			Color(0.00, 0.78, 1.00),
			Color(0.24, 0.26, 1.00),
			Color(1.00, 0.18, 0.82),
			Color(0.96, 0.96, 0.96),
			Color(0.06, 0.06, 0.06),
			Color(1.00, 0.54, 0.00),
			Color(0.62, 1.00, 0.00),
			Color(0.00, 1.00, 0.78),
			Color(0.00, 0.34, 1.00),
			Color(0.70, 0.00, 1.00),
			Color(1.00, 0.00, 0.34),
			Color(0.72, 0.72, 0.72),
			Color(0.30, 0.30, 0.30),
		],
	},
}
const LIQUID_SYMBOLS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F", "G"]

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
var hanoi_disk_count: int = 5
var difficulty: String = "normal"
var show_goal_hint: bool = true
var special_beakers_enabled: bool = true
var liquid_alpha: float = LIQUID_ALPHA_DEFAULT
var liquid_palette: String = LIQUID_PALETTE_DEFAULT
var show_liquid_symbols: bool = true
var music_volume: float = MUSIC_VOLUME_DEFAULT
var effects_volume: float = EFFECTS_VOLUME_DEFAULT
var pending_board_code: String = ""

func _ready() -> void:
	load_settings()
	_apply_audio_settings.call_deferred()

func set_beaker_capacity(value: int) -> void:
	beaker_capacity = clampi(value, CAPACITY_MIN, CAPACITY_MAX)
	save_settings()

func set_hanoi_disk_count(value: int) -> void:
	hanoi_disk_count = clampi(value, HANOI_DISK_COUNT_MIN, HANOI_DISK_COUNT_MAX)
	save_settings()

func set_difficulty(value: String) -> void:
	if DIFFICULTIES.has(value):
		difficulty = value
		save_settings()

func set_show_goal_hint(value: bool) -> void:
	show_goal_hint = value
	save_settings()

func set_special_beakers_enabled(value: bool) -> void:
	special_beakers_enabled = value
	save_settings()

func set_liquid_alpha(value: float) -> void:
	liquid_alpha = clampf(value, LIQUID_ALPHA_MIN, LIQUID_ALPHA_MAX)
	save_settings()

func set_liquid_palette(value: String) -> void:
	if LIQUID_PALETTES.has(value):
		liquid_palette = value
		save_settings()

func set_show_liquid_symbols(value: bool) -> void:
	show_liquid_symbols = value
	save_settings()

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	save_settings()
	_apply_audio_settings()

func set_effects_volume(value: float) -> void:
	effects_volume = clampf(value, 0.0, 1.0)
	save_settings()
	_apply_audio_settings()

func set_pending_board_code(value: String) -> void:
	pending_board_code = value.strip_edges()

func consume_pending_board_code() -> String:
	var code := pending_board_code
	pending_board_code = ""
	return code

func get_difficulty_label() -> String:
	return tr(str(DIFFICULTIES[difficulty]["label"]))

func get_filled_beaker_count() -> int:
	return int(DIFFICULTIES[difficulty]["filled_beakers"])

func get_empty_beaker_count() -> int:
	return int(DIFFICULTIES[difficulty]["empty_beakers"])

func get_beaker_count() -> int:
	return get_filled_beaker_count() + get_empty_beaker_count()

func get_liquid_colors() -> Array:
	var palette_key := liquid_palette if LIQUID_PALETTES.has(liquid_palette) else LIQUID_PALETTE_DEFAULT
	return LIQUID_PALETTES[palette_key]["colors"]

func get_liquid_symbols() -> Array:
	return LIQUID_SYMBOLS

func get_liquid_palette_label(key: String) -> String:
	if not LIQUID_PALETTES.has(key):
		return tr(key.capitalize())
	return tr(str(LIQUID_PALETTES[key]["label"]))

func find_difficulty_for_counts(filled_count: int, empty_count: int) -> String:
	for key in DIFFICULTIES:
		if (int(DIFFICULTIES[key]["filled_beakers"]) == filled_count
				and int(DIFFICULTIES[key]["empty_beakers"]) == empty_count):
			return key
	return ""

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	beaker_capacity = clampi(int(cfg.get_value("game", "beaker_capacity", beaker_capacity)), CAPACITY_MIN, CAPACITY_MAX)
	hanoi_disk_count = clampi(int(cfg.get_value("game", "hanoi_disk_count", hanoi_disk_count)), HANOI_DISK_COUNT_MIN, HANOI_DISK_COUNT_MAX)
	var saved_difficulty := str(cfg.get_value("game", "difficulty", difficulty))
	if DIFFICULTIES.has(saved_difficulty):
		difficulty = saved_difficulty
	show_goal_hint = bool(cfg.get_value("game", "show_goal_hint", show_goal_hint))
	special_beakers_enabled = bool(cfg.get_value("game", "special_beakers_enabled", special_beakers_enabled))
	liquid_alpha = clampf(float(cfg.get_value("display", "liquid_alpha", liquid_alpha)), LIQUID_ALPHA_MIN, LIQUID_ALPHA_MAX)
	var saved_palette := str(cfg.get_value("display", "liquid_palette", liquid_palette))
	if LIQUID_PALETTES.has(saved_palette):
		liquid_palette = saved_palette
	show_liquid_symbols = bool(cfg.get_value("display", "show_liquid_symbols", show_liquid_symbols))
	music_volume = clampf(float(cfg.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
	effects_volume = clampf(float(cfg.get_value("audio", "effects_volume", effects_volume)), 0.0, 1.0)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "beaker_capacity", beaker_capacity)
	cfg.set_value("game", "hanoi_disk_count", hanoi_disk_count)
	cfg.set_value("game", "difficulty", difficulty)
	cfg.set_value("game", "show_goal_hint", show_goal_hint)
	cfg.set_value("game", "special_beakers_enabled", special_beakers_enabled)
	cfg.set_value("display", "liquid_alpha", liquid_alpha)
	cfg.set_value("display", "liquid_palette", liquid_palette)
	cfg.set_value("display", "show_liquid_symbols", show_liquid_symbols)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "effects_volume", effects_volume)
	cfg.save(SETTINGS_PATH)

func _apply_audio_settings() -> void:
	if AudioManager and AudioManager.has_method("apply_volume_settings"):
		AudioManager.apply_volume_settings()
