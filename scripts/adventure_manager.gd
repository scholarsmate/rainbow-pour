extends Node

const ADVENTURE_DIR := "res://assets/adventures"
const PROGRESS_PATH := "user://adventure_progress.json"
const SCHEMA_VERSION_MIN := 1
const SCHEMA_VERSION_MAX := 1
const PROGRESS_SCHEMA_VERSION := 2

const PROGRESS_DEFAULT := {
	"version": PROGRESS_SCHEMA_VERSION,
	"adventures": {},
}

var _adventures: Array = []
var _adventure_by_id: Dictionary = {}
var _progress: Dictionary = PROGRESS_DEFAULT.duplicate(true)
var _current: Dictionary = {}

func _ready() -> void:
	reload_adventures()
	_load_progress()

func reload_adventures() -> void:
	_adventures.clear()
	_adventure_by_id.clear()

	var dir := DirAccess.open(ADVENTURE_DIR)
	if not dir:
		push_warning("Adventure directory not found: %s" % ADVENTURE_DIR)
		_clear_invalid_current()
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension().to_lower() == "json":
			_load_adventure_file("%s/%s" % [ADVENTURE_DIR, file_name])
		file_name = dir.get_next()
	dir.list_dir_end()

	_adventures.sort_custom(func(left, right):
		var left_meta := _adventure_meta(_as_dictionary(left))
		var right_meta := _adventure_meta(_as_dictionary(right))
		return _localized_text_value(_as_dictionary(left), left_meta, "title") < _localized_text_value(_as_dictionary(right), right_meta, "title")
	)
	_clear_invalid_current()

func has_adventures() -> bool:
	return not _adventures.is_empty()

func get_adventures() -> Array:
	var localized := []
	for adventure in _adventures:
		localized.append(_localized_adventure(_as_dictionary(adventure)))
	return localized

func get_adventure(adventure_id: String) -> Dictionary:
	var adventure := _get_adventure_ref(adventure_id)
	return _localized_adventure(adventure) if not adventure.is_empty() else {}

func start_puzzle(adventure_id: String, block_index: int, puzzle_index: int) -> bool:
	if not is_block_unlocked(adventure_id, block_index):
		return false
	var puzzle := _get_puzzle_ref(adventure_id, block_index, puzzle_index)
	if puzzle.is_empty():
		return false
	var board_code := str(puzzle.get("board_code", "")).strip_edges()
	if board_code == "":
		return false
	_current = {
		"adventure_id": adventure_id,
		"block_index": block_index,
		"puzzle_index": puzzle_index,
		"puzzle_id": _puzzle_id(adventure_id, block_index, puzzle_index, puzzle),
	}
	return true

func clear_current_puzzle() -> void:
	_current.clear()

func is_playing_adventure() -> bool:
	if _current.is_empty():
		return false
	return not _get_puzzle_ref(get_current_adventure_id(), get_current_block_index(), get_current_puzzle_index()).is_empty()

func get_current_adventure_id() -> String:
	return str(_current.get("adventure_id", ""))

func get_current_block_index() -> int:
	return int(_current.get("block_index", -1))

func get_current_puzzle_index() -> int:
	return int(_current.get("puzzle_index", -1))

func get_current_puzzle() -> Dictionary:
	var adventure := _get_adventure_ref(get_current_adventure_id())
	var puzzle := _get_puzzle_ref(get_current_adventure_id(), get_current_block_index(), get_current_puzzle_index())
	return _localized_puzzle(adventure, puzzle) if not puzzle.is_empty() else {}

func get_current_block() -> Dictionary:
	var adventure := _get_adventure_ref(get_current_adventure_id())
	var block := _get_block_ref(get_current_adventure_id(), get_current_block_index())
	return _localized_block(adventure, block) if not block.is_empty() else {}

func get_current_board_code() -> String:
	var puzzle := _get_puzzle_ref(get_current_adventure_id(), get_current_block_index(), get_current_puzzle_index())
	return str(puzzle.get("board_code", "")).strip_edges()

