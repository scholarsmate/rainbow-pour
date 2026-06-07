extends RefCounted

const PREFIX := "RP1"
const BASE85_ALPHABET := "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-:+=^!/*?&<>()[]{}@%$#"
const TRAIT_NONE := ""
const TRAIT_PRISMATIC := "prismatic"
const TRAIT_TINTED := "tinted"
const TRAIT_CRACKED := "cracked"
const COUNT_BITS := 4
const MAX_COUNT := (1 << COUNT_BITS) - 1
const MAX_TOTAL_BEAKERS := 16
const GOAL_BITS := 16

class BitWriter:
	var bytes := PackedByteArray()
	var current_byte := 0
	var bits_filled := 0

	func write_bits(value: int, count: int) -> void:
		if count <= 0:
			return
		for bit_idx in range(count - 1, -1, -1):
			current_byte = (current_byte << 1) | ((value >> bit_idx) & 1)
			bits_filled += 1
			if bits_filled == 8:
				bytes.append(current_byte)
				current_byte = 0
				bits_filled = 0

	func finish() -> PackedByteArray:
		if bits_filled > 0:
			current_byte = current_byte << (8 - bits_filled)
			bytes.append(current_byte)
			current_byte = 0
			bits_filled = 0
		return bytes

class BitReader:
	var bytes := PackedByteArray()
	var byte_idx := 0
	var bit_idx := 0
	var failed := false

	func _init(source: PackedByteArray) -> void:
		bytes = source

	func read_bits(count: int) -> int:
		if count <= 0:
			return 0
		var value := 0
		for idx in count:
			if byte_idx >= bytes.size():
				failed = true
				return 0
			var bit := (int(bytes[byte_idx]) >> (7 - bit_idx)) & 1
			value = (value << 1) | bit
			bit_idx += 1
			if bit_idx == 8:
				bit_idx = 0
				byte_idx += 1
		return value

static func encode(capacity: int, filled_count: int, empty_count: int, beakers: Array, beaker_traits: Array, cached_goal: int = -1) -> String:
	var writer := BitWriter.new()
	var beaker_count := filled_count + empty_count
	if capacity <= 0 or capacity > 8:
		return ""
	if filled_count <= 0 or filled_count > MAX_COUNT or empty_count <= 0 or empty_count > MAX_COUNT:
		return ""
	if beaker_count <= 0 or beaker_count > MAX_TOTAL_BEAKERS:
		return ""
	var color_bits := _bits_needed(filled_count - 1)
	var length_bits := _bits_needed(capacity)
	var has_goal := cached_goal >= 0 and cached_goal < (1 << GOAL_BITS)

	writer.write_bits(capacity - 1, 3)
	writer.write_bits(filled_count, COUNT_BITS)
	writer.write_bits(empty_count, COUNT_BITS)
	writer.write_bits(1 if has_goal else 0, 1)
	if has_goal:
		writer.write_bits(cached_goal, GOAL_BITS)

	for beaker_idx in beaker_count:
		var tube: Array = beakers[beaker_idx] if beaker_idx < beakers.size() else []
		writer.write_bits(tube.size(), length_bits)
		for color in tube:
			writer.write_bits(int(color), color_bits)

	for beaker_idx in beaker_count:
		var trait_data := _get_trait_data(beaker_traits, beaker_idx)
		match str(trait_data.get("type", TRAIT_NONE)):
			TRAIT_PRISMATIC:
				writer.write_bits(1, 2)
			TRAIT_TINTED:
				writer.write_bits(2, 2)
				writer.write_bits(int(trait_data.get("color", 0)), color_bits)
			TRAIT_CRACKED:
				writer.write_bits(3, 2)
			_:
				writer.write_bits(0, 2)

	var payload := _encode_base85(writer.finish())
	var check_char := BASE85_ALPHABET.substr(_luhn_check_value(payload), 1)
	return "%s%s%s" % [PREFIX, payload, check_char]

static func decode(raw_code: String) -> Dictionary:
	var code := raw_code.strip_edges()
	if code.begins_with(PREFIX):
		return _decode_v1(code)
	return {"ok": false}