func get_current_title() -> String:
	var adventure := _get_adventure_ref(get_current_adventure_id())
	var adventure_title := _localized_text_value(adventure, _adventure_meta(adventure), "title")
	var blocks := _adventure_blocks(adventure)
	var block := _get_block_ref(get_current_adventure_id(), get_current_block_index())
	var puzzle := _get_puzzle_ref(get_current_adventure_id(), get_current_block_index(), get_current_puzzle_index())
	var puzzles := _block_puzzles(block)
	var block_title := _localized_text_value(adventure, block, "title", "Rank %d" % (get_current_block_index() + 1))
	var puzzle_title := _localized_text_value(adventure, puzzle, "title")
	var position_title := tr("Rank %d/%d: %s | Puzzle %d/%d: %s") % [
		get_current_block_index() + 1,
		maxi(1, blocks.size()),
		block_title,
		get_current_puzzle_index() + 1,
		maxi(1, puzzles.size()),
		puzzle_title,
	]
	if adventure_title == "":
		return position_title
	if puzzle_title == "" or block_title == "":
		return adventure_title
	return "%s: %s" % [adventure_title, position_title]

func get_current_rank_progress() -> Dictionary:
	var adventure_id := get_current_adventure_id()
	var block_index := get_current_block_index()
	var adventure := _get_adventure_ref(adventure_id)
	var blocks := _adventure_blocks(adventure)
	var block := _get_block_ref(adventure_id, block_index)
	if block.is_empty():
		return {}
	var block_progress := get_block_progress(adventure_id, block_index)
	var unlock := _as_dictionary(block.get("unlock_next", {}))
	var final_rank := block_index >= blocks.size() - 1
	var threshold := int(unlock.get("min_stars", 0))
	var requires_all_solved := bool(unlock.get("requires_all_solved", true))
	var solved := int(block_progress.get("solved", 0))
	var puzzles := int(block_progress.get("puzzles", 0))
	var stars := int(block_progress.get("stars", 0))
	return {
		"rank_index": block_index + 1,
		"rank_count": blocks.size(),
		"rank_title": _localized_text_value(adventure, block, "title", "Rank %d" % (block_index + 1)),
		"puzzle_index": get_current_puzzle_index() + 1,
		"puzzle_count": puzzles,
		"solved": solved,
		"puzzles": puzzles,
		"puzzles_remaining": maxi(0, puzzles - solved),
		"stars": stars,
		"max_stars": int(block_progress.get("max_stars", puzzles * 5)),
		"threshold": threshold,
		"stars_remaining": maxi(0, threshold - stars),
		"requires_all_solved": requires_all_solved,
		"final_rank": final_rank,
		"next_rank_unlocked": (not final_rank
				and (not requires_all_solved or solved >= puzzles)
				and stars >= threshold),
	}

func is_current_chill() -> bool:
	return str(_current_scoring().get("mode", "")) == "chill"

func get_current_chill_stars() -> int:
	return clampi(int(_current_scoring().get("stars_on_solve", 5)), 1, 5)

func get_current_optimal_pours() -> int:
	var puzzle := _get_puzzle_ref(get_current_adventure_id(), get_current_block_index(), get_current_puzzle_index())
	if puzzle.is_empty() or not puzzle.has("optimal_pours"):
		return -1
	return int(puzzle.get("optimal_pours", -1))

func get_current_pour_limit() -> int:
	var puzzle := _get_puzzle_ref(get_current_adventure_id(), get_current_block_index(), get_current_puzzle_index())
	if puzzle.is_empty() or not puzzle.has("pour_limit"):
		return -1
	return int(puzzle.get("pour_limit", -1))

func get_current_dialog(kind: String) -> Array:
	var adventure := _get_adventure_ref(get_current_adventure_id())
	var puzzle := _get_puzzle_ref(get_current_adventure_id(), get_current_block_index(), get_current_puzzle_index())
	var localized_puzzle := _localized_puzzle(adventure, puzzle)
	var dialog := _as_dictionary(localized_puzzle.get("dialog", {}))
	return _as_array(dialog.get(kind, [])).duplicate(true)

func get_block(adventure_id: String, block_index: int) -> Dictionary:
	var adventure := _get_adventure_ref(adventure_id)
	var block := _get_block_ref(adventure_id, block_index)
	return _localized_block(adventure, block) if not block.is_empty() else {}

func get_puzzle(adventure_id: String, block_index: int, puzzle_index: int) -> Dictionary:
	var adventure := _get_adventure_ref(adventure_id)
	var puzzle := _get_puzzle_ref(adventure_id, block_index, puzzle_index)
	return _localized_puzzle(adventure, puzzle) if not puzzle.is_empty() else {}

func get_puzzle_progress(adventure_id: String, block_index: int, puzzle_index: int) -> Dictionary:
	var progress := _get_puzzle_progress_ref(adventure_id, block_index, puzzle_index, false)
	return progress.duplicate(true) if not progress.is_empty() else {}

func get_block_progress(adventure_id: String, block_index: int) -> Dictionary:
	var puzzles := _block_puzzles(_get_block_ref(adventure_id, block_index))
	var solved := 0
	var stars := 0
	for puzzle_index in puzzles.size():
		var puzzle_progress := get_puzzle_progress(adventure_id, block_index, puzzle_index)
		if bool(puzzle_progress.get("solved", false)):
			solved += 1
		stars += clampi(int(puzzle_progress.get("stars", 0)), 0, 5)
	return {
		"solved": solved,
		"puzzles": puzzles.size(),
		"stars": stars,
		"max_stars": puzzles.size() * 5,
	}

func get_adventure_progress_summary(adventure_id: String) -> Dictionary:
	var blocks := _adventure_blocks(_get_adventure_ref(adventure_id))
	var solved := 0
	var puzzles := 0
	var stars := 0
	var max_stars := 0
	for block_index in blocks.size():
		var block_progress := get_block_progress(adventure_id, block_index)
		solved += int(block_progress.get("solved", 0))
		puzzles += int(block_progress.get("puzzles", 0))
		stars += int(block_progress.get("stars", 0))
		max_stars += int(block_progress.get("max_stars", 0))
	return {
		"solved": solved,
		"puzzles": puzzles,
		"stars": stars,
		"max_stars": max_stars,
	}

func has_adventure_progress(adventure_id: String) -> bool:
	var adventure_progress := _get_adventure_progress_ref(adventure_id, false)
	var puzzles := _as_dictionary(adventure_progress.get("puzzles", {}))
	for puzzle_key in puzzles.keys():
		var puzzle_progress := _as_dictionary(puzzles[puzzle_key])
		if bool(puzzle_progress.get("solved", false)):
			return true
		if int(puzzle_progress.get("stars", 0)) > 0:
			return true
		if int(puzzle_progress.get("attempts_completed", 0)) > 0:
			return true
	return false

func clear_adventure_progress(adventure_id: String) -> bool:
	var all_progress := _all_progress_ref(false)
	if all_progress.is_empty() or not all_progress.has(adventure_id):
		return false
	all_progress.erase(adventure_id)
	_save_progress()
	return true

func is_block_unlocked(adventure_id: String, block_index: int) -> bool:
	if _get_adventure_ref(adventure_id).is_empty():
		return false
	if block_index < 0:
		return false
	if block_index == 0:
		return true
	var previous_block := _get_block_ref(adventure_id, block_index - 1)
	if previous_block.is_empty():
		return false
	var unlock := _as_dictionary(previous_block.get("unlock_next", {}))
	var previous_progress := get_block_progress(adventure_id, block_index - 1)
	if bool(unlock.get("requires_all_solved", true)) and int(previous_progress["solved"]) < int(previous_progress["puzzles"]):
		return false
	return int(previous_progress["stars"]) >= int(unlock.get("min_stars", 0))