static func _decode_v1(code: String) -> Dictionary:
	if code.length() <= PREFIX.length() + 1:
		return {"ok": false}
	var payload_with_check := code.substr(PREFIX.length())
	var payload := payload_with_check.substr(0, payload_with_check.length() - 1)
	var check_char := payload_with_check.substr(payload_with_check.length() - 1, 1)
	if BASE85_ALPHABET.find(check_char) != _luhn_check_value(payload):
		return {"ok": false}

	var bytes := _decode_base85(payload)
	if bytes.is_empty():
		return {"ok": false}
	var reader := BitReader.new(bytes)

	var capacity := reader.read_bits(3) + 1
	var filled_count := reader.read_bits(COUNT_BITS)
	var empty_count := reader.read_bits(COUNT_BITS)
	var has_goal := reader.read_bits(1) == 1
	var cached_goal := -1
	if has_goal:
		cached_goal = reader.read_bits(GOAL_BITS)
	var beaker_count := filled_count + empty_count
	if reader.failed or capacity <= 0 or filled_count <= 0 or empty_count <= 0:
		return {"ok": false}
	if filled_count > MAX_COUNT or empty_count > MAX_COUNT or beaker_count > MAX_TOTAL_BEAKERS:
		return {"ok": false}

	var color_bits := _bits_needed(filled_count - 1)
	var length_bits := _bits_needed(capacity)
	var beakers := []
	for beaker_idx in beaker_count:
		var tube_len := reader.read_bits(length_bits)
		if reader.failed or tube_len > capacity:
			return {"ok": false}
		var tube := []
		for segment_idx in tube_len:
			var color_idx := reader.read_bits(color_bits)
			if reader.failed or color_idx < 0 or color_idx >= filled_count:
				return {"ok": false}
			tube.append(color_idx)
		beakers.append(tube)

	var traits := []
	for beaker_idx in beaker_count:
		var trait_type := reader.read_bits(2)
		if reader.failed:
			return {"ok": false}
		if trait_type == 1:
			traits.append({"type": TRAIT_PRISMATIC, "color": -1})
		elif trait_type == 2:
			var color_idx := reader.read_bits(color_bits)
			if reader.failed or color_idx < 0 or color_idx >= filled_count:
				return {"ok": false}
			traits.append({"type": TRAIT_TINTED, "color": color_idx})
		elif trait_type == 3:
			traits.append({"type": TRAIT_CRACKED, "color": -1})
		elif trait_type == 0:
			traits.append({"type": TRAIT_NONE, "color": -1})

	return {
		"ok": true,
		"version": 1,
		"capacity": capacity,
		"filled_count": filled_count,
		"empty_count": empty_count,
		"beakers": beakers,
		"traits": traits,
		"cached_goal": cached_goal,
	}

static func _get_trait_data(traits: Array, idx: int) -> Dictionary:
	if idx < 0 or idx >= traits.size() or typeof(traits[idx]) != TYPE_DICTIONARY:
		return {"type": TRAIT_NONE, "color": -1}
	return traits[idx]

static func _bits_needed(max_value: int) -> int:
	var bits := 0
	var value := maxi(0, max_value)
	while (1 << bits) <= value:
		bits += 1
	return bits

static func _encode_base85(bytes: PackedByteArray) -> String:
	var encoded := ""
	var idx := 0
	while idx < bytes.size():
		var group_len := mini(4, bytes.size() - idx)
		var value := 0
		for byte_offset in 4:
			value = value << 8
			if byte_offset < group_len:
				value |= int(bytes[idx + byte_offset])
		var chars := []
		chars.resize(5)
		for char_idx in range(4, -1, -1):
			chars[char_idx] = BASE85_ALPHABET.substr(value % 85, 1)
			value = int(value / 85)
		for char_idx in group_len + 1:
			encoded += str(chars[char_idx])
		idx += group_len
	return encoded

static func _decode_base85(text: String) -> PackedByteArray:
	var bytes := PackedByteArray()
	var idx := 0
	while idx < text.length():
		var group_len := mini(5, text.length() - idx)
		if group_len <= 1:
			return PackedByteArray()
		var value := 0
		for char_offset in group_len:
			var digit := BASE85_ALPHABET.find(text.substr(idx + char_offset, 1))
			if digit < 0:
				return PackedByteArray()
			value = value * 85 + digit
		for pad_idx in range(group_len, 5):
			value = value * 85 + 84
		var group := PackedByteArray()
		group.resize(4)
		for byte_idx in range(3, -1, -1):
			group[byte_idx] = value & 0xff
			value = value >> 8
		for byte_idx in group_len - 1:
			bytes.append(group[byte_idx])
		idx += group_len
	return bytes

static func _luhn_check_value(text: String) -> int:
	var factor := 2
	var total := 0
	var base := BASE85_ALPHABET.length()
	for idx in range(text.length() - 1, -1, -1):
		var code_point := BASE85_ALPHABET.find(text.substr(idx, 1))
		if code_point < 0:
			return -1
		var addend := factor * code_point
		factor = 1 if factor == 2 else 2
		addend = int(addend / base) + (addend % base)
		total += addend
	return (base - (total % base)) % base