func complete_current(moves: int, score: int, stars: int) -> bool:
	if not is_playing_adventure():
		return false
	var puzzle_progress := _get_puzzle_progress_ref(
			get_current_adventure_id(),
			get_current_block_index(),
			get_current_puzzle_index(),
			true)
	if typeof(puzzle_progress) != TYPE_DICTIONARY:
		return false

	var earned_stars := clampi(stars, 1, 5)
	puzzle_progress["solved"] = true
	puzzle_progress["stars"] = maxi(int(puzzle_progress.get("stars", 0)), earned_stars)
	if score >= 0:
		puzzle_progress["best_score"] = maxi(int(puzzle_progress.get("best_score", -1)), score)
	var previous_moves := int(puzzle_progress.get("best_moves", 0))
	puzzle_progress["best_moves"] = maxi(0, moves) if previous_moves <= 0 else mini(previous_moves, maxi(0, moves))
	puzzle_progress["attempts_completed"] = int(puzzle_progress.get("attempts_completed", 0)) + 1
	puzzle_progress["completed_at"] = Time.get_datetime_string_from_system(true)
	_save_progress()
	return true

func get_next_puzzle_after_current() -> Dictionary:
	if not is_playing_adventure():
		return {}
	var adventure_id := get_current_adventure_id()
	var block_index := get_current_block_index()
	var puzzle_index := get_current_puzzle_index()
	var puzzles := _block_puzzles(_get_block_ref(adventure_id, block_index))
	if puzzle_index + 1 < puzzles.size():
		return _make_puzzle_ref(adventure_id, block_index, puzzle_index + 1)
	if is_block_unlocked(adventure_id, block_index + 1):
		var next_puzzles := _block_puzzles(_get_block_ref(adventure_id, block_index + 1))
		if not next_puzzles.is_empty():
			return _make_puzzle_ref(adventure_id, block_index + 1, 0)
	return {}

func get_first_playable_puzzle(adventure_id: String) -> Dictionary:
	var blocks := _adventure_blocks(_get_adventure_ref(adventure_id))
	var fallback := {}
	for block_index in blocks.size():
		if not is_block_unlocked(adventure_id, block_index):
			break
		var puzzles := _block_puzzles(_as_dictionary(blocks[block_index]))
		if not puzzles.is_empty() and fallback.is_empty():
			fallback = _make_puzzle_ref(adventure_id, block_index, 0)
		for puzzle_index in puzzles.size():
			var puzzle_progress := get_puzzle_progress(adventure_id, block_index, puzzle_index)
			if not bool(puzzle_progress.get("solved", false)):
				return _make_puzzle_ref(adventure_id, block_index, puzzle_index)
	return fallback

func get_puzzle_id(adventure_id: String, block_index: int, puzzle_index: int) -> String:
	var puzzle := _get_puzzle_ref(adventure_id, block_index, puzzle_index)
	if puzzle.is_empty():
		return ""
	return _puzzle_id(adventure_id, block_index, puzzle_index, puzzle)

func _load_adventure_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("Could not open adventure: %s" % path)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Adventure JSON is not a dictionary: %s" % path)
		return

	var adventure := _normalize_adventure(parsed, path)
	if adventure.is_empty():
		return
	var adventure_id := str(_adventure_meta(adventure).get("id", ""))
	if _adventure_by_id.has(adventure_id):
		push_warning("Duplicate adventure id skipped: %s" % adventure_id)
		return
	_adventures.append(adventure)
	_adventure_by_id[adventure_id] = adventure

func _normalize_adventure(raw: Dictionary, path: String) -> Dictionary:
	var schema_version := int(raw.get("schema_version", 0))
	if schema_version < SCHEMA_VERSION_MIN or schema_version > SCHEMA_VERSION_MAX:
		push_warning("Unsupported adventure schema in %s: %s" % [path, schema_version])
		return {}

	var metadata := _as_dictionary(raw.get("adventure", {})).duplicate(true)
	var adventure_id := str(metadata.get("id", "")).strip_edges()
	if adventure_id == "":
		push_warning("Adventure missing id: %s" % path)
		return {}
	metadata["id"] = adventure_id
	metadata["title"] = str(metadata.get("title", adventure_id)).strip_edges()
	if str(metadata["title"]) == "":
		metadata["title"] = adventure_id
	metadata["default_locale"] = str(metadata.get("default_locale", "en")).strip_edges()
	if str(metadata["default_locale"]) == "":
		metadata["default_locale"] = "en"

	var blocks := []
	for raw_block in _as_array(raw.get("blocks", [])):
		var block := _normalize_block(_as_dictionary(raw_block), adventure_id, blocks.size())
		if not block.is_empty():
			blocks.append(block)
	if blocks.is_empty():
		push_warning("Adventure has no playable blocks: %s" % path)
		return {}

	var normalized := raw.duplicate(true)
	normalized["adventure"] = metadata
	normalized["blocks"] = blocks
	normalized["_source_path"] = path
	return normalized

func _normalize_block(raw: Dictionary, adventure_id: String, block_index: int) -> Dictionary:
	var puzzles := []
	for raw_puzzle in _as_array(raw.get("puzzles", [])):
		var puzzle := _normalize_puzzle(_as_dictionary(raw_puzzle), adventure_id, block_index, puzzles.size())
		if not puzzle.is_empty():
			puzzles.append(puzzle)
	if puzzles.is_empty():
		return {}
	var block := raw.duplicate(true)
	block["id"] = str(block.get("id", "block_%02d" % (block_index + 1))).strip_edges()
	block["title"] = str(block.get("title", "Block %d" % (block_index + 1))).strip_edges()
	block["introduces"] = str(block.get("introduces", "")).strip_edges()
	block["puzzles"] = puzzles
	if typeof(block.get("unlock_next", {})) != TYPE_DICTIONARY:
		block["unlock_next"] = {}
	return block

func _normalize_puzzle(raw: Dictionary, adventure_id: String, block_index: int, puzzle_index: int) -> Dictionary:
	var board_code := str(raw.get("board_code", "")).strip_edges()
	if board_code == "":
		return {}
	var puzzle := raw.duplicate(true)
	puzzle["id"] = _puzzle_id(adventure_id, block_index, puzzle_index, puzzle)
	puzzle["board_code"] = board_code
	puzzle["title"] = str(puzzle.get("title", "Puzzle %d" % (puzzle_index + 1))).strip_edges()
	puzzle["introduces"] = str(puzzle.get("introduces", "")).strip_edges()
	if typeof(puzzle.get("rules", {})) != TYPE_DICTIONARY:
		puzzle["rules"] = {}
	if typeof(puzzle.get("dialog", {})) != TYPE_DICTIONARY:
		puzzle["dialog"] = {}
	return puzzle

func _load_progress() -> void:
	_progress = PROGRESS_DEFAULT.duplicate(true)
	var file := FileAccess.open(PROGRESS_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	if typeof(parsed.get("adventures", {})) != TYPE_DICTIONARY:
		return
	_progress = parsed
	if not _progress.has("version"):
		_progress["version"] = 1
	_upgrade_legacy_progress()

func _save_progress() -> void:
	var file := FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
	if not file:
		push_warning("Could not save adventure progress.")
		return
	file.store_string(JSON.stringify(_progress, "\t"))

func _upgrade_legacy_progress() -> void:
	var changed := int(_progress.get("version", 1)) < PROGRESS_SCHEMA_VERSION
	var all_progress := _all_progress_ref(false)
	for adventure_id in all_progress.keys():
		var adventure_progress := _as_dictionary(all_progress[adventure_id])
		var old_puzzles := _as_dictionary(adventure_progress.get("puzzles", {}))
		if old_puzzles.is_empty():
			continue
		var next_puzzles := old_puzzles.duplicate(true)
		var blocks := _adventure_blocks(_get_adventure_ref(str(adventure_id)))
		for block_index in blocks.size():
			var block := _as_dictionary(blocks[block_index])
			var block_puzzles := _block_puzzles(block)
			for puzzle_index in block_puzzles.size():
				var puzzle := _as_dictionary(block_puzzles[puzzle_index])
				var progress_key := _puzzle_progress_key(str(adventure_id), block_index, puzzle_index, puzzle)
				if progress_key == "" or next_puzzles.has(progress_key):
					continue
				for legacy_key in _legacy_puzzle_progress_keys(str(adventure_id), block_index, puzzle_index, puzzle):
					if legacy_key == progress_key or not old_puzzles.has(legacy_key):
						continue
					var legacy_progress := _as_dictionary(old_puzzles[legacy_key])
					if legacy_progress.is_empty():
						continue
					next_puzzles[progress_key] = legacy_progress.duplicate(true)
					_stamp_puzzle_progress_identity(next_puzzles[progress_key], str(adventure_id), block_index, puzzle_index, puzzle)
					changed = true
					break
		adventure_progress["puzzles"] = next_puzzles
		all_progress[adventure_id] = adventure_progress
	if int(_progress.get("version", 1)) != PROGRESS_SCHEMA_VERSION:
		_progress["version"] = PROGRESS_SCHEMA_VERSION
		changed = true
	if changed:
		_save_progress()

func _localized_adventure(adventure: Dictionary) -> Dictionary:
	if adventure.is_empty():
		return {}
	var localized := adventure.duplicate(true)
	var metadata := _adventure_meta(localized)
	_localize_text_field(localized, metadata, "title")
	_localize_text_field(localized, metadata, "description")

	var blocks := _adventure_blocks(localized)
	for block_index in blocks.size():
		if typeof(blocks[block_index]) == TYPE_DICTIONARY:
			var block: Dictionary = blocks[block_index]
			_localize_block_in_place(localized, block)
	return localized

func _localized_block(adventure: Dictionary, block: Dictionary) -> Dictionary:
	if adventure.is_empty() or block.is_empty():
		return {}
	var localized := block.duplicate(true)
	_localize_block_in_place(adventure, localized)
	return localized

func _localized_puzzle(adventure: Dictionary, puzzle: Dictionary) -> Dictionary:
	if adventure.is_empty() or puzzle.is_empty():
		return {}
	var localized := puzzle.duplicate(true)
	_localize_puzzle_in_place(adventure, localized)
	return localized

func _localize_block_in_place(adventure: Dictionary, block: Dictionary) -> void:
	_localize_text_field(adventure, block, "title")
	_localize_text_field(adventure, block, "introduces")
	var puzzles := _block_puzzles(block)
	for puzzle_index in puzzles.size():
		if typeof(puzzles[puzzle_index]) == TYPE_DICTIONARY:
			var puzzle: Dictionary = puzzles[puzzle_index]
			_localize_puzzle_in_place(adventure, puzzle)

func _localize_puzzle_in_place(adventure: Dictionary, puzzle: Dictionary) -> void:
	_localize_text_field(adventure, puzzle, "title")
	_localize_text_field(adventure, puzzle, "introduces")
	var dialog := _as_dictionary(puzzle.get("dialog", {}))
	for kind in ["intro", "outro"]:
		var lines := _as_array(dialog.get(kind, []))
		for line_index in lines.size():
			if typeof(lines[line_index]) == TYPE_DICTIONARY:
				var line: Dictionary = lines[line_index]
				_localize_text_field(adventure, line, "speaker")
				_localize_text_field(adventure, line, "text")

func _localize_text_field(adventure: Dictionary, container: Dictionary, field: String, fallback: String = "") -> void:
	container[field] = _localized_text_value(adventure, container, field, fallback)

func _localized_text_value(adventure: Dictionary, container: Dictionary, field: String, fallback: String = "") -> String:
	if container.is_empty():
		return fallback
	var resolved_fallback := str(container.get(field, fallback))
	if resolved_fallback == "" and fallback != "":
		resolved_fallback = fallback
	var key := str(container.get("%s_key" % field, "")).strip_edges()
	return _resolve_i18n_text(adventure, key, resolved_fallback)

func _resolve_i18n_text(adventure: Dictionary, key: String, fallback: String) -> String:
	var clean_key := key.strip_edges()
	if clean_key == "":
		return fallback
	var i18n := _as_dictionary(adventure.get("i18n", {}))
	if i18n.is_empty():
		return fallback
	for locale in _locale_candidates(adventure):
		var table := _as_dictionary(i18n.get(locale, {}))
		if table.has(clean_key):
			return str(table[clean_key])
	return fallback

func _locale_candidates(adventure: Dictionary) -> Array:
	var candidates := []
	_append_locale_family(candidates, str(TranslationServer.get_locale()))
	_append_locale_family(candidates, str(_adventure_meta(adventure).get("default_locale", "en")))
	_append_locale_family(candidates, "en")
	return candidates

func _append_locale_family(candidates: Array, locale: String) -> void:
	var clean_locale := locale.strip_edges()
	if clean_locale == "":
		return
	_append_unique_locale(candidates, clean_locale)
	var language_parts := clean_locale.replace("-", "_").split("_", false)
	if not language_parts.is_empty():
		_append_unique_locale(candidates, str(language_parts[0]))

func _append_unique_locale(candidates: Array, locale: String) -> void:
	var clean_locale := locale.strip_edges()
	if clean_locale != "" and not candidates.has(clean_locale):
		candidates.append(clean_locale)

func _get_adventure_ref(adventure_id: String) -> Dictionary:
	if _adventure_by_id.has(adventure_id) and typeof(_adventure_by_id[adventure_id]) == TYPE_DICTIONARY:
		return _adventure_by_id[adventure_id]
	return {}

func _get_block_ref(adventure_id: String, block_index: int) -> Dictionary:
	var blocks := _adventure_blocks(_get_adventure_ref(adventure_id))
	if block_index < 0 or block_index >= blocks.size() or typeof(blocks[block_index]) != TYPE_DICTIONARY:
		return {}
	return blocks[block_index]

func _get_puzzle_ref(adventure_id: String, block_index: int, puzzle_index: int) -> Dictionary:
	var puzzles := _block_puzzles(_get_block_ref(adventure_id, block_index))
	if puzzle_index < 0 or puzzle_index >= puzzles.size() or typeof(puzzles[puzzle_index]) != TYPE_DICTIONARY:
		return {}
	return puzzles[puzzle_index]

func _get_puzzle_progress_ref(adventure_id: String, block_index: int, puzzle_index: int, create: bool) -> Dictionary:
	var puzzle := _get_puzzle_ref(adventure_id, block_index, puzzle_index)
	if puzzle.is_empty():
		return {}
	var progress_key := _puzzle_progress_key(adventure_id, block_index, puzzle_index, puzzle)
	if progress_key == "":
		return {}
	var adventure_progress := _get_adventure_progress_ref(adventure_id, create)
	if adventure_progress.is_empty() and not create:
		return {}
	if typeof(adventure_progress.get("puzzles", {})) != TYPE_DICTIONARY:
		if not create:
			return {}
		adventure_progress["puzzles"] = {}
	var puzzles: Dictionary = adventure_progress["puzzles"]
	if not puzzles.has(progress_key):
		var migrated_progress := _find_legacy_puzzle_progress(puzzles, adventure_id, block_index, puzzle_index, puzzle)
		if not migrated_progress.is_empty():
			puzzles[progress_key] = migrated_progress
		elif not create:
			return {}
		else:
			puzzles[progress_key] = _make_empty_puzzle_progress(adventure_id, block_index, puzzle_index, puzzle)
	if typeof(puzzles[progress_key]) != TYPE_DICTIONARY:
		if not create:
			return {}
		puzzles[progress_key] = _make_empty_puzzle_progress(adventure_id, block_index, puzzle_index, puzzle)
	if create:
		_stamp_puzzle_progress_identity(puzzles[progress_key], adventure_id, block_index, puzzle_index, puzzle)
	return puzzles[progress_key]

func _puzzle_progress_key(adventure_id: String, block_index: int, puzzle_index: int, puzzle: Dictionary) -> String:
	var board_code := str(puzzle.get("board_code", "")).strip_edges()
	if board_code != "":
		return "board_code:%s" % board_code
	return _puzzle_id(adventure_id, block_index, puzzle_index, puzzle)

func _legacy_puzzle_progress_keys(adventure_id: String, block_index: int, puzzle_index: int, puzzle: Dictionary) -> Array:
	var keys := []
	var puzzle_id := _puzzle_id(adventure_id, block_index, puzzle_index, puzzle)
	if puzzle_id != "":
		keys.append(puzzle_id)
	keys.append("%d:%d" % [block_index, puzzle_index])
	keys.append("%d:%d" % [block_index + 1, puzzle_index + 1])
	return keys

func _find_legacy_puzzle_progress(puzzles: Dictionary, adventure_id: String, block_index: int, puzzle_index: int, puzzle: Dictionary) -> Dictionary:
	for legacy_key in _legacy_puzzle_progress_keys(adventure_id, block_index, puzzle_index, puzzle):
		if not puzzles.has(legacy_key):
			continue
		var legacy_progress := _as_dictionary(puzzles[legacy_key])
		if not legacy_progress.is_empty():
			var migrated := legacy_progress.duplicate(true)
			_stamp_puzzle_progress_identity(migrated, adventure_id, block_index, puzzle_index, puzzle)
			return migrated
	return {}

func _make_empty_puzzle_progress(adventure_id: String, block_index: int, puzzle_index: int, puzzle: Dictionary) -> Dictionary:
	var progress := {}
	_stamp_puzzle_progress_identity(progress, adventure_id, block_index, puzzle_index, puzzle)
	return progress

func _stamp_puzzle_progress_identity(progress: Dictionary, adventure_id: String, block_index: int, puzzle_index: int, puzzle: Dictionary) -> void:
	progress["progress_key"] = _puzzle_progress_key(adventure_id, block_index, puzzle_index, puzzle)
	progress["board_code"] = str(puzzle.get("board_code", "")).strip_edges()
	progress["puzzle_id"] = _puzzle_id(adventure_id, block_index, puzzle_index, puzzle)
	progress["block_index"] = block_index
	progress["puzzle_index"] = puzzle_index

func _get_adventure_progress_ref(adventure_id: String, create: bool) -> Dictionary:
	var all_progress := _all_progress_ref(create)
	if all_progress.is_empty() and not create:
		return {}
	if not all_progress.has(adventure_id):
		if not create:
			return {}
		all_progress[adventure_id] = {"puzzles": {}}
	if typeof(all_progress[adventure_id]) != TYPE_DICTIONARY:
		if not create:
			return {}
		all_progress[adventure_id] = {"puzzles": {}}
	var adventure_progress: Dictionary = all_progress[adventure_id]
	if typeof(adventure_progress.get("puzzles", {})) != TYPE_DICTIONARY:
		if not create:
			return {}
		adventure_progress["puzzles"] = {}
	return adventure_progress

func _all_progress_ref(create: bool) -> Dictionary:
	if typeof(_progress.get("adventures", {})) != TYPE_DICTIONARY:
		if not create:
			return {}
		_progress["adventures"] = {}
	return _progress["adventures"]

func _current_scoring() -> Dictionary:
	var puzzle := _get_puzzle_ref(get_current_adventure_id(), get_current_block_index(), get_current_puzzle_index())
	var rules := _as_dictionary(puzzle.get("rules", {}))
	return _as_dictionary(rules.get("scoring", {}))

func _adventure_meta(adventure: Dictionary) -> Dictionary:
	return _as_dictionary(adventure.get("adventure", {}))

func _adventure_blocks(adventure: Dictionary) -> Array:
	return _as_array(adventure.get("blocks", []))

func _block_puzzles(block: Dictionary) -> Array:
	return _as_array(block.get("puzzles", []))

func _puzzle_id(adventure_id: String, block_index: int, puzzle_index: int, puzzle: Dictionary) -> String:
	var explicit_id := str(puzzle.get("id", "")).strip_edges()
	if explicit_id != "":
		return explicit_id
	return "%s-b%02d-p%02d" % [adventure_id, block_index + 1, puzzle_index + 1]

func _make_puzzle_ref(adventure_id: String, block_index: int, puzzle_index: int) -> Dictionary:
	return {
		"adventure_id": adventure_id,
		"block_index": block_index,
		"puzzle_index": puzzle_index,
		"puzzle_id": get_puzzle_id(adventure_id, block_index, puzzle_index),
	}

func _clear_invalid_current() -> void:
	if _current.is_empty():
		return
	if _get_puzzle_ref(get_current_adventure_id(), get_current_block_index(), get_current_puzzle_index()).is_empty():
		_current.clear()

func _as_dictionary(value) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}

func _as_array(value) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
